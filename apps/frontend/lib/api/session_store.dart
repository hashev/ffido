import 'dart:async';
import 'dart:convert';

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

// Managers from different screens share the client's storage ordering.
class _SessionOperations {
  int version = 0;
  Future<void> tail = Future.value();
  Future<T> run<T>(Future<T> Function() action) {
    final result = tail.then((_) => action());
    tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
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
  static final _byClient = Expando<_SessionOperations>();
  _SessionOperations get _operations =>
      _byClient[client] ??= _SessionOperations();
  void _check(int version, int epoch, int authentication) {
    if (client.isClosed ||
        version != _operations.version ||
        epoch != client.epoch ||
        authentication != client.authenticationVersion) {
      throw const CancelledException();
    }
  }

  String _disabled(String endpoint) => 'ffido_session_disabled:$endpoint';
  String _passwordKey(String endpoint) => 'password:$endpoint';
  String _passwordDisabled(String endpoint) =>
      'ffido_password_disabled:$endpoint';

  Future<String?> savedPassword(String endpoint, String address) async {
    if (kIsWeb || preferences.getBool(_passwordDisabled(endpoint)) == true) {
      return null;
    }
    final version = _operations.version;
    final epoch = client.epoch;
    final authentication = client.authenticationVersion;
    final value = await store.read(_passwordKey(endpoint));
    // Logout can finish while Keychain/Keystore is still answering this read.
    if (value == null ||
        client.isClosed ||
        version != _operations.version ||
        epoch != client.epoch ||
        authentication != client.authenticationVersion ||
        preferences.getBool(_passwordDisabled(endpoint)) == true) {
      return null;
    }
    try {
      final record = jsonDecode(value);
      if (record is Map &&
          record['address'] == address &&
          record['password'] is String) {
        return record['password'] as String;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> _forgetPassword(String endpoint) async {
    await preferences.setBool(_passwordDisabled(endpoint), true);
    await store.delete(_passwordKey(endpoint));
  }

  Future<void> restore() async {
    final version = ++_operations.version;
    var epoch = client.epoch;
    final authentication = client.authenticationVersion;
    final endpoint = client.endpoint.toString();
    if (preferences.getBool(_disabled(endpoint)) == true) return;
    final secret = await store.read(endpoint);
    _check(version, epoch, authentication);
    if (secret == null || preferences.getBool(_disabled(endpoint)) == true) {
      return;
    }
    try {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(secret)) {
        throw const UnauthorizedException();
      }
      final configured = client.configure(endpoint: endpoint, token: secret);
      epoch = client.epoch;
      await configured;
      _check(version, epoch, authentication);
      await client.restoreSession();
      _check(version, epoch, authentication);
    } on UnauthorizedException {
      _check(version, epoch, authentication);
      await _operations.run(() async {
        _check(version, epoch, authentication);
        await preferences.setBool(_disabled(endpoint), true);
        _check(version, epoch, authentication);
        await store.delete(endpoint);
      });
      rethrow;
    } finally {
      if (version == _operations.version &&
          epoch == client.epoch &&
          authentication == client.authenticationVersion &&
          !client.isClosed &&
          client.session == null) {
        await client.clearAuthToken();
      }
    }
  }

  Future<String> connect({
    required String endpoint,
    required String name,
    required String address,
    required String password,
  }) async {
    final version = ++_operations.version;
    final previous = client.endpoint.toString();
    final wire.LoginResponse result = await client.login(
      endpoint: endpoint,
      name: name,
      address: address,
      password: password,
    );
    final epoch = client.epoch;
    final authentication = client.authenticationVersion;
    final target = client.endpoint.toString();
    _check(version, epoch, authentication);
    return _operations.run(() async {
      void check() => _check(version, epoch, authentication);
      check();
      await preferences.setBool(_disabled(target), true);
      check();
      await preferences.setBool(_passwordDisabled(target), true);
      check();
      await preferences.setString('ffido_endpoint_v1', target);
      check();
      await preferences.setString('ffido_name_v1', result.session.profile.name);
      check();
      await preferences.setString(
        'ffido_address_v1',
        result.session.profile.address,
      );
      check();
      if (previous != target) {
        await preferences.setBool(_disabled(previous), true);
        check();
        try {
          await _forgetPassword(previous);
          check();
          await store.delete(previous);
          check();
        } on CancelledException {
          rethrow;
        } catch (_) {
          check();
        }
      }
      try {
        await store.write(target, result.sessionSecret);
        check();
        if (!kIsWeb) {
          await store.write(
            _passwordKey(target),
            jsonEncode({
              'address': result.session.profile.address,
              'password': password,
            }),
          );
          check();
          await preferences.remove(_passwordDisabled(target));
          check();
        }
        await preferences.remove(_disabled(target));
        check();
        return kIsWeb
            ? 'Вы подключены. В браузере вход действует до закрытия приложения.'
            : 'Вы подключены. Вход сохранён на этом устройстве.';
      } on CancelledException {
        rethrow;
      } catch (_) {
        check();
        return 'Вы подключены, но сохранить вход не удалось. После перезапуска введите пароль снова.';
      }
    });
  }

  Future<String> logout() async {
    ++_operations.version;
    final endpoint = client.endpoint.toString();
    // Start revocation/local invalidation before waiting for any slow store.
    final revoked = client.logout().then(
      (_) => true,
      onError: (Object _) => false,
    );
    final retired = client.hasToken
        ? client.clearAuthToken()
        : Future<void>.value();
    final tombstone = preferences.setBool(_disabled(endpoint), true);
    final passwordTombstone = preferences.setBool(
      _passwordDisabled(endpoint),
      true,
    );
    final cleaned = _operations
        .run(() async {
          await tombstone;
          await passwordTombstone;
          await preferences.setBool(_disabled(endpoint), true);
          await _forgetPassword(endpoint);
          await store.delete(endpoint);
        })
        .then((_) => true, onError: (Object _) => false);
    try {
      await retired;
    } on CancelledException {
      // A newer configure can supersede retirement after local invalidation.
    }
    final didRevoke = await revoked;
    final didClean = await cleaned;
    var message = didRevoke
        ? 'Вы вышли из сессии'
        : 'Вы вышли на этом устройстве. Отозвать сессию на сервере не удалось.';
    if (!didClean) message += ' Удалить запись из защищённого хранилища не удалось; автоматический вход отключён.';
    return message;
  }
}
