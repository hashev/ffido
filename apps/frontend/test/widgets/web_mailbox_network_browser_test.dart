@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/repositories/message_repository.dart';

import '../support/fake_transport.dart';

void main() {
  testWidgets('a transient Web Netmail failure keeps the opened message', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = FakeTransport();
    api.conference = (_) async => wire.Conference(
      id: 'MAIL',
      name: 'Mail',
      personalMailbox: true,
      canRead: true,
      canPost: true,
      kind: wire.AreaKind.AREA_KIND_NETMAIL,
    );
    api.messages = (_) async => wire.ListMessagesResponse(
      messages: [
        wire.Message(id: 'g#1', subject: 'First', fromName: 'One'),
        wire.Message(id: 'g#2', subject: 'Second', fromName: 'Two'),
      ],
    );
    api.message = (request) async {
      if (request.messageId == 'g#2') throw const NetworkException();
      return wire.Message(
        id: request.messageId,
        subject: 'First',
        fromName: 'One',
        body: 'Opened private body',
      );
    };
    await tester.pumpWidget(
      MaterialApp(
        home: MessageScreen(
          conferenceId: 'MAIL',
          conferenceName: 'Mail',
          conferenceDescription: '',
          personalMailbox: true,
          kind: AreaKind.netmail,
          canRead: true,
          canPost: true,
          repository: MessageRepository(api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    expect(find.text('Opened private body'), findsOneWidget);
    await tester.tap(find.text('Следующее'));
    await tester.pumpAndSettle();
    expect(find.text('Opened private body'), findsOneWidget);
    expect(find.textContaining('Сервер недоступен'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await api.dispose();
  });
}
