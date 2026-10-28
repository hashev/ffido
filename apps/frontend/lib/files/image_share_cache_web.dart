import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> cleanup() async {}
Future<XFile> prepare(String name, String mime, Uint8List bytes) async =>
    XFile.fromData(bytes, mimeType: mime, name: name);
