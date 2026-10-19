import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/api/uue_capabilities.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_transport.dart';

void main() {
  test('old server disables UUE without breaking ordinary reads', () async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    expect(await loadUueCapabilities(api), isNull);
    expect(
      (await api.listMessages(wire.ListMessagesRequest())).messages,
      isEmpty,
    );
  });
  test(
    'server limits and opaque multipart references map without precision loss',
    () async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.getUueLimitsHandler = (_) async => wire.UueLimits(
        maxFileBytes: Int64(1048576),
        partBodyBytes: 32768,
        maxParts: 128,
        chunkBytes: 65536,
        previewPixels: Int64(16000000),
        previewDimension: 8192,
      );
      final limits = await loadUueCapabilities(api);
      expect(limits!.fileBytes, 1048576);
      expect(limits.chunkBytes, 65536);
      final original = wire.UuePart(
        source: wire.UuePartReference(
          message: wire.MessageReference(
            conferenceId: 'mailbox',
            messageId: 'generation#31',
          ),
          blockIndex: 2,
        ),
        filename: 'Новый.bin',
        transferId: 'a' * 32,
        part: 2,
        total: 3,
      );
      final decoded = wire.UuePart.fromBuffer(original.writeToBuffer());
      expect(decoded.source.message.messageId, 'generation#31');
      expect(decoded.filename, 'Новый.bin');
      expect(decoded.part, 2);
    },
  );
}
