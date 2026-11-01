import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/files/uue_picker.dart';

class GrowingFile extends XFile {
  GrowingFile() : super('unused');
  @override
  Future<int> length() async => 2;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield Uint8List.fromList([1, 2]);
    yield Uint8List.fromList([3, 4]);
  }
}

void main() {
  test(
    'Android in-memory selection below and at the limit preserves bytes',
    () async {
      for (final size in [0, 3, 170884, 1048576]) {
        final bytes = Uint8List.fromList(List.generate(size, (i) => i % 256));
        final selected = await pickUueFile(
          1048576,
          chooseFile: () async => XFile.fromData(bytes, path: 'photo.jpg'),
        );
        expect(selected!.name, 'photo.jpg');
        expect(selected.bytes, bytes);
      }
    },
  );
  test('desktop file selection preserves bytes', () async {
    final dir = Directory.systemTemp.createTempSync('ffido-uue-picker-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/photo.jpg');
    final bytes = Uint8List.fromList([0, 255, 1]);
    file.writeAsBytesSync(bytes);
    final selected = await pickUueFile(
      1048576,
      chooseFile: () async => XFile(file.path),
    );
    expect(selected!.bytes, bytes);
  });
  test('oversized and growing files are rejected', () async {
    for (final file in [XFile.fromData(Uint8List(4)), GrowingFile()]) {
      await expectLater(
        pickUueFile(3, chooseFile: () async => file),
        throwsA(isA<ValidationException>()),
      );
    }
  });
  test('cancel returns no attachment and provider errors propagate', () async {
    expect(await pickUueFile(3, chooseFile: () async => null), isNull);
    await expectLater(
      pickUueFile(3, chooseFile: () async => throw StateError('provider')),
      throwsStateError,
    );
  });
}
