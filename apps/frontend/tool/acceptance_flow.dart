import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fido/repositories/uue_repository.dart';
import 'package:fixnum/fixnum.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

void require(bool value, String description) {
  if (!value) throw StateError(description);
}

Future<void> acceptance(
  ApiClient client,
  String tokenA,
  String tokenB,
  String operation,
) async {
  await client.setAuthToken(tokenA);
  final profileA = await client.getProfile();
  require(
    profileA.name == 'Алексей' && profileA.address == '2:1/2',
    'assigned profile A',
  );
  final conferences = await client.listConferences(
    wire.ListConferencesRequest(
      page: wire.PageRequest(limit: 20),
      sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
    ),
  );
  require(conferences.conferences.length == 1, 'conference catalog');
  final conference = conferences.conferences.single.id;
  final before = await client.listMessages(
    wire.ListMessagesRequest(
      conferenceId: conference,
      page: wire.PageRequest(limit: 100),
      sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
    ),
  );
  final request = wire.CreateMessageRequest(
    conferenceId: conference,
    operationId: '$operation-a',
    toName: 'All',
    subject: 'Русская тема',
    body: 'Привет, мир!\nbegin 644 payload.bin\n#`/\\!\n`\nend\n',
  );
  final created = await client.createMessage(request);
  require(
    created.status == wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
    'saved locally',
  );
  final repeated = await client.createMessage(request);
  require(
    repeated.message.messageId == created.message.messageId &&
        repeated.ftnMessageId == created.ftnMessageId,
    'idempotent retry',
  );
  final detail = await client.getMessage(created.message);
  require(
    detail.body.contains('Привет, мир!') &&
        detail.fromName == 'Алексей' &&
        detail.fromAddress == '2:1/2' &&
        detail.isRead,
    'Unicode and read identity',
  );
  final uue = UueRepository(client);
  final parts = await uue.messageParts(conference, created.message.messageId);
  require(parts.length == 1, 'UUE metadata over transport');
  final assembled = await uue.assemble(parts);
  final binary = await uue.download(assembled);
  require(
    binary.length == 3 && binary[0] == 0 && binary[1] == 255 && binary[2] == 1,
    'UUE binary chunk over transport',
  );
  final staging = Uint8List.fromList([0, 255, 1]);
  await client.uploadUueChunk(
    wire.UploadUueChunkRequest(
      operationId: '$operation-stage',
      filename: 'a.bin',
      fileSize: Int64(3),
      sha256: sha256.convert(staging).toString(),
      data: staging,
    ),
  );
  require(
    (await client.getUueSendStatus(
          wire.UueOperationReference(operationId: '$operation-stage'),
        )).state ==
        'uploading',
    'UUE durable upload status over transport',
  );
  await client.addBookmark(wire.GetConferenceRequest(conferenceId: conference));
  final bookmarks = await client.listBookmarks(wire.PageRequest(limit: 20));
  require(
    bookmarks.bookmarks.length == 1 && bookmarks.bookmarks.single.hasAddedAt(),
    'bookmark timestamp',
  );
  final history = await client.listHistory(wire.PageRequest(limit: 20));
  require(
    history.history.isNotEmpty && history.history.first.hasViewedAt(),
    'history timestamp',
  );
  await client.setAuthToken(tokenB);
  final profileB = await client.getProfile();
  require(
    profileB.name == 'Борис' && profileB.address == '2:1/3',
    'assigned profile B',
  );
  require(
    (await client.listBookmarks(wire.PageRequest(limit: 20))).bookmarks.isEmpty,
    'private bookmarks',
  );
  final otherRows = await client.listMessages(
    wire.ListMessagesRequest(
      conferenceId: conference,
      page: wire.PageRequest(limit: 100),
      sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
    ),
  );
  require(
    !otherRows.messages
        .firstWhere((m) => m.id == created.message.messageId)
        .isRead,
    'private read state',
  );
  await client.markRead(created.message);
  final reply = await client.createMessage(
    wire.CreateMessageRequest(
      conferenceId: conference,
      operationId: '$operation-b',
      toName: 'wrong',
      toAddress: '2:9/9',
      subject: 'Re: Русская тема',
      body: 'Ответ по gRPC',
      inReplyTo: created.message.messageId,
    ),
  );
  final thread = await client.getThread(
    wire.GetThreadRequest(
      conferenceId: conference,
      threadId: created.message.messageId,
      page: wire.PageRequest(limit: 100),
    ),
  );
  require(
    thread.messages.length == 2 &&
        thread.messages.last.toAddress == '2:1/2' &&
        thread.messages.last.inReplyTo == created.message.messageId,
    'reply recipient and thread',
  );
  require(
    reply.status == wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
    'reply acknowledgement',
  );
  await client.setAuthToken(tokenA);
  await client.removeBookmark(
    wire.GetConferenceRequest(conferenceId: conference),
  );
  await client.clearHistory();
  require(
    (await client.listHistory(wire.PageRequest(limit: 20))).history.isEmpty,
    'Empty clearHistory',
  );
  final after = await client.getConference(
    wire.GetConferenceRequest(conferenceId: conference),
  );
  require(
    after.totalCount == before.total + Int64(2),
    'exactly two new messages',
  );
  try {
    await client.listConferences(
      wire.ListConferencesRequest(
        page: wire.PageRequest(offset: Int64(-1), limit: 0),
      ),
    );
    throw StateError('invalid fields accepted');
  } on ValidationException catch (error) {
    require(error.fieldErrors.isNotEmpty, 'binary field-details trailers');
  }
  await client.clearAuthToken();
  try {
    await client.getProfile();
    throw StateError('missing token accepted');
  } on UnauthorizedException {
    // The client and server both enforce token authentication.
  }
}
