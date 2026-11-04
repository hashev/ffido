import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/widgets/message_actions.dart';
import 'package:fido/widgets/message_search_dialog.dart';

import '../support/adaptive_appearance.dart';
import '../support/fake_transport.dart';
import '../support/message_identity.dart';

void main() {
  setUp(mockMessageIdentity);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(loadAdaptiveFonts);
  final sizes = [
    const Size(320, 568),
    const Size(360, 800),
    const Size(412, 915),
    const Size(800, 360),
    const Size(600, 960),
    const Size(800, 1280),
    const Size(1280, 800),
    const Size(1024, 768),
    const Size(1440, 900),
    const Size(599, 800),
    const Size(1023, 800),
  ];
  for (final size in sizes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('reader ${size.width}x${size.height} scale=$scale', (
        t,
      ) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final api = FakeTransport()
          ..messages = (_) async => wire.ListMessagesResponse(
            messages: [wire.Message(id: 'g#1', subject: 'Оригинал')],
          );
        api.message = (r) async => wire.Message(
          id: r.messageId,
          subject: 'Оригинал',
          fromName: 'Автор',
          fromAddress: '2:1/2',
          body: 'Короткое письмо\n AB> Цитата',
        );
        final repo = MessageRepository(api);
        addTearDown(api.dispose);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'Roboto',
                brightness: scale == 2 ? Brightness.dark : Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('Открыть читатель'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MessageScreen(
                          conferenceId: 'echo',
                          conferenceName: 'Очень длинное название эхоконференции для проверки панели',
                          conferenceDescription: '',
                          canRead: true,
                          canPost: true,
                          repository: repo,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Открыть читатель'));
        await t.pumpAndSettle();
        await t.tap(find.text('Оригинал'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.byType(MessageActions));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final tiles = find.descendant(
          of: find.byType(MessageActions),
          matching: find.byType(TextButton),
        );
        expect(tiles, findsNWidgets(5));
        for (final element in tiles.evaluate()) {
          final rect = t.getRect(find.byElementPredicate((e) => e == element));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
        }
        final calls = api.calls.length;
        for (final width in [599.0, 600.0, 1023.0, 1024.0, size.width]) {
          t.view.physicalSize = Size(width, size.height);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
        expect(api.calls.length, calls);
        if ([320.0, 800.0, 1440.0].contains(size.width) && size.height != 360) {
          await adaptiveScreenshot(
            t,
            key,
            'reader-${size.width.toInt()}-$scale',
          );
        }
      });
    }
  }
  testWidgets('search remains scrollable above keyboard on short screen', (
    t,
  ) async {
    t.view.physicalSize = const Size(800, 360);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<Object>(
                context: context,
                builder: (_) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(2),
                    viewInsets: const EdgeInsets.only(bottom: 120),
                  ),
                  child: const MessageSearchDialog(
                    query: 'тест',
                    headersOnly: true,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text('Найти далее'));
    await t.tap(find.text('Найти далее'));
    await t.pumpAndSettle();
    expect(find.byType(MessageSearchDialog), findsNothing);
  });
}
