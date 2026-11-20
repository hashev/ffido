import 'dart:js_interop';

import 'package:flutter/widgets.dart';

import 'telegram_environment.dart';

@JS('Telegram.WebApp')
external _App? get _application;

extension type _App(JSObject _) implements JSObject {
  external String get initData;
  external String get colorScheme;
  external double get viewportHeight;
  external _Insets? get safeAreaInset;
  external _Insets? get contentSafeAreaInset;
  @JS('BackButton')
  external _Back get backButton;
  external void ready();
  external void onEvent(String name, JSFunction callback);
  external void offEvent(String name, JSFunction callback);
  external void enableClosingConfirmation();
  external void disableClosingConfirmation();
}

extension type _Insets(JSObject _) implements JSObject {
  external double get top;
  external double get bottom;
  external double get left;
  external double get right;
}

extension type _Back(JSObject _) implements JSObject {
  external void show();
  external void hide();
}

class _WebTelegramHost extends TelegramHost {
  _WebTelegramHost() {
    try {
      app = _application;
    } catch (_) {
      app = null;
    }
    if (initData.isEmpty) {
      app = null;
      return;
    }
    changed = (() => notifyListeners()).toJS;
    backClicked = (() => back?.call()).toJS;
    for (final event in [
      'themeChanged',
      'viewportChanged',
      'safeAreaChanged',
      'contentSafeAreaChanged',
    ]) {
      app!.onEvent(event, changed!);
    }
    app!.onEvent('backButtonClicked', backClicked!);
  }
  _App? app;
  JSFunction? changed, backClicked;
  VoidCallback? back;
  @override
  String get initData => app?.initData ?? '';
  @override
  String? get startNode {
    try {
      return Uri.splitQueryString(initData)['start_param'];
    } catch (_) {
      return null;
    }
  }

  @override
  bool get dark => app?.colorScheme != 'light';
  @override
  double? get viewportHeight {
    final height = app?.viewportHeight;
    return height != null && height.isFinite && height > 0 ? height : null;
  }

  EdgeInsets padding(_Insets? value) => value == null
      ? EdgeInsets.zero
      : EdgeInsets.fromLTRB(value.left, value.top, value.right, value.bottom);
  @override
  EdgeInsets get insets =>
      padding(app?.safeAreaInset) + padding(app?.contentSafeAreaInset);
  @override
  void ready() => app?.ready();
  @override
  void navigation(bool canPop, VoidCallback callback) {
    back = callback;
    if (canPop) {
      app?.backButton.show();
    } else {
      app?.backButton.hide();
    }
  }

  @override
  void editing(bool value) {
    if (value) {
      app?.enableClosingConfirmation();
    } else {
      app?.disableClosingConfirmation();
    }
  }

  @override
  void dispose() {
    if (app != null && changed != null && backClicked != null) {
      for (final event in [
        'themeChanged',
        'viewportChanged',
        'safeAreaChanged',
        'contentSafeAreaChanged',
      ]) {
        app!.offEvent(event, changed!);
      }
      app!.offEvent('backButtonClicked', backClicked!);
    }
    super.dispose();
  }
}

TelegramHost createTelegramHost() => _WebTelegramHost();
final TelegramHost telegramHost = createTelegramHost();
