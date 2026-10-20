import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/api/model_mapping.dart';
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/pages/reader_app.dart';
import 'package:fido/pages/forward_destination.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

void main() {
  test(
    'legacy echo and explicit private metadata map without fake statistics',
    () {
      final legacy = mapConference(wire.Conference(id: 'RU.TEST'));
      expect(legacy.kind, AreaKind.echo);
      expect(legacy.statisticsKnown, isTrue);
      final private = mapConference(
        wire.Conference(
          id: 'private',
          kind: wire.AreaKind.AREA_KIND_NETMAIL,
          storageFormat: 'Squish',
          availability:
              wire.AreaAvailability.AREA_AVAILABILITY_UNSUPPORTED_FORMAT,
          statisticsKnown: false,
        ),
      );
      expect(private.kind, AreaKind.netmail);
      expect(private.unsupportedFormat, isTrue);
      expect(private.statisticsKnown, isFalse);
      final cached = Conference.fromJson(private.toJson());
      expect(cached.kind, private.kind);
      expect(cached.storageFormat, 'Squish');
      expect(cached.statisticsKnown, isFalse);
      expect(cached.copyWith(isBookmarked: true).kind, AreaKind.netmail);
    },
  );
  test(
    'private catalog never persists or falls back after network or denial',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = FakeTransport()
        ..conferences = (_) async => wire.ListConferencesResponse(
          conferences: [
            wire.Conference(
              id: 'private',
              kind: wire.AreaKind.AREA_KIND_NETMAIL,
              name: 'Secret',
            ),
          ],
        );
      final repo = ConferenceRepository(apiClient: api, prefs: prefs);
      addTearDown(repo.dispose);
      addTearDown(api.dispose);
      expect(
        (await repo.fetchConferences()).conferences.single.kind,
        AreaKind.netmail,
      );
      expect(prefs.getKeys(), isEmpty);
      for (final error in [
        const NetworkException(),
        const ApiException(message: 'Denied', statusCode: 7),
      ]) {
        api.conferences = (_) async => throw error;
        await expectLater(
          repo.fetchConferences(),
          throwsA(isA<ApiException>()),
        );
      }
      api.switchSession();
      api.conferences = (_) async => wire.ListConferencesResponse();
      expect((await repo.fetchConferences()).conferences, isEmpty);
    },
  );
  testWidgets(
    'owner groups and unsupported row disappear when switching to point',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final api = FakeTransport()
        ..conferences = (_) async => wire.ListConferencesResponse(
          conferences: [
            wire.Conference(id: 'echo', name: 'Public', canRead: true),
            wire.Conference(
              id: 'net',
              name: 'Mail',
              kind: wire.AreaKind.AREA_KIND_NETMAIL,
              canRead: true,
            ),
            wire.Conference(
              id: 'local',
              name: 'Local',
              kind: wire.AreaKind.AREA_KIND_LOCAL,
              canRead: true,
            ),
            wire.Conference(
              id: 'old',
              name: 'Old',
              kind: wire.AreaKind.AREA_KIND_BAD,
              storageFormat: 'Squish',
              availability:
                  wire.AreaAvailability.AREA_AVAILABILITY_UNSUPPORTED_FORMAT,
              statisticsKnown: false,
            ),
          ],
        );
      final repo = ConferenceRepository(
        apiClient: api,
        prefs: await SharedPreferences.getInstance(),
      );
      addTearDown(repo.dispose);
      addTearDown(api.dispose);
      await tester.pumpWidget(MaterialApp(home: MainScreen(repository: repo)));
      await tester.pumpAndSettle();
      for (final label in ['Эхи', 'Личная почта', 'Локальные', 'Служебные']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.textContaining('Squish не поддерживается'), findsOneWidget);
      await tester.tap(find.text('Old'));
      await tester.pumpAndSettle();
      expect(api.calls.whereType<wire.ListMessagesRequest>(), isEmpty);
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [wire.Conference(id: 'echo', name: 'Public')],
      );
      api.switchSession();
      await tester.pumpAndSettle();
      expect(find.text('Mail'), findsNothing);
      expect(find.text('Old'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final kind in [AreaKind.netmail, AreaKind.local]) {
    testWidgets(
      '$kind composer has private wording, correct requests and uncertain retry',
      (tester) async {
        final api = FakeTransport();
        addTearDown(api.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: MessageScreen(
              conferenceId: 'private',
              conferenceName: 'Private',
              conferenceDescription: '',
              kind: kind,
              canRead: true,
              canPost: true,
              repository: MessageRepository(api),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Новое сообщение'));
        await tester.pumpAndSettle();
        expect(find.textContaining('доступен всем'), findsNothing);
        if (kind == AreaKind.netmail) {
          expect(
            tester
                .widget<TextField>(find.byType(TextField).at(0))
                .controller!
                .text,
            '',
          );
          await tester.tap(find.text('Отправить'));
          await tester.pumpAndSettle();
          expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
          expect(find.textContaining('полный FTN-адрес'), findsOneWidget);
        }
        await tester.enterText(find.byType(TextField).at(0), 'Николай');
        await tester.enterText(find.byType(TextField).at(1), '2:1/3.4');
        await tester.enterText(find.byType(TextField).at(2), 'Тема');
        await tester.enterText(find.byType(TextField).at(3), 'Текст\n> цитата');
        api.create = (_) async =>
            throw const ApiException(message: 'Denied', statusCode: 7);
        await tester.ensureVisible(find.text('Отправить'));
        await tester.tap(find.text('Отправить'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).at(3))
              .controller!
              .text,
          'Текст\n> цитата',
        );
        api.create = (_) async => throw const DeadlineException();
        await tester.tap(find.text('Отправить'));
        await tester.pumpAndSettle();
        final uncertain = api.calls.whereType<wire.CreateMessageRequest>().last;
        expect(uncertain.conferenceId, 'private');
        expect(uncertain.toAddress, '2:1/3.4');
        expect(uncertain.toName, 'Николай');
        expect(uncertain.inReplyTo, '');
        expect(
          tester.widget<TextField>(find.byType(TextField).at(3)).enabled,
          isFalse,
        );
        api.create = (_) async => wire.CreateMessageResponse(
          status: wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
        );
        await tester.ensureVisible(find.text('Повторить отправку'));
        await tester.tap(find.text('Повторить отправку'));
        await tester.pumpAndSettle();
        expect(
          api.calls.whereType<wire.CreateMessageRequest>().last.writeToBuffer(),
          uncertain.writeToBuffer(),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final kind in [
    AreaKind.netmail,
    AreaKind.local,
    AreaKind.bad,
    AreaKind.dupe,
    AreaKind.robots,
  ]) {
    testWidgets(
      '$kind reader never offers echo forwarding and uses correct reply label',
      (tester) async {
        final api = FakeTransport()
          ..messages = (_) async => wire.ListMessagesResponse(
            messages: [wire.Message(id: 'g#1', subject: 'Subject')],
          );
        api.message = (_) async => wire.Message(
          id: 'g#1',
          fromName: 'Name',
          fromAddress: '2:1/3.4',
          subject: 'Subject',
          body: '> quoted',
        );
        addTearDown(api.dispose);
        final writable = kind == AreaKind.netmail || kind == AreaKind.local;
        await tester.pumpWidget(
          MaterialApp(
            home: MessageScreen(
              conferenceId: 'private',
              conferenceName: 'Private',
              conferenceDescription: '',
              kind: kind,
              canRead: true,
              canPost: writable,
              repository: MessageRepository(api),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Subject'));
        await tester.pumpAndSettle();
        expect(find.text('Переслать'), findsNothing);
        expect(find.text('Ответить в эху'), findsNothing);
        if (writable) {
          await tester.ensureVisible(find.text(kind.replyLabel));
          await tester.tap(find.text(kind.replyLabel));
          await tester.pumpAndSettle();
          expect(find.textContaining('доступен всем'), findsNothing);
          expect(
            tester
                .widget<TextField>(find.byType(TextField).at(0))
                .controller!
                .text,
            'Name',
          );
          expect(
            tester
                .widget<TextField>(find.byType(TextField).at(1))
                .controller!
                .text,
            '2:1/3.4',
          );
          expect(
            tester
                .widget<TextField>(find.byType(TextField).at(3))
                .controller!
                .text,
            contains('quoted'),
          );
        } else {
          expect(find.byTooltip('Новое сообщение'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('forward destination only lists writable echoes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = FakeTransport()
      ..conferences = (_) async => wire.ListConferencesResponse(
        conferences: [
          wire.Conference(id: 'echo', name: 'Public', canPost: true),
          wire.Conference(
            id: 'net',
            name: 'Secret',
            kind: wire.AreaKind.AREA_KIND_NETMAIL,
            canPost: true,
          ),
        ],
      );
    final repo = ConferenceRepository(
      apiClient: api,
      prefs: await SharedPreferences.getInstance(),
    );
    addTearDown(repo.dispose);
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ForwardDestination(repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Secret'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
