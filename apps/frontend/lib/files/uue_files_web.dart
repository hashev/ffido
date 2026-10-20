import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'uue_file_types.dart';
import 'uue_picker.dart';

class PlatformUueFiles implements UueFiles {
  @override
  Future<SelectedUueFile?> pick(int maxBytes) => pickUueFile(maxBytes);
  @override
  Future<bool> save(String name, Uint8List bytes) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final url = web.URL.createObjectURL(blob);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = safeUueName(name);
    web.document.body?.append(link);
    link.click();
    link.remove();
    Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
    return true; // The browser now owns the download; final disk success is not observable.
  }
}
