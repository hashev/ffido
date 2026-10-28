import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:fido/repositories/uue_repository.dart';
import 'package:fido/files/uue_file_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/message_footer.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';

class FooterTransport extends FakeTransport implements MessageFooterSupport {
  @override
  bool supportsMessageFooter = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('automatic version follows upgrade, overrides survive, blank and reset restore defaults', () async {
    final prefs = await SharedPreferences.getInstance();
    final a = MessageFooterSettings(prefs, '1.0.4');
    expect(a.tagline, 'FFIDO 1.0.4');
    expect(a.origin, MessageFooterSettings.defaultOrigin);
    final b = MessageFooterSettings(prefs, '1.0.5');
    expect(b.tagline, 'FFIDO 1.0.5');
    await a.save('Custom', 'Мой сайт');
    expect(b.tagline, 'Custom');
    expect(b.origin, 'Мой сайт');
    await b.save('', 'Custom origin');
    expect(b.tagline, 'FFIDO 1.0.5');
    await b.reset();
    expect(b.hasOverrides, isFalse);
  });
  test('validation rejects controls, invalid Unicode and UTF-8 byte overflow without replacing saved values', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = MessageFooterSettings(prefs, '1.0.5');
    await settings.save('Saved', 'Origin');
    for (final value in [
      'x\ny',
      'x\ry',
      'x\u0000y',
      'x\u0001y',
      'x\u007fy',
      'я' * 129,
      '\uD800',
    ]) {
      await expectLater(
        settings.save(value, 'Origin'),
        throwsA(isA<ValidationException>()),
      );
      expect(settings.tagline, 'Saved');
    }
    await settings.save('я' * 128, 'Origin');
    expect(settings.tagline, 'я' * 128);
  });
  test('operation snapshot survives a settings change; a new operation uses new values', () async {
    final api = FooterTransport();
    addTearDown(api.dispose);
    final settings = await MessageFooterSettings.load();
    await settings.save('A', 'Origin A');
    final requests = <wire.CreateMessageRequest>[];
    api.create = (request) async {
      requests.add(request);
      return wire.CreateMessageResponse(
        message: wire.MessageReference(messageId: 'g#42'),
        status: wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
      );
    };
    final repository = MessageRepository(api);
    Future<void> send(String operation) => repository.sendMessage(
      conferenceId: 'echo',
      toName: 'All',
      toAddress: '',
      subject: 'Test',
      body: 'Body',
      operationId: operation,
    );
    await send('same');
    await settings.save('B', 'Origin B');
    await send('same');
    await send('new');
    expect(requests.map((r) => r.footer.tagline), ['A', 'A', 'B']);
  });
  test('crosspost snapshots retain footer for partial continuation', () async {
    final api = FooterTransport();
    addTearDown(api.dispose);
    final settings = await MessageFooterSettings.load();
    await settings.save('Group A', 'Origin');
    final seen = <String>[];
    api.crosspost = (request) async {
      seen.add(request.message.footer.tagline);
      return wire.CreateCrosspostResponse(total: 2, complete: false);
    };
    final repo = MessageRepository(api);
    Future<void> send() => repo.sendCrosspost(
      conferenceId: 'echo',
      additionalConferenceIds: ['other'],
      operationId: 'group',
      toName: 'All',
      toAddress: '',
      subject: 'Subject',
      body: 'Body',
    );
    await send();
    await settings.save('Group B', 'Changed');
    await send();
    expect(seen, ['Group A', 'Group A']);
  });

  test(
    'preference prefixes keep footer overrides isolated between profiles',
    () async {
      SharedPreferences.resetStatic();
      addTearDown(SharedPreferences.resetStatic);
      SharedPreferences.setPrefix('ffido_profile.one.');
      final one = MessageFooterSettings(
        await SharedPreferences.getInstance(),
        '1.0.5',
      );
      await one.save('One', 'Origin one');
      SharedPreferences.resetStatic();
      SharedPreferences.setPrefix('ffido_profile.two.');
      final two = MessageFooterSettings(
        await SharedPreferences.getInstance(),
        '1.0.5',
      );
      expect(two.hasOverrides, isFalse);
      await two.save('Two', 'Origin two');
      SharedPreferences.resetStatic();
      SharedPreferences.setPrefix('ffido_profile.one.');
      final restored = MessageFooterSettings(
        await SharedPreferences.getInstance(),
        '1.0.6',
      );
      expect(restored.tagline, 'One');
      expect(restored.origin, 'Origin one');
    },
  );

  test(
    'UUE partial continuation retains the original footer snapshot',
    () async {
      final api = FooterTransport();
      addTearDown(api.dispose);
      api.getUueLimitsHandler = (_) async => wire.UueLimits(
        maxFileBytes: Int64(1048576),
        partBodyBytes: 32768,
        maxParts: 128,
        chunkBytes: 65536,
        previewPixels: Int64(16000000),
        previewDimension: 8192,
      );
      api.getUueSendStatusHandler = (_) async =>
          throw const NotFoundException();
      api.uploadUueChunkHandler = (r) async => wire.UueUploadStatus(
        receivedBytes: Int64(r.data.length),
        complete: true,
      );
      final seen = <String>[];
      api.commitUueHandler = (r) async {
        seen.add(r.message.footer.tagline);
        return wire.UueSendStatus(
          operationId: 'uue',
          state: 'partial',
          totalParts: 2,
          savedParts: 1,
        );
      };
      final settings = await MessageFooterSettings.load();
      await settings.save('File A', 'Origin');
      final repo = UueRepository(api);
      final draft = UueDraft(
        conference: 'echo',
        operation: 'uue',
        subject: 'File',
        body: 'Body',
        toName: 'All',
        toAddress: '',
        file: SelectedUueFile('file.bin', Uint8List.fromList([1, 2, 3])),
      );
      await repo.send(draft);
      await settings.save('File B', 'Changed');
      await repo.send(draft);
      expect(seen, ['File A', 'File A']);
    },
  );

  test('legacy server refuses overrides before RPC; reset permits legacy and netmail bypasses footer', () async {
    final api = FooterTransport()..supportsMessageFooter = false;
    addTearDown(api.dispose);
    final snapshots = MessageFooterSnapshots(api);
    final settings = await MessageFooterSettings.load();
    await settings.save('Custom', 'Origin');
    await expectLater(
      snapshots.capture('same'),
      throwsA(isA<ValidationException>()),
    );
    expect(await snapshots.capture('netmail', enabled: false), isNull);
    await settings.reset();
    expect(await snapshots.capture('same'), isNull);
    api.switchSession();
    api.supportsMessageFooter = true;
    expect((await snapshots.capture('same'))!.tagline, startsWith('FFIDO '));
  });
}
