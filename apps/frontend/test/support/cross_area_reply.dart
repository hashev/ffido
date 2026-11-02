import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/templates/template_settings.dart';

import 'fake_transport.dart';

wire.Conference replyArea(String id, {bool netmail = true, bool post = true}) =>
    wire.Conference(
      id: id,
      name: id,
      description: 'Описание $id',
      kind: netmail
          ? wire.AreaKind.AREA_KIND_NETMAIL
          : wire.AreaKind.AREA_KIND_ECHO,
      canPost: post,
      canRead: true,
      storageFormat: 'JAM',
      personalMailbox: netmail,
    );

Future<void> replyTap(WidgetTester t, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await t.pumpAndSettle();
    if (finder.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        finder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
  }
  await t.ensureVisible(finder.first);
  await t.pumpAndSettle();
  await t.tap(finder.first);
  await t.pumpAndSettle();
}

TextEditingController replyField(WidgetTester t, String label) =>
    t.widget<TextField>(find.widgetWithText(TextField, label)).controller!;

Future<ConferenceRepository> openReplySource(
  WidgetTester t,
  FakeTransport api, {
  TemplateBundle? template,
  bool canPost = false,
  AreaKind kind = AreaKind.echo,
  String authorAddress = '2:1/9.7',
  String subject = 'Re: Тема',
}) async {
  final prefs = await SharedPreferences.getInstance();
  final repository = ConferenceRepository(apiClient: api, prefs: prefs);
  addTearDown(repository.dispose);
  api.conferences ??= (_) async => wire.ListConferencesResponse(
    conferences: [replyArea('MAIL'), replyArea('OTHER', netmail: false)],
  );
  api.conference ??= (r) async =>
      replyArea(r.conferenceId, netmail: r.conferenceId == 'MAIL');
  api.messages = (_) async => wire.ListMessagesResponse(
    messages: [wire.Message(id: 'source#1', subject: subject)],
  );
  api.message = (_) async => wire.Message(
    id: 'source#1',
    subject: subject,
    fromName: 'Иван Петров',
    fromAddress: authorAddress,
    toName: 'All',
    body: 'Привет\n АБ> Уже цитата',
    direction: wire.MailDirection.MAIL_DIRECTION_OUTGOING,
  );
  await t.pumpWidget(
    MaterialApp(
      home: MessageScreen(
        conferenceId: 'SOURCE',
        conferenceName: 'SOURCE',
        conferenceDescription: 'Исходная эха',
        canRead: true,
        canPost: canPost,
        kind: kind,
        repository: MessageRepository(api),
        conferences: repository,
        loadTemplate: () async =>
            template ?? (await TemplateSettings.load()).read(),
      ),
    ),
  );
  await t.pumpAndSettle();
  await replyTap(t, subject);
  return repository;
}
