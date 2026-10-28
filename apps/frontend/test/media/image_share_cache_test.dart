import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fido/files/image_share_cache_native.dart' as cache;

void main() {
  test('private unique files survive repeated share; only expired directories removed', () async {
    final root = await Directory.systemTemp.createTemp('ffido-share-test-');
    addTearDown(() => root.delete(recursive: true));
    final first = await cache.prepare(
      '../first.png',
      'image/png',
      Uint8List.fromList([1, 2]),
      root: root,
    );
    final second = await cache.prepare(
      'second.jpg',
      'image/jpeg',
      Uint8List.fromList([3]),
      root: root,
    );
    expect(await first.readAsBytes(), [1, 2]);
    expect(await second.readAsBytes(), [3]);
    expect(first.path, startsWith(root.path));
    expect(first.name, 'first.png');
    final old = Directory('${root.path}/expired');
    await old.create();
    await File('${old.path}/x').writeAsString('old');
    // Advancing the injected clock expires both old files without touching a
    // just-created directory whose mtime is ahead of that clock's TTL boundary.
    await cache.cleanup(root: root, now: DateTime.now());
    expect(await File(first.path).exists(), isTrue);
    await cache.cleanup(
      root: root,
      now: DateTime.now().add(const Duration(hours: 25)),
    );
    expect(await File(first.path).exists(), isFalse);
    expect(await old.exists(), isFalse);
  });
}
