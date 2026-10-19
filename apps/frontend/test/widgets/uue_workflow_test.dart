import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/files/uue_files.dart';
import 'package:fido/models/uue.dart';
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/repositories/uue_repository.dart';
import 'package:fido/widgets/uue_body.dart';
import '../support/fake_transport.dart';

class Files extends UueFiles {
  SelectedUueFile? selected;
  bool cancel = false, fail = false, failPick = false;
  Uint8List? saved;
  String? name;
  @override
  Future<SelectedUueFile?> pick(int limit) async {
    if (failPick) throw uueFileLimit();
    return selected;
  }

  @override
  Future<bool> save(String filename, Uint8List bytes) async {
    if (fail) throw StateError('write');
    if (cancel) return false;
    saved = bytes;
    name = filename;
    return true;
  }
}

wire.UueLimits limits() => wire.UueLimits(
  maxFileBytes: Int64(1048576),
  partBodyBytes: 32768,
  maxParts: 128,
  chunkBytes: 65536,
  previewPixels: Int64(16000000),
  previewDimension: 8192,
);
wire.UuePart part(int number, {bool verified = false}) => wire.UuePart(
  source: wire.UuePartReference(
    message: wire.MessageReference(
      conferenceId: 'ECHO',
      messageId: 'g#$number',
    ),
  ),
  fromAddress: '2:1/2',
  subject: 'File [$number/2]',
  filename: 'file.bin',
  part: number,
  total: 2,
  date: '2026-10-19T10:00:00Z',
  transferId: verified ? 'id' : '',
  sha256: verified ? 'hash' : '',
);
void ready(FakeTransport api, Uint8List bytes, {String name = 'file.bin'}) {
  api.getUueLimitsHandler = (_) async => limits();
  api.assembleUueHandler = (_) async => wire.UueAttachment(
    id: 'attachment',
    filename: name,
    size: Int64(bytes.length),
    sha256: sha256.convert(bytes).toString(),
    state: wire.UueState.UUE_STATE_READY,
  );
  api.getUueChunkHandler = (r) async => wire.UueChunk(
    offset: r.offset,
    totalSize: Int64(bytes.length),
    data: bytes,
    eof: true,
  );
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  late FakeTransport api;
  late UueFiles oldFiles;
  late Files files;
  setUp(() {
    api = FakeTransport();
    oldFiles = uueFiles;
    files = Files();
    uueFiles = files;
  });
  tearDown(() async {
    uueFiles = oldFiles;
    await api.dispose();
  });
  testWidgets(
    'valid file selection clears previous picker error without losing draft',
    (tester) async {
      api.getUueLimitsHandler = (_) async => limits();
      api.messages = (_) async => wire.ListMessagesResponse();
      await tester.pumpWidget(
        MaterialApp(
          home: MessageScreen(
            conferenceId: 'ECHO',
            conferenceName: 'Эха',
            conferenceDescription: '',
            canRead: true,
            canPost: true,
            repository: MessageRepository(api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Новое сообщение'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(2), 'Тема черновика');
      await tester.enterText(fields.at(3), 'Текст черновика');
      files.failPick = true;
      await tap(tester, 'Прикрепить файл UUE');
      expect(
        find.text('Не удалось выбрать файл или превышен лимит сервера'),
        findsOneWidget,
      );
      files.failPick = false;
      // Cancelling does not report a successful selection or discard the error.
      await tap(tester, 'Прикрепить файл UUE');
      expect(
        find.text('Не удалось выбрать файл или превышен лимит сервера'),
        findsOneWidget,
      );
      files.selected = SelectedUueFile(
        'valid.bin',
        Uint8List.fromList([0, 255, 1]),
      );
      await tap(tester, 'Прикрепить файл UUE');
      expect(find.text('valid.bin'), findsOneWidget);
      expect(
        find.text('Не удалось выбрать файл или превышен лимит сервера'),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(fields.at(2)).controller!.text,
        'Тема черновика',
      );
      expect(
        tester.widget<TextField>(fields.at(3)).controller!.text,
        'Текст черновика',
      );
      expect(api.calls.whereType<wire.UploadUueChunkRequest>(), isEmpty);
    },
  );
  testWidgets(
    'legacy multipart assembles automatically with persistent warning and optional manual selection',
    (tester) async {
      final bytes = Uint8List.fromList([0, 255, 1]);
      ready(api, bytes);
      api.searchUuePartsHandler = (_) async => wire.SearchUuePartsResponse(
        generation: 'g',
        parts: [part(1), part(2)],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UueAttachmentCard(
              repository: UueRepository(api),
              part: UuePart.fromWire(part(1)),
              files: files,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        api.calls.whereType<wire.AssembleUueRequest>().single.explicitOrder,
        isFalse,
      );
      expect(find.text('Подтвердите части UUE'), findsNothing);
      expect(find.textContaining('возможно смешивание частей'), findsOneWidget);
      await tap(tester, 'Выбрать части');
      expect(find.text('Подтвердите части UUE'), findsOneWidget);
      await tap(tester, 'Отмена');
      expect(api.calls.whereType<wire.AssembleUueRequest>().length, 1);
      await tap(tester, 'Выбрать части');
      await tap(tester, 'Подтвердить и собрать');
      expect(
        api.calls.whereType<wire.AssembleUueRequest>().last.explicitOrder,
        isTrue,
      );
      expect(
        find.textContaining('Контрольная сумма отсутствует'),
        findsOneWidget,
      );
      expect(find.textContaining('возможно смешивание частей'), findsOneWidget);
      files.cancel = true;
      await tap(tester, 'Сохранить файл');
      expect(files.saved, isNull);
      expect(find.text('Файл передан для сохранения'), findsNothing);
      files.cancel = false;
      files.fail = true;
      await tap(tester, 'Сохранить файл');
      expect(find.text('Не удалось сохранить файл'), findsOneWidget);
      files.fail = false;
      await tap(tester, 'Сохранить файл');
      expect(files.saved, bytes);
      api.switchSession();
      await tester.pumpAndSettle();
      expect(find.text('file.bin'), findsNothing);
    },
  );
  testWidgets(
    'unnumbered fragments require manual order, never guessed automatically',
    (tester) async {
      final a = part(1)
        ..part = 1
        ..total = 1
        ..subject = 'Unnumbered';
      final b = part(2)
        ..part = 1
        ..total = 1
        ..subject = 'Unnumbered';
      ready(api, Uint8List.fromList([0, 255, 1]));
      api.searchUuePartsHandler = (_) async =>
          wire.SearchUuePartsResponse(generation: 'g', parts: [a, b]);
      api.assembleUueHandler = (r) async => r.sources.length == 1
          ? wire.UueAttachment(state: wire.UueState.UUE_STATE_INCOMPLETE)
          : wire.UueAttachment(
              state: wire.UueState.UUE_STATE_READY,
              id: 'attachment',
              filename: 'file.bin',
              size: Int64(3),
              sha256: sha256.convert([0, 255, 1]).toString(),
            );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UueAttachmentCard(
              repository: UueRepository(api),
              part: UuePart.fromWire(a),
              files: files,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        api.calls.whereType<wire.AssembleUueRequest>().single.sources.length,
        1,
      );
      await tap(tester, 'Выбрать части');
      expect(find.text('Подтвердите части UUE'), findsOneWidget);
      await tap(tester, 'Подтвердить и собрать');
      expect(
        api.calls.whereType<wire.AssembleUueRequest>().last.explicitOrder,
        isTrue,
      );
      expect(find.textContaining('возможно смешивание частей'), findsOneWidget);
    },
  );
  testWidgets(
    'image with binary extension has inline static preview and exact save bytes',
    (tester) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
      );
      ready(api, bytes, name: 'image.bin');
      final single = part(1);
      api.searchUuePartsHandler = (_) async => wire.SearchUuePartsResponse(
        generation: 'g',
        parts: [single, part(2)],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UueAttachmentCard(
              repository: UueRepository(api),
              part: UuePart.fromWire(single),
              files: files,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.textContaining('возможно смешивание частей'), findsOneWidget);
      expect(find.text('Подтвердите части UUE'), findsNothing);
      expect(find.bySemanticsLabel('Предпросмотр изображения'), findsOneWidget);
      await tap(tester, 'Сохранить файл');
      expect(files.saved, bytes);
      expect(files.name, 'image.bin');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'echo composer attaches file and resumes same frozen draft after partial send',
    (tester) async {
      api.getUueLimitsHandler = (_) async => limits();
      api.messages = (_) async => wire.ListMessagesResponse();
      files.selected = SelectedUueFile(
        'a.bin',
        Uint8List.fromList([0, 255, 1]),
      );
      var commits = 0;
      api.getUueSendStatusHandler = (_) async {
        if (commits == 0) throw const NotFoundException();
        return wire.UueSendStatus(
          state: 'partial',
          filename: 'a.bin',
          fileSize: Int64(3),
          sha256: sha256.convert(files.selected!.bytes).toString(),
        );
      };
      api.uploadUueChunkHandler = (r) async =>
          wire.UueUploadStatus(receivedBytes: r.fileSize, complete: true);
      api.commitUueHandler = (r) async {
        commits++;
        return wire.UueSendStatus(
          state: commits == 1 ? 'partial' : 'completed',
          savedParts: commits,
          totalParts: 2,
        );
      };
      await tester.pumpWidget(
        MaterialApp(
          home: MessageScreen(
            conferenceId: 'ECHO',
            conferenceName: 'Эха',
            conferenceDescription: '',
            canRead: true,
            canPost: true,
            repository: MessageRepository(api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Новое сообщение'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(2), 'Н тема');
      await tester.enterText(fields.at(3), 'Н текст');
      await tap(tester, 'Прикрепить файл UUE');
      expect(find.text('a.bin'), findsOneWidget);
      await tap(tester, 'Отправить');
      expect(find.textContaining('Сохранено частей: 1/2'), findsOneWidget);
      expect(tester.widget<TextField>(fields.at(3)).enabled, isFalse);
      await tap(tester, 'Повторить отправку');
      final sent = api.calls.whereType<wire.CommitUueRequest>().toList();
      expect(sent.length, 2);
      expect(sent[0].message.operationId, sent[1].message.operationId);
      expect(sent[1].message.body, 'Н текст');
      expect(api.calls.whereType<wire.UploadUueChunkRequest>().length, 1);
      expect(find.text('Сообщение сохранено локально'), findsOneWidget);
    },
  );
  testWidgets(
    'Netmail validates recipient before upload and keeps text and file',
    (tester) async {
      api.getUueLimitsHandler = (_) async => limits();
      api.messages = (_) async => wire.ListMessagesResponse();
      files.selected = SelectedUueFile(
        'private.bin',
        Uint8List.fromList([0, 255]),
      );
      api.getUueSendStatusHandler = (_) async =>
          throw const NotFoundException();
      api.uploadUueChunkHandler = (r) async =>
          wire.UueUploadStatus(receivedBytes: r.fileSize, complete: true);
      api.commitUueHandler = (_) async =>
          wire.UueSendStatus(state: 'completed', savedParts: 1, totalParts: 1);
      await tester.pumpWidget(
        MaterialApp(
          home: MessageScreen(
            conferenceId: 'NET',
            conferenceName: 'Личная почта',
            conferenceDescription: '',
            kind: AreaKind.netmail,
            canRead: true,
            canPost: true,
            repository: MessageRepository(api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Новое сообщение'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Point2');
      await tester.enterText(fields.at(1), 'invalid');
      await tester.enterText(fields.at(2), 'Private file');
      await tester.enterText(fields.at(3), 'Keep this text');
      await tap(tester, 'Прикрепить файл UUE');
      await tap(tester, 'Отправить');
      expect(api.calls.whereType<wire.UploadUueChunkRequest>(), isEmpty);
      expect(
        tester.widget<TextField>(fields.at(3)).controller!.text,
        'Keep this text',
      );
      expect(find.text('private.bin'), findsOneWidget);
      await tester.enterText(fields.at(1), '2:1/2.2');
      await tap(tester, 'Отправить');
      final sent = api.calls.whereType<wire.CommitUueRequest>().single.message;
      expect(sent.conferenceId, 'NET');
      expect(sent.toAddress, '2:1/2.2');
      expect(sent.body, 'Keep this text');
    },
  );
  testWidgets(
    'phone layout saves oversized and damaged images without preview',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [9000, 1]) {
        final bytes = Uint8List(24)
          ..setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10])
          ..setRange(12, 16, [73, 72, 68, 82]);
        ByteData.sublistView(bytes)
          ..setUint32(16, width)
          ..setUint32(20, 1);
        ready(api, bytes, name: 'broken.png');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UueAttachmentCard(
                key: ValueKey(width),
                repository: UueRepository(api),
                part: UuePart.fromWire(part(1)..total = 1),
                files: files,
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RawImage), findsNothing);
        await tap(tester, 'Сохранить файл');
        expect(files.saved, bytes);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'read-only area has no composer and UUE reply has no implicit file',
    (tester) async {
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: 'g#1', subject: 'File')],
      );
      api.message = (_) async => wire.Message(
        id: 'g#1',
        subject: 'File',
        fromName: 'Author',
        body: 'begin 644 x\n`\nend',
      );
      api.getUueLimitsHandler = (_) async => limits();
      api.searchUuePartsHandler = (_) async =>
          wire.SearchUuePartsResponse(generation: 'g');
      final repository = MessageRepository(api);
      Future<void> screen(bool canPost) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MessageScreen(
              key: ValueKey(canPost),
              conferenceId: 'ECHO',
              conferenceName: 'Эха',
              conferenceDescription: '',
              canRead: true,
              canPost: canPost,
              repository: repository,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await screen(false);
      expect(find.byTooltip('Новое сообщение'), findsNothing);
      await screen(true);
      await tap(tester, 'File');
      await tap(tester, 'Ответить в эху');
      expect(find.text('Прикрепить файл UUE'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(
        tester.widget<TextField>(fields.at(3)).controller!.text,
        contains('> begin 644 x'),
      );
      await tap(tester, 'Отправить');
      expect(api.calls.whereType<wire.CreateMessageRequest>().length, 1);
      expect(api.calls.whereType<wire.CommitUueRequest>(), isEmpty);
      expect(api.calls.whereType<wire.UploadUueChunkRequest>(), isEmpty);
    },
  );
  testWidgets(
    'later missing part is found across pages without reading other messages',
    (tester) async {
      final bytes = Uint8List.fromList([0, 255, 1]);
      ready(api, bytes);
      var arrived = false;
      api.searchUuePartsHandler = (r) async => r.afterNumber == 0
          ? wire.SearchUuePartsResponse(
              generation: 'g',
              parts: [part(1, verified: true)],
              hasMore: arrived,
              nextNumber: 100,
            )
          : wire.SearchUuePartsResponse(
              generation: 'g',
              parts: [part(2, verified: true)],
            );
      api.assembleUueHandler = (r) async => r.sources.length == 1
          ? wire.UueAttachment(
              state: wire.UueState.UUE_STATE_INCOMPLETE,
              missingParts: [2],
            )
          : wire.UueAttachment(
              id: 'attachment',
              filename: 'file.bin',
              size: Int64(3),
              sha256: sha256.convert(bytes).toString(),
              state: wire.UueState.UUE_STATE_READY,
              checksumVerified: true,
            );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UueAttachmentCard(
              repository: UueRepository(api),
              part: UuePart.fromWire(part(1, verified: true)),
              files: files,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Не хватает частей: 2'), findsOneWidget);
      arrived = true;
      await tap(tester, 'Найти части');
      expect(find.textContaining('SHA-256 проверен'), findsOneWidget);
      await tap(tester, 'Сохранить файл');
      expect(files.saved, bytes);
      expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
    },
  );
  testWidgets('animated GIF preview stays on its first frame', (tester) async {
    final bytes = Uint8List.fromList([
      ...'GIF89a'.codeUnits,
      1,
      0,
      1,
      0,
      128,
      0,
      0,
      0,
      0,
      0,
      255,
      255,
      255,
      33,
      249,
      4,
      0,
      1,
      0,
      0,
      0,
      44,
      0,
      0,
      0,
      0,
      1,
      0,
      1,
      0,
      0,
      2,
      2,
      68,
      1,
      0,
      33,
      249,
      4,
      0,
      1,
      0,
      0,
      0,
      44,
      0,
      0,
      0,
      0,
      1,
      0,
      1,
      0,
      0,
      2,
      2,
      76,
      1,
      0,
      59,
    ]);
    ready(api, bytes, name: 'animated.gif');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UueAttachmentCard(
            repository: UueRepository(api),
            part: UuePart.fromWire(part(1)..total = 1),
            files: files,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    final first = tester.widget<RawImage>(find.byType(RawImage)).image!;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(first));
    await tap(tester, 'Сохранить файл');
    expect(files.saved, bytes);
  });
}
