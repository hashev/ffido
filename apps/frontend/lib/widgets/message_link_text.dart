import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../files/image_actions.dart';
import '../utils/ftn_text.dart';
import '../utils/message_links.dart';

class MessageLinkText extends StatefulWidget {
  final String text;
  final ImageActions? actions;
  const MessageLinkText(this.text, {super.key, this.actions});
  @override
  State<MessageLinkText> createState() => _MessageLinkTextState();
}

class _MessageLinkTextState extends State<MessageLinkText> {
  List<MessageLink> links = [];
  final recognizers = <TapGestureRecognizer>[];
  final nodes = <FocusNode>[];
  int? focused;
  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(covariant MessageLinkText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _release();
      _parse();
    }
  }

  void _parse() {
    links = messageLinks(widget.text);
    for (final link in links) {
      recognizers.add(
        TapGestureRecognizer()..onTap = () => unawaited(open(link.uri)),
      );
      nodes.add(FocusNode(debugLabel: 'Открыть ${link.uri.host} в браузере'));
    }
  }

  void _release() {
    for (final r in recognizers) {
      r.dispose();
    }
    for (final n in nodes) {
      n.dispose();
    }
    recognizers.clear();
    nodes.clear();
    focused = null;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  Future<void> open(Uri uri) async {
    try {
      if (await (widget.actions ?? PlatformImageActions()).openBrowser(uri)) {
        return;
      }
    } catch (_) {
      /* Show a local error, never retry automatically. */
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть внешний браузер')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final original = ftnTextSpan(widget.text, scheme);
    final spans = <TextSpan>[];
    var offset = 0;
    for (final span in original.children!.cast<TextSpan>()) {
      final text = span.text ?? '';
      final end = offset + text.length;
      var cursor = offset;
      for (var i = 0; i < links.length; i++) {
        final link = links[i];
        if (link.start >= end || link.end <= offset) continue;
        final start = link.start.clamp(offset, end),
            stop = link.end.clamp(offset, end);
        if (cursor < start) {
          spans.add(
            TextSpan(
              text: widget.text.substring(cursor, start),
              style: span.style,
            ),
          );
        }
        spans.add(
          TextSpan(
            text: widget.text.substring(start, stop),
            recognizer: recognizers[i],
            mouseCursor: SystemMouseCursors.click,
            style: TextStyle(
              color: scheme.brightness == Brightness.dark
                  ? const Color(0xFF90CAF9)
                  : const Color(0xFF0D47A1),
              decoration: TextDecoration.underline,
              backgroundColor: focused == i ? scheme.secondaryContainer : null,
            ),
          ),
        );
        cursor = stop;
      }
      if (cursor < end) {
        spans.add(
          TextSpan(text: widget.text.substring(cursor, end), style: span.style),
        );
      }
      offset = end;
    }
    Widget result = SelectableText.rich(
      TextSpan(style: ftnTextStyle(scheme), children: spans),
      style: ftnTextStyle(scheme),
    );
    // Each URL has a keyboard focus stop without replacing source characters
    // with WidgetSpans (which would change selection/copy offsets).
    for (var i = nodes.length - 1; i >= 0; i--) {
      final index = i;
      result = Focus(
        focusNode: nodes[i],
        onFocusChange: (value) {
          if (mounted) {
            setState(() {
              if (value) {
                focused = index;
              } else if (focused == index) {
                focused = null;
              }
            });
          }
        },
        onKeyEvent: (_, event) {
          if (nodes[index].hasPrimaryFocus &&
              event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            unawaited(open(links[index].uri));
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: result,
      );
      result = Semantics(
        container: true,
        explicitChildNodes: true,
        link: true,
        label: 'Открыть ${links[index].uri} во внешнем браузере',
        onTap: () => unawaited(open(links[index].uri)),
        child: result,
      );
    }
    return result;
  }
}
