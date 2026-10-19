import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/platform/desktop_profile.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    DesktopProfile.current = DesktopProfile('default');
    SharedPreferences.resetStatic();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopProfile.channel, null);
  });
  test('profile IDs and session namespaces preserve legacy', () {
    expect(
      DesktopProfile('default').sessionKey('https://server'),
      'ffido_session_v1:https://server',
    );
    expect(
      DesktopProfile('point1').sessionKey('https://server'),
      isNot(DesktopProfile('point2').sessionKey('https://server')),
    );
    for (final id in ['', '../x', 'Upper', 'a\n', 'a' * 33]) {
      expect(() => DesktopProfile(id), throwsArgumentError);
    }
  });
  test(
    'bootstrap selects prefix before preferences and isolates all keys',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      SharedPreferences.setPrefix('');
      SharedPreferences.setMockInitialValues({
        'flutter.ffido_name_v1': 'Legacy',
        'ffido_profile.point1.ffido_name_v1': 'One',
        'ffido_profile.point2.ffido_name_v1': 'Two',
        'ffido_profile.point2.ffido-conferences-v2:cache': 'private',
      });
      SharedPreferences.resetStatic();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            DesktopProfile.channel,
            (call) async => 'point1',
          );
      await DesktopProfile.initialize();
      final one = await SharedPreferences.getInstance();
      expect(one.getString('ffido_name_v1'), 'One');
      expect(one.getKeys(), {'ffido_name_v1'});
      await one.setString('ffido_endpoint_v1', 'https://one');
      await one.clear();
      SharedPreferences.resetStatic();
      SharedPreferences.setPrefix(DesktopProfile('point2').preferencesPrefix);
      final two = await SharedPreferences.getInstance();
      expect(two.getString('ffido_name_v1'), 'Two');
      expect(two.getString('ffido-conferences-v2:cache'), 'private');
      SharedPreferences.resetStatic();
      final legacy = await SharedPreferences.getInstance();
      expect(legacy.getString('ffido_name_v1'), 'Legacy');
      expect(legacy.getKeys(), {'ffido_name_v1'});
      SharedPreferences.resetStatic();
      SharedPreferences.setPrefix(DesktopProfile('new').preferencesPrefix);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );
  test(
    'title bridge observes identity after epoch, clears on logout and disposal',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DesktopProfile.channel, (call) async {
            calls.add(call);
            return null;
          });
      final client = ApiClient();
      DesktopProfile.observeIdentity(client);
      await client.configure(endpoint: 'https://server', token: 'a' * 64);
      client.session = wire.SessionInfo(
        profile: wire.Profile(name: 'One', address: '2:1/2.1'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.arguments, {'name': 'One', 'address': '2:1/2.1'});
      expect(calls.toString(), isNot(contains('a' * 64)));
      await client.clearAuthToken();
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.arguments, {'name': '', 'address': ''});
      await client.dispose();
    },
  );
  test('other platforms do not call native profile bridge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = ApiClient();
    await DesktopProfile.initialize();
    DesktopProfile.observeIdentity(client);
    await client.dispose();
    expect(DesktopProfile.current.id, 'default');
  });
}
