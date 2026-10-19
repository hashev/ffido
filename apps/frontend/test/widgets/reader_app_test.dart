import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/pages/reader_app.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import '../support/fake_transport.dart';

class PendingRequest {
  final wire.ListConferencesRequest request;
  final completer = Completer<wire.ListConferencesResponse>();
  PendingRequest(this.request);
  void succeed(String name) => completer.complete(conferenceData(name));
  void fail() => completer.completeError(const NetworkException());
}

Future<List<PendingRequest>> start(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final pending = <PendingRequest>[];
  final client = FakeTransport()
    ..conferences = (req) {
      final call = PendingRequest(req);
      pending.add(call);
      return call.completer.future;
    };
  addTearDown(client.dispose);
  final repo = ConferenceRepository(
    apiClient: client,
    prefs: await SharedPreferences.getInstance(),
  );
  addTearDown(repo.dispose);
  await tester.pumpWidget(MaterialApp(home: MainScreen(repository: repo)));
  await tester.pump();
  return pending;
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  // Завершаем оставшийся таймер демонстрационного профиля.
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'bottom tabs use icons, tooltips, accessible labels and 48px targets',
    (tester) async {
      final pending = await start(tester);
      pending.single.succeed('echo');
      await tester.pumpAndSettle();
      final finder = find.byType(BottomNavigationBar);
      final bar = tester.widget<BottomNavigationBar>(finder);
      expect(bar.showSelectedLabels, isFalse);
      expect(bar.showUnselectedLabels, isFalse);
      expect(bar.items.map((e) => e.tooltip), [
        'Главная',
        'Закладки',
        'История',
        'Профиль',
      ]);
      final semantics = tester.ensureSemantics();
      for (final label in ['Закладки', 'История', 'Профиль', 'Главная']) {
        final tooltip = find.descendant(
          of: finder,
          matching: find.byTooltip(label),
        );
        expect(tooltip, findsOneWidget);
        final size = tester.getSize(tooltip);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        await tester.tap(tooltip);
        await tester.pump();
        expect(
          tester
              .widget<BottomNavigationBar>(finder)
              .items[tester.widget<BottomNavigationBar>(finder).currentIndex]
              .label,
          label,
        );
      }
      semantics.dispose();
      if (pending.length > 1) {
        pending.last.succeed('refreshed');
        await tester.pump();
      }
      await close(tester);
    },
  );

  testWidgets('latest search wins over initial load and earlier searches', (
    tester,
  ) async {
    final calls = await start(tester);
    await search(tester, 'old');
    await search(tester, 'new');
    calls[2].succeed('new-result');
    await tester.pump();
    calls[1].succeed('old-result');
    calls[0].succeed('initial-result');
    await tester.pump();
    expect(find.text('new-result'), findsOneWidget);
    expect(find.text('old-result'), findsNothing);
    expect(find.text('initial-result'), findsNothing);
    await close(tester);
  });
  testWidgets('stale error cannot replace newer success', (tester) async {
    final calls = await start(tester);
    await search(tester, 'new');
    calls[1].succeed('new-result');
    await tester.pump();
    calls[0].fail();
    await tester.pump();
    expect(find.text('new-result'), findsOneWidget);
    expect(find.textContaining('Ошибка загрузки'), findsNothing);
    await close(tester);
  });
  testWidgets('input invalidates an old result before debounce fires', (
    tester,
  ) async {
    final calls = await start(tester);
    await tester.enterText(find.byType(TextField), 'new');
    calls[0].succeed('old-result');
    await tester.pump();
    expect(find.text('old-result'), findsNothing);
    expect(find.text('Загрузка конференций...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    calls[1].succeed('new-result');
    await tester.pump();
    expect(find.text('new-result'), findsOneWidget);
    await close(tester);
  });
  for (final fail in [false, true]) {
    testWidgets('completion after dispose is safe (failure=$fail)', (
      tester,
    ) async {
      final calls = await start(tester);
      await tester.pumpWidget(const SizedBox());
      if (fail) {
        calls[0].fail();
      } else {
        calls[0].succeed('late');
      }
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }
  for (final clearButton in [false, true]) {
    testWidgets('clear cancels pending debounce (button=$clearButton)', (
      tester,
    ) async {
      final calls = await start(tester);
      await tester.enterText(find.byType(TextField), 'pending');
      await tester.pump();
      if (clearButton) {
        await tester.tap(find.byIcon(Icons.clear));
      } else {
        await tester.enterText(find.byType(TextField), '');
      }
      await tester.pump();
      expect(calls.length, 2);
      expect(calls[1].request.query.isNotEmpty, isFalse);
      calls[1].succeed('unfiltered');
      calls[0].succeed('old-initial');
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls.length, 2);
      expect(find.text('unfiltered'), findsOneWidget);
      await close(tester);
    });
  }
  testWidgets('refresh and retry preserve active filter', (tester) async {
    final calls = await start(tester);
    await search(tester, 'dart');
    calls[0].succeed('initial');
    calls[1].succeed('dart-result');
    await tester.pump();
    final refresh = find.byTooltip('Обновить').first;
    await tester.tap(refresh);
    await tester.pump();
    expect(calls[2].request.query, 'dart');
    calls[2].fail();
    await tester.pump();
    await tester.tap(find.text('Повторить').first);
    await tester.pump();
    expect(calls[3].request.query, 'dart');
    calls[3].succeed('retry-result');
    await tester.pump();
    expect(find.text('retry-result'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'dart',
    );
    await close(tester);
  });
  testWidgets('refresh cancels pending search timer', (tester) async {
    final calls = await start(tester);
    await tester.enterText(find.byType(TextField), 'pending');
    await tester.tap(find.byTooltip('Обновить').first);
    await tester.pump();
    expect(calls.length, 2);
    expect(calls[1].request.query, 'pending');
    calls[1].succeed('result');
    calls[0].succeed('old');
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls.length, 2);
    expect(find.text('result'), findsOneWidget);
    await close(tester);
  });
  testWidgets('wire conferences use the supported default icon', (
    tester,
  ) async {
    final calls = await start(tester);
    calls[0].succeed('icon-result');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byIcon(Icons.forum),
      ),
      findsOneWidget,
    );
    await close(tester);
  });
  testWidgets(
    'returning from background bypasses fresh cache and avoids duplicate refresh',
    (tester) async {
      final calls = await start(tester);
      calls[0].succeed('phone-old-state');
      await tester.pump();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls.length, 2);
      calls[1].succeed('laptop-new-state');
      await tester.pump();
      expect(find.text('laptop-new-state'), findsOneWidget);
      expect(find.text('phone-old-state'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls.length, 2);
      await close(tester);
    },
  );
  testWidgets('resume cancels a pending search timer and ignores old results', (
    tester,
  ) async {
    final calls = await start(tester);
    await tester.enterText(find.byType(TextField), 'pending');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls.length, 2);
    expect(calls[1].request.query, 'pending');
    calls[1].succeed('fresh-search');
    calls[0].succeed('stale-before-background');
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls.length, 2);
    expect(find.text('fresh-search'), findsOneWidget);
    expect(find.text('stale-before-background'), findsNothing);
    await close(tester);
  });
}
