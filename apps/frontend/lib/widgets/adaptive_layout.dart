import 'dart:math' as math;

import 'package:flutter/material.dart';

enum LayoutWidth {
  compact,
  medium,
  expanded;

  static LayoutWidth of(double width) => width < 600
      ? compact
      : width < 1024
      ? medium
      : expanded;
}

/// Constrains presentation without replacing the screen's state or controllers.
class AdaptiveContent extends StatelessWidget {
  static const listWidth = 1120.0;
  static const readerWidth = 960.0;
  static const formWidth = 800.0;

  final Widget child;
  final double maxWidth;
  const AdaptiveContent({
    super.key,
    required this.child,
    this.maxWidth = listWidth,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

/// A bounded number of columns; enlarged labels get more space, never less text.
int actionColumns(double width, TextScaler scaler, int count) => math.max(
  1,
  math.min(count, ((width + 8) / (128 * scaler.scale(14) / 14 + 8)).floor()),
);
