import 'update_metadata.dart';
import 'update_service.dart';

Future<UpdatePlatform> currentUpdatePlatform() async =>
    throw UnsupportedError('Обновления этой платформы не поддерживаются');
Future<UpdateResponse> fetchUpdate(
  Uri uri, {
  String? etag,
  int limit = updateMetadataLimit,
}) async => throw UnsupportedError('Недоступно');
Future<String> downloadUpdate(
  AvailableUpdate update,
  void Function(double) progress, {
  bool Function()? cancelled,
  String? stagingDirectory,
}) async => throw UnsupportedError('Недоступно');

Future<void> acquireDesktopLease() async {}
Future<void> installDesktop(String archive) async =>
    throw UnsupportedError('Недоступно');

Future<void> confirmDesktopStartup() async {}

Future<String?> consumeDesktopError() async => null;
