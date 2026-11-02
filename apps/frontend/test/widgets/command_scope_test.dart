import 'package:fido/media/external_image.dart';
import 'package:fido/media/message_images.dart';
import 'package:fido/widgets/external_image_preview.dart';

import '../media/external_image_test.dart' show FakeHttp, response;
import '../media/message_images_test.dart' show ready;
import 'message_links_test.dart' show ActionsFake;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/shortcuts/desktop_commands.dart';
import 'package:fido/shortcuts/command_scope.dart';

Future<void> chord(
  WidgetTester t,
  LogicalKeyboardKey key, {
  bool mac = false,
  PhysicalKeyboardKey? physical,
}) async {
  final modifier = mac
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await t.sendKeyDownEvent(modifier);
  await t.sendKeyEvent(
    key,
    physicalKey: physical,
    platform: physical == null ? null : 'macos',
  );
  await t.sendKeyUpEvent(modifier);
  await t.pumpAndSettle();
}

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
      'scope dispatch and input guard on $platform including Russian physical key',
      (t) async {
        final controller = TextEditingController(text: 'Привет');
        addTearDown(controller.dispose);
        var invoked = 0;
        await t.pumpWidget(
          MaterialApp(
            home: CommandScope(
              actions: {
                DesktopCommand.reply: CommandAction.enabled(() => invoked++),
              },
              child: Scaffold(body: TextField(controller: controller)),
            ),
          ),
        );
        await t.pumpAndSettle();
        await chord(
          t,
          LogicalKeyboardKey.keyR,
          mac: platform == TargetPlatform.macOS,
        );
        await chord(
          t,
          const LogicalKeyboardKey(0x440),
          physical: PhysicalKeyboardKey.keyR,
          mac: platform == TargetPlatform.macOS,
        );
        expect(invoked, 2);
        await t.tap(find.byType(TextField));
        await t.pump();
        await chord(
          t,
          LogicalKeyboardKey.keyR,
          mac: platform == TargetPlatform.macOS,
        );
        expect(invoked, 2);
        expect(controller.text, 'Привет');
        await t.enterText(find.byType(TextField), 'Ручной ввод');
        expect(controller.text, 'Ручной ввод');
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 6,
        );
        await chord(
          t,
          LogicalKeyboardKey.keyC,
          mac: platform == TargetPlatform.macOS,
        );
        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 6),
        );
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
  testWidgets('repeat events never dispatch again', (t) async {
    var invoked = 0;
    await t.pumpWidget(
      MaterialApp(
        home: CommandScope(
          actions: {
            DesktopCommand.compose: CommandAction.enabled(() => invoked++),
          },
          child: const Scaffold(body: Text('reader')),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyN);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.keyN);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.keyN);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyN);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(invoked, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  testWidgets('modal routes block all background commands', (t) async {
    var invoked = 0;
    await t.pumpWidget(
      MaterialApp(
        home: CommandScope(
          actions: {
            for (final command in DesktopCommand.values)
              command: CommandAction.enabled(() => invoked++),
          },
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const AlertDialog(content: Text('image or confirmation')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    for (final key in [
      LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.keyN,
      LogicalKeyboardKey.keyU,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyF,
    ]) {
      await chord(t, key);
    }
    await t.sendKeyEvent(LogicalKeyboardKey.f6);
    await t.sendKeyEvent(LogicalKeyboardKey.f1);
    await t.pumpAndSettle();
    expect(invoked, 0);
    expect(find.text('Горячие клавиши'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('image or confirmation'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  testWidgets(
    'real image viewer consumes Escape and isolates reader commands',
    (t) async {
      final owner = MessageImages(
        'https://e.org',
        createLoad: () =>
            ExternalImageLoad(http: FakeHttp((_, _) async => response())),
      );
      addTearDown(owner.dispose);
      owner.more();
      var invoked = 0;
      await t.pumpWidget(
        MaterialApp(
          home: CommandScope(
            actions: {
              for (final command in DesktopCommand.values)
                command: CommandAction.enabled(() => invoked++),
            },
            child: Scaffold(
              body: ListenableBuilder(
                listenable: owner,
                builder: (_, _) => ExternalImagePreview(
                  owner: owner,
                  entry: owner.entries.single,
                  actions: ActionsFake(),
                ),
              ),
            ),
          ),
        ),
      );
      await ready(t, owner);
      await t.tap(find.byType(InkWell));
      await t.pumpAndSettle();
      for (final key in [
        LogicalKeyboardKey.keyU,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyN,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyL,
      ]) {
        await chord(t, key);
      }
      expect(invoked, 0);
      expect(find.byType(ExternalImageViewer), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(ExternalImageViewer), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    'mobile scope preserves legacy search and ignores new bindings',
    (t) async {
      var searched = 0, composed = 0;
      await t.pumpWidget(
        MaterialApp(
          home: CommandScope(
            actions: {
              DesktopCommand.search: CommandAction.enabled(() => searched++),
              DesktopCommand.compose: CommandAction.enabled(() => composed++),
            },
            child: const Scaffold(body: Text('Mobile reader')),
          ),
        ),
      );
      await t.pumpAndSettle();
      await chord(t, LogicalKeyboardKey.keyN);
      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      await t.pumpAndSettle();
      expect(composed, 0);
      expect(find.byType(AlertDialog), findsNothing);
      await chord(t, LogicalKeyboardKey.keyF);
      await t.sendKeyEvent(LogicalKeyboardKey.f6);
      await t.pumpAndSettle();
      expect(searched, 2);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
  for (final width in [390.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'help layout, F1 dedup and field focus/selection $width $brightness',
        (t) async {
          t.view.physicalSize = Size(width, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final controller = TextEditingController(text: 'Черновик');
          final focus = FocusNode();
          addTearDown(controller.dispose);
          addTearDown(focus.dispose);
          await t.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.7)),
                child: child!,
              ),
              home: CommandScope(
                readerUnavailableReason:
                    'Команды читателя недоступны в редакторе',
                child: Scaffold(
                  appBar: AppBar(actions: const [CommandHelpButton()]),
                  body: TextField(controller: controller, focusNode: focus),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.tap(find.byType(TextField));
          controller.selection = const TextSelection(
            baseOffset: 1,
            extentOffset: 4,
          );
          await t.sendKeyEvent(LogicalKeyboardKey.f1);
          await t.pumpAndSettle();
          await t.sendKeyEvent(LogicalKeyboardKey.f1);
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('Ответить — Cmd+R'), findsOneWidget);
          expect(find.textContaining('Ctrl+F / F6'), findsOneWidget);
          expect(
            find.text('Команды читателя недоступны в редакторе'),
            findsNWidgets(5),
          );
          expect(t.takeException(), isNull);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          expect(controller.text, 'Черновик');
          expect(
            controller.selection,
            const TextSelection(baseOffset: 1, extentOffset: 4),
          );
          await t.tap(find.byTooltip('Горячие клавиши (F1)'));
          await t.pumpAndSettle();
          await t.tap(find.text('Закрыть'));
          await t.pumpAndSettle();
          expect(controller.text, 'Черновик');
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }
}
