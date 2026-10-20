import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:fido/api/api_client.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

import 'acceptance_flow.dart' show require;

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
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  try {
    if (args.single == 'save') {
      final login = await client.login(
        endpoint: input['endpoint'] as String,
        name: 'Алексей',
        address: '2:1/2',
        password: input['passwordA'] as String,
      );
      final conferences = await client.listConferences(
        wire.ListConferencesRequest(
          page: wire.PageRequest(limit: 20),
          sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
        ),
      );
      final conference = conferences.conferences.single.id;
      final created = await client.createMessage(
        wire.CreateMessageRequest(
          conferenceId: conference,
          operationId: 'container-persist',
          toName: 'All',
          subject: 'Container persistence',
          body: 'Сохранено на внешнем mount',
        ),
      );
      await client.markRead(
        wire.MessageReference(
          conferenceId: conference,
          messageId: created.message.messageId,
        ),
      );
      await client.addBookmark(
        wire.GetConferenceRequest(conferenceId: conference),
      );
      await client.uploadUueChunk(
        wire.UploadUueChunkRequest(
          operationId: 'container-upload',
          filename: 'persistent.bin',
          fileSize: Int64(bytes.length),
          sha256: sha256.convert(bytes).toString(),
          data: bytes.sublist(0, 2),
        ),
      );
      final savedMessage = await client.getMessage(created.message);
      require(
        savedMessage.body.contains('Сохранено на внешнем mount'),
        'created message body is readable',
      );
      await state.writeAsString(
        jsonEncode({
          'token': login.sessionSecret,
          'conference': conference,
          'message': created.message.messageId,
          'body': savedMessage.body,
        }),
      );
      // This file stays on the temporary fixture mount, never in CI artifacts.
      await Process.run('chmod', ['600', state.path]);
    } else {
      final saved =
          jsonDecode(await state.readAsString()) as Map<String, dynamic>;
      await client.setAuthToken(saved['token'] as String);
      await client.restoreSession();
      // Check read metadata before GetMessage can mark it read again.
      final messages = await client.listMessages(
        wire.ListMessagesRequest(
          conferenceId: saved['conference'] as String,
          page: wire.PageRequest(limit: 100),
          sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
        ),
      );
      require(
        messages.messages
            .singleWhere((message) => message.id == saved['message'])
            .isRead,
        'read metadata persisted before opening the message',
      );
      final detail = await client.getMessage(
        wire.MessageReference(
          conferenceId: saved['conference'] as String,
          messageId: saved['message'] as String,
        ),
      );
      require(
        detail.body == saved['body'] && detail.isRead,
        'message and read state persisted',
      );
      require(
        (await client.listBookmarks(wire.PageRequest(limit: 20)))
            .bookmarks
            .isNotEmpty,
        'bookmark metadata persisted',
      );
      final uploaded = await client.uploadUueChunk(
        wire.UploadUueChunkRequest(
          operationId: 'container-upload',
          filename: 'persistent.bin',
          fileSize: Int64(bytes.length),
          sha256: sha256.convert(bytes).toString(),
          offset: Int64(2),
          data: bytes.sublist(2),
        ),
      );
      require(
        uploaded.complete && uploaded.receivedBytes == Int64(4),
        'upload bytes persisted',
      );
    }
    stdout.writeln('PASS: container persistence ${args.single}');
  } finally {
    await client.dispose();
  }
}
