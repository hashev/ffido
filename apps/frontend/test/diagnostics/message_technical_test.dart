import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/api_transport.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/message_technical_data.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/utils/message_technical_report.dart';

import '../support/fake_transport.dart';

wire.MessageTechnicalData technicalFixture() => wire.MessageTechnicalData(
  message: wire.MessageReference(conferenceId: 'ECHO', messageId: 'g#42'),
  attributes: 0x84000008,
  attributes2: 0xFFFFFFFF,
  encodingStatus:
      wire.TechnicalEncodingStatus.TECHNICAL_ENCODING_STATUS_UNDETERMINED,
  subfields: [
    wire.MessageTechnicalSubfield(lowId: 4, value: '2:1/2 original'.codeUnits),
    wire.MessageTechnicalSubfield(lowId: 5, value: '2:9/9 external'.codeUnits),
    wire.MessageTechnicalSubfield(
      lowId: 2000,
      value: 'CHRS: UNKNOWN 2'.codeUnits,
    ),
    wire.MessageTechnicalSubfield(
      lowId: 2000,
      value: 'CHRS: UTF-8 4'.codeUnits,
    ),
    wire.MessageTechnicalSubfield(lowId: 2000, highId: 9),
    wire.MessageTechnicalSubfield(
      lowId: 2000,
      value: [0, 13, 10, 9, 27, 92, 255, 192, 128],
    ),
    wire.MessageTechnicalSubfield(
      lowId: 2000,
      value: [0, 13, 10, 9, 27, 92, 255, 192, 128],
    ),
  ],
);

void main() {
  late FakeTransport api;
  late MessageRepository repo;
  setUp(() {
    api = FakeTransport();
    repo = MessageRepository(api);
  });
  tearDown(() => api.dispose());
  test('diagnostic bytes are immutable, ordered and independent of ordinary reading', () async {
    final response = technicalFixture();
    api.technicalData = (_) async => response;
    api.message = (_) async => throw StateError('must not read body');
    final result = await repo.getTechnicalData('ECHO', 'g#42');
    expect(result.attributes, 0x84000008);
    expect(result.attributes2, 0xFFFFFFFF);
    expect(result.effectiveEncoding, isNull);
    expect(result.subfields[4].highId, 9);
    expect(result.subfields[4].bytes, isEmpty);
    expect(result.subfields[5].bytes, result.subfields[6].bytes);
    response.subfields[5].value = [1];
    expect(result.subfields[5].bytes.first, 0);
    expect(() => result.subfields.clear(), throwsUnsupportedError);
    expect(() => result.subfields[5].bytes.clear(), throwsUnsupportedError);
    final request = api.calls.single as wire.MessageReference;
    expect(request.conferenceId, 'ECHO');
    expect(request.messageId, 'g#42');
  });
  test('rejects mismatched references, invalid encoding status and oversized metadata', () async {
    for (final mutate in <void Function(wire.MessageTechnicalData)>[
      (r) => r.message.conferenceId = 'OTHER',
      (r) => r.message.messageId = 'stale#42',
      (r) => r.encodingStatus =
          wire.TechnicalEncodingStatus.TECHNICAL_ENCODING_STATUS_UNSPECIFIED,
      (r) => r.effectiveEncoding = 'UTF-8',
      (r) => r.subfields.add(wire.MessageTechnicalSubfield(lowId: 6)),
      (r) => r.subfields.first.highId = 65536,
      (r) => r.subfields.first.value = List.filled(65536, 0),
    ]) {
      final response = technicalFixture();
      mutate(response);
      api.technicalData = (_) async => response;
      await expectLater(
        repo.getTechnicalData('ECHO', 'g#42'),
        throwsA(isA<ServerException>()),
      );
    }
    final response = technicalFixture()
      ..encodingStatus =
          wire.TechnicalEncodingStatus.TECHNICAL_ENCODING_STATUS_KNOWN
      ..effectiveEncoding = 'KOI8-R';
    api.technicalData = (_) async => response;
    expect(
      (await repo.getTechnicalData('ECHO', 'g#42')).effectiveEncoding,
      'KOI8-R',
    );
  });
  test('session change and cancellation discard late metadata', () async {
    for (final changeSession in [false, true]) {
      final pending = Completer<wire.MessageTechnicalData>();
      api.technicalData = (_) => pending.future;
      final token = RpcCancellation();
      final call = repo.getTechnicalData('ECHO', 'g#42', cancellation: token);
      final assertion = expectLater(call, throwsA(isA<CancelledException>()));
      if (changeSession) {
        api.switchSession();
      } else {
        await token.cancel();
      }
      pending.complete(technicalFixture());
      await assertion;
    }
    final token = RpcCancellation();
    await token.cancel();
    final count = api.calls.length;
    await expectLater(
      repo.getTechnicalData('ECHO', 'g#42', cancellation: token),
      throwsA(isA<CancelledException>()),
    );
    expect(api.calls.length, count);
  });
  test('report preserves bytes, repeated and empty fields, both words and FTN identities', () {
    final data = MessageTechnicalData.fromWire(technicalFixture());
    final report = messageTechnicalReport(data);
    expect(
      technicalBytes([0, 13, 10, 9, 27, 92, 255, 192, 128]),
      r'\x00\r\n\t\x1B\\\xFF\xC0\x80',
    );
    expect(report, contains('FTN REPLY:\n2:9/9 external'));
    expect(report, contains('Локальный ID письма:\ng#42'));
    expect(report, contains('MSGID:\n2:1/2 original'));
    expect(report, contains('CHRS: UNKNOWN 2\nCHRS: UTF-8 4'));
    expect(report, contains('№5 · 2000/9:\nПустое значение'));
    expect(report, contains('0x84000008'));
    expect(report, contains('0xFFFFFFFF'));
    expect(report, contains('Неизвестные биты:\n0x04000000'));
    expect(report, contains('Read, Deleted'));
    expect(report, contains('Не удалось определить кодировку'));
    expect(report, isNot(contains('\uFFFD')));
    final missing = technicalFixture()..subfields.clear();
    expect(
      messageTechnicalReport(MessageTechnicalData.fromWire(missing)),
      contains('MSGID:\nОтсутствует'),
    );
    expect(technicalHex(-1), '0xFFFFFFFF');
    final deceptive = TechnicalSubfield(2000, 0, 'X: CHRS: UTF-8 4'.codeUnits);
    expect(deceptive.isChrs, isFalse);
    expect(
      TechnicalSubfield(2000, 0, '\x01CHRS: CP866 2\rX: test'.codeUnits).isChrs,
      isTrue,
    );
  });
  test('every defined JAM bit is independently named and does not hide unknown bits', () {
    const expected = [
      'Local',
      'InTransit',
      'Private',
      'Read',
      'Sent',
      'KillSent',
      'ArchiveSent',
      'Hold',
      'Crash',
      'Immediate',
      'Direct',
      'Gate',
      'FileRequest',
      'FileAttached',
      'TruncFile',
      'KillFile',
      'ReceiptRequest',
      'ConfirmRequest',
      'Orphan',
      'Encrypted',
      'Compressed',
      'Escaped',
      'Fpu',
      'TypeLocal',
      'TypeEcho',
      'TypeNet',
    ];
    for (var i = 0; i < 26; i++) {
      final value = technicalFixture()..attributes = 1 << i;
      final rows = technicalRows(MessageTechnicalData.fromWire(value));
      expect(
        rows.singleWhere((r) => r.label == 'Установленные флаги').value,
        expected[i],
      );
      expect(
        rows.singleWhere((r) => r.label == 'Неизвестные биты').value,
        '0x00000000',
      );
    }
    for (final entry in {
      29: 'NoDisplay',
      30: 'Locked',
      31: 'Deleted',
    }.entries) {
      final value = technicalFixture()..attributes = 1 << entry.key;
      expect(
        technicalRows(MessageTechnicalData.fromWire(value))
            .singleWhere((r) => r.label == 'Установленные флаги')
            .value,
        entry.value,
      );
    }
  });
}
