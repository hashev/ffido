import 'dart:async';

class ImageResponse {
  final int status;
  final Map<String, String> headers;
  final Stream<List<int>> body;
  const ImageResponse(this.status, this.headers, this.body);
}

abstract class ImageHttp {
  Future<ImageResponse> request(Uri uri, String method);
  void close();
}

class ImageLoadException implements Exception {
  final String message;
  const ImageLoadException(this.message);
  @override
  String toString() => message;
}
