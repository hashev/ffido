// Isolated visual QA. No network requests or real FTN messages are sent.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/utils/reader_theme.dart';
import '../support/fake_transport.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final api = FakeTransport();
  api.messages = (r) async => wire.ListMessagesResponse(
    messages: [
      wire.Message(
        id: 'smoke#${r.page.offset.toInt() + 1}',
        subject: 'Проверка ${r.page.offset.toInt() + 1}',
        fromName: 'Тестовый автор',
      ),
    ],
    hasMore: r.page.offset.toInt() == 0,
  );
  api.message = (r) async => wire.Message(
    id: r.messageId,
    subject: 'Проверка ${r.messageId}',
    fromName: 'Тестовый автор',
    fromAddress: '2:1/2',
    toName: 'All',
    body:
        'Обычный текст. Русская раскладка.\n\n AB> Цитата первого уровня\n AB>> Цитата второго уровня\n > AB>> Третий уровень\n\n  Отступы сохраняются.\na > b — обычный текст.',
  );
  api.conferences = (_) async => wire.ListConferencesResponse(
    conferences: [
      wire.Conference(
        id: 'test.target',
        name: 'Тестовая эха назначения',
        canPost: true,
      ),
    ],
  );
  api.conference = (r) async => wire.Conference(
    id: r.conferenceId,
    name: 'Тестовая эха назначения',
    canPost: true,
  );
  final conferences = ConferenceRepository(
    apiClient: api,
    prefs: await SharedPreferences.getInstance(),
  );
  runApp(
    MaterialApp(
      title: 'FFIDO — изолированная проверка',
      theme: readerTheme(),
      home: MessageScreen(
        conferenceId: 'test.source',
        conferenceName: 'Тестовая эха • без сети',
        conferenceDescription: '',
        canRead: true,
        canPost: true,
        repository: MessageRepository(api),
        conferences: conferences,
      ),
    ),
  );
}
