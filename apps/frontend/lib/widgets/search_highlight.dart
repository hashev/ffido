import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/message_search.dart';

// Split spans without changing characters, link recognizers or quote styles.
List<TextSpan> highlightSearch(
  List<TextSpan> spans,
  List<SearchRange> ranges,
  Color color,
) {
  final output = <TextSpan>[];
  var offset = 0;
  for (final span in spans) {
    final text = span.text ?? '';
    final end = offset + text.length;
    final cuts = <int>{offset, end};
    for (final range in ranges) {
      if (range.start < end && range.end > offset) {
        cuts.add(range.start.clamp(offset, end));
        cuts.add(range.end.clamp(offset, end));
      }
    }
    final boundaries = cuts.toList()..sort();
    for (var i = 0; i + 1 < boundaries.length; i++) {
      final start = boundaries[i], stop = boundaries[i + 1];
      final marked = ranges.any((r) => r.start <= start && r.end >= stop);
      output.add(
        TextSpan(
          text: text.substring(start - offset, stop - offset),
          style: marked
              ? (span.style ?? const TextStyle()).copyWith(
                  backgroundColor: color,
                )
              : span.style,
          recognizer: span.recognizer,
          mouseCursor: span.mouseCursor,
        ),
      );
    }
    offset = end;
  }
  return output;
}

// Layout callbacks also run when an image above the match changes its height.
class SearchReveal extends SingleChildRenderObjectWidget {
  final int? offset;
  final bool enabled;
  const SearchReveal({
    super.key,
    required super.child,
    this.offset,
    this.enabled = true,
  });
  @override
  RenderObject createRenderObject(BuildContext context) =>
      SearchRevealRender(offset, enabled, Scrollable.maybeOf(context));
  @override
  void updateRenderObject(
    BuildContext context,
    covariant SearchRevealRender renderObject,
  ) {
    renderObject.update(offset, enabled, Scrollable.maybeOf(context));
  }
}

class SearchRevealRender extends RenderProxyBox {
  int? offset;
  bool enabled;
  ScrollableState? scrollable;
  bool scheduled = false;
  SearchRevealRender(this.offset, this.enabled, this.scrollable);
  void update(int? value, bool active, ScrollableState? scroll) {
    offset = value;
    enabled = active;
    scrollable = scroll;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    if (!enabled || offset == null || scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!attached ||
          !enabled ||
          offset == null ||
          scrollable == null ||
          !scrollable!.mounted) {
        return;
      }
      Rect? target;
      void visit(RenderObject node) {
        if (target != null) return;
        if (node is RenderParagraph) {
          final boxes = node.getBoxesForSelection(
            TextSelection(baseOffset: offset!, extentOffset: offset! + 1),
          );
          if (boxes.isNotEmpty) {
            target = boxes.first.toRect().shift(
              node.localToGlobal(Offset.zero),
            );
          }
        } else if (node is RenderEditable) {
          target = node
              .getLocalRectForCaret(TextPosition(offset: offset!))
              .shift(node.localToGlobal(Offset.zero));
        } else {
          node.visitChildren(visit);
        }
      }

      visit(this);
      if (target == null) return;
      final viewport = scrollable!.context.findRenderObject();
      if (viewport is! RenderBox) return;
      final position = scrollable!.position;
      final top = viewport.localToGlobal(Offset.zero).dy;
      final relative = target!.top - top;
      if (relative < 0 ||
          relative + target!.height > position.viewportDimension) {
        position.jumpTo(
          (position.pixels + relative - position.viewportDimension * .25).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }
}
