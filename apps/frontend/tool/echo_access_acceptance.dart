import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> denied(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    require(e.isAccessDenied, 'expected PERMISSION_DENIED');
    return;
  }
  throw StateError('unauthorized call succeeded');
}

wire.CreateMessageRequest post(String area, String operation) =>
    wire.CreateMessageRequest(
      conferenceId: area,
      operationId: operation,
      subject: 'ACL fixture',
      body: 'ACL body',
      toName: 'All',
    );
Future<void> main() async {
  final input = jsonDecode(
    await stdin.transform(utf8.decoder).join(),
  ) as Map<String, dynamic>;
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
    final phase = input['phase'] as String;
    if (phase != 'initial') {
      await client.setAuthToken(input['token'] as String);
      await client.restoreSession();
      final ref = wire.MessageReference(
        conferenceId: 'ACL.FULL',
        messageId: input['message'] as String,
      );
      if (phase == 'revoked') {
        await denied(() => client.getMessage(ref));
        await denied(
          () => client.createMessage(post('ACL.FULL', 'acl-initial')),
        );
        require(
          (await client.listBookmarks(wire.PageRequest(limit: 100))).bookmarks
              .every((v) => v.conference.id != 'ACL.FULL'),
          'revoked bookmark',
        );
        require(
          (await client.listHistory(wire.PageRequest(limit: 100))).history
              .every((v) => v.conference.id != 'ACL.FULL'),
          'revoked history',
        );
      } else {
        final meta = await client.getConference(
          wire.GetConferenceRequest(conferenceId: 'ACL.FULL'),
        );
        require(
          meta.totalCount.toInt() == 1 && meta.unreadCount.toInt() == 0,
          'preserved read state',
        );
        require(
          (await client.listBookmarks(wire.PageRequest(limit: 100))).bookmarks
              .any((v) => v.conference.id == 'ACL.FULL'),
          'restored bookmark',
        );
      }
      stdout.writeln('{}');
      return;
    }
    final a = await client.login(
      endpoint: client.endpoint.toString(),
      name: 'Алексей',
      address: '2:1/2',
      password: input['passwordA'] as String,
    );
    final b = await client.login(
      endpoint: client.endpoint.toString(),
      name: 'Борис',
      address: '2:1/3',
      password: input['passwordB'] as String,
    );
    await client.setAuthToken(a.sessionSecret);
    final list = await client.listConferences(
      wire.ListConferencesRequest(
        page: wire.PageRequest(limit: 100),
        query: 'ACL.',
        sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
      ),
    );
    require(list.total.toInt() == 4 && !list.hasMore, 'filtered catalog');
    final read = list.conferences.firstWhere((v) => v.id == 'ACL.READ');
    final write = list.conferences.firstWhere((v) => v.id == 'ACL.WRITE');
    require(
      read.canRead && !read.canPost && !write.canRead && write.canPost,
      'directional permissions',
    );
    await denied(() => client.createMessage(post('ACL.READ', 'acl-readonly')));
    final written = await client.createMessage(
      post('ACL.WRITE', 'acl-writeonly'),
    );
    await denied(() => client.getMessage(written.message));
    await denied(() => client.markRead(written.message));
    await denied(
      () => client.getThread(
        wire.GetThreadRequest(
          conferenceId: 'ACL.WRITE',
          threadId: written.message.messageId,
          page: wire.PageRequest(limit: 20),
        ),
      ),
    );
    final created = await client.createMessage(post('ACL.FULL', 'acl-initial'));
    require(
      (await client.createMessage(post('ACL.FULL', 'acl-initial')))
              .message
              .messageId ==
          created.message.messageId,
      'idempotency',
    );
    await client.getMessage(created.message);
    await client.addBookmark(
      wire.GetConferenceRequest(conferenceId: 'ACL.FULL'),
    );
    final private = await client.createMessage(
      post('ACL.PRIVATE', 'acl-private'),
    );
    await client.setAuthToken(b.sessionSecret);
    final page = await client.listConferences(
      wire.ListConferencesRequest(
        page: wire.PageRequest(limit: 1),
        query: 'ACL.',
        sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
      ),
    );
    require(
      page.total.toInt() == 1 &&
          page.conferences.single.id == 'ACL.FULL' &&
          !page.hasMore,
      'point isolation and pagination',
    );
    final shared = await client.getConference(
      wire.GetConferenceRequest(conferenceId: 'ACL.FULL'),
    );
    require(shared.unreadCount.toInt() == 1, 'independent read state');
    await denied(() => client.getMessage(private.message));
    await denied(
      () => client.createMessage(post('ACL.PRIVATE', 'acl-forbidden')),
    );
    await denied(
      () => client.getConference(
        wire.GetConferenceRequest(conferenceId: 'ACL.HIDDEN'),
      ),
    );
    stdout.write('FFIDO_ACL_RESULT:');
    stdout.writeln(
      jsonEncode({
        'token': a.sessionSecret,
        'message': created.message.messageId,
      }),
    );
  } finally {
    await client.dispose();
  }
}
