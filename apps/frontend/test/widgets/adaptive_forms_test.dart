import 'package:fido/pages/reader_app.dart';
import 'package:fido/widgets/message_technical_dialog.dart';
import 'package:fido/templates/template_settings_panel.dart';
import 'package:fido/templates/template_settings.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/message_footer.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/settings.dart';
import 'package:fido/pages/reply_destination.dart';
import 'package:fido/pages/forward_destination.dart';
import 'package:fido/pages/crosspost_destinations.dart';
import 'package:fido/pages/profile_screen.dart';
import 'package:fido/pages/personal_conferences.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/repositories/account_repository.dart';

import '../support/fake_transport.dart';
import '../support/adaptive_appearance.dart';
import 'settings_test.dart' as fixtures;

void main() {
  setUpAll(loadAdaptiveFonts);
  for (final size in [
    const Size(320, 568),
    const Size(800, 360),
    const Size(800, 1280),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('forms ${size.width}x${size.height} scale=$scale', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final longError = List.filled(
          20,
          'Сервер недоступен: повторите запрос к https://example.invalid/очень/длинный/путь.',
        ).join(' ');
        final api = FakeTransport();
        addTearDown(api.dispose);
        api.conferences = (_) async => wire.ListConferencesResponse(
          conferences: [
            wire.Conference(
              id: 'target',
              name: 'Очень длинное название доступной области назначения',
              description: 'Длинное описание',
              canRead: true,
              canPost: true,
            ),
          ],
        );
        final repo = ConferenceRepository(apiClient: api, prefs: prefs);
        addTearDown(repo.dispose);
        final client = fixtures.LoginClient();
        addTearDown(client.dispose);
        final key = GlobalKey();
        Future<void> open(Widget child, {bool keyboard = false}) async {
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
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    viewInsets: EdgeInsets.only(bottom: keyboard ? 100 : 0),
                  ),
                  child: child!,
                ),
                home: child,
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }

        await open(
          SettingsWidget(
            client: client,
            preferences: prefs,
            store: fixtures.MemoryStore(),
            footerSettings: MessageFooterSettings(prefs, 'test'),
          ),
          keyboard: true,
        );
        await t.scrollUntilVisible(
          find.text('Подключиться'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await t.ensureVisible(find.text('Подключиться'));
        await t.pumpAndSettle();
        expect(
          t.getRect(find.text('Подключиться')).bottom,
          lessThanOrEqualTo(size.height - 100),
        );
        await adaptiveScreenshot(
          t,
          key,
          'settings-${size.width.toInt()}x${size.height.toInt()}-$scale',
        );
        await open(
          ReplyDestination(repository: repo, sourceId: 'source'),
          keyboard: true,
        );
        await t.scrollUntilVisible(
          find.text('Очень длинное название доступной области назначения'),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await t.ensureVisible(
          find.text('Очень длинное название доступной области назначения'),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await adaptiveScreenshot(
          t,
          key,
          'destination-${size.width.toInt()}x${size.height.toInt()}-$scale',
        );
        await open(ForwardDestination(repository: repo), keyboard: true);
        await open(
          CrosspostDestinations(
            repository: repo,
            primaryId: 'source',
            primaryName: 'Длинное название исходной области',
            selected: [],
          ),
          keyboard: true,
        );
        Future<void> checkDialog(Widget dialog) async {
          await open(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Открыть диалог'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => dialog,
                  ),
                ),
              ),
            ),
            keyboard: true,
          );
          await t.tap(find.text('Открыть диалог'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await t.ensureVisible(find.text('Закрыть'));
          await t.tap(find.text('Закрыть'));
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        }

        await checkDialog(
          TemplatePreview(bundle: const TemplateBundle('@quote')),
        );
        await checkDialog(
          MessageTechnicalDialog(
            repository: MessageRepository(api),
            conferenceId: 'echo',
            messageId: 'g#1',
          ),
        );
        api.profile = () async => throw NetworkException(message: longError);
        await open(ProfileScreen(repository: AccountRepository(api)));
        expect(find.text('Повторить'), findsOneWidget);
        await t.ensureVisible(find.text('Повторить'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        api.conferences = (_) async =>
            throw NetworkException(message: longError);
        final failingRepo = ConferenceRepository(apiClient: api, prefs: prefs);
        addTearDown(failingRepo.dispose);
        await failingRepo.clearCache();
        await open(
          PersonalConferences(
            history: false,
            catalog: true,
            active: true,
            repository: AccountRepository(api),
            conferences: failingRepo,
          ),
          keyboard: true,
        );
        await t.ensureVisible(find.text('Повторить'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        api.conferences = (_) async => wire.ListConferencesResponse();
        await failingRepo.clearCache();
        await open(MainScreen(repository: failingRepo), keyboard: true);
        await t.ensureVisible(find.text('Выбрать эхи'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
}
