import 'dart:async';

import 'package:fido/pages/personal_conferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/reader_app.dart';
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

wire.Conference area(String id, int count) => wire.Conference(
  id: id,
  name: id,
  canRead: true,
  isBookmarked: true,
  unreadCount: Int64(count),
);
Future<void> start(WidgetTester tester, FakeTransport api) async {
  SharedPreferences.setMockInitialValues({});
  addTearDown(api.dispose);
  final repo = ConferenceRepository(
    apiClient: api,
    prefs: await SharedPreferences.getInstance(),
  );
  addTearDown(repo.dispose);
  await tester.pumpWidget(MaterialApp(home: MainScreen(repository: repo)));
  await tester.pumpAndSettle();
}

void main() {
  for (final retry in [false, true]) {
    testWidgets('return updates only touched favorite, retry=$retry', (
      tester,
    ) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [area('a', 2), area('b', 7)],
      );
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: 'a#1', subject: 'Letter')],
      );
      api.message = (r) async =>
          wire.Message(id: r.messageId, body: 'Body', isRead: true);
      var updates = 0;
      api.conference = (r) async {
        updates++;
        if (retry && updates == 1) throw const NetworkException();
        return area(r.conferenceId, 1);
      };
      await start(tester, api);
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Letter'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      if (retry) {
        expect(
          find.textContaining('Не удалось обновить счётчик'),
          findsOneWidget,
        );
        await tester.tap(find.text('Повторить'));
        await tester.pumpAndSettle();
      }
      expect(find.text('1'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(api.calls.whereType<wire.ListConferencesRequest>(), hasLength(1));
      expect(
        api.calls.whereType<wire.GetConferenceRequest>().every(
          (r) => r.conferenceId == 'a',
        ),
        isTrue,
      );
      expect(api.calls.whereType<wire.MessageReference>(), hasLength(1));
    });
  }
  testWidgets(
    'denied reading removes only the revoked row without catalog reload',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [area('a', 1), area('b', 2)],
      );
      api.messages = (_) async =>
          throw const ApiException(message: 'Denied', statusCode: 7);
      await start(tester, api);
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('a'), findsNothing);
      expect(find.text('b'), findsOneWidget);
      expect(api.calls.whereType<wire.ListConferencesRequest>(), hasLength(1));
    },
  );
  testWidgets('keyboard can confirm bookmark through focused action', (
    tester,
  ) async {
    final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
    api.conferences = (r) async => wire.ListConferencesResponse(
      conferences: r.bookmarkedOnly ? [] : [area('a', 0)..isBookmarked = false],
    );
    var saved = 0;
    api.add = (_) async {
      saved++;
      return Empty();
    };
    await start(tester, api);
    await tester.tap(find.byTooltip('Все области'));
    await tester.pumpAndSettle();
    bool focused() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<IconButton>()
            ?.tooltip ==
        'Добавить в закладки';
    for (var i = 0; i < 30 && !focused(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focused(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(find.byTooltip('Удалить из закладок'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets(
    'denied point refresh redacts both retained lists without rereading catalog',
    (tester) async {
      final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [area('a', 1), area('b', 2)],
      );
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: 'a#1', subject: 'Letter')],
      );
      api.message = (r) async =>
          wire.Message(id: r.messageId, body: 'Body', isRead: true);
      api.conference = (_) async =>
          throw const ApiException(message: 'Denied', statusCode: 7);
      await start(tester, api);
      await tester.tap(find.byTooltip('Все области'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Закладки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Letter'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('a'), findsNothing);
      await tester.tap(find.byTooltip('Все области'));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsNothing);
      expect(find.text('b'), findsOneWidget);
      expect(api.calls.whereType<wire.ListConferencesRequest>(), hasLength(2));
    },
  );

  testWidgets('catalog resize keeps query pages scroll and pending bookmark', (
    t,
  ) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(600, 800);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api = FakeTransport()..supportsLightweightConferenceCatalog = true;
    api.conferences = (r) async => wire.ListConferencesResponse(
      conferences: List.generate(
        20,
        (i) => area('echo-${r.page.offset.toInt() + i}', 1),
      ),
      hasMore: r.page.offset.toInt() == 0,
    );
    final pending = Completer<Empty>();
    api.add = (_) => pending.future;
    api.remove = (_) => pending.future;
    await start(t, api);
    await t.tap(find.byTooltip('Все области'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'echo');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    final state = t.state<PersonalConferencesState>(
      find.byWidgetPredicate((w) => w is PersonalConferences && w.catalog),
    );
    await state.load(more: true);
    await t.pumpAndSettle();
    expect(state.entries, hasLength(40));
    state.controller.jumpTo(100);
    await t.pumpAndSettle();
    final offset = state.controller.offset;
    final operation = state.toggle(state.entries.first);
    await t.pump();
    final calls = api.calls.length;
    for (final width in [599.0, 600.0, 1023.0, 1024.0, 600.0]) {
      t.view.physicalSize = Size(width, 800);
      await t.pumpAndSettle();
      expect(state.search.text, 'echo');
      expect(state.entries, hasLength(40));
      expect(state.controller.offset, offset);
      expect(api.calls.length, calls);
      expect(t.takeException(), isNull);
    }
    pending.complete(Empty());
    await operation;
    await t.pumpAndSettle();
    expect(state.search.text, 'echo');
    expect(state.entries, hasLength(40));
  });
}
