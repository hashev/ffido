import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/pages/web_settings.dart';
import 'package:fido/repositories/backend_directory.dart';
import 'package:fido/repositories/web_workspace.dart';
import 'package:fido/repositories/web_draft_store.dart';

import '../repositories/web_workspace_test.dart'
    show FakeTelegramHost, WorkspaceApi, workspaceCatalog;

void main() {
  late WorkspaceApi api;
  late FakeTelegramHost host;
  late WebWorkspace workspace;
  Future<void> prepare() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    api = WorkspaceApi();
    host = FakeTelegramHost();
    workspace = WebWorkspace(
      api,
      prefs,
      BackendDirectoryRepository(prefs, () async => workspaceCatalog()),
      host,
    );
    await workspace.refresh();
  }

  tearDown(() async {
    WebDraftStore.active = null;
    workspace.dispose();
    host.dispose();
    await api.dispose();
  });
  Future<void> showSettings(WidgetTester tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      MaterialApp(home: WebSettings(workspace: workspace)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(
    WidgetTester tester,
    String text, {
    double delta = 250,
  }) => tester.scrollUntilVisible(
    find.text(text),
    delta,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  Future<void> login() async {
    final node = workspace.directory.current!.find('test')!;
    await workspace.directory.accept(node);
    await workspace.discover(node);
    await workspace.hptLogin(node, 'One', '2:1/1.1', 'fixture');
  }

  testWidgets(
    'catalog is shown without endpoint input or unsolicited discovery',
    (tester) async {
      await prepare();
      await showSettings(tester);
      expect(find.text('Тестовый узел'), findsOneWidget);
      expect(api.discovered, isEmpty);
      expect(find.widgetWithText(TextField, 'Адрес сервера'), findsNothing);
      await tester.tap(find.text('Тестовый узел'));
      await tester.pumpAndSettle();
      expect(api.discovered, ['https://node.example.org']);
      expect(find.text('Войти по HPT-паролю'), findsOneWidget);
      await scrollTo(tester, 'One — 2:1/1.1');
      expect(find.text('One — 2:1/1.1'), findsOneWidget);
    },
  );
  testWidgets('endpoint move shows both addresses before any backend request', (
    tester,
  ) async {
    await prepare();
    await workspace.preferences.setString(
      BackendDirectoryRepository.historyKey,
      jsonEncode({'test': 'https://old.example.org'}),
    );
    await showSettings(tester);
    await tester.tap(find.text('Тестовый узел'));
    await tester.pumpAndSettle();
    expect(find.textContaining('https://old.example.org'), findsWidgets);
    expect(find.textContaining('https://node.example.org'), findsWidgets);
    expect(api.discovered, isEmpty);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(
      workspace.directory.acceptedEndpoints['test'],
      'https://old.example.org',
    );
    expect(api.discovered, isEmpty);
  });
  testWidgets(
    'browser selects the last accepted profile without sending credentials',
    (tester) async {
      await prepare();
      host.proof = '';
      final node = workspace.directory.current!.find('test')!;
      await workspace.directory.accept(node);
      await workspace.preferences.setString(
        WebWorkspace.lastKey,
        jsonEncode(['test', node.endpoint.toString(), '2:1/1.1']),
      );
      await showSettings(tester);
      expect(
        tester
            .widgetList<EditableText>(find.byType(EditableText))
            .map((w) => w.controller.text),
        contains('2:1/1.1'),
      );
      expect(api.discovered, isEmpty);
      expect(api.hasToken, isFalse);
    },
  );
  testWidgets(
    'logout warning can be cancelled and confirmed logout clears only this profile',
    (tester) async {
      await prepare();
      await login();
      final scope = workspace.selected!.scope;
      await workspace.drafts.write(scope, 'draft', {'body': 'Private draft'});
      await showSettings(tester);
      await scrollTo(tester, 'Завершить сеанс');
      await tester.tap(find.text('Завершить сеанс'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(api.hasToken, isTrue);
      expect(workspace.drafts.list(scope), hasLength(1));
      await tester.tap(find.text('Завершить сеанс'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(api.hasToken, isFalse);
      expect(workspace.drafts.list(scope), isEmpty);
      expect(workspace.preferences.getBool(workspace.stopped(scope)), isTrue);
      await scrollTo(tester, 'Войти через Telegram', delta: -250);
      expect(find.text('Войти через Telegram'), findsOneWidget);
    },
  );
  testWidgets(
    'binding needs explicit confirmation and sends the fresh password without persistence',
    (tester) async {
      await prepare();
      await login();
      await showSettings(tester);
      await scrollTo(tester, 'Привязать или заменить Telegram');
      await tester.tap(find.text('Привязать или заменить Telegram'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(api.binds, 0);
      await tester.tap(find.text('Привязать или заменить Telegram'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('telegram-bind-password')),
        'fresh-password',
      );
      await tester.tap(find.text('Привязать'));
      await tester.pumpAndSettle();
      expect(api.binds, 1);
      expect(api.submittedPassword, 'fresh-password');
      expect(api.replaceBinding, isTrue);
      expect(
        workspace.preferences.getKeys().any(
          (key) => (workspace.preferences.get(key)?.toString() ?? '').contains(
            'fresh-password',
          ),
        ),
        isFalse,
      );
    },
  );
  testWidgets(
    'browser unlink confirms without a password and keeps the HPT session',
    (tester) async {
      await prepare();
      host.proof = '';
      await login();
      await showSettings(tester);
      await scrollTo(tester, 'Отвязать Telegram');
      await tester.tap(find.text('Отвязать Telegram'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('telegram-bind-password')), findsNothing);
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(api.unbinds, 1);
      expect(api.hasToken, isTrue);
      expect(api.logouts, 0);
    },
  );
  testWidgets(
    'logout removes the previous private root from navigation history',
    (tester) async {
      await prepare();
      await login();
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/': (context) => api.hasToken
                ? Scaffold(
                    body: Column(
                      children: [
                        const Text('Private root'),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/settings'),
                          child: const Text('Settings'),
                        ),
                      ],
                    ),
                  )
                : WebSettings(workspace: workspace),
            '/settings': (_) => WebSettings(workspace: workspace),
          },
        ),
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'Завершить сеанс');
      await tester.tap(find.text('Завершить сеанс'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(find.text('Private root'), findsNothing);
      final context = tester.element(find.byType(WebSettings));
      expect(Navigator.canPop(context), isFalse);
    },
  );
}
