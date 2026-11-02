import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/widgets/message_link_text.dart';
import 'package:fido/widgets/search_highlight.dart';

import '../support/fake_transport.dart';

wire.FindMessageResponse found(String id, {String body = '😀 Привет привет'}) =>
    wire.FindMessageResponse(
      message: wire.Message(
        id: id,
        fromName: 'Автор',
        subject: 'Найденное письмо',
        body: body,
        isRead: true,
      ),
      matches: [
        wire.SearchMatch(
          field_1: wire.MessageSearchField.MESSAGE_SEARCH_BODY,
          startUtf16: body.indexOf('Привет'),
          lengthUtf16: 6,
        ),
      ],
    );
Future<void> mount(WidgetTester tester, FakeTransport api) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      home: MessageScreen(
        conferenceId: 'echo',
        conferenceName: 'Эха',
        conferenceDescription: '',
        canRead: true,
        repository: MessageRepository(api),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> search(
  WidgetTester tester, [
  String query = 'Привет',
  bool settle = true,
]) async {
  await tester.tap(find.byTooltip('Поиск по письмам'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), query);
  await tester.tap(find.widgetWithText(FilledButton, 'Найти далее'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets(
    'find opens response without GetMessage, continues exclusively and stops at end',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      var count = 0;
      api.find = (r) async =>
          ++count < 3 ? found('g#$count') : wire.FindMessageResponse();
      await mount(tester, api);
      await search(tester);
      expect(find.text('Найденное письмо'), findsOneWidget);
      expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
      expect(
        api.calls.whereType<wire.FindMessageRequest>().single.includeStart,
        isTrue,
      );
      final text = tester.widget<MessageLinkText>(
        find.byType(MessageLinkText).first,
      );
      expect(text.searchRanges.single.start, 3);
      await tester.tap(find.widgetWithText(TextButton, 'Найти далее'));
      await tester.pumpAndSettle();
      final requests = api.calls.whereType<wire.FindMessageRequest>().toList();
      expect(requests.last.startMessageId, 'g#1');
      expect(requests.last.includeStart, isFalse);
      await tester.tap(find.widgetWithText(TextButton, 'Найти далее'));
      await tester.pumpAndSettle();
      expect(find.text('До конца области совпадений нет'), findsOneWidget);
      expect(find.text('Найденное письмо'), findsOneWidget);
      expect(
        tester
            .widget<MessageLinkText>(find.byType(MessageLinkText).first)
            .searchRanges,
        isEmpty,
      );
      await tester.tap(find.text('Закрыть поиск'));
      await tester.pumpAndSettle();
      expect(find.text('Найти далее'), findsNothing);
    },
  );
  testWidgets('empty query, keyboard entry, unsupported server and retry', (
    tester,
  ) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    api.find = (_) async =>
        throw const ApiException(message: 'unsupported', statusCode: 12);
    await mount(tester, api);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pumpAndSettle();
    expect(find.text('Поиск по письмам'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Найти далее'));
    await tester.pumpAndSettle();
    expect(api.calls.whereType<wire.FindMessageRequest>(), isEmpty);
    await tester.enterText(find.byType(TextField), 'Привет');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.text('Сервер не поддерживает поиск. Обновите сервер.'),
      findsOneWidget,
    );
    api.find = (_) async => found('g#2');
    await tester.tap(find.widgetWithText(TextButton, 'Найти далее'));
    await tester.pumpAndSettle();
    expect(find.text('Найденное письмо'), findsOneWidget);
  });
  testWidgets('cancel and profile switch discard late search results', (
    tester,
  ) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    var pending = Completer<wire.FindMessageResponse>();
    api.find = (_) => pending.future;
    await mount(tester, api);
    await search(tester, 'Привет', false);
    expect(find.text('Отменить поиск'), findsOneWidget);
    await tester.tap(find.text('Отменить поиск'));
    await tester.pump();
    pending.complete(found('g#1'));
    await tester.pumpAndSettle();
    expect(find.text('Найденное письмо'), findsNothing);
    pending = Completer<wire.FindMessageResponse>();
    await tester.tap(find.widgetWithText(TextButton, 'Найти далее'));
    await tester.pump();
    api.switchSession();
    await tester.pumpAndSettle();
    pending.complete(found('g#2'));
    await tester.pumpAndSettle();
    expect(find.text('Найденное письмо'), findsNothing);
    expect(find.text('Поиск: Привет'), findsNothing);
  });
  testWidgets(
    'first body match is revealed using layout after long wrapped text',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      final body =
          '${List.filled(100, 'Длинная строка с переносом текста 😀').join('\n')}\nПривет';
      api.find = (_) async => found('g#1', body: body);
      await mount(tester, api);
      await search(tester);
      final reveals = tester
          .widgetList<SearchReveal>(find.byType(SearchReveal))
          .where((w) => w.enabled && w.offset != null);
      expect(reveals, isNotEmpty);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'manual navigation resets search anchor and chain search preserves failed context',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      final rows = [
        for (var i = 1; i <= 3; i++)
          wire.Message(id: 'g#$i', subject: 'Письмо $i'),
      ];
      api.messages = (_) async => wire.ListMessagesResponse(messages: rows);
      api.message = (r) async => wire.Message(
        id: r.messageId,
        subject: 'Письмо ${r.messageId}',
        body: 'Текст',
      );
      api.thread = (_) async => wire.ListMessagesResponse(messages: rows);
      api.find = (_) async => found('g#2');
      await mount(tester, api);
      await tester.tap(find.text('Письмо 1'));
      await tester.pumpAndSettle();
      await search(tester);
      expect(
        api.calls.whereType<wire.FindMessageRequest>().last.startMessageId,
        'g#1',
      );
      await tester.tap(find.text('Следующее'));
      await tester.pumpAndSettle();
      expect(find.text('Письмо g#3'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Найти далее'));
      await tester.pumpAndSettle();
      final request = api.calls.whereType<wire.FindMessageRequest>().last;
      expect(request.startMessageId, 'g#3');
      expect(request.includeStart, isTrue);
      await tester.tap(find.text('Цепочка сообщений'));
      await tester.pumpAndSettle();
      api.find = (_) async => wire.FindMessageResponse();
      await search(tester);
      expect(find.text('До конца области совпадений нет'), findsOneWidget);
      // Returning to the list after an unsuccessful search still loads the thread.
      expect(api.calls.whereType<wire.GetThreadRequest>(), isNotEmpty);
    },
  );
  testWidgets('network retry keeps the same anchor and header mode is sent', (
    tester,
  ) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    api.find = (_) async => throw const NetworkException();
    await mount(tester, api);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      List.filled(129, 'Я').join(),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Найти далее'));
    await tester.pumpAndSettle();
    expect(api.calls.whereType<wire.FindMessageRequest>(), isEmpty);
    await tester.enterText(find.byType(TextField), 'Привет');
    await tester.tap(find.byType(DropdownButtonFormField<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Заголовки').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Найти далее'));
    await tester.pumpAndSettle();
    final initial = api.calls.whereType<wire.FindMessageRequest>().last;
    expect(initial.scope, wire.MessageSearchScope.MESSAGE_SEARCH_HEADER_ONLY);
    api.find = (_) async => wire.FindMessageResponse();
    await tester.tap(find.widgetWithText(TextButton, 'Найти далее'));
    await tester.pumpAndSettle();
    final retry = api.calls.whereType<wire.FindMessageRequest>().last;
    expect(retry.startMessageId, initial.startMessageId);
    expect(retry.includeStart, initial.includeStart);
  });
  for (final width in [390.0, 1100.0]) {
    testWidgets(
      'match remains visible at width $width with scaled text and manual scroll wins',
      (tester) async {
        tester.view.resetPhysicalSize();
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = FakeTransport();
        addTearDown(api.dispose);
        final body =
            '${List.filled(60, 'Длинный текст с переносами 😀 и проверкой ширины.').join('\n')}\nПривет';
        api.find = (_) async => found('g#1', body: body);
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: MessageScreen(
              conferenceId: 'echo',
              conferenceName: 'Эха',
              conferenceDescription: '',
              canRead: true,
              repository: MessageRepository(api),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await search(tester);
        final bodyText = find.descendant(
          of: find.byType(MessageLinkText),
          matching: find.byType(EditableText),
        );
        final editable = tester.state<EditableTextState>(bodyText);
        final caret = editable.renderEditable.getLocalRectForCaret(
          TextPosition(offset: body.indexOf('Привет')),
        );
        final global = editable.renderEditable.localToGlobal(caret.center);
        expect(global.dy, inInclusiveRange(0, 850));
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, 250),
        );
        await tester.pumpAndSettle();
        final after = scroll.position.pixels;
        // Trigger another layout without a new search result.
        tester.view.physicalSize = Size(width - 10, 850);
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, closeTo(after, 1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
