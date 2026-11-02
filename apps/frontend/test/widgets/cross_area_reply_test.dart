import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';

import '../support/fake_transport.dart';
import '../support/cross_area_reply.dart';
import '../support/message_identity.dart';

void main() {
  late FakeTransport api;
  setUp(() {
    mockMessageIdentity();
    SharedPreferences.setMockInitialValues({});
    api = FakeTransport();
  });
  tearDown(() async => api.dispose());
  testWidgets(
    'readonly source opens editable personal reply with author and FTN quote',
    (t) async {
      await openReplySource(t, api);
      expect(find.text('Ответить в эху'), findsNothing);
      await replyTap(t, 'Ответить лично');
      expect(replyField(t, 'Получатель').text, 'Иван Петров');
      expect(replyField(t, 'FTN-адрес получателя').text, '2:1/9.7');
      expect(replyField(t, 'Тема').text, 'Re: Тема');
      expect(replyField(t, 'Текст').text, contains('ИП> Привет'));
      expect(replyField(t, 'Текст').text, contains('АБ>> Уже цитата'));
      expect(replyField(t, 'Текст').text, isNot(contains('Forwarded')));
      expect(find.byTooltip('Дополнительно'), findsNothing);
      await t.enterText(
        find.widgetWithText(TextField, 'Получатель'),
        'Ручной адресат',
      );
      expect(replyField(t, 'Получатель').text, 'Ручной адресат');
      expect(
        find.text('Личный ответ получателю через Netmail.'),
        findsOneWidget,
      );
    },
  );
  for (final kind in AreaKind.values.where((k) => k != AreaKind.echo)) {
    testWidgets('new cross-area actions absent in $kind', (t) async {
      await openReplySource(t, api, kind: kind);
      expect(find.text('Ответить в другую область…'), findsNothing);
      expect(find.text('Ответить лично'), findsNothing);
    });
  }
  testWidgets('cancel picker preserves source and sends nothing', (t) async {
    await openReplySource(t, api);
    await replyTap(t, 'Ответить в другую область…');
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Re: Тема'), findsOneWidget);
    expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
  });
  testWidgets(
    'personal to echo requires named confirmation and preserves draft',
    (t) async {
      await openReplySource(t, api);
      await replyTap(t, 'Ответить лично');
      replyField(t, 'Текст').text = 'Личный черновик';
      replyField(t, 'Тема').text = 'Правка';
      replyField(t, 'Получатель').text = 'Кому';
      await replyTap(t, 'Изменить область назначения');
      await replyTap(t, 'OTHER');
      expect(
        find.text('Ответ в OTHER будет доступен всем участникам эхи.'),
        findsOneWidget,
      );
      await replyTap(t, 'Отмена');
      await t.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await t.pumpAndSettle();
      expect(find.text('Netmail: MAIL'), findsOneWidget);
      await replyTap(t, 'Изменить область назначения');
      await replyTap(t, 'OTHER');
      await replyTap(t, 'Выбрать эху');
      await t.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await t.pumpAndSettle();
      expect(find.text('Эха: OTHER'), findsOneWidget);
      expect(replyField(t, 'Текст').text, 'Личный черновик');
      expect(replyField(t, 'Тема').text, 'Правка');
      expect(replyField(t, 'Получатель').text, 'Кому');
      expect(find.textContaining('Шаблон уже применён'), findsOneWidget);
    },
  );
  for (final address in ['', '2:bad']) {
    testWidgets(
      'invalid author address requires manual correction ($address)',
      (t) async {
        await openReplySource(t, api, authorAddress: address, subject: 'Тема');
        await replyTap(t, 'Ответить лично');
        expect(replyField(t, 'Тема').text, 'Re: Тема');
        await replyTap(t, 'Отправить');
        expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
        expect(
          find.text('Укажите имя и полный FTN-адрес получателя'),
          findsOneWidget,
        );
        replyField(t, 'FTN-адрес получателя').text = '2:1/3.4';
        await replyTap(t, 'Отправить');
        final request = api.calls.whereType<wire.CreateMessageRequest>().single;
        expect(request.toAddress, '2:1/3.4');
        expect(request.inReplyTo, isEmpty);
        expect(request.conferenceId, 'MAIL');
        expect(
          find.text('Re: Тема'),
          findsNothing,
        ); // source had unprefixed title
        expect(find.text('Тема'), findsOneWidget);
      },
    );
  }
  for (final failure in [
    'revoked',
    'deleted',
    'type',
    'network',
    'aka',
    'encoding',
  ]) {
    testWidgets(
      'fresh destination failure $failure preserves draft and destination',
      (t) async {
        await openReplySource(t, api);
        await replyTap(t, 'Ответить лично');
        replyField(t, 'Текст').text = 'Сохранить текст';
        api.conference = (_) async {
          if (failure == 'deleted') throw const NotFoundException();
          if (failure == 'network') throw const NetworkException();
          return replyArea(
            'MAIL',
            post: failure != 'revoked',
            netmail: failure != 'type',
          );
        };
        api.create = (_) async => throw ApiException(
          message: failure,
          statusCode: failure == 'aka' ? 7 : 3,
        );
        await replyTap(t, 'Отправить');
        expect(replyField(t, 'Текст').text, 'Сохранить текст');
        expect(find.text('Netmail: MAIL'), findsOneWidget);
        expect(
          api.calls.whereType<wire.CreateMessageRequest>().length,
          ['aka', 'encoding'].contains(failure) ? 1 : 0,
        );
        expect(
          t.widget<TextField>(find.widgetWithText(TextField, 'Текст')).enabled,
          isTrue,
        );
      },
    );
  }
  testWidgets(
    'lost result freezes fields and retries same key without new preflight',
    (t) async {
      final repo = await openReplySource(t, api);
      await replyTap(t, 'Ответить лично');
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [replyArea('CACHED.ECHO', netmail: false)],
      );
      await repo.fetchConferences(forceRefresh: true);
      var count = 0;
      api.create = (_) async {
        if (count++ == 0) throw const NetworkException();
        return wire.CreateMessageResponse(
          message: wire.MessageReference(
            conferenceId: 'MAIL',
            messageId: 'target#99',
          ),
          status: wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
        );
      };
      api.calls.clear();
      await replyTap(t, 'Отправить');
      for (final label in [
        'Получатель',
        'FTN-адрес получателя',
        'Тема',
        'Текст',
      ]) {
        expect(
          t.widget<TextField>(find.widgetWithText(TextField, label)).enabled,
          isFalse,
        );
      }
      expect(
        t
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Изменить область назначения'),
            )
            .onPressed,
        isNull,
      );
      api.conference = (_) async => throw const NetworkException();
      await replyTap(t, 'Повторить отправку');
      final requests = api.calls
          .whereType<wire.CreateMessageRequest>()
          .toList();
      expect(requests, hasLength(2));
      expect(requests[1], requests[0]);
      expect(api.calls.whereType<wire.GetConferenceRequest>(), hasLength(1));
      expect(find.text('Re: Тема'), findsOneWidget);
      expect(
        api.calls.whereType<wire.MessageReference>().where(
          (r) => r.messageId == 'target#99',
        ),
        isEmpty,
      );
      // Catalog cache is invalidated after successful send.
      api.conferences = (_) async => throw const NetworkException();
      await expectLater(
        repo.fetchConferences(),
        throwsA(isA<NetworkException>()),
      );
    },
  );
  testWidgets('definite refusal allows explicit target change with a new key', (
    t,
  ) async {
    await openReplySource(t, api);
    await replyTap(t, 'Ответить лично');
    api.create = (_) async =>
        throw const ValidationException(message: 'encoding');
    await replyTap(t, 'Отправить');
    await replyTap(t, 'Изменить область назначения');
    await replyTap(t, 'OTHER');
    await replyTap(t, 'Выбрать эху');
    api.create = (_) async => wire.CreateMessageResponse(
      message: wire.MessageReference(
        conferenceId: 'MAIL',
        messageId: 'target#99',
      ),
      status: wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
    );
    await replyTap(t, 'Отправить');
    final requests = api.calls.whereType<wire.CreateMessageRequest>().toList();
    expect(requests[1].operationId, isNot(requests[0].operationId));
    expect(requests[1].conferenceId, 'OTHER');
    expect(requests[1].inReplyTo, isEmpty);
  });
  testWidgets(
    'session change disposes draft and late send cannot change source',
    (t) async {
      await openReplySource(t, api);
      await replyTap(t, 'Ответить лично');
      final pending = Completer<wire.CreateMessageResponse>();
      api.create = (_) => pending.future;
      await t.tap(find.text('Отправить'));
      await t.pump();
      api.switchSession();
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      pending.complete(
        wire.CreateMessageResponse(
          message: wire.MessageReference(messageId: 'old#99'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('session change closes public-audience confirmation and draft', (
    t,
  ) async {
    await openReplySource(t, api);
    await replyTap(t, 'Ответить лично');
    await replyTap(t, 'Изменить область назначения');
    await replyTap(t, 'OTHER');
    expect(find.text('Опубликовать ответ в эхе?'), findsOneWidget);
    api.switchSession();
    await t.pumpAndSettle();
    expect(find.text('Опубликовать ответ в эхе?'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(t.takeException(), isNull);
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets('audience and target accessible at width $width', (t) async {
      t.view.physicalSize = Size(width, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await openReplySource(t, api);
      await replyTap(t, 'Ответить лично');
      expect(find.text('Netmail: MAIL'), findsOneWidget);
      expect(find.text('Источник: SOURCE (SOURCE)'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
