import 'dart:convert';
import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:fido/media/external_image.dart';
import 'package:fido/media/message_images.dart';
import 'package:fido/widgets/external_image_preview.dart';

import '../media/external_image_test.dart' show FakeHttp, response;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/message.dart';
import 'package:fido/models/message_search.dart';
import 'package:fido/repositories/uue_repository.dart';
import 'package:fido/utils/ftn_text.dart';
import 'package:fido/widgets/uue_body.dart';
import 'package:fido/widgets/message_link_text.dart';

import '../support/fake_transport.dart';
import 'message_links_test.dart' show ActionsFake;
import 'uue_workflow_test.dart' as uue;

void main() {
  testWidgets(
    'highlight keeps exact text, quote colors, link recognizer and copy',
    (tester) async {
      const text = '😀 AB> https://example.org/Привет\nПривет';
      final actions = ActionsFake();
      final start = text.indexOf('https');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageLinkText(
              text,
              actions: actions,
              searchRanges: [
                SearchRange(start + 4, start + 10),
                SearchRange(text.lastIndexOf('Привет'), text.length),
              ],
            ),
          ),
        ),
      );
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.textSpan!.toPlainText(), text);
      final spans = selectable.textSpan!.children!.cast<TextSpan>();
      expect(
        spans.where((s) => s.style?.backgroundColor != null),
        hasLength(2),
      );
      final link = spans.firstWhere(
        (s) => s.recognizer != null && s.style?.backgroundColor != null,
      );
      (link.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pump();
      expect(actions.opened.single, Uri.parse('https://example.org/Привет'));
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable.widget.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      editable.copySelection(SelectionChangedCause.toolbar);
      await tester.pump();
      expect(copied, text);
    },
  );
  testWidgets('highlight overlays real FTN quote style', (tester) async {
    const text = ' AB> Привет\n>> Привет';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MessageLinkText(
            text,
            searchRanges: [SearchRange(5, 11), SearchRange(15, 21)],
          ),
        ),
      ),
    );
    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    final scheme = Theme.of(tester.element(find.byType(MessageLinkText)))
        .colorScheme;
    final spans = selectable.textSpan!.children!
        .cast<TextSpan>()
        .where((s) => s.style?.backgroundColor != null)
        .toList();
    expect(spans.first.style!.color, quoteColor(scheme, 1));
    expect(spans.last.style!.color, quoteColor(scheme, 2));
    expect(selectable.textSpan!.toPlainText(), text);
  });
  testWidgets(
    'hidden UUE match reveals source and keeps attachments available',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      const prefix = '😀 before\n',
          block = 'begin 644 file.bin\n`\nend\n',
          suffix = 'Привет';
      const body = '$prefix$block$suffix';
      uue.ready(api, utf8.encode('abc'));
      api.searchUuePartsHandler = (_) async => wire.SearchUuePartsResponse(
        parts: [
          uue.part(1)
            ..total = 1
            ..bodyStart = utf8.encode(prefix).length
            ..bodyEnd = utf8.encode(prefix + block).length,
        ],
      );
      final message = Message(
        id: 'g#1',
        fromName: 'A',
        fromAddress: '',
        toName: 'All',
        toAddress: '',
        subject: 'Subject',
        body: body,
        date: DateTime(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UueBody(
                repository: UueRepository(api),
                conference: 'ECHO',
                message: message,
                searchRanges: [
                  SearchRange(body.indexOf('644'), body.indexOf('644') + 3),
                ],
                revealSearch: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Показать вложения'), findsOneWidget);
      expect(
        tester
            .widgetList<MessageLinkText>(find.byType(MessageLinkText))
            .map((w) => w.text)
            .join(),
        body,
      );
      expect(
        tester
            .widgetList<MessageLinkText>(find.byType(MessageLinkText))
            .first
            .searchRanges
            .single
            .start,
        body.indexOf('644'),
      );
      await tester.tap(find.text('Показать вложения'));
      await tester.pumpAndSettle();
      expect(find.byType(UueAttachmentCard), findsOneWidget);
      await tester.tap(find.text('Показать исходный UUE'));
      await tester.pumpAndSettle();
      expect(find.text('Показать вложения'), findsOneWidget);
      await tester.tap(find.text('Показать вложения'));
      await tester.pumpAndSettle();
      // Removing the search restores the existing attachment presentation.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UueBody(
                repository: UueRepository(api),
                conference: 'ECHO',
                message: message,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UueAttachmentCard), findsOneWidget);
    },
  );
  testWidgets(
    'late image before match preserves source offsets and reveals the target',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      final pending = Completer<ImageResponse>();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final prefix =
          '${List.filled(50, 'Строка до изображения').join('\n')}\nhttps://e.org/image\n';
      final body =
          '$prefix${List.filled(40, 'После изображения').join('\n')}\nПривет';
      final message = Message(
        id: 'g#1',
        fromName: 'A',
        fromAddress: '',
        toName: 'All',
        toAddress: '',
        subject: 'Subject',
        body: body,
        date: DateTime(2026),
      );
      late MessageImages images;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: UueBody(
                repository: UueRepository(api),
                conference: 'ECHO',
                message: message,
                searchRanges: [
                  SearchRange(body.indexOf('Привет'), body.length),
                ],
                revealSearch: true,
                createImages: (body) => images = MessageImages(
                  body,
                  createLoad: () => ExternalImageLoad(
                    http: FakeHttp(
                      (_, method) => method == 'HEAD'
                          ? response(headers: {'content-type': 'image/png'})
                          : pending.future,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      pending.complete(response());
      for (var i = 0; i < 100 && images.entries.any((e) => e.loading); i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.byType(ExternalImagePreview), findsOneWidget);
      final paragraphs = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('Привет'),
      );
      final paragraph = tester.renderObject<RenderParagraph>(paragraphs.last);
      final offset = paragraph.text.toPlainText().indexOf('Привет');
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + 1),
          )
          .first;
      final global = paragraph.localToGlobal(box.toRect().center);
      expect(global.dy, inInclusiveRange(0, 600));
      expect(
        tester
            .widgetList<MessageLinkText>(find.byType(MessageLinkText))
            .map((w) => w.text)
            .join(),
        body,
      );
      final suffix = tester
          .widgetList<MessageLinkText>(find.byType(MessageLinkText))
          .last;
      expect(suffix.searchRanges.single.start, suffix.text.indexOf('Привет'));
    },
  );
}
