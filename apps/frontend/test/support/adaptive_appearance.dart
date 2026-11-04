import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadAdaptiveFonts() async {
  final executable = Platform.resolvedExecutable.replaceAll('\\', '/');
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      executable.split('/bin/cache/').first;
  final fonts = {
    'Roboto': '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    'MaterialIcons':
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    'monospace': '/System/Library/Fonts/Menlo.ttc',
  };
  for (final font in fonts.entries) {
    if (!File(font.value).existsSync()) continue;
    await (FontLoader(font.key)..addFont(
          Future.value(
            ByteData.sublistView(File(font.value).readAsBytesSync()),
          ),
        ))
        .load();
  }
}

Future<void> adaptiveScreenshot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/adaptive-appearance').createSync(recursive: true);
    File('build/adaptive-appearance/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
