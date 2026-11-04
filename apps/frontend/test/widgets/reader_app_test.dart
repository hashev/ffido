import 'dart:async';

import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/conference_card.dart';
import 'package:fido/pages/reader_app.dart';
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

wire.Conference area(String id, {bool favorite = false}) => wire.Conference(
  id: id,
  name: id,
  description: 'Описание $id',
  canRead: true,
  isBookmarked: favorite,
  unreadCount: Int64(7),
  statisticsKnown: true,
);
Future<void> start(WidgetTester tester, FakeTransport api) async {
  SharedPreferences.setMockInitialValues({});
  addTearDown(api.dispose);
  final repo = ConferenceRepository(
    apiClient: api,
    prefs: await SharedPreferences.getInstance(),
  );
  addTearDown(repo.dispose);
  await tester.pumpWidget(MaterialApp(home: MainScreen(repository: repo)));
  await tester.pumpAndSettle();
}

Future<void> catalog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Все области'));
  await tester.pumpAndSettle();
}

List<wire.ListConferencesRequest> calls(FakeTransport api) =>
    api.calls.whereType<wire.ListConferencesRequest>().toList();

void main() {
  testWidgets(
    'cold start loads only first favorites page; empty state chooses areas',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: r.bookmarkedOnly ? [] : [area('all')],
      );
      await start(tester, api);
      expect(calls(api), hasLength(1));
      expect(calls(api).single.bookmarkedOnly, isTrue);
      expect(calls(api).single.omitStatistics, isFalse);
      expect(find.text('Нет закладок'), findsOneWidget);
      await tester.tap(find.text('Выбрать эхи'));
      await tester.pumpAndSettle();
      expect(find.text('all'), findsOneWidget);
      expect(calls(api).last.omitStatistics, isTrue);
      expect(calls(api).last.sort, wire.ConferenceSort.CONFERENCE_SORT_CATALOG);
      expect(find.text('7'), findsNothing);
    },
  );
  testWidgets(
    'both lists share cards; favorites show exact zero and catalog hides statistics',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [area('same')..unreadCount = Int64.ZERO],
      );
      await start(tester, api);
      expect(find.byType(ConferenceCard), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      await catalog(tester);
      expect(find.byType(ConferenceCard), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('Описание same'), findsOneWidget);
      expect(find.text('Статистика недоступна'), findsNothing);
    },
  );
  testWidgets(
    'catalog paints page one while later page is pending and keeps rows on error',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      final next = Completer<wire.ListConferencesResponse>();
      api.conferences = (r) async {
        if (r.bookmarkedOnly) return wire.ListConferencesResponse();
        if (r.page.offset == Int64.ZERO) {
          return wire.ListConferencesResponse(
            conferences: [area('first')],
            hasMore: true,
          );
        }
        return next.future;
      };
      await start(tester, api);
      await catalog(tester);
      expect(find.text('first'), findsOneWidget);
      await tester.tap(find.text('Загрузить ещё'));
      await tester.pump();
      expect(find.text('first'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      next.completeError(const NetworkException());
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      api.conferences = (_) async =>
          wire.ListConferencesResponse(conferences: [area('second')]);
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
    },
  );
  testWidgets(
    'bookmark confirmation changes row without catalog reload and syncs favorites',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      bool saved = false;
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: r.bookmarkedOnly && !saved
            ? []
            : [area('one', favorite: saved)],
      );
      final confirm = Completer<Empty>();
      api.add = (_) async {
        await confirm.future;
        saved = true;
        return Empty();
      };
      api.remove = (_) async {
        saved = false;
        return Empty();
      };
      await start(tester, api);
      await catalog(tester);
      final before = calls(api).length;
      await tester.tap(find.byTooltip('Добавить в закладки'));
      await tester.pump();
      expect(find.byTooltip('Добавить в закладки'), findsOneWidget);
      await tester.tap(find.byTooltip('Добавить в закладки'));
      await tester.pump();
      expect(api.calls.whereType<wire.GetConferenceRequest>(), hasLength(1));
      confirm.complete(Empty());
      await tester.pumpAndSettle();
      expect(calls(api), hasLength(before));
      expect(find.byTooltip('Удалить из закладок'), findsOneWidget);
      await tester.tap(find.byTooltip('Закладки'));
      await tester.pumpAndSettle();
      expect(find.text('one'), findsOneWidget);
      await tester.tap(find.byTooltip('Удалить из закладок'));
      await tester.pumpAndSettle();
      await catalog(tester);
      expect(find.byTooltip('Добавить в закладки'), findsOneWidget);
      expect(calls(api).where((r) => !r.bookmarkedOnly), hasLength(1));
    },
  );
  testWidgets(
    'switching tabs preserves catalog query rows and scroll without requests',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: r.bookmarkedOnly
            ? []
            : List.generate(20, (i) => area('row$i')),
      );
      await start(tester, api);
      await catalog(tester);
      await tester.enterText(find.byType(TextField), 'row');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      final first = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      final count = calls(api).length;
      await tester.tap(find.byTooltip('Закладки'));
      await tester.pumpAndSettle();
      await catalog(tester);
      expect(calls(api), hasLength(count));
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        first,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'row',
      );
    },
  );
  for (final fail in [false, true]) {
    testWidgets('late search result ignored (failure=$fail)', (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      final old = Completer<wire.ListConferencesResponse>();
      api.conferences = (r) async {
        if (r.bookmarkedOnly) return wire.ListConferencesResponse();
        if (r.query == 'old') return old.future;
        return wire.ListConferencesResponse(
          conferences: [area(r.query.isEmpty ? 'initial' : r.query)],
        );
      };
      await start(tester, api);
      await catalog(tester);
      await tester.enterText(find.byType(TextField), 'old');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pumpAndSettle();
      if (fail) {
        old.completeError(const NetworkException());
      } else {
        old.complete(wire.ListConferencesResponse(conferences: [area('old')]));
      }
      await tester.pumpAndSettle();
      expect(find.text('new'), findsNWidgets(2));
      expect(find.text('old'), findsNothing);
      expect(find.text('Сервер недоступен'), findsNothing);
    });
  }
  testWidgets(
    'clearing search cancels debounce; explicit refresh preserves filter',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: r.bookmarkedOnly ? [] : [area('one')],
      );
      await start(tester, api);
      await catalog(tester);
      await tester.enterText(find.byType(TextField), 'old');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Очистить поиск'));
      await tester.pumpAndSettle();
      expect(calls(api).any((r) => r.query == 'old'), isFalse);
      await tester.enterText(find.byType(TextField), 'keep');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Обновить'));
      await tester.pumpAndSettle();
      expect(calls(api).last.query, 'keep');
    },
  );
  testWidgets(
    'repeated page terminates with retry instead of infinite loading',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: r.bookmarkedOnly ? [] : [area('one')],
        hasMore: !r.bookmarkedOnly,
      );
      await start(tester, api);
      await catalog(tester);
      await tester.tap(find.text('Загрузить ещё'));
      await tester.pumpAndSettle();
      expect(find.textContaining('не продвигается'), findsOneWidget);
      expect(find.text('one'), findsOneWidget);
    },
  );
  testWidgets(
    'resume refreshes only active list and session switch discards late data',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: r.bookmarkedOnly ? [] : [area('old')],
      );
      await start(tester, api);
      await catalog(tester);
      final before = calls(api).length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls(api).length, before + 1);
      expect(calls(api).last.bookmarkedOnly, isFalse);
      api.conferences = (_) async =>
          wire.ListConferencesResponse(conferences: [area('new')]);
      api.switchSession();
      await tester.pumpAndSettle();
      expect(find.text('old'), findsNothing);
      expect(find.text('new'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.text('Горячие клавиши'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets('manual refresh cancels pending search debounce', (tester) async {
    final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
    api.conferences = (r) async => wire.ListConferencesResponse(
      conferences: r.bookmarkedOnly ? [] : [area('one')],
    );
    await start(tester, api);
    await catalog(tester);
    await tester.enterText(find.byType(TextField), 'filter');
    await tester.pump(const Duration(milliseconds: 100));
    final before = calls(api).length;
    await tester.tap(find.byTooltip('Обновить'));
    await tester.pumpAndSettle();
    expect(calls(api).length, before + 1);
    expect(calls(api).last.query, 'filter');
  });
  testWidgets(
    'retry bookmark mutation does not refresh catalog and clears its error',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: r.bookmarkedOnly ? [] : [area('one')],
      );
      var attempts = 0;
      api.add = (_) async {
        if (++attempts == 1) throw const NetworkException();
        return Empty();
      };
      await start(tester, api);
      await catalog(tester);
      final before = calls(api).length;
      await tester.tap(find.byTooltip('Добавить в закладки'));
      await tester.pumpAndSettle();
      expect(find.text('Сервер недоступен'), findsOneWidget);
      await tester.tap(find.text('Повторить изменение закладки'));
      await tester.pumpAndSettle();
      expect(find.text('Сервер недоступен'), findsNothing);
      expect(find.byTooltip('Удалить из закладок'), findsOneWidget);
      expect(attempts, 2);
      expect(calls(api).length, before);
    },
  );
}
