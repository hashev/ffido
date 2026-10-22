import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/main.dart' as app;
import 'package:fido/platform/desktop_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    test(
      'secure session failure permits login and preserves settings on $platform',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          DesktopProfile.channel,
          (call) async => call.method == 'getProfile' ? 'default' : null,
        );
        messenger.setMockMethodCallHandler(secure, (call) async {
          if (call.method == 'read') {
            throw PlatformException(
              code: 'auth-failed',
              message: 'QA Keychain access denied',
            );
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(DesktopProfile.channel, null);
          messenger.setMockMethodCallHandler(secure, null);
        });
        SharedPreferences.setMockInitialValues({
          'ffido_endpoint_v1': 'https://example.invalid:8080',
          'ffido_name_v1': 'Update QA',
          'ffido_address_v1': '2:5020/1.42',
        });
        await app.initializeApp();
        expect(app.apiClient.hasToken, isFalse);
        expect(app.startupMessage.toLowerCase(), contains('войдите снова'));
        expect(
          app.startupMessage.contains('Keychain'),
          platform == TargetPlatform.macOS,
        );
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString('ffido_name_v1'), 'Update QA');
        expect(preferences.getString('ffido_address_v1'), '2:5020/1.42');
        expect(
          preferences.getString('ffido_endpoint_v1'),
          'https://example.invalid:8080',
        );
      },
    );
  }
}
