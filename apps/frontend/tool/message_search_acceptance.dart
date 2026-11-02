import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:fixnum/fixnum.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_transport.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

void check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

Future<void> main() async {
  final input = jsonDecode(
    await stdin.transform(utf8.decoder).join(),
  ) as Map<String, dynamic>;
  final uri = Uri.parse(input['endpoint'] as String);
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
  try {
    final tokens = <String>[];
    for (var i = 0; i < 2; i++) {
      final login = await client.login(
        endpoint: uri.toString(),
        name: 'Test$i',
        address: '2:1/${i + 2}',
        password: (input['passwords'] as List)[i] as String,
      );
      tokens.add(login.sessionSecret);
    }
    await client.setAuthToken(tokens.first);
    final ids = <String, List<String>>{};
    for (final area in ['RU.CP866', 'RU.UTF8']) {
      ids[area] = [];
      final count = area == 'RU.CP866' ? 512 : 3;
      for (var i = 0; i < count; i++) {
        final result = await client.createMessage(
          wire.CreateMessageRequest(
            conferenceId: area,
            operationId: '${area.replaceAll('.', '-')}-$i',
            toName: 'All',
            subject: 'Письмо $i',
            body:
                '${List.filled(64, 'Строка для проверки поиска и отмены.').join('\n')}\n${i == 0 || i == count - 1 ? 'Hовый Привет' : 'Без совпадения'}',
          ),
        );
        ids[area]!.add(result.message.messageId);
      }
    }
    await client.setAuthToken(tokens.last);
    for (final area in ids.keys) {
      final request = wire.FindMessageRequest(
        conferenceId: area,
        query: 'ПРИВЕТ',
        scope: wire.MessageSearchScope.MESSAGE_SEARCH_HEADER_AND_BODY,
        sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
        startMessageId: ids[area]!.first,
        includeStart: true,
      );
      final first = await client.findMessage(request);
      check(
        first.message.id == ids[area]!.first && first.message.isRead,
        'First result/view',
      );
      check(
        first.matches.single.startUtf16 == first.message.body.indexOf('Привет'),
        'Exact highlight offset',
      );
      request.includeStart = false;
      final timer = Stopwatch()..start();
      final last = await client.findMessage(request);
      timer.stop();
      check(last.message.id == ids[area]!.last, 'Continuation across pages');
      stdout.writeln(
        '$area: next match across ${ids[area]!.length} messages: ${timer.elapsedMilliseconds} ms',
      );
      request.startMessageId = last.message.id;
      check(
        !(await client.findMessage(request)).hasMessage(),
        'No wrap at end',
      );
      request.clearStartMessageId();
      request.query = 'Новый';
      check(
        (await client.findMessage(request)).hasMessage() ==
            (area == 'RU.CP866'),
        'Effective charset policy',
      );
      for (var offset = 0; offset < ids[area]!.length; offset += 100) {
        final rows = await client.listMessages(
          wire.ListMessagesRequest(
            conferenceId: area,
            page: wire.PageRequest(limit: 100, offset: Int64(offset)),
            sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
          ),
        );
        check(
          rows.messages.every(
            (m) =>
                m.isRead ==
                (m.id == ids[area]!.first || m.id == ids[area]!.last),
          ),
          'Skipped messages unchanged',
        );
      }
    }
    final token = RpcCancellation();
    final timer = Stopwatch()..start();
    final pending = client.findMessage(
      wire.FindMessageRequest(
        conferenceId: 'RU.CP866',
        query: 'not-present',
        scope: wire.MessageSearchScope.MESSAGE_SEARCH_HEADER_AND_BODY,
        sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
      ),
      cancellation: token,
    );
    final handled = pending.then<void>(
      (_) => throw StateError('Cancelled scan succeeded'),
      onError: (Object e) {
        check(e is CancelledException, 'Controlled cancellation');
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await token.cancel();
    await handled;
    stdout.writeln('Cancellation: ${timer.elapsedMilliseconds} ms');
    await client.listMessages(
      wire.ListMessagesRequest(
        conferenceId: 'RU.CP866',
        page: wire.PageRequest(limit: 1),
        sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
      ),
    );
    stdout.writeln(
      'PASS: TLS client/server, CP866/UTF-8, offsets, continuation, no-wrap, read-state, cancellation',
    );
  } finally {
    await client.dispose();
  }
}
