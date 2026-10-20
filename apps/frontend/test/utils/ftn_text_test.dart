import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/utils/ftn_text.dart';

void main() {
  test(
    'FTN prefixes preserve whitespace and recognize only leading markers',
    () {
      const cases = {
        '> a': 1,
        '>> a': 2,
        ' AB> a': 1,
        'AB>> a': 2,
        '> AB> a': 2,
        'AB> CD> a': 2,
        'ЮК> a': 1,
        '𐐀> a': 1,
        '': 0,
        'a > b': 0,
        '  text': 0,
        'ABCDEFGHI> x': 0,
      };
      for (final entry in cases.entries) {
        expect(quoteDepth(entry.key), entry.value, reason: entry.key);
      }
      const original = 'Текст\n\n AB> цитата\n>> вложенная\n  отступ';
      for (final brightness in Brightness.values) {
        final colors = ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        );
        expect(ftnTextSpan(original, colors).toPlainText(), original);
        for (final depth in [0, 1, 2]) {
          final a = quoteColor(colors, depth).computeLuminance();
          final b = colors.surface.computeLuminance();
          expect(
            (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
      expect(quoteReply('AB> q\n>> n'), '> AB> q\n> >> n\n\n');
    },
  );
  testWidgets(
    'controller preserves composing, selection, edits and clipboard',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            if (call.method == 'Clipboard.getData') return {'text': copied};
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final controller = FtnTextController();
      final undo = UndoHistoryController();
      addTearDown(undo.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(controller: controller, undoController: undo),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '> Привет\n>> Мир',
          selection: TextSelection.collapsed(offset: 8),
          composing: TextRange(start: 2, end: 8),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(TextField));
      final span = controller.buildTextSpan(
        context: context,
        withComposing: true,
      );
      expect(span.toPlainText(), controller.text);
      expect(
        span.children!.whereType<TextSpan>().any(
          (s) => s.style?.decoration == TextDecoration.underline,
        ),
        isTrue,
      );
      expect(controller.selection.baseOffset, 8);
      expect(controller.value.composing, const TextRange(start: 2, end: 8));
      controller.value = const TextEditingValue(
        text: 'Текст\n AB> цитата\n> >> вложенная',
        selection: TextSelection(baseOffset: 0, extentOffset: 29),
      );
      // Exercise Flutter's copy action without introducing presentation markup.
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      expect(
        controller
            .buildTextSpan(context: context, withComposing: false)
            .toPlainText(),
        controller.text,
      );
      expect(copied, controller.text);
      controller.text = 'Первый';
      await tester.pump(const Duration(milliseconds: 600));
      controller.text = '> Второй';
      await tester.pump(const Duration(milliseconds: 600));
      undo.undo();
      await tester.pump();
      expect(controller.text, 'Первый');
      final long = List.filled(10000, '> цитата').join('\n');
      controller.text = long;
      expect(
        controller
            .buildTextSpan(context: context, withComposing: false)
            .toPlainText(),
        long,
      );
    },
  );
}
