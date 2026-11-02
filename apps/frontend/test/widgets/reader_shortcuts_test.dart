import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/templates/template_settings.dart';

import '../support/fake_transport.dart';
import '../support/cross_area_reply.dart';
import '../support/message_identity.dart';
import 'command_scope_test.dart' show chord;
import 'unread_echo_navigation_test.dart' as fixture;
import 'uue_workflow_test.dart' as uue_fixture;

import 'package:fido/files/uue_files.dart';

void keyboardTest(String description, WidgetTesterCallback callback) =>
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

void main() {
  late FakeTransport api;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockMessageIdentity();
    api = FakeTransport();
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await api.dispose();
  });
  Future<void> mount(
    WidgetTester t, {
    AreaKind kind = AreaKind.echo,
    bool post = true,
    bool read = true,
    bool outgoing = false,
    bool personal = false,
  }) async {
    api.conference = (r) async => wire.Conference(
      id: r.conferenceId,
      canRead: read,
      canPost: post,
      personalMailbox: personal,
    );
    api.messages = (_) async => wire.ListMessagesResponse(
      messages: [fixture.row('g#1'), fixture.row('g#2')],
    );
    api.message = (r) async => wire.Message(
      id: r.messageId,
      subject: 'Subject ${r.messageId}',
      body: 'Original',
      fromName: 'Author',
      fromAddress: '2:1/9',
      toName: 'Recipient',
      toAddress: '2:1/8',
      direction: outgoing
          ? wire.MailDirection.MAIL_DIRECTION_OUTGOING
          : wire.MailDirection.MAIL_DIRECTION_INCOMING,
    );
    await t.pumpWidget(
      MaterialApp(
        home: MessageScreen(
          conferenceId: 'SOURCE',
          conferenceName: 'SOURCE',
          conferenceDescription: '',
          kind: kind,
          personalMailbox: personal,
          canRead: read,
          canPost: post,
          repository: MessageRepository(api),
          loadTemplate: () async => const TemplateBundle('@quote'),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  keyboardTest(
    'new from list and ordinary reply use same draft, no sending or cross-area picker',
    (t) async {
      await mount(t);
      await chord(t, LogicalKeyboardKey.keyR);
      expect(find.text('Сообщение'), findsNothing);
      await chord(t, LogicalKeyboardKey.keyN);
      expect(find.text('Сообщение'), findsOneWidget);
      expect(replyField(t, 'Тема').text, isEmpty);
      await t.pageBack();
      await t.pumpAndSettle();
      await replyTap(t, 'subject g#1');
      await chord(t, LogicalKeyboardKey.keyR);
      expect(replyField(t, 'Тема').text, 'Re: Subject g#1');
      expect(replyField(t, 'Текст').text, contains('A> Original'));
      expect(replyField(t, 'Получатель').text, 'Author');
      expect(find.text('Изменить область назначения'), findsNothing);
      await replyTap(t, 'Отправить');
      final sent = api.calls.whereType<wire.CreateMessageRequest>().single;
      expect(sent.inReplyTo, 'g#1');
      expect(sent.conferenceId, 'SOURCE');
    },
  );
  for (final outgoing in [false, true]) {
    keyboardTest(
      'Netmail reply retains correspondence outgoing=$outgoing; list matches button',
      (t) async {
        await mount(
          t,
          kind: AreaKind.netmail,
          outgoing: outgoing,
          personal: true,
        );
        await replyTap(t, 'subject g#1');
        await chord(t, LogicalKeyboardKey.keyR);
        expect(
          replyField(t, 'Получатель').text,
          outgoing ? 'Recipient' : 'Author',
        );
        expect(
          replyField(t, 'FTN-адрес получателя').text,
          outgoing ? '2:1/8' : '2:1/9',
        );
        await t.pageBack();
        await t.pumpAndSettle();
        api.calls.clear();
        await chord(t, LogicalKeyboardKey.keyL);
        expect(api.calls.whereType<wire.ListMessagesRequest>(), hasLength(1));
        expect(find.text('Original'), findsNothing);
        api.calls.clear();
        await chord(t, LogicalKeyboardKey.keyL);
        expect(api.calls, isEmpty);
      },
    );
  }
  keyboardTest('Ctrl+L returns to current message list, then is a no-op', (
    t,
  ) async {
    await mount(t);
    await replyTap(t, 'subject g#1');
    api.calls.clear();
    await chord(t, LogicalKeyboardKey.keyL);
    expect(find.text('subject g#2'), findsOneWidget);
    expect(api.calls, isEmpty);
    await chord(t, LogicalKeyboardKey.keyL);
    expect(find.text('SOURCE'), findsOneWidget);
  });
  keyboardTest(
    'selected read-only message text allows search and return to list',
    (t) async {
      await mount(t);
      await replyTap(t, 'subject g#1');
      await t.tap(find.text('Original'));
      await t.pumpAndSettle();
      final editor = FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>();
      expect(editor, isNotNull);
      expect(editor!.widget.readOnly, isTrue);
      await chord(t, LogicalKeyboardKey.keyF);
      expect(find.text('Поиск по письмам'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      await t.tap(find.text('Original'));
      await t.pumpAndSettle();
      await chord(t, LogicalKeyboardKey.keyL);
      expect(find.text('subject g#2'), findsOneWidget);
      expect(find.text('Original'), findsNothing);
    },
  );
  keyboardTest('readonly and no-read commands follow button permissions', (
    t,
  ) async {
    await mount(t, post: false);
    await replyTap(t, 'subject g#1');
    await chord(t, LogicalKeyboardKey.keyR);
    await chord(t, LogicalKeyboardKey.keyN);
    expect(find.text('Сообщение'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.f1);
    await t.pumpAndSettle();
    expect(find.text('Нет права публикации'), findsNWidgets(2));
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await mount(t, read: false);
    await chord(t, LogicalKeyboardKey.keyF);
    expect(find.text('Поиск по письмам'), findsNothing);
    await chord(t, LogicalKeyboardKey.keyN);
    expect(find.text('Сообщение'), findsOneWidget);
  });
  keyboardTest('help explains busy commands while navigation is pending', (
    t,
  ) async {
    await mount(t);
    final pending = Completer<wire.Message>();
    api.message = (_) => pending.future;
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyU);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.f1);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Операция выполняется'), findsNWidgets(5));
    pending.complete(fixture.row('g#1'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
  });
  keyboardTest(
    'pending navigation and session change never duplicate/revive commands',
    (t) async {
      await mount(t);
      final pending = Completer<wire.Message>();
      api.message = (_) => pending.future;
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyU);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.keyN);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(find.text('Сообщение'), findsNothing);
      api.switchSession();
      pending.complete(fixture.row('old#1'));
      await t.pumpAndSettle();
      expect(find.text('body old#1'), findsNothing);
    },
  );
  for (final kind in AreaKind.values.where((k) => k != AreaKind.echo)) {
    keyboardTest('unread unavailable in $kind', (t) async {
      await mount(t, kind: kind);
      api.calls.clear();
      await chord(t, LogicalKeyboardKey.keyU);
      expect(api.calls, isEmpty);
    });
  }
  keyboardTest(
    'unread skips page and read echo, keeps existing exhaustion behavior',
    (t) async {
      await api.dispose();
      api = fixture.apiForEchoes();
      api.messages = (r) async {
        if (r.conferenceId == 'a') {
          return wire.ListMessagesResponse(
            messages: [fixture.row('a#1', read: true)],
            hasMore: r.page.offset.toInt() == 0,
          );
        }
        return wire.ListMessagesResponse(
          messages: [
            fixture.row('${r.conferenceId}#1', read: r.conferenceId == 'b'),
          ],
        );
      };
      await t.pumpWidget(
        fixture.screen(
          api,
          order: [fixture.echo('a'), fixture.echo('b'), fixture.echo('c')],
        ),
      );
      await t.pumpAndSettle();
      await chord(t, LogicalKeyboardKey.keyU);
      expect(find.text('body c#1'), findsOneWidget);
      await chord(t, LogicalKeyboardKey.keyU);
      final count = api.calls.length;
      await chord(t, LogicalKeyboardKey.keyU);
      expect(api.calls.length, count);
      expect(
        find.text('Дальнейших непрочитанных сообщений нет'),
        findsOneWidget,
      );
    },
  );
  keyboardTest('navigation failure remains an error, not exhaustion', (
    t,
  ) async {
    await mount(t);
    api.message = (_) async => throw const NetworkException();
    await chord(t, LogicalKeyboardKey.keyU);
    expect(find.textContaining('Сервер недоступен'), findsWidgets);
    expect(find.text('Дальнейших непрочитанных сообщений нет'), findsNothing);
  });
  keyboardTest('chain suppresses unread shortcut', (t) async {
    await mount(t);
    await replyTap(t, 'subject g#1');
    await replyTap(t, 'Цепочка сообщений');
    api.calls.clear();
    await chord(t, LogicalKeyboardKey.keyU);
    expect(api.calls, isEmpty);
  });
  keyboardTest(
    'editor reader shortcuts preserve explicit UUE attachment without upload',
    (t) async {
      final oldFiles = uueFiles;
      final files = uue_fixture.Files()
        ..selected = SelectedUueFile('draft.bin', Uint8List.fromList([1, 2]));
      uueFiles = files;
      addTearDown(() => uueFiles = oldFiles);
      api.getUueLimitsHandler = (_) async => uue_fixture.limits();
      await openReplySource(t, api, template: const TemplateBundle('@quote'));
      await replyTap(t, 'Ответить лично');
      final text = replyField(t, 'Текст');
      text.text = 'Draft with file';
      await replyTap(t, 'Прикрепить файл UUE');
      for (final key in [
        LogicalKeyboardKey.keyN,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyU,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyF,
      ]) {
        await chord(t, key);
      }
      expect(find.text('draft.bin'), findsOneWidget);
      expect(text.text, 'Draft with file');
      expect(api.calls.whereType<wire.UploadUueChunkRequest>(), isEmpty);
      expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
    },
  );
  keyboardTest(
    'editor, destination and public confirmation isolate background reader',
    (t) async {
      await openReplySource(t, api, template: const TemplateBundle('@quote'));
      await replyTap(t, 'Ответить лично');
      final body = replyField(t, 'Текст');
      body.text = 'Private draft';
      for (final key in [
        LogicalKeyboardKey.keyU,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyN,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyF,
      ]) {
        await chord(t, key);
      }
      expect(find.text('Сообщение'), findsOneWidget);
      expect(body.text, 'Private draft');
      await replyTap(t, 'Изменить область назначения');
      await chord(t, LogicalKeyboardKey.keyN);
      expect(find.text('Область для ответа'), findsOneWidget);
      await replyTap(t, 'OTHER');
      await chord(t, LogicalKeyboardKey.keyR);
      expect(find.text('Опубликовать ответ в эхе?'), findsOneWidget);
      await replyTap(t, 'Отмена');
      expect(body.text, 'Private draft');
      expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
    },
  );
}
