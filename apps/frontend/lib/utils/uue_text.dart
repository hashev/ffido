bool uueDataLine(String line) {
  if (line.isEmpty) return false;
  final count = (line.codeUnitAt(0) - 32) & 63;
  return count <= 45 &&
      line.length == 1 + 4 * ((count + 2) ~/ 3) &&
      line.codeUnits.every((c) => c >= 32 && c <= 96);
}

final uueBeginLine = RegExp(r'^begin [0-7]{3,4} [^\r\n]+$');
