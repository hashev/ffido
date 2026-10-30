import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/api/message_footer_snapshot.dart';
import 'package:fido/files/uue_files.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/templates/template_settings.dart';

import '../support/fake_transport.dart';

class FooterTransport extends FakeTransport implements MessageFooterSupport {
  @override
  bool get supportsMessageFooter => true;
}

class Files extends UueFiles {
  @override
  Future<SelectedUueFile?> pick(int limit) async =>
      SelectedUueFile('a.bin', Uint8List.fromList([0, 1, 2]));
  @override
  Future<bool> save(String name, Uint8List bytes) async => false;
}

Future<void> tap(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text).first);
  await t.tap(find.text(text).first);
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ffido_tagline_v1': 'My tagline',
      'ffido_origin_v1': 'My origin',
    });
    rootBundle.evict('assets/updates/identity.json');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'flutter/assets',
          (_) async => ByteData.sublistView(
            Uint8List.fromList(utf8.encode('{"version":"test"}')),
          ),
        );
  });
  Future<(FooterTransport, ConferenceRepository)> open(
    WidgetTester t, {
    bool forward = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await TemplateSettings(prefs).save(
      const TemplateBundle(
        '@forcesubj Шаблон\n@forceto Автор\n@cecho\n@forward@message\nПодпись @cfname',
      ),
    );
    final api = FooterTransport();
    addTearDown(api.dispose);
    api.getUueLimitsHandler = (_) async => wire.UueLimits(
      maxFileBytes: Int64(1024),
      partBodyBytes: 32768,
      maxParts: 10,
      chunkBytes: 65536,
      previewPixels: Int64(16000000),
      previewDimension: 8192,
    );
    wire.Conference echo(String id) => wire.Conference(
      id: id,
      name: id,
      canRead: true,
      canPost: true,
      kind: wire.AreaKind.AREA_KIND_ECHO,
    );
    api.conferences = (_) async => wire.ListConferencesResponse(
      conferences: [echo('RU.TARGET'), echo('RU.EXTRA')],
    );
    api.conference = (r) async => echo(r.conferenceId);
    api.messages = (_) async => wire.ListMessagesResponse(
      messages: [wire.Message(id: 'g#1', subject: 'Оригинал')],
    );
    api.message = (_) async => wire.Message(
      id: 'g#1',
      subject: 'Оригинал',
      fromName: 'Автор',
      fromAddress: '2:1/9',
      body: 'Исходное тело',
    );
    final conferences = ConferenceRepository(apiClient: api, prefs: prefs);
    addTearDown(conferences.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: MessageScreen(
          conferenceId: 'RU.SOURCE',
          conferenceName: 'RU.SOURCE',
          conferenceDescription: '',
          canRead: true,
          canPost: true,
          repository: MessageRepository(api),
          conferences: conferences,
        ),
      ),
    );
    await t.pumpAndSettle();
    if (forward) {
      await tap(t, 'Оригинал');
      await tap(t, 'Переслать');
      await tap(t, 'RU.TARGET');
    } else {
      await t.tap(find.byTooltip('Новое сообщение'));
      await t.pumpAndSettle();
    }
    return (api, conferences);
  }

  testWidgets(
    'forward and crosspost keep generated snapshot after destination change',
    (t) async {
      final (api, _) = await open(t, forward: true);
      final body = t
          .widget<TextField>(find.widgetWithText(TextField, 'Текст'))
          .controller!;
      final initial = body.text;
      expect(initial, startsWith('RU.TARGET\nИсходное тело\n'));
      body.text = '$initial\nПравка';
      await tap(t, 'Изменить эху назначения');
      await tap(t, 'RU.EXTRA');
      expect(body.text, '$initial\nПравка');
      await t.tap(find.byTooltip('Дополнительно'));
      await t.pumpAndSettle();
      await tap(t, 'Кросспостинг');
      await t.tap(find.text('RU.TARGET').first);
      await tap(t, 'Готово');
      await tap(t, 'Отправить');
      final sent = api.calls.whereType<wire.CreateCrosspostRequest>().single;
      expect(sent.message.body, '$initial\nПравка');
      expect(sent.message.subject, 'Шаблон');
      expect(sent.message.toName, 'Автор');
      expect(sent.message.inReplyTo, '');
      expect(sent.message.conferenceId, 'RU.EXTRA');
      expect(sent.additionalConferenceIds, ['RU.TARGET']);
      expect(sent.message.footer.tagline, 'My tagline');
      expect(sent.message.footer.origin, 'My origin');
    },
  );
  testWidgets(
    'UUE receives generated fields and freezes footer and body on retry',
    (t) async {
      final (api, _) = await open(t);
      final previous = uueFiles;
      uueFiles = Files();
      addTearDown(() => uueFiles = previous);
      api.getUueLimitsHandler = (_) async => wire.UueLimits(
        maxFileBytes: Int64(1024),
        partBodyBytes: 32768,
        maxParts: 10,
        chunkBytes: 65536,
        previewPixels: Int64(16000000),
        previewDimension: 8192,
      );
      // Refresh the limits, which were unavailable when the editor opened.

      api.getUueSendStatusHandler = (_) async =>
          throw const NotFoundException();
      api.uploadUueChunkHandler = (r) async =>
          wire.UueUploadStatus(receivedBytes: r.fileSize, complete: true);
      api.commitUueHandler = (_) async =>
          wire.UueSendStatus(state: 'partial', savedParts: 1, totalParts: 2);
      final body = t
          .widget<TextField>(find.widgetWithText(TextField, 'Текст'))
          .controller!
          .text;
      await tap(t, 'Прикрепить файл UUE');
      await tap(t, 'Отправить');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ffido_tagline_v1', 'Changed');
      await tap(t, 'Повторить отправку');
      final sent = api.calls.whereType<wire.CommitUueRequest>().toList();
      expect(sent.length, 2);
      expect(sent[0].message.body, body);
      expect(sent[1].message.body, body);
      expect(sent[0].message.subject, 'Шаблон');
      expect(sent[0].message.toName, 'Автор');
      expect(sent[0].message.footer.tagline, 'My tagline');
      expect(sent[1].message.footer.tagline, 'My tagline');
      expect(sent[0].message.operationId, sent[1].message.operationId);
    },
  );
}
