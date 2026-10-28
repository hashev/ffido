import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'uue_file_types.dart';

Future<Directory> _root() async =>
    Directory('${(await getTemporaryDirectory()).path}/ffido-image-share');
Future<void> cleanup({Directory? root, DateTime? now}) async {
  final directory = root ?? await _root();
  if (!await directory.exists()) return;
  final before = (now ?? DateTime.now()).subtract(const Duration(hours: 24));
  await for (final child in directory.list(followLinks: false)) {
    if (child is Directory && (await child.stat()).modified.isBefore(before)) {
      await child.delete(recursive: true);
    }
  }
}

Future<XFile> prepare(
  String name,
  String mime,
  Uint8List bytes, {
  Directory? root,
}) async {
  final directory = root ?? await _root();
  await directory.create(recursive: true);
  final folder = await Directory(
    '${directory.path}/${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
  ).create();
  final file = File('${folder.path}/${safeUueName(name)}');
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path, mimeType: mime, name: safeUueName(name));
}
