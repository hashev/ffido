import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_transport.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';

void main() {
  test('parameters, UTF-16 validation, empty response and errors', () async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    final repo = MessageRepository(api);
    api.find = (r) async {
      expect(r.query, 'Привет');
      expect(r.includeStart, isFalse);
      expect(r.startMessageId, 'g#1');
      expect(r.scope, wire.MessageSearchScope.MESSAGE_SEARCH_HEADER_ONLY);
      return wire.FindMessageResponse(
        message: wire.Message(id: 'g#2', body: '😀Привет'),
        matches: [
          wire.SearchMatch(
            field_1: wire.MessageSearchField.MESSAGE_SEARCH_BODY,
            startUtf16: 2,
            lengthUtf16: 6,
          ),
        ],
      );
    };
    final result = await repo.findMessage(
      conferenceId: 'echo',
      query: ' Привет ',
      headersOnly: true,
      startMessageId: 'g#1',
      includeStart: false,
    );
    expect(result!.matches[6]!.single.start, 2);
    api.find = (_) async => wire.FindMessageResponse();
    expect(await repo.findMessage(conferenceId: 'echo', query: 'x'), isNull);
    api.find = (_) async => wire.FindMessageResponse(
      message: wire.Message(id: 'g#2', body: '😀Привет'),
      matches: [
        wire.SearchMatch(
          field_1: wire.MessageSearchField.MESSAGE_SEARCH_BODY,
          startUtf16: 1,
          lengthUtf16: 3,
        ),
      ],
    );
    await expectLater(
      repo.findMessage(conferenceId: 'echo', query: 'x'),
      throwsA(isA<ServerException>()),
    );
    await expectLater(
      repo.findMessage(
        conferenceId: 'echo',
        query: List.filled(129, 'Я').join(),
      ),
      throwsA(isA<ValidationException>()),
    );
    api.find = (_) async => throw const NetworkException();
    await expectLater(
      repo.findMessage(conferenceId: 'echo', query: 'x'),
      throwsA(isA<NetworkException>()),
    );
  });
  test('cancellation before dispatch and epoch after dispatch', () async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    final repo = MessageRepository(api), token = RpcCancellation();
    await token.cancel();
    await expectLater(
      repo.findMessage(conferenceId: 'echo', query: 'x', cancellation: token),
      throwsA(isA<CancelledException>()),
    );
    expect(api.calls, isEmpty);
    final pending = Completer<wire.FindMessageResponse>();
    api.find = (_) => pending.future;
    final call = repo.findMessage(conferenceId: 'echo', query: 'x');
    api.switchSession();
    pending.complete(wire.FindMessageResponse());
    await expectLater(call, throwsA(isA<CancelledException>()));
  });
}
