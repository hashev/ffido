import '../api/generated/ffido/v1/ffido.pb.dart' as wire;

class TechnicalSubfield {
  final int lowId, highId;
  final List<int> bytes;
  TechnicalSubfield(this.lowId, this.highId, List<int> bytes)
    : bytes = List.unmodifiable(bytes);
  bool get isChrs =>
      lowId == 2000 &&
      highId == 0 &&
      String.fromCharCodes(bytes)
          .split(RegExp(r'[\r\n]'))
          .any(
            (line) => (line.startsWith('\x01') ? line.substring(1) : line)
                .startsWith('CHRS: '),
          );
}

class MessageTechnicalData {
  final String conferenceId, messageId;
  final int attributes, attributes2;
  final String? effectiveEncoding;
  final List<TechnicalSubfield> subfields;
  MessageTechnicalData.fromWire(wire.MessageTechnicalData value)
    : conferenceId = value.message.conferenceId,
      messageId = value.message.messageId,
      attributes = value.attributes,
      attributes2 = value.attributes2,
      effectiveEncoding =
          value.encodingStatus ==
              wire.TechnicalEncodingStatus.TECHNICAL_ENCODING_STATUS_KNOWN
          ? value.effectiveEncoding
          : null,
      subfields = List.unmodifiable(
        value.subfields.map(
          (f) => TechnicalSubfield(f.lowId, f.highId, f.value),
        ),
      );
}
