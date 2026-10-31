import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';
import '../support/message_identity.dart';

Widget screen(FakeTransport api) => MaterialApp(
  home: MessageScreen(
    canRead: true,
    canPost: true,
    conferenceId: 'id',
    conferenceName: 'Название',
    conferenceDescription: 'Описание',
    repository: MessageRepository(api),
  ),
);
void main() {
  setUp(mockMessageIdentity);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('list reads detail, records RPC identity and supports threads', (
    tester,
  ) async {
    final api = FakeTransport()
      ..messages = (_) async => wire.ListMessagesResponse(
        messages: [
          wire.Message(
            id: 'generation#42',
            subject: 'Тема',
            fromName: 'Автор',
            bodyPreview: 'Превью',
          ),
        ],
      );
    api.message = (r) async => wire.Message(
      id: r.messageId,
      fromName: 'Автор',
      fromAddress: '2:1/2',
      toName: 'All',
      subject: 'Тема',
      body: 'Полный текст',
    );
    addTearDown(api.dispose);
    await tester.pumpWidget(screen(api));
    await tester.pumpAndSettle();
    expect(find.text('Тема'), findsOneWidget);
    await tester.tap(find.text('Тема'));
    await tester.pumpAndSettle();
    expect(find.text('Полный текст'), findsOneWidget);
    expect((api.calls.last as wire.MessageReference).conferenceId, 'id');
    expect(
      (api.calls.last as wire.MessageReference).messageId,
      'generation#42',
    );
    await tester.tap(find.text('Цепочка сообщений'));
    await tester.pumpAndSettle();
    expect(api.calls.last, isA<wire.GetThreadRequest>());
  });
  testWidgets(
    'reader preserves layout and shows addresses without empty brackets',
    (tester) async {
      const body = 'Привет!\n\n DP> Цитата\n  отступ\nПодпись';
      final api = FakeTransport()
        ..messages = (_) async => wire.ListMessagesResponse(
          messages: [
            wire.Message(
              id: 'generation#42',
              subject: 'Тема',
              fromName: 'Автор',
              bodyPreview: body,
            ),
          ],
        );
      api.message = (_) async => wire.Message(
        id: 'generation#42',
        subject: 'Тема',
        fromName: 'Автор',
        fromAddress: '2:5001/100.1',
        toName: 'All',
        body: body,
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      final preview = tester.widget<Text>(
        find.text('Автор\nПривет! DP> Цитата отступ Подпись'),
      );
      expect(preview.maxLines, 3);
      expect(preview.overflow, TextOverflow.ellipsis);
      await tester.tap(find.text('Тема'));
      await tester.pumpAndSettle();
      expect(find.text('От: Автор <2:5001/100.1>'), findsOneWidget);
      expect(find.text('К: All (адрес не указан)'), findsOneWidget);
      expect(find.textContaining('<>'), findsNothing);
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.textSpan!.toPlainText(), body);
      expect(text.style!.height, 1.5);
      expect(text.style!.fontFamily, 'monospace');
      expect(
        text.style!.color,
        Theme.of(tester.element(find.byType(SelectableText)))
            .colorScheme
            .onSurface,
      );
    },
  );
  testWidgets(
    'double submit is blocked and uncertain retry preserves payload',
    (tester) async {
      final pending = Completer<wire.CreateMessageResponse>();
      final api = FakeTransport()..create = (_) => pending.future;
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Новое сообщение'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(2), 'Тема');
      await tester.enterText(fields.at(3), 'Текст');
      await tester.ensureVisible(find.text('Отправить'));
      await tester.tap(find.text('Отправить'));
      await tester.pump();
      expect(
        (tester.widget<ElevatedButton>(find.byType(ElevatedButton))).onPressed,
        isNull,
      );
      expect(api.calls.whereType<wire.CreateMessageRequest>().length, 1);
      pending.completeError(const NetworkException());
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields.at(3)).controller!.text, 'Текст');
      expect(tester.widget<TextField>(fields.at(3)).enabled, isFalse);
      api.create = null;
      await tester.ensureVisible(find.text('Повторить отправку'));
      await tester.tap(find.text('Повторить отправку'));
      await tester.pumpAndSettle();
      final creates = api.calls.whereType<wire.CreateMessageRequest>().toList();
      expect(creates.length, 2);
      expect(creates[0].writeToBuffer(), creates[1].writeToBuffer());
      expect(find.text('Сообщение сохранено локально'), findsOneWidget);
      expect(find.textContaining('доставлено'), findsNothing);
    },
  );
  for (final status in [2, 8, 12, 13, 15, 99]) {
    testWidgets(
      'uncertain status $status keeps operation through quarantine retry',
      (tester) async {
        final api = FakeTransport()
          ..create = (_) async => throw ServerException(statusCode: status);
        addTearDown(api.dispose);
        await tester.pumpWidget(screen(api));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Новое сообщение'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(2), 'Тема');
        await tester.enterText(fields.at(3), 'Текст');
        await tester.ensureVisible(find.text('Отправить'));
        await tester.tap(find.text('Отправить'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(fields.at(3)).enabled, isFalse);
        expect(
          tester.widget<TextField>(fields.at(3)).controller!.text,
          'Текст',
        );
        api.create = (_) async => throw const ServerException(statusCode: 9);
        await tester.ensureVisible(find.text('Повторить отправку'));
        await tester.tap(find.text('Повторить отправку'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(fields.at(3)).enabled, isFalse);
        api.create = null;
        await tester.tap(find.text('Повторить отправку'));
        await tester.pumpAndSettle();
        final creates = api.calls
            .whereType<wire.CreateMessageRequest>()
            .toList();
        expect(creates.length, 3);
        expect(creates[0].writeToBuffer(), creates[1].writeToBuffer());
        expect(creates[0].writeToBuffer(), creates[2].writeToBuffer());
        expect(find.text('Сообщение сохранено локально'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'definite validation failure keeps editable draft and permits correction',
    (tester) async {
      final api = FakeTransport()
        ..create = (_) async => throw const ValidationException();
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Новое сообщение'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(2), 'Тема');
      await tester.enterText(fields.at(3), 'Текст');
      await tester.ensureVisible(find.text('Отправить'));
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(fields.at(3)).enabled, isTrue);
      expect(tester.widget<TextField>(fields.at(3)).controller!.text, 'Текст');
      await tester.enterText(fields.at(3), 'Исправленный текст');
      api.create = null;
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      final creates = api.calls.whereType<wire.CreateMessageRequest>().toList();
      expect(creates[0].operationId, isNot(creates[1].operationId));
      expect(creates[1].body, 'Исправленный текст');
    },
  );
  testWidgets('pagination requests next offset and reload resets list', (
    tester,
  ) async {
    final api = FakeTransport()
      ..messages = (r) async => wire.ListMessagesResponse(
        messages: [
          wire.Message(
            id: '${r.page.offset}',
            subject: 'Страница ${r.page.offset}',
          ),
        ],
        hasMore: r.page.offset.toInt() == 0,
      );
    addTearDown(api.dispose);
    await tester.pumpWidget(screen(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Загрузить ещё'));
    await tester.pumpAndSettle();
    expect((api.calls.last as wire.ListMessagesRequest).page.offset.toInt(), 1);
    expect(find.text('Страница 0'), findsOneWidget);
    expect(find.text('Страница 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Обновить'));
    await tester.pumpAndSettle();
    expect(find.text('Страница 1'), findsNothing);
  });
  testWidgets('old response cannot reappear after session change or dispose', (
    tester,
  ) async {
    final pending = Completer<wire.ListMessagesResponse>();
    final api = FakeTransport()..messages = (_) => pending.future;
    addTearDown(api.dispose);
    await tester.pumpWidget(screen(api));
    api.messages = (_) async => wire.ListMessagesResponse();
    api.switchSession();
    await tester.pumpAndSettle();
    pending.complete(
      wire.ListMessagesResponse(messages: [wire.Message(subject: 'Чужое')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Чужое'), findsNothing);
    final late = Completer<wire.ListMessagesResponse>();
    api.messages = (_) => late.future;
    await tester.tap(find.byTooltip('Обновить'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    late.completeError(const NetworkException());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reply form retains assigned recipient and closes on session change',
    (tester) async {
      final api = FakeTransport();
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: '42', subject: 'Тема')],
      );
      api.message = (_) async => wire.Message(
        id: '42',
        subject: 'Тема',
        fromName: 'Автор',
        fromAddress: '2:1/2',
        body: 'Оригинал',
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тема'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ответить в эху'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, 'Автор');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '2:1/2');
      expect(tester.widget<TextField>(fields.at(0)).enabled, isFalse);
      expect(
        tester.widget<TextField>(fields.at(2)).controller!.text,
        'Re: Тема',
      );
      api.switchSession();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('detail failure is displayed and recoverable', (tester) async {
    final api = FakeTransport();
    api.messages = (_) async => wire.ListMessagesResponse(
      messages: [wire.Message(id: '42', subject: 'Тема')],
    );
    api.message = (_) async => throw const NotFoundException();
    addTearDown(api.dispose);
    await tester.pumpWidget(screen(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тема'));
    await tester.pumpAndSettle();
    expect(find.text('Повторить'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Тема'), findsOneWidget);
  });
}
