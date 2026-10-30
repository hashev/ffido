import 'package:flutter/material.dart';

import 'uue_text.dart';
export 'uue_text.dart';

final _initial = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Only a contiguous FTN quote prefix counts; an expression `a > b` does not.
({int depth, int end, int marker, String initials}) _quotePrefix(String line) {
  var offset = 0, depth = 0, prefixEnd = 0, marker = -1;
  var author = '';
  while (offset < line.length) {
    while (offset < line.length &&
        (line[offset] == ' ' || line[offset] == '\t')) {
      offset++;
    }
    final start = offset;
    var end = offset;
    if (end < line.length && line[end] == '?') {
      end++;
    } else {
      for (var initials = 0; initials < 8 && end < line.length; initials++) {
        final match = _initial.matchAsPrefix(line, end);
        if (match == null) break;
        end = match.end;
      }
    }
    if (end >= line.length || line[end] != '>') break;
    if (author.isEmpty && end > start) author = line.substring(start, end);
    if (depth == 0) marker = end;
    depth++;
    offset = prefixEnd = end + 1;
  }
  return (depth: depth, end: prefixEnd, marker: marker, initials: author);
}

int quoteDepth(String line) => _quotePrefix(line).depth;

String _quoteInitials(String name) {
  final initials = name
      .trim()
      .split(RegExp(r'\s+'))
      .map((part) {
        return _initial.firstMatch(part)?.group(0) ?? '';
      })
      .join()
      .toUpperCase();
  return initials.isEmpty ? '?' : String.fromCharCodes(initials.runes.take(8));
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

String quoteReply(String original, String authorName) {
  final initials = _quoteInitials(authorName);
  final lines = original
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final quoted = lines
      .map((line) {
        if (line.trim().isEmpty) return line;
        final prefix = _quotePrefix(line);
        if (prefix.depth == 0) return '$initials> $line';
        if (prefix.initials.isNotEmpty) {
          // Preserve named nested prefixes and their whitespace verbatim.
          return '${line.substring(0, prefix.marker + 1)}>${line.substring(prefix.marker + 1)}';
        }
        final author = initials;
        // Remove only the conventional separator, preserving the quoted text's indent.
        final rest = line.substring(prefix.end);
        final text = rest.startsWith(' ') ? rest.substring(1) : rest;
        return '$author${'>' * (prefix.depth + 1)} $text';
      })
      .join('\n');
  return '$quoted\n\n';
}

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
