import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/shortcuts/command_scope.dart';
import 'package:fido/shortcuts/desktop_commands.dart';

void main() {
  testWidgets(
    'Web and mobile keep legacy search without new reader shortcuts',
    (t) async {
      var searched = 0, invoked = 0;
      await t.pumpWidget(
        MaterialApp(
          home: CommandScope(
            actions: {
              for (final command in DesktopCommand.values)
                command: CommandAction.enabled(
                  () =>
                      command == DesktopCommand.search ? searched++ : invoked++,
                ),
            },
            child: const Scaffold(body: Text('reader')),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (final key in [
        LogicalKeyboardKey.keyN,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyU,
        LogicalKeyboardKey.keyL,
      ]) {
        await t.sendKeyEvent(key);
      }
      await t.sendKeyEvent(LogicalKeyboardKey.keyF);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      await t.sendKeyEvent(LogicalKeyboardKey.f6);
      await t.pumpAndSettle();
      expect(invoked, 0);
      expect(searched, 2);
      expect(find.byType(AlertDialog), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
