import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fido/media/external_image.dart';
import 'package:fido/media/image_http_native.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

class FakeHttp implements ImageHttp {
  final FutureOr<ImageResponse> Function(Uri, String) handle;
  final calls = <String>[];
  bool closed = false;
  FakeHttp(this.handle);
  @override
  Future<ImageResponse> request(Uri uri, String method) async {
    calls.add('$method $uri');
    return handle(uri, method);
  }

  @override
  void close() {
    closed = true;
  }
}

ImageResponse response({
  int status = 200,
  Map<String, String> headers = const {},
  List<int>? bytes,
}) => ImageResponse(status, headers, Stream.value(bytes ?? png));
void main() {
  test(
    'extensionless sniff and unsupported HEAD preserve actual bytes/MIME',
    () async {
      final http = FakeHttp(
        (_, method) => method == 'HEAD' ? response(status: 405) : response(),
      );
      final result = await ExternalImageLoad(http: http)
          .load(Uri.parse('https://e.org/image?q=secret#fragment'));
      expect(result.bytes, png);
      expect(result.mime, 'image/png');
      expect(result.name, 'ffido-image.png');
      expect(http.calls, [
        'HEAD https://e.org/image?q=secret',
        'GET https://e.org/image?q=secret',
      ]);
      expect(http.closed, isTrue);
      expect(() => result.bytes[0] = 0, throwsUnsupportedError);
    },
  );
  test(
    'explicit non-image MIME never downloads HTML/SVG despite extension',
    () async {
      for (final mime in ['text/html', 'image/svg+xml', 'text/plain']) {
        final http = FakeHttp(
          (_, _) => response(headers: {'content-type': mime}),
        );
        await expectLater(
          ExternalImageLoad(http: http).load(Uri.parse('https://e.org/a.png')),
          throwsA(isA<ImageLoadException>()),
        );
        expect(http.calls.length, 1);
        expect(http.closed, isTrue);
      }
    },
  );
  test(
    'bad bytes, known/unknown stream size, pixel/dimension and cancellation',
    () async {
      final huge = Uint8List.fromList(png);
      ByteData.sublistView(huge).setUint32(16, 8193);
      for (final r in [
        response(bytes: [1, 2, 3]),
        response(bytes: huge),
        response(headers: {'content-length': '16777217'}),
        ImageResponse(
          200,
          {},
          Stream.fromIterable([png, Uint8List(16 * 1024 * 1024)]),
        ),
      ]) {
        final http = FakeHttp((_, method) => method == 'HEAD' ? response() : r);
        await expectLater(
          ExternalImageLoad(http: http).load(Uri.parse('https://e.org/a')),
          throwsA(isA<ImageLoadException>()),
        );
        expect(http.closed, isTrue);
      }
      final http = FakeHttp((_, _) => response());
      final load = ExternalImageLoad(http: http)..cancel();
      await expectLater(
        load.load(Uri.parse('https://e.org')),
        throwsA(isA<ImageLoadException>()),
      );
      expect(http.calls, isEmpty);
    },
  );
  test(
    'unknown format is stopped after bounded sniff, no later chunks',
    () async {
      var chunks = 0;
      Stream<List<int>> body() async* {
        for (var i = 0; i < 20; i++) {
          chunks++;
          yield Uint8List(65536);
        }
      }

      final http = FakeHttp(
        (_, m) => m == 'HEAD' ? response() : ImageResponse(200, {}, body()),
      );
      await expectLater(
        ExternalImageLoad(http: http).load(Uri.parse('https://e.org')),
        throwsA(isA<ImageLoadException>()),
      );
      expect(chunks, 1);
    },
  );
  test(
    'redirects validate every hop, forbid downgrade and credentials',
    () async {
      for (final target in [
        'http://e.org/x',
        'https://user@e.org/x',
        'file:///tmp/x',
      ]) {
        final http = FakeHttp(
          (_, _) => response(status: 302, headers: {'location': target}),
        );
        await expectLater(
          ExternalImageLoad(http: http).load(Uri.parse('https://e.org')),
          throwsA(isA<ImageLoadException>()),
        );
        expect(http.calls.length, 1);
      }
      final http = FakeHttp(
        (_, _) => response(status: 302, headers: {'location': '/loop'}),
      );
      await expectLater(
        ExternalImageLoad(http: http).load(Uri.parse('https://e.org')),
        throwsA(isA<ImageLoadException>()),
      );
      expect(http.calls.length, 4);
      var hops = 0;
      final accepted = FakeHttp(
        (_, m) => m == 'HEAD' && hops++ < 3
            ? response(status: 302, headers: {'location': '/next$hops'})
            : response(),
      );
      expect(
        (await ExternalImageLoad(http: accepted)
                .load(Uri.parse('https://e.org')))
            .bytes,
        png,
      );
    },
  );
  test(
    'native TLS refuses an untrusted certificate without custom CA',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ffido-image-tls-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final key = '${directory.path}/key.pem',
          cert = '${directory.path}/cert.pem';
      final generated = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        key,
        '-out',
        cert,
        '-days',
        '1',
        '-subj',
        '/CN=localhost',
      ]);
      expect(generated.exitCode, 0);
      final context = SecurityContext()
        ..useCertificateChain(cert)
        ..usePrivateKey(key);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response.add(png);
        unawaited(request.response.close());
      }, onError: (Object _) {});
      await expectLater(
        ExternalImageLoad(http: PlatformImageHttp())
            .load(Uri.parse('https://127.0.0.1:${server.port}/image')),
        throwsA(isA<HandshakeException>()),
      );
    },
  );
  test('timeout closes the transport', () async {
    final http = FakeHttp((_, _) => Completer<ImageResponse>().future);
    await expectLater(
      ExternalImageLoad(
        http: http,
        timeout: const Duration(milliseconds: 10),
      ).load(Uri.parse('https://e.org')),
      throwsA(isA<ImageLoadException>()),
    );
    expect(http.closed, isTrue);
  });
  test(
    'native transport sends no cookies or authorization, including redirect',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <HttpRequest>[];
      server.listen((request) {
        requests.add(request);
        expect(request.headers.value('authorization'), isNull);
        expect(request.headers.value('cookie'), isNull);
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.cookies.add(Cookie('remote', 'secret'));
        if (request.method != 'HEAD') request.response.add(png);
        unawaited(request.response.close());
      });
      final image = await ExternalImageLoad(http: PlatformImageHttp())
          .load(Uri.parse('http://127.0.0.1:${server.port}/x'));
      expect(image.bytes, png);
      expect(requests.length, 2);
    },
  );
}
