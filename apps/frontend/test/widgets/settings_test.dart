import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/api/session_store.dart';
import 'package:fido/pages/settings.dart';

class MemoryStore implements SessionStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String endpoint) async => values[endpoint];
  @override
  Future<void> write(String endpoint, String secret) async {
    values[endpoint] = secret;
  }

  @override
  Future<void> delete(String endpoint) async {
    values.remove(endpoint);
  }
}

class LoginClient extends ApiClient {
  bool reject = false;
  @override
  Future<wire.LoginResponse> login({
    required String endpoint,
    required String name,
    required String address,
    required String password,
  }) async {
    if (reject) throw const UnauthorizedException();
    await configure(endpoint: endpoint, token: 'a' * 64);
    session = wire.SessionInfo(
      profile: wire.Profile(name: 'Серверное имя', address: address),
    );
    return wire.LoginResponse(sessionSecret: 'a' * 64, session: session);
  }

  @override
  Future<void> logout() => clearAuthToken();
}

void main() {
  testWidgets(
    'four fields login stores session but never password and supports logout',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = LoginClient();
      final store = MemoryStore();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsWidget(
            client: client,
            preferences: prefs,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('token')), findsNothing);
      await tester.enterText(find.byKey(const Key('name')), 'Имя');
      await tester.enterText(find.byKey(const Key('address')), '2:1/2');
      await tester.enterText(
        find.byKey(const Key('password')),
        'fixture-secret',
      );
      await tester.enterText(
        find.byKey(const Key('endpoint')),
        'https://other.invalid:8443',
      );
      expect(
        tester.widget<TextField>(find.byKey(const Key('password'))).obscureText,
        isTrue,
      );
      await tester.ensureVisible(find.text('Подключиться'));
      await tester.tap(find.text('Подключиться'));
      await tester.pumpAndSettle();
      expect(client.hasToken, isTrue);
      expect(store.values['https://other.invalid:8443'], 'a' * 64);
      expect(
        prefs.getKeys().any(
          (key) => prefs.get(key).toString().contains('fixture-secret'),
        ),
        isFalse,
      );
      expect(prefs.getKeys().any((key) => prefs.get(key) == 'a' * 64), isFalse);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('password')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('name')))
            .controller!
            .text,
        'Серверное имя',
      );
      await tester.ensureVisible(find.text('Выйти'));
      await tester.tap(find.text('Выйти'));
      await tester.pumpAndSettle();
      expect(client.hasToken, isFalse);
      expect(store.values, isEmpty);
      expect(find.text('Вы вышли из сессии'), findsOneWidget);
    },
  );
  testWidgets(
    'bad password preserves current session and shows understandable error',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final client = LoginClient();
      await client.setAuthToken('b' * 64);
      client.reject = true;
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsWidget(client: client, store: MemoryStore()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Подключиться'));
      await tester.tap(find.text('Подключиться'));
      await tester.pumpAndSettle();
      expect(client.hasToken, isTrue);
      expect(
        find.textContaining('Неверный FTN-адрес или пароль'),
        findsOneWidget,
      );
    },
  );
}
