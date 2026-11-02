// Isolated native keyboard acceptance. No real account, network or persistent preferences.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fido/shortcuts/desktop_commands.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/templates/template_settings.dart';

import 'fake_transport.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final api = FakeTransport();
  wire.Message message(String id) => wire.Message(
    id: id,
    subject: 'Test $id',
    body: 'Synthetic keyboard acceptance',
    fromName: 'Author',
    fromAddress: '2:1/2',
  );
  api.messages = (_) async =>
      wire.ListMessagesResponse(messages: [message('g#1'), message('g#2')]);
  api.message = (r) async => message(r.messageId);
  api.conference = (r) async =>
      wire.Conference(id: r.conferenceId, canRead: true, canPost: true);
  api.find = (_) async => wire.FindMessageResponse();
  HardwareKeyboard.instance.addHandler((event) {
    final keyboard = HardwareKeyboard.instance;
    final command = matchDesktopCommand(
      event,
      control: keyboard.isControlPressed,
      meta: keyboard.isMetaPressed,
      shift: keyboard.isShiftPressed,
      alt: keyboard.isAltPressed,
      platform: TargetPlatform.macOS,
    );
    if (command != null) {
      final before = screenState();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint(
          'KEYBOARD-ACCEPTANCE ${command.name}: $before -> ${screenState()}',
        );
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    return false;
  });
  runApp(
    MaterialApp(
      navigatorObservers: [fixtureRoutes],
      home: MessageScreen(
        conferenceId: 'KEYBOARD.FIXTURE',
        conferenceName: 'Keyboard acceptance (isolated)',
        conferenceDescription: '',
        canRead: true,
        canPost: true,
        kind: AreaKind.echo,
        repository: MessageRepository(api),
        loadTemplate: () async => const TemplateBundle('@quote'),
      ),
    ),
  );
  if (const bool.fromEnvironment('FFIDO_SHORTCUTS_REPLAY')) unawaited(replay());
}

// These diagnostics belong only to this synthetic fixture, never to the app.
List<Widget> screenWidgets() {
  final visible = <Widget>[];
  void visit(Element element) {
    visible.add(element.widget);
    element.visitChildren(visit);
  }

  final route = fixtureRoutes.current;
  final context = route is ModalRoute<dynamic> ? route.subtreeContext : null;
  if (context is Element) visit(context);
  return visible;
}

String screenState() {
  final visible = screenWidgets();
  final texts = visible.whereType<Text>().map((text) => text.data).toSet();
  if (texts.contains('Поиск по письмам')) return 'search-dialog';
  if (texts.contains('Горячие клавиши')) return 'help-dialog';
  if (texts.contains('Сообщение')) return 'composer';
  if (texts.contains('К списку')) return 'message';
  if (visible.whereType<ListTile>().isNotEmpty) return 'message-list';
  return 'other';
}

Future<void> emit(KeyEvent event) async {
  // Replay the captured Flutter event stream, including its Cmd state. This
  // checks the native widget tree; it does not simulate delivery by the OS.
  ui.PlatformDispatcher.instance.onKeyData?.call(
    ui.KeyData(
      type: event is KeyDownEvent ? ui.KeyEventType.down : ui.KeyEventType.up,
      physical: event.physicalKey.usbHidUsage,
      logical: event.logicalKey.keyId,
      timeStamp: event.timeStamp,
      character: null,
      synthesized: true,
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 350));
}

Future<void> command(
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey logical,
) async {
  final time = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
  await emit(
    KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.metaLeft,
      logicalKey: LogicalKeyboardKey.metaLeft,
      timeStamp: time,
    ),
  );
  await emit(
    KeyDownEvent(physicalKey: physical, logicalKey: logical, timeStamp: time),
  );
  await emit(
    KeyUpEvent(physicalKey: physical, logicalKey: logical, timeStamp: time),
  );
  await emit(
    KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.metaLeft,
      logicalKey: LogicalKeyboardKey.metaLeft,
      timeStamp: time,
    ),
  );
}

Future<void> replay() async {
  await Future<void>.delayed(const Duration(seconds: 2));
  try {
    await command(PhysicalKeyboardKey.keyU, LogicalKeyboardKey.keyU);
    if (screenState() != 'message') {
      throw StateError('Cmd+U did not open a message');
    }
    for (final editor in screenWidgets().whereType<EditableText>()) {
      if (editor.readOnly) {
        editor.focusNode.requestFocus();
        break;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await command(PhysicalKeyboardKey.keyL, LogicalKeyboardKey.keyL);
    if (screenState() != 'message-list') {
      throw StateError('Cmd+L did not return to the message list');
    }
    await command(PhysicalKeyboardKey.keyF, LogicalKeyboardKey.keyF);
    if (screenState() != 'search-dialog') {
      throw StateError('Cmd+F did not open search');
    }
    fixtureRoutes.current?.navigator?.pop();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await command(PhysicalKeyboardKey.keyU, const LogicalKeyboardKey(0x433));
    if (screenState() != 'message') {
      throw StateError('Russian Cmd+U did not open a message');
    }
    await command(PhysicalKeyboardKey.keyL, const LogicalKeyboardKey(0x434));
    if (screenState() != 'message-list') {
      throw StateError('Russian Cmd+L did not return to list');
    }
    await command(PhysicalKeyboardKey.keyF, const LogicalKeyboardKey(0x430));
    if (screenState() != 'search-dialog') {
      throw StateError('Russian Cmd+F did not open search');
    }
    debugPrint(
      'KEYBOARD-ACCEPTANCE PASS: captured Cmd+L/F replay changes the native screen in Latin/Russian layouts',
    );
  } catch (error, stack) {
    debugPrint('KEYBOARD-ACCEPTANCE FAIL: $error\n$stack');
  }
}

final fixtureRoutes = FixtureRoutes();

class FixtureRoutes extends NavigatorObserver {
  Route<dynamic>? current;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      current = route;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      current = previousRoute;
}
