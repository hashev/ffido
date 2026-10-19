import 'package:flutter/material.dart';

final _initial = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Only a contiguous FTN quote prefix counts; an expression `a > b` does not.
int quoteDepth(String line) {
  var offset = 0, depth = 0;
  while (offset < line.length) {
    while (offset < line.length &&
        (line[offset] == ' ' || line[offset] == '\t')) {
      offset++;
    }
    var end = offset;
    for (var initials = 0; initials < 8 && end < line.length; initials++) {
      final match = _initial.matchAsPrefix(line, end);
      if (match == null) break;
      end = match.end;
    }
    if (end < line.length && line[end] == '>') {
      depth++;
      offset = end + 1;
    } else {
      break;
    }
  }
  return depth;
}

Color quoteColor(ColorScheme scheme, int depth) => depth == 0
    ? scheme.onSurface
    : scheme.brightness == Brightness.dark
    ? (depth.isOdd ? const Color(0xFFFFD180) : const Color(0xFF80D8FF))
    : (depth.isOdd ? const Color(0xFF795000) : const Color(0xFF005070));

TextStyle ftnTextStyle(ColorScheme scheme) => TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: const ['Menlo', 'Consolas'],
  fontSize: 14,
  height: 1.5,
  color: scheme.onSurface,
);

bool uueDataLine(String line) {
  if (line.isEmpty) return false;
  final count = (line.codeUnitAt(0) - 32) & 63;
  return count <= 45 &&
      line.length == 1 + 4 * ((count + 2) ~/ 3) &&
      line.codeUnits.every((c) => c >= 32 && c <= 96);
}

final uueBeginLine = RegExp(r'^begin [0-7]{3,4} [^\r\n]+$');

TextSpan ftnTextSpan(
  String text,
  ColorScheme scheme, {
  TextStyle? style,
  TextRange? composing,
}) {
  final spans = <TextSpan>[];
  var offset = 0;
  var inUue = false;
  for (final line in text.split('\n')) {
    final end = offset + line.length;
    if (uueBeginLine.hasMatch(line)) inUue = true;
    final data =
        inUue &&
        (uueBeginLine.hasMatch(line) || uueDataLine(line) || line == 'end');
    final color = quoteColor(scheme, data ? 0 : quoteDepth(line));
    if (inUue && (!data || line == 'end')) inUue = false;
    final startComposition = composing == null
        ? end
        : composing.start.clamp(offset, end);
    final endComposition = composing == null
        ? end
        : composing.end.clamp(offset, end);
    spans.add(
      TextSpan(
        text: text.substring(offset, startComposition),
        style: TextStyle(color: color),
      ),
    );
    if (endComposition > startComposition) {
      spans.add(
        TextSpan(
          text: text.substring(startComposition, endComposition),
          style: TextStyle(color: color, decoration: TextDecoration.underline),
        ),
      );
    }
    spans.add(
      TextSpan(
        text: text.substring(endComposition, end),
        style: TextStyle(color: color),
      ),
    );
    if (end < text.length) spans.add(const TextSpan(text: '\n'));
    offset = end + 1;
  }
  return TextSpan(style: style ?? ftnTextStyle(scheme), children: spans);
}

String quoteReply(String original) =>
    '${original.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n').map((line) => '> $line').join('\n')}\n\n';

class FtnTextController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => ftnTextSpan(
    text,
    Theme.of(context).colorScheme,
    style: style,
    composing:
        withComposing &&
            value.isComposingRangeValid &&
            !value.composing.isCollapsed
        ? value.composing
        : null,
  );
}
