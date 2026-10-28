import 'dart:async';

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

// Глобальные экземпляры API клиента и репозиториев
final ApiClient apiClient = ApiClient();
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
  if (savedEndpoint != null) {
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
    await SessionManager(apiClient, prefs).restore();
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
    return MaterialApp(
      title: 'FFIDO',
      builder: (context, child) => UpdateShell(child: child!),
      theme: readerTheme(),
      initialRoute: '/',
      routes: {
        '/': (context) => apiClient.hasToken
            ? const MainScreen()
            : SettingsWidget(initialMessage: startupMessage),
        '/settings': (context) => const SettingsWidget(),
        '/loading': (context) => const LoadingWidget(),
      },
    );
  }
}
