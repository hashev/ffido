import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:fido/files/uue_files.dart';

import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';
import 'package:fido/pages/crosspost_destinations.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_transport.dart';

wire.Conference echo(String id, {bool post = true}) => wire.Conference(
  id: id,
  name: id,
  canPost: post,
  kind: wire.AreaKind.AREA_KIND_ECHO,
);

class _CrosspostFiles extends UueFiles {
  @override
  Future<bool> save(String filename, Uint8List bytes) async => false;
  @override
  Future<SelectedUueFile?> pick(int limit) async =>
      SelectedUueFile('test.bin', Uint8List.fromList([0, 1, 2]));
}

void main() {
  late FakeTransport api;
  ConferenceRepository? repository;
  late SharedPreferences prefs;
  ConferenceRepository getConferences() =>
      repository ??= ConferenceRepository(apiClient: api, prefs: prefs);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = FakeTransport();
    prefs = await SharedPreferences.getInstance();
    repository = null;
  });
  tearDown(() async {
    await repository?.dispose();
    await api.dispose();
  });

  Future<void> picker(
    WidgetTester tester, {
    List<Conference> selected = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CrosspostDestinations(
          repository: getConferences(),
          primaryId: 'RU.ONE',
          primaryName: 'RU.ONE',
          selected: selected,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    api.conferences = (_) async =>
        wire.ListConferencesResponse(conferences: [echo('RU.TWO')]);
    await tester.pumpWidget(
      MaterialApp(
        home: MessageScreen(
          canRead: true,
          canPost: true,
          conferenceId: 'RU.ONE',
          conferenceName: 'RU.ONE',
          conferenceDescription: '',
          repository: MessageRepository(api),
          conferences: getConferences(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Новое сообщение'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(2), 'Тема');
    await tester.enterText(find.byType(TextField).at(3), 'Текст');
  }

  Future<void> composer(WidgetTester tester) async {
    await openEditor(tester);
    await tester.tap(find.byTooltip('Дополнительно'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Кросспостинг'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RU.TWO').first);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
  }

  test('GoldED header uses canonical alphabetical order', () {
    Conference area(String id) => Conference(
      id: id,
      name: id,
      description: '',
      unreadCount: 0,
      totalCount: 0,
    );
    expect(
      crosspostHeader('RU.ONE', [area('RU.TWO'), area('RU.THREE')]),
      '* Originally in RU.ONE\n* Crossposted in RU.THREE\n* Crossposted in RU.TWO\n\n',
    );
  });

  testWidgets(
    'selection survives search and pages; primary and forbidden hidden',
    (tester) async {
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: r.query.isEmpty
            ? [echo('RU.ONE'), echo('RU.TWO'), echo('RU.NO', post: false)]
            : [echo('RU.THREE')],
      );
      await picker(tester);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await tester.tap(find.text('RU.TWO').first);
      await tester.enterText(find.byType(TextField), 'three');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RU.THREE').first);
      await tester.pump();
      expect(find.text('Выбрано дополнительных эх: 2/20'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
    },
  );

  testWidgets('filtered empty page can load next page and retry error', (
    tester,
  ) async {
    var fail = true;
    api.conferences = (r) async {
      if (r.page.offset.toInt() == 0) {
        return wire.ListConferencesResponse(
          conferences: [echo('RU.ONE')],
          hasMore: true,
        );
      }
      if (fail) throw const NetworkException();
      return wire.ListConferencesResponse(conferences: [echo('RU.TWO')]);
    };
    await picker(tester);
    await tester.tap(find.text('Загрузить ещё'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось'), findsOneWidget);
    fail = false;
    await tester.tap(find.textContaining('Повторить'));
    await tester.pumpAndSettle();
    // Retrying the first filtered page still leaves its next page available.
    if (find.text('RU.TWO').evaluate().isEmpty) {
      await tester.tap(find.text('Загрузить ещё'));
      await tester.pumpAndSettle();
    }
    expect(find.text('RU.TWO'), findsNWidgets(2));
  });

  testWidgets('old search result cannot replace current query', (tester) async {
    final old = Completer<wire.ListConferencesResponse>();
    api.conferences = (r) => r.query == 'old'
        ? old.future
        : Future.value(
            wire.ListConferencesResponse(
              conferences: [echo(r.query == 'new' ? 'RU.NEW' : 'RU.TWO')],
            ),
          );
    await picker(tester);
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    old.complete(wire.ListConferencesResponse(conferences: [echo('RU.OLD')]));
    await tester.pumpAndSettle();
    expect(find.text('RU.NEW'), findsNWidgets(2));
    expect(find.text('RU.OLD'), findsNothing);
  });

  testWidgets('composer sends group and blocks UUE without losing text', (
    tester,
  ) async {
    await composer(tester);
    expect(find.textContaining('* Originally in RU.ONE'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Чтобы прикрепить UUE-файл'), findsOneWidget);
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    final sent = api.calls.whereType<wire.CreateCrosspostRequest>().single;
    expect(sent.message.body, 'Текст');
    expect(sent.additionalConferenceIds, ['RU.TWO']);
    expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
    expect(find.text('Сообщение сохранено локально'), findsOneWidget);
  });

  for (final partial in [true, false]) {
    testWidgets('group retry preserves frozen payload partial=$partial', (
      tester,
    ) async {
      api.crosspost = (_) async {
        if (!partial) throw const NetworkException();
        return wire.CreateCrosspostResponse(
          complete: false,
          total: 2,
          saved: [
            wire.CrosspostCopy(
              message: wire.MessageReference(
                conferenceId: 'RU.ONE',
                messageId: 'g#42',
              ),
              ftnMessageId: '2:1/2 12345678',
            ),
          ],
        );
      };
      await composer(tester);
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(3)).enabled,
        isFalse,
      );
      final first = api.calls
          .whereType<wire.CreateCrosspostRequest>()
          .single
          .writeToBuffer();
      api.crosspost = null;
      await tester.tap(find.text('Повторить отправку'));
      await tester.pumpAndSettle();
      expect(
        api.calls.whereType<wire.CreateCrosspostRequest>().last.writeToBuffer(),
        first,
      );
      expect(find.text('Сообщение сохранено локально'), findsOneWidget);
    });
  }

  testWidgets('unsupported server preserves editable draft without fallback', (
    tester,
  ) async {
    api.crosspost = (_) async =>
        throw const ApiException(message: 'unsupported', statusCode: 12);
    await composer(tester);
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('не поддерживает кросспостинг'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(3)).enabled,
      isTrue,
    );
    expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
  });

  testWidgets('twenty selected areas disable the twenty-first checkbox', (
    tester,
  ) async {
    final selected = List.generate(
      20,
      (i) => Conference(
        id: 'ECHO.$i',
        name: 'ECHO.$i',
        description: '',
        unreadCount: 0,
        totalCount: 0,
      ),
    );
    api.conferences = (_) async => wire.ListConferencesResponse(
      conferences: [echo('ECHO.EXTRA'), echo('ECHO.0')],
    );
    await picker(tester, selected: selected);
    final extra = find.ancestor(
      of: find.text('ECHO.EXTRA').first,
      matching: find.byType(CheckboxListTile),
    );
    expect(tester.widget<CheckboxListTile>(extra).onChanged, isNull);
    await tester.tap(find.text('ECHO.0').first);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(extra).onChanged, isNotNull);
  });

  testWidgets(
    'cancel preserves selection; confirm empty returns to normal sending',
    (tester) async {
      await composer(tester);
      await tester.tap(find.byTooltip('Дополнительно'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кросспостинг'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RU.TWO').first);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Кросспостинг: RU.TWO'), findsOneWidget);
      await tester.tap(find.byTooltip('Дополнительно'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кросспостинг'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await tester.tap(find.text('RU.TWO').first);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      expect(api.calls.whereType<wire.CreateMessageRequest>().length, 1);
      expect(api.calls.whereType<wire.CreateCrosspostRequest>(), isEmpty);
    },
  );

  testWidgets(
    'unknown group result warns on close and session change closes frozen editor',
    (tester) async {
      api.crosspost = (_) async => throw const NetworkException();
      await composer(tester);
      await tester.tap(find.text('Отправить'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Закрыть незавершённую отправку?'), findsOneWidget);
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      api.switchSession();
      await tester.pumpAndSettle();
      expect(find.text('Отправить'), findsNothing);
      expect(find.text('Повторить отправку'), findsNothing);
    },
  );

  testWidgets('double submit does not dispatch another group', (tester) async {
    final pending = Completer<wire.CreateCrosspostResponse>();
    api.crosspost = (_) => pending.future;
    await composer(tester);
    await tester.tap(find.text('Отправить'));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(api.calls.whereType<wire.CreateCrosspostRequest>().length, 1);
    pending.completeError(const NetworkException());
    await tester.pumpAndSettle();
  });

  testWidgets('attached UUE disables crossposting without changing draft', (
    tester,
  ) async {
    final previous = uueFiles;
    uueFiles = _CrosspostFiles();
    addTearDown(() => uueFiles = previous);
    api.getUueLimitsHandler = (_) async => wire.UueLimits(
      maxFileBytes: Int64(1024),
      partBodyBytes: 32768,
      maxParts: 10,
      chunkBytes: 65536,
      previewPixels: Int64(16000000),
      previewDimension: 8192,
    );
    await openEditor(tester);
    await tester.scrollUntilVisible(
      find.text('Прикрепить файл UUE'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Прикрепить файл UUE'));
    await tester.pumpAndSettle();
    expect(find.text('test.bin'), findsOneWidget);
    await tester.tap(find.byTooltip('Дополнительно'));
    await tester.pumpAndSettle();
    final item = tester.widget<PopupMenuItem<String>>(
      find.byType(PopupMenuItem<String>),
    );
    expect(item.enabled, isFalse);
    expect(find.textContaining('только текст, уберите UUE'), findsOneWidget);
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(3)).controller!.text,
      'Текст',
    );
  });

  for (final forward in [false, true]) {
    testWidgets(
      'crosspost original and reply relation follow composer forward=$forward',
      (tester) async {
        api.messages = (_) async => wire.ListMessagesResponse(
          messages: [wire.Message(id: 'g#42', subject: 'Original')],
        );
        api.message = (_) async => wire.Message(
          id: 'g#42',
          subject: 'Original',
          fromName: 'Author',
          fromAddress: '2:1/9',
          body: 'Source',
        );
        api.conferences = (_) async => wire.ListConferencesResponse(
          conferences: [echo('RU.TARGET'), echo('RU.EXTRA')],
        );
        api.conference = (r) async => echo(r.conferenceId);
        await tester.pumpWidget(
          MaterialApp(
            home: MessageScreen(
              conferenceId: 'RU.SOURCE',
              conferenceName: 'RU.SOURCE',
              conferenceDescription: '',
              canRead: true,
              canPost: true,
              repository: MessageRepository(api),
              conferences: getConferences(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Original'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.text(forward ? 'Переслать' : 'Ответить в эху'),
        );
        await tester.tap(find.text(forward ? 'Переслать' : 'Ответить в эху'));
        await tester.pumpAndSettle();
        if (forward) {
          await tester.tap(find.text('RU.TARGET').first);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Дополнительно'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Кросспостинг'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('RU.EXTRA').first);
        await tester.tap(find.text('Готово'));
        await tester.pumpAndSettle();
        if (forward) {
          await tester.tap(find.text('Изменить эху назначения'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('RU.EXTRA').first);
          await tester.pumpAndSettle();
          expect(find.textContaining('* Crossposted in'), findsNothing);
          await tester.tap(find.byTooltip('Дополнительно'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Кросспостинг'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('RU.TARGET').first);
          await tester.tap(find.text('Готово'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Отправить'));
        await tester.pumpAndSettle();
        final sent = api.calls.whereType<wire.CreateCrosspostRequest>().single;
        expect(sent.message.conferenceId, forward ? 'RU.EXTRA' : 'RU.SOURCE');
        expect(sent.message.inReplyTo, forward ? '' : 'g#42');
        expect(
          sent.additionalConferenceIds,
          forward ? ['RU.TARGET'] : ['RU.EXTRA'],
        );
      },
    );
  }

  for (final kind in [AreaKind.netmail, AreaKind.local, AreaKind.bad]) {
    testWidgets('crossposting is absent for $kind', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MessageScreen(
            kind: kind,
            conferenceId: 'AREA',
            conferenceName: 'AREA',
            conferenceDescription: '',
            canRead: true,
            canPost: true,
            repository: MessageRepository(api),
            conferences: getConferences(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Новое сообщение'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Дополнительно'), findsNothing);
    });
  }
}
