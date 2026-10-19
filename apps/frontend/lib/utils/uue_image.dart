import 'dart:typed_data';

class UueImageInfo {
  final String format;
  final int width, height;
  const UueImageInfo(this.format, this.width, this.height);
  bool allowed(int pixels, int dimension) =>
      width > 0 &&
      height > 0 &&
      width <= dimension &&
      height <= dimension &&
      width * height <= pixels;
}

UueImageInfo? uueImageInfo(Uint8List bytes) {
  final b = ByteData.sublistView(bytes);
  bool at(int offset, List<int> magic) =>
      offset >= 0 &&
      offset + magic.length <= bytes.length &&
      List.generate(
        magic.length,
        (i) => bytes[offset + i] == magic[i],
      ).every((v) => v);
  if (bytes.length >= 24 &&
      at(0, [137, 80, 78, 71, 13, 10, 26, 10]) &&
      at(12, [73, 72, 68, 82])) {
    return UueImageInfo('PNG', b.getUint32(16), b.getUint32(20));
  }
  if (bytes.length >= 10 &&
      (at(0, [71, 73, 70, 56, 55, 97]) || at(0, [71, 73, 70, 56, 57, 97]))) {
    return UueImageInfo(
      'GIF',
      b.getUint16(6, Endian.little),
      b.getUint16(8, Endian.little),
    );
  }
  if (at(0, [255, 216])) {
    var offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset++] != 255) return null;
      while (offset < bytes.length && bytes[offset] == 255) {
        offset++;
      }
      if (offset + 2 >= bytes.length) return null;
      final marker = bytes[offset++];
      if (marker == 217 || marker == 218) return null;
      if (marker == 1 || (marker >= 208 && marker <= 215)) continue;
      final length = b.getUint16(offset);
      if (length < 2 || offset + length > bytes.length) return null;
      if ({
        192,
        193,
        194,
        195,
        197,
        198,
        199,
        201,
        202,
        203,
        205,
        206,
        207,
      }.contains(marker)) {
        if (length < 8) return null;
        return UueImageInfo(
          'JPEG',
          b.getUint16(offset + 5),
          b.getUint16(offset + 3),
        );
      }
      offset += length;
    }
  }
  if (bytes.length >= 20 &&
      at(0, [82, 73, 70, 70]) &&
      at(8, [87, 69, 66, 80]) &&
      b.getUint32(4, Endian.little) <= bytes.length - 8) {
    for (var offset = 12; offset + 8 <= bytes.length;) {
      final size = b.getUint32(offset + 4, Endian.little);
      if (size > bytes.length - offset - 8) return null;
      final data = offset + 8;
      if (at(offset, [86, 80, 56, 88]) && size >= 10) {
        return UueImageInfo(
          'WebP',
          1 +
              bytes[data + 4] +
              (bytes[data + 5] << 8) +
              (bytes[data + 6] << 16),
          1 +
              bytes[data + 7] +
              (bytes[data + 8] << 8) +
              (bytes[data + 9] << 16),
        );
      }
      if (at(offset, [86, 80, 56, 76]) && size >= 5 && bytes[data] == 47) {
        return UueImageInfo(
          'WebP',
          1 + ((bytes[data + 1] | bytes[data + 2] << 8) & 16383),
          1 +
              ((bytes[data + 2] >> 6 |
                      bytes[data + 3] << 2 |
                      bytes[data + 4] << 10) &
                  16383),
        );
      }
      if (at(offset, [86, 80, 56, 32]) &&
          size >= 10 &&
          at(data + 3, [157, 1, 42])) {
        return UueImageInfo(
          'WebP',
          b.getUint16(data + 6, Endian.little) & 16383,
          b.getUint16(data + 8, Endian.little) & 16383,
        );
      }
      offset += 8 + size + (size & 1);
    }
  }
  return null;
}
