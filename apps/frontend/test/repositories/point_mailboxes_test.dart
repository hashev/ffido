import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/api/model_mapping.dart';
import 'package:fido/models/message.dart';
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';

void main() {
  test(
    'old server defaults and anchor actual offset remain compatible',
    () async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      final repo = MessageRepository(api);
      expect(mapConference(wire.Conference()).personalMailbox, isFalse);
      expect(mapMessage(wire.Message()).direction, MailDirection.unspecified);
      api.messages = (r) async =>
          wire.ListMessagesResponse(actualOffset: Int64(40));
      final result = await repo.getConferenceMessages(
        conferenceId: 'P1',
        anchorMessageId: 'g#45',
        query: 'filter',
        sort: 'oldest',
      );
      expect(result.actualOffset, 40);
      final request = api.calls.last as wire.ListMessagesRequest;
      expect(request.anchorMessageId, 'g#45');
      expect(request.query, 'filter');
      expect(mapMessages(wire.ListMessagesResponse()).actualOffset, isNull);
    },
  );
  test(
    'late position revisions and previous sessions cannot replace newer state',
    () async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      final repo = MessageRepository(api);
      final old = Completer<wire.Conference>();
      var count = 0;
      api.conference = (_) {
        if (count++ == 0) return old.future;
        return Future.value(
          wire.Conference(personalMailbox: true, positionRevision: Int64(2)),
        );
      };
      final first = repo.getMailboxState('P1');
      await repo.getMailboxState('P1');
      old.complete(
        wire.Conference(personalMailbox: true, positionRevision: Int64.ONE),
      );
      await expectLater(first, throwsA(isA<CancelledException>()));
      final previous = Completer<wire.Conference>();
      api.conference = (_) => previous.future;
      final stale = repo.getMailboxState('P1');
      api.switchSession();
      previous.complete(
        wire.Conference(personalMailbox: true, positionRevision: Int64(99)),
      );
      await expectLater(stale, throwsA(isA<CancelledException>()));
      api.conference = (_) async =>
          wire.Conference(personalMailbox: true, positionRevision: Int64.ONE);
      expect((await repo.getMailboxState('P2')).positionRevision, 1);
    },
  );
  test(
    'outgoing reply uses recipient and creates no substitute author',
    () async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      final repo = MessageRepository(api);
      final original = Message(
        id: 'g#1',
        fromName: 'Me',
        fromAddress: '2:1/2.1',
        toName: 'Remote',
        toAddress: '2:1/9.7',
        subject: 'Topic',
        body: 'Body',
        date: DateTime.utc(2026),
        direction: MailDirection.outgoing,
      );
      await repo.replyToMessage(
        conferenceId: 'P1',
        originalMessage: original,
        body: 'Reply',
        operationId: 'same',
      );
      final request = api.calls.last as wire.CreateMessageRequest;
      expect(request.toAddress, '2:1/9.7');
      expect(request.toName, 'Remote');
      expect(request.inReplyTo, 'g#1');
      expect(request.operationId, 'same');
    },
  );
}
