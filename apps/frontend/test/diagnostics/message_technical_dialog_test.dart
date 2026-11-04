import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/message_technical_data.dart';
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/utils/message_technical_report.dart';
import 'package:fido/widgets/message_technical_dialog.dart';

import '../support/fake_transport.dart';
import '../widgets/command_scope_test.dart' show chord;
import 'message_technical_test.dart' show technicalFixture;

Future<void> mountDialog(
  WidgetTester tester,
  FakeTransport api, {
  ThemeMode theme = ThemeMode.light,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      themeMode: theme,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => MessageTechnicalDialog(
                repository: MessageRepository(api),
                conferenceId: 'ECHO',
                messageId: 'g#42',
              ),
            ),
            child: const Text('Диагностика'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Диагностика'));
  await tester.pump();
}

void main() {
  testWidgets(
    'loading, explicit retry, old server and access denial never masquerade as empty fields',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      final pending = Completer<wire.MessageTechnicalData>();
      api.technicalData = (_) => pending.future;
      await mountDialog(tester, api);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Скопировать отчёт'),
            )
            .onPressed,
        isNull,
      );
      pending.completeError(const NetworkException());
      await tester.pumpAndSettle();
      expect(find.textContaining('Не удалось получить'), findsOneWidget);
      expect(find.text('Отсутствует'), findsNothing);
      api.technicalData = (_) async =>
          throw const ApiException(statusCode: 12, message: 'unimplemented');
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.textContaining('обновите сервер'), findsOneWidget);
      api.technicalData = (_) async =>
          throw const ApiException(statusCode: 7, message: 'denied');
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(
        find.text('Нет доступа к техническим данным письма'),
        findsOneWidget,
      );
      api.technicalData = (_) async => technicalFixture();
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(find.text('MSGID'), findsOneWidget);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.byType(MessageTechnicalDialog), findsNothing);
    },
  );
  testWidgets(
    'copy uses exact byte-escaped report; session change clears data and late response',
    (tester) async {
      final api = FakeTransport();
      addTearDown(api.dispose);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      api.technicalData = (_) async => technicalFixture();
      await mountDialog(tester, api);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Скопировать отчёт'));
      await tester.pumpAndSettle();
      expect(
        copied,
        messageTechnicalReport(
          MessageTechnicalData.fromWire(technicalFixture()),
        ),
      );
      expect(copied, isNot(contains('http')));
      api.switchSession();
      await tester.pumpAndSettle();
      expect(find.byType(MessageTechnicalDialog), findsNothing);
      final pending = Completer<wire.MessageTechnicalData>();
      api.technicalData = (_) => pending.future;
      await tester.tap(find.text('Диагностика'));
      await tester.pump();
      api.switchSession();
      await tester.pumpAndSettle();
      pending.complete(technicalFixture());
      await tester.pumpAndSettle();
      expect(find.text('MSGID'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [390.0, 1280.0]) {
    for (final theme in ThemeMode.values.where((t) => t != ThemeMode.system)) {
      testWidgets('lazy long metadata width=$width theme=$theme scale=1.5', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = FakeTransport();
        addTearDown(api.dispose);
        final value = technicalFixture()..subfields.clear();
        for (var i = 0; i < 8192; i++) {
          value.subfields.add(wire.MessageTechnicalSubfield(lowId: 2000));
        }
        api.technicalData = (_) async => value;
        await mountDialog(tester, api, theme: theme, scale: 1.5);
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText).evaluate().length, lessThan(30));
        final scrollable = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        final state = tester.state<ScrollableState>(scrollable);
        state.position.jumpTo(10000000);
        await tester.pumpAndSettle();
        expect(state.position.pixels, greaterThan(100000));
        expect(find.byType(SelectableText).evaluate().length, lessThan(30));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Закрыть'));
        await tester.pumpAndSettle();
        final long = technicalFixture();
        long.subfields.first.value = List.filled(64000, 255);
        api.technicalData = (_) async => long;
        await tester.tap(find.text('Диагностика'));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(
          find.text(technicalBytes(long.subfields.first.value)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final kind in AreaKind.values) {
    testWidgets('read-only diagnostic row is available in $kind', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeTransport();
      addTearDown(api.dispose);
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [wire.Message(id: 'g#42', subject: 'Unopened')],
      );
      api.technicalData = (_) async => technicalFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: MessageScreen(
            conferenceId: 'ECHO',
            conferenceName: 'Area',
            conferenceDescription: '',
            canRead: true,
            canPost: false,
            kind: kind,
            repository: MessageRepository(api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Действия письма'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Технические данные'));
      await tester.pumpAndSettle();
      expect(find.byType(MessageTechnicalDialog), findsOneWidget);
      await tester.tap(find.text('Закрыть'));
      await tester.pumpAndSettle();
      expect(find.text('Unopened'), findsOneWidget);
    });
  }
  for (final unsupported in [false, true]) {
    testWidgets(
      'diagnostics hidden without reading or supported storage: $unsupported',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final api = FakeTransport();
        addTearDown(api.dispose);
        api.messages = (_) async => wire.ListMessagesResponse(
          messages: [wire.Message(id: 'g#42', subject: 'Unopened')],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MessageScreen(
              conferenceId: 'ECHO',
              conferenceName: 'Area',
              conferenceDescription: '',
              canRead: unsupported,
              canPost: true,
              unsupportedFormat: unsupported,
              repository: MessageRepository(api),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Действия письма'), findsNothing);
        expect(find.byTooltip('Действия области'), findsNothing);
        expect(api.calls.whereType<wire.MessageReference>(), isEmpty);
      },
    );
  }
  testWidgets('closing pending request discards its late response', (
    tester,
  ) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    final pending = Completer<wire.MessageTechnicalData>();
    api.technicalData = (_) => pending.future;
    await mountDialog(tester, api);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    pending.complete(technicalFixture());
    await tester.pumpAndSettle();
    expect(find.text('MSGID'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'row diagnostics preserves unread list and blocks reader shortcuts; opened entry works',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeTransport();
      addTearDown(api.dispose);
      var reads = 0;
      api.messages = (_) async => wire.ListMessagesResponse(
        messages: [
          wire.Message(id: 'g#42', subject: 'Unopened', isRead: false),
        ],
      );
      api.technicalData = (_) async => technicalFixture();
      api.message = (r) async {
        reads++;
        return wire.Message(id: r.messageId, subject: 'Opened', body: 'body');
      };
      await tester.pumpWidget(
        MaterialApp(
          home: MessageScreen(
            conferenceId: 'ECHO',
            conferenceName: 'Эха',
            conferenceDescription: '',
            canRead: true,
            canPost: false,
            repository: MessageRepository(api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Действия письма'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Технические данные'));
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(find.byIcon(Icons.mail), findsOneWidget);
      await chord(tester, LogicalKeyboardKey.keyN);
      await chord(tester, LogicalKeyboardKey.keyR);
      await chord(tester, LogicalKeyboardKey.keyU);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(find.byType(MessageTechnicalDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MessageTechnicalDialog), findsNothing);
      expect(find.text('Unopened'), findsOneWidget);
      await tester.tap(find.text('Unopened'));
      await tester.pumpAndSettle();
      expect(reads, 1);
      await tester.tap(find.byTooltip('Действия области'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Технические данные'));
      await tester.pumpAndSettle();
      expect(find.byType(MessageTechnicalDialog), findsOneWidget);
      expect(reads, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
