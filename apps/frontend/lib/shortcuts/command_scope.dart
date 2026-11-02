import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop_commands.dart';

class CommandAction {
  final VoidCallback? invoke;
  final String? reason;
  const CommandAction.enabled(VoidCallback callback)
    : invoke = callback,
      reason = null;
  const CommandAction.disabled(String message)
    : invoke = null,
      reason = message;
}

/// Commands belong to the visible route; this scope never observes global keys.
class CommandScope extends StatefulWidget {
  final Widget child;
  final Map<DesktopCommand, CommandAction> actions;
  final String readerUnavailableReason;
  const CommandScope({
    super.key,
    required this.child,
    this.actions = const {},
    this.readerUnavailableReason = 'Доступно в экране чтения',
  });

  @override
  State<CommandScope> createState() => _CommandScopeState();
}

class _CommandScopeState extends State<CommandScope> {
  bool helpOpen = false;

  Future<void> showHelp() async {
    if (helpOpen || ModalRoute.of(context)?.isCurrent != true) return;
    final previousFocus = FocusManager.instance.primaryFocus;
    final editor = previousFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    final selection = editor?.widget.controller.selection;
    final text = editor?.widget.controller.text;
    helpOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Горячие клавиши'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final command in DesktopCommand.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${command.label} — ${command.keys(defaultTargetPlatform)}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(command.description),
                          Text(
                            command == DesktopCommand.help
                                ? 'Доступно'
                                : widget.actions[command]?.reason ??
                                      (widget.actions[command]?.invoke != null
                                          ? 'Доступно'
                                          : widget.readerUnavailableReason),
                          ),
                        ],
                      ),
                    ),
                  const Text(
                    'Команды читателя не действуют при вводе текста и поверх других экранов. Переназначение пока недоступно.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } finally {
      helpOpen = false;
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          previousFocus?.context != null &&
          previousFocus!.canRequestFocus) {
        previousFocus.requestFocus();
        await WidgetsBinding.instance.endOfFrame;
        if (mounted &&
            editor?.mounted == true &&
            selection != null &&
            editor!.widget.controller.text == text) {
          editor.widget.controller.selection = selection;
        }
      }
    }
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (helpOpen || ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final command = matchDesktopCommand(
      event,
      control: keyboard.isControlPressed,
      meta: keyboard.isMetaPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      platform: defaultTargetPlatform,
    );
    if (command == null) return KeyEventResult.ignored;
    if (command == DesktopCommand.help) {
      showHelp();
      return KeyEventResult.handled;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    final focusedWidget = focus?.widget;
    final editor = focusedWidget is EditableText
        ? focusedWidget
        : focus?.findAncestorStateOfType<EditableTextState>()?.widget;
    // SelectableText also uses EditableText, but remains part of the reader.
    if (editor != null && !editor.readOnly) {
      return KeyEventResult.ignored;
    }
    final action = widget.actions[command];
    if (action == null) return KeyEventResult.ignored;
    action.invoke?.call();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => _CommandHelp(
    showHelp: showHelp,
    child: Focus(autofocus: true, onKeyEvent: onKey, child: widget.child),
  );
}

class _CommandHelp extends InheritedWidget {
  final VoidCallback showHelp;
  const _CommandHelp({required this.showHelp, required super.child});
  @override
  bool updateShouldNotify(_CommandHelp oldWidget) => false;
}

class CommandHelpButton extends StatelessWidget {
  const CommandHelpButton({super.key});
  @override
  Widget build(BuildContext context) => desktopCommandsEnabled()
      ? CommandIconButton(
          command: DesktopCommand.help,
          label: 'Горячие клавиши',
          icon: Icons.help_outline,
          onPressed: context
              .dependOnInheritedWidgetOfExactType<_CommandHelp>()!
              .showHelp,
        )
      : const SizedBox.shrink();
}

/// Keep the button's accessible name stable while showing its shortcut on hover.
class CommandIconButton extends StatelessWidget {
  final DesktopCommand command;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const CommandIconButton({
    super.key,
    required this.command,
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: commandTooltip(command, label),
    excludeFromSemantics: true,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, semanticLabel: label),
    ),
  );
}
