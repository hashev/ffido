import 'package:flutter/material.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/message_screen.dart';
import 'package:fido/pages/personal_conferences.dart';
import 'package:fido/repositories/account_repository.dart';

import '../support/fake_transport.dart';

import 'package:fido/repositories/message_repository.dart';
import 'package:fido/api/model_mapping.dart';

wire.Conference conference(String id) => wire.Conference(
  id: id,
  name: id,
  canRead: true,
  isBookmarked: true,
  unreadCount: Int64(1),
  statisticsKnown: true,
);

void main() {
  for (final source in ['catalog', 'bookmarks', 'history']) {
    testWidgets(
      '$source opens immediately and uses alphabetical favorites for transitions',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final api = FakeTransport();
        addTearDown(api.dispose);
        api.conferences = (_) async => wire.ListConferencesResponse(
          conferences: [conference('z'), conference('outside')],
        );
        api.bookmarks = (r) async => wire.ListBookmarksResponse(
          bookmarks: [
            wire.Bookmark(
              conference: conference(r.offset.toInt() == 0 ? 'z' : 'a'),
            ),
          ],
          hasMore: r.offset == Int64.ZERO,
        );
        api.history = (_) async => wire.ListHistoryResponse(
          history: [wire.HistoryEntry(conference: conference('z'))],
          hasMore: true,
        );
        api.conference = (r) async => conference(r.conferenceId);
        var reachedA = false;
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
              history: source == 'history',
              catalog: source == 'catalog',
              repository: AccountRepository(api),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = api.calls.whereType<wire.PageRequest>().length;
        await tester.tap(find.text('z'));
        await tester.pumpAndSettle();
        expect(find.byType(MessageScreen), findsOneWidget);
        expect(api.calls.whereType<wire.PageRequest>(), hasLength(before));
        await tester.tap(find.text('letter'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Следующее'));
        await tester.pumpAndSettle();
        expect(find.text('body a'), findsOneWidget);
        await tester.tap(find.text('Следующее'));
        await tester.pumpAndSettle();
        expect(find.text('body z'), findsOneWidget);
        expect(
          api.calls.whereType<wire.GetConferenceRequest>().map(
            (r) => r.conferenceId,
          ),
          ['a', 'z'],
        );
        expect(
          api.calls.whereType<wire.ListConferencesRequest>().length,
          source == 'catalog' ? 1 : 0,
        );
      },
    );
  }
  testWidgets(
    'nonfavorite echo starts at first alphabetical favorite and empty favorites end traversal',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.conference = (r) async => conference(r.conferenceId);
      api.messages = (r) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: '${r.conferenceId}#1', subject: 'letter')],
      );
      api.message = (r) async => wire.Message(
        id: r.messageId,
        body: 'body ${r.conferenceId}',
        isRead: true,
      );
      for (final empty in [false, true]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(
            home: MessageScreen(
              conferenceId: 'outside',
              conferenceName: 'outside',
              conferenceDescription: '',
              canRead: true,
              repository: MessageRepository(api),
              loadFavoriteOrder: (_) async => empty
                  ? []
                  : [
                      mapConference(conference('a')),
                      mapConference(conference('z')),
                    ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('letter'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Следующее'));
        await tester.pumpAndSettle();
        expect(find.text(empty ? 'body outside' : 'body a'), findsOneWidget);
        if (empty) {
          expect(
            find.text('Дальнейших непрочитанных сообщений нет'),
            findsOneWidget,
          );
        }
      }
    },
  );
  testWidgets(
    'repeated favorite page errors only when transition needs snapshot',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.bookmarks = (_) async => wire.ListBookmarksResponse(
        bookmarks: [wire.Bookmark(conference: conference('z'))],
        hasMore: true,
      );
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: 'z#1', subject: 'letter')],
      );
      api.message = (r) async =>
          wire.Message(id: r.messageId, body: 'body z', isRead: true);
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
      expect(find.byType(MessageScreen), findsOneWidget);
      await tester.tap(find.text('letter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Следующее'));
      await tester.pumpAndSettle();
      expect(find.text('body z'), findsOneWidget);
      expect(find.textContaining('не продвигается'), findsOneWidget);
    },
  );
}
