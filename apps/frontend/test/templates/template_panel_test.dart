import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/templates/template_settings.dart';
import 'package:fido/templates/default_template.dart';
import 'package:fido/templates/template_settings_panel.dart';
import 'package:fido/updates/update_controller.dart';

Future<void> tap(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  final found = find.text(label);
  await tester.ensureVisible(found);
  await tester.pumpAndSettle();
  await tester.tap(found);
  await tester.pumpAndSettle();
}

class FailingResetSettings extends TemplateSettings {
  FailingResetSettings(super.preferences);
  @override
  Future<void> reset() async => throw const FormatException('reset failed');
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
    bool failReset = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              TemplateSettingsPanel(
                settings: failReset
                    ? FailingResetSettings(prefs)
                    : TemplateSettings(
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
    expect(TemplateSettings(prefs).read()!.text, defaultMessageTemplate);
    expect(prefs.containsKey(TemplateSettings.key), isFalse);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('message-template')))
          .controller!
          .text,
      defaultMessageTemplate,
    );
    expect(appUpdates.canExit, isTrue);
    expect(prefs.getString('ffido_origin_v1'), 'Old origin');
  });
  testWidgets('default loads without writing and example requires save', (
    tester,
  ) async {
    final prefs = await open(tester);
    final field = find.byKey(const Key('message-template'));
    expect(
      tester.widget<TextField>(field).controller!.text,
      defaultMessageTemplate,
    );
    expect(prefs.containsKey(TemplateSettings.key), isFalse);
    expect(appUpdates.canExit, isTrue);
    await tap(tester, 'Предпросмотр шаблона');
    expect(find.textContaining('Hello, Иван!'), findsOneWidget);
    expect(find.textContaining('Best Regards, Юрий'), findsOneWidget);
    await tap(tester, 'Закрыть');
    await tester.enterText(field, '');
    await tap(tester, 'Сохранить шаблон');
    expect(TemplateSettings(prefs).read()!.text, '');
    await tap(tester, 'Вставить пример');
    expect(
      tester.widget<TextField>(field).controller!.text,
      defaultMessageTemplate,
    );
    expect(TemplateSettings(prefs).read()!.text, '');
    expect(appUpdates.canExit, isFalse);
  });

  testWidgets('reset failure preserves saved override and unsaved input', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await TemplateSettings(prefs).save(const TemplateBundle('Сохранённый'));
    await open(tester, failReset: true);
    final field = find.byKey(const Key('message-template'));
    expect(tester.widget<TextField>(field).controller!.text, 'Сохранённый');
    await tester.enterText(field, 'Несохранённый');
    await tap(tester, 'Сбросить шаблон');
    expect(tester.widget<TextField>(field).controller!.text, 'Несохранённый');
    expect(TemplateSettings(prefs).read()!.text, 'Сохранённый');
    expect(find.text('Шаблон сброшен'), findsNothing);
    expect(find.textContaining('Не удалось сохранить шаблон'), findsOneWidget);
    expect(appUpdates.canExit, isFalse);
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
