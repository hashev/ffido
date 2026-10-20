import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/files/uue_files_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformUueFiles.channel, null);
  });
  test(
    'desktop cancellation does not write and write errors propagate',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      var writes = 0;
      final cancelled = PlatformUueFiles(
        chooseSave: (_) async => null,
        write: (_, _) async {
          writes++;
        },
      );
      expect(await cancelled.save('a.bin', Uint8List(1)), isFalse);
      expect(writes, 0);
      final failed = PlatformUueFiles(
        chooseSave: (_) async => '/chosen/file',
        write: (_, _) async => throw StateError('disk'),
      );
      await expectLater(failed.save('a.bin', Uint8List(1)), throwsStateError);
      final saved = PlatformUueFiles(
        chooseSave: (name) async {
          expect(name, 'safe.bin');
          return '/chosen/file';
        },
        write: (path, data) async {
          expect(path, '/chosen/file');
          expect(data, [0, 255, 1]);
          writes++;
        },
      );
      expect(
        await saved.save('../safe.bin', Uint8List.fromList([0, 255, 1])),
        isTrue,
      );
      expect(writes, 1);
    },
  );
  test(
    'mobile uses system export channel with exact bytes and propagates cancel',
    () async {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(PlatformUueFiles.channel, (call) async {
              expect(call.method, 'saveUue');
              final args = call.arguments as Map;
              expect(args['name'], 'a.bin');
              expect(args['bytes'], [0, 255]);
              return false;
            });
        expect(
          await PlatformUueFiles().save('a.bin', Uint8List.fromList([0, 255])),
          isFalse,
        );
      }
    },
  );
}
