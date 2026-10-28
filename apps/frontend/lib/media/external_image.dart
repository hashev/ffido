import 'dart:async';
import 'dart:typed_data';

import '../utils/message_links.dart';
import '../utils/uue_image.dart';
import 'image_http.dart';
import 'image_http_native.dart'
    if (dart.library.js_interop) 'image_http_web.dart'
    as platform;
export 'image_http.dart';

class ExternalImage {
  final Uint8List bytes;
  final UueImageInfo info;
  ExternalImage(Uint8List bytes, this.info)
    : bytes = bytes.asUnmodifiableView();
  String get extension => switch (info.format) {
    'JPEG' => 'jpg',
    'WebP' => 'webp',
    _ => info.format.toLowerCase(),
  };
  String get mime => 'image/${info.format == 'JPEG' ? 'jpeg' : extension}';
  String get name => 'ffido-image.$extension';
}

class ExternalImageLoad {
  static const maxBytes = 16 * 1024 * 1024;
  final ImageHttp http;
  final Duration timeout;
  bool _closed = false;
  ExternalImageLoad({
    ImageHttp? http,
    this.timeout = const Duration(seconds: 15),
  }) : http = http ?? platform.PlatformImageHttp();
  void cancel() {
    _closed = true;
    http.close();
  }

  void _check() {
    if (_closed) throw const ImageLoadException('Загрузка отменена');
  }

  Future<ExternalImage> load(Uri uri) async {
    final timer = Timer(timeout, cancel);
    try {
      return await _load(uri).timeout(
        timeout,
        onTimeout: () {
          throw const ImageLoadException(
            'Превышено время загрузки (15 секунд)',
          );
        },
      );
    } finally {
      timer.cancel();
      cancel();
    }
  }

  Future<ExternalImage> _load(Uri original) async {
    if (!webUri(original)) throw const ImageLoadException('Недопустимый адрес');
    var redirects = 0;
    var effectiveUri = original.removeFragment();
    Future<ImageResponse> request(String method) async {
      var uri = effectiveUri;
      while (true) {
        _check();
        final response = await http.request(uri, method);
        _check();
        if (![301, 302, 303, 307, 308].contains(response.status)) {
          effectiveUri = uri;
          return response;
        }
        // Cancel body subscriptions even if a redirect sends a large payload.
        await response.body.take(0).drain<void>();
        final location = response.headers['location'];
        if (++redirects > 3 || location == null) {
          throw const ImageLoadException('Слишком много перенаправлений');
        }
        final next = uri.resolve(location);
        if (!webUri(next) ||
            (uri.scheme == 'https' && next.scheme != 'https')) {
          throw const ImageLoadException('Небезопасное перенаправление');
        }
        uri = next.removeFragment();
      }
    }

    bool rejectedMime(ImageResponse response) {
      final mime = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      return mime != null &&
          mime.isNotEmpty &&
          !{
            'image/png',
            'image/jpeg',
            'image/gif',
            'image/webp',
            'application/octet-stream',
            'binary/octet-stream',
          }.contains(mime);
    }

    final head = await request('HEAD');
    await head.body.take(0).drain<void>();
    if (head.status >= 200 && head.status < 300 && rejectedMime(head)) {
      throw const ImageLoadException(
        'Ссылка не является прямым PNG/JPEG/GIF/WebP',
      );
    }
    final response = await request('GET');
    if (response.status != 200 || rejectedMime(response)) {
      throw const ImageLoadException(
        'Изображение недоступно или формат не поддерживается',
      );
    }
    final length = int.tryParse(response.headers['content-length'] ?? '');
    if (length != null && length > maxBytes) {
      throw const ImageLoadException('Изображение больше 16 МиБ');
    }
    final builder = BytesBuilder(copy: false);
    var size = 0;
    final prefix = BytesBuilder(copy: false);
    var signatureKnown = false;
    await for (final chunk in response.body) {
      _check();
      if (!signatureKnown) {
        final needed = 65536 - prefix.length;
        prefix.add(chunk.length <= needed ? chunk : chunk.sublist(0, needed));
        final probe = prefix.toBytes();
        if (probe.length >= 12) {
          if (!_signature(probe)) {
            throw const ImageLoadException(
              'Неподдерживаемый формат изображения',
            );
          }
          signatureKnown = true;
        }
        final dimensions = uueImageInfo(probe);
        if (dimensions != null && !dimensions.allowed(16000000, 8192)) {
          throw const ImageLoadException(
            'Изображение превышает 16 Мп или 8192 пикселя',
          );
        }
      }
      if (size + chunk.length > maxBytes) {
        throw const ImageLoadException('Изображение больше 16 МиБ');
      }
      builder.add(chunk);
      size += chunk.length;
    }
    _check();
    final bytes = builder.takeBytes();
    final info = uueImageInfo(bytes);
    if (info == null) {
      throw const ImageLoadException(
        'Повреждённое или неподдерживаемое изображение',
      );
    }
    if (!info.allowed(16000000, 8192)) {
      throw const ImageLoadException(
        'Изображение превышает 16 Мп или 8192 пикселя',
      );
    }
    // Pixel decoding is performed by the bounded UI decoder before ready/share.
    return ExternalImage(bytes, info);
  }
}

bool _signature(Uint8List b) =>
    (b.length >= 8 && b[0] == 137 && b[1] == 80 && b[2] == 78 && b[3] == 71) ||
    (b.length >= 3 && b[0] == 255 && b[1] == 216 && b[2] == 255) ||
    (b.length >= 6 && String.fromCharCodes(b.take(6)).startsWith('GIF8')) ||
    (b.length >= 12 &&
        String.fromCharCodes(b.take(4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WEBP');
