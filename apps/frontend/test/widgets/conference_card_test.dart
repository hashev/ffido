import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/fido_conference.dart';
import 'package:fido/conference_card.dart';
import 'package:fido/models/conference.dart';

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

    testWidgets('неизвестная статистика не выглядит нулевой', (tester) async {
      final conference = FidoConference(
        name: 'broken.conf',
        description: '',
        unreadCount: 0,
        icon: Icons.forum,
        statisticsKnown: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConferenceCard(conference: conference, onTap: () {}),
          ),
        ),
      );
      expect(find.text('Статистика недоступна'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNotNull);
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

  for (final kind in [AreaKind.netmail, AreaKind.local]) {
    for (final state in ['positive', 'zero', 'unknown', 'unsupported']) {
      testWidgets('$kind counter $state has readable semantics', (t) async {
        final semantics = t.ensureSemantics();
        final known = state != 'unknown' && state != 'unsupported';
        final count = state == 'positive' ? 7 : 0;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ConferenceCard(
                conference: FidoConference(
                  id: 'arbitrary-id',
                  name: 'Произвольное имя',
                  description: 'Описание',
                  unreadCount: count,
                  icon: Icons.mail,
                  kind: kind,
                  canRead: true,
                  statisticsKnown: known,
                  unsupportedFormat: state == 'unsupported',
                  storageFormat: state == 'unsupported' ? 'Squish' : 'JAM',
                ),
                showZeroCount: true,
                onTap: () {},
              ),
            ),
          ),
        );
        expect(find.text(known ? '$count' : '—'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            known
                ? 'Непрочитанных: $count'
                : 'Количество непрочитанных неизвестно',
          ),
          findsOneWidget,
        );
        if (!known) expect(find.text('0'), findsNothing);
        expect(
          t.widget<ListTile>(find.byType(ListTile)).onTap,
          state == 'unsupported' ? isNull : isNotNull,
        );
        semantics.dispose();
      });
    }
    for (final reason in ['catalog', 'no-read']) {
      testWidgets('$kind hides counter for $reason', (t) async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ConferenceCard(
                conference: FidoConference(
                  name: 'Private',
                  description: 'Описание',
                  unreadCount: 37,
                  icon: Icons.mail,
                  kind: kind,
                  canRead: reason != 'no-read',
                  canPost: true,
                  statisticsKnown: false,
                ),
                showStatistics: reason != 'catalog',
                showZeroCount: true,
                onTap: () {},
              ),
            ),
          ),
        );
        expect(find.text('37'), findsNothing);
        expect(find.text('—'), findsNothing);
        if (reason == 'catalog') {
          expect(find.text('Статистика недоступна'), findsNothing);
        }
      });
    }
  }
  for (final kind in [AreaKind.bad, AreaKind.dupe, AreaKind.robots]) {
    testWidgets('$kind counter stays hidden', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConferenceCard(
              conference: FidoConference(
                name: 'Service',
                description: '',
                unreadCount: 37,
                icon: Icons.mail,
                kind: kind,
                canRead: true,
              ),
              showZeroCount: true,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('37'), findsNothing);
      expect(find.text('—'), findsNothing);
    });
  }
}
