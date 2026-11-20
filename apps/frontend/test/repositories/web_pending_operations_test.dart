import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/files/uue_file_types.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/repositories/uue_repository.dart';
import 'package:fido/repositories/web_draft_store.dart';

import '../support/fake_transport.dart';

void main() {
  late FakeTransport api;
  late SharedPreferences prefs;
  late WebDraftStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    api = FakeTransport();
    store = WebDraftStore(
      readValue: prefs.getString,
      listKeys: prefs.getKeys,
      writeValue: prefs.setString,
      removeValue: prefs.remove,
    )..scope = 'profile';
    WebDraftStore.active = store;
  });
  tearDown(() async {
    WebDraftStore.active = null;
    await api.dispose();
  });
  test('request is durable before send, frozen on restart, never automatically repeated', () async {
    List<int>? sent;
    api.create = (request) async {
      expect(store.list('profile'), hasLength(1));
      sent = request.writeToBuffer();
      throw const NetworkException();
    };
    Future<void> send(MessageRepository repo) async {
      await repo.sendMessage(
        conferenceId: 'ECHO',
        toName: 'All',
        toAddress: '',
        subject: 'Subject',
        body: 'Body',
        operationId: 'stable',
      );
    }

    await expectLater(
      send(MessageRepository(api)),
      throwsA(isA<NetworkException>()),
    );
    expect(api.calls.whereType<wire.CreateMessageRequest>(), hasLength(1));
    final reopened = WebDraftStore(
      readValue: prefs.getString,
      listKeys: prefs.getKeys,
      writeValue: prefs.setString,
      removeValue: prefs.remove,
    )..scope = 'profile';
    WebDraftStore.active = reopened;
    expect(api.calls.whereType<wire.CreateMessageRequest>(), hasLength(1));
    api.create = (request) async {
      expect(request.writeToBuffer(), sent);
      return wire.CreateMessageResponse(
        status: wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
        message: wire.MessageReference(conferenceId: 'ECHO', messageId: 'g#1'),
      );
    };
    await send(MessageRepository(api));
    expect(reopened.list('profile'), isEmpty);
    expect(api.calls.whereType<wire.CreateMessageRequest>(), hasLength(2));
  });
  test('definitive rejection is not presented as an unknown send', () async {
    api.create = (_) async =>
        throw const ValidationException(message: 'Rejected');
    await expectLater(
      MessageRepository(api).sendMessage(
        conferenceId: 'ECHO',
        toName: 'All',
        toAddress: '',
        subject: 'Subject',
        body: 'Body',
        operationId: 'rejected',
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(store.list('profile'), isEmpty);
  });
  test('preview digest and bytes survive as an immutable request', () async {
    final request = wire.CreateMessageRequest(
      conferenceId: 'ECHO',
      operationId: 'digest',
      body: 'Body',
      expectedPreviewDigest: 'preview',
    );
    await store.freeze(
      'profile',
      'digest',
      'CreateMessage',
      request.writeToBuffer(),
      'unchanged',
    );
    final restored = wire.CreateMessageRequest.fromBuffer(
      base64Decode(store.list('profile').single['wire'] as String),
    );
    expect(restored.expectedPreviewDigest, 'preview');
  });
  test('UUE remembers commit metadata without bytes and requires the same reselected file', () async {
    api.getUueLimitsHandler = (_) async => wire.UueLimits(
      maxFileBytes: Int64(1048576),
      partBodyBytes: 32768,
      maxParts: 128,
      chunkBytes: 65536,
      previewPixels: Int64(16000000),
      previewDimension: 8192,
    );
    api.getUueSendStatusHandler = (_) async => throw const NotFoundException();
    api.uploadUueChunkHandler = (request) async => wire.UueUploadStatus(
      receivedBytes: request.offset + request.data.length,
    );
    api.commitUueHandler = (_) async => throw const NetworkException();
    UueDraft draft(List<int> bytes) => UueDraft(
      conference: 'ECHO',
      operation: 'uue',
      subject: 'Subject',
      body: 'Body',
      toName: 'All',
      toAddress: '',
      file: SelectedUueFile('original.bin', Uint8List.fromList(bytes)),
    );
    await expectLater(
      UueRepository(api).send(draft([65, 66, 67])),
      throwsA(isA<NetworkException>()),
    );
    final record = store.list('profile').single;
    expect(record['rpc'], 'CommitUue');
    expect(record.keys, isNot(contains('data')));
    WebDraftStore.active = WebDraftStore(
      readValue: prefs.getString,
      listKeys: prefs.getKeys,
      writeValue: prefs.setString,
      removeValue: prefs.remove,
    )..scope = 'profile';
    await expectLater(UueRepository(api).send(draft([99])), throwsStateError);
    api.commitUueHandler = (_) async => wire.UueSendStatus(
      operationId: 'uue',
      state: 'completed',
      totalParts: 1,
      savedParts: 1,
    );
    expect(
      (await UueRepository(api).send(draft([65, 66, 67]))).complete,
      isTrue,
    );
    expect(store.list('profile'), isEmpty);
  });
}
