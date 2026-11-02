import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:protobuf/protobuf.dart';
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final input = jsonDecode(
    await stdin.transform(utf8.decoder).join(),
  ) as Map<String, dynamic>;
  final uri = Uri.parse(input['endpoint'] as String),
      root = input['root'] as String;
  final clients = <ApiClient>[], secrets = <String>[];
  Future<ApiClient> login(int index) async {
    final client = ApiClient(
      endpoint: uri.toString(),
      readAttempts: 1,
      channelFactory: (_) => grpc.ClientChannel(
        uri.host,
        port: uri.port,
        options: grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.secure(
            certificates: File(input['ca'] as String).readAsBytesSync(),
          ),
        ),
      ),
    );
    clients.add(client);
    final account = index == 2 ? 1 : 0;
    final session = await client.login(
      endpoint: uri.toString(),
      name: 'Device$index',
      address: ['2:1/2.2', '2:1/2.3'][account],
      password: (input['passwords'] as List)[account] as String,
    );
    secrets.add(session.sessionSecret);
    return client;
  }

  Future<String> database() async {
    final result = await Process.run('python3', [
      '-c',
      'import sqlite3,sys; print("\\n".join(sqlite3.connect(sys.argv[1]).iterdump()))',
      '$root/metadata.db',
    ]);
    check(result.exitCode == 0, 'SQLite snapshot');
    return result.stdout as String;
  }

  Future<List<int>> web(String method, GeneratedMessage payload) async {
    final security = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(input['ca'] as String);
    final http = HttpClient(context: security);
    try {
      final request = await http.postUrl(
        Uri.parse('${input['web']}/ffido.v1.Ffido/$method'),
      );
      for (final e in {
        'content-type': 'application/grpc-web+proto',
        'x-grpc-web': '1',
        'origin': 'https://localhost',
        'authorization': 'Bearer ${secrets.first}',
      }.entries) {
        request.headers.set(e.key, e.value);
      }
      final bytes = payload.writeToBuffer(),
          prefix = ByteData(5)..setUint32(1, bytes.length);
      request.add(prefix.buffer.asUint8List());
      request.add(bytes);
      final response = await request.close();
      final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
      check(
        response.statusCode == 200 && body.length >= 5 && body.first == 0,
        'gRPC-Web data frame',
      );
      final length = ByteData.sublistView(Uint8List.fromList(body))
          .getUint32(1);
      check(
        ascii.decode(body.sublist(10 + length)).contains('grpc-status:0'),
        'gRPC-Web trailer',
      );
      return body.sublist(5, 5 + length);
    } finally {
      http.close(force: true);
    }
  }

  try {
    final first = await login(0),
        second = await login(1),
        alien = await login(2);
    final fixtures = input['fixtures'] as List;
    wire.MessageReference ref(String area, int number) {
      final f = fixtures.singleWhere(
        (f) => f['conference'] == area && f['number'] == number,
      );
      return wire.MessageReference(
        conferenceId: area,
        messageId: f['id'] as String,
      );
    }

    final one = ref('SOURCE', 1),
        two = ref('SOURCE', 2),
        other = ref('OTHER', 1);
    Future<wire.ListMessagesResponse> list(ApiClient client) =>
        client.listMessages(
          wire.ListMessagesRequest(
            conferenceId: 'SOURCE',
            page: wire.PageRequest(limit: 100),
            sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
            respectPersonalFilters: true,
          ),
        );
    if (input['restart'] == true) {
      final state = await second.getPersonalMessageFilters();
      check(
        state.revision == Int64.ONE && state.rules.length == 2,
        'Rules survive server restart',
      );
      final rows = await list(second);
      check(
        rows.messages[1].isRead && !rows.messages[0].isRead,
        'Read marks persist independently of collapsed state',
      );
      check(
        (await alien.getPersonalMessageFilters()).rules.isEmpty,
        'Profile isolation after restart',
      );
      stdout.writeln(
        'PASS restart: synchronized rules/revision and personal read state persist',
      );
      return;
    }
    final initial = await second.getPersonalMessageFilters();
    check(initial.revision == Int64.ZERO, 'Empty settings');
    final save = wire.ReplacePersonalMessageFiltersRequest(
      expectedRevision: Int64.ZERO,
      operationId: 'acceptance-save',
      rules: [
        wire.PersonalMessageFilter(
          ruleId: '00000000-0000-4000-8000-000000000001',
          enabled: true,
          scope: wire
              .PersonalMessageFilterScope
              .PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS,
          authorContains: 'ИВАН',
        ),
        wire.PersonalMessageFilter(
          ruleId: '00000000-0000-4000-8000-000000000002',
          enabled: true,
          scope: wire
              .PersonalMessageFilterScope
              .PERSONAL_MESSAGE_FILTER_SCOPE_CONFERENCE,
          conferenceId: 'SOURCE',
          subjectContains: 'ШУМ',
        ),
      ],
    );
    await first.replacePersonalMessageFilters(
      save,
    ); // Confirmation deliberately discarded.
    check(
      (await second.replacePersonalMessageFilters(save)).revision == Int64.ONE,
      'Same operation after lost confirmation',
    );
    try {
      await second.replacePersonalMessageFilters(
        save.deepCopy()..operationId = 'conflicting-device',
      );
      throw StateError('CAS overwrite accepted');
    } on ApiException catch (e) {
      check(e.statusCode == 10, 'ABORTED CAS conflict');
    }
    final settings = await second.getPersonalMessageFilters();
    check(
      settings.rules.length == 2 && settings.revision == Int64.ONE,
      'Second device synchronization',
    );
    check(
      (await alien.getPersonalMessageFilters()).rules.isEmpty,
      'Other profile not affected',
    );
    final sqlBefore = await database();
    final jam = <String, List<int>>{};
    for (final file in Directory(
      root,
    ).listSync(recursive: true).whereType<File>()) {
      if (['.jhr', '.jdt', '.jdx'].any(file.path.endsWith)) {
        jam[file.path] = file.readAsBytesSync();
      }
    }
    final page = await list(second);
    check(
      page.total.toInt() == 3 && page.messages.length == 3,
      'Pagination unchanged',
    );
    check(
      page.messages[0].personalCollapse.matchedRuleIds.length == 2 &&
          page.messages[1].personalCollapse.matchedRuleIds.length == 1 &&
          page.messages[2].personalCollapse.matchedRuleIds.isEmpty,
      'Global and per-echo rules',
    );
    check(
      page.messages.take(2).every((m) => !m.isRead && m.bodyPreview.isEmpty),
      'No preview/read on collapsed rows',
    );
    for (final reference in [one, two, other]) {
      final request = wire.GetMessagePresentationRequest(message: reference);
      final native = await first.getMessagePresentation(request);
      check(
        native.hasCollapsed() && !native.collapsed.isRead,
        'Header-only presentation across CHRS/default/override',
      );
      final viaWeb = wire.MessagePresentation.fromBuffer(
        await web('GetMessagePresentation', request),
      );
      check(
        base64Encode(native.writeToBuffer()) ==
            base64Encode(viaWeb.writeToBuffer()),
        'Byte-exact gRPC-Web presentation',
      );
    }
    final webRules = wire.PersonalMessageFilterSet.fromBuffer(
      await web('GetPersonalMessageFilters', Empty()),
    );
    check(
      webRules.revision == settings.revision && webRules.rules.length == 2,
      'gRPC-Web synchronized rules',
    );
    final find = wire.FindMessageRequest(
      conferenceId: 'SOURCE',
      query: 'секрет',
      scope: wire.MessageSearchScope.MESSAGE_SEARCH_HEADER_AND_BODY,
      sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
      includeStart: true,
      respectPersonalFilters: true,
    );
    final found = await second.findMessage(find);
    check(
      found.message.id == one.messageId &&
          found.message.body.isEmpty &&
          found.matches.isEmpty,
      'Collapsed search has no body/read',
    );
    check(
      await database() == sqlBefore,
      'Complete SQLite state unchanged before explicit Show',
    );
    final revealed = await second.getMessagePresentation(
      wire.GetMessagePresentationRequest(
        message: two,
        reveal: true,
        searchQuery: 'секрет',
        searchScope: wire.MessageSearchScope.MESSAGE_SEARCH_HEADER_AND_BODY,
      ),
    );
    check(
      revealed.hasVisible() &&
          revealed.visible.isRead &&
          revealed.visible.body.startsWith('😀 '),
      'Explicit reveal exact current text',
    );
    check(
      revealed.matches.single.startUtf16 == 3 &&
          revealed.matches.single.lengthUtf16 == 6,
      'UTF-16 ranges recomputed on reveal',
    );
    check(
      await database() != sqlBefore,
      'Explicit reveal records personal read/history',
    );
    check(
      (await first.getMessagePresentation(
        wire.GetMessagePresentationRequest(message: two),
      )).collapsed.isRead,
      'Other device sees read state without bypassing collapse',
    );
    final areas = (await first.listConferences(
      wire.ListConferencesRequest(
        page: wire.PageRequest(limit: 100),
        sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
      ),
    )).conferences;
    final mailbox = areas.singleWhere((a) => a.personalMailbox).id;
    final mail = fixtures.singleWhere(
      (f) => (f['conference'] as String).startsWith('@ffido/point/'),
    );
    final mailRef = wire.MessageReference(
      conferenceId: mailbox,
      messageId: mail['id'] as String,
    );
    check(
      (await first.getMessagePresentation(
        wire.GetMessagePresentationRequest(message: mailRef),
      )).hasVisible(),
      'Netmail excluded',
    );
    try {
      await alien.getMessagePresentation(
        wire.GetMessagePresentationRequest(message: mailRef),
      );
      throw StateError('Foreign mailbox allowed');
    } on ApiException catch (e) {
      check(e.isAccessDenied, 'Foreign mailbox denied');
    }
    final legacy = await first.getMessage(one);
    check(
      legacy.body.isNotEmpty && legacy.isRead,
      'Legacy GetMessage unchanged',
    );
    // Keep first source unread again to verify persistence separately after restart.
    await first.markUnread(one);
    for (final entry in jam.entries) {
      check(
        base64Encode(File(entry.key).readAsBytesSync()) ==
            base64Encode(entry.value),
        'JAM modified by personal filters',
      );
    }
    stdout.writeln(
      'PASS native TLS + Envoy gRPC-Web: two devices, CAS/replay, global/local rules, CP866/UTF-8/override, collapsed search, explicit reveal, profile/mailbox isolation; JAM unchanged and full SQLite dump unchanged before Show',
    );
  } finally {
    for (final client in clients) {
      await client.dispose();
    }
  }
}
