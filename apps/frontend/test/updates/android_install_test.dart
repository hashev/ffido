import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/updates/android_install_result.dart';
import 'package:fido/updates/update_controller.dart';
import 'package:fido/updates/update_metadata.dart';
import 'package:fido/updates/update_ui.dart';

import 'update_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UpdateFixture fixture;
  late UpdateController controller;
  Object? recovered;
  var installs = 0;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const saved = {
    'target': 'v1.0.1',
    'target_build': 1002,
    'sha256':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'source':
        'https://github.com/hashev/ffido/releases/download/v1.0.1/client.apk',
    'token': 'private-session-token',
    'path': '/private/user/cache/update.apk',
  };
  setUp(() async {
    recovered = null;
    installs = 0;
    SharedPreferences.setMockInitialValues({
      'ffido_android_diagnostic_v1': jsonEncode(saved),
    });
    fixture = UpdateFixture();
    await fixture.initialize();
    messenger.setMockMethodCallHandler(UpdateController.native, (call) async {
      if (call.method == 'recover') return recovered;
      if (call.method == 'install') installs++;
      return null;
    });
    controller = UpdateController(
      service: fixture.service(
        platform: UpdatePlatform('android', 'universal', [36]),
      ),
      preferences: await SharedPreferences.getInstance(),
    );
  });
  tearDown(() {
    controller.dispose();
    messenger.setMockMethodCallHandler(UpdateController.native, null);
  });

  test(
    'resume does not replace an active download with an old installer result',
    () async {
      controller.phase = UpdatePhase.downloading;
      recovered = {'outcome': 'blocked', 'status': 2};
      await controller.resume();
      expect(controller.phase, UpdatePhase.downloading);
      expect(controller.installResult, isNull);
      expect(installs, 0);
    },
  );

  test('installer parser rejects unknown and malformed outcomes', () {
    for (final value in [
      true,
      null,
      {'outcome': 'virus'},
      {'outcome': 'failed', 'status': '/private/path'},
    ]) {
      expect(() => AndroidInstallResult.parse(value), throwsFormatException);
    }
  });

  for (final outcome in [
    'blocked',
    'cancelled',
    'permission_denied',
    'failed',
    'unknown',
  ]) {
    test(
      'recover $outcome exits waiting without automatic reinstall or diagnosis',
      () async {
        await controller.start();
        controller.phase = UpdatePhase.installing;
        recovered = {
          'outcome': outcome,
          'status': outcome == 'unknown' ? null : 2,
        };
        await controller.resume();
        expect(controller.busy, isFalse);
        expect(controller.installResult!.outcome, outcome);
        expect(controller.message, isNot(contains('Play Protect')));
        expect(controller.message, isNot(contains('отключ')));
        expect(installs, 0);
        final summary = jsonDecode(controller.diagnosticSummary) as Map;
        expect(summary['target'], saved['target']);
        expect(summary['sha256'], saved['sha256']);
        expect(summary['outcome'], outcome);
        expect(
          controller.diagnosticSummary,
          isNot(contains('private-session-token')),
        );
        expect(controller.diagnosticSummary, isNot(contains('/private/')));
      },
    );
  }

  test(
    'pending session stays pending, then native callback releases waiting',
    () async {
      recovered = {'outcome': 'pending', 'status': null};
      await controller.start();
      expect(controller.busy, isTrue);
      final done = messenger.handlePlatformMessage(
        UpdateController.native.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('installResult', {
            'outcome': 'blocked',
            'status': 2,
          }),
        ),
        (_) {},
      );
      await done;
      expect(controller.busy, isFalse);
      expect(controller.message, contains('Android запретил'));
      expect(jsonDecode(controller.diagnosticSummary)['android_status'], 2);
      expect(installs, 0);
    },
  );

  test(
    'platform exception preserves bounded result and public target context',
    () async {
      final updates = UpdateController(
        service: controller.service,
        preferences: controller.preferences,
        installer: (update, progress) async => throw PlatformException(
          code: 'install',
          message: 'private raw error',
          details: {'outcome': 'failed', 'status': 1, 'token': 'secret'},
        ),
      );
      addTearDown(updates.dispose);
      updates.available = fixture.available;
      await updates.install();
      expect(updates.busy, isFalse);
      expect(updates.installResult!.status, 1);
      expect(updates.message, isNot(contains('private raw error')));
      expect(
        jsonDecode(updates.diagnosticSummary)['target'],
        fixture.available.manifest.identity.tag,
      );
      expect(updates.diagnosticSummary, isNot(contains('secret')));
    },
  );

  testWidgets('diagnostic is revealed only by an explicit action', (
    tester,
  ) async {
    await tester.runAsync(controller.start);
    await tester.pumpWidget(
      MaterialApp(home: UpdateScreen(controller: controller)),
    );
    expect(find.textContaining('private-session-token'), findsNothing);
    expect(find.textContaining('aaaaaaaaaaaa'), findsNothing);
    await tester.tap(find.text('Диагностика обновления'));
    await tester.pumpAndSettle();
    expect(find.textContaining('aaaaaaaaaaaa'), findsOneWidget);
    expect(find.textContaining('private-session-token'), findsNothing);
    expect(find.textContaining('/private/'), findsNothing);
  });
}
