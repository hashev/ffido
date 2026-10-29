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
  });
}
