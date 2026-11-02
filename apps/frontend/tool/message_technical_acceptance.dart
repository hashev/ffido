import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart' as grpc;
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/utils/message_technical_report.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final input = jsonDecode(
    await stdin.transform(utf8.decoder).join(),
  ) as Map<String, dynamic>;
  final uri = Uri.parse(input['endpoint'] as String),
      root = input['root'] as String;
  final clients = <ApiClient>[];
  final secrets = <String>[];
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
    final session = await client.login(
      endpoint: uri.toString(),
      name: 'Test$index',
      address: ['2:1/2.2', '2:1/2.3'][index],
      password: (input['passwords'] as List)[index] as String,
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

  try {
    final client = await login(0), stranger = await login(1);
    final areas = (await client.listConferences(
      wire.ListConferencesRequest(
        page: wire.PageRequest(limit: 100),
        sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
      ),
    )).conferences;
    final own = areas.singleWhere((a) => a.personalMailbox).id;
    final fixtures = input['fixtures'] as List;
    final references = [
      for (final fixture in fixtures)
        wire.MessageReference(
          conferenceId:
              (fixture['conference'] as String).startsWith('@ffido/point/')
              ? own
              : fixture['conference'] as String,
          messageId: fixture['id'] as String,
        ),
    ];
    final sqliteBefore = await database();
    final jam = <String, List<int>>{};
    for (final file in Directory(
      root,
    ).listSync(recursive: true).whereType<File>()) {
      if (['.jhr', '.jdt', '.jdx'].any((ext) => file.path.endsWith(ext))) {
        jam[file.path] = file.readAsBytesSync();
      }
    }
    final repo = MessageRepository(client);
    check(references.length == 7, 'All isolated fixtures must be listed');
    for (final reference in references) {
      final number = int.parse(reference.messageId.split('#').last);
      final fixture = fixtures.singleWhere(
        (f) =>
            f['number'] == number &&
            (f['conference'] == reference.conferenceId ||
                reference.conferenceId == own &&
                    (f['conference'] as String).startsWith('@ffido/point/')),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        final data = await repo.getTechnicalData(
          reference.conferenceId,
          reference.messageId,
        );
        check(
          data.attributes == 0x04000008 && data.attributes2 == 0xffffffff,
          'Unsigned attributes',
        );
        final expected = fixture['fields'] as List;
        check(data.subfields.length == expected.length, 'Field count');
        for (var i = 0; i < expected.length; i++) {
          final f = data.subfields[i], e = expected[i] as List;
          check(
            f.lowId == e[0] &&
                f.highId == e[1] &&
                jsonEncode(f.bytes) == jsonEncode(e[2]),
            'Wire bytes/order/high ID',
          );
        }
        final encoding = reference.conferenceId == 'OTHER'
            ? 'KOI8-R'
            : reference.conferenceId == own
            ? 'CP866'
            : switch (number) {
                1 => 'CP866',
                2 || 3 => null,
                4 => 'UTF-8',
                _ => 'CP866',
              };
        check(data.effectiveEncoding == encoding, 'CHRS/default/override');
        final report = messageTechnicalReport(data);
        check(
          report.contains('2:9/9 external') &&
              report.contains(r'\xFF\x00\r\n\t\x1B\\'),
          'Report preserves external reply and bytes',
        );
        check(!report.contains(root), 'No server paths');
      }
      if (reference.conferenceId == own) {
        try {
          await stranger.getMessageTechnicalData(reference);
          throw StateError('Foreign mailbox accepted');
        } on ApiException catch (e) {
          check(e.isAccessDenied, 'Foreign mailbox denied');
        }
      }
    }
    final security = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(input['ca'] as String);
    final http = HttpClient(context: security);
    try {
      for (final reference in references) {
        final native = await client.getMessageTechnicalData(reference);
        final request = await http.postUrl(
          Uri.parse('${input['web']}/ffido.v1.Ffido/GetMessageTechnicalData'),
        );
        request.headers.set('content-type', 'application/grpc-web+proto');
        request.headers.set('x-grpc-web', '1');
        request.headers.set('origin', 'https://localhost');
        request.headers.set('authorization', 'Bearer ${secrets.first}');
        final bytes = reference.writeToBuffer();
        final prefix = ByteData(5)..setUint32(1, bytes.length);
        request.add(prefix.buffer.asUint8List());
        request.add(bytes);
        final response = await request.close();
        final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
        check(
          response.statusCode == 200 && body.length >= 5 && body.first == 0,
          'gRPC-Web data frame: HTTP ${response.statusCode}, ${utf8.decode(body, allowMalformed: true)}',
        );
        final length = ByteData.sublistView(Uint8List.fromList(body))
            .getUint32(1);
        final web = wire.MessageTechnicalData.fromBuffer(
          body.sublist(5, 5 + length),
        );
        check(
          base64Encode(web.writeToBuffer()) ==
              base64Encode(native.writeToBuffer()),
          'gRPC-Web exact metadata',
        );
        check(
          ascii.decode(body.sublist(10 + length)).contains('grpc-status:0'),
          'gRPC-Web success trailer',
        );
      }
    } finally {
      http.close(force: true);
    }
    check(
      await database() == sqliteBefore,
      'SQLite personal read/history/position/counters must remain unchanged',
    );
    for (final entry in jam.entries) {
      check(
        base64Encode(File(entry.key).readAsBytesSync()) ==
            base64Encode(entry.value),
        'JAM changed',
      );
    }
    stdout.writeln(
      'PASS native Dart → TLS gRPC + TLS Envoy gRPC-Web: 7 fixtures, repeated byte-exact diagnostics, CHRS/default/override, foreign mailbox denied; JAM and complete SQLite dump unchanged',
    );
  } finally {
    for (final client in clients) {
      await client.dispose();
    }
  }
}
