import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:fido/api/api_client.dart';
import 'package:fido/api/session_store.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/pages/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Run against the temporary fixture from scripts/check_two_devices.py.
/// Separate invocations exercise persistence across actual app restarts.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('FFIDO_TEST_PHASE');
  testWidgets('two devices: $phase', (tester) async {
    const endpoint = String.fromEnvironment('FFIDO_TEST_ENDPOINT');
    const host = String.fromEnvironment('FFIDO_TEST_HOST');
    const password = String.fromEnvironment('FFIDO_TEST_PASSWORD');
    const ca = String.fromEnvironment('FFIDO_TEST_CA');
    SharedPreferences.setPrefix('ffido_device_fixture.');
    final prefs = await SharedPreferences.getInstance();
    final client = ApiClient(
      endpoint: endpoint,
      channelFactory: (uri) => grpc.ClientChannel(
        host,
        port: uri.port,
        options: grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.secure(
            certificates: base64Decode(ca),
            authority: 'localhost',
          ),
        ),
      ),
    );
    const store = SecureSessionStore();
    final manager = SessionManager(client, prefs, store: store);
    try {
      if (phase == 'laptop_setup' || phase == 'phone_send') {
        await tester.pumpWidget(
          MaterialApp(
            home: SettingsWidget(
              client: client,
              preferences: prefs,
              store: store,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('name')), 'Device Fixture');
        await tester.enterText(find.byKey(const Key('address')), '2:1/2');
        await tester.enterText(find.byKey(const Key('password')), password);
        await tester.ensureVisible(find.text('Подключиться'));
        await tester.tap(find.text('Подключиться'));
        await tester.pumpAndSettle();
        // The on-device test needs real network/plugin futures, outside fake time.
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          while (!client.hasToken && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        });
        await tester.pumpAndSettle();
        expect(client.hasToken, isTrue);
        expect(find.textContaining('Вход сохранён'), findsOneWidget);
        expect(await store.read(endpoint), isNotNull);
      } else {
        await manager.restore();
        expect(
          client.hasToken,
          isTrue,
          reason: 'session must survive an actual app restart',
        );
        expect(client.session!.profile.address, '2:1/2');
      }
      if (phase == 'phone_send') {
        final created = await client.createMessage(
          wire.CreateMessageRequest(
            conferenceId: 'RU.TEST',
            operationId: 'two-device-phone',
            toName: 'All',
            subject: 'Two device fixture',
            body: 'Phone message',
          ),
        );
        await client.getMessage(created.message);
        await client.addBookmark(
          wire.GetConferenceRequest(conferenceId: 'RU.TEST'),
        );
      }
      if (phase == 'laptop_continue') {
        final rows = await client.listMessages(
          wire.ListMessagesRequest(
            conferenceId: 'RU.TEST',
            page: wire.PageRequest(limit: 20),
            sort: wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
          ),
        );
        expect(rows.messages.length, 1);
        expect(rows.messages.single.isRead, isTrue);
        expect(rows.messages.single.bodyPreview, contains('Phone message'));
        expect(
          (await client.listBookmarks(
            wire.PageRequest(limit: 20),
          )).total.toInt(),
          1,
        );
        expect(
          (await client.listHistory(wire.PageRequest(limit: 20))).total.toInt(),
          1,
        );
      }
      if (phase == 'phone_logout' || phase == 'laptop_check') {
        // laptop_check runs after phone_logout: restoration above must still work.
        final message = await manager.logout();
        expect(message, 'Вы вышли из сессии');
        expect(client.hasToken, isFalse);
        expect(await store.read(endpoint), isNull);
        await prefs.clear();
      }
      await tester.pumpWidget(const SizedBox());
    } finally {
      await client.dispose();
    }
  }, skip: phase.isEmpty);
}
