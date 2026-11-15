import 'dart:async';

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
  Future<String?> Function(String)? onRead;
  Future<void> Function(String)? onWrite;
  @override
  Future<String?> read(String endpoint) async =>
      onRead == null ? values[endpoint] : await onRead!(endpoint);
  @override
  Future<void> write(String endpoint, String secret) async {
    await onWrite?.call(endpoint);
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
  test(
    'late restore cannot undo offline logout from another manager',
    () async {
      final read = Completer<String?>();
      store.onRead = (_) => read.future;
      final pending = SessionManager(client, prefs, store: store).restore();
      final cancelled = expectLater(
        pending,
        throwsA(isA<CancelledException>()),
      );
      client.offlineLogout = true;
      await SessionManager(client, prefs, store: store).logout();
      read.complete('a' * 64);
      await cancelled;
      expect(client.hasToken, isFalse);
      expect(client.session, isNull);
    },
  );
  test(
    'late write cannot enable restoration after logout, queue recovers',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      store.onWrite = (_) async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final old = SessionManager(client, prefs, store: store).connect(
        endpoint: client.endpoint.toString(),
        name: 'Old',
        address: '2:1/2',
        password: 'old',
      );
      final cancelled = expectLater(old, throwsA(isA<CancelledException>()));
      await entered.future;
      client.offlineLogout = true;
      final logout = SessionManager(client, prefs, store: store).logout();
      expect(client.hasToken, isFalse);
      release.complete();
      await logout;
      await cancelled;
      final endpoint = client.endpoint.toString();
      expect(store.values[endpoint], isNull);
      expect(prefs.getBool('ffido_session_disabled:$endpoint'), isTrue);
      expect(
        await SessionManager(
          client,
          prefs,
          store: store,
        ).savedPassword(endpoint, '2:1/2'),
        isNull,
      );
      await SessionManager(client, prefs, store: store).connect(
        endpoint: endpoint,
        name: 'New',
        address: '2:1/3',
        password: 'new',
      );
      expect(client.session!.profile.name, 'New');
      expect(prefs.getBool('ffido_session_disabled:$endpoint'), isNull);
      expect(
        await SessionManager(
          client,
          prefs,
          store: store,
        ).savedPassword(endpoint, '2:1/3'),
        'new',
      );
    },
  );
  for (final endpoint in ['same', 'other']) {
    test(
      'connect logout connect preserves newest storage on $endpoint server',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        store.onWrite = (_) async {
          if (!entered.isCompleted) {
            entered.complete();
            await release.future;
          }
        };
        final oldEndpoint = client.endpoint.toString();
        final old = SessionManager(client, prefs, store: store).connect(
          endpoint: oldEndpoint,
          name: 'Old',
          address: '2:1/2',
          password: 'old',
        );
        final cancelled = expectLater(old, throwsA(isA<CancelledException>()));
        await entered.future;
        client.offlineLogout = true;
        final logout = SessionManager(client, prefs, store: store).logout();
        final target = endpoint == 'same' ? oldEndpoint : 'https://new.invalid';
        final newest = SessionManager(client, prefs, store: store).connect(
          endpoint: target,
          name: 'New',
          address: '2:1/3',
          password: 'new',
        );
        release.complete();
        await cancelled;
        await logout;
        await newest;
        expect(client.session!.profile.address, '2:1/3');
        expect(client.hasToken, isTrue);
        expect(
          await SessionManager(
            client,
            prefs,
            store: store,
          ).savedPassword(target, '2:1/3'),
          'new',
        );
        if (target != oldEndpoint) {
          expect(store.values[oldEndpoint], isNull);
          expect(prefs.getBool('ffido_session_disabled:$oldEndpoint'), isTrue);
        }
      },
    );
  }
  for (final change in ['endpoint', 'dispose', 'clear']) {
    test('pending secret read is discarded on $change', () async {
      final read = Completer<String?>();
      store.onRead = (_) => read.future;
      final pending = SessionManager(client, prefs, store: store).restore();
      final cancelled = expectLater(
        pending,
        throwsA(isA<CancelledException>()),
      );
      if (change == 'endpoint') {
        await client.configure(endpoint: 'https://other.invalid');
      }
      if (change == 'dispose') await client.dispose();
      if (change == 'clear') await client.clearAuthToken();
      read.complete('a' * 64);
      await cancelled;
      expect(client.hasToken, isFalse);
    });
  }
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
  test('failed secure write keeps current login without plaintext fallback or stale restoration', () async {
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
  });
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
    'password survives restart and expired session only in secure storage',
    () async {
      final manager = SessionManager(client, prefs, store: store);
      final endpoint = client.endpoint.toString();
      await manager.connect(
        endpoint: endpoint,
        name: 'Name',
        address: '2:1/2',
        password: 'remember-me',
      );
      expect(await manager.savedPassword(endpoint, '2:1/2'), 'remember-me');
      expect(await manager.savedPassword(endpoint, '2:1/3'), isNull);
      expect(
        await manager.savedPassword('https://other.invalid', '2:1/2'),
        isNull,
      );
      expect(
        prefs.getKeys().any(
          (key) => prefs.get(key).toString().contains('remember-me'),
        ),
        isFalse,
      );
      client.restoreFailure = const UnauthorizedException();
      await expectLater(
        manager.restore(),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(await manager.savedPassword(endpoint, '2:1/2'), 'remember-me');
      await manager.logout();
      expect(await manager.savedPassword(endpoint, '2:1/2'), isNull);
      expect(store.values, isEmpty);
    },
  );
  test(
    'failed deletion cannot restore a saved password after logout',
    () async {
      final manager = SessionManager(client, prefs, store: store);
      final endpoint = client.endpoint.toString();
      await manager.connect(
        endpoint: endpoint,
        name: 'Name',
        address: '2:1/2',
        password: 'remember-me',
      );
      store.failDelete = true;
      await manager.logout();
      expect(await manager.savedPassword(endpoint, '2:1/2'), isNull);
    },
  );
  test('logout blocks a password read that was already in flight', () async {
    final manager = SessionManager(client, prefs, store: store);
    final endpoint = client.endpoint.toString();
    await manager.connect(
      endpoint: endpoint,
      name: 'Name',
      address: '2:1/2',
      password: 'remember-me',
    );
    final gate = Completer<void>();
    store.onRead = (key) async {
      final stale = store.values[key];
      await gate.future;
      return stale;
    };
    final pending = manager.savedPassword(endpoint, '2:1/2');
    await manager.logout();
    gate.complete();
    expect(await pending, isNull);
  });
  test('secure profile sessions isolate connect, restore, endpoint changes and logout', () async {
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
    await expectLater(manager.restore(), throwsA(isA<UnauthorizedException>()));
    expect(await oneStore.read(endpoint), isNull);
    expect(await twoStore.read(endpoint), 'c' * 64);
    expect(await const SecureSessionStore().read(endpoint), 'd' * 64);
    expect(secrets.values, isNot(contains('not-stored')));
  });
}
