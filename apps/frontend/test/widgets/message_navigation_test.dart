import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';
import '../support/fake_transport.dart';

wire.Message row(String id) =>
    wire.Message(id: id, subject: 'Тема $id', body: 'Тело $id');
Widget screen(FakeTransport api) => MaterialApp(
  home: MessageScreen(
    conferenceId: 'echo',
    conferenceName: 'Эха',
    conferenceDescription: '',
    canRead: true,
    canPost: true,
    repository: MessageRepository(api),
  ),
);
Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('navigation crosses pages, preserves order and returns to list', (
    tester,
  ) async {
    final api = FakeTransport()
      ..messages = (r) async => wire.ListMessagesResponse(
        messages: [row(r.page.offset.toInt() == 0 ? 'g#42' : 'g#99')],
        hasMore: r.page.offset.toInt() == 0,
      );
    api.message = (r) async => row(r.messageId);
    addTearDown(api.dispose);
    await tester.pumpWidget(screen(api));
    await tester.pumpAndSettle();
    await tap(tester, 'Тема g#42');
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Предыдущее'))
          .onPressed,
      isNull,
    );
    await tap(tester, 'Следующее');
    expect(find.text('Тело g#99'), findsOneWidget);
    expect(
      api.calls.whereType<wire.ListMessagesRequest>().last.page.offset.toInt(),
      1,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Следующее'))
          .onPressed,
      isNull,
    );
    await tap(tester, 'Предыдущее');
    expect(find.text('Тело g#42'), findsOneWidget);
    await tap(tester, 'К списку');
    expect(find.text('Тема g#99'), findsOneWidget);
  });
  testWidgets(
    'failed detail keeps current letter and retries without parallel calls',
    (tester) async {
      final pending = Completer<wire.Message>();
      final api = FakeTransport()
        ..messages = (_) async =>
            wire.ListMessagesResponse(messages: [row('a'), row('b')]);
      api.message = (r) =>
          r.messageId == 'a' ? Future.value(row('a')) : pending.future;
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Тема a');
      await tester.tap(find.text('Следующее'));
      await tester.pump();
      expect(find.text('Тело a'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Следующее'))
            .onPressed,
        isNull,
      );
      pending.completeError(const NetworkException());
      await tester.pumpAndSettle();
      api.message = (r) async => row(r.messageId);
      await tap(tester, 'Повторить');
      expect(find.text('Тело b'), findsOneWidget);
    },
  );
  testWidgets(
    'duplicate and empty pages terminate and stale detail suggests refresh',
    (tester) async {
      final api = FakeTransport()
        ..messages = (_) async =>
            wire.ListMessagesResponse(messages: [row('a')], hasMore: true);
      api.message = (r) async => row(r.messageId);
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Тема a');
      await tap(tester, 'Следующее');
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Следующее'))
            .onPressed,
        isNull,
      );
      await tap(tester, 'К списку');
      api.message = (_) async => throw const NotFoundException();
      await tap(tester, 'Тема a');
      expect(find.textContaining('Список устарел'), findsOneWidget);
      await tap(tester, 'Повторить');
      expect(find.text('Тема a'), findsOneWidget);
    },
  );
  testWidgets(
    'thread navigation stays in thread and late detail cannot cross sessions',
    (tester) async {
      final api = FakeTransport()
        ..messages = (_) async =>
            wire.ListMessagesResponse(messages: [row('a')]);
      api.thread = (_) async =>
          wire.ListMessagesResponse(messages: [row('a'), row('c')]);
      api.message = (r) async => row(r.messageId);
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Тема a');
      await tap(tester, 'Цепочка сообщений');
      await tap(tester, 'Тема a');
      await tap(tester, 'Следующее');
      expect(find.text('Тело c'), findsOneWidget);
      final pending = Completer<wire.Message>();
      api.message = (_) => pending.future;
      await tester.tap(find.text('Предыдущее'));
      await tester.pump();
      api.messages = (_) async => wire.ListMessagesResponse();
      api.switchSession();
      pending.complete(row('a'));
      await tester.pumpAndSettle();
      expect(find.text('Тело a'), findsNothing);
    },
  );
  testWidgets(
    'narrow reader keeps bottom navigation visible and handles denied transition',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeTransport();
      api.messages = (_) async =>
          wire.ListMessagesResponse(messages: [row('a'), row('b')]);
      api.message = (r) async => r.messageId == 'a'
          ? wire.Message(
              id: 'a',
              subject: 'Тема a',
              body: List.filled(100, '> цитата').join('\n'),
            )
          : throw const ServerException(statusCode: 7);
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Тема a');
      expect(find.text('Следующее').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, 'Следующее');
      expect(find.byType(SelectableText), findsNothing);
    },
  );
  testWidgets(
    'page error retry completes transition and empty page ends navigation',
    (tester) async {
      final api = FakeTransport();
      var fail = true;
      api.messages = (r) async {
        if (r.page.offset.toInt() == 0) {
          return wire.ListMessagesResponse(messages: [row('a')], hasMore: true);
        }
        if (fail) throw const NetworkException();
        return wire.ListMessagesResponse(messages: [row('b')], hasMore: true);
      };
      api.message = (r) async => row(r.messageId);
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Тема a');
      await tap(tester, 'Следующее');
      expect(find.text('Тело a'), findsOneWidget);
      fail = false;
      await tap(tester, 'Повторить');
      expect(find.text('Тело b'), findsOneWidget);
      api.messages = (_) async => wire.ListMessagesResponse(hasMore: true);
      await tap(tester, 'Следующее');
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Следующее'))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'changed JAM generation requires refresh instead of mixing pages',
    (tester) async {
      final api = FakeTransport();
      api.messages = (r) async => wire.ListMessagesResponse(
        messages: [row(r.page.offset.toInt() == 0 ? 'old#42' : 'new#43')],
        hasMore: true,
      );
      api.message = (r) async => row(r.messageId);
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Тема old#42');
      await tap(tester, 'Следующее');
      expect(find.text('Тело old#42'), findsOneWidget);
      expect(find.textContaining('Список устарел'), findsOneWidget);
      api.messages = (_) async =>
          wire.ListMessagesResponse(messages: [row('new#43')]);
      await tap(tester, 'Повторить');
      expect(find.text('Тема new#43'), findsOneWidget);
      expect(find.text('Тело old#42'), findsNothing);
    },
  );
}
