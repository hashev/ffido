import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:fido/platform/desktop_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/api/session_store.dart';

class MemoryStore implements SessionStore {
  final values = <String, String>{};
  bool failWrites = false, failDelete = false;
  @override
  Future<String?> read(String endpoint) async => values[endpoint];
  @override
  Future<void> write(String endpoint, String secret) async {
    if (failWrites) throw StateError('unavailable');
    values[endpoint] = secret;
  }

  @override
  Future<void> delete(String endpoint) async {
    if (failDelete) throw StateError('unavailable');
    values.remove(endpoint);
  }
}

class SessionClient extends ApiClient {
  ApiException? restoreFailure;
  bool offlineLogout = false;
  @override
  Future<wire.LoginResponse> login({
    required String endpoint,
    required String name,
    required String address,
    required String password,
  }) async {
    await configure(endpoint: endpoint, token: 'b' * 64);
    session = wire.SessionInfo(
      profile: wire.Profile(userId: 'A', name: name, address: address),
    );
    return wire.LoginResponse(sessionSecret: 'b' * 64, session: session);
  }

  @override
  Future<wire.SessionInfo> restoreSession() async {
    if (restoreFailure != null) throw restoreFailure!;
    return session = wire.SessionInfo(
      profile: wire.Profile(userId: 'A', name: 'Name', address: '2:1/2'),
    );
  }

  @override
  Future<void> logout() async {
    if (offlineLogout) throw const NetworkException();
    await clearAuthToken();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late MemoryStore store;
  late SessionClient client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = MemoryStore();
    client = SessionClient();
    store.values[client.endpoint.toString()] = 'a' * 64;
  });
  tearDown(() => client.dispose());
  test('restart restores secret for exactly its server', () async {
    await SessionManager(client, prefs, store: store).restore();
    expect(client.hasToken, isTrue);
    expect(client.session!.profile.userId, 'A');
    await client.configure(endpoint: 'https://another.invalid');
    await SessionManager(client, prefs, store: store).restore();
    expect(client.hasToken, isFalse);
  });
  test(
    'network error retains saved secret without claiming login succeeded',
    () async {
      client.restoreFailure = const NetworkException();
      await expectLater(
        SessionManager(client, prefs, store: store).restore(),
        throwsA(isA<NetworkException>()),
      );
      expect(client.hasToken, isFalse);
      expect(store.values, isNotEmpty);
    },
  );
  test('revoked session is removed and returns to login', () async {
    client.restoreFailure = const UnauthorizedException();
    await expectLater(
      SessionManager(client, prefs, store: store).restore(),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(client.hasToken, isFalse);
    expect(store.values, isEmpty);
  });
  test(
    'offline logout clears memory and prevents restoring an undeletable secret',
    () async {
      final manager = SessionManager(client, prefs, store: store);
      await manager.restore();
      client.offlineLogout = true;
      store.failDelete = true;
      final message = await manager.logout();
      expect(message, contains('Отозвать сессию на сервере не удалось'));
      expect(client.hasToken, isFalse);
      await manager.restore();
      expect(client.hasToken, isFalse);
    },
  );
  test(
    'failed secure write keeps current login without plaintext fallback or stale restoration',
    () async {
      store.failWrites = true;
      final manager = SessionManager(client, prefs, store: store);
      final result = await manager.connect(
        endpoint: client.endpoint.toString(),
        name: 'Name',
        address: '2:1/2',
        password: 'private-fixture',
      );
      expect(result, contains('сохранить вход не удалось'));
      expect(client.hasToken, isTrue);
      expect(
        prefs.getKeys().any(
          (key) => prefs.get(key).toString().contains('private-fixture'),
        ),
        isFalse,
      );
      await client.clearAuthToken();
      await manager.restore();
      expect(client.hasToken, isFalse);
    },
  );
  test('corrupt saved secret is rejected and removed', () async {
    store.values[client.endpoint.toString()] = 'damaged';
    await expectLater(
      SessionManager(client, prefs, store: store).restore(),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(client.hasToken, isFalse);
    expect(store.values, isEmpty);
  });
  test(
    'secure profile sessions isolate connect, restore, endpoint changes and logout',
    () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final secrets = <String, String>{};
      var failWrite = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final key = args['key'] as String;
            switch (call.method) {
              case 'write':
                if (failWrite) throw PlatformException(code: 'unavailable');
                secrets[key] = args['value'] as String;
                return null;
              case 'read':
                return secrets[key];
              case 'delete':
                secrets.remove(key);
                return null;
            }
            throw StateError('Unexpected secure storage operation');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final oneStore = SecureSessionStore(profile: DesktopProfile('point1'));
      final twoStore = SecureSessionStore(profile: DesktopProfile('point2'));
      final endpoint = client.endpoint.toString();
      await twoStore.write(endpoint, 'c' * 64);
      await const SecureSessionStore().write(endpoint, 'd' * 64);
      final manager = SessionManager(client, prefs, store: oneStore);
      await manager.connect(
        endpoint: endpoint,
        name: 'One',
        address: '2:1/2.1',
        password: 'not-stored',
      );
      expect(await oneStore.read(endpoint), 'b' * 64);
      await client.clearAuthToken();
      await manager.restore();
      expect(client.hasToken, isTrue);
      await manager.connect(
        endpoint: 'https://another.invalid',
        name: 'One',
        address: '2:1/2.1',
        password: 'not-stored',
      );
      expect(await oneStore.read(endpoint), isNull);
      expect(await twoStore.read(endpoint), 'c' * 64);
      await manager.logout();
      expect(await twoStore.read(endpoint), 'c' * 64);
      failWrite = true;
      final result = await manager.connect(
        endpoint: endpoint,
        name: 'One',
        address: '2:1/2.1',
        password: 'not-stored',
      );
      expect(result, contains('сохранить вход не удалось'));
      await client.clearAuthToken();
      await manager.restore();
      expect(client.hasToken, isFalse);
      failWrite = false;
      await manager.connect(
        endpoint: endpoint,
        name: 'One',
        address: '2:1/2.1',
        password: 'not-stored',
      );
      client.restoreFailure = const UnauthorizedException();
      await expectLater(
        manager.restore(),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(await oneStore.read(endpoint), isNull);
      expect(await twoStore.read(endpoint), 'c' * 64);
      expect(await const SecureSessionStore().read(endpoint), 'd' * 64);
      expect(secrets.values, isNot(contains('not-stored')));
    },
  );
}
