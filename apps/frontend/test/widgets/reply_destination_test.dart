import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/pages/reply_destination.dart';
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

wire.Conference area(
  String id, {
  wire.AreaKind kind = wire.AreaKind.AREA_KIND_NETMAIL,
  bool post = true,
  String format = 'JAM',
  bool mailbox = false,
}) => wire.Conference(
  id: id,
  name: id,
  kind: kind,
  canPost: post,
  storageFormat: format,
  personalMailbox: mailbox,
);

void main() {
  late FakeTransport api;
  late ConferenceRepository repo;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeTransport();
  });
  Future<void> repository() async {
    repo = ConferenceRepository(
      apiClient: api,
      prefs: await SharedPreferences.getInstance(),
    );
  }

  tearDown(() async {
    await repo.dispose();
    await api.dispose();
  });
  Future<void> open(WidgetTester t, {bool personal = false}) async {
    await repository();
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<Object?>(
                builder: (_) => ReplyDestination(
                  repository: repo,
                  sourceId: 'SOURCE',
                  personalOnly: personal,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'all pages decide uniqueness; own write-only mailbox and filtering',
    (t) async {
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: r.page.offset.toInt() == 0
            ? [area('mailA', mailbox: true)]
            : [
                area('mailB'),
                area('SOURCE', kind: wire.AreaKind.AREA_KIND_ECHO),
                area('echo', kind: wire.AreaKind.AREA_KIND_ECHO),
                area('local', kind: wire.AreaKind.AREA_KIND_LOCAL),
                area('bad', kind: wire.AreaKind.AREA_KIND_BAD),
                area('dupe', kind: wire.AreaKind.AREA_KIND_DUPE),
                area('robots', kind: wire.AreaKind.AREA_KIND_ROBOTS),
                area('squish', format: 'Squish'),
                area('readonly', post: false),
              ],
        hasMore: r.page.offset.toInt() == 0,
      );
      await open(t, personal: true);
      expect(find.text('mailA'), findsOneWidget);
      expect(find.text('mailB'), findsOneWidget);
      expect(find.text('echo'), findsNothing);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      // This route still explicitly requests personal destinations.
      await t.tap(find.text('mailB'));
      await t.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    },
  );
  testWidgets(
    'general picker groups netmail first, local search never auto-selects',
    (t) async {
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [
          area('A.echo', kind: wire.AreaKind.AREA_KIND_ECHO),
          area('z.mail'),
          area('b.mail'),
        ],
      );
      await open(t);
      expect(
        t.getTopLeft(find.text('b.mail')).dy,
        lessThan(t.getTopLeft(find.text('A.echo')).dy),
      );
      await t.enterText(find.byType(TextField), 'z.mail');
      await t.pump();
      expect(find.widgetWithText(ListTile, 'z.mail'), findsOneWidget);
      expect(find.text('A.echo'), findsNothing);
      expect(find.text('Область для ответа'), findsOneWidget);
    },
  );
  for (final count in [0, 1]) {
    testWidgets('personal catalog count $count', (t) async {
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [
          if (count == 1) area('mail'),
          area('echo', kind: wire.AreaKind.AREA_KIND_ECHO),
        ],
      );
      await open(t, personal: true);
      expect(
        find.text('Личный ответ'),
        count == 1 ? findsNothing : findsOneWidget,
      );
      if (count == 0) {
        expect(
          find.textContaining('Нет доступного для отправки Netmail'),
          findsOneWidget,
        );
      }
    });
  }
  testWidgets('failure is distinct from empty and can be retried', (t) async {
    api.conferences = (_) async => throw const NetworkException();
    await open(t, personal: true);
    expect(find.textContaining('Не удалось загрузить'), findsOneWidget);
    expect(find.textContaining('Нет доступного'), findsNothing);
    api.conferences = (_) async =>
        wire.ListConferencesResponse(conferences: [area('mail')]);
    await t.tap(find.text('Повторить'));
    await t.pumpAndSettle();
    expect(find.text('Личный ответ'), findsNothing);
  });
  for (final session in [false, true]) {
    testWidgets(
      'late result ignored after ${session ? "session change" : "close"}',
      (t) async {
        final pending = Completer<wire.ListConferencesResponse>();
        api.conferences = (_) => pending.future;
        await repository();
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReplyDestination(
                      repository: repo,
                      sourceId: 'SOURCE',
                      personalOnly: true,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await t.tap(find.text('open'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        if (session) {
          api.switchSession();
          await t.pump();
        } else {
          await t.pageBack();
          await t.pump();
        }
        await t.pump(const Duration(milliseconds: 500));
        pending.complete(
          wire.ListConferencesResponse(conferences: [area('old-mail')]),
        );
        await t.pumpAndSettle();
        expect(find.text('open'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}
