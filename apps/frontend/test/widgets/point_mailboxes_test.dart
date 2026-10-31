import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';
import '../support/message_identity.dart';

wire.Message row(int index, {bool outgoing = false}) => wire.Message(
  id: 'g#$index',
  subject: 'Тема $index',
  body: 'Тело $index',
  fromName: 'Автор',
  fromAddress: '2:1/9.7',
  toName: 'Адресат',
  toAddress: '2:1/2.1',
  direction: outgoing
      ? wire.MailDirection.MAIL_DIRECTION_OUTGOING
      : wire.MailDirection.MAIL_DIRECTION_INCOMING,
  positionRevision: Int64(index + 1),
);
wire.Conference state({String? position = 'g#40', int revision = 1}) =>
    wire.Conference(
      id: 'mailbox',
      name: 'Моя почта',
      personalMailbox: true,
      kind: wire.AreaKind.AREA_KIND_NETMAIL,
      canRead: true,
      canPost: true,
      lastOpenedMessageId: position,
      positionRevision: Int64(revision),
    );
Widget screen(FakeTransport api) => MaterialApp(
  home: MessageScreen(
    conferenceId: 'mailbox',
    conferenceName: 'Моя почта',
    conferenceDescription: '',
    kind: AreaKind.netmail,
    personalMailbox: true,
    canRead: true,
    canPost: true,
    repository: MessageRepository(api),
  ),
);
Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  setUp(mockMessageIdentity);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'bulk preserves mailbox position and selected body without GetMessage',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      var marked = false;
      api.conference = (_) async => state(position: 'g#0', revision: 1);
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [row(0)..isRead = marked, row(1)..isRead = marked],
      );
      api.message = (_) async => row(0);
      api.bulkRead = (_) async {
        marked = true;
        return wire.MarkConferenceReadResponse();
      };
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Тема 0');
      final details = api.calls.whereType<wire.MessageReference>().length;
      final states = api.calls.whereType<wire.GetConferenceRequest>().length;
      await tester.tap(find.byTooltip('Действия области'));
      await tester.pumpAndSettle();
      await tap(tester, 'Отметить всё прочитанным');
      await tap(tester, 'Отметить');
      expect(
        api.calls
            .whereType<wire.MarkConferenceReadRequest>()
            .single
            .conferenceId,
        'mailbox',
      );
      expect(api.calls.whereType<wire.MessageReference>().length, details);
      expect(api.calls.whereType<wire.GetConferenceRequest>().length, states);
      expect(find.text('Тело 0'), findsOneWidget);
      expect(find.text('Сообщения отмечены прочитанными'), findsOneWidget);
      await tap(tester, 'Ответить лично');
      expect(
        tester.widget<TextField>(find.byType(TextField).at(3)).controller!.text,
        contains('А> Тело 0\n\n'),
      );
    },
  );
  testWidgets(
    'continue loads actual anchor page and navigates both directions',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.conference = (_) async => state();
      api.messages = (request) async {
        final offset = request.anchorMessageId.isNotEmpty
            ? 40
            : request.page.offset.toInt();
        return wire.ListMessagesResponse(
          messages: [
            for (var i = offset; i < (offset + 20).clamp(0, 45); i++) row(i),
          ],
          actualOffset: Int64(offset),
          hasMore: offset + 20 < 45,
        );
      };
      api.message = (request) async =>
          row(int.parse(request.messageId.split('#').last));
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      expect(find.textContaining('Обновлено с сервера:'), findsOneWidget);
      expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
      await tap(tester, 'Продолжить с последнего открытого письма');
      expect(find.text('Тело 40'), findsOneWidget);
      expect(
        api.calls.whereType<wire.ListMessagesRequest>().last.anchorMessageId,
        'g#40',
      );
      await tap(tester, 'Предыдущее');
      expect(find.text('Тело 39'), findsOneWidget);
      expect(
        api.calls
            .whereType<wire.ListMessagesRequest>()
            .last
            .page
            .offset
            .toInt(),
        20,
      );
      await tap(tester, 'Следующее');
      expect(find.text('Тело 40'), findsOneWidget);
    },
  );
  testWidgets(
    'removed anchor returns to fresh list without false message view',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      var removed = false;
      api.conference = (_) async => state(position: removed ? null : 'g#40');
      api.messages = (request) async {
        if (request.anchorMessageId.isNotEmpty) {
          removed = true;
          throw const NotFoundException();
        }
        return wire.ListMessagesResponse(
          messages: [row(0)],
          actualOffset: Int64.ZERO,
        );
      };
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Продолжить с последнего открытого письма');
      expect(find.text('Тема 0'), findsOneWidget);
      expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
    },
  );
  testWidgets(
    'resume keeps opened personal mail on its anchor page without another view',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.conference = (_) async => state(position: 'g#40', revision: 41);
      api.messages = (request) async => wire.ListMessagesResponse(
        messages: [row(request.anchorMessageId.isEmpty ? 0 : 40)],
        actualOffset: Int64(request.anchorMessageId.isEmpty ? 0 : 40),
      );
      api.message = (_) async => row(40);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Продолжить с последнего открытого письма');
      expect(find.text('Тело 40'), findsOneWidget);
      final views = api.calls.whereType<wire.MessageReference>().length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Тело 40'), findsOneWidget);
      expect(find.text('К списку'), findsOneWidget);
      expect(api.calls.whereType<wire.MessageReference>().length, views);
      expect(
        api.calls.whereType<wire.ListMessagesRequest>().last.anchorMessageId,
        'g#40',
      );
    },
  );
  testWidgets('resume cannot retain deleted personal mail', (tester) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    var removed = false;
    api.conference = (_) async => state(position: 'g#0', revision: 1);
    api.messages = (request) async {
      if (removed && request.anchorMessageId.isNotEmpty) {
        throw const NotFoundException();
      }
      return wire.ListMessagesResponse(messages: removed ? [] : [row(0)]);
    };
    api.message = (_) async => row(0);
    await tester.pumpWidget(screen(api));
    await tester.pumpAndSettle();
    await tap(tester, 'Тема 0');
    removed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Тело 0'), findsNothing);
    expect(find.text('К списку'), findsNothing);
  });
  testWidgets('resume updates position without reopening old selected mail', (
    tester,
  ) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    var revision = 1;
    api.conference = (_) async =>
        state(position: revision == 1 ? 'g#0' : 'g#1', revision: revision);
    api.messages = (_) async => wire.ListMessagesResponse(
      messages: [row(0), row(1)],
      actualOffset: Int64.ZERO,
    );
    api.message = (_) async => row(0);
    await tester.pumpWidget(screen(api));
    await tester.pumpAndSettle();
    await tap(tester, 'Тема 0');
    revision = 2;
    final views = api.calls.whereType<wire.MessageReference>().length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      find.text('Продолжить с последнего открытого письма'),
      findsOneWidget,
    );
    expect(api.calls.whereType<wire.MessageReference>().length, views);
  });
  testWidgets(
    'network failure clears private rows and a session switch cannot revive them',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.conference = (_) async => state();
      api.messages = (_) async => wire.ListMessagesResponse(messages: [row(0)]);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      api.conference = (_) async => throw const NetworkException();
      await tester.tap(find.byTooltip('Обновить'));
      await tester.pumpAndSettle();
      expect(find.text('Тема 0'), findsNothing);
      expect(
        find.text('Продолжить с последнего открытого письма'),
        findsNothing,
      );
      api.switchSession();
      await tester.pumpAndSettle();
      expect(find.text('Тема 0'), findsNothing);
    },
  );
  testWidgets(
    'outgoing personal reply uses destination and retains styled quote',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.conference = (_) async => state(position: null);
      api.messages = (_) async =>
          wire.ListMessagesResponse(messages: [row(0, outgoing: true)]);
      api.message = (_) async => row(0, outgoing: true);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Тема 0');
      await tap(tester, 'Ответить лично');
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller!.text)
          .toList();
      expect(fields, contains('Адресат'));
      expect(fields, contains('2:1/2.1'));
      expect(fields.any((s) => s.contains('> Тело 0')), isTrue);
      expect(find.text('Переслать'), findsNothing);
    },
  );
  testWidgets(
    'personal reply keeps immutable draft and operation after uncertain commit',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.conference = (_) async => state(position: null);
      api.messages = (_) async => wire.ListMessagesResponse(messages: [row(0)]);
      api.message = (_) async => row(0);
      final requests = <wire.CreateMessageRequest>[];
      api.create = (request) async {
        requests.add(request.deepCopy());
        throw const ServerException();
      };
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Тема 0');
      await tap(tester, 'Ответить лично');
      await tap(tester, 'Отправить');
      expect(requests.single.toAddress, '2:1/9.7');
      expect(requests.single.inReplyTo, 'g#0');
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.enabled == false),
        isTrue,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(3)).controller!.text,
        contains('> Тело 0'),
      );
      api.create = (request) async {
        requests.add(request.deepCopy());
        return wire.CreateMessageResponse(
          status: wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
          message: wire.MessageReference(messageId: 'saved'),
        );
      };
      await tap(tester, 'Повторить отправку');
      expect(requests.length, 2);
      expect(requests[1].operationId, requests[0].operationId);
      expect(requests[1].body, requests[0].body);
      expect(requests[1].toAddress, requests[0].toAddress);
    },
  );
  testWidgets(
    'personal thread survives refresh and exits explicitly to all mail',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.conference = (_) async => state(position: null);
      api.messages = (_) async =>
          wire.ListMessagesResponse(messages: [row(0), row(1)]);
      api.message = (_) async => row(0);
      api.thread = (_) async => wire.ListMessagesResponse(messages: [row(0)]);
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'Тема 0');
      await tap(tester, 'Цепочка сообщений');
      expect(find.text('Все письма'), findsOneWidget);
      final before = api.calls.whereType<wire.ListMessagesRequest>().length;
      await tester.tap(find.byTooltip('Обновить'));
      await tester.pumpAndSettle();
      expect(api.calls.whereType<wire.ListMessagesRequest>().length, before);
      expect(api.calls.whereType<wire.GetThreadRequest>().length, 2);
      await tap(tester, 'Все письма');
      expect(find.text('Тема 1'), findsOneWidget);
    },
  );
}
