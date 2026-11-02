import '../models/message_technical_data.dart';

String technicalHex(int mask) =>
    '0x${mask.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase()}';

// JAM's attribute word, not the per-user FFIDO read state.
const jamAttributeNames = <int, String>{
  0x1: 'Local',
  0x2: 'InTransit',
  0x4: 'Private',
  0x8: 'Read',
  0x10: 'Sent',
  0x20: 'KillSent',
  0x40: 'ArchiveSent',
  0x80: 'Hold',
  0x100: 'Crash',
  0x200: 'Immediate',
  0x400: 'Direct',
  0x800: 'Gate',
  0x1000: 'FileRequest',
  0x2000: 'FileAttached',
  0x4000: 'TruncFile',
  0x8000: 'KillFile',
  0x10000: 'ReceiptRequest',
  0x20000: 'ConfirmRequest',
  0x40000: 'Orphan',
  0x80000: 'Encrypted',
  0x100000: 'Compressed',
  0x200000: 'Escaped',
  0x400000: 'Fpu',
  0x800000: 'TypeLocal',
  0x1000000: 'TypeEcho',
  0x2000000: 'TypeNet',
  0x20000000: 'NoDisplay',
  0x40000000: 'Locked',
  0x80000000: 'Deleted',
};

String technicalBytes(List<int> bytes) {
  if (bytes.isEmpty) return 'Пустое значение';
  final text = StringBuffer();
  for (final byte in bytes) {
    text.write(switch (byte) {
      0x5c => r'\\',
      13 => r'\r',
      10 => r'\n',
      9 => r'\t',
      >= 0x20 && <= 0x7e => String.fromCharCode(byte),
      _ => '\\x${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}',
    });
  }
  return text.toString();
}

const technicalExplanation =
    'Показаны исходные байты: \\r, \\n, \\t, \\xNN; обратная косая черта экранирована. JAM Read не является персональной отметкой прочитанности FFIDO.';

typedef TechnicalRow = ({String label, String value});
List<TechnicalRow> technicalRows(MessageTechnicalData data) {
  String values(bool Function(TechnicalSubfield) match) {
    final fields = data.subfields.where(match).toList();
    return fields.isEmpty
        ? 'Отсутствует'
        : fields.map((f) => technicalBytes(f.bytes)).join('\n');
  }

  final flags = jamAttributeNames.entries
      .where((e) => data.attributes & e.key != 0)
      .map((e) => e.value)
      .join(', ');
  final knownMask = jamAttributeNames.keys.fold(0, (a, b) => a | b);
  return [
    (label: 'Область', value: data.conferenceId),
    (label: 'Локальный ID письма', value: data.messageId),
    (label: 'MSGID', value: values((f) => f.lowId == 4 && f.highId == 0)),
    (label: 'FTN REPLY', value: values((f) => f.lowId == 5 && f.highId == 0)),
    (label: 'CHRS', value: values((f) => f.isChrs)),
    (
      label: 'Фактическая кодировка чтения',
      value: data.effectiveEncoding ?? 'Не удалось определить кодировку',
    ),
    (label: 'JAM attributes', value: technicalHex(data.attributes)),
    (label: 'Установленные флаги', value: flags.isEmpty ? 'Нет' : flags),
    (
      label: 'Неизвестные биты',
      value: technicalHex(data.attributes & ~knownMask),
    ),
    (label: 'JAM attributes2', value: technicalHex(data.attributes2)),
    (
      label: 'Исходные технические подполя',
      value: 'MSGID, REPLY и все кладжи в порядке хранения',
    ),
    if (data.subfields.isEmpty) (label: 'Кладжи', value: 'Отсутствует'),
    for (var i = 0; i < data.subfields.length; i++)
      (
        label:
            '№${i + 1} · ${data.subfields[i].lowId}/${data.subfields[i].highId}',
        value: technicalBytes(data.subfields[i].bytes),
      ),
  ];
}

String messageTechnicalReport(MessageTechnicalData data) => [
  'Технические данные',
  technicalExplanation,
  ...technicalRows(data).map((row) => '${row.label}:\n${row.value}'),
].join('\n\n');
