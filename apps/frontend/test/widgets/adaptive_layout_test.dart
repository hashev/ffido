import 'package:fido/widgets/adaptive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('width classes and columns use local logical constraints', () {
    expect(LayoutWidth.of(599), LayoutWidth.compact);
    expect(LayoutWidth.of(600), LayoutWidth.medium);
    expect(LayoutWidth.of(1023), LayoutWidth.medium);
    expect(LayoutWidth.of(1024), LayoutWidth.expanded);
    expect(actionColumns(288, TextScaler.noScaling, 5), 2);
    expect(actionColumns(288, TextScaler.linear(2), 5), 1);
    expect(actionColumns(960, TextScaler.noScaling, 5), 5);
    expect(actionColumns(960, TextScaler.noScaling, 1), 1);
  });
  testWidgets('content fills narrow space and constrains a wide window', (
    t,
  ) async {
    for (final width in [320.0, 599.0, 600.0, 1023.0, 1024.0, 1440.0]) {
      await t.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              child: const AdaptiveContent(
                maxWidth: 400,
                child: Placeholder(key: Key('content')),
              ),
            ),
          ),
        ),
      );
      expect(
        t.getSize(find.byKey(const Key('content'))).width,
        width < 400 ? width : 400,
      );
      expect(t.takeException(), isNull);
    }
  });
}
