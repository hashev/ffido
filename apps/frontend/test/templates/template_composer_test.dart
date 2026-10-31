import 'dart:convert';

import 'package:flutter/services.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/templates/template_settings.dart';

import '../support/fake_transport.dart';

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

String field(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rootBundle.evict('assets/updates/identity.json');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'flutter/assets',
          (_) async => ByteData.sublistView(
            Uint8List.fromList(utf8.encode('{"version":"test"}')),
          ),
        );
  });
  Future<FakeTransport> open(
    WidgetTester tester, {
    TemplateBundle? bundle,
    Future<TemplateBundle?> Function()? loader,
    AreaKind kind = AreaKind.echo,
    bool outgoing = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (bundle != null) await TemplateSettings(prefs).save(bundle);
    final api = FakeTransport();
    addTearDown(api.dispose);
    api.conferences = (_) async => wire.ListConferencesResponse(
      conferences: [
        wire.Conference(
          id: 'target',
          name: 'RU.TARGET',
          canRead: true,
          canPost: true,
        ),
      ],
    );
    api.conference = (_) async => wire.Conference(
      id: 'target',
      name: 'RU.TARGET',
      canRead: true,
      canPost: true,
    );
    final conferences = ConferenceRepository(apiClient: api, prefs: prefs);
    addTearDown(conferences.dispose);
    api.messages = (_) async => wire.ListMessagesResponse(
      messages: [wire.Message(id: 'g#1', subject: 'Тема')],
    );
    api.message = (_) async => wire.Message(
      id: 'g#1',
      subject: 'Тема',
      fromName: outgoing ? 'Я' : 'Автор',
      fromAddress: '2:1/1',
      toName: 'Адресат',
      toAddress: '2:1/2',
      body: 'Оригинал',
      direction: outgoing
          ? wire.MailDirection.MAIL_DIRECTION_OUTGOING
          : wire.MailDirection.MAIL_DIRECTION_INCOMING,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MessageScreen(
          conferenceId: 'id',
          conferenceName: 'RU.TEST',
          conferenceDescription: 'Описание',
          kind: kind,
          canPost: true,
          canRead: true,
          repository: MessageRepository(api),
          conferences: conferences,
          loadTemplate: loader,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  Future<void> select(WidgetTester tester) async {
    await tap(tester, 'Тема');
  }

  testWidgets('default applies to new drafts after update and reset', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Новое сообщение'));
    await tester.pumpAndSettle();
    expect(field(tester, 'Текст'), contains('Hello, !'));
    expect(field(tester, 'Текст'), contains('Best Regards, Реальный'));
    final body = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Текст'))
        .controller!;
    expect(
      body.selection.baseOffset,
      body.text.indexOf('Hello, !') + 'Hello, !\n\n'.length,
    );
    body.text = 'Ручная правка';
    final prefs = await SharedPreferences.getInstance();
    await TemplateSettings(prefs).save(const TemplateBundle('Собственный'));
    await tester.pump();
    expect(field(tester, 'Текст'), 'Ручная правка');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Новое сообщение'));
    await tester.pumpAndSettle();
    expect(field(tester, 'Текст'), 'Собственный');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await TemplateSettings(prefs).reset();
    await tester.tap(find.byTooltip('Новое сообщение'));
    await tester.pumpAndSettle();
    expect(field(tester, 'Текст'), contains('Hello, !'));
    expect(field(tester, 'Текст'), contains('Best Regards, Реальный'));
    expect(prefs.containsKey(TemplateSettings.key), isFalse);
  });

  testWidgets('default reply modes insert one quote or none', (tester) async {
    await open(tester);
    await select(tester);
    await tap(tester, 'Ответить в эху');
    var text = field(tester, 'Текст');
    expect(text, contains('Hello, Автор!'));
    expect(text, contains('from Автор -> Адресат:'));
    expect('А> Оригинал'.allMatches(text), hasLength(1));
    expect(text, isNot(contains('Reply to message')));
    final body = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Текст'))
        .controller!;
    expect(body.selection.baseOffset, lessThan(text.indexOf('from Автор')));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Вид ответа'));
    await tester.pumpAndSettle();
    await tap(tester, 'Без цитаты');
    text = field(tester, 'Текст');
    expect(text, contains('Reply to message from <'));
    expect(text, contains('>, Автор -> Адресат:'));
    expect(text, contains('Hello, Автор!'));
    expect(text, contains('Best Regards, Реальный'));
    expect(text, isNot(contains('Оригинал')));
  });

  testWidgets('default forward has one header and original before greeting', (
    tester,
  ) async {
    await open(tester);
    await select(tester);
    await tap(tester, 'Переслать');
    await tap(tester, 'RU.TARGET');
    final body = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Текст'))
        .controller!;
    expect('* Forwarded by'.allMatches(body.text), hasLength(1));
    expect('Оригинал'.allMatches(body.text), hasLength(1));
    expect(body.text, contains('* Area : RU.TEST (Описание)'));
    expect(
      body.text.indexOf('Оригинал'),
      lessThan(body.text.indexOf('Hello,')),
    );
    expect(body.text, contains('Best Regards, Реальный'));
    final initial = body.text;
    body.text = '$initial\nПравка';
    await tap(tester, 'Изменить эху назначения');
    await tap(tester, 'RU.TARGET');
    expect(body.text, '$initial\nПравка');
  });

  testWidgets(
    'custom new letter applies headers, author, area and cursor once',
    (tester) async {
      await open(
        tester,
        bundle: TemplateBundle(
          '@new@forcesubj Новая\n@forceto Другой\n@cfname|@cecho\n@positionПодпись',
        ),
      );
      await tester.tap(find.byTooltip('Новое сообщение'));
      await tester.pumpAndSettle();
      expect(field(tester, 'Тема'), 'Новая');
      expect(field(tester, 'Получатель'), 'Другой');
      expect(field(tester, 'Текст'), 'Реальный|RU.TEST\nПодпись');
      final body = tester
          .widget<TextField>(find.widgetWithText(TextField, 'Текст'))
          .controller!;
      expect(body.selection.baseOffset, body.text.indexOf('Подпись'));
      body.text = 'Ручная правка';
      final prefs = await SharedPreferences.getInstance();
      await TemplateSettings(prefs).save(TemplateBundle('Другой шаблон'));
      await tester.pump();
      expect(field(tester, 'Текст'), 'Ручная правка');
    },
  );
  testWidgets('quoted reply and explicit plain reply use distinct branches', (
    tester,
  ) async {
    const tpl = '@quotedС цитатой\n@replyБез цитаты\n@quote';
    await open(tester, bundle: TemplateBundle(tpl));
    await select(tester);
    await tap(tester, 'Ответить в эху');
    expect(field(tester, 'Текст'), 'С цитатой\nА> Оригинал\n\n');
    expect(field(tester, 'Получатель'), 'Автор');
    expect(field(tester, 'FTN-адрес получателя'), '2:1/1');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Вид ответа'));
    await tester.pumpAndSettle();
    await tap(tester, 'Без цитаты');
    expect(field(tester, 'Текст'), 'Без цитаты\n');
    expect(
      find.text('Ответ будет опубликован в эхе и доступен всем участникам.'),
      findsOneWidget,
    );
  });
  testWidgets('outgoing netmail retains destination and parent on send', (
    tester,
  ) async {
    final api = await open(
      tester,
      bundle: TemplateBundle(
        '@forceto Изменённый\n@replyОтвет\n@quotedЦитата\n@quote',
      ),
      kind: AreaKind.netmail,
      outgoing: true,
    );
    await select(tester);
    await tap(tester, 'Ответить лично');
    expect(field(tester, 'Получатель'), 'Изменённый');
    expect(field(tester, 'FTN-адрес получателя'), '2:1/2');
    await tap(tester, 'Отправить');
    final request = api.calls.whereType<wire.CreateMessageRequest>().single;
    expect(request.toName, 'Изменённый');
    expect(request.toAddress, '2:1/2');
    expect(request.inReplyTo, 'g#1');
  });
  testWidgets(
    'generated text and user edits freeze through uncertain retries',
    (tester) async {
      final api = await open(tester, bundle: TemplateBundle('Подпись @cfname'));
      api.create = (_) async => throw const ServerException(statusCode: 14);
      await tester.tap(find.byTooltip('Новое сообщение'));
      await tester.pumpAndSettle();
      final body = tester
          .widget<TextField>(find.widgetWithText(TextField, 'Текст'))
          .controller!;
      body.text = '${body.text}Правка';
      await tester.enterText(find.widgetWithText(TextField, 'Тема'), 'Тема');
      await tap(tester, 'Отправить');
      await tap(tester, 'Повторить отправку');
      final requests = api.calls
          .whereType<wire.CreateMessageRequest>()
          .toList();
      expect(requests.length, 2);
      expect(requests[0].body, requests[1].body);
      expect(requests[0].operationId, requests[1].operationId);
      expect(requests[0].body, endsWith('Правка'));
    },
  );
  testWidgets(
    'loading blocks input and late completion cannot revive old session',
    (tester) async {
      final pending = Completer<TemplateBundle?>();
      final api = await open(tester, loader: () => pending.future);
      await tester.tap(find.byTooltip('Новое сообщение'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Текст'))
            .enabled,
        isFalse,
      );
      api.switchSession();
      await tester.pumpAndSettle();
      pending.complete(TemplateBundle('Поздний'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('corrupt configuration offers explicit legacy fallback', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(TemplateSettings.key, 'corrupt');
    await open(tester);
    await select(tester);
    await tap(tester, 'Ответить в эху');
    expect(find.textContaining('Не удалось применить шаблон'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, 'Текст')).enabled,
      isFalse,
    );
    await tap(tester, 'Использовать штатное оформление');
    expect(field(tester, 'Текст'), 'А> Оригинал\n\n');
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, 'Текст')).enabled,
      isTrue,
    );
  });
  testWidgets('explicit empty override suppresses automatic quote', (
    tester,
  ) async {
    await open(tester, bundle: TemplateBundle(''));
    await select(tester);
    await tap(tester, 'Ответить в эху');
    expect(field(tester, 'Текст'), '');
  });
}
