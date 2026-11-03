// Recording target only: production main.dart never imports this fixture.
// All letters are fictional. No connection to a server is made.
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/reader_app.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/utils/reader_theme.dart';

import '../test/support/fake_transport.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final api = FakeTransport();
  final areas = [
    area('RU.FTN.DEVELOP', 'Разработка программ для FidoNet', 4),
    area('RU.LINUX', 'Linux: вопросы, опыт и решения', 2),
    area('SU.BOOKS', 'Книги, которые хочется обсудить', 3),
    area('Netmail', 'Личная переписка', 1, personal: true),
  ];
  final rows = [
    letter(
      1,
      'Анна Смирнова',
      'Новый релиз FFIDO',
      'Привет, All!\n\nВ новой версии стало удобнее читать эхи с телефона. '
          'Поиск подсвечивает совпадения, а публичный разговор '
          'можно продолжить лично через Netmail.\n\n'
          'Какие возможности вы используете чаще всего?\n\nДо встречи в эхе!\nАнна',
    ),
    letter(
      2,
      'Михаил Волков',
      'Безопасное подключение к серверу',
      'Привет!\n\nFFIDO подключается к серверу по TLS. '
          'Базы JAM остаются на ноде: на телефон передаются только письма.\n\n'
          'Для TLS нужен доверенный сертификат с именем сервера. '
          'Отключать проверку сертификата не требуется.\n\nМихаил',
    ),
    letter(
      3,
      'Дмитрий Соколов',
      'Re: Новый релиз FFIDO',
      'Привет, Анна!\n\n АС> Какие возможности вы используете чаще всего?\n\n'
          'Читаю эхи в дороге, сохраняю интересные области '
          'в закладки и продолжаю с того же места на компьютере.\n\nДмитрий',
    ),
    letter(
      4,
      'Елена Орлова',
      'Сертификаты и доверие',
      'Коллеги, привет!\n\nПроверила TLS на Android и на ноутбуке. '
          'Один профиль, общая прочитанность и история чтения.\n\n'
          'Если меняется адрес сервера, стоит проверить имя '
          'в сертификате и настройки TLS.\n\nЕлена',
    ),
    letter(
      5,
      'Игорь Морозов',
      'Чтение цепочек на телефоне',
      'Привет, All!\n\nОткрыл цепочку обсуждения и быстро нашёл исходный вопрос. '
          'Цитаты помогают сохранить контекст даже в длинной переписке.\n\nИгорь',
    ),
  ];
  api.conferences = (r) async => wire.ListConferencesResponse(
    conferences: areas.where(
      (a) => a.name.toLowerCase().contains(r.query.toLowerCase()),
    ),
    total: Int64(areas.length),
  );
  api.conference = (r) async => areas.firstWhere((a) => a.id == r.conferenceId);
  api.messages = (r) async => wire.ListMessagesResponse(
    messages: rows.skip(r.page.offset.toInt()).take(r.page.limit.toInt()),
    total: Int64(rows.length),
    actualOffset: r.page.offset,
  );
  api.message = (r) async =>
      rows.firstWhere((m) => m.id == r.messageId).deepCopy()..isRead = true;
  api.profile = () async =>
      wire.Profile(name: 'Алексей Иванов', address: '2:9999/1.1');
  api.find = (r) async {
    var start = rows.indexWhere((m) => m.id == r.startMessageId);
    if (start < 0) start = 0;
    if (r.startMessageId.isNotEmpty && !r.includeStart) start++;
    for (final message in rows.skip(start)) {
      final matches = <wire.SearchMatch>[];
      for (final (field, text) in [
        (wire.MessageSearchField.MESSAGE_SEARCH_SUBJECT, message.subject),
        (wire.MessageSearchField.MESSAGE_SEARCH_BODY, message.body),
      ]) {
        final query = r.query.toLowerCase();
        for (
          var offset = text.toLowerCase().indexOf(query);
          offset >= 0 && query.isNotEmpty;
          offset = text.toLowerCase().indexOf(query, offset + query.length)
        ) {
          matches.add(
            wire.SearchMatch(
              field_1: field,
              startUtf16: offset,
              lengthUtf16: query.length,
            ),
          );
        }
      }
      if (matches.isNotEmpty) {
        return wire.FindMessageResponse(
          message: message.deepCopy()..isRead = true,
          matches: matches,
        );
      }
    }
    return wire.FindMessageResponse();
  };
  final repository = ConferenceRepository(
    apiClient: api,
    prefs: await SharedPreferences.getInstance(),
  );
  runApp(
    MaterialApp(
      title: 'FFIDO',
      theme: readerTheme(),
      debugShowCheckedModeBanner: false,
      home: MainScreen(repository: repository),
    ),
  );
}

wire.Conference area(
  String name,
  String description,
  int unread, {
  bool personal = false,
}) => wire.Conference(
  id: name,
  name: name,
  description: description,
  unreadCount: Int64(unread),
  totalCount: Int64(5),
  canRead: true,
  canPost: true,
  storageFormat: 'JAM',
  kind: personal
      ? wire.AreaKind.AREA_KIND_NETMAIL
      : wire.AreaKind.AREA_KIND_ECHO,
  personalMailbox: personal,
);
wire.Message letter(int number, String author, String subject, String body) =>
    wire.Message(
      id: 'demo#$number',
      fromName: author,
      fromAddress: '2:9999/10.$number',
      toName: 'All',
      subject: subject,
      body: body,
      bodyPreview: body.replaceAll('\n', ' '),
      date: Timestamp.fromDateTime(
        DateTime.utc(2026, 11, 3, 9, 30 - number * 5),
      ),
      isRead: number > 3,
    );
