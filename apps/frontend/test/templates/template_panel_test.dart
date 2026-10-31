import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/templates/template_settings.dart';
import 'package:fido/templates/template_settings_panel.dart';
import 'package:fido/updates/update_controller.dart';

Future<void> tap(WidgetTester tester, String label) async {
  final found = find.text(label);
  await tester.ensureVisible(found);
  await tester.tap(found);
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'ffido_origin_v1': 'Old origin',
    }),
  );
  Future<SharedPreferences> open(
    WidgetTester tester, {
    bool fail = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              TemplateSettingsPanel(
                settings: TemplateSettings(
                  prefs,
                  write: fail ? (_) async => false : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('local save, guard and independent reset', (tester) async {
    final prefs = await open(tester);
    expect(appUpdates.canExit, isTrue);
    await tester.enterText(
      find.byKey(const Key('message-template')),
      'Подпись @cfname',
    );
    expect(appUpdates.canExit, isFalse);
    await tap(tester, 'Сохранить шаблон');
    expect(find.text('Шаблон сохранён'), findsOneWidget);
    expect(TemplateSettings(prefs).read()!.text, 'Подпись @cfname');
    expect(appUpdates.canExit, isTrue);
    await tap(tester, 'Сбросить шаблон');
    expect(TemplateSettings(prefs).read(), isNull);
    expect(prefs.getString('ffido_origin_v1'), 'Old origin');
  });
  testWidgets('all compatibility errors retain last working setting', (
    tester,
  ) async {
    final prefs = await open(tester);
    final field = find.byKey(const Key('message-template'));
    await tester.enterText(field, 'Рабочий');
    await tap(tester, 'Сохранить шаблон');
    for (final input in [
      '@pipe{bad}',
      '@forcefrom X',
      '@unknown',
      '@include missing',
      '@random cookies.txt',
    ]) {
      await tester.ensureVisible(field);
      await tester.enterText(field, input);
      await tap(tester, 'Сохранить шаблон');
      expect(find.text('Исправьте ошибки шаблона'), findsOneWidget);
      expect(TemplateSettings(prefs).read()!.text, 'Рабочий');
    }
    await tester.ensureVisible(field);
    await tester.enterText(field, '@header @msgno\n@origin');
    await tap(tester, 'Сохранить шаблон');
    expect(find.textContaining('может дублировать'), findsWidgets);
    expect(TemplateSettings(prefs).read()!.text, '@header @msgno\n@origin');
  });
  testWidgets('preview shows same text, cursor and does not save', (
    tester,
  ) async {
    final prefs = await open(tester);
    await tester.enterText(
      find.byKey(const Key('message-template')),
      '@quoted@oname\n@position@cfname',
    );
    await tap(tester, 'Предпросмотр шаблона');
    expect(find.text('Иван Петров\n▏Юрий'), findsOneWidget);
    expect(prefs.containsKey(TemplateSettings.key), isFalse);
    await tap(tester, 'Закрыть');
    expect(appUpdates.canExit, isFalse);
  });
  testWidgets('write failure preserves form input', (tester) async {
    await open(tester, fail: true);
    await tester.enterText(
      find.byKey(const Key('message-template')),
      'Новый текст',
    );
    await tap(tester, 'Сохранить шаблон');
    expect(
      find.text(
        'Не удалось сохранить шаблон; введённый текст сохранён в форме',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('message-template')))
          .controller!
          .text,
      'Новый текст',
    );
  });
  testWidgets('scrolling away preserves unsaved text and update guard', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: scroll,
            children: [
              const SizedBox(height: 1800),
              TemplateSettingsPanel(preferences: prefs),
            ],
          ),
        ),
      ),
    );
    scroll.jumpTo(1800);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('message-template')),
      'Несохранённый текст',
    );
    expect(appUpdates.canExit, isFalse);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(appUpdates.canExit, isFalse);
    scroll.jumpTo(1800);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('message-template')))
          .controller!
          .text,
      'Несохранённый текст',
    );
  });
}
