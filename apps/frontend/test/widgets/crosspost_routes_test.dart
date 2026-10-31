import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/reader_app.dart';
import 'package:fido/pages/personal_conferences.dart';
import 'package:fido/pages/crosspost_destinations.dart';
import 'package:fido/repositories/account_repository.dart';
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';
import '../support/message_identity.dart';

wire.Conference area(String id) => wire.Conference(
  id: id,
  name: id,
  canRead: true,
  canPost: true,
  unreadCount: Int64(1),
);
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(mockMessageIdentity);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final source in ['home', 'bookmarks', 'history']) {
    for (final mode in ['new', 'reply', 'forward']) {
      testWidgets(
        '$source -> $mode -> crosspost confirmation uses same transport',
        (tester) async {
          final api = FakeTransport();
          addTearDown(api.dispose);
          api.conferences = (_) async => wire.ListConferencesResponse(
            conferences: [area('A'), area('B'), area('C')],
          );
          api.bookmarks = (_) async => wire.ListBookmarksResponse(
            bookmarks: [wire.Bookmark(conference: area('A'))],
          );
          api.history = (_) async => wire.ListHistoryResponse(
            history: [wire.HistoryEntry(conference: area('A'))],
          );
          api.messages = (_) async => wire.ListMessagesResponse(
            messages: [wire.Message(id: 'g#1', subject: 'Letter')],
          );
          api.message = (r) async =>
              wire.Message(id: r.messageId, subject: 'Letter', body: 'Body');
          final repository = ConferenceRepository(
            apiClient: api,
            prefs: await SharedPreferences.getInstance(),
          );
          addTearDown(repository.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: source == 'home'
                  ? MainScreen(repository: repository)
                  : PersonalConferences(
                      history: source == 'history',
                      repository: AccountRepository(api),
                    ),
            ),
          );
          await tester.pumpAndSettle();
          await tap(tester, find.text('A'));
          if (mode == 'new') {
            await tap(tester, find.byTooltip('Новое сообщение'));
          } else {
            await tap(tester, find.text('Letter'));
            await tap(
              tester,
              find.text(mode == 'reply' ? 'Ответить в эху' : 'Переслать'),
            );
            if (mode == 'forward') await tap(tester, find.text('B').first);
          }
          final menu = tester.widget<PopupMenuButton<String>>(
            find.byType(PopupMenuButton<String>),
          );
          expect(menu.enabled, isTrue);
          await tap(tester, find.byTooltip('Дополнительно'));
          await tap(tester, find.text('Кросспостинг'));
          final picker = tester.widget<CrosspostDestinations>(
            find.byType(CrosspostDestinations),
          );
          expect(picker.repository.transport, same(api));
          expect(picker.primaryId, mode == 'forward' ? 'B' : 'A');
          await tap(
            tester,
            find.byWidgetPredicate(
              (w) => w is CheckboxListTile && (w.title as Text).data == 'C',
            ),
          );
          await tap(tester, find.text('Готово'));
          expect(find.text('Кросспостинг: C'), findsOneWidget);
        },
      );
    }
  }
  testWidgets(
    'crosspost after unread transition targets active echo and closes picker on session change',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [area('A'), area('B'), area('C')],
      );
      api.conference = (r) async => area(r.conferenceId);
      api.messages = (r) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: '${r.conferenceId}#1', subject: 'Letter')],
      );
      api.message = (r) async => wire.Message(
        id: r.messageId,
        subject: 'Letter',
        body: r.conferenceId,
        isRead: true,
      );
      final repo = ConferenceRepository(
        apiClient: api,
        prefs: await SharedPreferences.getInstance(),
      );
      addTearDown(repo.dispose);
      await tester.pumpWidget(MaterialApp(home: MainScreen(repository: repo)));
      await tester.pumpAndSettle();
      await tap(tester, find.text('A'));
      await tap(tester, find.text('Letter'));
      await tap(tester, find.text('Следующее'));
      await tap(tester, find.byTooltip('Новое сообщение'));
      await tap(tester, find.byTooltip('Дополнительно'));
      await tap(tester, find.text('Кросспостинг'));
      expect(
        tester
            .widget<CrosspostDestinations>(find.byType(CrosspostDestinations))
            .primaryId,
        'B',
      );
      api.switchSession();
      await tester.pumpAndSettle();
      expect(find.byType(CrosspostDestinations), findsNothing);
    },
  );
}
