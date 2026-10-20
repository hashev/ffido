import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';

import '../models/uue.dart';
import 'api_exceptions.dart';
import 'api_transport.dart';

Future<UueCapabilities?> loadUueCapabilities(ApiTransport api) async {
  final epoch = api.epoch;
  try {
    final value = await api.getUueLimits(Empty());
    if (epoch != api.epoch) throw const CancelledException();
    final result = UueCapabilities.fromWire(value);
    if (result.fileBytes <= 0 ||
        result.fileBytes > 16 * 1024 * 1024 ||
        result.partBytes < 1024 ||
        result.partBytes > 256 * 1024 ||
        result.parts <= 0 ||
        result.parts > 1024 ||
        result.chunkBytes <= 0 ||
        result.chunkBytes > 65536 ||
        result.previewPixels <= 0 ||
        result.previewPixels > 64000000 ||
        result.previewDimension <= 0 ||
        result.previewDimension > 16384) {
      throw const ServerException(message: 'Некорректные лимиты UUE');
    }
    return result;
  } on ApiException catch (error) {
    if (epoch != api.epoch) throw const CancelledException();
    if (error.statusCode == 12) return null;
    rethrow;
  }
}
