import 'package:fido/widgets/message_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('whole action tiles fit 320dp at text scale $scale', (t) async {
      t.view.physicalSize = const Size(320, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final semantics = t.ensureSemantics();
      bool? quoted;
      var replies = 0;
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MessageActions(
                  actions: [
                    MessageAction(
                      label: 'Ответить в эху',
                      icon: Icons.reply,
                      onPressed: () => replies++,
                      variantsLabel: 'Вид ответа',
                      onVariant: (v) => quoted = v,
                    ),
                    for (final label in [
                      'Переслать',
                      'Ответить лично',
                      'Ответить в другую область…',
                      'Цепочка сообщений',
                    ])
                      MessageAction(
                        label: label,
                        icon: Icons.forward,
                        onPressed: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final buttons = find.byType(TextButton);
      final first = t.getRect(buttons.at(0));
      final second = t.getRect(buttons.at(1));
      if (scale == 1) {
        expect(first.top, second.top);
      } else {
        expect(second.top, greaterThan(first.bottom));
      }
      for (final element in buttons.evaluate()) {
        final rect = t.getRect(find.byElementPredicate((e) => e == element));
        expect(rect.left, greaterThanOrEqualTo(16));
        expect(rect.right, lessThanOrEqualTo(304));
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      await t.tap(find.text('Ответить в эху'));
      expect(replies, 1);
      expect(find.bySemanticsLabel('Вид ответа'), findsOneWidget);
      await t.tap(find.byTooltip('Вид ответа'));
      await t.pumpAndSettle();
      await t.tap(find.text('Без цитаты'));
      await t.pumpAndSettle();
      expect(quoted, false);
      expect(t.takeException(), isNull);
      semantics.dispose();
    });
  }
}
