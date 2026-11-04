import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/reader_app.dart';
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

void main() {
  setUpAll(() async {
    final executable = Platform.resolvedExecutable.replaceAll('\\', '/');
    final root =
        Platform.environment['FLUTTER_ROOT'] ??
        executable.split('/bin/cache/').first;
    final fonts = Directory('$root/bin/cache/artifacts/material_fonts');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = File('${fonts.path}/${entry.value}').readAsBytesSync();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  for (final width in [320, 1280]) {
    for (final dark in [false, true]) {
      testWidgets('catalog appearance width=$width dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width.toDouble(), 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final api = FakeTransport()
          ..supportsLightweightConferenceCatalog = true;
        addTearDown(api.dispose);
        api.conferences = (r) async => wire.ListConferencesResponse(
          conferences: [
            wire.Conference(
              id: 'ru.test',
              name: 'Длинное название избранной эхоконференции',
              description:
                  'Обсуждение интерфейса и быстрый переход к сообщениям',
              canRead: true,
              isBookmarked: true,
              unreadCount: Int64(2147483647),
            ),
            wire.Conference(
              id: 'ru.zero',
              name: 'Прочитанная эха',
              description: 'Нет непрочитанных',
              canRead: true,
              isBookmarked: true,
              unreadCount: Int64.ZERO,
            ),
            wire.Conference(
              id: 'ru.unknown',
              name: 'Неизвестная статистика',
              description: 'Описание эхи',
              canRead: true,
              isBookmarked: true,
              statisticsKnown: false,
            ),
          ],
        );
        final repo = ConferenceRepository(
          apiClient: api,
          prefs: await SharedPreferences.getInstance(),
        );
        addTearDown(repo.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: ThemeData(
                fontFamily: 'Roboto',
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              home: MainScreen(repository: repo),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final screen in ['favorites', 'catalog']) {
          if (screen == 'catalog') {
            await tester.tap(find.byTooltip('Все области'));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('build/catalog-appearance')
              ..createSync(recursive: true);
            File(
              '${directory.path}/$screen-$width-${dark ? "dark" : "light"}.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.pumpAndSettle();
        expect(find.text('Горячие клавиши'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Горячие клавиши'), findsNothing);
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }
  }
}
