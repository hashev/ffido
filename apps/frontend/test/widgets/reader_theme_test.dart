import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/utils/reader_theme.dart';
import 'package:fido/utils/ftn_text.dart';

num contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    test('theme contrast and states $brightness', () {
      final theme = readerTheme(brightness: brightness),
          states = <WidgetState>{};
      final colors = theme.colorScheme;
      expect(
        contrast(colors.primary, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.onPrimary, colors.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.onSurfaceVariant, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      for (final depth in [0, 1, 2]) {
        for (final background in [
          theme.scaffoldBackgroundColor,
          colors.surface,
        ]) {
          expect(
            contrast(quoteColor(colors, depth), background),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      final style = theme.iconButtonTheme.style!;
      expect(style.mouseCursor!.resolve(states), SystemMouseCursors.click);
      expect(
        style.mouseCursor!.resolve({WidgetState.disabled}),
        SystemMouseCursors.basic,
      );
      expect(style.overlayColor!.resolve({WidgetState.hovered}), isNotNull);
      expect(
        style.overlayColor!.resolve({WidgetState.focused}),
        isNot(style.overlayColor!.resolve(states)),
      );
      expect(
        style.foregroundColor!.resolve({WidgetState.disabled}),
        isNot(style.foregroundColor!.resolve(states)),
      );
    });
  }
  testWidgets(
    'mouse hover, keyboard activation, disabled state and text cursor',
    (tester) async {
      var calls = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: readerTheme(),
          home: Scaffold(
            body: Column(
              children: [
                IconButton(
                  focusNode: focus,
                  tooltip: 'Действие',
                  onPressed: () => calls++,
                  icon: const Icon(Icons.refresh),
                ),
                const IconButton(
                  tooltip: 'Недоступно',
                  onPressed: null,
                  icon: Icon(Icons.send),
                ),
                const TextField(),
              ],
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(find.byTooltip('Действие')));
      await tester.pump();
      final regions = tester.widgetList<MouseRegion>(
        find.descendant(
          of: find.byTooltip('Действие'),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(regions.any((r) => r.cursor == SystemMouseCursors.click), isTrue);
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.widgetList<IconButton>(find.byType(IconButton)).last.onPressed,
        isNull,
      );
      await mouse.moveTo(tester.getCenter(find.byType(TextField)));
      await tester.pump();
      expect(
        tester
            .widgetList<MouseRegion>(
              find.descendant(
                of: find.byType(TextField),
                matching: find.byType(MouseRegion),
              ),
            )
            .any((r) => r.cursor == SystemMouseCursors.text),
        isTrue,
      );
      await mouse.removePointer();
    },
  );
}
