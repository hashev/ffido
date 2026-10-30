import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';

import '../test/support/fake_transport.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/models/conference.dart';
import 'package:fido/templates/template_engine.dart';
import 'package:fido/templates/template_settings.dart';
import 'package:fido/templates/template_settings_panel.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('text template persists, previews all modes and resets on device', (
    tester,
  ) async {
    // Use an isolated namespace; never touch the user's real preferences.
    const phase = String.fromEnvironment('FFIDO_TEMPLATE_SMOKE_PHASE');
    const namespace = String.fromEnvironment('FFIDO_TEMPLATE_SMOKE_NAMESPACE');
    final suffix = namespace.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : namespace;
    SharedPreferences.setPrefix('ffido_template_smoke_$suffix.');
    final prefs = await SharedPreferences.getInstance();
    if (phase == 'read') {
      expect(TemplateSettings(prefs).read()!.text, '@cfname restart');
    }
    addTearDown(() async {
      if (phase == 'write') {
        await TemplateSettings(prefs)
            .save(const TemplateBundle('@cfname restart'));
      } else {
        await prefs.clear();
      }
    });
    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [TemplateSettingsPanel(preferences: prefs)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await open();
    const tpl =
        'Привет, @tfname!\n@quoted@oname написал:\n@quote\n@forward@message\n@position\nС уважением, @cfname';
    final previousClipboard = await Clipboard.getData(Clipboard.kTextPlain);
    addTearDown(
      () =>
          Clipboard.setData(ClipboardData(text: previousClipboard?.text ?? '')),
    );
    await Clipboard.setData(const ClipboardData(text: tpl));
    final pasted = await Clipboard.getData(Clipboard.kTextPlain);
    await tester.enterText(
      find.byKey(const Key('message-template')),
      pasted!.text!,
    );
    await tap('Сохранить шаблон');
    debugPrint('template-smoke: saved');
    expect(TemplateSettings(prefs).read()!.text, tpl);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await prefs.reload();
    await open();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('message-template')))
          .controller!
          .text,
      tpl,
    );
    await tap('Предпросмотр шаблона');
    debugPrint('template-smoke: preview');
    for (final action in TemplateAction.values) {
      final dropdown = find.byKey(const Key('template-preview-action'));
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pump(const Duration(milliseconds: 400));
      const labels = [
        'Новое письмо',
        'Ответ без цитаты',
        'Ответ с цитатой',
        'Пересылка',
      ];
      await tester.tap(find.text(labels[action.index]).last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.widget<DropdownButton<TemplateAction>>(dropdown).value,
        action,
      );
      for (final kind in [AreaKind.echo, AreaKind.netmail, AreaKind.local]) {
        final area = find.byType(DropdownButton<AreaKind>);
        await tester.ensureVisible(area);
        await tester.tap(area);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text(kind.groupLabel).last);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const Key('template-preview-body')), findsOneWidget);
      }
    }
    debugPrint('template-smoke: modes checked');
    await tap('Закрыть');
    await tap('Сбросить шаблон');
    expect(TemplateSettings(prefs).read(), isNull);
    await tester.enterText(
      find.byKey(const Key('message-template')),
      '@include no-file.txt',
    );
    await tap('Сохранить шаблон');
    expect(find.text('Исправьте ошибки шаблона'), findsOneWidget);
    expect(TemplateSettings(prefs).read(), isNull);
    expect(
      TemplateEngine().render('@random no-file.txt', TemplateContext()).valid,
      isFalse,
    );

    debugPrint('template-smoke: reset checked');
    await prefs.setString(TemplateSettings.key, 'corrupt');
    final api = FakeTransport();
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MessageScreen(
          conferenceId: 'SMOKE',
          conferenceName: 'Smoke',
          conferenceDescription: '',
          canRead: true,
          canPost: true,
          repository: MessageRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Новое сообщение'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось применить шаблон'), findsOneWidget);
    await tap('Использовать штатное оформление');
    debugPrint('template-smoke: fallback checked');
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, 'Текст')).enabled,
      isTrue,
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
  });
}
