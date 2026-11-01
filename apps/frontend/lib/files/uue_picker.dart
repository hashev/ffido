import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'uue_file_types.dart';

Future<SelectedUueFile?> pickUueFile(
  int maxBytes, {
  Future<XFile?> Function()? chooseFile,
}) async {
  if (maxBytes <= 0 || maxBytes > 16 * 1024 * 1024) throw uueFileLimit();
  final selected = await (chooseFile ?? openFile)();
  if (selected == null) return null;
  if (await selected.length() > maxBytes) throw uueFileLimit();
  final builder = BytesBuilder(copy: false);
  await for (final bytes in selected.openRead()) {
    if (builder.length + bytes.length > maxBytes) throw uueFileLimit();
    builder.add(bytes);
  }
  return SelectedUueFile(safeUueName(selected.name), builder.takeBytes());
}
