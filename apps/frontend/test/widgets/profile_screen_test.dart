import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fido/pages/profile_screen.dart';
import 'package:fido/repositories/account_repository.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

import '../support/fake_transport.dart';

void main() {
  testWidgets('profile can close during its pending load', (tester) async {
    final pending = Completer<wire.Profile>();
    final api = FakeTransport()..profile = () => pending.future;
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(repository: AccountRepository(api))),
    );
    await tester.pumpWidget(const SizedBox());
    pending.complete(wire.Profile(name: 'Late'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('profile displays assigned data and clears on session change', (
    tester,
  ) async {
    final api = FakeTransport();
    addTearDown(api.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(repository: AccountRepository(api))),
    );
    await tester.pump();
    expect(find.text('Реальный профиль'), findsOneWidget);
    expect(find.text('2:1/2'), findsOneWidget);
    final pending = Completer<wire.Profile>();
    api.profile = () => pending.future;
    api.switchSession();
    await tester.pump();
    expect(find.text('Реальный профиль'), findsNothing);
    pending.complete(wire.Profile(name: 'Новая сессия', address: '2:3/4'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Новая сессия'), findsOneWidget);
  });
}
