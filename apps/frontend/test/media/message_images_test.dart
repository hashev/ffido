import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/media/external_image.dart';
import 'package:fido/media/message_images.dart';
import 'package:fido/widgets/external_image_preview.dart';

import '../widgets/message_links_test.dart' show ActionsFake;
import 'external_image_test.dart' show FakeHttp, response, png;

Future<void> ready(WidgetTester tester, MessageImages owner) async {
  for (var i = 0; i < 200 && owner.entries.any((e) => e.loading); i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('classification controls cards independently from queue', (
    tester,
  ) async {
    final pending = Completer<ImageResponse>();
    final owner = MessageImages(
      'https://e.org/page https://e.org/fake.JPG?q=1#f '
      'https://e.org/offline https://e.org/broken.JpEg?x=1 '
      'https://e.org/detected https://e.org/image',
      createLoad: () => ExternalImageLoad(
        http: FakeHttp((uri, method) {
          switch (uri.path) {
            case '/page':
              return pending.future;
            case '/fake.JPG':
              return response(headers: {'content-type': 'text/html'});
            case '/offline':
            case '/broken.JpEg':
              throw StateError('offline');
            case '/detected':
              if (method == 'HEAD') {
                return response(headers: {'content-type': 'image/png'});
              }
              throw StateError('offline');
            default:
              return response();
          }
        }),
      ),
    );
    addTearDown(owner.dispose);
    owner.more();
    expect(owner.entries.first.loading, isTrue);
    expect(owner.entries.first.showPreview, isFalse);
    pending.complete(response(headers: {'content-type': 'text/html'}));
    await ready(tester, owner);
    expect(owner.entries.map((e) => e.showPreview), [
      false,
      false,
      false,
      true,
      true,
      true,
    ]);
    expect(owner.entries[1].notImage, isTrue);
    expect(owner.entries[1].error, isNull);
    expect(owner.entries[3].error, isNotNull);
    expect(owner.entries[4].imageDetected, isTrue);
    expect(owner.entries.last.thumbnail, isNotNull);
  });
  test('portrait thumbnail fits both axes within 1000 pixels', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
        .drawPaint(ui.Paint()..color = const ui.Color(0xffff0000));
    final picture = recorder.endRecording();
    final original = await picture.toImage(2000, 4000);
    final bytes = (await original.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    original.dispose();
    picture.dispose();
    final owner = MessageImages(
      'https://e.org/portrait',
      createLoad: () =>
          ExternalImageLoad(http: FakeHttp((_, _) => response(bytes: bytes))),
    );
    addTearDown(owner.dispose);
    owner.more();
    for (var i = 0; i < 300 && owner.entries.single.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      owner.entries.single.thumbnail?.width,
      500,
      reason: owner.entries.single.error,
    );
    expect(owner.entries.single.thumbnail?.height, 1000);
  });
  test('queue dedupes fragments, batches ten, max two, LRU/reload', () async {
    var calls = 0;
    final gates = <Completer<ImageResponse>>[];
    final owner = MessageImages(
      '${List.generate(12, (i) => 'https://e.org/$i').join('\n')}\nhttps://e.org/0#dup',
      cacheBudget: png.length * 2,
      createLoad: () => ExternalImageLoad(
        http: FakeHttp((_, m) {
          if (m == 'HEAD') return response();
          calls++;
          final gate = Completer<ImageResponse>();
          gates.add(gate);
          return gate.future;
        }),
      ),
    );
    addTearDown(owner.dispose);
    owner.more();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(owner.entries.length, 12);
    expect(owner.visible, 10);
    expect(calls, 2);
    Future<void> drain() async {
      for (var i = 0; i < 300 && owner.entries.any((e) => e.loading); i++) {
        for (final gate in gates.toList()) {
          if (!gate.isCompleted) gate.complete(response());
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(owner.entries.any((e) => e.loading), isFalse);
    }

    await drain();
    expect(calls, 10);
    expect(owner.cachedBytes, lessThanOrEqualTo(png.length * 2));
    expect(owner.entries.first.source, isNull);
    owner.more();
    await drain();
    expect(owner.visible, 12);
    expect(calls, 12);
    owner.retry(owner.entries.first);
    await drain();
    expect(calls, 13);
    expect(owner.entries.first.source, isNotNull);
    owner.invalidate();
    expect(owner.cachedBytes, 0);
    expect(owner.entries.every((e) => e.thumbnail == null), isTrue);
  });
  test('late responses ignored after disposal', () async {
    final gate = Completer<ImageResponse>();
    final http = FakeHttp((_, _) => gate.future);
    final owner = MessageImages(
      'https://e.org',
      createLoad: () => ExternalImageLoad(http: http),
    );
    owner.more();
    owner.invalidate();
    gate.complete(response());
    await Future<void>.delayed(Duration.zero);
    expect(owner.entries.single.source, isNull);
    expect(http.closed, isTrue);
    owner.dispose();
  });
  testWidgets(
    'viewer reuses bytes, zoom/escape/cancel and session invalidation',
    (tester) async {
      var gets = 0;
      final owner = MessageImages(
        'https://e.org',
        createLoad: () => ExternalImageLoad(
          http: FakeHttp((_, m) {
            if (m == 'GET') gets++;
            return response();
          }),
        ),
      );
      final actions = ActionsFake();
      owner.more();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: owner,
              builder: (_, _) => ExternalImagePreview(
                owner: owner,
                entry: owner.entries.single,
                actions: actions,
              ),
            ),
          ),
        ),
      );
      await ready(tester, owner);
      expect(
        owner.entries.single.source,
        isNotNull,
        reason: owner.entries.single.error,
      );
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(gets, 1);
      await tester.tap(find.byTooltip('Поделиться изображением'));
      await tester.pump();
      expect(find.text('Файл передан системному диалогу'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ExternalImageViewer), findsNothing);
      expect(gets, 1);
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      owner.invalidate();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(ExternalImageViewer), findsNothing);
      await tester.pumpWidget(const SizedBox());
      owner.dispose();
    },
  );
  testWidgets('corrupt pixels never ready/shareable', (tester) async {
    final owner = MessageImages(
      'https://e.org',
      createLoad: () => ExternalImageLoad(
        http: FakeHttp((_, _) => response(bytes: png.sublist(0, 24))),
      ),
    );
    owner.more();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await ready(tester, owner);
    expect(owner.entries.single.source, isNull);
    expect(owner.entries.single.error, isNotNull);
    owner.dispose();
  });
}
