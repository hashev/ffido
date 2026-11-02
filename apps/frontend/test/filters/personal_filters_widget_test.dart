import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fixnum/fixnum.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/message_screen.dart';
import 'package:fido/models/conference.dart';
import 'package:fido/pages/personal_message_filters_screen.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/repositories/personal_message_filters_repository.dart';

import '../support/fake_transport.dart';
import '../widgets/command_scope_test.dart' show chord;
import 'personal_filters_repository_test.dart'
    show filterRule, collapsedRow, collapsedPresentation;

void main() {
  late FakeTransport api;
  late Set<String> read;
  late wire.PersonalMessageFilterSet settings;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeTransport();
    read = {};
    settings = wire.PersonalMessageFilterSet(
      revision: Int64.ONE,
      rules: [filterRule()],
    );
    api.filters = () async => settings.deepCopy();
    api.conferences = (_) async => wire.ListConferencesResponse(
      conferences: [wire.Conference(id: 'ECHO', name: 'Echo', canRead: true)],
    );
    api.messages = (_) async => wire.ListMessagesResponse(
      messages: [
        for (final id in ['g#1', 'g#2'])
          collapsedRow(id)
            ..subject = 'Noise $id'
            ..isRead = read.contains(id),
      ],
    );
    api.presentation = (r) async {
      if (!r.reveal) {
        return collapsedPresentation(r.message.messageId)
          ..collapsed.subject = 'Noise ${r.message.messageId}';
      }
      read.add(r.message.messageId);
      return wire.MessagePresentation(
        rulesRevision: settings.revision,
        visible: wire.Message(
          id: r.message.messageId,
          conferenceId: 'ECHO',
          subject: 'Noise ${r.message.messageId}',
          body: 'secret body',
          fromName: 'Автор',
          isRead: true,
        ),
        matches: r.searchQuery.isEmpty
            ? []
            : [
                wire.SearchMatch(
                  field_1: wire.MessageSearchField.MESSAGE_SEARCH_BODY,
                  lengthUtf16: 6,
                ),
              ],
      );
    };
    api.replaceFilters = (r) async {
      if (r.expectedRevision != settings.revision) {
        throw const ApiException(statusCode: 10, message: 'conflict');
      }
      settings = wire.PersonalMessageFilterSet(
        revision: settings.revision + Int64.ONE,
        rules: r.rules.map((r) => r.deepCopy()),
      );
      return wire.ReplacePersonalMessageFiltersResponse(
        revision: settings.revision,
      );
    };
  });
  tearDown(() => api.dispose());
  Future<void> reader(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MessageScreen(
          conferenceId: 'ECHO',
          conferenceName: 'Echo',
          conferenceDescription: '',
          canRead: true,
          canPost: true,
          repository: MessageRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'unread navigation stops without reading; reveal only on explicit Show and shortcuts blocked',
    (tester) async {
      await reader(tester);
      expect(find.textContaining('Письмо свернуто'), findsNWidgets(2));
      await tester.tap(find.text('Noise g#1'));
      await tester.pumpAndSettle();
      expect(read, isEmpty);
      expect(find.text('Показать'), findsOneWidget);
      expect(find.text('secret body'), findsNothing);
      await chord(tester, LogicalKeyboardKey.keyR);
      expect(find.text('secret body'), findsNothing);
      await chord(tester, LogicalKeyboardKey.keyU);
      expect(read, isEmpty);
      expect(find.text('Noise g#2'), findsOneWidget);
      await chord(tester, LogicalKeyboardKey.keyU);
      expect(read, isEmpty);
      await tester.tap(find.text('Показать'));
      await tester.pumpAndSettle();
      expect(read, {'g#2'});
      expect(find.textContaining('secret body'), findsOneWidget);
      expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
      await chord(tester, LogicalKeyboardKey.keyL);
      expect(find.text('Noise g#1'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    'filter-aware search keeps cursor collapsed and highlights only explicit reveal',
    (tester) async {
      api.find = (r) async => wire.FindMessageResponse(
        message: collapsedRow(r.includeStart ? 'g#1' : 'g#2'),
      );
      await reader(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Найти далее'));
      await tester.pumpAndSettle();
      expect(read, isEmpty);
      expect(find.text('Показать'), findsOneWidget);
      expect(find.textContaining('secret body'), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Найти далее'));
      await tester.pumpAndSettle();
      final continued = api.calls.whereType<wire.FindMessageRequest>().last;
      expect(continued.includeStart, isFalse);
      expect(continued.startMessageId, 'g#1');
      expect(read, isEmpty);

      await tester.tap(find.text('Показать'));
      await tester.pumpAndSettle();
      expect(read, {'g#2'});
      final reveal = api.calls
          .whereType<wire.GetMessagePresentationRequest>()
          .last;
      expect(reveal.searchQuery, 'secret');
      expect(reveal.message.messageId, 'g#2');
      expect(reveal.reveal, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    'editor cancellation and explicit save; conflicts keep draft and require refresh',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PersonalMessageFiltersScreen(
            repository: PersonalMessageFiltersRepository(api),
            conferenceId: 'ECHO',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить правило'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Имя автора содержит'),
        'Иван',
      );
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(
        api.calls.whereType<wire.ReplacePersonalMessageFiltersRequest>(),
        isEmpty,
      );
      await tester.tap(find.text('Добавить правило'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Имя автора содержит'),
        'Иван',
      );
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(
        api.calls.whereType<wire.ReplacePersonalMessageFiltersRequest>(),
        isEmpty,
      );
      settings.revision = Int64(2);
      await tester.tap(find.text('Сохранить правила'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Черновик сохранён'), findsOneWidget);
      expect(find.text('Автор: Иван'), findsOneWidget);
      await tester.tap(find.text('Загрузить актуальные'));
      await tester.pumpAndSettle();
      expect(find.text('Автор: Иван'), findsOneWidget);
      await tester.tap(find.text('Сохранить мой набор вместо актуального'));
      await tester.pumpAndSettle();
      expect(settings.rules, hasLength(2));
      expect(settings.rules.last.authorContains, 'Иван');
      expect(
        settings.rules.last.scope,
        wire
            .PersonalMessageFilterScope
            .PERSONAL_MESSAGE_FILTER_SCOPE_CONFERENCE,
      );
      await tester.tap(find.text('Тема: Noise'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Тема содержит'),
        'Other',
      );
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Удалить правило').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить правила'));
      await tester.pumpAndSettle();
      expect(settings.rules, hasLength(1));
      expect(settings.rules.single.enabled, isFalse);
      expect(settings.rules.single.subjectContains, 'Other');
    },
  );
  testWidgets(
    'quick rule prefills only selected condition and does not save until confirmed',
    (tester) async {
      await reader(tester);
      await tester.tap(find.byTooltip('Действия письма').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Свернуть по автору'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Имя автора содержит'),
            )
            .controller!
            .text,
        'Автор',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Тема содержит'))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        api.calls.whereType<wire.ReplacePersonalMessageFiltersRequest>(),
        isEmpty,
      );
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(read, isEmpty);
    },
  );
  testWidgets(
    'removing rule never opens collapsed letter until explicit Open',
    (tester) async {
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [
          wire.Message(
            id: 'g#1',
            conferenceId: 'ECHO',
            subject: 'Noise g#1',
            personalCollapse: wire.PersonalMessageCollapse(
              rulesRevision: settings.revision,
              matchedRuleIds: settings.rules.isEmpty
                  ? []
                  : [filterRule().ruleId],
            ),
          ),
        ],
      );
      final original = api.presentation!;
      api.presentation = (r) async {
        if (settings.rules.isNotEmpty) return original(r);
        read.add(r.message.messageId);
        return wire.MessagePresentation(
          rulesRevision: settings.revision,
          visible: wire.Message(
            id: r.message.messageId,
            conferenceId: 'ECHO',
            subject: 'Noise g#1',
            body: 'secret body',
            isRead: true,
          ),
          matches: r.searchQuery.isEmpty
              ? []
              : [
                  wire.SearchMatch(
                    field_1: wire.MessageSearchField.MESSAGE_SEARCH_BODY,
                    lengthUtf16: 6,
                  ),
                ],
        );
      };
      api.find = (_) async =>
          wire.FindMessageResponse(message: collapsedRow('g#1'));
      await reader(tester);
      await tester.tap(find.byTooltip('Поиск по письмам'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Найти далее'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Управление правилами'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Удалить правило'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить правила'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(read, isEmpty);
      expect(find.text('Открыть'), findsOneWidget);
      expect(find.textContaining('secret body'), findsNothing);
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(read, {'g#1'});
      expect(
        api.calls
            .whereType<wire.GetMessagePresentationRequest>()
            .last
            .searchQuery,
        'secret',
      );
    },
  );
  testWidgets(
    'next echo applies destination rules without marking selected collapsed letter',
    (tester) async {
      api.conference = (r) async => wire.Conference(
        id: r.conferenceId,
        canRead: true,
        unreadCount: Int64.ONE,
      );
      api.messages = (r) async => wire.ListMessagesResponse(
        messages: [
          collapsedRow(r.conferenceId == 'ECHO' ? 'g#1' : 'g#2')
            ..conferenceId = r.conferenceId
            ..subject = '${r.conferenceId} message',
        ],
      );
      api.presentation = (r) async => collapsedPresentation(r.message.messageId)
        ..collapsed.message.conferenceId = r.message.conferenceId
        ..collapsed.subject = '${r.message.conferenceId} message';
      Conference area(String id) => Conference(
        id: id,
        name: id,
        description: '',
        unreadCount: 1,
        totalCount: 1,
        canRead: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MessageScreen(
            conferenceId: 'ECHO',
            conferenceName: 'ECHO',
            conferenceDescription: '',
            canRead: true,
            conferenceOrder: [area('ECHO'), area('OTHER')],
            repository: MessageRepository(api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ECHO message'));
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.keyU);
      expect(find.text('OTHER message'), findsOneWidget);
      expect(find.text('Показать'), findsOneWidget);
      expect(read, isEmpty);
      expect(
        api.calls
            .whereType<wire.GetMessagePresentationRequest>()
            .last
            .message
            .conferenceId,
        'OTHER',
      );
      expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    'thread rows preserve collapsed neighbours and selection position',
    (tester) async {
      api.thread = (r) async {
        expect(r.respectPersonalFilters, isTrue);
        return wire.ListMessagesResponse(
          messages: [
            collapsedRow('g#1')..subject = 'Thread one',
            collapsedRow('g#2')..subject = 'Thread two',
          ],
        );
      };
      await reader(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Показать').first);
      await tester.pumpAndSettle();
      expect(read, {'g#1'});
      await tester.tap(find.text('Цепочка сообщений'));
      await tester.pumpAndSettle();
      expect(find.text('Thread one'), findsOneWidget);
      expect(find.text('Thread two'), findsOneWidget);
      await tester.tap(find.text('Thread two'));
      await tester.pumpAndSettle();
      expect(find.text('Показать'), findsOneWidget);
      expect(read, {'g#1'});
    },
  );
  testWidgets(
    'refresh while editing exposes concurrent change before any replacement',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PersonalMessageFiltersScreen(
            repository: PersonalMessageFiltersRepository(api),
            conferenceId: 'ECHO',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить правило'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Имя автора содержит'),
        'Local draft',
      );
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      settings = wire.PersonalMessageFilterSet(
        revision: Int64(2),
        rules: [filterRule(subject: 'Remote change')],
      );
      await tester.tap(find.byTooltip('Обновить правила'));
      await tester.pumpAndSettle();
      expect(
        find.text('Сохранить мой набор вместо актуального'),
        findsOneWidget,
      );
      expect(find.text('Автор: Local draft'), findsOneWidget);
      expect(
        api.calls.whereType<wire.ReplacePersonalMessageFiltersRequest>(),
        isEmpty,
      );
      await tester.tap(find.text('Актуальные правила сервера'));
      await tester.pumpAndSettle();
      expect(find.text('Тема: Remote change'), findsOneWidget);
    },
  );
  testWidgets('session change closes an open editor and discards old rules', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PersonalMessageFiltersScreen(
                    repository: PersonalMessageFiltersRepository(api),
                  ),
                ),
              ),
              child: const Text('Manage'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить правило'));
    await tester.pumpAndSettle();
    api.switchSession();
    await tester.pumpAndSettle();
    expect(find.byType(PersonalMessageFiltersScreen), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
  for (final width in [390.0, 1280.0]) {
    for (final theme in [Brightness.light, Brightness.dark]) {
      testWidgets('collapsed view is adaptive $width $theme', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final longTitle = 'Я' * 128;
        settings.rules.single.subjectContains = longTitle;
        api.messages = (_) async => wire.ListMessagesResponse(
          messages: [collapsedRow('g#1')..subject = longTitle],
        );
        api.presentation = (r) async =>
            collapsedPresentation(r.message.messageId)
              ..collapsed.subject = longTitle;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: theme),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: MessageScreen(
              conferenceId: 'ECHO',
              conferenceName: 'Echo',
              conferenceDescription: '',
              canRead: true,
              repository: MessageRepository(api),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(longTitle));
        await tester.pumpAndSettle();
        expect(find.text('Показать'), findsOneWidget);
        await tester.ensureVisible(find.text('Показать'));
        await tester.pumpAndSettle();
        expect(find.text('Показать').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('late reveal after close cannot repopulate another screen', (
    tester,
  ) async {
    final pending = Completer<wire.MessagePresentation>();
    await reader(tester);
    await tester.tap(find.text('Noise g#1'));
    await tester.pumpAndSettle();
    api.presentation = (_) => pending.future;
    await tester.tap(find.text('Показать'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('Other')));
    pending.complete(
      wire.MessagePresentation(
        rulesRevision: Int64.ONE,
        visible: wire.Message(
          id: 'g#1',
          conferenceId: 'ECHO',
          body: 'secret body',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Other'), findsOneWidget);
    expect(find.textContaining('secret body'), findsNothing);
  });
}
