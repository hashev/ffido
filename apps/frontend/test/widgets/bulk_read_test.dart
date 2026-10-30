import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';

Future<void> show(
  WidgetTester tester,
  FakeTransport api, {
  AreaKind kind = AreaKind.echo,
  bool canRead = true,
  bool personalMailbox = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MessageScreen(
        conferenceId: 'echo',
        conferenceName: 'Test Echo',
        conferenceDescription: '',
        repository: MessageRepository(api),
        canRead: canRead,
        personalMailbox: personalMailbox,
        kind: kind,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, {bool retry = false}) async {
  await tester.tap(find.byTooltip('Действия области'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.text(retry ? 'Проверить/повторить' : 'Отметить всё прочитанным'),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cancel causes no RPC; success refreshes whole echo without reading details',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      await show(tester, api);
      await choose(tester);
      expect(
        find.textContaining('вне текущей страницы и цепочки'),
        findsOneWidget,
      );
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(api.calls.whereType<wire.MarkConferenceReadRequest>(), isEmpty);
      await choose(tester);
      await tester.tap(find.text('Отметить'));
      await tester.pumpAndSettle();
      expect(
        api.calls
            .whereType<wire.MarkConferenceReadRequest>()
            .single
            .conferenceId,
        'echo',
      );
      expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
      expect(api.calls.whereType<wire.ListMessagesRequest>().length, 2);
      expect(find.text('Сообщения отмечены прочитанными'), findsOneWidget);
    },
  );
  testWidgets(
    'uncertain retry keeps operation key and blocks a second action',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      var attempts = 0;
      api.bulkRead = (_) async {
        if (attempts++ == 0) throw const NetworkException();
        return wire.MarkConferenceReadResponse();
      };
      await show(tester, api);
      await choose(tester);
      await tester.tap(find.text('Отметить'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Результат не подтверждён'), findsOneWidget);
      await choose(tester, retry: true);
      final calls = api.calls
          .whereType<wire.MarkConferenceReadRequest>()
          .toList();
      expect(calls.length, 2);
      expect(calls[0].operationId, calls[1].operationId);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('late completion after session switch cannot report success', (
    tester,
  ) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    final pending = Completer<wire.MarkConferenceReadResponse>();
    api.bulkRead = (_) => pending.future;
    await show(tester, api);
    await choose(tester);
    await tester.tap(find.text('Отметить'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .enabled,
      isFalse,
    );
    api.switchSession();
    await tester.pumpAndSettle();
    pending.complete(wire.MarkConferenceReadResponse());
    await tester.pumpAndSettle();
    expect(find.text('Сообщения отмечены прочитанными'), findsNothing);
  });

  testWidgets(
    'bulk in a thread preserves selected body and refreshes without GetMessage',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [
          wire.Message(id: 'g#1', subject: 'Subject', bodyPreview: 'preview'),
        ],
      );
      api.message = (_) async => wire.Message(
        id: 'g#1',
        subject: 'Subject',
        body: 'Full original body',
        fromName: 'Author',
      );
      api.thread = (_) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: 'g#1', subject: 'Subject', isRead: true)],
      );
      await show(tester, api);
      await tester.tap(find.text('Subject'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Цепочка сообщений'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subject'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textSpan!
            .toPlainText(),
        contains('Full original body'),
      );
      final details = api.calls.whereType<wire.MessageReference>().length;
      await choose(tester);
      await tester.tap(find.text('Отметить'));
      await tester.pumpAndSettle();
      expect(api.calls.whereType<wire.MessageReference>().length, details);
      expect(api.calls.whereType<wire.GetThreadRequest>().length, 2);
      expect(
        tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textSpan!
            .toPlainText(),
        contains('Full original body'),
      );
    },
  );

  testWidgets(
    'bulk refresh preserves both loaded pages with one server mutation',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.messages = (r) async {
        final offset = r.page.offset.toInt();
        final count = r.page.limit.toInt() == 4 ? 4 : 2;
        return wire.ListMessagesResponse(
          hasMore: offset == 0 && count == 2,
          messages: [
            for (var i = offset; i < offset + count; i++)
              wire.Message(id: 'g#$i', subject: 'Row $i'),
          ],
        );
      };
      await show(tester, api);
      await tester.ensureVisible(find.text('Загрузить ещё'));
      await tester.tap(find.text('Загрузить ещё'));
      await tester.pumpAndSettle();
      expect(find.text('Row 3'), findsOneWidget);
      await choose(tester);
      await tester.tap(find.text('Отметить'));
      await tester.pumpAndSettle();
      expect(api.calls.whereType<wire.MarkConferenceReadRequest>().length, 1);
      expect(
        api.calls.whereType<wire.ListMessagesRequest>().last.page.limit.toInt(),
        4,
      );
      expect(find.text('Row 3'), findsOneWidget);
    },
  );
  for (final kind in [
    AreaKind.netmail,
    AreaKind.local,
    AreaKind.bad,
    AreaKind.dupe,
    AreaKind.robots,
  ]) {
    testWidgets('bulk action marks read-only $kind', (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      await show(tester, api, kind: kind);
      await choose(tester);
      await tester.tap(find.text('Отметить'));
      await tester.pumpAndSettle();
      expect(api.calls.whereType<wire.MarkConferenceReadRequest>().length, 1);
      expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
    });
  }
  testWidgets('unreadable area has no bulk action', (tester) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    await show(tester, api, kind: AreaKind.bad, canRead: false);
    expect(find.byTooltip('Действия области'), findsNothing);
  });

  testWidgets('old server rejection has no fallback or success', (
    tester,
  ) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    api.bulkRead = (_) async =>
        throw const ApiException(message: 'Echo only', statusCode: 9);
    await show(tester, api, kind: AreaKind.netmail);
    await choose(tester);
    await tester.tap(find.text('Отметить'));
    await tester.pumpAndSettle();
    expect(find.text('Сообщения отмечены прочитанными'), findsNothing);
    expect(find.textContaining('Echo only'), findsOneWidget);
    expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
    expect(api.calls.whereType<wire.MarkConferenceReadRequest>().length, 1);
  });
}
