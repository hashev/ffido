import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'image_http.dart';

class PlatformImageHttp implements ImageHttp {
  final _abort = web.AbortController();
  @override
  Future<ImageResponse> request(Uri uri, String method) async {
    final response = await web.window
        .fetch(
          uri.toString().toJS,
          web.RequestInit(
            method: method,
            credentials: 'omit',
            redirect: 'manual',
            cache: 'no-store',
            signal: _abort.signal,
          ),
        )
        .toDart;
    // Browsers hide manual redirect targets. Fail closed rather than follow
    // an uninspectable downgrade/credential redirect or bypass CORS.
    if (response.type == 'opaqueredirect' || response.type == 'opaque') {
      throw const ImageLoadException(
        'Браузер не разрешает проверить перенаправление',
      );
    }
    return ImageResponse(response.status, {
      for (final name in ['content-type', 'content-length', 'location'])
        if (response.headers.get(name) != null)
          name: response.headers.get(name)!,
    }, _stream(response));
  }

  Stream<List<int>> _stream(web.Response response) async* {
    final reader =
        response.body?.getReader() as web.ReadableStreamDefaultReader?;
    if (reader == null) return;
    try {
      while (true) {
        final chunk = await reader.read().toDart;
        if (chunk.done) break;
        yield (chunk.value as JSUint8Array).toDart;
      }
    } finally {
      await reader.cancel().toDart;
      reader.releaseLock();
    }
  }

  @override
  void close() => _abort.abort();
}
