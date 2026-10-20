import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/pages/loading.dart';

void main() {
  group('LoadingWidget', () {
    testWidgets('отображает CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoadingWidget()));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('отображает текст загрузки по умолчанию', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoadingWidget()));

      expect(find.text('Загрузка...'), findsOneWidget);
    });

    testWidgets('отображает кастомный текст загрузки', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoadingWidget(message: 'Загрузка конференций...'),
        ),
      );

      expect(find.text('Загрузка конференций...'), findsOneWidget);
      expect(find.text('Загрузка...'), findsNothing);
    });

    testWidgets('отображает AppBar когда showAppBar = true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoadingWidget(showAppBar: true, appBarTitle: 'Тест'),
        ),
      );

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Тест'), findsOneWidget);
    });

    testWidgets('не отображает AppBar когда showAppBar = false', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: LoadingWidget(showAppBar: false)),
      );

      expect(find.byType(AppBar), findsNothing);
    });
  });
}
