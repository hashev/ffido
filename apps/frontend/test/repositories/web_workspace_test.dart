import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/platform/telegram_host_stub.dart';
import 'package:fido/repositories/backend_directory.dart';
import 'package:fido/repositories/web_workspace.dart';
import 'package:fido/repositories/web_draft_store.dart';

class FakeTelegramHost extends BrowserTelegramHost {
  String proof = 'fixture';
  String? hint;
  @override
  String get initData => proof;
  @override
  String? get startNode => hint;
}

class WorkspaceApi extends ApiClient {
  final discovered = <String>[];
  final revoked = <String>[];
  bool unavailable = false;
  bool invalidProof = false;
  bool rejectRestore = false;
  final unavailableEndpoints = <String>{};
  int unbinds = 0, logouts = 0;
  int binds = 0;
  String? submittedPassword;
  bool? replaceBinding;
  @override
  Future<wire.TelegramBinding> getTelegramBinding() async =>
      wire.TelegramBinding(bound: true);
  @override
  Future<wire.TelegramBinding> bindTelegram({
    required String initData,
    required String password,
    bool replaceExisting = false,
  }) async {
    binds++;
    submittedPassword = password;
    replaceBinding = replaceExisting;
    return wire.TelegramBinding(bound: true);
  }

  String? currentToken;
  final responses = <String, wire.SessionInfo>{};
  @override
  Future<void> configure({required String endpoint, String? token}) async {
    currentToken = token;
    await super.configure(endpoint: endpoint, token: token);
  }

  @override
  Future<bool> supportsTelegram(String endpoint) async => true;
  @override
  Future<wire.TelegramProfiles> telegramProfiles(
    String endpoint,
    String initData,
  ) async {
    discovered.add(endpoint);
    if (unavailable || unavailableEndpoints.contains(endpoint)) {
      throw const NetworkException();
    }
    if (invalidProof) throw const UnauthorizedException();
    return wire.TelegramProfiles(
      profiles: [
        wire.Profile(name: 'One', address: '2:1/1.1'),
        wire.Profile(name: 'Two', address: '2:1/1.2'),
      ],
    );
  }

  Future<wire.LoginResponse> establish(String endpoint, String address) async {
    final token = (address.endsWith('.1') ? '1' : '2') * 64;
    final response = wire.LoginResponse(
      sessionSecret: token,
      session: wire.SessionInfo(
        profile: wire.Profile(name: address, address: address),
      ),
    );
    responses[token] = response.session;
    await configure(endpoint: endpoint, token: token);
    session = response.session;
    return response;
  }

  @override
  Future<wire.LoginResponse> loginWithTelegram({
    required String endpoint,
    required String initData,
    required String address,
  }) => establish(endpoint, address);
  @override
  Future<wire.LoginResponse> login({
    required String endpoint,
    required String name,
    required String address,
    required String password,
  }) => establish(endpoint, address);
  @override
  Future<wire.SessionInfo> restoreSession() async {
    if (rejectRestore) throw const UnauthorizedException();
    return session = responses[currentToken]!;
  }

  @override
  Future<void> logout() async {
    logouts++;
    await clearAuthToken();
    if (unavailable) throw const NetworkException();
  }

  @override
  Future<void> unbindTelegram() async {
    if (unavailable) throw const NetworkException();
    unbinds++;
  }

  @override
  Future<void> revokeSessionAt(String endpoint, String token) async {
    revoked.add(token);
    if (unavailable) throw const NetworkException();
  }
}

String workspaceCatalog({String endpoint = 'https://node.example.org'}) =>
    jsonEncode({
      'schema': 1,
      'servers': [
        {
          'id': 'test',
          'name': 'Тестовый узел',
          'ftn_address': '2:1/1',
          'endpoint': endpoint,
        },
        {
          'id': 'other',
          'name': 'Другой узел',
          'ftn_address': '2:1/2',
          'endpoint': 'https://other.example.org',
        },
      ],
    });

void main() {
  late WorkspaceApi api;
  late SharedPreferences prefs;
  late FakeTelegramHost host;
  late WebWorkspace workspace;
  late String source;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    api = WorkspaceApi();
    host = FakeTelegramHost();
    source = workspaceCatalog();
    workspace = WebWorkspace(
      api,
      prefs,
      BackendDirectoryRepository(prefs, () async => source),
      host,
    );
  });
  tearDown(() async {
    WebDraftStore.active = null;
    workspace.dispose();
    host.dispose();
    await api.dispose();
  });
  test(
    'new device does not disclose identity; only accepted nodes are discovered',
    () async {
      await workspace.restore();
      expect(api.discovered, isEmpty);
      final node = workspace.directory.current!.find('test')!;
      await expectLater(workspace.discover(node), throwsStateError);
      await workspace.directory.accept(node);
      await workspace.restore();
      expect(api.discovered, ['https://node.example.org']);
      expect(workspace.profiles, hasLength(2));
      expect(workspace.selected, isNull);
    },
  );
  test('multiple profiles restore last selection; explicit logout suppresses auto login', () async {
    await workspace.refresh();
    final node = workspace.directory.current!.find('test')!;
    await workspace.directory.accept(node);
    await workspace.discover(node);
    final first = workspace.profiles.first, second = workspace.profiles.last;
    await workspace.select(first);
    await workspace.drafts.write(first.scope, 'draft', {'body': 'One'});
    await workspace.select(second);
    await workspace.drafts.write(second.scope, 'draft', {'body': 'Two'});
    await workspace.select(first);
    expect(api.session!.profile.address, first.profile.address);
    await workspace.signOut();
    expect(workspace.drafts.list(first.scope), isEmpty);
    expect(workspace.drafts.list(second.scope), hasLength(1));
    expect(prefs.getBool(workspace.stopped(first.scope)), isTrue);
    await workspace.restore();
    expect(workspace.selected, isNull);
    await workspace.select(first);
    expect(workspace.selected!.scope, first.scope);
    expect(
      prefs.getKeys().any(
        (key) => (prefs.get(key)?.toString() ?? '').contains('1' * 64),
      ),
      isFalse,
    );
  });
  test(
    'unlink keeps current HPT session but retires a Telegram session',
    () async {
      await workspace.refresh();
      final node = workspace.directory.current!.find('test')!;
      await workspace.directory.accept(node);
      await workspace.hptLogin(node, 'One', '2:1/1.1', 'fixture');
      await workspace.signOut(unbind: true);
      expect(api.unbinds, 1);
      expect(api.hasToken, isTrue);
      expect(api.logouts, 0);
      await workspace.discover(node);
      await workspace.select(workspace.profiles.last);
      await workspace.signOut(unbind: true);
      expect(api.hasToken, isFalse);
      expect(api.unbinds, 2);
    },
  );
  test(
    'offline logout clears local identity and reports unconfirmed revocation',
    () async {
      await workspace.refresh();
      final node = workspace.directory.current!.find('test')!;
      await workspace.directory.accept(node);
      await workspace.hptLogin(node, 'One', '2:1/1.1', 'fixture');
      final scope = workspace.selected!.scope;
      await workspace.drafts.write(scope, 'draft', {'body': 'private'});
      api.unavailable = true;
      await expectLater(
        workspace.signOut(),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('не подтверждён'),
          ),
        ),
      );
      expect(api.hasToken, isFalse);
      expect(workspace.selected, isNull);
      expect(workspace.drafts.list(scope), isEmpty);
      expect(prefs.getBool(workspace.stopped(scope)), isTrue);
    },
  );
  test('removal and migration block active token; forgetting clears undiscovered drafts', () async {
    await workspace.refresh();
    final node = workspace.directory.current!.find('test')!;
    await workspace.directory.accept(node);
    await workspace.hptLogin(node, 'One', '2:1/1.1', 'fixture');
    final hiddenScope = jsonEncode([
      'test',
      node.endpoint.toString(),
      '2:1/1.99',
    ]);
    await workspace.drafts.write(hiddenScope, 'draft', {'body': 'Hidden'});
    source = workspaceCatalog(endpoint: 'https://new.example.org');
    await workspace.refresh();
    expect(api.hasToken, isFalse);
    expect(workspace.selected, isNull);
    expect(workspace.directory.knownEntries, isEmpty);
    await workspace.forget('test');
    expect(workspace.drafts.list(hiddenScope), isEmpty);
    expect(workspace.directory.acceptedEndpoints, isEmpty);
  });
  test('expired proof and inaccessible node do not hide errors or expose other nodes', () async {
    await workspace.refresh();
    final node = workspace.directory.current!.find('test')!;
    await workspace.directory.accept(node);
    api.unavailable = true;
    await expectLater(
      workspace.discover(node),
      throwsA(isA<NetworkException>()),
    );
    expect(workspace.errors, contains('test'));
    expect(api.discovered, ['https://node.example.org']);
  });
  test(
    'one unavailable known node does not block profiles from another',
    () async {
      await workspace.refresh();
      for (final node in workspace.directory.current!.entries) {
        await workspace.directory.accept(node);
      }
      api.unavailableEndpoints.add('https://other.example.org');
      await workspace.restore();
      expect(api.discovered.toSet(), {
        'https://node.example.org',
        'https://other.example.org',
      });
      expect(workspace.profiles, hasLength(2));
      expect(workspace.errors.keys, ['other']);
    },
  );
  test('invalid Telegram proof requires reopening rather than falling through to HPT', () async {
    await workspace.refresh();
    final node = workspace.directory.current!.find('test')!;
    await workspace.directory.accept(node);
    api.invalidProof = true;
    await expectLater(
      workspace.discover(node),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(workspace.invalidTelegramProof, contains('test'));
    await expectLater(
      workspace.hptLogin(node, 'One', '2:1/1.1', 'fixture'),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(api.hasToken, isFalse);
  });
  test(
    'failed switch retires the wrong active token and preserves other sessions',
    () async {
      await workspace.refresh();
      final node = workspace.directory.current!.find('test')!;
      await workspace.directory.accept(node);
      await workspace.discover(node);
      final first = workspace.profiles.first, second = workspace.profiles.last;
      await workspace.select(first);
      await workspace.select(second);
      api.rejectRestore = true;
      host.proof = '';
      await expectLater(
        workspace.select(first),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(workspace.selected, isNull);
      expect(api.hasToken, isFalse);
      expect(workspace.drafts.scope, isNull);
      api.rejectRestore = false;
      await workspace.select(second);
      expect(workspace.selected!.scope, second.scope);
      expect(api.logouts, 0);
    },
  );
}
