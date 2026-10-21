// Test-only entry point. This file is never the release application's target.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/platform/desktop_profile.dart';
import 'package:fido/api/session_store.dart';
import 'package:fido/updates/update_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopProfile.initialize();
  final profile = DesktopProfile.current.id;
  final preferences = await SharedPreferences.getInstance();
  const build = String.fromEnvironment('FFIDO_QA_BUILD');
  final bundleID = await UpdateController.native.invokeMethod<String>(
    'testBundleID',
  );
  final endpoint = 'https://$bundleID.update-qa.invalid:8080';
  final secret = (profile == 'default' ? 'a' : 'b') * 64;
  const store = SecureSessionStore();
  if (build == 'A') {
    await preferences.setString('ffido_update_qa_saved', profile);
    await preferences.setString('ffido_endpoint_v1', endpoint);
    await preferences.setString('ffido_name_v1', 'QA $profile');
    await preferences.setString(
      'ffido_address_v1',
      profile == 'default' ? '2:1/2' : '2:1/3',
    );
    await store.write(endpoint, secret);
    if (await store.read(endpoint) != secret) {
      throw StateError('A could not read its own session');
    }
  }
  final preserved =
      preferences.getString('ffido_update_qa_saved') == profile &&
      preferences.getString('ffido_endpoint_v1') == endpoint &&
      preferences.getString('ffido_name_v1') == 'QA $profile' &&
      preferences.getString('ffido_address_v1') ==
          (profile == 'default' ? '2:1/2' : '2:1/3');
  final session = await UpdateController.native
      .invokeMapMethod<String, dynamic>('testKeychainRead', {
        'account': DesktopProfile.current.sessionKey(endpoint),
        'expected': secret,
      });
  final sessionFields = <String, dynamic>{
    'secureSession': session?['matches'] == true,
    'keychainStatus': session?['status'],
    'sessionWrittenAndReadByA': build == 'A',
  };
  String directory = '';
  UpdateController.native.setMethodCallHandler((call) async {
    if (call.method == 'canExit') {
      return profile != 'p2' || await File('$directory/allow').exists();
    }
    return null;
  });
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(child: Text('FFIDO update QA: $profile · $build')),
      ),
    ),
  );
  directory =
      await UpdateController.native.invokeMethod<String>('testMark', {
        ...sessionFields,
        'prefsOK': preserved,
        'status': 'ready',
      }) ??
      '';
  const feed = String.fromEnvironment('FFIDO_QA_FEED');
  if (feed.isEmpty || profile != 'default') return;
  Future<void> install() =>
      UpdateController.native.invokeMethod<void>('installMacOS', {
        'url': feed,
        'publicKey': const String.fromEnvironment('FFIDO_QA_KEY'),
        'version': '2',
        'packageURL': const String.fromEnvironment('FFIDO_QA_PACKAGE'),
      });
  try {
    await install();
  } catch (error) {
    await UpdateController.native.invokeMethod<String>('testMark', {
      ...sessionFields,
      'prefsOK': preserved,
      'status': 'blocked',
      'error': '$error',
      'errorCode': error is PlatformException && error.details is Map
          ? (error.details as Map)['code']
          : null,
    });
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (!await File('$directory/allow').exists()) {
      if (DateTime.now().isAfter(deadline)) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    try {
      await install();
    } catch (error) {
      await UpdateController.native.invokeMethod<String>('testMark', {
        ...sessionFields,
        'prefsOK': preserved,
        'status': 'failed',
        'error': '$error',
      });
    }
  }
}
