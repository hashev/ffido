import 'package:flutter/widgets.dart';

abstract class TelegramHost extends ChangeNotifier {
  String get initData;
  String? get startNode;
  bool get dark;
  double? get viewportHeight;
  EdgeInsets get insets;
  void ready();
  void navigation(bool canPop, VoidCallback back);
  void editing(bool value);
}
