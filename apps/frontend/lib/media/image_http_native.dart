import 'dart:io';

import 'image_http.dart';

class PlatformImageHttp implements ImageHttp {
  // Fresh system trust, no FFIDO transport, credentials, cookie jar or overrides.
  final HttpClient _client = HttpClient(
    context: SecurityContext(withTrustedRoots: true),
  );
  @override
  Future<ImageResponse> request(Uri uri, String method) async {
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'image/png,image/jpeg,image/gif,image/webp',
    );
    final response = await request.close();
    return ImageResponse(response.statusCode, {
      for (final name in ['content-type', 'content-length', 'location'])
        if (response.headers.value(name) != null)
          name: response.headers.value(name)!,
    }, response);
  }

  @override
  void close() => _client.close(force: true);
}
