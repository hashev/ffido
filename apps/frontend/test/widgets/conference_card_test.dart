import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/fido_conference.dart';
import 'package:fido/conference_card.dart';

void main() {
  group('ConferenceCard Widget', () {
    final testConference = FidoConference(
      name: 'comp.lang.dart',
      description: 'Обсуждение Dart',
      unreadCount: 15,
      icon: Icons.code,
    );

    testWidgets('отображает название конференции', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConferenceCard(conference: testConference, onTap: () {}),
          ),
        ),
      );

      expect(find.text('comp.lang.dart'), findsOneWidget);
    });

    testWidgets('отображает описание конференции', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConferenceCard(conference: testConference, onTap: () {}),
          ),
        ),
      );

      expect(find.text('Обсуждение Dart'), findsOneWidget);
    });

    testWidgets('отображает количество непрочитанных', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConferenceCard(conference: testConference, onTap: () {}),
          ),
        ),
      );

      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('не отображает счетчик когда unreadCount = 0', (tester) async {
      final emptyConference = FidoConference(
        name: 'empty.conf',
        description: 'Пустая',
        unreadCount: 0,
        icon: Icons.forum,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConferenceCard(conference: emptyConference, onTap: () {}),
          ),
        ),
      );

      expect(find.text('0'), findsNothing);
    });

    testWidgets('onTap вызывается при нажатии', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConferenceCard(
              conference: testConference,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ListTile));
      await tester.pump();

      expect(tapped, true);
    });
  });
}
