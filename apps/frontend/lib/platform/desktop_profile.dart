import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

class DesktopProfile {
  DesktopProfile(this.id) {
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,31}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid profile');
    }
  }
  final String id;
  static DesktopProfile current = DesktopProfile('default');
  static const channel = MethodChannel('ffido/desktop_profile');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  String get preferencesPrefix =>
      id == 'default' ? 'flutter.' : 'ffido_profile.$id.';
  String sessionKey(String endpoint) => id == 'default'
      ? 'ffido_session_v1:$endpoint'
      : 'ffido_profile_session_v1:$id:$endpoint';

  static Future<void> initialize() async {
    if (!supported) return;
    current = DesktopProfile(
      await channel.invokeMethod<String>('getProfile') ?? 'default',
    );
    SharedPreferences.setPrefix(current.preferencesPrefix);
  }

  static void observeIdentity(ApiClient client) {
    if (!supported) return;
    // Native calls are queued in the order of the auth transitions.
    Future<void> pending = Future.value();
    void update() {
      final profile = client.hasToken ? client.session?.profile : null;
      final fields = <String, String>{
        'name': profile?.name ?? '',
        'address': profile?.address ?? '',
      };
      pending = pending
          .then((_) => channel.invokeMethod<void>('setIdentity', fields))
          .catchError((Object error) {
            debugPrint('Window identity update failed: $error');
          });
    }

    client.identityChanges.listen((_) => update());
    update();
  }
}
