import 'dart:async';

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/media/external_image.dart';
import 'package:fido/media/message_images.dart';
import 'package:fido/models/message.dart';
import 'package:fido/repositories/uue_repository.dart';
import 'package:fido/widgets/uue_body.dart';
import 'package:fido/widgets/message_link_text.dart';
import 'package:fido/widgets/external_image_preview.dart';

import '../support/fake_transport.dart';
import '../media/external_image_test.dart' show FakeHttp, response;

Finder textBlock(String value) => find.byWidgetPredicate(
  (w) => w is MessageLinkText && w.text.contains(value),
);
Future<MessageImages> mount(
  WidgetTester tester,
  String body, {
  ImageHttp Function()? http,
  Brightness brightness = Brightness.light,
}) async {
  final api = FakeTransport();
  addTearDown(api.dispose);
  late MessageImages images;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          child: UueBody(
            key: UniqueKey(),
            conference: 'echo',
            repository: UueRepository(api),
            message: Message(
              id: 'g#1',
              fromName: 'A',
              fromAddress: '',
              toName: 'All',
              toAddress: '',
              subject: 'S',
              body: body,
              date: DateTime(2026),
            ),
            createImages: (body) => images = MessageImages(
              body,
              createLoad: () => ExternalImageLoad(
                http: http?.call() ?? FakeHttp((_, _) => response()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 100 && images.entries.any((e) => e.loading); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  return images;
}

void main() {
  testWidgets(
    'unknown URL has no loading card and HTML or network failure stays hidden',
    (tester) async {
      final gate = Completer<ImageResponse>();
      await mount(
        tester,
        'https://e.org/page',
        http: () => FakeHttp((_, _) => gate.future),
      );
      expect(find.byType(ExternalImagePreview), findsNothing);
      expect(find.byType(Card), findsNothing);
      gate.complete(response(headers: {'content-type': 'text/html'}));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNothing);
      await mount(
        tester,
        'https://e.org/offline',
        http: () => FakeHttp((_, _) => throw StateError('network')),
      );
      expect(find.byType(ExternalImagePreview), findsNothing);
      expect(find.text('Повторить загрузку изображения'), findsNothing);
    },
  );
  testWidgets('late unknown image response cannot populate a new message', (
    tester,
  ) async {
    final gate = Completer<ImageResponse>();
    final old = await mount(
      tester,
      'https://e.org/old',
      http: () => FakeHttp((_, _) => gate.future),
    );
    expect(find.byType(ExternalImagePreview), findsNothing);
    await mount(
      tester,
      'https://e.org/new-page',
      http: () =>
          FakeHttp((_, _) => response(headers: {'content-type': 'text/html'})),
    );
    gate.complete(response());
    await tester.pumpAndSettle();
    expect(old.active, isFalse);
    expect(old.entries.single.thumbnail, isNull);
    expect(find.byType(ExternalImagePreview), findsNothing);
    expect(textBlock('https://e.org/new-page'), findsOneWidget);
  });
  for (final width in [360.0, 1000.0]) {
    testWidgets('mixed pages, Origin and extensionless image at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const body =
          'https://башорг.рф/quote/470067\n'
          'https://e.org/photo.JPG?q=1#first\nПосле картинки\n'
          'https://e.org/photo.JPG?q=1#again\n'
          'https://e.org/fake.jpg\n'
          ' * Origin: https://github.com/hashev/ffido https://wfido.ru';
      final gets = <Uri>[];
      await mount(
        tester,
        body,
        http: () => FakeHttp((uri, method) {
          if (method == 'GET') gets.add(uri);
          return uri.path == '/photo.JPG'
              ? response()
              : response(headers: {'content-type': 'text/html'});
        }),
      );
      expect(find.byType(ExternalImagePreview), findsOneWidget);
      expect(find.text('Повторить загрузку изображения'), findsNothing);
      expect(gets.length, 1);
      expect(
        tester.getTopLeft(find.byType(ExternalImagePreview)).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(textBlock('photo.JPG?q=1#first')).dy,
        ),
      );
      expect(
        tester.getBottomLeft(find.byType(ExternalImagePreview)).dy,
        lessThanOrEqualTo(tester.getTopLeft(textBlock('После картинки')).dy),
      );
      expect(
        find
            .byType(MessageLinkText)
            .evaluate()
            .map((e) => (e.widget as MessageLinkText).text)
            .join(),
        body,
      );
    });
  }
  for (final width in [360.0, 1000.0]) {
    testWidgets(
      'preview lies between full URL line and subsequent text at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(
          tester,
          'Перед\nСлова https://e.org/a после URL\nПодпись\n * Origin: Site',
        );
        final preview = find.byType(ExternalImagePreview);
        expect(
          tester.getTopLeft(preview).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(textBlock('после URL')).dy),
        );
        expect(
          tester.getBottomLeft(preview).dy,
          lessThanOrEqualTo(tester.getTopLeft(textBlock('Подпись')).dy),
        );
      },
    );
  }
  testWidgets(
    'multiple URLs, fragment duplicates and no final newline preserve order and one GET',
    (tester) async {
      final gets = <String>[];
      await mount(
        tester,
        'https://e.org/a https://e.org/b\nПосле\nhttps://e.org/a#duplicate',
        http: () => FakeHttp((uri, method) {
          if (method == 'GET') gets.add(uri.toString());
          return response();
        }),
      );
      expect(
        tester
            .widgetList<ExternalImagePreview>(find.byType(ExternalImagePreview))
            .map((w) => w.entry.uri.toString()),
        ['https://e.org/a', 'https://e.org/b'],
      );
      expect(gets, ['https://e.org/a', 'https://e.org/b']);
      expect(
        tester.getBottomLeft(find.byType(ExternalImagePreview).last).dy,
        lessThanOrEqualTo(tester.getTopLeft(textBlock('После')).dy),
      );
    },
  );
  testWidgets(
    'error and retry remain by URL; additional portion returns to its original slot',
    (tester) async {
      var fail = true;
      final gets = <String>[];
      final body =
          '${List.generate(11, (i) => 'https://e.org/$i.png\nпосле$i').join('\n')}\nКонец';
      final images = await mount(
        tester,
        body,
        http: () => FakeHttp((uri, method) {
          if (method == 'GET') gets.add(uri.path);
          return fail && uri.path == '/0.png'
              ? response(status: 403)
              : response();
        }),
      );
      expect(images.entries.first.error, isNotNull);
      expect(
        tester.getBottomLeft(find.byType(ExternalImagePreview).first).dy,
        lessThanOrEqualTo(tester.getTopLeft(textBlock('после0')).dy),
      );
      fail = false;
      await tester.tap(find.text('Повторить загрузку изображения').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Загрузить ещё изображения'));
      await tester.tap(find.text('Загрузить ещё изображения'));
      await tester.pumpAndSettle();
      expect(find.byType(ExternalImagePreview), findsNWidgets(11));
      expect(
        tester.getBottomLeft(find.byType(ExternalImagePreview).last).dy,
        lessThanOrEqualTo(tester.getTopLeft(textBlock('после10')).dy),
      );
      expect(gets.where((s) => s == '/10.png').length, 1);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'shared selection copies exact source through cards in $brightness',
      (tester) async {
        const body =
            '  AB> начало Я🌍\nhttps://e.org/a\n>>  хвост\nhttps://e.org/b\nконец';
        await mount(tester, body, brightness: brightness);
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'];
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
        final selection = tester.state<SelectableRegionState>(
          find.byType(SelectableRegion),
        );
        await tester.tapAt(
          tester.getTopLeft(textBlock('начало')) + const Offset(5, 5),
        );
        selection.selectAll(SelectionChangedCause.keyboard);
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.pump();
        expect(copied, body);
      },
    );
  }
  testWidgets('mouse selection crosses preview without copying its labels', (
    tester,
  ) async {
    const body = 'начало один\nhttps://e.org/a\nконец два';
    await mount(tester, body);
    RenderParagraph paragraph(Finder block) =>
        tester.renderObject<RenderParagraph>(
          find.descendant(of: block, matching: find.byType(RichText)).first,
        );
    final first = paragraph(textBlock('начало')),
        last = paragraph(textBlock('конец'));
    final start = first.localToGlobal(
      first.getOffsetForCaret(const TextPosition(offset: 7), Rect.zero) +
          const Offset(0, 8),
    );
    final end = last.localToGlobal(
      last.getOffsetForCaret(const TextPosition(offset: 5), Rect.zero) +
          const Offset(0, 8),
    );
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(end);
    await gesture.up();
    await tester.pumpAndSettle();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'];
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
    tester
        .state<SelectableRegionState>(find.byType(SelectableRegion))
        .contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed!();
    await tester.pump();
    expect(copied, 'один\nhttps://e.org/a\nконец');
  });
  testWidgets('touch toolbar selects and copies source through an image', (
    tester,
  ) async {
    const body = 'начало один\nhttps://e.org/a\nконец два';
    await mount(tester, body);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'];
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
    final paragraph = tester.renderObject<RenderParagraph>(
      find
          .descendant(of: textBlock('начало'), matching: find.byType(RichText))
          .first,
    );
    await tester.longPressAt(paragraph.localToGlobal(const Offset(20, 10)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, body);
  });
}
