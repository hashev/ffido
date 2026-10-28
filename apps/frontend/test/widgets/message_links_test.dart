import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/files/image_actions.dart';
import 'package:fido/utils/ftn_text.dart';
import 'package:fido/widgets/message_link_text.dart';

class ActionsFake extends ImageActions {
  final opened = <Uri>[];
  bool answer = true;
  @override
  bool get canShare => true;
  @override
  Future<bool> openBrowser(Uri uri) async {
    opened.add(uri);
    return answer;
  }

  @override
  Future<bool> save(String name, Uint8List bytes) async => false;
  @override
  Future<ImageActionResult> share(
    String name,
    String mime,
    Uint8List bytes,
    Rect origin, {
    bool Function()? isActive,
  }) async => ImageActionResult.cancelled;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'exact selectable FTN text, contrast and touch in $brightness',
      (tester) async {
        const body =
            '  AB> https://e.org/a?q=1#x\n>>  www.example.org\n  конец';
        final actions = ActionsFake();
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: Scaffold(body: MessageLinkText(body, actions: actions)),
          ),
        );
        final selectable = tester.widget<SelectableText>(
          find.byType(SelectableText),
        );
        expect(selectable.textSpan!.toPlainText(), body);
        final spans = selectable.textSpan!.children!.cast<TextSpan>();
        final link = spans.firstWhere((span) => span.recognizer != null);
        expect(link.style!.decoration, TextDecoration.underline);
        final a = link.style!.color!.computeLuminance(),
            b = scheme.surface.computeLuminance();
        expect(
          (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          spans.any(
            (s) =>
                s.text == '  AB> ' && s.style!.color == quoteColor(scheme, 1),
          ),
          isTrue,
        );
        expect(actions.opened, isEmpty);
        // Tap at the glyph offset, exercising the actual gesture recognizer.
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        final position = editable.renderEditable
            .getLocalRectForCaret(const TextPosition(offset: 12))
            .center;
        await tester.tapAt(editable.renderEditable.localToGlobal(position));
        await tester.pump();
        expect(actions.opened.single.toString(), 'https://e.org/a?q=1#x');
        final controller = editable.widget.controller;
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: body.length,
        );
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'];
            }
            return null;
          },
        );
        editable.copySelection(SelectionChangedCause.keyboard);
        await tester.pump();
        expect(copied, body);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      },
    );
  }
  testWidgets('keyboard, error, no retry and editor remains inert', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final actions = ActionsFake()..answer = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageLinkText('https://e.org', actions: actions),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Открыть https://e.org во внешнем браузере'),
      findsOneWidget,
    );
    semantics.dispose();
    final focus = tester
        .widgetList<Focus>(find.byType(Focus))
        .firstWhere(
          (f) => f.focusNode?.debugLabel?.startsWith('Открыть ') ?? false,
        );
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(actions.opened.length, 1);
    expect(find.text('Не удалось открыть внешний браузер'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(actions.opened.length, 1);
    tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(actions.opened.length, 1);

    final controller = FtnTextController()..text = 'https://e.org';
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(actions.opened.length, 1);
    final span = controller.buildTextSpan(
      context: tester.element(find.byType(TextField)),
      withComposing: false,
    );
    expect(
      span.children!.cast<TextSpan>().every((s) => s.recognizer == null),
      isTrue,
    );
  });
}
