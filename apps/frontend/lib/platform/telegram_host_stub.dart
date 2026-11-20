import 'package:flutter/widgets.dart';

import 'telegram_environment.dart';

class BrowserTelegramHost extends TelegramHost {
  @override
  String get initData => '';
  @override
  String? get startNode => null;
  @override
  bool get dark => true;
  @override
  double? get viewportHeight => null;
  @override
  EdgeInsets get insets => EdgeInsets.zero;
  @override
  void ready() {}
  @override
  void navigation(bool canPop, VoidCallback back) {}
  @override
  void editing(bool value) {}
}

TelegramHost createTelegramHost() => BrowserTelegramHost();
final TelegramHost telegramHost = createTelegramHost();
