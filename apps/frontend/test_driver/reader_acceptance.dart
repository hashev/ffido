import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final directory = Platform.environment['FFIDO_SCREENSHOT_DIR'];
    if (directory == null) throw StateError('FFIDO_SCREENSHOT_DIR is required');
    await File('$directory/$name.png').writeAsBytes(bytes);
    return true;
  },
);
