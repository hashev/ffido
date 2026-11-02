import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:fido/api/api_client.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final input = jsonDecode(
    await stdin.transform(utf8.decoder).join(),
  ) as Map<String, dynamic>;
  final uri = Uri.parse(input['endpoint'] as String);
  final clients = <ApiClient>[];
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
    await client.login(
      endpoint: uri.toString(),
      name: 'Test$index',
      address: ['2:1/2.2', '2:1/2.3', '2:1/4'][index],
      password: (input['passwords'] as List)[index] as String,
    );
    return client;
  }

  Future<List<wire.Conference>> catalog(ApiClient client) async =>
      (await client.listConferences(
        wire.ListConferencesRequest(
          page: wire.PageRequest(limit: 100),
          sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
        ),
      )).conferences;
  try {
    final reader = await login(0),
        author = await login(1),
        noMailbox = await login(2);
    final mail = (await catalog(reader))
        .singleWhere((a) => a.personalMailbox)
        .id;
    check(
      (await catalog(noMailbox))
          .every((a) => a.kind != wire.AreaKind.AREA_KIND_NETMAIL),
      'No Netmail must remain empty',
    );
    final original = await author.createMessage(
      wire.CreateMessageRequest(
        conferenceId: 'SOURCE',
        operationId: 'original',
        toName: 'All',
        subject: 'Original',
        body: 'Original text',
      ),
    );
    final source = await reader.getMessage(
      wire.MessageReference(
        conferenceId: 'SOURCE',
        messageId: original.message.messageId,
      ),
    );
    check(source.fromAddress == '2:1/2.3', 'Author address');
    for (final target in [mail, 'OTHER']) {
      await reader.createMessage(
        wire.CreateMessageRequest(
          conferenceId: target,
          operationId: target == mail ? 'mail-seed' : 'echo-seed',
          toName: 'Author',
          toAddress: source.fromAddress,
          subject: 'Seed',
          body: 'Seed',
        ),
      );
      final request = wire.CreateMessageRequest(
        conferenceId: target,
        operationId: target == mail ? 'mail-reply' : 'echo-reply',
        toName: source.fromName,
        toAddress: source.fromAddress,
        subject: 'Re: Original',
        body: 'T> Original text\nAnswer',
      );
      final committed = await reader.createMessage(request);
      // Discard the first confirmation as if the response had been lost, then reconcile the same operation.
      final repeated = await reader.createMessage(request);
      check(
        repeated.message == committed.message &&
            repeated.ftnMessageId == committed.ftnMessageId,
        'Retry must not duplicate',
      );
      final detail = await reader.getMessage(repeated.message);
      check(
        detail.fromAddress == '2:1/2.2' && detail.toAddress == '2:1/2.3',
        'Authenticated author and recipient',
      );
      check(
        detail.body.startsWith('T> Original text\nAnswer'),
        'Quoted reply text',
      );
      if (target == mail) {
        check(
          detail.direction == wire.MailDirection.MAIL_DIRECTION_OUTGOING,
          'Outgoing personal copy',
        );
        check(!detail.body.contains('Origin:'), 'No echo footer in Netmail');
      } else {
        check(detail.body.contains('Origin:'), 'Echo footer');
      }
      final thread = await reader.getThread(
        wire.GetThreadRequest(
          conferenceId: target,
          threadId: detail.threadId,
          page: wire.PageRequest(limit: 100),
        ),
      );
      check(thread.messages.length == 1, 'Independent local thread');
    }
    final unchanged = await reader.getMessage(original.message);
    check(
      unchanged.body == source.body && unchanged.subject == source.subject,
      'Source unchanged',
    );
    stdout.writeln(
      'TLS: Echo → own Netmail / other Echo; author, quote, no mailbox, discarded response and idempotent retry passed',
    );
  } finally {
    for (final client in clients) {
      await client.dispose();
    }
  }
}
