import 'dart:async';
import 'package:flutter/material.dart';

/// Утилита для debounce операций (например, поиска)
class Debouncer {
  final Duration duration;
  Timer? _timer;

  Debouncer({this.duration = const Duration(milliseconds: 300)});

  /// Выполнить действие с debounce
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Отменить ожидающий вызов
  void cancel() {
    _timer?.cancel();
  }

  /// Освободить ресурсы
  void dispose() {
    _timer?.cancel();
  }
}
