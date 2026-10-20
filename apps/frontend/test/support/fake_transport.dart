import 'dart:async';

import 'package:fido/api/api_transport.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';

class FakeTransport implements ApiTransport {
  @override
  int epoch = 0;
  @override
  bool hasToken = true;
  @override
  Uri endpoint = Uri.parse('https://test.invalid');
  @override
  String get cacheScope => '$endpoint:$epoch';
  final changes = StreamController<int>.broadcast(sync: true);
  @override
  Stream<int> get sessionChanges => changes.stream;
  void switchSession({bool authenticated = true}) {
    epoch++;
    hasToken = authenticated;
    changes.add(epoch);
  }

  Future<void> dispose() => changes.close();
  Future<wire.ListConferencesResponse> Function(wire.ListConferencesRequest)?
  conferences;
  Future<wire.Conference> Function(wire.GetConferenceRequest)? conference;
  Future<wire.Message> Function(wire.MessageReference)? message;
  Future<wire.ListMessagesResponse> Function(wire.ListMessagesRequest)?
  messages;
  Future<wire.CreateMessageResponse> Function(wire.CreateMessageRequest)?
  create;
  Future<wire.Profile> Function()? profile;
  Future<wire.ListBookmarksResponse> Function(wire.PageRequest)? bookmarks;
  Future<wire.ListHistoryResponse> Function(wire.PageRequest)? history;
  Future<Empty> Function()? clear;
  Future<Empty> Function(wire.GetConferenceRequest)? add;
  Future<Empty> Function(wire.GetConferenceRequest)? remove;
  Future<wire.ListMessagesResponse> Function(wire.GetThreadRequest)? thread;
  Future<wire.MarkConferenceReadResponse> Function(
    wire.MarkConferenceReadRequest,
  )?
  bulkRead;
  @override
  Future<wire.MarkConferenceReadResponse> markConferenceRead(
    wire.MarkConferenceReadRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return bulkRead == null ? wire.MarkConferenceReadResponse() : bulkRead!(r);
  }

  final calls = <Object>[];
  @override
  Future<wire.ListConferencesResponse> listConferences(
    wire.ListConferencesRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return conferences == null
        ? wire.ListConferencesResponse()
        : conferences!(r);
  }

  @override
  Future<wire.Conference> getConference(
    wire.GetConferenceRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    if (conference != null) return conference!(r);
    throw const NotFoundException();
  }

  @override
  Future<wire.ListMessagesResponse> listMessages(
    wire.ListMessagesRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return messages == null ? wire.ListMessagesResponse() : messages!(r);
  }

  @override
  Future<wire.Message> getMessage(
    wire.MessageReference r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return message == null ? wire.Message() : message!(r);
  }

  @override
  Future<wire.CreateMessageResponse> createMessage(
    wire.CreateMessageRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return create == null
        ? wire.CreateMessageResponse(
            status: wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY,
            message: wire.MessageReference(messageId: 'saved'),
          )
        : create!(r);
  }

  @override
  Future<Empty> markRead(
    wire.MessageReference r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return Empty();
  }

  @override
  Future<wire.ListMessagesResponse> getThread(
    wire.GetThreadRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return thread == null ? wire.ListMessagesResponse() : thread!(r);
  }

  @override
  Future<wire.ListBookmarksResponse> listBookmarks(
    wire.PageRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return bookmarks == null ? wire.ListBookmarksResponse() : bookmarks!(r);
  }

  @override
  Future<Empty> addBookmark(
    wire.GetConferenceRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return add == null ? Empty() : add!(r);
  }

  @override
  Future<Empty> removeBookmark(
    wire.GetConferenceRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return remove == null ? Empty() : remove!(r);
  }

  @override
  Future<wire.ListHistoryResponse> listHistory(
    wire.PageRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    return history == null ? wire.ListHistoryResponse() : history!(r);
  }

  @override
  Future<Empty> clearHistory({RpcCancellation? cancellation}) async {
    return clear == null ? Empty() : clear!();
  }

  @override
  Future<wire.Profile> getProfile({RpcCancellation? cancellation}) async {
    return profile == null
        ? wire.Profile(name: 'Реальный профиль', address: '2:1/2')
        : profile!();
  }

  Future<wire.UueLimits> Function(Empty)? getUueLimitsHandler;
  @override
  Future<wire.UueLimits> getUueLimits(
    Empty r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    if (getUueLimitsHandler != null) return getUueLimitsHandler!(r);
    throw const ApiException(message: 'UUE unsupported', statusCode: 12);
  }

  Future<wire.SearchUuePartsResponse> Function(wire.SearchUuePartsRequest)?
  searchUuePartsHandler;
  @override
  Future<wire.SearchUuePartsResponse> searchUueParts(
    wire.SearchUuePartsRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    if (searchUuePartsHandler != null) return searchUuePartsHandler!(r);
    throw const ApiException(message: 'UUE unsupported', statusCode: 12);
  }

  Future<wire.UueAttachment> Function(wire.AssembleUueRequest)?
  assembleUueHandler;
  @override
  Future<wire.UueAttachment> assembleUue(
    wire.AssembleUueRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    if (assembleUueHandler != null) return assembleUueHandler!(r);
    throw const ApiException(message: 'UUE unsupported', statusCode: 12);
  }

  Future<wire.UueChunk> Function(wire.GetUueChunkRequest)? getUueChunkHandler;
  @override
  Future<wire.UueChunk> getUueChunk(
    wire.GetUueChunkRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    if (getUueChunkHandler != null) return getUueChunkHandler!(r);
    throw const ApiException(message: 'UUE unsupported', statusCode: 12);
  }

  Future<wire.UueUploadStatus> Function(wire.UploadUueChunkRequest)?
  uploadUueChunkHandler;
  @override
  Future<wire.UueUploadStatus> uploadUueChunk(
    wire.UploadUueChunkRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    if (uploadUueChunkHandler != null) return uploadUueChunkHandler!(r);
    throw const ApiException(message: 'UUE unsupported', statusCode: 12);
  }

  Future<wire.UueSendStatus> Function(wire.CommitUueRequest)? commitUueHandler;
  @override
  Future<wire.UueSendStatus> commitUue(
    wire.CommitUueRequest r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    if (commitUueHandler != null) return commitUueHandler!(r);
    throw const ApiException(message: 'UUE unsupported', statusCode: 12);
  }

  Future<wire.UueSendStatus> Function(wire.UueOperationReference)?
  getUueSendStatusHandler;
  @override
  Future<wire.UueSendStatus> getUueSendStatus(
    wire.UueOperationReference r, {
    RpcCancellation? cancellation,
  }) async {
    calls.add(r);
    if (getUueSendStatusHandler != null) return getUueSendStatusHandler!(r);
    throw const ApiException(message: 'UUE unsupported', statusCode: 12);
  }
}

wire.ListConferencesResponse conferenceData(String name) =>
    wire.ListConferencesResponse(
      conferences: [
        wire.Conference(
          canRead: true,
          canPost: true,
          id: 'id-$name',
          name: name,
          description: 'description',
        ),
      ],
    );
