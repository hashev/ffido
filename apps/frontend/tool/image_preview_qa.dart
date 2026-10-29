// Explicit QA target; ordinary lib/main.dart never imports this file.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:fido/files/image_actions.dart';
import 'package:fido/media/external_image.dart';
import 'package:fido/media/message_images.dart';
import 'package:fido/widgets/message_link_text.dart';
import 'package:fido/widgets/external_image_preview.dart';

const marker = 'FFIDO_IMAGE_QA';
const live = bool.fromEnvironment('FFIDO_IMAGE_QA_LIVE');
const body =
    'https://башорг.рф/quote/470067\n'
    'https://brorabbit.g0x.ru/pic/6ada3fe6.jpg\n'
    'После изображения\n'
    ' * Origin: https://github.com/hashev/ffido https://wfido.ru';
final bytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

class FixtureHttp implements ImageHttp {
  @override
  Future<ImageResponse> request(Uri uri, String method) async =>
      uri.path.endsWith('.jpg')
      ? ImageResponse(200, {'content-type': 'image/png'}, Stream.value(bytes))
      : ImageResponse(200, {
          'content-type': 'text/html',
        }, Stream.value(utf8.encode('<html>Page</html>')));
  @override
  void close() {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(const MaterialApp(home: QaReader()));
}

class QaReader extends StatefulWidget {
  const QaReader({super.key});
  @override
  State<QaReader> createState() => _QaReaderState();
}

class _QaReaderState extends State<QaReader> {
  final owner = MessageImages(
    body,
    createLoad: () =>
        live ? ExternalImageLoad() : ExternalImageLoad(http: FixtureHttp()),
  );
  @override
  void initState() {
    super.initState();
    owner.more();
  }

  @override
  void dispose() {
    owner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(marker)),
    body: ListenableBuilder(
      listenable: owner,
      builder: (_, _) => ListView(
        children: [
          for (final line in body.split('\n')) ...[
            MessageLinkText(line, actions: PlatformImageActions()),
            for (final entry in owner.entries)
              if (line.contains(entry.uri.toString()) && entry.showPreview)
                ExternalImagePreview(owner: owner, entry: entry),
          ],
          Text(live ? 'Live network' : 'Deterministic fixtures'),
          TextButton(
            onPressed: owner.invalidate,
            child: const Text('Invalidate session'),
          ),
        ],
      ),
    ),
  );
}
