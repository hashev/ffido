import '../api/generated/ffido/v1/ffido.pb.dart' as wire;

class UueCapabilities {
  final int fileBytes,
      partBytes,
      parts,
      chunkBytes,
      previewPixels,
      previewDimension;
  const UueCapabilities({
    required this.fileBytes,
    required this.partBytes,
    required this.parts,
    required this.chunkBytes,
    required this.previewPixels,
    required this.previewDimension,
  });
  factory UueCapabilities.fromWire(wire.UueLimits value) => UueCapabilities(
    fileBytes: value.maxFileBytes.toInt(),
    partBytes: value.partBodyBytes,
    parts: value.maxParts,
    chunkBytes: value.chunkBytes,
    previewPixels: value.previewPixels.toInt(),
    previewDimension: value.previewDimension,
  );
}

class UueSource {
  final String conference, message;
  final int block;
  const UueSource(this.conference, this.message, this.block);
  factory UueSource.fromWire(wire.UuePartReference v) =>
      UueSource(v.message.conferenceId, v.message.messageId, v.blockIndex);
  wire.UuePartReference toWire() => wire.UuePartReference(
    message: wire.MessageReference(
      conferenceId: conference,
      messageId: message,
    ),
    blockIndex: block,
  );
  String get key => '$conference:$message:$block';
}

class UuePart {
  final UueSource source;
  final String from, to, subject, filename, transfer, sha256, diagnostic, date;
  final int part, total, begin, end, direction;
  UuePart.fromWire(wire.UuePart v)
    : source = UueSource.fromWire(v.source),
      from = v.fromAddress,
      to = v.toAddress,
      subject = v.subject,
      filename = v.filename,
      transfer = v.transferId,
      sha256 = v.sha256,
      diagnostic = v.diagnostic,
      date = v.date,
      direction = v.direction.value,
      part = v.part,
      total = v.total,
      begin = v.bodyStart,
      end = v.bodyEnd;
  bool get verifiedFormat => transfer.isNotEmpty && sha256.isNotEmpty;
}

enum UueFileState { unspecified, ready, incomplete, conflict, corrupt }

class UueAttachment {
  final String id, name, sha256, diagnostic;
  final int size;
  final bool verified;
  final UueFileState state;
  final List<int> missing;
  final List<UueSource> sources;
  UueAttachment.fromWire(wire.UueAttachment v)
    : id = v.id,
      name = v.filename,
      sha256 = v.sha256,
      diagnostic = v.diagnostic,
      size = v.size.toInt(),
      verified = v.checksumVerified,
      state = UueFileState.values[v.state.value],
      missing = List.unmodifiable(v.missingParts),
      sources = List.unmodifiable(v.sources.map(UueSource.fromWire));
}

class UueTransfer {
  final String operation, state, diagnostic;
  final int total, saved;
  UueTransfer.fromWire(wire.UueSendStatus v)
    : operation = v.operationId,
      state = v.state,
      diagnostic = v.diagnostic,
      total = v.totalParts,
      saved = v.savedParts;
  bool get complete => state == 'completed';
}
