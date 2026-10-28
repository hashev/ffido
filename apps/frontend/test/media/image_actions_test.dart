import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fido/files/image_actions.dart';
import 'package:fido/files/uue_files.dart';

class Files extends UueFiles {
  String? name;
  Uint8List? bytes;
  bool answer = true;
  @override
  Future<SelectedUueFile?> pick(int maxBytes) async => null;
  @override
  Future<bool> save(String name, Uint8List bytes) async {
    this.name = name;
    this.bytes = bytes;
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('browser receives web URI only, failure stays observable', () async {
    final calls = <Uri>[];
    final actions = PlatformImageActions(
      launch: (uri) async {
        calls.add(uri);
        return false;
      },
    );
    for (final u in [
      'file:///tmp/x',
      'javascript:alert(1)',
      'https://u:p@e.org',
    ]) {
      expect(await actions.openBrowser(Uri.parse(u)), isFalse);
    }
    final uri = Uri.parse('https://e.org/a?q=x#f');
    expect(await actions.openBrowser(uri), isFalse);
    expect(calls, [uri]);
  });
  test(
    'file share preserves bytes/MIME and distinct cancel/unsupported/errors',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      for (final status in ShareResultStatus.values) {
        final actions = PlatformImageActions(
          send: (params) async {
            expect(params.text, isNull);
            expect(params.uri, isNull);
            expect(params.files!.single.mimeType, 'image/png');
            expect(await params.files!.single.readAsBytes(), bytes);
            expect(params.fileNameOverrides, ['a.png']);
            expect(params.downloadFallbackEnabled, isFalse);
            return ShareResult('test', status);
          },
        );
        expect(
          await actions.share(
            '../a.png',
            'image/png',
            bytes,
            const Rect.fromLTWH(0, 0, 10, 10),
          ),
          switch (status) {
            ShareResultStatus.success => ImageActionResult.handedOff,
            ShareResultStatus.dismissed => ImageActionResult.cancelled,
            _ => ImageActionResult.unsupported,
          },
        );
      }
      final actions = PlatformImageActions(
        send: (_) async => throw PlatformException(code: 'failed'),
      );
      await expectLater(
        actions.share('a.png', 'image/png', bytes, Rect.zero),
        throwsA(isA<PlatformException>()),
      );
      final files = Files()..answer = false;
      final save = PlatformImageActions(files: files);
      expect(await save.save('../a.png', bytes), isFalse);
      expect(files.name, 'a.png');
      expect(files.bytes, bytes);
    },
  );
  test('lost reader context cannot hand a file to another app', () async {
    var sent = 0;
    final actions = PlatformImageActions(
      send: (_) async {
        sent++;
        return const ShareResult('x', ShareResultStatus.success);
      },
    );
    expect(
      await actions.share(
        'a.png',
        'image/png',
        Uint8List(1),
        Rect.zero,
        isActive: () => false,
      ),
      ImageActionResult.cancelled,
    );
    expect(sent, 0);
  });
  test('Android uses dedicated file channel, never URL-only sharing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformImageActions.channel, (call) async {
          calls.add(call);
          return call.method == 'openBrowser' ? true : 'cancelled';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlatformImageActions.channel, null),
    );
    final actions = PlatformImageActions();
    expect(await actions.openBrowser(Uri.parse('https://e.org')), isTrue);
    expect(
      await actions.share(
        'a.png',
        'image/png',
        Uint8List.fromList([1]),
        Rect.zero,
      ),
      ImageActionResult.cancelled,
    );
    expect(calls.last.method, 'share');
    expect(
      (calls.last.arguments as Map).keys,
      unorderedEquals(['name', 'mime', 'bytes']),
    );
  });
}
