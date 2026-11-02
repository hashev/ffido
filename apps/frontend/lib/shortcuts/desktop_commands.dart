import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DesktopCommand {
  unread(
    'Следующее непрочитанное',
    'В обычной эхе, включая переход в следующую эху',
    PhysicalKeyboardKey.keyU,
    'U',
  ),
  reply(
    'Ответить',
    'Обычный ответ на открытое письмо с цитатой',
    PhysicalKeyboardKey.keyR,
    'R',
  ),
  compose(
    'Новое письмо',
    'Новый черновик в текущей области',
    PhysicalKeyboardKey.keyN,
    'N',
  ),
  search(
    'Поиск по письмам',
    'Поиск во всей текущей доступной области',
    PhysicalKeyboardKey.keyF,
    'F',
  ),
  list(
    'К списку писем',
    'От открытого письма к списку текущей области',
    PhysicalKeyboardKey.keyL,
    'L',
  ),
  help(
    'Горячие клавиши',
    'Локальная справка в каталоге, читателе и редакторе',
    PhysicalKeyboardKey.f1,
    'F1',
  );

  const DesktopCommand(this.label, this.description, this.key, this.letter);
  final String label, description, letter;
  final PhysicalKeyboardKey key;

  String keys(TargetPlatform platform) {
    if (this == help) return 'F1';
    final primary =
        '${platform == TargetPlatform.macOS ? 'Cmd' : 'Ctrl'}+$letter';
    return this == search
        ? '$primary${platform == TargetPlatform.macOS ? ' / Ctrl+F' : ''} / F6'
        : primary;
  }
}

bool desktopCommandsEnabled({TargetPlatform? platform, bool web = kIsWeb}) =>
    !web &&
    {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(platform ?? defaultTargetPlatform);

/// Match physical positions so Russian and Latin layouts use the same keys.
DesktopCommand? matchDesktopCommand(
  KeyEvent event, {
  required bool control,
  required bool meta,
  required bool shift,
  required bool alt,
  required TargetPlatform platform,
  bool web = kIsWeb,
}) {
  if (event is! KeyDownEvent || shift || alt) return null;
  if (!control && !meta && event.physicalKey == PhysicalKeyboardKey.f6) {
    return DesktopCommand.search;
  }
  if (control && !meta && event.physicalKey == PhysicalKeyboardKey.keyF) {
    return DesktopCommand.search;
  }
  if (!desktopCommandsEnabled(platform: platform, web: web)) return null;
  if (!control && !meta && event.physicalKey == PhysicalKeyboardKey.f1) {
    return DesktopCommand.help;
  }
  if (platform == TargetPlatform.macOS ? !meta || control : !control || meta) {
    return null;
  }
  for (final command in DesktopCommand.values) {
    if (command != DesktopCommand.help && event.physicalKey == command.key) {
      return command;
    }
  }
  return null;
}

String commandTooltip(DesktopCommand command, String label) =>
    desktopCommandsEnabled()
    ? '$label (${command.keys(defaultTargetPlatform)})'
    : label;
