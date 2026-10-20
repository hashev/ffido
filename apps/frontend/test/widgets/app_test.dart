import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final saved in ['https://saved.invalid:8443', 'http://invalid']) {
    test(
      'startup restores only valid endpoint and removes legacy cache ($saved)',
      () async {
        SharedPreferences.setMockInitialValues({
          'ffido_endpoint_v1': saved,
          'cached_conferences': 'legacy',
        });
        await app.initializeApp();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('cached_conferences'), isFalse);
        expect(
          prefs.containsKey('ffido_endpoint_v1'),
          saved.startsWith('https'),
        );
        await app.conferenceRepository.dispose();
      },
    );
  }
  testWidgets(
    'application starts with understandable login and exposes loading route',
    (tester) async {
      await tester.pumpWidget(const app.ReaderApp());
      await tester.pumpAndSettle();
      expect(find.text('Подключение к FFIDO'), findsOneWidget);
      expect(find.byKey(const Key('name')), findsOneWidget);
      expect(find.byKey(const Key('address')), findsOneWidget);
      expect(find.byKey(const Key('password')), findsOneWidget);
      expect(find.byKey(const Key('token')), findsNothing);
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).pushNamed('/loading');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Загрузка...'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
