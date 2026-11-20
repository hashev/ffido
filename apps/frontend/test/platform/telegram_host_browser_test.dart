@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/platform/telegram_host.dart';

void main() {
  test('missing SDK is a normal browser without Telegram authority', () {
    globalContext.delete('Telegram'.toJS);
    final host = createTelegramHost();
    expect(host.initData, isEmpty);
    expect(host.insets, EdgeInsets.zero);
    host.ready();
    host.editing(true);
    host.navigation(true, () {});
    host.dispose();
  });
  test(
    'theme viewport safe areas back and closing confirmation follow the SDK',
    () {
      final events = <String, JSFunction>{};
      bool ready = false,
          backVisible = false,
          closing = false,
          wentBack = false;
      final app =
          <String, Object?>{
                'initData': 'start_param=test&user=%7B%22id%22%3A123%7D',
                'colorScheme': 'light',
                'viewportHeight': 600,
                'safeAreaInset': {
                  'left': 1,
                  'top': 20,
                  'right': 2,
                  'bottom': 10,
                },
                'contentSafeAreaInset': {
                  'left': 0,
                  'top': 22,
                  'right': 0,
                  'bottom': 1,
                },
                'ready': (() {
                  ready = true;
                }).toJS,
                'onEvent': ((String name, JSFunction callback) {
                  events[name] = callback;
                }).toJS,
                'offEvent': ((String name, JSFunction callback) {
                  events.remove(name);
                }).toJS,
                'enableClosingConfirmation': (() {
                  closing = true;
                }).toJS,
                'disableClosingConfirmation': (() {
                  closing = false;
                }).toJS,
                'BackButton': {
                  'show': (() {
                    backVisible = true;
                  }).toJS,
                  'hide': (() {
                    backVisible = false;
                  }).toJS,
                },
              }.jsify()
              as JSObject;
      globalContext.setProperty('Telegram'.toJS, {'WebApp': app}.jsify());
      final host = createTelegramHost();
      expect(host.initData, contains('user='));
      expect(host.startNode, 'test');
      expect(host.dark, isFalse);
      expect(host.viewportHeight, 600);
      expect(host.insets, const EdgeInsets.fromLTRB(1, 42, 2, 11));
      int changes = 0;
      host.addListener(() {
        changes++;
      });
      app.setProperty('colorScheme'.toJS, 'dark'.toJS);
      events['themeChanged']!.callAsFunction();
      expect(host.dark, isTrue);
      expect(changes, 1);
      host.ready();
      expect(ready, isTrue);
      host.navigation(true, () {
        wentBack = true;
      });
      expect(backVisible, isTrue);
      events['backButtonClicked']!.callAsFunction();
      expect(wentBack, isTrue);
      host.navigation(false, () {});
      expect(backVisible, isFalse);
      host.editing(true);
      expect(closing, isTrue);
      host.editing(false);
      expect(closing, isFalse);
      host.dispose();
      expect(events, isEmpty);
      globalContext.delete('Telegram'.toJS);
    },
  );
}
