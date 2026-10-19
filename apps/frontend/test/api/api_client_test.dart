import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/uue_capabilities.dart';
import 'package:fido/api/api_transport.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pbgrpc.dart' as wire;

class TestService extends wire.FfidoServiceBase {
  @override
  Future<wire.UueLimits> getUueLimits(grpc.ServiceCall c, Empty r) async =>
      throw const grpc.GrpcError.unimplemented();
  @override
  Future<wire.SearchUuePartsResponse> searchUueParts(
    grpc.ServiceCall c,
    wire.SearchUuePartsRequest r,
  ) async => throw const grpc.GrpcError.unimplemented();
  @override
  Future<wire.UueAttachment> assembleUue(
    grpc.ServiceCall c,
    wire.AssembleUueRequest r,
  ) async => throw const grpc.GrpcError.unimplemented();
  @override
  Future<wire.UueChunk> getUueChunk(
    grpc.ServiceCall c,
    wire.GetUueChunkRequest r,
  ) async => throw const grpc.GrpcError.unimplemented();
  @override
  Future<wire.UueUploadStatus> uploadUueChunk(
    grpc.ServiceCall c,
    wire.UploadUueChunkRequest r,
  ) async => throw const grpc.GrpcError.unimplemented();
  @override
  Future<wire.UueSendStatus> commitUue(
    grpc.ServiceCall c,
    wire.CommitUueRequest r,
  ) async => throw const grpc.GrpcError.unimplemented();
  @override
  Future<wire.UueSendStatus> getUueSendStatus(
    grpc.ServiceCall c,
    wire.UueOperationReference r,
  ) async => throw const grpc.GrpcError.unimplemented();
  bool corrupt = false;
  TestService() {
    $addMethod(
      grpc.ServiceMethod<Empty, wire.Profile>(
        'GetProfile',
        (grpc.ServiceCall call, Future<Empty> request) async =>
            getProfile(call, await request),
        false,
        false,
        Empty.fromBuffer,
        (response) => corrupt ? [255] : response.writeToBuffer(),
      ),
    );
  }

  bool bulkUnavailableOnce = false;
  final bulkKeys = <String>[];
  @override
  Future<wire.MarkConferenceReadResponse> markConferenceRead(
    grpc.ServiceCall c,
    wire.MarkConferenceReadRequest r,
  ) async {
    bulkKeys.add(r.operationId);
    if (bulkUnavailableOnce) {
      bulkUnavailableOnce = false;
      throw const grpc.GrpcError.unavailable();
    }
    await before(c);
    return wire.MarkConferenceReadResponse(generation: r.operationId);
  }

  @override
  Future<wire.LoginResponse> login(
    grpc.ServiceCall c,
    wire.LoginRequest r,
  ) async {
    await before(c);
    return wire.LoginResponse(
      sessionSecret: 'b' * 64,
      session: wire.SessionInfo(
        profile: wire.Profile(userId: 'A', name: r.name, address: r.address),
      ),
    );
  }

  @override
  Future<wire.SessionInfo> restoreSession(grpc.ServiceCall c, Empty r) async {
    await before(c);
    return wire.SessionInfo(
      profile: wire.Profile(userId: 'A', name: 'Name', address: '2:1/2'),
    );
  }

  @override
  Future<Empty> logout(grpc.ServiceCall c, Empty r) async {
    await before(c);
    return Empty();
  }

  int calls = 0, creates = 0;
  String? authorization;
  grpc.GrpcError? failure;
  Completer<void>? barrier;
  Future<void> before(grpc.ServiceCall call) async {
    calls++;
    authorization = call.clientMetadata?['authorization'];
    if (barrier != null) await barrier!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<wire.Profile> getProfile(grpc.ServiceCall c, Empty r) async {
    await before(c);
    return wire.Profile(name: 'Юрий', address: '2:1/2');
  }

  @override
  Future<wire.ListConferencesResponse> listConferences(
    grpc.ServiceCall c,
    wire.ListConferencesRequest r,
  ) async {
    await before(c);
    return wire.ListConferencesResponse();
  }

  @override
  Future<wire.Conference> getConference(
    grpc.ServiceCall c,
    wire.GetConferenceRequest r,
  ) async {
    await before(c);
    return wire.Conference(id: r.conferenceId);
  }

  @override
  Future<wire.ListMessagesResponse> listMessages(
    grpc.ServiceCall c,
    wire.ListMessagesRequest r,
  ) async {
    await before(c);
    return wire.ListMessagesResponse();
  }

  @override
  Future<wire.Message> getMessage(
    grpc.ServiceCall c,
    wire.MessageReference r,
  ) async {
    await before(c);
    return wire.Message(id: r.messageId);
  }

  @override
  Future<wire.CreateMessageResponse> createMessage(
    grpc.ServiceCall c,
    wire.CreateMessageRequest r,
  ) async {
    creates++;
    await before(c);
    return wire.CreateMessageResponse(
      status: wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
      message: wire.MessageReference(messageId: r.operationId),
    );
  }

  @override
  Future<Empty> markRead(grpc.ServiceCall c, wire.MessageReference r) async {
    await before(c);
    return Empty();
  }

  @override
  Future<wire.ListMessagesResponse> getThread(
    grpc.ServiceCall c,
    wire.GetThreadRequest r,
  ) async {
    await before(c);
    return wire.ListMessagesResponse();
  }

  @override
  Future<wire.ListBookmarksResponse> listBookmarks(
    grpc.ServiceCall c,
    wire.PageRequest r,
  ) async {
    await before(c);
    return wire.ListBookmarksResponse();
  }

  @override
  Future<Empty> addBookmark(
    grpc.ServiceCall c,
    wire.GetConferenceRequest r,
  ) async {
    await before(c);
    return Empty();
  }

  @override
  Future<Empty> removeBookmark(
    grpc.ServiceCall c,
    wire.GetConferenceRequest r,
  ) async {
    await before(c);
    return Empty();
  }

  @override
  Future<wire.ListHistoryResponse> listHistory(
    grpc.ServiceCall c,
    wire.PageRequest r,
  ) async {
    await before(c);
    return wire.ListHistoryResponse();
  }

  @override
  Future<Empty> clearHistory(grpc.ServiceCall c, Empty r) async {
    await before(c);
    return Empty();
  }
}

void main() {
  late ApiClient client;
  late grpc.Server server;
  late TestService service;
  final token = 'a' * 64;
  setUp(() async {
    service = TestService();
    server = grpc.Server.create(services: [service]);
    await server.serve(address: '127.0.0.1', port: 0);
    client = ApiClient(
      endpoint: 'https://localhost:${server.port}',
      channelFactory: (uri) => grpc.ClientChannel(
        '127.0.0.1',
        port: uri.port,
        options: const grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.insecure(),
        ),
      ),
    );
    await client.setAuthToken(token);
  });
  tearDown(() async {
    service.barrier?.complete();
    await client.dispose();
    await server.shutdown();
  });
  test('all typed RPCs share metadata and preserve Unicode', () async {
    expect((await client.getProfile()).name, 'Юрий');
    await client.listConferences(wire.ListConferencesRequest());
    await client.getConference(wire.GetConferenceRequest());
    await client.listMessages(wire.ListMessagesRequest());
    await client.getMessage(wire.MessageReference());
    await client.createMessage(wire.CreateMessageRequest(operationId: 'op'));
    await client.markRead(wire.MessageReference());
    await client.getThread(wire.GetThreadRequest());
    await client.listBookmarks(wire.PageRequest());
    await client.addBookmark(wire.GetConferenceRequest());
    await client.removeBookmark(wire.GetConferenceRequest());
    await client.listHistory(wire.PageRequest());
    await client.clearHistory();
    expect(service.calls, 13);
    expect(service.authorization, 'Bearer $token');
    expect(client.cacheScope, isNot(contains(token)));
  });
  test('logout refuses calls before contacting server', () async {
    await client.clearAuthToken();
    await expectLater(
      client.getProfile(),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(service.calls, 0);
  });
  test(
    'read retries are bounded but create never automatically retries',
    () async {
      service.failure = const grpc.GrpcError.unavailable(
        'private server details',
      );
      await expectLater(client.getProfile(), throwsA(isA<NetworkException>()));
      expect(service.calls, 2);
      await expectLater(
        client.createMessage(wire.CreateMessageRequest(operationId: 'same')),
        throwsA(isA<NetworkException>()),
      );
      expect(service.creates, 1);
    },
  );
  test('session change cancels in-flight data', () async {
    service.barrier = Completer<void>();
    final pending = client.getProfile();
    final assertion = expectLater(pending, throwsA(isA<CancelledException>()));
    while (service.calls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await client.setAuthToken('b' * 64);
    await assertion;
  });
  test('explicit cancellation aborts in-flight call', () async {
    service.barrier = Completer<void>();
    final cancellation = RpcCancellation();
    final pending = client.getProfile(cancellation: cancellation);
    final assertion = expectLater(pending, throwsA(isA<CancelledException>()));
    while (service.calls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await cancellation.cancel();
    await assertion;
  });
  test('deadline bounds a pending RPC and dispose closes the client', () async {
    await client.dispose();
    client = ApiClient(
      endpoint: 'https://localhost:${server.port}',
      timeout: const Duration(milliseconds: 30),
      channelFactory: (uri) => grpc.ClientChannel(
        '127.0.0.1',
        port: uri.port,
        options: const grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.insecure(),
        ),
      ),
    );
    await client.setAuthToken(token);
    service.barrier = Completer<void>();
    await expectLater(client.getProfile(), throwsA(isA<DeadlineException>()));
    await client.dispose();
    await client.dispose();
    expect(client.hasToken, isFalse);
    await expectLater(client.getProfile(), throwsA(isA<CancelledException>()));
    await expectLater(
      client.setAuthToken(token),
      throwsA(isA<CancelledException>()),
    );
  });
  test('invalid transport budgets are refused', () {
    expect(() => ApiClient(timeout: Duration.zero), throwsArgumentError);
    expect(() => ApiClient(readAttempts: 0), throwsArgumentError);
    expect(() => ApiClient(readAttempts: 4), throwsArgumentError);
  });
  test('configuration validation is atomic', () async {
    final previous = client.epoch;
    for (final endpoint in [
      'http://localhost',
      'https://token@localhost',
      'https://localhost/path',
      'https://localhost?q=token',
      'https://localhost#token',
      'https://localhost:0',
    ]) {
      await expectLater(
        client.configure(endpoint: endpoint, token: token),
        throwsA(isA<ValidationException>()),
      );
    }
    await expectLater(
      client.setAuthToken('invalid'),
      throwsA(isA<ValidationException>()),
    );
    expect(client.epoch, previous);
    expect(client.hasToken, isTrue);
    await client.configure(endpoint: client.endpoint.toString(), token: token);
    expect(client.epoch, previous);
  });
  test(
    'field violations decode from binary trailers and malformed trailers are safe',
    () {
      final details = wire.ErrorDetails(
        violations: [
          wire.FieldViolation(field_1: 'subject', message: 'Обязательное поле'),
        ],
      );
      final error = ApiClient.mapGrpcError(
        const grpc.GrpcError.invalidArgument('private path'),
        {'ffido-error-details-bin': base64.encode(details.writeToBuffer())},
      );
      expect((error as ValidationException).fieldErrors['subject'], [
        'Обязательное поле',
      ]);
      expect(error.toString(), isNot(contains('private path')));
      expect(
        ApiClient.mapGrpcError(const grpc.GrpcError.invalidArgument(), {
          'ffido-error-details-bin': '!',
        }),
        isA<ValidationException>(),
      );
    },
  );
  for (final status in [
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    99,
  ]) {
    test('status $status maps without exposing server details', () {
      final error = ApiClient.mapGrpcError(
        grpc.GrpcError.custom(status, 'secret path SQL token'),
        const {},
        'GetProfile',
      );
      expect(error.toString(), isNot(contains('secret')));
      expect(error.statusCode, status);
      expect(error.rpcName, 'GetProfile');
    });
  }
  test(
    'malformed successful protobuf is a controlled named RPC error',
    () async {
      service.corrupt = true;
      await expectLater(
        client.getProfile(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.rpcName, 'RPC', 'GetProfile')
              .having((e) => e.statusCode, 'status', isNot(0)),
        ),
      );
    },
  );
  test(
    'bulk RPC retries unavailable with exactly the same operation key',
    () async {
      service.bulkUnavailableOnce = true;
      final result = await client.markConferenceRead(
        wire.MarkConferenceReadRequest(
          conferenceId: 'echo',
          operationId: 'immutable-bulk',
        ),
      );
      expect(result.generation, 'immutable-bulk');
      expect(service.bulkKeys, ['immutable-bulk', 'immutable-bulk']);
    },
  );
  test(
    'identity follows confirmed login, restore and unauthenticated response',
    () async {
      final identities = <String?>[];
      final sub = client.identityChanges.listen(
        (_) => identities.add(client.session?.profile.address),
      );
      await client.login(
        endpoint: client.endpoint.toString(),
        name: 'One',
        address: '2:1/2.1',
        password: 'fixture',
      );
      expect(identities.last, '2:1/2.1');
      await client.restoreSession();
      expect(identities.last, '2:1/2');
      service.failure = const grpc.GrpcError.unauthenticated();
      await expectLater(
        client.getProfile(),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(identities.last, isNull);
      await sub.cancel();
    },
  );
  test(
    'login uses no Bearer and switches session only after server confirmation',
    () async {
      service.failure = const grpc.GrpcError.unauthenticated(
        'private fixture secret',
      );
      final previous = client.epoch;
      await expectLater(
        client.login(
          endpoint: client.endpoint.toString(),
          name: 'Name',
          address: '2:1/2',
          password: 'fixture',
        ),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(client.epoch, previous);
      expect(service.authorization, isNull);
      service.failure = null;
      final response = await client.login(
        endpoint: client.endpoint.toString(),
        name: 'Name',
        address: '2:1/2',
        password: 'fixture',
      );
      expect(response.session.profile.name, 'Name');
      expect(client.hasToken, isTrue);
      await client.restoreSession();
      await client.logout();
      expect(client.hasToken, isFalse);
    },
  );
  test(
    'logout during pending login prevents a late session from returning',
    () async {
      service.barrier = Completer<void>();
      final pending = client.login(
        endpoint: client.endpoint.toString(),
        name: 'Name',
        address: '2:1/2',
        password: 'fixture',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final expectation = expectLater(
        pending,
        throwsA(isA<CancelledException>()),
      );
      // Retiring the current session also cancels in-flight Login.
      await client.clearAuthToken();
      service.barrier!.complete();
      service.barrier = null;
      await expectation;
      expect(client.hasToken, isFalse);
    },
  );
  test(
    'UUE capability on an old server keeps ordinary authenticated reading',
    () async {
      expect(await loadUueCapabilities(client), isNull);
      expect(client.hasToken, isTrue);
      expect((await client.getProfile()).name, 'Юрий');
    },
  );
}
