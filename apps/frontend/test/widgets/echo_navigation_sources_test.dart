import 'package:flutter/material.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/message_screen.dart';
import 'package:fido/pages/reader_app.dart';
import 'package:fido/pages/personal_conferences.dart';
import 'package:fido/repositories/account_repository.dart';
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

wire.Conference conference(String id) => wire.Conference(
  id: id,
  name: id,
  canRead: true,
  unreadCount: Int64(1),
  statisticsKnown: true,
);

void main() {
  testWidgets(
    'catalog passes sorted filtered snapshot and refreshes after cross-echo reading',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: [
          conference('z'),
          conference('a'),
          if (r.query.isEmpty) conference('outside'),
        ],
      );
      api.conference = (r) async => conference(r.conferenceId);
      api.messages = (r) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: '${r.conferenceId}#1', subject: 'letter')],
      );
      api.message = (r) async => wire.Message(
        id: r.messageId,
        body: 'body ${r.conferenceId}',
        isRead: true,
      );
      final repo = ConferenceRepository(
        apiClient: api,
        prefs: await SharedPreferences.getInstance(),
      );
      addTearDown(repo.dispose);
      await tester.pumpWidget(MaterialApp(home: MainScreen(repository: repo)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'filter');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('z'));
      await tester.pumpAndSettle();
      final reader = tester.widget<MessageScreen>(find.byType(MessageScreen));
      expect(reader.conferenceOrder.map((c) => c.id), ['a', 'z']);
      await tester.tap(find.text('letter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Следующее'));
      await tester.pumpAndSettle();
      expect(find.text('body a'), findsOneWidget);
      expect(
        api.calls.whereType<wire.GetConferenceRequest>().map(
          (r) => r.conferenceId,
        ),
        ['a'],
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MessageScreen), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'filter',
      );
      expect(
        api.calls.whereType<wire.ListConferencesRequest>().last.query,
        'filter',
      );
      expect(find.text('outside'), findsNothing);
    },
  );

  testWidgets('repeated personal pages stop without opening partial context', (
    tester,
  ) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    api.bookmarks = (_) async => wire.ListBookmarksResponse(
      bookmarks: [wire.Bookmark(conference: conference('z'))],
      hasMore: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalConferences(
          history: false,
          repository: AccountRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('z'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageScreen), findsNothing);
    expect(find.text('Список устарел. Обновите конференции.'), findsOneWidget);
    expect(api.calls.whereType<wire.PageRequest>().length, 2);
  });

  for (final history in [false, true]) {
    testWidgets(
      'source snapshot preserves ${history ? 'history' : 'bookmarks'} order across pages',
      (tester) async {
        final api = FakeTransport();
        addTearDown(api.dispose);
        api.bookmarks = (r) async => wire.ListBookmarksResponse(
          bookmarks: [
            wire.Bookmark(
              conference: conference(r.offset.toInt() == 0 ? 'z' : 'a'),
            ),
          ],
          hasMore: r.offset.toInt() == 0,
        );
        api.history = (r) async => wire.ListHistoryResponse(
          history: [
            wire.HistoryEntry(
              conference: conference(r.offset.toInt() == 0 ? 'z' : 'a'),
            ),
          ],
          hasMore: r.offset.toInt() == 0,
        );
        var reachedA = false;
        api.conference = (r) async => conference(r.conferenceId);
        api.messages = (r) async => wire.ListMessagesResponse(
          messages: [
            wire.Message(id: '${r.conferenceId}#1', subject: 'letter'),
            if (r.conferenceId == 'z')
              wire.Message(id: 'z#2', subject: 'letter 2', isRead: !reachedA),
          ],
        );
        api.message = (r) async {
          if (r.conferenceId == 'a') reachedA = true;
          return wire.Message(
            id: r.messageId,
            body: 'body ${r.conferenceId}',
            isRead: true,
          );
        };
        await tester.pumpWidget(
          MaterialApp(
            home: PersonalConferences(
              history: history,
              repository: AccountRepository(api),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('z'));
        await tester.pumpAndSettle();
        final reader = tester.widget<MessageScreen>(find.byType(MessageScreen));
        expect(reader.conferenceOrder.map((c) => c.id), ['z', 'a']);
        await tester.tap(find.text('letter'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Следующее'));
        await tester.pumpAndSettle();
        expect(find.text('body a'), findsOneWidget);
        // The second transition wraps to the start of this personal snapshot.
        await tester.tap(find.text('Следующее'));
        await tester.pumpAndSettle();
        expect(find.text('body z'), findsOneWidget);
        expect(
          api.calls.whereType<wire.GetConferenceRequest>().map(
            (r) => r.conferenceId,
          ),
          ['a', 'z'],
        );
        expect(api.calls.whereType<wire.ListConferencesRequest>(), isEmpty);
      },
    );
  }
}
