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
import '../support/adaptive_appearance.dart';

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
      expect(find.text('0'), findsOneWidget);
      await tester.tap(find.byTooltip('Обновить'));
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
    api.conference = (_) async => wire.Conference(
      id: 'echo',
      name: 'Echo',
      canRead: true,
      isBookmarked: true,
      unreadCount: Int64(unread ? 1 : 0),
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

  var fontsLoaded = false;
  for (final modern in [false, true]) {
    for (final width in [320.0, 1280.0]) {
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'private favorites modern=$modern width=$width dark=$dark scale=$scale',
            (t) async {
              if (!fontsLoaded) {
                await loadAdaptiveFonts();
                fontsLoaded = true;
              }
              t.view.physicalSize = Size(width, 1000);
              t.view.devicePixelRatio = 1;
              addTearDown(t.view.resetPhysicalSize);
              addTearDown(t.view.resetDevicePixelRatio);
              final rows = [
                wire.Conference(
                  id: 'raw-id',
                  name: 'Netmail',
                  kind: wire.AreaKind.AREA_KIND_NETMAIL,
                  unreadCount: Int64(3),
                ),
                wire.Conference(
                  id: 'point-id',
                  name: 'Почта поинта',
                  kind: wire.AreaKind.AREA_KIND_NETMAIL,
                  unreadCount: Int64.ZERO,
                  personalMailbox: true,
                ),
                wire.Conference(
                  id: 'unknown-id',
                  name: 'Неизвестный ящик',
                  kind: wire.AreaKind.AREA_KIND_NETMAIL,
                  statisticsKnown: false,
                ),
                wire.Conference(
                  id: 'carbon-id',
                  name: 'personal.mail',
                  kind: wire.AreaKind.AREA_KIND_LOCAL,
                  unreadCount: Int64(7),
                ),
                wire.Conference(
                  id: 'local-other',
                  name: 'Локальный архив',
                  kind: wire.AreaKind.AREA_KIND_LOCAL,
                  unreadCount: Int64(9),
                ),
                wire.Conference(
                  id: 'echo-id',
                  name: 'Эха',
                  unreadCount: Int64(2),
                ),
              ];
              for (final row in rows) {
                row.canRead = true;
                row.isBookmarked = true;
              }
              final api = FakeTransport()
                ..supportsLightweightConferenceCatalog = modern;
              api.conferences = (_) async =>
                  wire.ListConferencesResponse(conferences: rows);
              api.bookmarks = (_) async => wire.ListBookmarksResponse(
                bookmarks: [
                  for (final row in rows) wire.Bookmark(conference: row),
                ],
              );
              api.remove = (r) async {
                rows.removeWhere((x) => x.id == r.conferenceId);
                return Empty();
              };
              addTearDown(api.dispose);
              final semantics = t.ensureSemantics();
              final key = GlobalKey();
              await t.pumpWidget(
                RepaintBoundary(
                  key: key,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: ThemeData(
                      fontFamily: 'Roboto',
                      brightness: dark ? Brightness.dark : Brightness.light,
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: BookmarksScreen(repository: AccountRepository(api)),
                  ),
                ),
              );
              await t.pumpAndSettle();
              final listScroll = find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first;
              for (final row in rows) {
                await t.scrollUntilVisible(
                  find.text(row.name),
                  150,
                  scrollable: listScroll,
                );
                await t.ensureVisible(find.text(row.name));
                await t.pumpAndSettle();
                final tile = find
                    .ancestor(
                      of: find.text(row.name),
                      matching: find.byType(ListTile),
                    )
                    .first;
                expect(
                  find.descendant(
                    of: tile,
                    matching: find.text(
                      row.id == 'unknown-id' ? '—' : row.unreadCount.toString(),
                    ),
                  ),
                  findsOneWidget,
                );
                expect(t.takeException(), isNull);
              }
              t.state<ScrollableState>(listScroll).position.jumpTo(0);
              await t.pumpAndSettle();
              if (modern) {
                await adaptiveScreenshot(
                  t,
                  key,
                  'favorite-private-$width-$dark-$scale',
                );
              }
              final initial = api.calls
                  .where(
                    (x) =>
                        x is wire.ListConferencesRequest ||
                        x is wire.PageRequest,
                  )
                  .length;
              final tile = find
                  .ancestor(
                    of: find.text('Netmail'),
                    matching: find.byType(ListTile),
                  )
                  .first;
              final bookmark = find.descendant(
                of: tile,
                matching: find.byTooltip('Удалить из закладок'),
              );
              await t.tap(bookmark);
              await t.pumpAndSettle();
              expect(find.text('Netmail'), findsNothing);
              expect(
                api.calls.where(
                  (x) =>
                      x is wire.ListConferencesRequest || x is wire.PageRequest,
                ),
                hasLength(initial),
              );
              if (modern) {
                final request = api.calls
                    .whereType<wire.ListConferencesRequest>()
                    .single;
                expect(request.bookmarkedOnly, isTrue);
                expect(request.omitStatistics, isFalse);
              }
              semantics.dispose();
            },
          );
        }
      }
    }
  }
}
