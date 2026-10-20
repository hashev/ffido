import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'uue_file_types.dart';
import 'uue_picker.dart';

class PlatformUueFiles implements UueFiles {
  static const channel = MethodChannel('org.ffido/files');
  final Future<String?> Function(String) chooseSave;
  final Future<void> Function(String, Uint8List) write;
  PlatformUueFiles({
    Future<String?> Function(String)? chooseSave,
    Future<void> Function(String, Uint8List)? write,
  }) : chooseSave = chooseSave ?? _chooseSave,
       write = write ?? _write;
  static Future<String?> _chooseSave(String name) async =>
      (await getSaveLocation(suggestedName: name))?.path;
  static Future<void> _write(String path, Uint8List bytes) =>
      XFile.fromData(bytes, mimeType: 'application/octet-stream').saveTo(path);
  @override
  Future<SelectedUueFile?> pick(int maxBytes) => pickUueFile(maxBytes);
  @override
  Future<bool> save(String name, Uint8List bytes) async {
    name = safeUueName(name);
    if (bytes.length > 16 * 1024 * 1024) throw uueFileLimit();
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return await channel.invokeMethod<bool>('saveUue', {
            'name': name,
            'bytes': bytes,
          }) ??
          false;
    }
    final path = await chooseSave(name);
    if (path == null) return false;
    await write(path, bytes);
    return true;
  }
}
