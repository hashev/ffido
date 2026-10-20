import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/files/uue_files.dart';
import 'package:fido/models/uue.dart';
import 'package:fido/repositories/uue_repository.dart';

import '../support/fake_transport.dart';

wire.UueLimits limits() => wire.UueLimits(
  maxFileBytes: Int64(1048576),
  partBodyBytes: 32768,
  maxParts: 128,
  chunkBytes: 65536,
  previewPixels: Int64(16000000),
  previewDimension: 8192,
);
UueDraft draft(Uint8List bytes) => UueDraft(
  conference: 'ECHO',
  operation: 'key',
  subject: 'Н тема',
  body: 'Н текст',
  toName: 'All',
  toAddress: '',
  file: SelectedUueFile('a.bin', bytes),
);
void main() {
  late FakeTransport api;
  late UueRepository repository;
  setUp(() {
    api = FakeTransport();
    repository = UueRepository(api);
    api.getUueLimitsHandler = (_) async => limits();
    api.getUueSendStatusHandler = (_) async => throw const NotFoundException();
  });
  tearDown(() => api.dispose());
  test(
    'bounded upload uses the same operation and original author text',
    () async {
      final bytes = Uint8List.fromList(List.generate(100000, (i) => i & 255));
      final received = <int>[];
      api.uploadUueChunkHandler = (r) async {
        expect(r.operationId, 'key');
        expect(r.offset.toInt(), received.length);
        expect(r.data.length, lessThanOrEqualTo(65536));
        received.addAll(r.data);
        return wire.UueUploadStatus(
          receivedBytes: Int64(received.length),
          complete: received.length == bytes.length,
        );
      };
      api.commitUueHandler = (r) async {
        expect(received, bytes);
        expect(r.message.body, 'Н текст');
        expect(r.message.subject, 'Н тема');
        return wire.UueSendStatus(
          operationId: 'key',
          state: 'completed',
          totalParts: 5,
          savedParts: 5,
        );
      };
      final progress = <int>[];
      final result = await repository.send(
        draft(bytes),
        progress: (done, _) => progress.add(done),
      );
      expect(result.complete, isTrue);
      expect(progress, [65536, 100000]);
      expect(api.calls.whereType<wire.UploadUueChunkRequest>().length, 2);
    },
  );
  test(
    'partial resume skips upload and rejects another file under same key',
    () async {
      final bytes = Uint8List.fromList([0, 255, 1]);
      final hash = sha256.convert(bytes).toString();
      api.getUueSendStatusHandler = (_) async => wire.UueSendStatus(
        state: 'partial',
        filename: 'a.bin',
        fileSize: Int64(3),
        sha256: hash,
        savedParts: 1,
        totalParts: 2,
      );
      api.commitUueHandler = (r) async =>
          wire.UueSendStatus(state: 'completed', savedParts: 2, totalParts: 2);
      expect((await repository.send(draft(bytes))).complete, isTrue);
      expect(api.calls.whereType<wire.UploadUueChunkRequest>(), isEmpty);
      await expectLater(
        repository.send(draft(Uint8List.fromList([1, 2, 3]))),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'conflict', 6)),
      );
    },
  );
  test(
    'download checks boundaries size digest and late session replies',
    () async {
      final bytes = Uint8List.fromList(List.generate(100000, (i) => i & 255));
      final file = UueAttachment.fromWire(
        wire.UueAttachment(
          id: 'file',
          filename: 'a.bin',
          size: Int64(bytes.length),
          sha256: sha256.convert(bytes).toString(),
          state: wire.UueState.UUE_STATE_READY,
        ),
      );
      api.getUueChunkHandler = (r) async {
        final start = r.offset.toInt(),
            end = (r.offset.toInt() + r.maxBytes).clamp(0, bytes.length);
        return wire.UueChunk(
          offset: r.offset,
          totalSize: Int64(bytes.length),
          data: bytes.sublist(start, end),
          eof: end == bytes.length,
        );
      };
      expect(await repository.download(file), bytes);
      api.getUueChunkHandler = (_) async => wire.UueChunk(
        offset: Int64(1),
        totalSize: Int64(bytes.length),
        data: [1],
      );
      await expectLater(
        repository.download(file),
        throwsA(isA<ServerException>()),
      );
      final pending = Completer<wire.UueChunk>();
      api.getUueChunkHandler = (_) => pending.future;
      final future = repository.download(file);
      final rejected = expectLater(future, throwsA(isA<CancelledException>()));
      await Future<void>.delayed(Duration.zero);
      api.switchSession();
      pending.complete(wire.UueChunk());
      await rejected;
    },
  );
  test('search finds a late page and never reads or marks messages', () async {
    wire.UuePart part(int number) => wire.UuePart(
      source: wire.UuePartReference(
        message: wire.MessageReference(
          conferenceId: 'mail',
          messageId: 'g#$number',
        ),
      ),
      fromAddress: '2:1/2',
      toAddress: '2:1/1.1',
      subject: 'a [$number/2]',
      transferId: 'id',
      sha256: 'hash',
      part: number,
      total: 2,
    );
    final anchor = UuePart.fromWire(part(1));
    api.searchUuePartsHandler = (r) async => r.afterNumber == 0
        ? wire.SearchUuePartsResponse(
            generation: 'g',
            parts: [part(1)],
            hasMore: true,
            nextNumber: 50,
          )
        : wire.SearchUuePartsResponse(
            generation: 'g',
            parts: [part(2)],
            nextNumber: 51,
          );
    final result = await repository.findParts(anchor);
    expect(result.map((p) => p.part), [1, 2]);
    expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
    api.assembleUueHandler = (r) async {
      expect(r.explicitOrder, isTrue);
      expect(r.sources.map((s) => s.message.messageId), ['g#2', 'g#1']);
      return wire.UueAttachment(state: wire.UueState.UUE_STATE_INCOMPLETE);
    };
    await repository.assemble(result.reversed.toList(), confirmed: true);
  });
  test(
    'legacy grouping keeps total, subject, sender, recipient and direction',
    () async {
      wire.UuePart p(int n) => wire.UuePart(
        source: wire.UuePartReference(
          message: wire.MessageReference(
            conferenceId: 'mail',
            messageId: 'g#$n',
          ),
        ),
        fromAddress: '2:1/2.1',
        toAddress: '2:1/2.2',
        subject: 'file [$n/2]',
        part: n,
        total: 2,
      );
      final anchor = UuePart.fromWire(p(1));
      final candidates = [
        p(1),
        p(2),
        p(3)..total = 3,
        p(4)..fromAddress = '2:1/2.3',
        p(5)..toAddress = '2:1/2.4',
        p(6)..subject = 'other [2/2]',
        p(7)..direction = wire.MailDirection.MAIL_DIRECTION_OUTGOING,
      ];
      api.searchUuePartsHandler = (_) async =>
          wire.SearchUuePartsResponse(generation: 'g', parts: candidates);
      final found = await repository.findParts(anchor);
      expect(found.map((p) => p.source.message), ['g#1', 'g#2']);
      api.assembleUueHandler = (r) async {
        expect(r.explicitOrder, isFalse);
        return wire.UueAttachment(state: wire.UueState.UUE_STATE_INCOMPLETE);
      };
      await repository.assemble(found);
    },
  );
}
