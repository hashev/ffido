import 'package:fixnum/fixnum.dart';
import '../api/api_transport.dart';
import '../api/api_exceptions.dart';
import '../api/model_mapping.dart';
import '../api/generated/ffido/v1/ffido.pb.dart' as wire;
import '../models/conference.dart';
import '../models/api_response.dart';

class PersonalConferenceEntry {
  final Conference conference;
  final DateTime? date;
  PersonalConferenceEntry(this.conference, this.date);
}

class PersonalConferencePage {
  final List<PersonalConferenceEntry> entries;
  final int total;
  final bool hasMore;
  PersonalConferencePage(this.entries, this.total, this.hasMore);
}

class AccountRepository {
  final ApiTransport transport;
  final Future<void> Function()? onBookmarksChanged;
  AccountRepository(this.transport, {this.onBookmarksChanged});
  Stream<int> get sessionChanges => transport.sessionChanges;
  int get epoch => transport.epoch;
  void _check(int captured, RpcCancellation? cancellation) {
    if (captured != transport.epoch || cancellation?.isCancelled == true) {
      throw const CancelledException();
    }
  }

  Future<UserProfile> getProfile({RpcCancellation? cancellation}) async {
    final captured = transport.epoch;
    final profile = await transport.getProfile(cancellation: cancellation);
    _check(captured, cancellation);
    return mapProfile(profile);
  }

  Future<PersonalConferencePage> getBookmarks({
    int offset = 0,
    int limit = 20,
    RpcCancellation? cancellation,
  }) async {
    final captured = transport.epoch;
    final response = await transport.listBookmarks(
      wire.PageRequest(offset: Int64(offset), limit: limit),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    return PersonalConferencePage(
      response.bookmarks
          .map(
            (value) => PersonalConferenceEntry(
              mapConference(value.conference),
              value.hasAddedAt() ? value.addedAt.toDateTime().toUtc() : null,
            ),
          )
          .toList(),
      response.total.toInt(),
      response.hasMore,
    );
  }

  Future<PersonalConferencePage> getHistory({
    int offset = 0,
    int limit = 20,
    RpcCancellation? cancellation,
  }) async {
    final captured = transport.epoch;
    final response = await transport.listHistory(
      wire.PageRequest(offset: Int64(offset), limit: limit),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    return PersonalConferencePage(
      response.history
          .map(
            (value) => PersonalConferenceEntry(
              mapConference(value.conference),
              value.hasViewedAt() ? value.viewedAt.toDateTime().toUtc() : null,
            ),
          )
          .toList(),
      response.total.toInt(),
      response.hasMore,
    );
  }

  Future<void> clearHistory({RpcCancellation? cancellation}) async {
    final captured = transport.epoch;
    await transport.clearHistory(cancellation: cancellation);
    _check(captured, cancellation);
  }

  Future<void> removeBookmark(String id) async {
    final captured = transport.epoch;
    await transport.removeBookmark(wire.GetConferenceRequest(conferenceId: id));
    _check(captured, null);
    await onBookmarksChanged?.call();
    _check(captured, null);
  }
}
