import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/bookmarks_screen.dart';
import 'package:fido/pages/history_screen.dart';
import 'package:fido/repositories/account_repository.dart';

import '../support/fake_transport.dart';

void main() {
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
