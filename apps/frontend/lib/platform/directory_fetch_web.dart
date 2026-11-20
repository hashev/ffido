import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<String> fetchBackendDirectory() async {
  final controller = web.AbortController();
  final timer = Timer(const Duration(seconds: 10), () => controller.abort());
  try {
    final uri = Uri.base.resolve('backends.json');
    final response = await web.window
        .fetch(
          uri.toString().toJS,
          web.RequestInit(
            cache: 'no-store',
            redirect: 'error',
            signal: controller.signal,
          ),
        )
        .toDart;
    if (!response.ok) throw StateError('Не удалось загрузить каталог');
    return (await response.text().toDart).toDart;
  } finally {
    timer.cancel();
  }
}
