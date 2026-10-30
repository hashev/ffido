import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';

Conference echo(String id, {AreaKind kind = AreaKind.echo}) => Conference(
  id: id,
  name: id,
  description: '',
  totalCount: 0,
  unreadCount: 0,
  kind: kind,
  canRead: true,
);
wire.Message row(String id, {bool read = false}) => wire.Message(
  id: id,
  subject: 'subject $id',
  body: 'body $id',
  isRead: read,
);
Widget screen(
  FakeTransport api, {
  List<Conference> order = const [],
  AreaKind kind = AreaKind.echo,
}) => MaterialApp(
  home: MessageScreen(
    conferenceId: 'a',
    conferenceName: 'a',
    conferenceDescription: '',
    canRead: true,
    kind: kind,
    conferenceOrder: order,
    repository: MessageRepository(api),
  ),
);
Future<void> tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

bool enabled(WidgetTester tester, String label) =>
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, label))
        .onPressed !=
    null;
FakeTransport apiForEchoes() {
  final api = FakeTransport();
  api.conference = (r) async => wire.Conference(
    id: r.conferenceId,
    name: r.conferenceId,
    canRead: true,
    canPost: r.conferenceId == 'c',
    statisticsKnown: false,
  );
  api.messages = (r) async => wire.ListMessagesResponse(
    messages: [row('${r.conferenceId}#1', read: r.conferenceId == 'b')],
  );
  api.message = (r) async => row(r.messageId, read: true);
  return api;
}

void main() {
  testWidgets(
    'wraps once, deduplicates candidates and restarts from destination',
    (tester) async {
      final api = apiForEchoes();
      addTearDown(api.dispose);
      await tester.pumpWidget(
        screen(
          api,
          order: [echo('b'), echo('c'), echo('b'), echo('a'), echo('a')],
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'subject a#1');
      await tap(tester, 'Следующее');
      expect(find.text('body c#1'), findsOneWidget);
      expect(
        api.calls.whereType<wire.GetConferenceRequest>().map(
          (r) => r.conferenceId,
        ),
        ['b', 'c'],
      );
      await tap(tester, 'Следующее');
      expect(find.text('body c#1'), findsOneWidget);
      expect(
        api.calls.whereType<wire.GetConferenceRequest>().map(
          (r) => r.conferenceId,
        ),
        ['b', 'c', 'b', 'a'],
      );
      expect(enabled(tester, 'Следующее'), isFalse);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('successful wrap can be followed by another unread echo', (
    tester,
  ) async {
    final api = apiForEchoes();
    addTearDown(api.dispose);
    api.messages = (r) async =>
        wire.ListMessagesResponse(messages: [row('${r.conferenceId}#1')]);
    await tester.pumpWidget(
      screen(api, order: [echo('c'), echo('b'), echo('a')]),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'subject a#1');
    await tap(tester, 'Следующее');
    expect(find.text('body c#1'), findsOneWidget);
    await tap(tester, 'Следующее');
    expect(find.text('body b#1'), findsOneWidget);
    expect(
      api.calls.whereType<wire.MessageReference>().map((r) => r.conferenceId),
      ['a', 'c', 'b'],
    );
  });

  for (final order in [
    <Conference>[],
    [echo('a')],
    [echo('c')],
  ]) {
    testWidgets('no other source candidate for ${order.map((c) => c.id)}', (
      tester,
    ) async {
      final api = apiForEchoes();
      addTearDown(api.dispose);
      await tester.pumpWidget(screen(api, order: order));
      await tester.pumpAndSettle();
      await tap(tester, 'subject a#1');
      expect(enabled(tester, 'Следующее'), isFalse);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(api.calls.whereType<wire.GetConferenceRequest>(), isEmpty);
      expect(
        find.text('Дальнейших непрочитанных сообщений нет'),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'full empty circle preserves body and refresh enables a new search',
    (tester) async {
      final api = apiForEchoes();
      addTearDown(api.dispose);
      var arrived = false;
      api.messages = (r) async => wire.ListMessagesResponse(
        messages: [
          row('${r.conferenceId}#1', read: r.conferenceId != 'a' && !arrived),
        ],
      );
      await tester.pumpWidget(
        screen(api, order: [echo('b'), echo('c'), echo('a')]),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'subject a#1');
      await tap(tester, 'Следующее');
      expect(find.text('body a#1'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(enabled(tester, 'Следующее'), isFalse);
      expect(
        find.text('Дальнейших непрочитанных сообщений нет'),
        findsOneWidget,
      );
      expect(
        api.calls.whereType<wire.GetConferenceRequest>().map(
          (r) => r.conferenceId,
        ),
        ['b', 'c'],
      );
      arrived = true;
      await tester.tap(find.byTooltip('Обновить'));
      await tester.pumpAndSettle();
      expect(enabled(tester, 'Следующее'), isTrue);
      await tap(tester, 'Следующее');
      expect(find.text('body b#1'), findsOneWidget);
    },
  );

  testWidgets('fresh known zero skips all pages and bodies of read echo', (
    tester,
  ) async {
    final api = apiForEchoes();
    addTearDown(api.dispose);
    final conference = api.conference!;
    api.conference = (r) async => r.conferenceId == 'b'
        ? wire.Conference(
            id: 'b',
            name: 'b',
            canRead: true,
            statisticsKnown: true,
            totalCount: Int64(20000),
            unreadCount: Int64.ZERO,
          )
        : conference(r);
    final messages = api.messages!;
    api.messages = (r) async {
      if (r.conferenceId == 'b') {
        return wire.ListMessagesResponse(
          messages: [row('b#1', read: true)],
          hasMore: true,
        );
      }
      return messages(r);
    };
    await tester.pumpWidget(
      screen(api, order: [echo('b'), echo('c'), echo('a')]),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'subject a#1');
    await tap(tester, 'Следующее');
    expect(find.text('body c#1'), findsOneWidget);
    expect(
      api.calls.whereType<wire.ListMessagesRequest>().where(
        (r) => r.conferenceId == 'b',
      ),
      isEmpty,
    );
    expect(
      api.calls.whereType<wire.MessageReference>().map((r) => r.conferenceId),
      ['a', 'c'],
    );
    expect(
      api.calls.whereType<wire.GetConferenceRequest>().map(
        (r) => r.conferenceId,
      ),
      ['b', 'c'],
    );
  });

  for (final known in [true, false]) {
    testWidgets('stale zero and fresh known=$known finds later unread page', (
      tester,
    ) async {
      final api = apiForEchoes();
      addTearDown(api.dispose);
      api.conference = (r) async => wire.Conference(
        id: r.conferenceId,
        name: r.conferenceId,
        canRead: true,
        statisticsKnown: r.conferenceId == 'b' || known,
        unreadCount: r.conferenceId == 'c' && !known ? Int64.ZERO : Int64(1),
      );
      api.messages = (r) async {
        if (r.conferenceId != 'c') {
          return wire.ListMessagesResponse(
            messages: [row('${r.conferenceId}#1', read: r.conferenceId == 'b')],
          );
        }
        return wire.ListMessagesResponse(
          messages: r.page.offset == Int64.ZERO
              ? [row('c#1', read: true)]
              : [row('c#2')],
          hasMore: r.page.offset == Int64.ZERO,
        );
      };
      await tester.pumpWidget(
        screen(api, order: [echo('b'), echo('c'), echo('a')]),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'subject a#1');
      await tap(tester, 'Следующее');
      expect(find.text('body c#2'), findsOneWidget);
      expect(
        api.calls.whereType<wire.GetConferenceRequest>().map(
          (r) => r.conferenceId,
        ),
        ['b', 'c'],
      );
      expect(
        api.calls
            .whereType<wire.ListMessagesRequest>()
            .where((r) => r.conferenceId == 'c')
            .map((r) => r.page.offset.toInt()),
        [0, 1],
      );
      expect(
        api.calls.whereType<wire.MessageReference>().map((r) => r.messageId),
        ['a#1', 'c#2'],
      );
    });
  }

  testWidgets('skips read rows and entire pages without reading their bodies', (
    tester,
  ) async {
    final api = apiForEchoes();
    addTearDown(api.dispose);
    api.messages = (r) async {
      final offset = r.page.offset.toInt();
      return wire.ListMessagesResponse(
        messages: switch (offset) {
          0 => [row('g#1'), row('g#2', read: true)],
          2 => [row('g#3', read: true), row('g#4', read: true)],
          _ => [row('g#5')],
        },
        hasMore: offset < 4,
      );
    };
    await tester.pumpWidget(screen(api));
    await tester.pumpAndSettle();
    await tap(tester, 'subject g#1');
    await tap(tester, 'Следующее');
    expect(find.text('body g#5'), findsOneWidget);
    expect(
      api.calls.whereType<wire.MessageReference>().map((r) => r.messageId),
      ['g#1', 'g#5'],
    );
    expect(enabled(tester, 'Предыдущее'), isFalse);
  });

  testWidgets(
    'previous chooses nearest unread and manual read selection remains possible',
    (tester) async {
      final api = apiForEchoes();
      addTearDown(api.dispose);
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [row('g#1'), row('g#2', read: true), row('g#3')],
      );
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tap(tester, 'subject g#3');
      await tap(tester, 'Предыдущее');
      expect(find.text('body g#1'), findsOneWidget);
      await tap(tester, 'К списку');
      await tap(tester, 'subject g#2');
      expect(find.text('body g#2'), findsOneWidget);
      expect(enabled(tester, 'Следующее'), isFalse);
    },
  );

  testWidgets(
    'crosses in snapshot order, skips read echo and private area, updates permissions',
    (tester) async {
      final api = apiForEchoes();
      addTearDown(api.dispose);
      await tester.pumpWidget(
        screen(
          api,
          order: [
            echo('a'),
            echo('b'),
            echo('net', kind: AreaKind.netmail),
            echo('c'),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'subject a#1');
      await tap(tester, 'Следующее');
      expect(find.text('body c#1'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);
      expect(find.byTooltip('Новое сообщение'), findsOneWidget);
      expect(
        api.calls.whereType<wire.GetConferenceRequest>().map(
          (r) => r.conferenceId,
        ),
        ['b', 'c'],
      );
      expect(
        api.calls.whereType<wire.MessageReference>().map((r) => r.conferenceId),
        ['a', 'c'],
      );
      expect(enabled(tester, 'Следующее'), isTrue);
      await tap(tester, 'Следующее');
      expect(enabled(tester, 'Следующее'), isFalse);
      expect(
        find.text('Дальнейших непрочитанных сообщений нет'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'empty echo can continue and stale zero counts do not exclude candidates',
    (tester) async {
      final api = apiForEchoes();
      addTearDown(api.dispose);
      api.messages = (r) async => wire.ListMessagesResponse(
        messages: r.conferenceId == 'a' ? [] : [row('c#1')],
      );
      await tester.pumpWidget(screen(api, order: [echo('a'), echo('c')]));
      await tester.pumpAndSettle();
      await tap(tester, 'Следующее');
      expect(find.text('body c#1'), findsOneWidget);
    },
  );

  testWidgets('no source context means no cross-echo requests', (tester) async {
    final api = apiForEchoes();
    addTearDown(api.dispose);
    await tester.pumpWidget(screen(api));
    await tester.pumpAndSettle();
    await tap(tester, 'subject a#1');
    expect(enabled(tester, 'Следующее'), isFalse);
    expect(api.calls.whereType<wire.GetConferenceRequest>(), isEmpty);
  });

  testWidgets('network error retries same transition and keeps current body', (
    tester,
  ) async {
    final api = apiForEchoes();
    addTearDown(api.dispose);
    var fail = true;
    api.conference = (r) async {
      if (fail) throw const NetworkException();
      return wire.Conference(
        id: r.conferenceId,
        name: r.conferenceId,
        canRead: true,
        statisticsKnown: false,
      );
    };
    await tester.pumpWidget(screen(api, order: [echo('c'), echo('a')]));
    await tester.pumpAndSettle();
    await tap(tester, 'subject a#1');
    await tap(tester, 'Следующее');
    expect(find.text('body a#1'), findsOneWidget);
    expect(find.text('Сервер недоступен'), findsOneWidget);
    fail = false;
    await tap(tester, 'Повторить');
    expect(find.text('body c#1'), findsOneWidget);
  });

  for (final stage in ['conference', 'page', 'body']) {
    for (final status in [7, 5]) {
      testWidgets('skips inaccessible candidate at $stage status $status', (
        tester,
      ) async {
        final api = apiForEchoes();
        addTearDown(api.dispose);
        final conference = api.conference!;
        final messages = api.messages!;
        final message = api.message!;
        api.conference = (r) async {
          if (stage == 'conference' && r.conferenceId == 'b') {
            throw ServerException(statusCode: status);
          }
          return conference(r);
        };
        api.messages = (r) async {
          if (r.conferenceId == 'b') {
            if (stage == 'page') throw ServerException(statusCode: status);
            return wire.ListMessagesResponse(messages: [row('b#1')]);
          }
          return messages(r);
        };
        api.message = (r) async {
          if (stage == 'body' && r.conferenceId == 'b') {
            throw ServerException(statusCode: status);
          }
          return message(r);
        };
        await tester.pumpWidget(
          screen(api, order: [echo('b'), echo('c'), echo('a')]),
        );
        await tester.pumpAndSettle();
        await tap(tester, 'subject a#1');
        await tap(tester, 'Следующее');
        expect(find.text('body c#1'), findsOneWidget);
      });
    }
  }

  for (final stage in ['conference', 'page', 'body']) {
    for (final close in [false, true]) {
      testWidgets(
        'late wrapped $stage cannot survive ${close ? 'close' : 'session change'}',
        (tester) async {
          final api = apiForEchoes();
          addTearDown(api.dispose);
          final pending = Completer<void>();
          final conference = api.conference!;
          final messages = api.messages!;
          final message = api.message!;
          api.conference = (r) async {
            if (stage == 'conference' && r.conferenceId == 'c') {
              await pending.future;
            }
            return conference(r);
          };
          api.messages = (r) async {
            if (stage == 'page' && r.conferenceId == 'c') await pending.future;
            return messages(r);
          };
          api.message = (r) async {
            if (stage == 'body' && r.conferenceId == 'c') await pending.future;
            return message(r);
          };
          await tester.pumpWidget(screen(api, order: [echo('c'), echo('a')]));
          await tester.pumpAndSettle();
          await tap(tester, 'subject a#1');
          final next = tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Следующее'))
              .onPressed!;
          next();
          next();
          await tester.pump();
          expect(enabled(tester, 'Следующее'), isFalse);
          expect(
            api.calls
                .whereType<wire.GetConferenceRequest>()
                .where((r) => r.conferenceId == 'c')
                .length,
            1,
          );
          expect(find.text('body a#1'), findsOneWidget);
          if (close) {
            await tester.pumpWidget(const SizedBox());
          } else {
            api.switchSession();
          }
          pending.complete();
          await tester.pumpAndSettle();
          expect(find.text('body c#1'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final stage in ['conference', 'page', 'body']) {
    testWidgets(
      'wrapped $stage network failure retries without false exhaustion',
      (tester) async {
        final api = apiForEchoes();
        addTearDown(api.dispose);
        var fail = true;
        final conference = api.conference!;
        final messages = api.messages!;
        final message = api.message!;
        api.conference = (r) async {
          if (stage == 'conference' && fail) throw const NetworkException();
          return conference(r);
        };
        api.messages = (r) async {
          if (stage == 'page' && fail && r.conferenceId == 'c') {
            throw const NetworkException();
          }
          return messages(r);
        };
        api.message = (r) async {
          if (stage == 'body' && fail && r.conferenceId == 'c') {
            throw const NetworkException();
          }
          return message(r);
        };
        await tester.pumpWidget(screen(api, order: [echo('c'), echo('a')]));
        await tester.pumpAndSettle();
        await tap(tester, 'subject a#1');
        await tap(tester, 'Следующее');
        expect(find.text('body a#1'), findsOneWidget);
        expect(find.text('Сервер недоступен'), findsOneWidget);
        expect(
          find.text('Дальнейших непрочитанных сообщений нет'),
          findsNothing,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        fail = false;
        await tap(tester, 'Повторить');
        expect(find.text('body c#1'), findsOneWidget);
      },
    );
  }

  testWidgets('non-echo navigation still opens read neighbours', (
    tester,
  ) async {
    final api = apiForEchoes();
    addTearDown(api.dispose);
    api.messages = (_) async => wire.ListMessagesResponse(
      messages: [row('g#1'), row('g#2', read: true)],
    );
    await tester.pumpWidget(screen(api, kind: AreaKind.local));
    await tester.pumpAndSettle();
    await tap(tester, 'subject g#1');
    await tap(tester, 'Следующее');
    expect(find.text('body g#2'), findsOneWidget);
    await tap(tester, 'Предыдущее');
    expect(find.text('body g#1'), findsOneWidget);
  });
}
