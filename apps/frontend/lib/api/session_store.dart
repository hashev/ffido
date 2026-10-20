import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import '../platform/desktop_profile.dart';
import 'api_exceptions.dart';
import 'generated/ffido/v1/ffido.pb.dart' as wire;

abstract interface class SessionStore {
  Future<String?> read(String endpoint);
  Future<void> write(String endpoint, String secret);
  Future<void> delete(String endpoint);
}

class SecureSessionStore implements SessionStore {
  const SecureSessionStore({this.profile});
  final DesktopProfile? profile;
  // macOS login Keychain supports local desktop builds without a provisioning
  // profile; secrets still stay in the OS Keychain, never preferences.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  String _key(String endpoint) =>
      (profile ?? DesktopProfile.current).sessionKey(endpoint);
  @override
  Future<String?> read(String endpoint) async =>
      kIsWeb ? null : _storage.read(key: _key(endpoint));
  @override
  Future<void> write(String endpoint, String secret) async {
    if (!kIsWeb) await _storage.write(key: _key(endpoint), value: secret);
  }

  @override
  Future<void> delete(String endpoint) async {
    if (!kIsWeb) await _storage.delete(key: _key(endpoint));
  }
}

class SessionManager {
  SessionManager(
    this.client,
    this.preferences, {
    this.store = const SecureSessionStore(),
  });
  final ApiClient client;
  final SharedPreferences preferences;
  final SessionStore store;
  String _disabled(String endpoint) => 'ffido_session_disabled:$endpoint';

  Future<void> restore() async {
    final endpoint = client.endpoint.toString();
    if (preferences.getBool(_disabled(endpoint)) == true) return;
    final secret = await store.read(endpoint);
    if (secret == null) return;
    try {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(secret)) {
        throw const UnauthorizedException();
      }
      await client.configure(endpoint: endpoint, token: secret);
      await client.restoreSession();
    } on UnauthorizedException {
      await preferences.setBool(_disabled(endpoint), true);
      await store.delete(endpoint);
      rethrow;
    } finally {
      if (client.session == null) await client.clearAuthToken();
    }
  }

  Future<String> connect({
    required String endpoint,
    required String name,
    required String address,
    required String password,
  }) async {
    final previous = client.endpoint.toString();
    final wire.LoginResponse result = await client.login(
      endpoint: endpoint,
      name: name,
      address: address,
      password: password,
    );
    final target = client.endpoint.toString();
    // A tombstone prevents an old secret from returning after a failed write/delete.
    await preferences.setBool(_disabled(target), true);
    await preferences.setString('ffido_endpoint_v1', target);
    await preferences.setString('ffido_name_v1', result.session.profile.name);
    await preferences.setString(
      'ffido_address_v1',
      result.session.profile.address,
    );
    if (previous != target) {
      await preferences.setBool(_disabled(previous), true);
      try {
        await store.delete(previous);
      } catch (_) {
        /* Tombstone remains. */
      }
    }
    try {
      await store.write(target, result.sessionSecret);
      await preferences.remove(_disabled(target));
      return kIsWeb
          ? 'Вы подключены. В браузере вход действует до закрытия приложения.'
          : 'Вы подключены. Вход сохранён на этом устройстве.';
    } catch (_) {
      return 'Вы подключены, но сохранить вход не удалось. После перезапуска введите пароль снова.';
    }
  }

  Future<String> logout() async {
    final endpoint = client.endpoint.toString();
    await preferences.setBool(_disabled(endpoint), true);
    var message = 'Вы вышли из сессии';
    try {
      await client.logout();
    } catch (_) {
      message =
          'Вы вышли на этом устройстве. Отозвать сессию на сервере не удалось.';
    } finally {
      await client.clearAuthToken();
    }
    try {
      await store.delete(endpoint);
    } catch (_) {
      message += ' Удалить запись из защищённого хранилища не удалось; автоматический вход отключён.';
    }
    return message;
  }
}
