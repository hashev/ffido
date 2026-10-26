import 'dart:async';
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_transport.dart';
import '../api/api_constants.dart';
import '../api/api_exceptions.dart';
import '../api/model_mapping.dart';
import '../api/generated/ffido/v1/ffido.pb.dart' as wire;
import '../models/conference.dart';

class ConferenceRepository {
  ConferenceRepository({required this._apiClient, required this._prefs}) {
    _subscription = _apiClient.sessionChanges.listen((_) {
      unawaited(clearCache());
    });
  }
  final ApiTransport _apiClient;
  final SharedPreferences _prefs;
  late final StreamSubscription<int> _subscription;
  Future<void> _cacheQueue = Future.value();
  static const _prefix = 'ffido-conferences-v2:';
  static const _cacheValidDuration = Duration(minutes: 5);
  int get epoch => _apiClient.epoch;
  ApiTransport get transport => _apiClient;
  Stream<int> get sessionChanges => _apiClient.sessionChanges;
  void _check(int captured, RpcCancellation? cancellation) {
    if (captured != epoch || cancellation?.isCancelled == true) {
      throw const CancelledException();
    }
    if (!_apiClient.hasToken) throw const UnauthorizedException();
  }

  wire.PageRequest _page(int offset, int limit) =>
      wire.PageRequest(offset: Int64(offset), limit: limit);
  Future<ConferenceListResponse> fetchConferences({
    int offset = ApiConstants.defaultOffset,
    int limit = ApiConstants.defaultLimit,
    bool forceRefresh = false,
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    _check(captured, cancellation);
    await _cacheQueue;
    _check(captured, cancellation);
    if (!forceRefresh && offset == 0) {
      final cached = _getCachedConferences(limit);
      if (cached != null) return cached;
    }
    try {
      final response = await _apiClient.listConferences(
        wire.ListConferencesRequest(
          page: _page(offset, limit),
          sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
        ),
        cancellation: cancellation,
      );
      _check(captured, cancellation);
      final result = mapConferences(response);
      if (offset == 0) await _cacheConferences(result, limit, captured);
      _check(captured, cancellation);
      return result;
    } on ApiException catch (error) {
      _check(captured, cancellation);
      if (error.isAccessDenied) await clearCache();
      if (offset == 0 && error.allowsCacheFallback) {
        final cached = _getCachedConferences(limit);
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  Future<ConferenceListResponse> searchConferences({
    required String query,
    int offset = ApiConstants.defaultOffset,
    int limit = ApiConstants.defaultLimit,
    RpcCancellation? cancellation,
  }) async {
    if (query.trim().isEmpty) {
      return fetchConferences(
        offset: offset,
        limit: limit,
        cancellation: cancellation,
      );
    }
    final captured = epoch;
    _check(captured, cancellation);
    final result = await _apiClient.listConferences(
      wire.ListConferencesRequest(
        page: _page(offset, limit),
        query: query.trim(),
        sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
      ),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    return mapConferences(result);
  }

  /// Loads a catalog without mixing cached and live pages. A cached fallback
  /// retains hasMore so callers can explicitly identify an incomplete catalog.
  Future<ConferenceListResponse> fetchAllConferences({
    String query = '',
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    final filter = query.trim();
    _check(captured, cancellation);
    await _cacheQueue;
    _check(captured, cancellation);
    final items = <String, Conference>{};
    ConferenceListResponse? firstPage;
    var offset = 0;
    try {
      while (true) {
        final response = await _apiClient.listConferences(
          wire.ListConferencesRequest(
            page: _page(offset, ApiConstants.defaultLimit),
            query: filter,
            sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
          ),
          cancellation: cancellation,
        );
        _check(captured, cancellation);
        final page = mapConferences(response);
        firstPage ??= page;
        final previousCount = items.length;
        for (final conference in page.conferences) {
          items[conference.id] = conference;
        }
        if (!page.hasMore) break;
        if (items.length == previousCount) {
          throw const ServerException(
            message: 'Загрузка каталога не продвигается',
          );
        }
        offset += page.conferences.length;
        _check(captured, cancellation);
      }
      if (filter.isEmpty) {
        if (items.values.any((c) => c.kind != AreaKind.echo)) {
          await clearCache();
        } else {
          await _cacheConferences(
            firstPage,
            ApiConstants.defaultLimit,
            captured,
          );
        }
      }
      _check(captured, cancellation);
      return ConferenceListResponse(
        conferences: items.values.toList(),
        total: items.length,
        hasMore: false,
      );
    } on ApiException catch (error) {
      _check(captured, cancellation);
      if (error.isAccessDenied) await clearCache();
      _check(captured, cancellation);
      if (firstPage == null && filter.isEmpty && error.allowsCacheFallback) {
        final cached = _getCachedConferences(ApiConstants.defaultLimit);
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  Future<Conference?> getConferenceById(
    String id, {
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    _check(captured, cancellation);
    try {
      final response = await _apiClient.getConference(
        wire.GetConferenceRequest(conferenceId: id),
        cancellation: cancellation,
      );
      _check(captured, cancellation);
      return mapConference(response);
    } on ApiException catch (error) {
      if (error.isAccessDenied) await clearCache();
      if (error is! NotFoundException) rethrow;
      _check(captured, cancellation);
      return null;
    }
  }

  Future<bool> toggleBookmark(
    String id,
    bool isBookmarked, {
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    _check(captured, cancellation);
    final request = wire.GetConferenceRequest(conferenceId: id);
    try {
      if (isBookmarked) {
        await _apiClient.removeBookmark(request, cancellation: cancellation);
      } else {
        await _apiClient.addBookmark(request, cancellation: cancellation);
      }
    } on ApiException catch (error) {
      _check(captured, cancellation);
      if (error.isAccessDenied) await clearCache();
      rethrow;
    }
    _check(captured, cancellation);
    await clearCache();
    return !isBookmarked;
  }

  String get _key => '$_prefix${_apiClient.cacheScope}';
  ConferenceListResponse? _getCachedConferences(int limit) {
    try {
      final encoded = _prefs.getString(_key);
      if (encoded == null) return null;
      final data = jsonDecode(encoded) as Map<String, dynamic>;
      if (data['scope'] != _apiClient.cacheScope ||
          data['limit'] != limit ||
          data['schema'] != 2) {
        return null;
      }
      final stamp = data['timestamp'] as int;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(stamp),
      );
      if (age.isNegative || age > _cacheValidDuration) return null;
      return ConferenceListResponse.fromJson(
        data['response'] as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheConferences(
    ConferenceListResponse response,
    int limit,
    int captured,
  ) {
    // Private metadata always requires a current server response, never offline fallback.
    if (response.conferences.any((c) => c.kind != AreaKind.echo)) {
      return clearCache();
    }
    final scope = _apiClient.cacheScope;
    final key = _key;
    return _enqueue((_) async {
      if (captured != epoch || !_apiClient.hasToken) return;
      await _prefs.setString(
        key,
        jsonEncode({
          'schema': 2,
          'scope': scope,
          'limit': limit,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'response': {
            'conferences': response.conferences
                .map((value) => value.toJson())
                .toList(),
            'total': response.total,
            'has_more': response.hasMore,
          },
        }),
      );
      if (captured != epoch) await _prefs.remove(key);
    });
  }

  Future<void> clearCache() {
    return _enqueue((_) async {
      for (final key
          in _prefs
              .getKeys()
              .where(
                (key) =>
                    key.startsWith('ffido-conferences-') ||
                    key == 'cached_conferences' ||
                    key.startsWith('conferences_cache_'),
              )
              .toList()) {
        await _prefs.remove(key);
      }
    });
  }

  Future<void> _enqueue(Future<void> Function(Object?) action) {
    // Cache persistence is optional and cannot turn a successful RPC into failure.
    _cacheQueue = _cacheQueue.then((_) async {
      try {
        await action(null);
      } catch (_) {}
    });
    return _cacheQueue;
  }

  Future<void> dispose() => _subscription.cancel();
}
