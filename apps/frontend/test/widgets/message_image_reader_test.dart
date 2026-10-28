import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/models/message.dart';
import 'package:fido/media/external_image.dart';
import 'package:fido/media/message_images.dart';
import 'package:fido/repositories/uue_repository.dart';
import 'package:fido/widgets/uue_body.dart';
import 'package:fido/widgets/external_image_preview.dart';

import '../support/fake_transport.dart';
import '../media/external_image_test.dart' show FakeHttp, response, png;
import 'uue_workflow_test.dart' as uue;
import 'message_links_test.dart' show ActionsFake;

void main() {
  testWidgets(
    'duplicates across UUE fragments and raw view keep one preview/GET',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      const prefix = 'https://e.org/a\n',
          block = 'begin 644 file.bin\n`\nend\n';
      final message = Message(
        id: 'g#1',
        fromName: 'A',
        fromAddress: '',
        toName: 'All',
        toAddress: '',
        subject: 'Subject',
        body: '$prefix${block}https://e.org/a#duplicate',
        date: DateTime(2026),
      );
      uue.ready(api, png);
      api.searchUuePartsHandler = (_) async => wire.SearchUuePartsResponse(
        parts: [
          uue.part(1)
            ..total = 1
            ..bodyStart = utf8.encode(prefix).length
            ..bodyEnd = utf8.encode(prefix + block).length,
        ],
      );
      var gets = 0;
      late MessageImages images;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UueBody(
                repository: UueRepository(api),
                conference: 'ECHO',
                message: message,
                createImages: (body) => images = MessageImages(
                  body,
                  createLoad: () => ExternalImageLoad(
                    http: FakeHttp((_, method) {
                      if (method == 'GET') gets++;
                      return response();
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 100 && images.entries.any((e) => e.loading); i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(UueAttachmentCard), findsOneWidget);
      expect(find.byType(ExternalImagePreview), findsOneWidget);
      expect(gets, 1);
      await tester.tap(find.text('Показать исходный UUE'));
      await tester.pumpAndSettle();
      expect(find.byType(ExternalImagePreview), findsOneWidget);
      expect(gets, 1);
    },
  );

  testWidgets(
    'same message and scroll survive viewer without read/history RPC; session closes viewer',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final message = Message(
        id: 'id',
        fromName: 'A',
        fromAddress: '',
        toName: 'All',
        toAddress: '',
        subject: 'Subject',
        body: 'https://e.org/a\nhttps://e.org/a#duplicate',
        date: DateTime(2026),
      );
      late MessageImages images;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 300),
                  UueBody(
                    repository: UueRepository(api),
                    conference: 'c',
                    message: message,
                    imageActions: ActionsFake(),
                    createImages: (body) => images = MessageImages(
                      body,
                      createLoad: () => ExternalImageLoad(
                        http: FakeHttp((_, _) => response()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 1000),
                ],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 100 && images.entries.any((e) => e.loading); i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      scroll.jumpTo(150);
      await tester.pump();
      final before = scroll.offset;
      final rpc = api.calls.length;
      expect(find.byType(ExternalImagePreview), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.byType(ExternalImageViewer), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(scroll.offset, before);
      expect(api.calls.length, rpc);
      expect(
        identical(
          tester.widget<UueBody>(find.byType(UueBody)).message,
          message,
        ),
        isTrue,
      );
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      api.switchSession();
      await tester.pumpAndSettle();
      expect(find.byType(ExternalImageViewer), findsNothing);
      expect(images.active, isFalse);
      expect(api.calls.length, rpc);
    },
  );
}
