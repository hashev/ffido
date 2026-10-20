import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';

void main() {
  testWidgets('missing permissions deny both actions', (tester) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MessageScreen(
          conferenceId: 'echo',
          conferenceName: 'Echo',
          conferenceDescription: '',
          repository: MessageRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(find.byTooltip('Новое сообщение'), findsNothing);
    expect(find.text('Нет доступа к конференции'), findsOneWidget);
  });
  testWidgets('read-only hides creation and reply actions', (tester) async {
    final api = FakeTransport()
      ..messages = (_) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: '1', subject: 'Subject')],
      );
    api.message = (_) async => wire.Message(id: '1', body: 'Body');
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MessageScreen(
          conferenceId: 'echo',
          conferenceName: 'Echo',
          conferenceDescription: '',
          canRead: true,
          canPost: false,
          repository: MessageRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Новое сообщение'), findsNothing);
    await tester.tap(find.text('Subject'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Ответить в эху'), findsNothing);
    expect(find.text('Ответить всем'), findsNothing);
    expect(find.text('Переслать'), findsOneWidget);
  });
  testWidgets(
    'write-only sends without reading and preserves draft on denial',
    (tester) async {
      final api = FakeTransport()
        ..create = (_) async =>
            throw const ApiException(message: 'Нет доступа', statusCode: 7);
      addTearDown(api.dispose);
      var invalidations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MessageScreen(
            conferenceId: 'echo',
            conferenceName: 'Echo',
            conferenceDescription: '',
            canRead: false,
            canPost: true,
            repository: MessageRepository(api),
            onAccessDenied: () async {
              invalidations++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.calls, isEmpty);
      expect(find.byTooltip('Обновить'), findsNothing);
      await tester.tap(find.byTooltip('Новое сообщение'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(2), 'Subject');
      await tester.enterText(fields.at(3), 'Draft');
      await tester.ensureVisible(find.text('Отправить'));
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      expect(invalidations, 1);
      expect(find.text('Нет доступа'), findsOneWidget);
      expect(tester.widget<TextField>(fields.at(3)).controller!.text, 'Draft');
      expect(tester.widget<TextField>(fields.at(3)).enabled, isTrue);
      expect(api.calls.whereType<wire.ListMessagesRequest>(), isEmpty);
      expect(api.calls.whereType<wire.GetThreadRequest>(), isEmpty);
      api.create = null;
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      expect(
        api.calls.whereType<wire.CreateMessageRequest>().last.inReplyTo,
        isEmpty,
      );
      expect(api.calls.whereType<wire.ListMessagesRequest>(), isEmpty);
    },
  );
  testWidgets('denied refresh removes selected content and list', (
    tester,
  ) async {
    final api = FakeTransport()
      ..messages = (_) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: '1', subject: 'Subject')],
      );
    api.message = (_) async => wire.Message(id: '1', body: 'Private body');
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MessageScreen(
          conferenceId: 'echo',
          conferenceName: 'Echo',
          conferenceDescription: '',
          canRead: true,
          canPost: true,
          repository: MessageRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subject'));
    await tester.pumpAndSettle();
    api.messages = (_) async =>
        throw const ApiException(message: 'Нет доступа', statusCode: 7);
    await tester.tap(find.byTooltip('Обновить'));
    await tester.pumpAndSettle();
    expect(find.text('Private body'), findsNothing);
    expect(find.text('Subject'), findsNothing);
    expect(find.text('Нет доступа'), findsOneWidget);
  });
}
