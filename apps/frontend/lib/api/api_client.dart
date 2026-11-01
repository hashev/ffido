import 'message_footer_snapshot.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:grpc/grpc_or_grpcweb.dart' as grpc;
import 'package:grpc/service_api.dart' as rpc;
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';

import 'channel_native.dart'
    if (dart.library.js_interop) 'channel_web.dart'
    as channels;
import 'generated/ffido/v1/ffido.pbgrpc.dart' as wire;
import 'api_transport.dart';
import 'api_exceptions.dart';

class ApiClient implements ApiTransport, MessageFooterSupport {
  ApiClient({
    String? endpoint,
    rpc.ClientChannel Function(Uri)? channelFactory,
    this.timeout = const Duration(seconds: 10),
    this.readAttempts = 2,
  }) : _endpoint = validateEndpoint(endpoint ?? channels.defaultEndpoint),
       _factory = channelFactory ?? channels.createChannel {
    if (timeout <= Duration.zero || readAttempts < 1 || readAttempts > 3) {
      throw ArgumentError('Invalid RPC budget');
    }
  }
  final Duration timeout;
  final int readAttempts;
  final rpc.ClientChannel Function(Uri) _factory;
  final StreamController<int> _changes = StreamController<int>.broadcast(
    sync: true,
  );
  final Set<Future<void> Function()> _active = {};
  final String _instance = _nonce();
  rpc.ClientChannel? _channel;
  wire.FfidoClient? _stub;
  Uri _endpoint;
  String? _token;
  int _epoch = 0;
  bool _closed = false;
  int _loginVersion = 0;
  wire.SessionInfo? _session;
  final _identityChanges = StreamController<void>.broadcast(sync: true);
  Stream<void> get identityChanges => _identityChanges.stream;
  @override
  bool get supportsMessageFooter => _session?.supportsMessageFooter ?? false;
  wire.SessionInfo? get session => _session;
  set session(wire.SessionInfo? value) {
    _session = value;
    _identityChanges.add(null);
  }

  @override
  int get epoch => _epoch;
  @override
  Uri get endpoint => _endpoint;
  @override
  String get cacheScope => 'ffido-v1:$_endpoint:$_instance:$_epoch';
  @override
  bool get hasToken => !_closed && _token != null;
  @override
  Stream<int> get sessionChanges => _changes.stream;
  static String _nonce() =>
      base64Url.encode(List.generate(16, (_) => Random.secure().nextInt(256)));
  static Uri validateEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const ValidationException(
        fieldErrors: {
          'endpoint': ['Нужен HTTPS адрес сервера без пути'],
        },
      );
    }
    return uri.replace(path: '');
  }

  Future<void> configure({required String endpoint, String? token}) async {
    if (_closed) throw const CancelledException();
    final nextEndpoint = validateEndpoint(endpoint);
    final nextToken = token?.trim();
    if (nextToken != null &&
        nextToken.isNotEmpty &&
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(nextToken)) {
      throw const ValidationException(
        fieldErrors: {
          'token': ['Нужен выданный 64-символьный токен'],
        },
      );
    }
    final value = nextToken == null || nextToken.isEmpty ? null : nextToken;
    if (_endpoint == nextEndpoint && _token == value) return;
    final previous = _channel;
    final calls = _active.toList();
    _epoch++;
    _endpoint = nextEndpoint;
    _token = value;
    session = null;
    _channel = null;
    _stub = null;
    _changes.add(_epoch);
    await Future.wait(calls.map((cancel) => cancel()));
    await previous?.terminate();
  }

  Future<wire.LoginResponse> login({
    required String endpoint,
    required String name,
    required String address,
    required String password,
  }) async {
    if (_closed) throw const CancelledException();
    final target = validateEndpoint(endpoint);
    final fields = <String, List<String>>{};
    if (name.trim().isEmpty) fields['name'] = ['Укажите имя'];
    if (!RegExp(r'^\d+:\d+/\d+(?:\.\d+)?$').hasMatch(address.trim())) {
      fields['address'] = ['Укажите FTN-адрес, например 2:5015/120.1'];
    }
    if (password.isEmpty) fields['password'] = ['Укажите пароль'];
    if (fields.isNotEmpty) throw ValidationException(fieldErrors: fields);
    final version = ++_loginVersion;
    final captured = epoch;
    final channel = _factory(target);
    final call = wire.FfidoClient(channel).login(
      wire.LoginRequest(
        name: name.trim(),
        address: address.trim(),
        password: password,
      ),
      options: rpc.CallOptions(timeout: timeout),
    );
    final cancel = call.cancel;
    _active.add(cancel);
    try {
      final result = await call;
      if (_closed || captured != epoch || version != _loginVersion) {
        throw const CancelledException(rpcName: 'Login');
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result.sessionSecret) ||
          !result.hasSession() ||
          !result.session.hasProfile()) {
        throw const ApiException(
          message: 'Некорректный ответ входа',
          statusCode: grpc.StatusCode.internal,
          rpcName: 'Login',
        );
      }
      // Do not cancel this completed call when configure retires the old session.
      _active.remove(cancel);
      await configure(endpoint: target.toString(), token: result.sessionSecret);
      session = result.session;
      return result;
    } on grpc.GrpcError catch (error) {
      if (_closed || captured != epoch || version != _loginVersion) {
        throw const CancelledException(rpcName: 'Login');
      }
      Map<String, String> trailers;
      try {
        trailers = await call.trailers;
      } catch (_) {
        trailers = const {};
      }
      throw mapGrpcError(error, trailers, 'Login');
    } finally {
      _active.remove(cancel);
      await channel.terminate();
    }
  }

  Future<wire.SessionInfo> restoreSession() async {
    final result = await _invoke(
      'RestoreSession',
      (c, o) => c.restoreSession(Empty(), options: o),
    );
    session = result;
    return result;
  }

  Future<void> logout() async {
    ++_loginVersion;
    try {
      if (hasToken) {
        await _invoke('Logout', (c, o) => c.logout(Empty(), options: o));
      }
    } finally {
      await clearAuthToken();
    }
  }

  Future<void> clearAuthToken() => configure(endpoint: endpoint.toString());
  Future<void> setAuthToken(String token) =>
      configure(endpoint: endpoint.toString(), token: token);
  wire.FfidoClient get _client {
    _channel ??= _factory(_endpoint);
    return _stub ??= wire.FfidoClient(_channel!);
  }

  void _check(
    int captured,
    RpcCancellation? cancellation, [
    String rpcName = "",
  ]) {
    if (_closed || captured != _epoch || cancellation?.isCancelled == true) {
      throw CancelledException(rpcName: rpcName);
    }
    if (_token == null) {
      throw UnauthorizedException(rpcName: rpcName);
    }
  }

  Future<T> _invoke<T>(
    String rpcName,
    rpc.ResponseFuture<T> Function(wire.FfidoClient, rpc.CallOptions) invoke, {
    bool retry = false,
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    for (var attempt = 0; ; attempt++) {
      _check(captured, cancellation, rpcName);
      final call = invoke(
        _client,
        rpc.CallOptions(
          timeout: timeout,
          metadata: {'authorization': 'Bearer $_token'},
        ),
      );
      final cancel = call.cancel;
      _active.add(cancel);
      cancellation?.add(cancel);
      try {
        final result = await call;
        _check(captured, cancellation, rpcName);
        return result;
      } on grpc.GrpcError catch (error) {
        _check(captured, cancellation, rpcName);
        if (retry &&
            error.code == grpc.StatusCode.unavailable &&
            attempt + 1 < readAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          continue;
        }
        Map<String, String> trailers;
        try {
          trailers = await call.trailers;
        } catch (_) {
          trailers = const {};
        }
        _check(captured, cancellation, rpcName);
        if (error.code == grpc.StatusCode.unauthenticated) session = null;
        throw mapGrpcError(error, trailers, rpcName);
      } finally {
        _active.remove(cancel);
        cancellation?.remove(cancel);
      }
    }
  }

  static ApiException mapGrpcError(
    grpc.GrpcError error, [
    Map<String, String> trailers = const {},
    String rpcName = "",
  ]) {
    switch (error.code) {
      case grpc.StatusCode.unauthenticated:
        return UnauthorizedException(rpcName: rpcName);
      case grpc.StatusCode.notFound:
        return NotFoundException(rpcName: rpcName);
      case grpc.StatusCode.unavailable:
        return NetworkException(rpcName: rpcName);
      case grpc.StatusCode.deadlineExceeded:
        return DeadlineException(rpcName: rpcName);
      case grpc.StatusCode.cancelled:
        return CancelledException(rpcName: rpcName);
      case grpc.StatusCode.invalidArgument:
        final fields = <String, List<String>>{};
        final encoded = trailers['ffido-error-details-bin'];
        if (encoded != null && encoded.length <= 16384) {
          try {
            final details = wire.ErrorDetails.fromBuffer(
              base64.decode(base64.normalize(encoded)),
            );
            for (final violation in details.violations) {
              if (violation.field_1.length <= 128 &&
                  violation.message.length <= 256) {
                fields
                    .putIfAbsent(violation.field_1, () => [])
                    .add(violation.message);
              }
            }
          } catch (_) {
            /* A malformed optional trailer does not hide the RPC status. */
          }
        }
        return ValidationException(fieldErrors: fields, rpcName: rpcName);
      case grpc.StatusCode.alreadyExists:
        return ApiException(
          rpcName: rpcName,
          message:
              'Этот идентификатор отправки уже использован с другим текстом',
          statusCode: grpc.StatusCode.alreadyExists,
        );
      case grpc.StatusCode.permissionDenied:
        return ApiException(
          rpcName: rpcName,
          message: 'Нет доступа',
          statusCode: grpc.StatusCode.permissionDenied,
        );
      case grpc.StatusCode.failedPrecondition:
        return ApiException(
          rpcName: rpcName,
          message: 'База недоступна до восстановления',
          statusCode: grpc.StatusCode.failedPrecondition,
        );
      case grpc.StatusCode.resourceExhausted:
        return ApiException(
          rpcName: rpcName,
          message:
              'Превышен лимит запроса; уменьшите размер страницы или текста',
          statusCode: grpc.StatusCode.resourceExhausted,
        );
      default:
        return ServerException(statusCode: error.code, rpcName: rpcName);
    }
  }

  @override
  Future<wire.ListConferencesResponse> listConferences(
    wire.ListConferencesRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "ListConferences",
    (c, o) => c.listConferences(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.Conference> getConference(
    wire.GetConferenceRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "GetConference",
    (c, o) => c.getConference(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.ListMessagesResponse> listMessages(
    wire.ListMessagesRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "ListMessages",
    (c, o) => c.listMessages(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.Message> getMessage(
    wire.MessageReference r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "GetMessage",
    (c, o) => c.getMessage(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.CreateCrosspostResponse> createCrosspost(
    wire.CreateCrosspostRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    'CreateCrosspost',
    (c, o) => c.createCrosspost(r, options: o),
    cancellation: cancellation,
  );
  @override
  Future<wire.CreateMessageResponse> createMessage(
    wire.CreateMessageRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "CreateMessage",
    (c, o) => c.createMessage(r, options: o),
    cancellation: cancellation,
  );
  @override
  Future<wire.MarkConferenceReadResponse> markConferenceRead(
    wire.MarkConferenceReadRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    'MarkConferenceRead',
    (c, o) => c.markConferenceRead(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<Empty> markRead(
    wire.MessageReference r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "MarkRead",
    (c, o) => c.markRead(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<Empty> markUnread(
    wire.MessageReference r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "MarkUnread",
    (c, o) => c.markUnread(r, options: o),
    retry: false,
    cancellation: cancellation,
  );
  @override
  Future<wire.ListMessagesResponse> getThread(
    wire.GetThreadRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "GetThread",
    (c, o) => c.getThread(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.ListBookmarksResponse> listBookmarks(
    wire.PageRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "ListBookmarks",
    (c, o) => c.listBookmarks(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<Empty> addBookmark(
    wire.GetConferenceRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "AddBookmark",
    (c, o) => c.addBookmark(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<Empty> removeBookmark(
    wire.GetConferenceRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "RemoveBookmark",
    (c, o) => c.removeBookmark(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.ListHistoryResponse> listHistory(
    wire.PageRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    "ListHistory",
    (c, o) => c.listHistory(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<Empty> clearHistory({RpcCancellation? cancellation}) => _invoke(
    "ClearHistory",
    (c, o) => c.clearHistory(Empty(), options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.Profile> getProfile({RpcCancellation? cancellation}) => _invoke(
    "GetProfile",
    (c, o) => c.getProfile(Empty(), options: o),
    retry: true,
    cancellation: cancellation,
  );
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _token = null;
    session = null;
    _epoch++;
    _changes.add(_epoch);
    await Future.wait(_active.toList().map((cancel) => cancel()));
    await _channel?.terminate();
    await _changes.close();
    await _identityChanges.close();
  }

  @override
  Future<wire.UueLimits> getUueLimits(
    Empty r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    'GetUueLimits',
    (c, o) => c.getUueLimits(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.SearchUuePartsResponse> searchUueParts(
    wire.SearchUuePartsRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    'SearchUueParts',
    (c, o) => c.searchUueParts(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.UueAttachment> assembleUue(
    wire.AssembleUueRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    'AssembleUue',
    (c, o) => c.assembleUue(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.UueChunk> getUueChunk(
    wire.GetUueChunkRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    'GetUueChunk',
    (c, o) => c.getUueChunk(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.UueUploadStatus> uploadUueChunk(
    wire.UploadUueChunkRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    'UploadUueChunk',
    (c, o) => c.uploadUueChunk(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.UueSendStatus> commitUue(
    wire.CommitUueRequest r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    'CommitUue',
    (c, o) => c.commitUue(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
  @override
  Future<wire.UueSendStatus> getUueSendStatus(
    wire.UueOperationReference r, {
    RpcCancellation? cancellation,
  }) => _invoke(
    'GetUueSendStatus',
    (c, o) => c.getUueSendStatus(r, options: o),
    retry: true,
    cancellation: cancellation,
  );
}
