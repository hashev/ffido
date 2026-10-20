import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:fido/files/uue_files.dart';
import 'package:fido/utils/uue_image.dart';
import 'package:fido/utils/ftn_text.dart';

void main() {
  test(
    'formats come from signatures and dimensions are bounded before decode',
    () {
      final png = Uint8List(24)
        ..setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10])
        ..setRange(12, 16, [73, 72, 68, 82]);
      ByteData.sublistView(png)
        ..setUint32(16, 9000)
        ..setUint32(20, 1);
      final info = uueImageInfo(png)!;
      expect(info.format, 'PNG');
      expect(info.allowed(16000000, 8192), isFalse);
      final gif = Uint8List.fromList([71, 73, 70, 56, 57, 97, 1, 0, 2, 0]);
      expect(uueImageInfo(gif)!.height, 2);
      final jpeg = Uint8List.fromList([
        255,
        216,
        255,
        192,
        0,
        8,
        8,
        0,
        2,
        0,
        3,
        0,
      ]);
      expect(uueImageInfo(jpeg)!.width, 3);
      final webp = Uint8List(30)
        ..setRange(0, 4, [82, 73, 70, 70])
        ..setRange(8, 16, [87, 69, 66, 80, 86, 80, 56, 88]);
      ByteData.sublistView(webp)
        ..setUint32(4, 22, Endian.little)
        ..setUint32(16, 10, Endian.little);
      expect(uueImageInfo(webp)!.format, 'WebP');
      expect(uueImageInfo(webp)!.width, 1);
      expect(
        uueImageInfo(Uint8List.fromList('not an image.png'.codeUnits)),
        isNull,
      );
      for (var length = 0; length < png.length; length++) {
        expect(uueImageInfo(Uint8List.sublistView(png, 0, length)), isNull);
      }
    },
  );
  test(
    'safe filename preserves bytes-independent Unicode and removes paths',
    () {
      expect(safeUueName('../../secret'), 'secret');
      expect(safeUueName('CON.txt'), '_CON.txt');
      expect(safeUueName('a\nb'), 'a_b');
      expect(safeUueName('..'), 'attachment.bin');
      expect(safeUueName(List.filled(200, 'Н').join()).runes.length, 100);
    },
  );
  test('UUE rows beginning with quote marker are not colored as quotes', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    final row = '>${List.filled(40, '`').join()}';
    final text = 'begin 644 a\n$row\n`\nend\n> настоящая цитата';
    final span = ftnTextSpan(text, scheme);
    final children = span.children!.whereType<TextSpan>().toList();
    expect(
      children.firstWhere((s) => s.text == row).style!.color,
      scheme.onSurface,
    );
    expect(
      children.firstWhere((s) => s.text == '> настоящая цитата').style!.color,
      isNot(scheme.onSurface),
    );
    expect(span.toPlainText(), text);
  });
}
