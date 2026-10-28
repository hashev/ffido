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
final bytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

class FixtureHttp implements ImageHttp {
  @override
  Future<ImageResponse> request(Uri uri, String method) async =>
      ImageResponse(200, {'content-type': 'image/png'}, Stream.value(bytes));
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
    'https://ffido-media-qa.invalid/image.png',
    createLoad: () => ExternalImageLoad(http: FixtureHttp()),
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
          MessageLinkText(
            'https://ffido-media-qa.invalid/image.png',
            actions: PlatformImageActions(),
          ),
          ExternalImagePreview(owner: owner, entry: owner.entries.single),
          TextButton(
            onPressed: owner.invalidate,
            child: const Text('Invalidate session'),
          ),
        ],
      ),
    ),
  );
}
