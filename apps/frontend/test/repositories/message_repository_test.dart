import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/api_transport.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/message.dart';
import 'package:fido/repositories/message_repository.dart';
import '../support/fake_transport.dart';

void main() {
  late FakeTransport api;
  late MessageRepository repo;
  final original = Message(
    id: 'generation#42',
    fromName: 'Автор',
    fromAddress: '2:1/2',
    toName: 'Другой',
    toAddress: '2:1/3',
    subject: 'Тема',
    body: 'Русский текст',
    date: DateTime.utc(2026),
  );
  setUp(() {
    api = FakeTransport();
    repo = MessageRepository(api);
  });
  tearDown(() => api.dispose());

  test(
    'bulk read preserves immutable key, maps legacy and ignores stale/cancelled results',
    () async {
      final calls = <wire.MarkConferenceReadRequest>[];
      api.bulkRead = (r) async {
        calls.add(r);
        throw const NetworkException();
      };
      for (var n = 0; n < 2; n++) {
        await expectLater(
          repo.markConferenceRead(
            conferenceId: 'echo',
            operationId: 'same-key',
          ),
          throwsA(isA<NetworkException>()),
        );
      }
      expect(calls.map((r) => r.operationId), ['same-key', 'same-key']);
      expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
      api.bulkRead = (_) async =>
          throw const ApiException(message: 'unimplemented', statusCode: 12);
      await expectLater(
        repo.markConferenceRead(conferenceId: 'echo', operationId: 'legacy'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('не поддерживает'),
          ),
        ),
      );
      final future = Completer<wire.MarkConferenceReadResponse>();
      api.bulkRead = (_) => future.future;
      final pending = repo.markConferenceRead(
        conferenceId: 'echo',
        operationId: 'old',
      );
      api.switchSession();
      future.complete(wire.MarkConferenceReadResponse());
      await expectLater(pending, throwsA(isA<CancelledException>()));
      final cancelled = RpcCancellation();
      await cancelled.cancel();
      api.bulkRead = (_) async => wire.MarkConferenceReadResponse();
      await expectLater(
        repo.markConferenceRead(
          conferenceId: 'echo',
          operationId: 'cancel',
          cancellation: cancelled,
        ),
        throwsA(isA<CancelledException>()),
      );
    },
  );
  test('list/detail/read/thread preserve IDs, pagination and UTC', () async {
    api.message = (r) async =>
        wire.Message(id: r.messageId, subject: 'Тема', body: 'Текст');
    await repo.getConferenceMessages(
      conferenceId: 'conf',
      offset: 2,
      limit: 3,
      sort: 'oldest',
    );
    final list = api.calls.last as wire.ListMessagesRequest;
    expect(list.page.offset.toInt(), 2);
    expect(list.page.limit, 3);
    expect(list.sort, wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING);
    final detail = await repo.getMessage(
      conferenceId: 'conf',
      messageId: original.id,
    );
    expect(detail.id, original.id);
    expect(detail.body, 'Текст');
    expect(detail.date.isUtc, isTrue);
    await repo.markAsRead(conferenceId: 'conf', messageId: original.id);
    expect((api.calls.last as wire.MessageReference).messageId, original.id);
    await repo.getThread(
      conferenceId: 'conf',
      threadId: original.id,
      offset: 20,
    );
    expect((api.calls.last as wire.GetThreadRequest).page.offset.toInt(), 20);
    await expectLater(
      repo.getConferenceMessages(conferenceId: 'conf', sort: 'bad'),
      throwsA(isA<ValidationException>()),
    );
  });
  for (final replyAll in [false, true]) {
    test('reply addresses original author (all=$replyAll)', () async {
      final result = replyAll
          ? await repo.replyToAll(
              conferenceId: 'conf',
              originalMessage: original,
              body: 'Ответ',
              operationId: 'same',
            )
          : await repo.replyToMessage(
              conferenceId: 'conf',
              originalMessage: original,
              body: 'Ответ',
              operationId: 'same',
            );
      final request = api.calls.single as wire.CreateMessageRequest;
      expect(request.toName, 'Автор');
      expect(request.toAddress, '2:1/2');
      expect(request.inReplyTo, original.id);
      expect(request.subject, 'Re: Тема');
      expect(request.operationId, 'same');
      expect(result.status, 'saved_locally');
    });
  }
  test(
    'new and forwarded messages have no parent and use explicit recipient',
    () async {
      await repo.composeNewMessage(
        conferenceId: 'conf',
        toName: 'All',
        toAddress: '',
        subject: 'Новое',
        body: 'Текст',
        operationId: 'new',
      );
      expect((api.calls.last as wire.CreateMessageRequest).inReplyTo, isEmpty);
      await repo.forwardMessage(
        conferenceId: 'conf',
        toName: 'Получатель',
        toAddress: '2:1/5',
        originalMessage: original,
        note: 'Комментарий',
        operationId: 'forward',
      );
      final request = api.calls.last as wire.CreateMessageRequest;
      expect(request.inReplyTo, isEmpty);
      expect(request.toAddress, '2:1/5');
      expect(request.subject, 'Fwd: Тема');
      expect(request.body, contains('Русский текст'));
      expect(request.body, startsWith('Комментарий'));
      expect(request.operationId, 'forward');
    },
  );
  test('uncertain retry keeps operation ID and payload', () async {
    api.create = (_) async => throw const NetworkException();
    await expectLater(
      repo.replyToMessage(
        conferenceId: 'conf',
        originalMessage: original,
        body: 'Ответ',
        operationId: 'same',
      ),
      throwsA(isA<NetworkException>()),
    );
    api.create = null;
    await repo.replyToMessage(
      conferenceId: 'conf',
      originalMessage: original,
      body: 'Ответ',
      operationId: 'same',
    );
    expect(
      (api.calls[0] as wire.CreateMessageRequest).writeToBuffer(),
      (api.calls[1] as wire.CreateMessageRequest).writeToBuffer(),
    );
  });
  test('unknown save status cannot claim success', () async {
    api.create = (_) async => wire.CreateMessageResponse();
    await expectLater(
      repo.sendMessage(
        conferenceId: 'conf',
        toName: 'All',
        toAddress: '',
        subject: 'Тема',
        body: 'Текст',
      ),
      throwsA(isA<ServerException>()),
    );
  });
  test('late detail after session change is rejected', () async {
    final pending = Completer<wire.Message>();
    api.message = (_) => pending.future;
    final result = repo.getMessage(conferenceId: 'conf', messageId: '42');
    final assertion = expectLater(result, throwsA(isA<CancelledException>()));
    api.switchSession();
    pending.complete(wire.Message(id: 'old'));
    await assertion;
  });
  test('cancelled request cannot publish successful response', () async {
    final cancellation = RpcCancellation();
    await cancellation.cancel();
    await expectLater(
      repo.getThread(
        conferenceId: 'conf',
        threadId: '42',
        cancellation: cancellation,
      ),
      throwsA(isA<CancelledException>()),
    );
  });
}
