import 'dart:typed_data';
import 'dart:convert';

import '../api/api_exceptions.dart';

class SelectedUueFile {
  final String name;
  final Uint8List bytes;
  SelectedUueFile(this.name, Uint8List bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
}

abstract class UueFiles {
  Future<SelectedUueFile?> pick(int maxBytes);
  Future<bool> save(String name, Uint8List bytes);
}

String safeUueName(String input) {
  if (input.length > 4096) return 'attachment.bin';
  var value = input
      .split(RegExp(r'[/\\]'))
      .last
      .replaceAll(RegExp(r'[\x00-\x1f\x7f:*?"<>|]'), '_')
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  if (value.isEmpty) return 'attachment.bin';
  final name = StringBuffer();
  var bytes = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final length = utf8.encode(character).length;
    if (bytes + length > 200) break;
    name.write(character);
    bytes += length;
  }
  value = name.toString();
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(value)) {
    value = '_$value';
  }
  return value;
}

ValidationException uueFileLimit() =>
    const ValidationException(message: 'Файл превышает лимит сервера');
