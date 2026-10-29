import 'dart:async';

import 'package:fixnum/fixnum.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/bookmarks_screen.dart';
import 'package:fido/pages/history_screen.dart';
import 'package:fido/repositories/account_repository.dart';

import '../support/fake_transport.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'bookmark counters preserve order, removal and layout on narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final entries = [
        wire.Bookmark(
          conference: wire.Conference(
            id: 'z',
            name: 'Zulu very long echo name',
            unreadCount: Int64(2147483647),
          ),
        ),
        wire.Bookmark(
          conference: wire.Conference(
            id: 'a',
            name: 'Alpha',
            unreadCount: Int64(0),
          ),
        ),
        wire.Bookmark(
          conference: wire.Conference(
            id: 'u',
            name: 'Unknown',
            statisticsKnown: false,
            unreadCount: Int64(99),
          ),
        ),
        wire.Bookmark(
          conference: wire.Conference(
            id: 'net',
            name: 'Mail',
            kind: wire.AreaKind.AREA_KIND_NETMAIL,
          ),
        ),
      ];
      final api = FakeTransport();
      api.bookmarks = (_) async =>
          wire.ListBookmarksResponse(bookmarks: entries);
      api.remove = (r) async {
        entries.removeWhere((e) => e.conference.id == r.conferenceId);
        return Empty();
      };
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(home: BookmarksScreen(repository: AccountRepository(api))),
      );
      await tester.pumpAndSettle();
      expect(find.text('2147483647'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('99'), findsNothing);
      expect(find.bySemanticsLabel('Непрочитанных: 0'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Количество непрочитанных неизвестно'),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<ListTile>(find.byType(ListTile))
            .map((t) => (t.title as Text).data),
        ['Zulu very long echo name', 'Alpha', 'Unknown', 'Mail'],
      );
      expect(api.calls.length, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Удалить из закладок').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('2147483647'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  testWidgets(
    'bookmark counters refresh, survive errors and discard old session results',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      wire.ListBookmarksResponse data(int count) => wire.ListBookmarksResponse(
        bookmarks: [
          wire.Bookmark(
            conference: wire.Conference(
              id: 'echo',
              name: 'Echo',
              unreadCount: Int64(count),
            ),
          ),
        ],
      );
      api.bookmarks = (_) async => data(1);
      final repo = AccountRepository(api);
      Widget screen(bool active) => MaterialApp(
        home: BookmarksScreen(repository: repo, active: active),
      );
      await tester.pumpWidget(screen(true));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      api.bookmarks = (_) async => throw const NetworkException();
      await tester.tap(find.byTooltip('Обновить'));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      api.bookmarks = (_) async => data(0);
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      await tester.pumpWidget(screen(false));
      api.bookmarks = (_) async => data(3);
      await tester.pumpWidget(screen(true));
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      final old = Completer<wire.ListBookmarksResponse>();
      api.bookmarks = (_) => old.future;
      await tester.tap(find.byTooltip('Обновить'));
      await tester.pump();
      api.bookmarks = (_) async => data(7);
      api.switchSession();
      await tester.pumpAndSettle();
      old.complete(data(99));
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
      expect(find.text('99'), findsNothing);
      expect(find.text('3'), findsNothing);
    },
  );
  testWidgets('bookmark counter changes from one to zero after reading', (
    tester,
  ) async {
    var unread = true;
    final api = FakeTransport();
    addTearDown(api.dispose);
    api.bookmarks = (_) async => wire.ListBookmarksResponse(
      bookmarks: [
        wire.Bookmark(
          conference: wire.Conference(
            id: 'echo',
            name: 'Echo',
            canRead: true,
            unreadCount: Int64(unread ? 1 : 0),
          ),
        ),
      ],
    );
    api.messages = (_) async => wire.ListMessagesResponse(
      messages: [wire.Message(id: 'g#1', subject: 'Subject')],
    );
    api.message = (r) async {
      unread = false;
      return wire.Message(id: r.messageId, subject: 'Subject', body: 'Body');
    };
    await tester.pumpWidget(
      MaterialApp(home: BookmarksScreen(repository: AccountRepository(api))),
    );
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.text('Echo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subject'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  for (final history in [false, true]) {
    testWidgets(
      'personal screen loading, failure, retry, empty (history=$history)',
      (tester) async {
        final api = FakeTransport();
        final bookmarks = Completer<wire.ListBookmarksResponse>();
        final views = Completer<wire.ListHistoryResponse>();
        api.bookmarks = (_) => bookmarks.future;
        api.history = (_) => views.future;
        addTearDown(api.dispose);
        final repo = AccountRepository(api);
        await tester.pumpWidget(
          MaterialApp(
            home: history
                ? HistoryScreen(repository: repo)
                : BookmarksScreen(repository: repo),
          ),
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        if (history) {
          views.completeError(const NetworkException());
        } else {
          bookmarks.completeError(const NetworkException());
        }
        await tester.pumpAndSettle();
        expect(find.text('Повторить'), findsOneWidget);
        api.bookmarks = null;
        api.history = null;
        await tester.tap(find.text('Повторить'));
        await tester.pumpAndSettle();
        expect(
          find.text(history ? 'История просмотров пуста' : 'Нет закладок'),
          findsOneWidget,
        );
      },
    );
    testWidgets(
      'personal data is cleared on session change and safe after dispose (history=$history)',
      (tester) async {
        final api = FakeTransport()
          ..bookmarks = (_) async => wire.ListBookmarksResponse(
            bookmarks: [
              wire.Bookmark(
                conference: wire.Conference(
                  canRead: true,
                  canPost: true,
                  id: 'id',
                  name: 'Конференция',
                ),
              ),
            ],
          );
        api.history = (_) async => wire.ListHistoryResponse(
          history: [
            wire.HistoryEntry(
              conference: wire.Conference(
                canRead: true,
                canPost: true,
                id: 'id',
                name: 'Конференция',
              ),
            ),
          ],
        );
        addTearDown(api.dispose);
        final repo = AccountRepository(api);
        await tester.pumpWidget(
          MaterialApp(
            home: history
                ? HistoryScreen(repository: repo)
                : BookmarksScreen(repository: repo),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Конференция'), findsOneWidget);
        final bookmarks = Completer<wire.ListBookmarksResponse>();
        final views = Completer<wire.ListHistoryResponse>();
        api.bookmarks = (_) => bookmarks.future;
        api.history = (_) => views.future;
        api.switchSession();
        await tester.pump();
        expect(find.text('Конференция'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        if (history) {
          views.completeError(const NetworkException());
        } else {
          bookmarks.completeError(const NetworkException());
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('history is removed only after successful RPC', (tester) async {
    final api = FakeTransport()
      ..history = (_) async => wire.ListHistoryResponse(
        history: [
          wire.HistoryEntry(
            conference: wire.Conference(
              canRead: true,
              canPost: true,
              name: 'Конференция',
            ),
          ),
        ],
      );
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(repository: AccountRepository(api))),
    );
    await tester.pumpAndSettle();
    api.clear = () async => throw const NetworkException();
    await tester.tap(find.byTooltip('Очистить историю'));
    await tester.pumpAndSettle();
    expect(find.text('Конференция'), findsOneWidget);
    api.clear = () async => Empty();
    await tester.tap(find.byTooltip('Очистить историю'));
    await tester.pumpAndSettle();
    expect(find.text('Конференция'), findsNothing);
    expect(find.text('История просмотров пуста'), findsOneWidget);
  });
}
