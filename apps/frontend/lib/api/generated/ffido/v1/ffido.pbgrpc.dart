// This is a generated file - do not edit.
//
// Generated from ffido/v1/ffido.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart' as $1;

import 'ffido.pb.dart' as $0;

export 'ffido.pb.dart';

/// Login проверяет данные HPT; остальные RPC требуют внутреннюю Bearer-сессию.
@$pb.GrpcServiceName('ffido.v1.Ffido')
class FfidoClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  FfidoClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.LoginResponse> login(
    $0.LoginRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$login, request, options: options);
  }

  $grpc.ResponseFuture<$0.SessionInfo> restoreSession(
    $1.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$restoreSession, request, options: options);
  }

  $grpc.ResponseFuture<$1.Empty> logout(
    $1.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$logout, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListConferencesResponse> listConferences(
    $0.ListConferencesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listConferences, request, options: options);
  }

  $grpc.ResponseFuture<$0.Conference> getConference(
    $0.GetConferenceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getConference, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListMessagesResponse> listMessages(
    $0.ListMessagesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMessages, request, options: options);
  }

  $grpc.ResponseFuture<$0.Message> getMessage(
    $0.MessageReference request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMessage, request, options: options);
  }

  $grpc.ResponseFuture<$0.CreateMessageResponse> createMessage(
    $0.CreateMessageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMessage, request, options: options);
  }

  $grpc.ResponseFuture<$0.CreateCrosspostResponse> createCrosspost(
    $0.CreateCrosspostRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createCrosspost, request, options: options);
  }

  $grpc.ResponseFuture<$1.Empty> markRead(
    $0.MessageReference request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$markRead, request, options: options);
  }

  $grpc.ResponseFuture<$1.Empty> markUnread(
    $0.MessageReference request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$markUnread, request, options: options);
  }

  $grpc.ResponseFuture<$0.MarkConferenceReadResponse> markConferenceRead(
    $0.MarkConferenceReadRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$markConferenceRead, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListMessagesResponse> getThread(
    $0.GetThreadRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getThread, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListBookmarksResponse> listBookmarks(
    $0.PageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listBookmarks, request, options: options);
  }

  $grpc.ResponseFuture<$1.Empty> addBookmark(
    $0.GetConferenceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$addBookmark, request, options: options);
  }

  $grpc.ResponseFuture<$1.Empty> removeBookmark(
    $0.GetConferenceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$removeBookmark, request, options: options);
  }

  $grpc.ResponseFuture<$0.ListHistoryResponse> listHistory(
    $0.PageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listHistory, request, options: options);
  }

  $grpc.ResponseFuture<$1.Empty> clearHistory(
    $1.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$clearHistory, request, options: options);
  }

  $grpc.ResponseFuture<$0.Profile> getProfile(
    $1.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getProfile, request, options: options);
  }

  $grpc.ResponseFuture<$0.UueLimits> getUueLimits(
    $1.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getUueLimits, request, options: options);
  }

  $grpc.ResponseFuture<$0.SearchUuePartsResponse> searchUueParts(
    $0.SearchUuePartsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$searchUueParts, request, options: options);
  }

  $grpc.ResponseFuture<$0.UueAttachment> assembleUue(
    $0.AssembleUueRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$assembleUue, request, options: options);
  }

  $grpc.ResponseFuture<$0.UueChunk> getUueChunk(
    $0.GetUueChunkRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getUueChunk, request, options: options);
  }

  $grpc.ResponseFuture<$0.UueUploadStatus> uploadUueChunk(
    $0.UploadUueChunkRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$uploadUueChunk, request, options: options);
  }

  $grpc.ResponseFuture<$0.UueSendStatus> commitUue(
    $0.CommitUueRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$commitUue, request, options: options);
  }

  $grpc.ResponseFuture<$0.UueSendStatus> getUueSendStatus(
    $0.UueOperationReference request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getUueSendStatus, request, options: options);
  }

  // method descriptors

  static final _$login = $grpc.ClientMethod<$0.LoginRequest, $0.LoginResponse>(
      '/ffido.v1.Ffido/Login',
      ($0.LoginRequest value) => value.writeToBuffer(),
      $0.LoginResponse.fromBuffer);
  static final _$restoreSession = $grpc.ClientMethod<$1.Empty, $0.SessionInfo>(
      '/ffido.v1.Ffido/RestoreSession',
      ($1.Empty value) => value.writeToBuffer(),
      $0.SessionInfo.fromBuffer);
  static final _$logout = $grpc.ClientMethod<$1.Empty, $1.Empty>(
      '/ffido.v1.Ffido/Logout',
      ($1.Empty value) => value.writeToBuffer(),
      $1.Empty.fromBuffer);
  static final _$listConferences =
      $grpc.ClientMethod<$0.ListConferencesRequest, $0.ListConferencesResponse>(
          '/ffido.v1.Ffido/ListConferences',
          ($0.ListConferencesRequest value) => value.writeToBuffer(),
          $0.ListConferencesResponse.fromBuffer);
  static final _$getConference =
      $grpc.ClientMethod<$0.GetConferenceRequest, $0.Conference>(
          '/ffido.v1.Ffido/GetConference',
          ($0.GetConferenceRequest value) => value.writeToBuffer(),
          $0.Conference.fromBuffer);
  static final _$listMessages =
      $grpc.ClientMethod<$0.ListMessagesRequest, $0.ListMessagesResponse>(
          '/ffido.v1.Ffido/ListMessages',
          ($0.ListMessagesRequest value) => value.writeToBuffer(),
          $0.ListMessagesResponse.fromBuffer);
  static final _$getMessage =
      $grpc.ClientMethod<$0.MessageReference, $0.Message>(
          '/ffido.v1.Ffido/GetMessage',
          ($0.MessageReference value) => value.writeToBuffer(),
          $0.Message.fromBuffer);
  static final _$createMessage =
      $grpc.ClientMethod<$0.CreateMessageRequest, $0.CreateMessageResponse>(
          '/ffido.v1.Ffido/CreateMessage',
          ($0.CreateMessageRequest value) => value.writeToBuffer(),
          $0.CreateMessageResponse.fromBuffer);
  static final _$createCrosspost =
      $grpc.ClientMethod<$0.CreateCrosspostRequest, $0.CreateCrosspostResponse>(
          '/ffido.v1.Ffido/CreateCrosspost',
          ($0.CreateCrosspostRequest value) => value.writeToBuffer(),
          $0.CreateCrosspostResponse.fromBuffer);
  static final _$markRead = $grpc.ClientMethod<$0.MessageReference, $1.Empty>(
      '/ffido.v1.Ffido/MarkRead',
      ($0.MessageReference value) => value.writeToBuffer(),
      $1.Empty.fromBuffer);
  static final _$markUnread = $grpc.ClientMethod<$0.MessageReference, $1.Empty>(
      '/ffido.v1.Ffido/MarkUnread',
      ($0.MessageReference value) => value.writeToBuffer(),
      $1.Empty.fromBuffer);
  static final _$markConferenceRead = $grpc.ClientMethod<
          $0.MarkConferenceReadRequest, $0.MarkConferenceReadResponse>(
      '/ffido.v1.Ffido/MarkConferenceRead',
      ($0.MarkConferenceReadRequest value) => value.writeToBuffer(),
      $0.MarkConferenceReadResponse.fromBuffer);
  static final _$getThread =
      $grpc.ClientMethod<$0.GetThreadRequest, $0.ListMessagesResponse>(
          '/ffido.v1.Ffido/GetThread',
          ($0.GetThreadRequest value) => value.writeToBuffer(),
          $0.ListMessagesResponse.fromBuffer);
  static final _$listBookmarks =
      $grpc.ClientMethod<$0.PageRequest, $0.ListBookmarksResponse>(
          '/ffido.v1.Ffido/ListBookmarks',
          ($0.PageRequest value) => value.writeToBuffer(),
          $0.ListBookmarksResponse.fromBuffer);
  static final _$addBookmark =
      $grpc.ClientMethod<$0.GetConferenceRequest, $1.Empty>(
          '/ffido.v1.Ffido/AddBookmark',
          ($0.GetConferenceRequest value) => value.writeToBuffer(),
          $1.Empty.fromBuffer);
  static final _$removeBookmark =
      $grpc.ClientMethod<$0.GetConferenceRequest, $1.Empty>(
          '/ffido.v1.Ffido/RemoveBookmark',
          ($0.GetConferenceRequest value) => value.writeToBuffer(),
          $1.Empty.fromBuffer);
  static final _$listHistory =
      $grpc.ClientMethod<$0.PageRequest, $0.ListHistoryResponse>(
          '/ffido.v1.Ffido/ListHistory',
          ($0.PageRequest value) => value.writeToBuffer(),
          $0.ListHistoryResponse.fromBuffer);
  static final _$clearHistory = $grpc.ClientMethod<$1.Empty, $1.Empty>(
      '/ffido.v1.Ffido/ClearHistory',
      ($1.Empty value) => value.writeToBuffer(),
      $1.Empty.fromBuffer);
  static final _$getProfile = $grpc.ClientMethod<$1.Empty, $0.Profile>(
      '/ffido.v1.Ffido/GetProfile',
      ($1.Empty value) => value.writeToBuffer(),
      $0.Profile.fromBuffer);
  static final _$getUueLimits = $grpc.ClientMethod<$1.Empty, $0.UueLimits>(
      '/ffido.v1.Ffido/GetUueLimits',
      ($1.Empty value) => value.writeToBuffer(),
      $0.UueLimits.fromBuffer);
  static final _$searchUueParts =
      $grpc.ClientMethod<$0.SearchUuePartsRequest, $0.SearchUuePartsResponse>(
          '/ffido.v1.Ffido/SearchUueParts',
          ($0.SearchUuePartsRequest value) => value.writeToBuffer(),
          $0.SearchUuePartsResponse.fromBuffer);
  static final _$assembleUue =
      $grpc.ClientMethod<$0.AssembleUueRequest, $0.UueAttachment>(
          '/ffido.v1.Ffido/AssembleUue',
          ($0.AssembleUueRequest value) => value.writeToBuffer(),
          $0.UueAttachment.fromBuffer);
  static final _$getUueChunk =
      $grpc.ClientMethod<$0.GetUueChunkRequest, $0.UueChunk>(
          '/ffido.v1.Ffido/GetUueChunk',
          ($0.GetUueChunkRequest value) => value.writeToBuffer(),
          $0.UueChunk.fromBuffer);
  static final _$uploadUueChunk =
      $grpc.ClientMethod<$0.UploadUueChunkRequest, $0.UueUploadStatus>(
          '/ffido.v1.Ffido/UploadUueChunk',
          ($0.UploadUueChunkRequest value) => value.writeToBuffer(),
          $0.UueUploadStatus.fromBuffer);
  static final _$commitUue =
      $grpc.ClientMethod<$0.CommitUueRequest, $0.UueSendStatus>(
          '/ffido.v1.Ffido/CommitUue',
          ($0.CommitUueRequest value) => value.writeToBuffer(),
          $0.UueSendStatus.fromBuffer);
  static final _$getUueSendStatus =
      $grpc.ClientMethod<$0.UueOperationReference, $0.UueSendStatus>(
          '/ffido.v1.Ffido/GetUueSendStatus',
          ($0.UueOperationReference value) => value.writeToBuffer(),
          $0.UueSendStatus.fromBuffer);
}

@$pb.GrpcServiceName('ffido.v1.Ffido')
abstract class FfidoServiceBase extends $grpc.Service {
  $core.String get $name => 'ffido.v1.Ffido';

  FfidoServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.LoginRequest, $0.LoginResponse>(
        'Login',
        login_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.LoginRequest.fromBuffer(value),
        ($0.LoginResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.Empty, $0.SessionInfo>(
        'RestoreSession',
        restoreSession_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.Empty.fromBuffer(value),
        ($0.SessionInfo value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.Empty, $1.Empty>(
        'Logout',
        logout_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.Empty.fromBuffer(value),
        ($1.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ListConferencesRequest,
            $0.ListConferencesResponse>(
        'ListConferences',
        listConferences_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.ListConferencesRequest.fromBuffer(value),
        ($0.ListConferencesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetConferenceRequest, $0.Conference>(
        'GetConference',
        getConference_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetConferenceRequest.fromBuffer(value),
        ($0.Conference value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.ListMessagesRequest, $0.ListMessagesResponse>(
            'ListMessages',
            listMessages_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.ListMessagesRequest.fromBuffer(value),
            ($0.ListMessagesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MessageReference, $0.Message>(
        'GetMessage',
        getMessage_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.MessageReference.fromBuffer(value),
        ($0.Message value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.CreateMessageRequest, $0.CreateMessageResponse>(
            'CreateMessage',
            createMessage_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.CreateMessageRequest.fromBuffer(value),
            ($0.CreateMessageResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CreateCrosspostRequest,
            $0.CreateCrosspostResponse>(
        'CreateCrosspost',
        createCrosspost_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.CreateCrosspostRequest.fromBuffer(value),
        ($0.CreateCrosspostResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MessageReference, $1.Empty>(
        'MarkRead',
        markRead_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.MessageReference.fromBuffer(value),
        ($1.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MessageReference, $1.Empty>(
        'MarkUnread',
        markUnread_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.MessageReference.fromBuffer(value),
        ($1.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.MarkConferenceReadRequest,
            $0.MarkConferenceReadResponse>(
        'MarkConferenceRead',
        markConferenceRead_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.MarkConferenceReadRequest.fromBuffer(value),
        ($0.MarkConferenceReadResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.GetThreadRequest, $0.ListMessagesResponse>(
            'GetThread',
            getThread_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.GetThreadRequest.fromBuffer(value),
            ($0.ListMessagesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PageRequest, $0.ListBookmarksResponse>(
        'ListBookmarks',
        listBookmarks_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PageRequest.fromBuffer(value),
        ($0.ListBookmarksResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetConferenceRequest, $1.Empty>(
        'AddBookmark',
        addBookmark_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetConferenceRequest.fromBuffer(value),
        ($1.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetConferenceRequest, $1.Empty>(
        'RemoveBookmark',
        removeBookmark_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetConferenceRequest.fromBuffer(value),
        ($1.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PageRequest, $0.ListHistoryResponse>(
        'ListHistory',
        listHistory_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PageRequest.fromBuffer(value),
        ($0.ListHistoryResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.Empty, $1.Empty>(
        'ClearHistory',
        clearHistory_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.Empty.fromBuffer(value),
        ($1.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.Empty, $0.Profile>(
        'GetProfile',
        getProfile_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.Empty.fromBuffer(value),
        ($0.Profile value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.Empty, $0.UueLimits>(
        'GetUueLimits',
        getUueLimits_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.Empty.fromBuffer(value),
        ($0.UueLimits value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SearchUuePartsRequest,
            $0.SearchUuePartsResponse>(
        'SearchUueParts',
        searchUueParts_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.SearchUuePartsRequest.fromBuffer(value),
        ($0.SearchUuePartsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.AssembleUueRequest, $0.UueAttachment>(
        'AssembleUue',
        assembleUue_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.AssembleUueRequest.fromBuffer(value),
        ($0.UueAttachment value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.GetUueChunkRequest, $0.UueChunk>(
        'GetUueChunk',
        getUueChunk_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.GetUueChunkRequest.fromBuffer(value),
        ($0.UueChunk value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$0.UploadUueChunkRequest, $0.UueUploadStatus>(
            'UploadUueChunk',
            uploadUueChunk_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $0.UploadUueChunkRequest.fromBuffer(value),
            ($0.UueUploadStatus value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.CommitUueRequest, $0.UueSendStatus>(
        'CommitUue',
        commitUue_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.CommitUueRequest.fromBuffer(value),
        ($0.UueSendStatus value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.UueOperationReference, $0.UueSendStatus>(
        'GetUueSendStatus',
        getUueSendStatus_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $0.UueOperationReference.fromBuffer(value),
        ($0.UueSendStatus value) => value.writeToBuffer()));
  }

  $async.Future<$0.LoginResponse> login_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.LoginRequest> $request) async {
    return login($call, await $request);
  }

  $async.Future<$0.LoginResponse> login(
      $grpc.ServiceCall call, $0.LoginRequest request);

  $async.Future<$0.SessionInfo> restoreSession_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.Empty> $request) async {
    return restoreSession($call, await $request);
  }

  $async.Future<$0.SessionInfo> restoreSession(
      $grpc.ServiceCall call, $1.Empty request);

  $async.Future<$1.Empty> logout_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.Empty> $request) async {
    return logout($call, await $request);
  }

  $async.Future<$1.Empty> logout($grpc.ServiceCall call, $1.Empty request);

  $async.Future<$0.ListConferencesResponse> listConferences_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListConferencesRequest> $request) async {
    return listConferences($call, await $request);
  }

  $async.Future<$0.ListConferencesResponse> listConferences(
      $grpc.ServiceCall call, $0.ListConferencesRequest request);

  $async.Future<$0.Conference> getConference_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetConferenceRequest> $request) async {
    return getConference($call, await $request);
  }

  $async.Future<$0.Conference> getConference(
      $grpc.ServiceCall call, $0.GetConferenceRequest request);

  $async.Future<$0.ListMessagesResponse> listMessages_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.ListMessagesRequest> $request) async {
    return listMessages($call, await $request);
  }

  $async.Future<$0.ListMessagesResponse> listMessages(
      $grpc.ServiceCall call, $0.ListMessagesRequest request);

  $async.Future<$0.Message> getMessage_Pre($grpc.ServiceCall $call,
      $async.Future<$0.MessageReference> $request) async {
    return getMessage($call, await $request);
  }

  $async.Future<$0.Message> getMessage(
      $grpc.ServiceCall call, $0.MessageReference request);

  $async.Future<$0.CreateMessageResponse> createMessage_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateMessageRequest> $request) async {
    return createMessage($call, await $request);
  }

  $async.Future<$0.CreateMessageResponse> createMessage(
      $grpc.ServiceCall call, $0.CreateMessageRequest request);

  $async.Future<$0.CreateCrosspostResponse> createCrosspost_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.CreateCrosspostRequest> $request) async {
    return createCrosspost($call, await $request);
  }

  $async.Future<$0.CreateCrosspostResponse> createCrosspost(
      $grpc.ServiceCall call, $0.CreateCrosspostRequest request);

  $async.Future<$1.Empty> markRead_Pre($grpc.ServiceCall $call,
      $async.Future<$0.MessageReference> $request) async {
    return markRead($call, await $request);
  }

  $async.Future<$1.Empty> markRead(
      $grpc.ServiceCall call, $0.MessageReference request);

  $async.Future<$1.Empty> markUnread_Pre($grpc.ServiceCall $call,
      $async.Future<$0.MessageReference> $request) async {
    return markUnread($call, await $request);
  }

  $async.Future<$1.Empty> markUnread(
      $grpc.ServiceCall call, $0.MessageReference request);

  $async.Future<$0.MarkConferenceReadResponse> markConferenceRead_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.MarkConferenceReadRequest> $request) async {
    return markConferenceRead($call, await $request);
  }

  $async.Future<$0.MarkConferenceReadResponse> markConferenceRead(
      $grpc.ServiceCall call, $0.MarkConferenceReadRequest request);

  $async.Future<$0.ListMessagesResponse> getThread_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetThreadRequest> $request) async {
    return getThread($call, await $request);
  }

  $async.Future<$0.ListMessagesResponse> getThread(
      $grpc.ServiceCall call, $0.GetThreadRequest request);

  $async.Future<$0.ListBookmarksResponse> listBookmarks_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.PageRequest> $request) async {
    return listBookmarks($call, await $request);
  }

  $async.Future<$0.ListBookmarksResponse> listBookmarks(
      $grpc.ServiceCall call, $0.PageRequest request);

  $async.Future<$1.Empty> addBookmark_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetConferenceRequest> $request) async {
    return addBookmark($call, await $request);
  }

  $async.Future<$1.Empty> addBookmark(
      $grpc.ServiceCall call, $0.GetConferenceRequest request);

  $async.Future<$1.Empty> removeBookmark_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetConferenceRequest> $request) async {
    return removeBookmark($call, await $request);
  }

  $async.Future<$1.Empty> removeBookmark(
      $grpc.ServiceCall call, $0.GetConferenceRequest request);

  $async.Future<$0.ListHistoryResponse> listHistory_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.PageRequest> $request) async {
    return listHistory($call, await $request);
  }

  $async.Future<$0.ListHistoryResponse> listHistory(
      $grpc.ServiceCall call, $0.PageRequest request);

  $async.Future<$1.Empty> clearHistory_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.Empty> $request) async {
    return clearHistory($call, await $request);
  }

  $async.Future<$1.Empty> clearHistory(
      $grpc.ServiceCall call, $1.Empty request);

  $async.Future<$0.Profile> getProfile_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.Empty> $request) async {
    return getProfile($call, await $request);
  }

  $async.Future<$0.Profile> getProfile(
      $grpc.ServiceCall call, $1.Empty request);

  $async.Future<$0.UueLimits> getUueLimits_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.Empty> $request) async {
    return getUueLimits($call, await $request);
  }

  $async.Future<$0.UueLimits> getUueLimits(
      $grpc.ServiceCall call, $1.Empty request);

  $async.Future<$0.SearchUuePartsResponse> searchUueParts_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$0.SearchUuePartsRequest> $request) async {
    return searchUueParts($call, await $request);
  }

  $async.Future<$0.SearchUuePartsResponse> searchUueParts(
      $grpc.ServiceCall call, $0.SearchUuePartsRequest request);

  $async.Future<$0.UueAttachment> assembleUue_Pre($grpc.ServiceCall $call,
      $async.Future<$0.AssembleUueRequest> $request) async {
    return assembleUue($call, await $request);
  }

  $async.Future<$0.UueAttachment> assembleUue(
      $grpc.ServiceCall call, $0.AssembleUueRequest request);

  $async.Future<$0.UueChunk> getUueChunk_Pre($grpc.ServiceCall $call,
      $async.Future<$0.GetUueChunkRequest> $request) async {
    return getUueChunk($call, await $request);
  }

  $async.Future<$0.UueChunk> getUueChunk(
      $grpc.ServiceCall call, $0.GetUueChunkRequest request);

  $async.Future<$0.UueUploadStatus> uploadUueChunk_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UploadUueChunkRequest> $request) async {
    return uploadUueChunk($call, await $request);
  }

  $async.Future<$0.UueUploadStatus> uploadUueChunk(
      $grpc.ServiceCall call, $0.UploadUueChunkRequest request);

  $async.Future<$0.UueSendStatus> commitUue_Pre($grpc.ServiceCall $call,
      $async.Future<$0.CommitUueRequest> $request) async {
    return commitUue($call, await $request);
  }

  $async.Future<$0.UueSendStatus> commitUue(
      $grpc.ServiceCall call, $0.CommitUueRequest request);

  $async.Future<$0.UueSendStatus> getUueSendStatus_Pre($grpc.ServiceCall $call,
      $async.Future<$0.UueOperationReference> $request) async {
    return getUueSendStatus($call, await $request);
  }

  $async.Future<$0.UueSendStatus> getUueSendStatus(
      $grpc.ServiceCall call, $0.UueOperationReference request);
}
