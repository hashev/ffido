import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart';

import 'generated/ffido/v1/ffido.pb.dart' as wire;

class RpcCancellation {
  bool _cancelled = false;
  final Set<Future<void> Function()> _callbacks = {};
  bool get isCancelled => _cancelled;
  void add(Future<void> Function() callback) => _callbacks.add(callback);
  void remove(Future<void> Function() callback) => _callbacks.remove(callback);
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await Future.wait(_callbacks.toList().map((callback) => callback()));
    _callbacks.clear();
  }
}

abstract interface class ApiTransport {
  int get epoch;
  Uri get endpoint;
  String get cacheScope;
  bool get hasToken;
  Stream<int> get sessionChanges;
  Future<wire.ListConferencesResponse> listConferences(
    wire.ListConferencesRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.Conference> getConference(
    wire.GetConferenceRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.ListMessagesResponse> listMessages(
    wire.ListMessagesRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.Message> getMessage(
    wire.MessageReference request, {
    RpcCancellation? cancellation,
  });
  Future<wire.CreateCrosspostResponse> createCrosspost(
    wire.CreateCrosspostRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.CreateMessageResponse> createMessage(
    wire.CreateMessageRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.MarkConferenceReadResponse> markConferenceRead(
    wire.MarkConferenceReadRequest request, {
    RpcCancellation? cancellation,
  });
  Future<Empty> markRead(
    wire.MessageReference request, {
    RpcCancellation? cancellation,
  });
  Future<wire.ListMessagesResponse> getThread(
    wire.GetThreadRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.ListBookmarksResponse> listBookmarks(
    wire.PageRequest request, {
    RpcCancellation? cancellation,
  });
  Future<Empty> addBookmark(
    wire.GetConferenceRequest request, {
    RpcCancellation? cancellation,
  });
  Future<Empty> removeBookmark(
    wire.GetConferenceRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.ListHistoryResponse> listHistory(
    wire.PageRequest request, {
    RpcCancellation? cancellation,
  });
  Future<Empty> clearHistory({RpcCancellation? cancellation});
  Future<wire.Profile> getProfile({RpcCancellation? cancellation});
  Future<wire.UueLimits> getUueLimits(
    Empty request, {
    RpcCancellation? cancellation,
  });
  Future<wire.SearchUuePartsResponse> searchUueParts(
    wire.SearchUuePartsRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.UueAttachment> assembleUue(
    wire.AssembleUueRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.UueChunk> getUueChunk(
    wire.GetUueChunkRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.UueUploadStatus> uploadUueChunk(
    wire.UploadUueChunkRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.UueSendStatus> commitUue(
    wire.CommitUueRequest request, {
    RpcCancellation? cancellation,
  });
  Future<wire.UueSendStatus> getUueSendStatus(
    wire.UueOperationReference request, {
    RpcCancellation? cancellation,
  });
}
