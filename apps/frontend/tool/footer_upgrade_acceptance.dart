import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:fido/api/api_client.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

void require(bool ok, String reason) {
  if (!ok) throw StateError(reason);
}

Future<void> main(List<String> args) async {
  final input = jsonDecode(
    await stdin.transform(utf8.decoder).join(),
  ) as Map<String, dynamic>;
  final state = File(input['state'] as String);
  final client = ApiClient(
    endpoint: input['endpoint'] as String,
    channelFactory: (uri) => grpc.ClientChannel(
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
    if (args.single == 'seed') {
      final session = await client.login(
        endpoint: client.endpoint.toString(),
        name: 'Upgrade fixture',
        address: '2:1/2',
        password: input['password'] as String,
      );
      require(!client.supportsMessageFooter, 'before server must be legacy');
      final saved = await client.createMessage(
        wire.CreateMessageRequest(
          conferenceId: 'RU.ONE',
          operationId: 'legacy',
          toName: 'All',
          subject: 'Legacy',
          body: 'Preserve this old message',
        ),
      );
      final old = await client.getMessage(saved.message);
      await state.writeAsString(
        jsonEncode({
          'token': session.sessionSecret,
          'old': saved.message.toProto3Json(),
          'oldBody': old.body,
        }),
      );
      await Process.run('chmod', ['600', state.path]);
    } else {
      final saved =
          jsonDecode(await state.readAsString()) as Map<String, dynamic>;
      await client.setAuthToken(saved['token'] as String);
      final session = await client.restoreSession();
      final oldRef = wire.MessageReference()..mergeFromProto3Json(saved['old']);
      if (args.single != 'restored') {
        require(
          (await client.getMessage(oldRef)).body == saved['oldBody'],
          'legacy body must remain unchanged',
        );
      }
      if (args.single == 'footer') {
        require(
          session.supportsMessageFooter,
          'restored session must advertise footer support',
        );
        final expected = <Map<String, dynamic>>[];
        Future<void> check(
          wire.MessageReference ref,
          String tagline,
          String origin,
        ) async {
          final message = await client.getMessage(ref);
          require(
            message.body.contains('--- $tagline\n * Origin: $origin (2:1/2)'),
            'footer mismatch',
          );
          require(
            RegExp(r'^--- ', multiLine: true).allMatches(message.body).length ==
                1,
            'exactly one footer',
          );
          expected.add({'reference': ref.toProto3Json(), 'body': message.body});
        }

        final normal = await client.createMessage(
          wire.CreateMessageRequest(
            conferenceId: 'RU.ONE',
            operationId: 'footer-auto',
            toName: 'All',
            subject: 'Automatic',
            body: 'Automatic body',
            footer: wire.MessageFooter(
              tagline: 'FFIDO 1.0.7',
              origin: 'https://github.com/hashev/ffido',
            ),
          ),
        );
        await check(
          normal.message,
          'FFIDO 1.0.7',
          'https://github.com/hashev/ffido',
        );
        final reply = await client.createMessage(
          wire.CreateMessageRequest(
            conferenceId: 'RU.ONE',
            operationId: 'footer-reply',
            toName: 'All',
            subject: 'Reply',
            body: 'Reply body',
            inReplyTo: normal.message.messageId,
            footer: wire.MessageFooter(
              tagline: 'Custom tag',
              origin: 'Custom origin',
            ),
          ),
        );
        await check(reply.message, 'Custom tag', 'Custom origin');
        final group = await client.createCrosspost(
          wire.CreateCrosspostRequest(
            message: wire.CreateMessageRequest(
              conferenceId: 'RU.ONE',
              operationId: 'footer-group',
              toName: 'All',
              subject: 'Group',
              body: 'Group body',
              footer: wire.MessageFooter(
                tagline: 'Group tag',
                origin: 'Group origin',
              ),
            ),
            additionalConferenceIds: ['RU.TWO'],
          ),
        );
        require(
          group.complete && group.saved.length == 2,
          'group must be complete',
        );
        for (final copy in group.saved) {
          await check(copy.message, 'Group tag', 'Group origin');
        }
        saved['expected'] = expected;
        await state.writeAsString(jsonEncode(saved));
      } else if (args.single == 'verify') {
        for (final item in saved['expected'] as List) {
          final ref = wire.MessageReference()
            ..mergeFromProto3Json(item['reference']);
          require(
            (await client.getMessage(ref)).body == item['body'],
            'HPT must preserve message body and footer',
          );
        }
      } else if (args.single == 'restored') {
        require(
          !session.supportsMessageFooter,
          'backup must run on legacy version',
        );
        final rows = await client.listMessages(
          wire.ListMessagesRequest(
            conferenceId: 'RU.ONE',
            page: wire.PageRequest(limit: 100),
            sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
          ),
        );
        require(
          rows.messages.length == 1,
          'restored backup must contain only original message',
        );
        final restored = await client.getMessage(
          wire.MessageReference(
            conferenceId: 'RU.ONE',
            messageId: rows.messages.single.id,
          ),
        );
        require(
          restored.body == saved['oldBody'],
          'restored body must remain unchanged after generation refresh',
        );
      } else {
        throw ArgumentError('seed, footer, verify or restored expected');
      }
    }
    stdout.writeln('PASS: footer upgrade ${args.single}');
  } finally {
    await client.dispose();
  }
}
