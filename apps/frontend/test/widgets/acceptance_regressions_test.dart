import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as w;
import 'package:fido/pages/reader_app.dart';
import 'package:fido/pages/bookmarks_screen.dart';
import 'package:fido/pages/history_screen.dart';
import 'package:fido/repositories/account_repository.dart';
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

Future<void> start(WidgetTester tester, FakeTransport api) async {
  SharedPreferences.setMockInitialValues({});
  final repo = ConferenceRepository(
    apiClient: api,
    prefs: await SharedPreferences.getInstance(),
  );
  addTearDown(repo.dispose);
  addTearDown(api.dispose);
  await tester.pumpWidget(MaterialApp(home: MainScreen(repository: repo)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'bookmarks can be added, removed in their tab and remain removed on home',
    (tester) async {
      bool saved = false;
      final api = FakeTransport();
      w.Conference conference() => w.Conference(
        canRead: true,
        canPost: true,
        id: 'one',
        name: 'Конференция',
        isBookmarked: saved,
      );
      api.conferences = (_) async =>
          w.ListConferencesResponse(conferences: [conference()]);
      api.add = (_) async {
        saved = true;
        return Empty();
      };
      api.remove = (_) async {
        saved = false;
        return Empty();
      };
      api.bookmarks = (_) async => w.ListBookmarksResponse(
        bookmarks: saved ? [w.Bookmark(conference: conference())] : [],
      );
      await start(tester, api);
      await tester.tap(find.byTooltip('Добавить в закладки'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Удалить из закладок'), findsOneWidget);
      await tester.tap(find.text('Закладки').last);
      await tester.pumpAndSettle();
      expect(find.text('Конференция'), findsOneWidget);
      await tester.tap(find.byTooltip('Удалить из закладок'));
      await tester.pumpAndSettle();
      expect(find.text('Нет закладок'), findsOneWidget);
      await tester.tap(find.text('Главная').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Добавить в закладки'), findsOneWidget);
      expect(saved, isFalse);
    },
  );

  testWidgets(
    'bookmark pending blocks double click and error preserves prior state',
    (tester) async {
      final pending = Completer<Empty>();
      var calls = 0;
      final api = FakeTransport()
        ..conferences = (_) async => conferenceData('one');
      api.add = (_) {
        calls++;
        return pending.future;
      };
      await start(tester, api);
      await tester.tap(find.byTooltip('Добавить в закладки'));
      await tester.pump();
      await tester.tap(find.byTooltip('Добавить в закладки'));
      await tester.pump();
      expect(calls, 1);
      pending.completeError(const NetworkException());
      await tester.pumpAndSettle();
      expect(find.byTooltip('Добавить в закладки'), findsOneWidget);
      expect(find.text('Сервер недоступен'), findsOneWidget);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'old bookmark completion cannot overwrite another session (error=$fail)',
      (tester) async {
        final pending = Completer<Empty>();
        final api = FakeTransport()
          ..conferences = (_) async => conferenceData('A');
        api.add = (_) => pending.future;
        await start(tester, api);
        await tester.tap(find.byTooltip('Добавить в закладки'));
        await tester.pump();
        api.conferences = (_) async => conferenceData('B');
        api.switchSession();
        await tester.pumpAndSettle();
        if (fail) {
          pending.completeError(const NetworkException());
        } else {
          pending.complete(Empty());
        }
        await tester.pumpAndSettle();
        expect(find.text('B'), findsOneWidget);
        expect(find.text('A'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed bookmark deletion keeps entry and stale success does not remove B',
    (tester) async {
      final api = FakeTransport();
      api.bookmarks = (_) async => w.ListBookmarksResponse(
        bookmarks: [
          w.Bookmark(
            conference: w.Conference(
              canRead: true,
              canPost: true,
              id: 'one',
              name: 'A',
            ),
          ),
        ],
      );
      api.remove = (_) async => throw const NetworkException();
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(home: BookmarksScreen(repository: AccountRepository(api))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Удалить из закладок'));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      final pending = Completer<Empty>();
      api.remove = (_) => pending.future;
      await tester.tap(find.byTooltip('Удалить из закладок'));
      await tester.pump();
      api.bookmarks = (_) async => w.ListBookmarksResponse(
        bookmarks: [
          w.Bookmark(
            conference: w.Conference(
              canRead: true,
              canPost: true,
              id: 'one',
              name: 'B',
            ),
          ),
        ],
      );
      api.switchSession();
      await tester.pumpAndSettle();
      pending.complete(Empty());
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      expect(find.text('A'), findsNothing);
    },
  );

  testWidgets(
    'opening preloaded empty history after read refreshes it; home keeps filter and new unread',
    (tester) async {
      var viewed = false;
      final queries = <String>[];
      final api = FakeTransport();
      api.conferences = (r) async {
        queries.add(r.query);
        return w.ListConferencesResponse(
          conferences: [
            w.Conference(
              canRead: true,
              canPost: true,
              id: 'one',
              name: 'Конференция',
              unreadCount: Int64(viewed ? 0 : 1),
            ),
          ],
        );
      };
      api.history = (_) async => w.ListHistoryResponse(
        history: viewed
            ? [
                w.HistoryEntry(
                  conference: w.Conference(
                    canRead: true,
                    canPost: true,
                    id: 'one',
                    name: 'Конференция',
                  ),
                ),
              ]
            : [],
      );
      api.messages = (_) async => w.ListMessagesResponse(
        messages: [w.Message(id: 'g#1', subject: 'Тема')],
      );
      api.message = (r) async {
        viewed = true;
        return w.Message(id: r.messageId, subject: 'Тема', body: 'Текст');
      };
      await start(tester, api);
      await tester.tap(find.text('История').last);
      await tester.pumpAndSettle();
      expect(find.text('История просмотров пуста'), findsOneWidget);
      await tester.tap(find.text('Главная').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Кон');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Конференция'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тема'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('К списку'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Тема'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(queries.last, 'Кон');
      expect(find.text('1'), findsNothing);
      await tester.tap(find.text('История').last);
      await tester.pumpAndSettle();
      expect(find.text('Конференция'), findsOneWidget);
      expect(find.text('История просмотров пуста'), findsNothing);
    },
  );

  testWidgets('late old history is discarded after tab reactivation', (
    tester,
  ) async {
    final api = FakeTransport();
    final old = Completer<w.ListHistoryResponse>();
    api.history = (_) => old.future;
    addTearDown(api.dispose);
    final repo = AccountRepository(api);
    Widget screen(bool active) => MaterialApp(
      home: HistoryScreen(repository: repo, active: active),
    );
    await tester.pumpWidget(screen(true));
    await tester.pump();
    await tester.pumpWidget(screen(false));
    await tester.pump();
    api.history = (_) async => w.ListHistoryResponse(
      history: [
        w.HistoryEntry(
          conference: w.Conference(canRead: true, canPost: true, name: 'Новое'),
        ),
      ],
    );
    await tester.pumpWidget(screen(true));
    await tester.pumpAndSettle();
    old.complete(
      w.ListHistoryResponse(
        history: [
          w.HistoryEntry(
            conference: w.Conference(
              canRead: true,
              canPost: true,
              name: 'Старое',
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Новое'), findsOneWidget);
    expect(find.text('Старое'), findsNothing);
  });
}
