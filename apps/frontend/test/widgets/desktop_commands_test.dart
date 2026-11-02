import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/shortcuts/desktop_commands.dart';

void main() {
  for (final platform in TargetPlatform.values) {
    for (final web in [false, true]) {
      test('command registry $platform web=$web', () {
        final desktop =
            !web &&
            {
              TargetPlatform.windows,
              TargetPlatform.linux,
              TargetPlatform.macOS,
            }.contains(platform);
        final mac = platform == TargetPlatform.macOS;
        final keys = <String>{};
        for (final command in DesktopCommand.values) {
          expect(keys.add(command.keys(platform)), isTrue);
          final event = KeyDownEvent(
            physicalKey: command.key,
            logicalKey: LogicalKeyboardKey.keyA,
            timeStamp: Duration.zero,
          );
          DesktopCommand? match({
            bool shift = false,
            bool alt = false,
            bool? control,
            bool? meta,
          }) => matchDesktopCommand(
            event,
            control: control ?? (command != DesktopCommand.help && !mac),
            meta: meta ?? (command != DesktopCommand.help && mac),
            shift: shift,
            alt: alt,
            platform: platform,
            web: web,
          );
          expect(
            match(),
            desktop || (!mac && command == DesktopCommand.search)
                ? command
                : null,
          );
          expect(match(shift: true), isNull);
          expect(match(alt: true), isNull);
          expect(match(control: true, meta: true), isNull);
          expect(
            matchDesktopCommand(
              KeyRepeatEvent(
                physicalKey: command.key,
                logicalKey: LogicalKeyboardKey.keyA,
                timeStamp: Duration.zero,
              ),
              control: !mac,
              meta: mac,
              shift: false,
              alt: false,
              platform: platform,
              web: web,
            ),
            isNull,
          );
          expect(
            command.keys(platform),
            command == DesktopCommand.help
                ? 'F1'
                : startsWith(mac ? 'Cmd+' : 'Ctrl+'),
          );
        }
        for (final key in [PhysicalKeyboardKey.keyF, PhysicalKeyboardKey.f6]) {
          expect(
            matchDesktopCommand(
              KeyDownEvent(
                physicalKey: key,
                logicalKey: LogicalKeyboardKey.keyA,
                timeStamp: Duration.zero,
              ),
              control: key == PhysicalKeyboardKey.keyF,
              meta: false,
              shift: false,
              alt: false,
              platform: platform,
              web: web,
            ),
            DesktopCommand.search,
          );
        }
      });
    }
  }
}
