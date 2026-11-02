import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/api_transport.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/repositories/personal_message_filters_repository.dart';

import '../support/fake_transport.dart';

wire.PersonalMessageFilter filterRule({String subject = 'Noise'}) =>
    wire.PersonalMessageFilter(
      ruleId: '00000000-0000-4000-8000-000000000001',
      enabled: true,
      scope: wire
          .PersonalMessageFilterScope
          .PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS,
      subjectContains: subject,
    );
wire.Message collapsedRow(String id) => wire.Message(
  id: id,
  conferenceId: 'ECHO',
  subject: 'Noise',
  fromName: 'Автор',
  personalCollapse: wire.PersonalMessageCollapse(
    rulesRevision: Int64.ONE,
    matchedRuleIds: [filterRule().ruleId],
  ),
);
wire.MessagePresentation collapsedPresentation(String id) =>
    wire.MessagePresentation(
      rulesRevision: Int64.ONE,
      matchedRuleIds: [filterRule().ruleId],
      collapsed: wire.CollapsedMessageHeaders(
        message: wire.MessageReference(conferenceId: 'ECHO', messageId: id),
        subject: 'Noise',
        fromName: 'Автор',
      ),
    );
void main() {
  late FakeTransport api;
  late PersonalMessageFiltersRepository repo;
  setUp(() {
    api = FakeTransport();
    repo = PersonalMessageFiltersRepository(api);
  });
  tearDown(() => api.dispose());
  test(
    'empty, unavailable and old server are distinct; profile reset drops rules',
    () async {
      expect(await repo.ensure(), isFalse);
      api.switchSession();
      api.filters = () async => throw const NetworkException();
      await expectLater(repo.refresh(), throwsA(isA<NetworkException>()));
      expect(repo.supported, isNull);
      api.filters = () async => wire.PersonalMessageFilterSet(
        revision: Int64.ONE,
        rules: [filterRule()],
      );
      await repo.refresh();
      expect(repo.snapshot!.rules.single.subjectContains, 'Noise');
      api.endpoint = Uri.parse('https://another.invalid');
      expect(repo.snapshot, isNull);
      expect(repo.supported, isNull);
      api.switchSession();
      expect(repo.snapshot, isNull);
      expect(repo.supported, isNull);
    },
  );
  test('same operation survives lost response; CAS conflict has no automatic retry', () async {
    var state = wire.PersonalMessageFilterSet();
    api.filters = () async => state;
    final request = wire.ReplacePersonalMessageFiltersRequest(
      expectedRevision: Int64.ZERO,
      operationId: 'same',
      rules: [filterRule()],
    );
    var attempts = 0;
    api.replaceFilters = (r) async {
      attempts++;
      expect(r.operationId, 'same');
      state = wire.PersonalMessageFilterSet(
        revision: Int64.ONE,
        rules: r.rules,
      );
      if (attempts == 1) throw const NetworkException();
      return wire.ReplacePersonalMessageFiltersResponse(revision: Int64.ONE);
    };
    await expectLater(repo.save(request), throwsA(isA<NetworkException>()));
    await repo.save(request);
    expect(attempts, 2);
    expect(repo.snapshot!.revision, Int64.ONE);
    api.replaceFilters = (_) async {
      attempts++;
      throw const ApiException(statusCode: 10, message: 'conflict');
    };
    await expectLater(repo.save(request), throwsA(isA<ApiException>()));
    expect(attempts, 3);
  });
  test('two devices share confirmed settings only after refresh; stale and late answers rejected', () async {
    var state = wire.PersonalMessageFilterSet();
    api.filters = () async => state;
    final second = PersonalMessageFiltersRepository(api);
    await repo.refresh();
    await second.refresh();
    api.replaceFilters = (r) async {
      state = wire.PersonalMessageFilterSet(
        revision: Int64.ONE,
        rules: r.rules,
      );
      return wire.ReplacePersonalMessageFiltersResponse(revision: Int64.ONE);
    };
    await repo.save(
      wire.ReplacePersonalMessageFiltersRequest(
        operationId: 'one',
        rules: [filterRule()],
      ),
    );
    expect(second.snapshot!.rules, isEmpty);
    await second.refresh();
    expect(second.snapshot!.rules, hasLength(1));
    api.filters = () async => wire.PersonalMessageFilterSet();
    await expectLater(repo.refresh(), throwsA(isA<ServerException>()));
    final pending = Completer<wire.PersonalMessageFilterSet>();
    api.filters = () => pending.future;
    final call = repo.refresh();
    final assertion = expectLater(call, throwsA(isA<CancelledException>()));
    api.switchSession();
    pending.complete(state);
    await assertion;
    expect(repo.snapshot, isNull);
  });
  test('unsigned revision and validator keep protocol bounds', () async {
    api.filters = () async => wire.PersonalMessageFilterSet(
      revision: Int64(-1),
      rules: [filterRule()],
    );
    await repo.refresh();
    expect(repo.snapshot!.revision.toStringUnsigned(), '18446744073709551615');
    api.filters = () async =>
        wire.PersonalMessageFilterSet(revision: Int64.ONE);
    await expectLater(repo.refresh(), throwsA(isA<ServerException>()));
    for (final rule in [
      filterRule(subject: ''),
      filterRule()..addressEquals = '2:1/2*',
      filterRule(subject: 'Ж' * 129),
      filterRule()
        ..scope = wire
            .PersonalMessageFilterScope
            .PERSONAL_MESSAGE_FILTER_SCOPE_UNSPECIFIED,
    ]) {
      expect(
        () => PersonalMessageFiltersRepository.validateRule(rule),
        throwsA(isA<ValidationException>()),
      );
    }
  });
  test('presentation is explicit and never uses ordinary GetMessage for collapsed result', () async {
    final messages = MessageRepository(api);
    api.filters = () async => wire.PersonalMessageFilterSet(
      revision: Int64.ONE,
      rules: [filterRule()],
    );
    api.presentation = (r) async => collapsedPresentation(r.message.messageId);
    api.message = (_) async => throw StateError('must not read');
    final value = await messages.getMessage(
      conferenceId: 'ECHO',
      messageId: 'g#1',
    );
    expect(value.isCollapsed, isTrue);
    expect(value.body, isEmpty);
    expect(value.isRead, isFalse);
    expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
    api.presentation = (_) async => wire.MessagePresentation();
    await expectLater(
      messages.getPresentation(conferenceId: 'ECHO', messageId: 'g#1'),
      throwsA(isA<ServerException>()),
    );
    api.presentation = (_) async => collapsedPresentation('other#1');
    await expectLater(
      messages.getPresentation(conferenceId: 'ECHO', messageId: 'g#1'),
      throwsA(isA<ServerException>()),
    );
    api.presentation = (_) async => collapsedPresentation('g#1');
    await expectLater(
      messages.getPresentation(
        conferenceId: 'ECHO',
        messageId: 'g#1',
        reveal: true,
      ),
      throwsA(isA<ServerException>()),
    );
    final pending = Completer<wire.MessagePresentation>();
    api.presentation = (_) => pending.future;
    final token = RpcCancellation();
    final call = messages.getPresentation(
      conferenceId: 'ECHO',
      messageId: 'g#1',
      cancellation: token,
    );
    final assertion = expectLater(call, throwsA(isA<CancelledException>()));
    await token.cancel();
    pending.complete(collapsedPresentation('g#1'));
    await assertion;
  });
  test('filter-aware search returns collapsed cursor without ranges; reveal uses same reference and search context', () async {
    final messages = MessageRepository(api);
    api.filters = () async => wire.PersonalMessageFilterSet(
      revision: Int64.ONE,
      rules: [filterRule()],
    );
    api.find = (r) async {
      expect(r.respectPersonalFilters, isTrue);
      return wire.FindMessageResponse(message: collapsedRow('g#1'));
    };
    final result = await messages.findMessage(
      conferenceId: 'ECHO',
      query: 'body',
    );
    expect(result!.message.isCollapsed, isTrue);
    expect(result.matches, isEmpty);
    expect(result.firstField, 0);
    api.presentation = (r) async {
      expect(r.message.messageId, 'g#1');
      expect(r.reveal, isTrue);
      expect(r.searchQuery, 'body');
      return wire.MessagePresentation(
        rulesRevision: Int64.ONE,
        visible: wire.Message(
          id: 'g#1',
          conferenceId: 'ECHO',
          body: 'body',
          isRead: true,
        ),
        matches: [
          wire.SearchMatch(
            field_1: wire.MessageSearchField.MESSAGE_SEARCH_BODY,
            lengthUtf16: 4,
          ),
        ],
      );
    };
    final revealed = await messages.getPresentation(
      conferenceId: 'ECHO',
      messageId: 'g#1',
      reveal: true,
      query: 'body',
    );
    expect(revealed.message.isRead, isTrue);
    expect(revealed.matches[6]!.single.end, 4);
  });
}
