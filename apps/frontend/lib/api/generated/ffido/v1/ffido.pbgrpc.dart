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
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart' as $0;

import 'ffido.pb.dart' as $1;

export 'ffido.pb.dart';

/// HPT/Telegram вход и capabilities доступны до сессии; бизнес-RPC требуют Bearer.
@$pb.GrpcServiceName('ffido.v1.Ffido')
class FfidoClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  FfidoClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$1.ServerCapabilities> getServerCapabilities(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getServerCapabilities, request, options: options);
  }

  $grpc.ResponseFuture<$1.TelegramProfiles> listTelegramProfiles(
    $1.TelegramProof request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listTelegramProfiles, request, options: options);
  }

  $grpc.ResponseFuture<$1.LoginResponse> loginWithTelegram(
    $1.TelegramLoginRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$loginWithTelegram, request, options: options);
  }

  $grpc.ResponseFuture<$1.TelegramBinding> bindTelegram(
    $1.BindTelegramRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$bindTelegram, request, options: options);
  }

  $grpc.ResponseFuture<$1.TelegramBinding> getTelegramBinding(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getTelegramBinding, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> unbindTelegram(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$unbindTelegram, request, options: options);
  }

  $grpc.ResponseFuture<$1.LoginResponse> login(
    $1.LoginRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$login, request, options: options);
  }

  $grpc.ResponseFuture<$1.SessionInfo> restoreSession(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$restoreSession, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> logout(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$logout, request, options: options);
  }

  $grpc.ResponseFuture<$1.ListConferencesResponse> listConferences(
    $1.ListConferencesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listConferences, request, options: options);
  }

  $grpc.ResponseFuture<$1.Conference> getConference(
    $1.GetConferenceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getConference, request, options: options);
  }

  $grpc.ResponseFuture<$1.ListMessagesResponse> listMessages(
    $1.ListMessagesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listMessages, request, options: options);
  }

  $grpc.ResponseFuture<$1.SearchArchiveMessagesResponse> searchArchiveMessages(
    $1.SearchArchiveMessagesRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$searchArchiveMessages, request, options: options);
  }

  $grpc.ResponseFuture<$1.ReadArchiveMessageResponse> readArchiveMessage(
    $1.ReadArchiveMessageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$readArchiveMessage, request, options: options);
  }

  $grpc.ResponseFuture<$1.ListMessagesResponse> getArchiveThread(
    $1.GetArchiveThreadRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getArchiveThread, request, options: options);
  }

  $grpc.ResponseFuture<$1.FindMessageResponse> findMessage(
    $1.FindMessageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$findMessage, request, options: options);
  }

  $grpc.ResponseFuture<$1.Message> getMessage(
    $1.MessageReference request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMessage, request, options: options);
  }

  $grpc.ResponseFuture<$1.PersonalMessageFilterSet> getPersonalMessageFilters(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getPersonalMessageFilters, request,
        options: options);
  }

  $grpc.ResponseFuture<$1.ReplacePersonalMessageFiltersResponse>
      replacePersonalMessageFilters(
    $1.ReplacePersonalMessageFiltersRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$replacePersonalMessageFilters, request,
        options: options);
  }

  $grpc.ResponseFuture<$1.MessagePresentation> getMessagePresentation(
    $1.GetMessagePresentationRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMessagePresentation, request,
        options: options);
  }

  $grpc.ResponseFuture<$1.MessageTechnicalData> getMessageTechnicalData(
    $1.MessageReference request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getMessageTechnicalData, request,
        options: options);
  }

  $grpc.ResponseFuture<$1.MessagePreview> previewMessage(
    $1.CreateMessageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$previewMessage, request, options: options);
  }

  $grpc.ResponseFuture<$1.CreateMessageResponse> createMessage(
    $1.CreateMessageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createMessage, request, options: options);
  }

  $grpc.ResponseFuture<$1.CreateCrosspostResponse> createCrosspost(
    $1.CreateCrosspostRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$createCrosspost, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> markRead(
    $1.MessageReference request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$markRead, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> markUnread(
    $1.MessageReference request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$markUnread, request, options: options);
  }

  $grpc.ResponseFuture<$1.MarkConferenceReadResponse> markConferenceRead(
    $1.MarkConferenceReadRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$markConferenceRead, request, options: options);
  }

  $grpc.ResponseFuture<$1.ListMessagesResponse> getThread(
    $1.GetThreadRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getThread, request, options: options);
  }

  $grpc.ResponseFuture<$1.ListBookmarksResponse> listBookmarks(
    $1.PageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listBookmarks, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> addBookmark(
    $1.GetConferenceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$addBookmark, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> removeBookmark(
    $1.GetConferenceRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$removeBookmark, request, options: options);
  }

  $grpc.ResponseFuture<$1.ListHistoryResponse> listHistory(
    $1.PageRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$listHistory, request, options: options);
  }

  $grpc.ResponseFuture<$0.Empty> clearHistory(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$clearHistory, request, options: options);
  }

  $grpc.ResponseFuture<$1.Profile> getProfile(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getProfile, request, options: options);
  }

  $grpc.ResponseFuture<$1.UueLimits> getUueLimits(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getUueLimits, request, options: options);
  }

  $grpc.ResponseFuture<$1.SearchUuePartsResponse> searchUueParts(
    $1.SearchUuePartsRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$searchUueParts, request, options: options);
  }

  $grpc.ResponseFuture<$1.UueAttachment> assembleUue(
    $1.AssembleUueRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$assembleUue, request, options: options);
  }

  $grpc.ResponseFuture<$1.UueChunk> getUueChunk(
    $1.GetUueChunkRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getUueChunk, request, options: options);
  }

  $grpc.ResponseFuture<$1.UueUploadStatus> uploadUueChunk(
    $1.UploadUueChunkRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$uploadUueChunk, request, options: options);
  }

  $grpc.ResponseFuture<$1.UueSendStatus> commitUue(
    $1.CommitUueRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$commitUue, request, options: options);
  }

  $grpc.ResponseFuture<$1.UueSendStatus> getUueSendStatus(
    $1.UueOperationReference request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getUueSendStatus, request, options: options);
  }

  // method descriptors

  static final _$getServerCapabilities =
      $grpc.ClientMethod<$0.Empty, $1.ServerCapabilities>(
          '/ffido.v1.Ffido/GetServerCapabilities',
          ($0.Empty value) => value.writeToBuffer(),
          $1.ServerCapabilities.fromBuffer);
  static final _$listTelegramProfiles =
      $grpc.ClientMethod<$1.TelegramProof, $1.TelegramProfiles>(
          '/ffido.v1.Ffido/ListTelegramProfiles',
          ($1.TelegramProof value) => value.writeToBuffer(),
          $1.TelegramProfiles.fromBuffer);
  static final _$loginWithTelegram =
      $grpc.ClientMethod<$1.TelegramLoginRequest, $1.LoginResponse>(
          '/ffido.v1.Ffido/LoginWithTelegram',
          ($1.TelegramLoginRequest value) => value.writeToBuffer(),
          $1.LoginResponse.fromBuffer);
  static final _$bindTelegram =
      $grpc.ClientMethod<$1.BindTelegramRequest, $1.TelegramBinding>(
          '/ffido.v1.Ffido/BindTelegram',
          ($1.BindTelegramRequest value) => value.writeToBuffer(),
          $1.TelegramBinding.fromBuffer);
  static final _$getTelegramBinding =
      $grpc.ClientMethod<$0.Empty, $1.TelegramBinding>(
          '/ffido.v1.Ffido/GetTelegramBinding',
          ($0.Empty value) => value.writeToBuffer(),
          $1.TelegramBinding.fromBuffer);
  static final _$unbindTelegram = $grpc.ClientMethod<$0.Empty, $0.Empty>(
      '/ffido.v1.Ffido/UnbindTelegram',
      ($0.Empty value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$login = $grpc.ClientMethod<$1.LoginRequest, $1.LoginResponse>(
      '/ffido.v1.Ffido/Login',
      ($1.LoginRequest value) => value.writeToBuffer(),
      $1.LoginResponse.fromBuffer);
  static final _$restoreSession = $grpc.ClientMethod<$0.Empty, $1.SessionInfo>(
      '/ffido.v1.Ffido/RestoreSession',
      ($0.Empty value) => value.writeToBuffer(),
      $1.SessionInfo.fromBuffer);
  static final _$logout = $grpc.ClientMethod<$0.Empty, $0.Empty>(
      '/ffido.v1.Ffido/Logout',
      ($0.Empty value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$listConferences =
      $grpc.ClientMethod<$1.ListConferencesRequest, $1.ListConferencesResponse>(
          '/ffido.v1.Ffido/ListConferences',
          ($1.ListConferencesRequest value) => value.writeToBuffer(),
          $1.ListConferencesResponse.fromBuffer);
  static final _$getConference =
      $grpc.ClientMethod<$1.GetConferenceRequest, $1.Conference>(
          '/ffido.v1.Ffido/GetConference',
          ($1.GetConferenceRequest value) => value.writeToBuffer(),
          $1.Conference.fromBuffer);
  static final _$listMessages =
      $grpc.ClientMethod<$1.ListMessagesRequest, $1.ListMessagesResponse>(
          '/ffido.v1.Ffido/ListMessages',
          ($1.ListMessagesRequest value) => value.writeToBuffer(),
          $1.ListMessagesResponse.fromBuffer);
  static final _$searchArchiveMessages = $grpc.ClientMethod<
          $1.SearchArchiveMessagesRequest, $1.SearchArchiveMessagesResponse>(
      '/ffido.v1.Ffido/SearchArchiveMessages',
      ($1.SearchArchiveMessagesRequest value) => value.writeToBuffer(),
      $1.SearchArchiveMessagesResponse.fromBuffer);
  static final _$readArchiveMessage = $grpc.ClientMethod<
          $1.ReadArchiveMessageRequest, $1.ReadArchiveMessageResponse>(
      '/ffido.v1.Ffido/ReadArchiveMessage',
      ($1.ReadArchiveMessageRequest value) => value.writeToBuffer(),
      $1.ReadArchiveMessageResponse.fromBuffer);
  static final _$getArchiveThread =
      $grpc.ClientMethod<$1.GetArchiveThreadRequest, $1.ListMessagesResponse>(
          '/ffido.v1.Ffido/GetArchiveThread',
          ($1.GetArchiveThreadRequest value) => value.writeToBuffer(),
          $1.ListMessagesResponse.fromBuffer);
  static final _$findMessage =
      $grpc.ClientMethod<$1.FindMessageRequest, $1.FindMessageResponse>(
          '/ffido.v1.Ffido/FindMessage',
          ($1.FindMessageRequest value) => value.writeToBuffer(),
          $1.FindMessageResponse.fromBuffer);
  static final _$getMessage =
      $grpc.ClientMethod<$1.MessageReference, $1.Message>(
          '/ffido.v1.Ffido/GetMessage',
          ($1.MessageReference value) => value.writeToBuffer(),
          $1.Message.fromBuffer);
  static final _$getPersonalMessageFilters =
      $grpc.ClientMethod<$0.Empty, $1.PersonalMessageFilterSet>(
          '/ffido.v1.Ffido/GetPersonalMessageFilters',
          ($0.Empty value) => value.writeToBuffer(),
          $1.PersonalMessageFilterSet.fromBuffer);
  static final _$replacePersonalMessageFilters = $grpc.ClientMethod<
          $1.ReplacePersonalMessageFiltersRequest,
          $1.ReplacePersonalMessageFiltersResponse>(
      '/ffido.v1.Ffido/ReplacePersonalMessageFilters',
      ($1.ReplacePersonalMessageFiltersRequest value) => value.writeToBuffer(),
      $1.ReplacePersonalMessageFiltersResponse.fromBuffer);
  static final _$getMessagePresentation = $grpc.ClientMethod<
          $1.GetMessagePresentationRequest, $1.MessagePresentation>(
      '/ffido.v1.Ffido/GetMessagePresentation',
      ($1.GetMessagePresentationRequest value) => value.writeToBuffer(),
      $1.MessagePresentation.fromBuffer);
  static final _$getMessageTechnicalData =
      $grpc.ClientMethod<$1.MessageReference, $1.MessageTechnicalData>(
          '/ffido.v1.Ffido/GetMessageTechnicalData',
          ($1.MessageReference value) => value.writeToBuffer(),
          $1.MessageTechnicalData.fromBuffer);
  static final _$previewMessage =
      $grpc.ClientMethod<$1.CreateMessageRequest, $1.MessagePreview>(
          '/ffido.v1.Ffido/PreviewMessage',
          ($1.CreateMessageRequest value) => value.writeToBuffer(),
          $1.MessagePreview.fromBuffer);
  static final _$createMessage =
      $grpc.ClientMethod<$1.CreateMessageRequest, $1.CreateMessageResponse>(
          '/ffido.v1.Ffido/CreateMessage',
          ($1.CreateMessageRequest value) => value.writeToBuffer(),
          $1.CreateMessageResponse.fromBuffer);
  static final _$createCrosspost =
      $grpc.ClientMethod<$1.CreateCrosspostRequest, $1.CreateCrosspostResponse>(
          '/ffido.v1.Ffido/CreateCrosspost',
          ($1.CreateCrosspostRequest value) => value.writeToBuffer(),
          $1.CreateCrosspostResponse.fromBuffer);
  static final _$markRead = $grpc.ClientMethod<$1.MessageReference, $0.Empty>(
      '/ffido.v1.Ffido/MarkRead',
      ($1.MessageReference value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$markUnread = $grpc.ClientMethod<$1.MessageReference, $0.Empty>(
      '/ffido.v1.Ffido/MarkUnread',
      ($1.MessageReference value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$markConferenceRead = $grpc.ClientMethod<
          $1.MarkConferenceReadRequest, $1.MarkConferenceReadResponse>(
      '/ffido.v1.Ffido/MarkConferenceRead',
      ($1.MarkConferenceReadRequest value) => value.writeToBuffer(),
      $1.MarkConferenceReadResponse.fromBuffer);
  static final _$getThread =
      $grpc.ClientMethod<$1.GetThreadRequest, $1.ListMessagesResponse>(
          '/ffido.v1.Ffido/GetThread',
          ($1.GetThreadRequest value) => value.writeToBuffer(),
          $1.ListMessagesResponse.fromBuffer);
  static final _$listBookmarks =
      $grpc.ClientMethod<$1.PageRequest, $1.ListBookmarksResponse>(
          '/ffido.v1.Ffido/ListBookmarks',
          ($1.PageRequest value) => value.writeToBuffer(),
          $1.ListBookmarksResponse.fromBuffer);
  static final _$addBookmark =
      $grpc.ClientMethod<$1.GetConferenceRequest, $0.Empty>(
          '/ffido.v1.Ffido/AddBookmark',
          ($1.GetConferenceRequest value) => value.writeToBuffer(),
          $0.Empty.fromBuffer);
  static final _$removeBookmark =
      $grpc.ClientMethod<$1.GetConferenceRequest, $0.Empty>(
          '/ffido.v1.Ffido/RemoveBookmark',
          ($1.GetConferenceRequest value) => value.writeToBuffer(),
          $0.Empty.fromBuffer);
  static final _$listHistory =
      $grpc.ClientMethod<$1.PageRequest, $1.ListHistoryResponse>(
          '/ffido.v1.Ffido/ListHistory',
          ($1.PageRequest value) => value.writeToBuffer(),
          $1.ListHistoryResponse.fromBuffer);
  static final _$clearHistory = $grpc.ClientMethod<$0.Empty, $0.Empty>(
      '/ffido.v1.Ffido/ClearHistory',
      ($0.Empty value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$getProfile = $grpc.ClientMethod<$0.Empty, $1.Profile>(
      '/ffido.v1.Ffido/GetProfile',
      ($0.Empty value) => value.writeToBuffer(),
      $1.Profile.fromBuffer);
  static final _$getUueLimits = $grpc.ClientMethod<$0.Empty, $1.UueLimits>(
      '/ffido.v1.Ffido/GetUueLimits',
      ($0.Empty value) => value.writeToBuffer(),
      $1.UueLimits.fromBuffer);
  static final _$searchUueParts =
      $grpc.ClientMethod<$1.SearchUuePartsRequest, $1.SearchUuePartsResponse>(
          '/ffido.v1.Ffido/SearchUueParts',
          ($1.SearchUuePartsRequest value) => value.writeToBuffer(),
          $1.SearchUuePartsResponse.fromBuffer);
  static final _$assembleUue =
      $grpc.ClientMethod<$1.AssembleUueRequest, $1.UueAttachment>(
          '/ffido.v1.Ffido/AssembleUue',
          ($1.AssembleUueRequest value) => value.writeToBuffer(),
          $1.UueAttachment.fromBuffer);
  static final _$getUueChunk =
      $grpc.ClientMethod<$1.GetUueChunkRequest, $1.UueChunk>(
          '/ffido.v1.Ffido/GetUueChunk',
          ($1.GetUueChunkRequest value) => value.writeToBuffer(),
          $1.UueChunk.fromBuffer);
  static final _$uploadUueChunk =
      $grpc.ClientMethod<$1.UploadUueChunkRequest, $1.UueUploadStatus>(
          '/ffido.v1.Ffido/UploadUueChunk',
          ($1.UploadUueChunkRequest value) => value.writeToBuffer(),
          $1.UueUploadStatus.fromBuffer);
  static final _$commitUue =
      $grpc.ClientMethod<$1.CommitUueRequest, $1.UueSendStatus>(
          '/ffido.v1.Ffido/CommitUue',
          ($1.CommitUueRequest value) => value.writeToBuffer(),
          $1.UueSendStatus.fromBuffer);
  static final _$getUueSendStatus =
      $grpc.ClientMethod<$1.UueOperationReference, $1.UueSendStatus>(
          '/ffido.v1.Ffido/GetUueSendStatus',
          ($1.UueOperationReference value) => value.writeToBuffer(),
          $1.UueSendStatus.fromBuffer);
}

@$pb.GrpcServiceName('ffido.v1.Ffido')
abstract class FfidoServiceBase extends $grpc.Service {
  $core.String get $name => 'ffido.v1.Ffido';

  FfidoServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Empty, $1.ServerCapabilities>(
        'GetServerCapabilities',
        getServerCapabilities_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($1.ServerCapabilities value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.TelegramProof, $1.TelegramProfiles>(
        'ListTelegramProfiles',
        listTelegramProfiles_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.TelegramProof.fromBuffer(value),
        ($1.TelegramProfiles value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.TelegramLoginRequest, $1.LoginResponse>(
        'LoginWithTelegram',
        loginWithTelegram_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.TelegramLoginRequest.fromBuffer(value),
        ($1.LoginResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.BindTelegramRequest, $1.TelegramBinding>(
        'BindTelegram',
        bindTelegram_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.BindTelegramRequest.fromBuffer(value),
        ($1.TelegramBinding value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $1.TelegramBinding>(
        'GetTelegramBinding',
        getTelegramBinding_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($1.TelegramBinding value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.Empty>(
        'UnbindTelegram',
        unbindTelegram_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.LoginRequest, $1.LoginResponse>(
        'Login',
        login_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.LoginRequest.fromBuffer(value),
        ($1.LoginResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $1.SessionInfo>(
        'RestoreSession',
        restoreSession_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($1.SessionInfo value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.Empty>(
        'Logout',
        logout_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.ListConferencesRequest,
            $1.ListConferencesResponse>(
        'ListConferences',
        listConferences_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.ListConferencesRequest.fromBuffer(value),
        ($1.ListConferencesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.GetConferenceRequest, $1.Conference>(
        'GetConference',
        getConference_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.GetConferenceRequest.fromBuffer(value),
        ($1.Conference value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$1.ListMessagesRequest, $1.ListMessagesResponse>(
            'ListMessages',
            listMessages_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $1.ListMessagesRequest.fromBuffer(value),
            ($1.ListMessagesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.SearchArchiveMessagesRequest,
            $1.SearchArchiveMessagesResponse>(
        'SearchArchiveMessages',
        searchArchiveMessages_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.SearchArchiveMessagesRequest.fromBuffer(value),
        ($1.SearchArchiveMessagesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.ReadArchiveMessageRequest,
            $1.ReadArchiveMessageResponse>(
        'ReadArchiveMessage',
        readArchiveMessage_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.ReadArchiveMessageRequest.fromBuffer(value),
        ($1.ReadArchiveMessageResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.GetArchiveThreadRequest,
            $1.ListMessagesResponse>(
        'GetArchiveThread',
        getArchiveThread_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.GetArchiveThreadRequest.fromBuffer(value),
        ($1.ListMessagesResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$1.FindMessageRequest, $1.FindMessageResponse>(
            'FindMessage',
            findMessage_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $1.FindMessageRequest.fromBuffer(value),
            ($1.FindMessageResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.MessageReference, $1.Message>(
        'GetMessage',
        getMessage_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.MessageReference.fromBuffer(value),
        ($1.Message value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $1.PersonalMessageFilterSet>(
        'GetPersonalMessageFilters',
        getPersonalMessageFilters_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($1.PersonalMessageFilterSet value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.ReplacePersonalMessageFiltersRequest,
            $1.ReplacePersonalMessageFiltersResponse>(
        'ReplacePersonalMessageFilters',
        replacePersonalMessageFilters_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.ReplacePersonalMessageFiltersRequest.fromBuffer(value),
        ($1.ReplacePersonalMessageFiltersResponse value) =>
            value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.GetMessagePresentationRequest,
            $1.MessagePresentation>(
        'GetMessagePresentation',
        getMessagePresentation_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.GetMessagePresentationRequest.fromBuffer(value),
        ($1.MessagePresentation value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$1.MessageReference, $1.MessageTechnicalData>(
            'GetMessageTechnicalData',
            getMessageTechnicalData_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $1.MessageReference.fromBuffer(value),
            ($1.MessageTechnicalData value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.CreateMessageRequest, $1.MessagePreview>(
        'PreviewMessage',
        previewMessage_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.CreateMessageRequest.fromBuffer(value),
        ($1.MessagePreview value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$1.CreateMessageRequest, $1.CreateMessageResponse>(
            'CreateMessage',
            createMessage_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $1.CreateMessageRequest.fromBuffer(value),
            ($1.CreateMessageResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.CreateCrosspostRequest,
            $1.CreateCrosspostResponse>(
        'CreateCrosspost',
        createCrosspost_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.CreateCrosspostRequest.fromBuffer(value),
        ($1.CreateCrosspostResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.MessageReference, $0.Empty>(
        'MarkRead',
        markRead_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.MessageReference.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.MessageReference, $0.Empty>(
        'MarkUnread',
        markUnread_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.MessageReference.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.MarkConferenceReadRequest,
            $1.MarkConferenceReadResponse>(
        'MarkConferenceRead',
        markConferenceRead_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.MarkConferenceReadRequest.fromBuffer(value),
        ($1.MarkConferenceReadResponse value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$1.GetThreadRequest, $1.ListMessagesResponse>(
            'GetThread',
            getThread_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $1.GetThreadRequest.fromBuffer(value),
            ($1.ListMessagesResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.PageRequest, $1.ListBookmarksResponse>(
        'ListBookmarks',
        listBookmarks_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.PageRequest.fromBuffer(value),
        ($1.ListBookmarksResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.GetConferenceRequest, $0.Empty>(
        'AddBookmark',
        addBookmark_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.GetConferenceRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.GetConferenceRequest, $0.Empty>(
        'RemoveBookmark',
        removeBookmark_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.GetConferenceRequest.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.PageRequest, $1.ListHistoryResponse>(
        'ListHistory',
        listHistory_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.PageRequest.fromBuffer(value),
        ($1.ListHistoryResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.Empty>(
        'ClearHistory',
        clearHistory_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $1.Profile>(
        'GetProfile',
        getProfile_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($1.Profile value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $1.UueLimits>(
        'GetUueLimits',
        getUueLimits_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($1.UueLimits value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.SearchUuePartsRequest,
            $1.SearchUuePartsResponse>(
        'SearchUueParts',
        searchUueParts_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.SearchUuePartsRequest.fromBuffer(value),
        ($1.SearchUuePartsResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.AssembleUueRequest, $1.UueAttachment>(
        'AssembleUue',
        assembleUue_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.AssembleUueRequest.fromBuffer(value),
        ($1.UueAttachment value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.GetUueChunkRequest, $1.UueChunk>(
        'GetUueChunk',
        getUueChunk_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.GetUueChunkRequest.fromBuffer(value),
        ($1.UueChunk value) => value.writeToBuffer()));
    $addMethod(
        $grpc.ServiceMethod<$1.UploadUueChunkRequest, $1.UueUploadStatus>(
            'UploadUueChunk',
            uploadUueChunk_Pre,
            false,
            false,
            ($core.List<$core.int> value) =>
                $1.UploadUueChunkRequest.fromBuffer(value),
            ($1.UueUploadStatus value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.CommitUueRequest, $1.UueSendStatus>(
        'CommitUue',
        commitUue_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.CommitUueRequest.fromBuffer(value),
        ($1.UueSendStatus value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.UueOperationReference, $1.UueSendStatus>(
        'GetUueSendStatus',
        getUueSendStatus_Pre,
        false,
        false,
        ($core.List<$core.int> value) =>
            $1.UueOperationReference.fromBuffer(value),
        ($1.UueSendStatus value) => value.writeToBuffer()));
  }

  $async.Future<$1.ServerCapabilities> getServerCapabilities_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return getServerCapabilities($call, await $request);
  }

  $async.Future<$1.ServerCapabilities> getServerCapabilities(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Future<$1.TelegramProfiles> listTelegramProfiles_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.TelegramProof> $request) async {
    return listTelegramProfiles($call, await $request);
  }

  $async.Future<$1.TelegramProfiles> listTelegramProfiles(
      $grpc.ServiceCall call, $1.TelegramProof request);

  $async.Future<$1.LoginResponse> loginWithTelegram_Pre($grpc.ServiceCall $call,
      $async.Future<$1.TelegramLoginRequest> $request) async {
    return loginWithTelegram($call, await $request);
  }

  $async.Future<$1.LoginResponse> loginWithTelegram(
      $grpc.ServiceCall call, $1.TelegramLoginRequest request);

  $async.Future<$1.TelegramBinding> bindTelegram_Pre($grpc.ServiceCall $call,
      $async.Future<$1.BindTelegramRequest> $request) async {
    return bindTelegram($call, await $request);
  }

  $async.Future<$1.TelegramBinding> bindTelegram(
      $grpc.ServiceCall call, $1.BindTelegramRequest request);

  $async.Future<$1.TelegramBinding> getTelegramBinding_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return getTelegramBinding($call, await $request);
  }

  $async.Future<$1.TelegramBinding> getTelegramBinding(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Future<$0.Empty> unbindTelegram_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return unbindTelegram($call, await $request);
  }

  $async.Future<$0.Empty> unbindTelegram(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Future<$1.LoginResponse> login_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.LoginRequest> $request) async {
    return login($call, await $request);
  }

  $async.Future<$1.LoginResponse> login(
      $grpc.ServiceCall call, $1.LoginRequest request);

  $async.Future<$1.SessionInfo> restoreSession_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return restoreSession($call, await $request);
  }

  $async.Future<$1.SessionInfo> restoreSession(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Future<$0.Empty> logout_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return logout($call, await $request);
  }

  $async.Future<$0.Empty> logout($grpc.ServiceCall call, $0.Empty request);

  $async.Future<$1.ListConferencesResponse> listConferences_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.ListConferencesRequest> $request) async {
    return listConferences($call, await $request);
  }

  $async.Future<$1.ListConferencesResponse> listConferences(
      $grpc.ServiceCall call, $1.ListConferencesRequest request);

  $async.Future<$1.Conference> getConference_Pre($grpc.ServiceCall $call,
      $async.Future<$1.GetConferenceRequest> $request) async {
    return getConference($call, await $request);
  }

  $async.Future<$1.Conference> getConference(
      $grpc.ServiceCall call, $1.GetConferenceRequest request);

  $async.Future<$1.ListMessagesResponse> listMessages_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.ListMessagesRequest> $request) async {
    return listMessages($call, await $request);
  }

  $async.Future<$1.ListMessagesResponse> listMessages(
      $grpc.ServiceCall call, $1.ListMessagesRequest request);

  $async.Future<$1.SearchArchiveMessagesResponse> searchArchiveMessages_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.SearchArchiveMessagesRequest> $request) async {
    return searchArchiveMessages($call, await $request);
  }

  $async.Future<$1.SearchArchiveMessagesResponse> searchArchiveMessages(
      $grpc.ServiceCall call, $1.SearchArchiveMessagesRequest request);

  $async.Future<$1.ReadArchiveMessageResponse> readArchiveMessage_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.ReadArchiveMessageRequest> $request) async {
    return readArchiveMessage($call, await $request);
  }

  $async.Future<$1.ReadArchiveMessageResponse> readArchiveMessage(
      $grpc.ServiceCall call, $1.ReadArchiveMessageRequest request);

  $async.Future<$1.ListMessagesResponse> getArchiveThread_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.GetArchiveThreadRequest> $request) async {
    return getArchiveThread($call, await $request);
  }

  $async.Future<$1.ListMessagesResponse> getArchiveThread(
      $grpc.ServiceCall call, $1.GetArchiveThreadRequest request);

  $async.Future<$1.FindMessageResponse> findMessage_Pre($grpc.ServiceCall $call,
      $async.Future<$1.FindMessageRequest> $request) async {
    return findMessage($call, await $request);
  }

  $async.Future<$1.FindMessageResponse> findMessage(
      $grpc.ServiceCall call, $1.FindMessageRequest request);

  $async.Future<$1.Message> getMessage_Pre($grpc.ServiceCall $call,
      $async.Future<$1.MessageReference> $request) async {
    return getMessage($call, await $request);
  }

  $async.Future<$1.Message> getMessage(
      $grpc.ServiceCall call, $1.MessageReference request);

  $async.Future<$1.PersonalMessageFilterSet> getPersonalMessageFilters_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return getPersonalMessageFilters($call, await $request);
  }

  $async.Future<$1.PersonalMessageFilterSet> getPersonalMessageFilters(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Future<$1.ReplacePersonalMessageFiltersResponse>
      replacePersonalMessageFilters_Pre(
          $grpc.ServiceCall $call,
          $async.Future<$1.ReplacePersonalMessageFiltersRequest>
              $request) async {
    return replacePersonalMessageFilters($call, await $request);
  }

  $async.Future<$1.ReplacePersonalMessageFiltersResponse>
      replacePersonalMessageFilters($grpc.ServiceCall call,
          $1.ReplacePersonalMessageFiltersRequest request);

  $async.Future<$1.MessagePresentation> getMessagePresentation_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.GetMessagePresentationRequest> $request) async {
    return getMessagePresentation($call, await $request);
  }

  $async.Future<$1.MessagePresentation> getMessagePresentation(
      $grpc.ServiceCall call, $1.GetMessagePresentationRequest request);

  $async.Future<$1.MessageTechnicalData> getMessageTechnicalData_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.MessageReference> $request) async {
    return getMessageTechnicalData($call, await $request);
  }

  $async.Future<$1.MessageTechnicalData> getMessageTechnicalData(
      $grpc.ServiceCall call, $1.MessageReference request);

  $async.Future<$1.MessagePreview> previewMessage_Pre($grpc.ServiceCall $call,
      $async.Future<$1.CreateMessageRequest> $request) async {
    return previewMessage($call, await $request);
  }

  $async.Future<$1.MessagePreview> previewMessage(
      $grpc.ServiceCall call, $1.CreateMessageRequest request);

  $async.Future<$1.CreateMessageResponse> createMessage_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.CreateMessageRequest> $request) async {
    return createMessage($call, await $request);
  }

  $async.Future<$1.CreateMessageResponse> createMessage(
      $grpc.ServiceCall call, $1.CreateMessageRequest request);

  $async.Future<$1.CreateCrosspostResponse> createCrosspost_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.CreateCrosspostRequest> $request) async {
    return createCrosspost($call, await $request);
  }

  $async.Future<$1.CreateCrosspostResponse> createCrosspost(
      $grpc.ServiceCall call, $1.CreateCrosspostRequest request);

  $async.Future<$0.Empty> markRead_Pre($grpc.ServiceCall $call,
      $async.Future<$1.MessageReference> $request) async {
    return markRead($call, await $request);
  }

  $async.Future<$0.Empty> markRead(
      $grpc.ServiceCall call, $1.MessageReference request);

  $async.Future<$0.Empty> markUnread_Pre($grpc.ServiceCall $call,
      $async.Future<$1.MessageReference> $request) async {
    return markUnread($call, await $request);
  }

  $async.Future<$0.Empty> markUnread(
      $grpc.ServiceCall call, $1.MessageReference request);

  $async.Future<$1.MarkConferenceReadResponse> markConferenceRead_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.MarkConferenceReadRequest> $request) async {
    return markConferenceRead($call, await $request);
  }

  $async.Future<$1.MarkConferenceReadResponse> markConferenceRead(
      $grpc.ServiceCall call, $1.MarkConferenceReadRequest request);

  $async.Future<$1.ListMessagesResponse> getThread_Pre($grpc.ServiceCall $call,
      $async.Future<$1.GetThreadRequest> $request) async {
    return getThread($call, await $request);
  }

  $async.Future<$1.ListMessagesResponse> getThread(
      $grpc.ServiceCall call, $1.GetThreadRequest request);

  $async.Future<$1.ListBookmarksResponse> listBookmarks_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.PageRequest> $request) async {
    return listBookmarks($call, await $request);
  }

  $async.Future<$1.ListBookmarksResponse> listBookmarks(
      $grpc.ServiceCall call, $1.PageRequest request);

  $async.Future<$0.Empty> addBookmark_Pre($grpc.ServiceCall $call,
      $async.Future<$1.GetConferenceRequest> $request) async {
    return addBookmark($call, await $request);
  }

  $async.Future<$0.Empty> addBookmark(
      $grpc.ServiceCall call, $1.GetConferenceRequest request);

  $async.Future<$0.Empty> removeBookmark_Pre($grpc.ServiceCall $call,
      $async.Future<$1.GetConferenceRequest> $request) async {
    return removeBookmark($call, await $request);
  }

  $async.Future<$0.Empty> removeBookmark(
      $grpc.ServiceCall call, $1.GetConferenceRequest request);

  $async.Future<$1.ListHistoryResponse> listHistory_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.PageRequest> $request) async {
    return listHistory($call, await $request);
  }

  $async.Future<$1.ListHistoryResponse> listHistory(
      $grpc.ServiceCall call, $1.PageRequest request);

  $async.Future<$0.Empty> clearHistory_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return clearHistory($call, await $request);
  }

  $async.Future<$0.Empty> clearHistory(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Future<$1.Profile> getProfile_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return getProfile($call, await $request);
  }

  $async.Future<$1.Profile> getProfile(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Future<$1.UueLimits> getUueLimits_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return getUueLimits($call, await $request);
  }

  $async.Future<$1.UueLimits> getUueLimits(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Future<$1.SearchUuePartsResponse> searchUueParts_Pre(
      $grpc.ServiceCall $call,
      $async.Future<$1.SearchUuePartsRequest> $request) async {
    return searchUueParts($call, await $request);
  }

  $async.Future<$1.SearchUuePartsResponse> searchUueParts(
      $grpc.ServiceCall call, $1.SearchUuePartsRequest request);

  $async.Future<$1.UueAttachment> assembleUue_Pre($grpc.ServiceCall $call,
      $async.Future<$1.AssembleUueRequest> $request) async {
    return assembleUue($call, await $request);
  }

  $async.Future<$1.UueAttachment> assembleUue(
      $grpc.ServiceCall call, $1.AssembleUueRequest request);

  $async.Future<$1.UueChunk> getUueChunk_Pre($grpc.ServiceCall $call,
      $async.Future<$1.GetUueChunkRequest> $request) async {
    return getUueChunk($call, await $request);
  }

  $async.Future<$1.UueChunk> getUueChunk(
      $grpc.ServiceCall call, $1.GetUueChunkRequest request);

  $async.Future<$1.UueUploadStatus> uploadUueChunk_Pre($grpc.ServiceCall $call,
      $async.Future<$1.UploadUueChunkRequest> $request) async {
    return uploadUueChunk($call, await $request);
  }

  $async.Future<$1.UueUploadStatus> uploadUueChunk(
      $grpc.ServiceCall call, $1.UploadUueChunkRequest request);

  $async.Future<$1.UueSendStatus> commitUue_Pre($grpc.ServiceCall $call,
      $async.Future<$1.CommitUueRequest> $request) async {
    return commitUue($call, await $request);
  }

  $async.Future<$1.UueSendStatus> commitUue(
      $grpc.ServiceCall call, $1.CommitUueRequest request);

  $async.Future<$1.UueSendStatus> getUueSendStatus_Pre($grpc.ServiceCall $call,
      $async.Future<$1.UueOperationReference> $request) async {
    return getUueSendStatus($call, await $request);
  }

  $async.Future<$1.UueSendStatus> getUueSendStatus(
      $grpc.ServiceCall call, $1.UueOperationReference request);
}
