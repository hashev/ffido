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
  } catch (_) {
    startupMessage =
        'Не удалось восстановить вход. Проверьте сеть и подключитесь снова.';
  }
}

Future<void> main() async {
  await initializeApp();
  runApp(const ReaderApp());
}

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FFIDO',
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
