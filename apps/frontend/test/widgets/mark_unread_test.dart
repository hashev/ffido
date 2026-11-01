import 'dart:async';

import 'package:fixnum/fixnum.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/pages/personal_conferences.dart';
import 'package:fido/repositories/account_repository.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';

class Fixture {
  final api = FakeTransport();
  bool read = false, failLists = false;
  int detailCalls = 0;
  final AreaKind kind;
  final bool mailbox;
  Fixture({this.kind = AreaKind.echo, this.mailbox = false}) {
    api.messages = (_) async {
      if (failLists) throw const NetworkException();
      return wire.ListMessagesResponse(messages: rows(), total: Int64(2));
    };
    api.thread = (_) async =>
        wire.ListMessagesResponse(messages: rows(), total: Int64(2));
    api.message = (request) async {
      detailCalls++;
      read = true;
      return rows().first;
    };
    api.unread = (_) async {
      read = false;
      return Empty();
    };
    api.conference = (_) async => wire.Conference(
      id: 'area',
      name: 'AREA',
      canRead: true,
      canPost: false,
      kind: wire.AreaKind.values[kind.index],
      personalMailbox: mailbox,
      lastOpenedMessageId: 'g#1',
      positionRevision: Int64(7),
      statisticsKnown: true,
      unreadCount: Int64(read ? 0 : 1),
      totalCount: Int64(2),
    );
  }
  List<wire.Message> rows() => [
    wire.Message(
      id: 'g#1',
      subject: 'Письмо 1',
      body: 'Тело письма',
      fromName: 'Автор',
      isRead: read,
      positionRevision: Int64(7),
    ),
    wire.Message(id: 'g#2', subject: 'Письмо 2', isRead: true),
  ];
}

Future<void> show(WidgetTester tester, Fixture f, {bool canRead = true}) async {
  final prefs = await SharedPreferences.getInstance();
  final conferences = ConferenceRepository(apiClient: f.api, prefs: prefs);
  addTearDown(conferences.dispose);
  addTearDown(f.api.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MessageScreen(
        key: ValueKey(f),
        conferenceId: 'area',
        conferenceName: 'AREA',
        conferenceDescription: '',
        repository: MessageRepository(f.api),
        conferences: conferences,
        canRead: canRead,
        canPost: false,
        kind: f.kind,
        personalMailbox: f.mailbox,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, {bool settle = true}) async {
  await tester.tap(find.byTooltip('Действия области'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Пометить непрочитанным'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final kind in AreaKind.values) {
    testWidgets(
      '${kind.name}: read-only action returns to list without GetMessage and clears counters cache',
      (tester) async {
        final f = Fixture(kind: kind);
        await show(tester, f);
        await tap(tester, 'Письмо 1');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_conferences', 'old');
        await choose(tester);
        expect(find.text('К списку'), findsNothing);
        expect(find.byType(ListTile), findsNWidgets(2));
        expect(find.byIcon(Icons.mail), findsOneWidget);
        expect(f.detailCalls, 1);
        expect(f.api.unreadCalls.single.conferenceId, 'area');
        expect(f.api.unreadCalls.single.messageId, 'g#1');
        expect(prefs.containsKey('cached_conferences'), isFalse);
        expect(f.read, isFalse);
        await tap(tester, 'Письмо 1');
        expect(f.detailCalls, 2);
        expect(f.read, isTrue);
      },
    );
  }

  testWidgets('bookmarks counter updates when returning after marking unread', (
    tester,
  ) async {
    final f = Fixture()..read = true;
    addTearDown(f.api.dispose);
    f.api.bookmarks = (_) async => wire.ListBookmarksResponse(
      bookmarks: [
        wire.Bookmark(
          conference: await f.api.conference!(
            wire.GetConferenceRequest(conferenceId: 'area'),
          ),
        ),
      ],
      total: Int64(1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalConferences(
          history: false,
          repository: AccountRepository(f.api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    await tap(tester, 'AREA');
    await tap(tester, 'Письмо 1');
    await choose(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Закладки'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets(
    'unread is again a navigation target despite having been opened',
    (tester) async {
      final f = Fixture();
      await show(tester, f);
      await tap(tester, 'Письмо 1');
      await choose(tester);
      await tap(tester, 'Следующее');
      expect(find.text('К списку'), findsOneWidget);
      expect(f.detailCalls, 2);
      expect(f.read, isTrue);
    },
  );

  testWidgets('mailbox keeps thread and reading position', (tester) async {
    final f = Fixture(kind: AreaKind.netmail, mailbox: true);
    await show(tester, f);
    await tap(tester, 'Письмо 1');
    await tap(tester, 'Цепочка сообщений');
    await tap(tester, 'Письмо 1');
    final before = f.api.calls.whereType<wire.GetThreadRequest>().length;
    await choose(tester);
    expect(find.text('Все письма'), findsOneWidget);
    expect(f.api.calls.whereType<wire.GetThreadRequest>().length, before + 1);
    expect(f.api.calls.whereType<wire.GetThreadRequest>().last.threadId, 'g#1');
    expect(f.detailCalls, 2);
    expect(find.text('Продолжить с последнего открытого письма'), findsNothing);
  });

  testWidgets(
    'anchored mailbox refresh preserves page, sorting and last opened position',
    (tester) async {
      final f = Fixture(kind: AreaKind.netmail, mailbox: true);
      f.api.messages = (request) async => wire.ListMessagesResponse(
        messages: f.rows(),
        total: Int64(42),
        actualOffset: Int64(
          request.anchorMessageId.isNotEmpty ? 40 : request.page.offset.toInt(),
        ),
      );
      await show(tester, f);
      await tap(tester, 'Продолжить с последнего открытого письма');
      final originalSort = f.api.calls
          .whereType<wire.ListMessagesRequest>()
          .last
          .sort;
      await choose(tester);
      final last = f.api.calls.whereType<wire.ListMessagesRequest>().last;
      expect(last.page.offset.toInt(), 40);
      expect(last.sort, originalSort);
      expect(last.anchorMessageId, isEmpty);
      expect(
        find.text('Продолжить с последнего открытого письма'),
        findsOneWidget,
      );
      expect(f.detailCalls, 1);
    },
  );

  testWidgets(
    'command failure and old server keep the opened letter and allow retry',
    (tester) async {
      final f = Fixture();
      await show(tester, f);
      await tap(tester, 'Письмо 1');
      f.api.unread = (_) async =>
          throw const ApiException(statusCode: 12, message: 'unimplemented');
      await choose(tester);
      expect(find.textContaining('Обновите сервер'), findsOneWidget);
      expect(find.text('К списку'), findsOneWidget);
      f.api.unread = (_) async {
        f.read = false;
        throw const NetworkException();
      };
      await tap(tester, 'Повторить');
      expect(find.text('К списку'), findsOneWidget);
      expect(find.textContaining('Не удалось подтвердить'), findsOneWidget);
      f.api.unread = (_) async => Empty();
      await tap(tester, 'Повторить');
      expect(find.text('К списку'), findsNothing);
      expect(f.api.unreadCalls, hasLength(3));
    },
  );

  testWidgets(
    'refresh failure after confirmed success retries only list and preserves unread',
    (tester) async {
      final f = Fixture();
      await show(tester, f);
      await tap(tester, 'Письмо 1');
      f.failLists = true;
      await choose(tester);
      expect(
        find.textContaining(
          'Письмо помечено непрочитанным. Не удалось обновить',
        ),
        findsOneWidget,
      );
      expect(find.text('К списку'), findsNothing);
      expect(find.byIcon(Icons.mail), findsOneWidget);
      expect(f.read, isFalse);
      f.failLists = false;
      await tap(tester, 'Повторить');
      expect(f.api.unreadCalls, hasLength(1));
      expect(f.detailCalls, 1);
      expect(find.byIcon(Icons.mail), findsOneWidget);
    },
  );

  testWidgets('revoked read access during refresh clears the previous list', (
    tester,
  ) async {
    final f = Fixture();
    await show(tester, f);
    await tap(tester, 'Письмо 1');
    f.api.conference = (_) async =>
        wire.Conference(id: 'area', name: 'AREA', canRead: false);
    await choose(tester);
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('К списку'), findsNothing);
    expect(find.byTooltip('Действия области'), findsNothing);
    expect(find.textContaining('Доступ к области отозван'), findsOneWidget);
    expect(f.read, isFalse);
  });

  testWidgets('late counter refresh cannot populate a new session', (
    tester,
  ) async {
    final f = Fixture();
    await show(tester, f);
    await tap(tester, 'Письмо 1');
    final pending = Completer<wire.Conference>();
    f.api.conference = (_) => pending.future;
    await choose(tester, settle: false);
    expect(find.text('К списку'), findsNothing);
    f.api.messages = (_) async => wire.ListMessagesResponse();
    f.api.switchSession();
    await tester.pumpAndSettle();
    pending.complete(
      wire.Conference(id: 'area', name: 'OLD SESSION', canRead: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('OLD SESSION'), findsNothing);
    expect(find.text('Письмо 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final leave in ['session', 'dispose']) {
    testWidgets(
      'pending command blocks navigation and ignores late result after $leave',
      (tester) async {
        final f = Fixture();
        await show(tester, f);
        await tap(tester, 'Письмо 1');
        final pending = Completer<Empty>();
        f.api.unread = (_) => pending.future;
        await choose(tester, settle: false);
        expect(
          tester
              .widget<PopupMenuButton<String>>(
                find.byType(PopupMenuButton<String>),
              )
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Следующее'))
              .onPressed,
          isNull,
        );
        expect(f.api.unreadCalls, hasLength(1));
        final listCalls = f.api.calls
            .whereType<wire.ListMessagesRequest>()
            .length;
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          f.api.calls.whereType<wire.ListMessagesRequest>().length,
          listCalls,
        );
        if (leave == 'session') {
          f.api.messages = (_) async => wire.ListMessagesResponse();
          f.api.switchSession();
          await tester.pumpAndSettle();
        } else {
          await tester.pumpWidget(const SizedBox());
        }
        pending.complete(Empty());
        await tester.pumpAndSettle();
        expect(find.text('Тело письма'), findsNothing);
        expect(
          find.textContaining('Письмо помечено непрочитанным'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('action is absent without selection and without read access', (
    tester,
  ) async {
    final f = Fixture();
    await show(tester, f);
    await tester.tap(find.byTooltip('Действия области'));
    await tester.pumpAndSettle();
    expect(find.text('Пометить непрочитанным'), findsNothing);
    await tester.tapAt(const Offset(5, 300));
    await tester.pumpAndSettle();
    final denied = Fixture();
    await show(tester, denied, canRead: false);
    expect(find.byTooltip('Действия области'), findsNothing);
  });
}
