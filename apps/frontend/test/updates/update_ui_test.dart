import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/updates/update_controller.dart';
import 'package:fido/updates/update_ui.dart';

import 'update_fixture.dart';

void main() {
  late UpdateFixture fixture;
  late UpdateController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fixture = UpdateFixture();
    await fixture.initialize();
    controller = UpdateController(
      service: fixture.service(),
      preferences: await SharedPreferences.getInstance(),
    );
  });
  tearDown(() => controller.dispose());
  testWidgets(
    'уведомление сохраняет экран и текст, Позже скрывает до нового запуска',
    (tester) async {
      final text = TextEditingController(text: 'черновик');
      addTearDown(text.dispose);
      // Desktop startup reads the updater diagnostic file using real I/O.
      // Complete it outside the widget test's fake async clock on every host.
      await tester.runAsync(controller.start);
      expect(controller.available, isNotNull);
      await tester.pumpWidget(
        MaterialApp(
          home: UpdateShell(
            controller: controller,
            child: Scaffold(body: TextField(controller: text)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Обновить'), findsOneWidget);
      expect(find.text('черновик'), findsOneWidget);
      await tester.tap(find.text('Позже'));
      await tester.pumpAndSettle();
      expect(find.text('Обновить'), findsNothing);
      expect(find.text('черновик'), findsOneWidget);
      await controller.check(manual: true);
      await tester.pumpAndSettle();
      expect(find.text('Обновить'), findsNothing);
      expect(controller.available, isNotNull);
    },
  );
  testWidgets('ручная проверка до входа показывает ошибку и допускает повтор', (
    tester,
  ) async {
    var offline = true;
    controller.service = fixture.service(
      fetcher: (uri, {etag, limit = 2097152}) async {
        if (offline) throw StateError('offline');
        return fixture.fetch(uri, etag: etag, limit: limit);
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: UpdateScreen(controller: controller)),
    );
    await tester.tap(find.text('Проверить обновления'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось проверить'), findsOneWidget);
    offline = false;
    await tester.tap(find.text('Проверить обновления'));
    await tester.pumpAndSettle();
    expect(find.text('Обновить'), findsOneWidget);
  });
  test('защита редактора не запускает установщик; после закрытия передаёт прогресс', () async {
    var installs = 0;
    final done = Completer<void>();
    final updates = UpdateController(
      service: fixture.service(),
      installer: (update, progress) async {
        installs++;
        progress(.5);
        await done.future;
      },
    );
    addTearDown(updates.dispose);
    updates.available = fixture.available;
    final owner = Object();
    updates.guardExit(owner, () => false);
    await updates.install();
    expect(installs, 0);
    expect(updates.message, contains('закройте редактор'));
    updates.removeExitGuard(owner);
    final pending = updates.install();
    expect(updates.progress, .5);
    expect(updates.busy, isTrue);
    await updates.install();
    expect(installs, 1);
    done.complete();
    await pending;
    expect(updates.busy, isFalse);
  });
  test(
    'фоновая ошибка не показывает сообщение и сохраняет доступность приложения',
    () async {
      controller.service = fixture.service(
        fetcher: (uri, {etag, limit = 2097152}) async =>
            throw StateError('offline'),
      );
      await controller.check();
      expect(controller.phase, UpdatePhase.error);
      expect(controller.message, isEmpty);
      expect(controller.busy, isFalse);
    },
  );
}
