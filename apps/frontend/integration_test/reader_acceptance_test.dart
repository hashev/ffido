import 'dart:io';

import 'package:flutter/services.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';

import '../test/support/fake_transport.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/reader_app.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/widgets/external_image_preview.dart';
import 'package:fido/widgets/message_link_text.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android reader routes, inline JPEG and unread navigation', (
    tester,
  ) async {
    const endpoint = String.fromEnvironment('FFIDO_TEST_ENDPOINT');
    const password = String.fromEnvironment('FFIDO_TEST_PASSWORD');
    const ca = String.fromEnvironment('FFIDO_TEST_CA');
    const image = String.fromEnvironment('FFIDO_TEST_IMAGE');
    ApiClient client() => ApiClient(
      endpoint: endpoint,
      channelFactory: (uri) => grpc.ClientChannel(
        '10.0.2.2',
        port: uri.port,
        options: grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.secure(
            certificates: base64Decode(ca),
            authority: 'localhost',
          ),
        ),
      ),
    );
    final reader = client(), sender = client();
    addTearDown(reader.dispose);
    addTearDown(sender.dispose);
    await reader.login(
      endpoint: endpoint,
      name: 'Upgrade fixture',
      address: '2:1/2',
      password: password,
    );
    await sender.login(
      endpoint: endpoint,
      name: 'Sender fixture',
      address: '2:1/3',
      password: password,
    );
    final refs = <wire.MessageReference>[];
    for (final item in [
      ('RU.ONE', 'Unread old'),
      ('RU.ONE', 'Already read'),
      ('RU.ONE', 'Unread JPEG'),
      ('RU.TWO', 'Next echo'),
    ]) {
      final result = await sender.createMessage(
        wire.CreateMessageRequest(
          conferenceId: item.$1,
          operationId: 'android-${refs.length}',
          toName: 'All',
          subject: item.$2,
          body: item.$2 == 'Unread JPEG'
              ? 'Перед ссылкой\n$image\nПодпись после изображения'
              : 'Body ${item.$2}',
        ),
      );
      refs.add(result.message);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
    await reader.markRead(refs[1]);
    for (final id in ['RU.ONE', 'RU.TWO']) {
      await reader.addBookmark(wire.GetConferenceRequest(conferenceId: id));
    }
    SharedPreferences.setMockInitialValues({});
    final catalog = ConferenceRepository(
      apiClient: reader,
      prefs: await SharedPreferences.getInstance(),
    );
    addTearDown(catalog.dispose);
    await tester.pumpWidget(MaterialApp(home: MainScreen(repository: catalog)));
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
    }

    Future<void> tap(Finder finder) async {
      await waitFor(finder);
      await tester.ensureVisible(finder.first);
      await tester.tap(finder.first);
      await tester.pumpAndSettle();
    }

    await tap(find.text('RU.ONE'));
    await tap(find.byTooltip('Новое сообщение'));
    await tap(find.byTooltip('Дополнительно'));
    await tap(find.text('Кросспостинг'));
    await waitFor(find.text('RU.TWO'));
    await tap(find.text('Готово'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(find.text('Unread JPEG'));
    await waitFor(find.bySemanticsLabel('Открыть изображение на весь экран'));
    final preview = find.byType(ExternalImagePreview);
    final signature = find.byWidgetPredicate(
      (w) => w is MessageLinkText && w.text.contains('Подпись после'),
    );
    expect(
      tester.getBottomLeft(preview).dy,
      lessThanOrEqualTo(tester.getTopLeft(signature).dy),
    );
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('reader-inline');
    await tap(find.bySemanticsLabel('Открыть изображение на весь экран'));
    await tap(find.byTooltip('Закрыть изображение'));
    await tap(find.text('Следующее'));
    await waitFor(find.text('Unread old'));
    expect(
      find.byWidgetPredicate(
        (w) => w is MessageLinkText && w.text.contains('Body Unread old'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is MessageLinkText && w.text.contains('Body Already read'),
      ),
      findsNothing,
    );
    await tap(find.text('Следующее'));
    await waitFor(find.text('Next echo'));
    expect(
      find.byWidgetPredicate(
        (w) => w is MessageLinkText && w.text.contains('Body Next echo'),
      ),
      findsOneWidget,
    );
    expect(find.text('RU.TWO'), findsOneWidget);
    expect(reader.supportsMessageFooter, isTrue);
  }, skip: const bool.fromEnvironment('FFIDO_ADAPTIVE_ONLY'));

  testWidgets('adaptive reader preserves draft through native rotation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = FakeTransport();
    api.messages = (_) async => wire.ListMessagesResponse(
      messages: [wire.Message(id: 'g#1', subject: 'Адаптивная проверка')],
    );
    api.message = (r) async => wire.Message(
      id: r.messageId,
      subject: 'Адаптивная проверка',
      fromName: 'Автор',
      fromAddress: '2:1/2',
      body: 'Текст письма\n AB> Цитата',
    );
    final catalog = ConferenceRepository(
      apiClient: api,
      prefs: await SharedPreferences.getInstance(),
    );
    addTearDown(api.dispose);
    addTearDown(catalog.dispose);
    addTearDown(() => SystemChrome.setPreferredOrientations([]));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: const bool.fromEnvironment('FFIDO_ADAPTIVE_LIGHT')
              ? Brightness.light
              : Brightness.dark,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Открыть'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MessageScreen(
                    conferenceId: 'echo',
                    conferenceName: 'Длинное название эхоконференции',
                    conferenceDescription: '',
                    canRead: true,
                    canPost: true,
                    repository: MessageRepository(api),
                    conferences: catalog,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Future<void> tapText(String text) async {
      final target = find.text(text);
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          target,
          100,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tapText('Открыть');
    await tapText('Адаптивная проверка');
    await tapText('Ответить в эху');
    final body = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!;
    await tester.enterText(
      find.byType(TextField).last,
      'Черновик после поворота\n AB> Цитата',
    );
    if (Platform.isAndroid &&
        const bool.fromEnvironment('FFIDO_ADAPTIVE_KEYBOARD')) {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.view.viewInsets.bottom, greaterThan(0));
      debugPrint('ADAPTIVE_KEYBOARD bottom=${tester.view.viewInsets.bottom}');
    }
    final calls = api.calls.length;
    if (Platform.isAndroid) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
      ]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        tester.view.physicalSize.width,
        greaterThan(tester.view.physicalSize.height),
      );
    } else {
      await binding.setSurfaceSize(const Size(600, 700));
      await tester.pumpAndSettle();
    }
    expect(body.text, 'Черновик после поворота\n AB> Цитата');
    expect(api.calls.length, calls);
    expect(tester.takeException(), isNull);
    await tapText('Отправить');
    // FakeTransport records synthetic sends only, with no real server or FTN data.
    expect(api.calls.whereType<wire.CreateMessageRequest>(), hasLength(1));
    if (Platform.isAndroid) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        tester.view.physicalSize.height,
        greaterThan(tester.view.physicalSize.width),
      );
    } else {
      await binding.setSurfaceSize(const Size(1200, 800));
      await tester.pumpAndSettle();
      await binding.setSurfaceSize(null);
    }
    expect(tester.takeException(), isNull);
    debugPrint(
      'ADAPTIVE_ACCEPTANCE physical=${tester.view.physicalSize} density=${tester.view.devicePixelRatio} calls=${api.calls.length}',
    );
  });
}
