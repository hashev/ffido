import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'uue_file_types.dart';

Future<SelectedUueFile?> pickUueFile(int maxBytes) async {
  if (maxBytes <= 0 || maxBytes > 16 * 1024 * 1024) throw uueFileLimit();
  final selected = await openFile();
  if (selected == null) return null;
  if (await selected.length() > maxBytes) throw uueFileLimit();
  final builder = BytesBuilder(copy: false);
  await for (final bytes in selected.openRead(0, maxBytes + 1)) {
    if (builder.length + bytes.length > maxBytes) throw uueFileLimit();
    builder.add(bytes);
  }
  return SelectedUueFile(safeUueName(selected.name), builder.takeBytes());
}
