import 'package:fido/api/message_footer.dart';
import 'package:fido/updates/update_controller.dart';
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
  testWidgets('footer saves locally without login, validates and resets', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final client = LoginClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsWidget(
          client: client,
          preferences: prefs,
          footerSettings: MessageFooterSettings(prefs, '1.0.5'),
          store: MemoryStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(appUpdates.canExit, isTrue);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('tagline')),
      200,
      scrollable: scrollable,
    );
    await tester.enterText(find.byKey(const Key('tagline')), 'My tagline');
    await tester.enterText(find.byKey(const Key('origin')), 'My origin');
    expect(appUpdates.canExit, isFalse);
    await tester.ensureVisible(find.text('Сохранить оформление'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Сохранить оформление'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('tagline')))
          .controller!
          .text,
      'My tagline',
    );
    await tester.tap(find.text('Сохранить оформление'));
    await tester.pumpAndSettle();
    expect(find.text('Оформление сохранено'), findsOneWidget);
    expect(appUpdates.canExit, isTrue);
    expect(prefs.getString(MessageFooterSettings.taglineKey), 'My tagline');
    expect(prefs.getString(MessageFooterSettings.originKey), 'My origin');
    expect(client.hasToken, isFalse);
    await tester.ensureVisible(find.text('Сбросить оформление'));
    await tester.tap(find.text('Сбросить оформление'));
    await tester.pumpAndSettle();
    expect(prefs.containsKey(MessageFooterSettings.taglineKey), isFalse);
    expect(prefs.containsKey(MessageFooterSettings.originKey), isFalse);
  });

  testWidgets('four fields login stores secrets securely and supports logout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = LoginClient();
    final store = MemoryStore();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsWidget(client: client, preferences: prefs, store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('token')), findsNothing);
    await tester.enterText(find.byKey(const Key('name')), 'Имя');
    await tester.enterText(find.byKey(const Key('address')), '2:1/2');
    await tester.enterText(find.byKey(const Key('password')), 'fixture-secret');
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
    await tester.scrollUntilVisible(
      find.byKey(const Key('password')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('password')))
          .controller!
          .text,
      'fixture-secret',
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('name'))).controller!.text,
      'Серверное имя',
    );
    // Reconnecting on the same screen must not require typing the password again.
    await tester.ensureVisible(find.text('Подключиться'));
    await tester.tap(find.text('Подключиться'));
    await tester.pumpAndSettle();
    expect(client.hasToken, isTrue);
    await tester.ensureVisible(find.text('Выйти'));
    await tester.tap(find.text('Выйти'));
    await tester.pumpAndSettle();
    expect(client.hasToken, isFalse);
    expect(store.values, isEmpty);
    expect(find.text('Вы вышли из сессии'), findsOneWidget);
  });
  testWidgets('saved password is obscured and cleared when changing server', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ffido_name_v1': 'Name',
      'ffido_address_v1': '2:1/2',
    });
    final prefs = await SharedPreferences.getInstance();
    final client = LoginClient();
    final store = MemoryStore();
    addTearDown(client.dispose);
    final endpoint = client.endpoint.toString();
    store.values['password:$endpoint'] =
        '{"address":"2:1/2","password":"saved-secret"}';
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsWidget(client: client, preferences: prefs, store: store),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(const Key('password')));
    expect(field.controller!.text, 'saved-secret');
    expect(field.obscureText, isTrue);
    await tester.enterText(
      find.byKey(const Key('endpoint')),
      'https://another.invalid',
    );
    expect(field.controller!.text, isEmpty);
  });
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
