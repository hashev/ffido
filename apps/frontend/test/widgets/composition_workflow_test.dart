import 'package:fido/updates/update_controller.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/message_screen.dart';
import 'package:fido/pages/forward_destination.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

Future<ConferenceRepository> repository(FakeTransport api) async {
  SharedPreferences.setMockInitialValues({});
  return ConferenceRepository(
    apiClient: api,
    prefs: await SharedPreferences.getInstance(),
  );
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

FakeTransport transport() {
  final api = FakeTransport();
  api.messages = (_) async => wire.ListMessagesResponse(
    messages: [wire.Message(id: 'g#42', subject: 'Оригинал')],
  );
  api.message = (r) async => wire.Message(
    id: r.messageId,
    subject: 'Оригинал',
    fromName: 'Автор',
    fromAddress: '2:1/2',
    body: 'Текст\n AB> Цитата',
  );
  api.conferences = (_) async => wire.ListConferencesResponse(
    conferences: [
      wire.Conference(id: 'target', name: 'Другая эха', canPost: true),
    ],
  );
  api.conference = (r) async =>
      wire.Conference(id: r.conferenceId, name: 'Другая эха', canPost: true);
  return api;
}

Future<void> reader(
  WidgetTester tester,
  FakeTransport api,
  ConferenceRepository repo, {
  bool canPost = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MessageScreen(
        conferenceId: 'source',
        conferenceName: 'Источник',
        conferenceDescription: '',
        canRead: true,
        canPost: canPost,
        repository: MessageRepository(api),
        conferences: repo,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tap(tester, 'Оригинал');
}

void main() {
  testWidgets('открытый редактор защищён от завершения updater', (
    tester,
  ) async {
    final api = transport();
    final repo = await repository(api);
    addTearDown(api.dispose);
    await reader(tester, api, repo);
    await tap(tester, 'Ответить в эху');
    expect(appUpdates.canExit, isFalse);
    final fields = find.byType(TextField);
    await tester.enterText(fields.last, 'Несохранённый текст');
    expect(appUpdates.canExit, isFalse);
    expect(find.text('Несохранённый текст'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(appUpdates.canExit, isTrue);
  });

  testWidgets(
    'public reply edits visible nested quote and sends exactly that body',
    (tester) async {
      final api = transport();
      final repo = await repository(api);
      addTearDown(api.dispose);
      await reader(tester, api, repo);
      expect(find.text('Ответить всем'), findsNothing);
      await tap(tester, 'Ответить в эху');
      expect(find.textContaining('доступен всем'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(
        tester.widget<TextField>(fields.at(3)).controller!.text,
        'А> Текст\n AB>> Цитата\n\n',
      );
      await tester.enterText(fields.at(3), '> Текст\nМой ответ');
      await tap(tester, 'Отправить');
      final sent = api.calls.whereType<wire.CreateMessageRequest>().single;
      expect(sent.conferenceId, 'source');
      expect(sent.inReplyTo, 'g#42');
      expect(sent.toName, 'Автор');
      expect(sent.body, '> Текст\nМой ответ');
    },
  );
  testWidgets(
    'read-only source forwards to paginated post-only target and retry freezes request',
    (tester) async {
      final api = transport();
      final repo = await repository(api);
      addTearDown(api.dispose);
      api.conferences = (r) async => r.page.offset.toInt() == 0
          ? wire.ListConferencesResponse(
              conferences: [
                wire.Conference(
                  id: 'read',
                  name: 'Только чтение',
                  canRead: true,
                ),
              ],
              hasMore: true,
            )
          : wire.ListConferencesResponse(
              conferences: [
                wire.Conference(
                  id: 'target',
                  name: 'Другая эха',
                  canPost: true,
                ),
              ],
            );
      await reader(tester, api, repo, canPost: false);
      expect(find.text('Ответить в эху'), findsNothing);
      await tap(tester, 'Переслать');
      expect(find.text('Только чтение'), findsNothing);
      await tap(tester, 'Загрузить ещё');
      await tap(tester, 'Другая эха');
      final fields = find.byType(TextField);
      expect(
        tester.widget<TextField>(fields.at(3)).controller!.text,
        contains('Area: source'),
      );
      await tester.enterText(fields.at(3), 'Комментарий\n> переслано');
      api.create = (_) async => throw const NetworkException();
      await tap(tester, 'Отправить');
      expect(tester.widget<TextField>(fields.at(3)).enabled, isFalse);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Изменить эху назначения'),
            )
            .onPressed,
        isNull,
      );
      api.create = null;
      await tap(tester, 'Повторить отправку');
      final sent = api.calls.whereType<wire.CreateMessageRequest>().toList();
      expect(sent.length, 2);
      expect(sent[0].writeToBuffer(), sent[1].writeToBuffer());
      expect(sent[0].conferenceId, 'target');
      expect(sent[0].inReplyTo, isEmpty);
      expect(sent[0].body, 'Комментарий\n> переслано');
      expect(
        find.textContaining('Текст'),
        findsWidgets,
      ); // Original remains open.
    },
  );
  testWidgets(
    'changing target preserves edits and revoked target keeps draft without send',
    (tester) async {
      final api = transport();
      final repo = await repository(api);
      addTearDown(api.dispose);
      await reader(tester, api, repo);
      await tap(tester, 'Переслать');
      await tap(tester, 'Другая эха');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(3), 'Правки');
      await tap(tester, 'Изменить эху назначения');
      await tap(tester, 'Другая эха');
      expect(tester.widget<TextField>(fields.at(3)).controller!.text, 'Правки');
      api.conference = (r) async =>
          wire.Conference(id: r.conferenceId, canPost: false);
      await tap(tester, 'Отправить');
      expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
      expect(tester.widget<TextField>(fields.at(3)).controller!.text, 'Правки');
      expect(find.text('Эха: не выбрана'), findsOneWidget);
    },
  );
  testWidgets(
    'destination search discards late response and closes on session change',
    (tester) async {
      final api = transport();
      final repo = await repository(api);
      addTearDown(api.dispose);
      final pending = Completer<wire.ListConferencesResponse>();
      api.conferences = (_) => pending.future;
      await tester.pumpWidget(
        MaterialApp(home: ForwardDestination(repository: repo)),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'новая');
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [wire.Conference(id: 'new', name: 'Новая', canPost: true)],
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      pending.complete(
        wire.ListConferencesResponse(
          conferences: [
            wire.Conference(id: 'old', name: 'Старая', canPost: true),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Новая'), findsOneWidget);
      expect(find.text('Старая'), findsNothing);
      api.switchSession();
      await tester.pumpAndSettle();
      expect(find.text('Новая'), findsNothing);
    },
  );
  testWidgets(
    'cancel and empty chooser never send; server ACL denial keeps editable draft',
    (tester) async {
      final api = transport();
      final repo = await repository(api);
      addTearDown(api.dispose);
      await reader(tester, api, repo);
      await tap(tester, 'Переслать');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
      await tap(tester, 'Переслать');
      await tap(tester, 'Другая эха');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(3), 'Черновик');
      api.create = (_) async => throw const ServerException(statusCode: 7);
      await tap(tester, 'Отправить');
      expect(tester.widget<TextField>(fields.at(3)).enabled, isTrue);
      expect(
        tester.widget<TextField>(fields.at(3)).controller!.text,
        'Черновик',
      );
      expect(find.text('Эха: не выбрана'), findsOneWidget);
      api.conferences = (_) async => wire.ListConferencesResponse();
      await repo.clearCache();
      await tap(tester, 'Изменить эху назначения');
      expect(find.text('Нет доступных для публикации эх'), findsOneWidget);
    },
  );
}
