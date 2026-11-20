import 'dart:async';
import 'dart:math' as math;

import 'platform/directory_fetch.dart';
import 'platform/telegram_host.dart';
import 'repositories/backend_directory.dart';
import 'repositories/web_workspace.dart';
import 'pages/web_settings.dart';

import 'files/image_actions.dart';

import 'updates/update_host_stub.dart'
    if (dart.library.io) 'updates/update_host_io.dart'
    as update_host;
import 'updates/update_ui.dart';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'platform/desktop_profile.dart';
import 'utils/reader_theme.dart';

import 'package:fido/pages/reader_app.dart';
import 'package:fido/pages/settings.dart';
import 'package:fido/pages/loading.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/session_store.dart';
import 'package:fido/api/api_exceptions.dart';

import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/repositories/account_repository.dart';

String startupMessage = '';
final applicationUptime = Stopwatch();

// Глобальные экземпляры API клиента и репозиториев
final ApiClient apiClient = ApiClient();
WebWorkspace? webWorkspace;
final readerNavigator = GlobalKey<NavigatorState>();
final telegramNavigation = _TelegramNavigation();
late ConferenceRepository conferenceRepository;
late MessageRepository messageRepository;
final AccountRepository accountRepository = AccountRepository(apiClient);

Future<void> initializeApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  unawaited(cleanupImageShares());
  await DesktopProfile.initialize();
  DesktopProfile.observeIdentity(apiClient);

  // Инициализация репозиториев
  final prefs = await SharedPreferences.getInstance();
  final savedEndpoint = prefs.getString('ffido_endpoint_v1');
  if (!kIsWeb && savedEndpoint != null) {
    try {
      await apiClient.configure(endpoint: savedEndpoint);
    } catch (_) {
      await prefs.remove('ffido_endpoint_v1');
    }
  }
  conferenceRepository = ConferenceRepository(
    apiClient: apiClient,
    prefs: prefs,
  );
  messageRepository = MessageRepository(apiClient);
  await conferenceRepository.clearCache();
  try {
    if (kIsWeb) {
      webWorkspace = WebWorkspace(
        apiClient,
        prefs,
        BackendDirectoryRepository(prefs, fetchBackendDirectory),
        telegramHost,
      );
      await webWorkspace!.restore();
      WidgetsBinding.instance.addPostFrameCallback((_) => telegramHost.ready());
    } else {
      await SessionManager(apiClient, prefs).restore();
    }
  } on UnauthorizedException {
    startupMessage =
        'Срок входа истёк или доступ изменён. Введите пароль снова.';
  } on PlatformException {
    startupMessage = defaultTargetPlatform == TargetPlatform.macOS
        ? 'Не удалось прочитать сессию. Разрешите доступ к Keychain или войдите снова; настройки профиля сохранены.'
        : 'Не удалось прочитать защищённую сессию. Войдите снова; настройки профиля сохранены.';
  } catch (_) {
    startupMessage =
        'Не удалось восстановить вход. Проверьте сеть и подключитесь снова.';
  }
}

Future<void> main() async {
  applicationUptime.start();
  WidgetsFlutterBinding.ensureInitialized();
  await update_host.acquireDesktopLease();
  final initialized = initializeApp().then((_) {
    // Only initialization publishes readiness; loading shells may be rebuilt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(update_host.confirmDesktopStartup());
    });
  });
  runApp(
    FutureBuilder<void>(
      future: initialized,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return const ReaderApp();
        }
        return MaterialApp(
          builder: (context, child) => UpdateShell(child: child!),
          home: Scaffold(
            body: Center(
              child: snapshot.hasError
                  ? const Text('Не удалось запустить приложение')
                  : const CircularProgressIndicator(),
            ),
          ),
        );
      },
    ),
  );
}

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: telegramHost,
      builder: (context, _) => MaterialApp(
        title: 'FFIDO',
        navigatorKey: readerNavigator,
        navigatorObservers: [telegramNavigation],
        builder: (context, child) {
          Widget content = UpdateShell(child: child!);
          if (kIsWeb && telegramHost.initData.isNotEmpty) {
            final height = telegramHost.viewportHeight;
            content = Padding(padding: telegramHost.insets, child: content);
            if (height != null) {
              content = Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: math.min(height, MediaQuery.sizeOf(context).height),
                  child: content,
                ),
              );
            }
          }
          return content;
        },
        theme: readerTheme(
          brightness: telegramHost.dark ? Brightness.dark : Brightness.light,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => apiClient.hasToken
              ? const MainScreen()
              : kIsWeb
              ? WebSettings(workspace: webWorkspace!)
              : SettingsWidget(initialMessage: startupMessage),
          '/settings': (context) => kIsWeb
              ? WebSettings(workspace: webWorkspace!)
              : const SettingsWidget(),
          '/loading': (context) => const LoadingWidget(),
        },
      ),
    );
  }
}

class _TelegramNavigation extends NavigatorObserver {
  void sync() => WidgetsBinding.instance.addPostFrameCallback((_) {
    telegramHost.navigation(
      readerNavigator.currentState?.canPop() ?? false,
      () {
        unawaited(readerNavigator.currentState?.maybePop());
      },
    );
  });
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => sync();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => sync();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => sync();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      sync();
}
