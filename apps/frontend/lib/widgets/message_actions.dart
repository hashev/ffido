import 'package:flutter/material.dart';

import 'adaptive_layout.dart';

class MessageAction {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final String? variantsLabel;
  final ValueChanged<bool>? onVariant;
  const MessageAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.variantsLabel,
    this.onVariant,
  });
}

class MessageActions extends StatelessWidget {
  final List<MessageAction> actions;
  const MessageActions({super.key, required this.actions});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = actionColumns(
        constraints.maxWidth,
        MediaQuery.textScalerOf(context),
        actions.length,
      );
      return Column(
        children: [
          for (var start = 0; start < actions.length; start += columns)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      if (i != 0) const SizedBox(width: 8),
                      Expanded(
                        child: start + i < actions.length
                            ? _ActionTile(action: actions[start + i])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _ActionTile extends StatelessWidget {
  final MessageAction action;
  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Tooltip(
            message: action.tooltip ?? action.label,
            excludeFromSemantics: true,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 88),
                padding: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: action.onPressed,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon),
                  const SizedBox(height: 8),
                  Text(action.label, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
        if (action.variantsLabel != null)
          PopupMenuButton<bool>(
            tooltip: action.variantsLabel,
            enabled: action.onVariant != null,
            onSelected: action.onVariant,
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: Text('С цитатой')),
              PopupMenuItem(value: false, child: Text('Без цитаты')),
            ],
            child: Semantics(
              label: action.variantsLabel,
              button: true,
              enabled: action.onVariant != null,
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Icon(
                    Icons.arrow_drop_down,
                    color: action.onVariant == null
                        ? Theme.of(context).disabledColor
                        : null,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class ReaderNavigation extends StatelessWidget {
  final VoidCallback? previous, next;
  final String nextTooltip;
  const ReaderNavigation({
    super.key,
    this.previous,
    this.next,
    required this.nextTooltip,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'Предыдущее',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final vertical = (painter.width + 64) * 2 > constraints.maxWidth;
      painter.dispose();
      final buttons = [
        TextButton.icon(
          onPressed: previous,
          icon: const Icon(Icons.chevron_left),
          label: const Text('Предыдущее'),
        ),
        Tooltip(
          message: nextTooltip,
          excludeFromSemantics: true,
          child: TextButton.icon(
            onPressed: next,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Следующее'),
          ),
        ),
      ];
      return vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: buttons,
            )
          : Row(
              children: [for (final button in buttons) Expanded(child: button)],
            );
    },
  );
}
