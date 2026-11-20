@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/message.dart';
import 'package:fido/files/uue_files.dart';
import 'package:fido/repositories/web_draft_store.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

class DraftFiles extends UueFiles {
  @override
  Future<SelectedUueFile?> pick(int maxBytes) async =>
      SelectedUueFile('draft.txt', Uint8List.fromList([65, 66, 67]));

  @override
  Future<UueSaveResult> save(String name, Uint8List bytes) =>
      throw UnimplementedError();
}

void main() {
  for (final removeFile in [false, true]) {
    testWidgets(
      'file ${removeFile ? 'removal' : 'selection'} persists without text edits and survives draft restore',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = WebDraftStore(
          readValue: prefs.getString,
          listKeys: prefs.getKeys,
          writeValue: prefs.setString,
          removeValue: prefs.remove,
        )..scope = 'profile';
        final previousStore = WebDraftStore.active;
        final previousFiles = uueFiles;
        WebDraftStore.active = store;
        uueFiles = DraftFiles();
        addTearDown(() {
          WebDraftStore.active = previousStore;
          uueFiles = previousFiles;
        });
        final api = FakeTransport();
        api.getUueLimitsHandler = (_) async => wire.UueLimits(
          maxFileBytes: Int64(1048576),
          partBodyBytes: 32768,
          maxParts: 128,
          chunkBytes: 65536,
          previewPixels: Int64(16000000),
          previewDimension: 8192,
        );
        final messages = MessageRepository(api);
        final conferences = ConferenceRepository(apiClient: api, prefs: prefs);
        addTearDown(conferences.dispose);
        addTearDown(api.dispose);
        final record = <String, dynamic>{
          'draftId': 'compose:attachment',
          'operationId': 'before-selection',
          'conferenceId': 'ECHO',
          'conferenceName': 'ECHO',
          'kind': 0,
          'forward': false,
          'toName': 'All',
          'toAddress': '',
          'subject': 'Saved subject',
          'body': 'Saved body',
          'uncertain': false,
          'hadAttachment': false,
        };
        await store.write('profile', record['draftId'] as String, record);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => openWebDraft(
                  context,
                  store.list('profile').single,
                  messages,
                  conferences,
                ),
                child: const Text('Restore'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Прикрепить файл UUE'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Прикрепить файл UUE'));
        await tester.pumpAndSettle();
        expect(find.text('draft.txt'), findsOneWidget);
        expect(store.list('profile').single['hadAttachment'], isTrue);
        final selectedOperation = store.list('profile').single['operationId'];
        expect(selectedOperation, isNot('before-selection'));
        if (removeFile) {
          await tester.ensureVisible(find.byTooltip('Убрать файл'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Убрать файл'));
          await tester.pumpAndSettle();
          expect(find.text('draft.txt'), findsNothing);
          expect(store.list('profile').single['hadAttachment'], isFalse);
          expect(
            store.list('profile').single['operationId'],
            isNot(selectedOperation),
          );
        }
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restore'));
        await tester.pumpAndSettle();
        final values = tester
            .widgetList<EditableText>(find.byType(EditableText))
            .map((widget) => widget.controller.text)
            .toList();
        expect(values, containsAll(['Saved subject', 'Saved body']));
        expect(
          find.textContaining('Файл не сохраняется на устройстве'),
          removeFile ? findsNothing : findsOneWidget,
        );
        if (!removeFile) {
          await tester.ensureVisible(find.text('Отправить').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Отправить').first);
          await tester.pumpAndSettle();
          expect(find.textContaining('выберите вложение заново'), findsWidgets);
        }
        expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
        expect(api.calls.whereType<wire.UploadUueChunkRequest>(), isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'restored reply retains text and recipient and never sends a missing attachment',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final api = FakeTransport();
      final messages = MessageRepository(api);
      final conferences = ConferenceRepository(apiClient: api, prefs: prefs);
      final original = Message(
        id: 'g#1',
        fromName: 'Author',
        fromAddress: '2:1/1.2',
        toName: 'All',
        toAddress: '',
        subject: 'Original',
        body: 'Original body',
        date: DateTime.utc(2026),
      );
      final record = <String, dynamic>{
        'draftId': 'compose:old',
        'operationId': 'old',
        'conferenceId': 'ECHO',
        'conferenceName': 'ECHO',
        'kind': 0,
        'original': original.toJson(),
        'forward': false,
        'toName': 'Saved recipient',
        'toAddress': '2:1/1.3',
        'subject': 'Saved subject',
        'body': 'Saved reply body',
        'uncertain': false,
        'hadAttachment': true,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openWebDraft(context, record, messages, conferences),
              child: const Text('Restore'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      final values = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((w) => w.controller.text)
          .toList();
      expect(
        values,
        containsAll([
          'Saved recipient',
          '2:1/1.3',
          'Saved subject',
          'Saved reply body',
        ]),
      );
      await tester.tap(find.text('Отправить').first);
      await tester.pumpAndSettle();
      expect(api.calls.whereType<wire.CreateMessageRequest>(), isEmpty);
      expect(find.textContaining('выберите вложение заново'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await api.dispose();
    },
  );
}
