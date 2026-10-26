import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/api_transport.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeTransport api;
  late SharedPreferences prefs;
  late ConferenceRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    api = FakeTransport()..conferences = (_) async => conferenceData('network');
    repo = ConferenceRepository(apiClient: api, prefs: prefs);
  });
  tearDown(() async {
    await repo.dispose();
    await api.dispose();
  });
  test('full catalog bypasses cache, preserves query and raw offsets, deduplicates', () async {
    await repo.fetchConferences();
    api.calls.clear();
    api.conferences = (request) async {
      expect(request.query, 'echo');
      expect(request.sort, wire.ConferenceSort.CONFERENCE_SORT_NAME);
      expect(request.page.limit, 20);
      final offset = request.page.offset.toInt();
      expect(offset, anyOf(0, 2));
      return wire.ListConferencesResponse(
        conferences: offset == 0
            ? [wire.Conference(id: 'a'), wire.Conference(id: 'b')]
            : [
                wire.Conference(id: 'b', name: 'updated'),
                wire.Conference(id: 'c'),
              ],
        hasMore: offset == 0,
      );
    };
    final result = await repo.fetchAllConferences(query: ' echo ');
    expect(result.conferences.map((c) => c.id), ['a', 'b', 'c']);
    expect(result.conferences[1].name, 'updated');
    expect(result.hasMore, isFalse);
    expect(result.total, 3);
    expect(api.calls.length, 2);
    expect((await repo.fetchConferences()).conferences.single.name, 'network');
  });
  test('full catalog empty result and first-page-only cache', () async {
    api.conferences = (_) async => wire.ListConferencesResponse();
    expect((await repo.fetchAllConferences()).conferences, isEmpty);
    api.conferences = (r) async => wire.ListConferencesResponse(
      conferences: [wire.Conference(id: 'id-${r.page.offset}')],
      hasMore: r.page.offset.toInt() == 0,
    );
    expect((await repo.fetchAllConferences()).conferences.length, 2);
    api.conferences = (_) async => throw const NetworkException();
    final fallback = await repo.fetchAllConferences();
    expect(fallback.conferences.length, 1);
    expect(fallback.hasMore, isTrue);
  });
  test(
    'late failure never returns partial result or cached first page',
    () async {
      await repo.fetchConferences();
      api.conferences = (r) async {
        if (r.page.offset.toInt() != 0) throw const NetworkException();
        return wire.ListConferencesResponse(
          conferences: [wire.Conference(id: 'partial')],
          hasMore: true,
        );
      };
      await expectLater(
        repo.fetchAllConferences(),
        throwsA(isA<NetworkException>()),
      );
    },
  );
  for (final empty in [false, true]) {
    test('full catalog rejects no progress (empty=$empty)', () async {
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: empty ? [] : [wire.Conference(id: 'repeated')],
        hasMore: true,
      );
      await expectLater(
        repo.fetchAllConferences(),
        throwsA(isA<ServerException>()),
      );
      expect(api.calls.length, empty ? 1 : 2);
    });
  }
  for (final sessionChange in [false, true]) {
    test(
      'full catalog cancels between pages (session=$sessionChange)',
      () async {
        final cancellation = RpcCancellation();
        api.conferences = (_) async {
          if (sessionChange) {
            api.switchSession();
          } else {
            await cancellation.cancel();
          }
          return wire.ListConferencesResponse(
            conferences: [wire.Conference(id: 'old')],
            hasMore: true,
          );
        };
        await expectLater(
          repo.fetchAllConferences(cancellation: cancellation),
          throwsA(isA<CancelledException>()),
        );
        expect(api.calls.length, 1);
      },
    );
  }
  test('full private catalog never persists its echo first page', () async {
    await repo.fetchConferences();
    api.conferences = (r) async => wire.ListConferencesResponse(
      conferences: [
        wire.Conference(
          id: 'id-${r.page.offset}',
          kind: r.page.offset.toInt() == 0
              ? wire.AreaKind.AREA_KIND_ECHO
              : wire.AreaKind.AREA_KIND_NETMAIL,
        ),
      ],
      hasMore: r.page.offset.toInt() == 0,
    );
    await repo.fetchAllConferences();
    expect(prefs.getKeys(), isEmpty);
  });
  for (final error in [
    const UnauthorizedException(),
    const CancelledException(),
    const ServerException(),
    const ApiException(message: 'Denied', statusCode: 7),
  ]) {
    test(
      'full catalog never hides status ${error.statusCode} behind cache',
      () async {
        await repo.fetchConferences();
        api.conferences = (_) async => throw error;
        await expectLater(
          repo.fetchAllConferences(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.statusCode,
              'status',
              error.statusCode,
            ),
          ),
        );
        if (error.isAccessDenied) expect(prefs.getKeys(), isEmpty);
      },
    );
  }
  test('full search has no fallback to unfiltered cache', () async {
    await repo.fetchConferences();
    api.conferences = (_) async => throw const NetworkException();
    await expectLater(
      repo.fetchAllConferences(query: 'new'),
      throwsA(isA<NetworkException>()),
    );
  });
  test('denied refresh removes cache and cannot fallback later', () async {
    await repo.fetchConferences();
    api.conferences = (_) async =>
        throw const ApiException(message: 'Denied', statusCode: 7);
    await expectLater(
      repo.fetchConferences(forceRefresh: true),
      throwsA(isA<ApiException>()),
    );
    expect(
      prefs.getKeys().where((key) => key.startsWith('ffido-conferences')),
      isEmpty,
    );
    api.conferences = (_) async => throw const NetworkException();
    await expectLater(
      repo.fetchConferences(),
      throwsA(isA<NetworkException>()),
    );
  });
  test('successful refresh replaces previously accessible catalog', () async {
    await repo.fetchConferences();
    api.conferences = (_) async => wire.ListConferencesResponse();
    expect(
      (await repo.fetchConferences(forceRefresh: true)).conferences,
      isEmpty,
    );
    api.conferences = (_) async => throw const NetworkException();
    expect((await repo.fetchConferences()).conferences, isEmpty);
  });
  test('first page caches and force refresh bypasses it', () async {
    var count = 0;
    api.conferences = (r) async {
      expect(r.page.limit, 20);
      expect(r.page.offset.toInt(), 0);
      return conferenceData('network${++count}');
    };
    expect((await repo.fetchConferences()).conferences.single.name, 'network1');
    expect((await repo.fetchConferences()).conferences.single.name, 'network1');
    expect(
      (await repo.fetchConferences(forceRefresh: true)).conferences.single.name,
      'network2',
    );
    expect(count, 2);
  });
  test('later page and different limit bypass first-page cache', () async {
    await repo.fetchConferences();
    api.conferences = (r) async =>
        conferenceData('page-${r.page.offset}-${r.page.limit}');
    expect(
      (await repo.fetchConferences(offset: 20)).conferences.single.name,
      'page-20-20',
    );
    expect((await repo.fetchConferences()).conferences.single.name, 'network');
    expect(
      (await repo.fetchConferences(limit: 50)).conferences.single.name,
      'page-0-50',
    );
  });
  for (final error in [const NetworkException(), const DeadlineException()]) {
    test(
      'refresh falls back to a valid cache on ${error.statusCode}',
      () async {
        await repo.fetchConferences();
        api.conferences = (_) async => throw error;
        expect(
          (await repo.fetchConferences(forceRefresh: true))
              .conferences
              .single
              .name,
          'network',
        );
        await expectLater(
          repo.fetchConferences(offset: 20),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          repo.fetchConferences(limit: 50),
          throwsA(isA<ApiException>()),
        );
      },
    );
  }
  for (final error in [
    const UnauthorizedException(),
    const NotFoundException(),
    const ValidationException(),
    const ServerException(),
    const CancelledException(),
  ]) {
    test('cache never hides status ${error.statusCode}', () async {
      await repo.fetchConferences();
      api.conferences = (_) async => throw error;
      await expectLater(
        repo.fetchConferences(forceRefresh: true),
        throwsA(
          isA<ApiException>().having(
            (e) => e.statusCode,
            'status',
            error.statusCode,
          ),
        ),
      );
    });
  }
  for (final corruption in [
    'expired',
    'future',
    'wrong scope',
    'schema',
    'limit',
    'bad JSON',
    'shape',
  ]) {
    test('ignores $corruption cache', () async {
      await repo.fetchConferences();
      final key = prefs.getKeys().single;
      final value = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      switch (corruption) {
        case 'expired':
          value['timestamp'] = DateTime.now()
              .subtract(const Duration(minutes: 6))
              .millisecondsSinceEpoch;
        case 'future':
          value['timestamp'] = DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch;
        case 'wrong scope':
          value['scope'] = 'other-user';
        case 'schema':
          value['schema'] = 1;
        case 'limit':
          value['limit'] = 50;
        case 'shape':
          value['response'] = {};
      }
      await prefs.setString(
        key,
        corruption == 'bad JSON' ? 'bad' : jsonEncode(value),
      );
      api.conferences = (_) async => conferenceData('fresh');
      expect((await repo.fetchConferences()).conferences.single.name, 'fresh');
    });
  }
  test(
    'session change cancels old response and removes persisted cache',
    () async {
      await repo.fetchConferences();
      final pending = Completer<wire.ListConferencesResponse>();
      api.conferences = (_) => pending.future;
      final request = repo.fetchConferences(forceRefresh: true);
      final assertion = expectLater(
        request,
        throwsA(isA<CancelledException>()),
      );
      await Future<void>.delayed(Duration.zero);
      api.switchSession();
      pending.complete(conferenceData('old user'));
      await assertion;
      await repo.clearCache();
      expect(prefs.getKeys(), isEmpty);
    },
  );
  test('logout cannot use a populated cache', () async {
    await repo.fetchConferences();
    api.switchSession(authenticated: false);
    await expectLater(
      repo.fetchConferences(),
      throwsA(isA<UnauthorizedException>()),
    );
  });
  test('cancelled scope and stale search response are rejected', () async {
    final cancellation = RpcCancellation();
    await cancellation.cancel();
    await expectLater(
      repo.searchConferences(query: 'dart', cancellation: cancellation),
      throwsA(isA<CancelledException>()),
    );
    expect(api.calls, isEmpty);
  });
  test('search is trimmed and empty query uses cache', () async {
    await repo.searchConferences(query: ' dart ', offset: 2, limit: 3);
    final request = api.calls.single as wire.ListConferencesRequest;
    expect(request.query, 'dart');
    expect(request.page.offset.toInt(), 2);
    expect(request.page.limit, 3);
    await repo.searchConferences(query: '  ');
    expect(api.calls.length, 2);
  });
  test(
    'bookmark mutations invalidate cache and preserve conference IDs',
    () async {
      await repo.fetchConferences();
      expect(await repo.toggleBookmark('id', false), isTrue);
      expect(prefs.getKeys(), isEmpty);
      expect((api.calls.last as wire.GetConferenceRequest).conferenceId, 'id');
      expect(await repo.toggleBookmark('id', true), isFalse);
      expect(await repo.getConferenceById('missing'), isNull);
    },
  );
  test('legacy cache is removed', () async {
    await prefs.setString('cached_conferences', 'legacy');
    await prefs.setInt('conferences_cache_timestamp', 1);
    await repo.clearCache();
    expect(prefs.getKeys(), isEmpty);
  });
}
