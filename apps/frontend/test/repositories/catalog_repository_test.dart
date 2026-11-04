import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/api_transport.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/repositories/conference_repository.dart';

import '../support/fake_transport.dart';

void main() {
  late FakeTransport api;
  late ConferenceRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = FakeTransport();
    repo = ConferenceRepository(
      apiClient: api,
      prefs: await SharedPreferences.getInstance(),
    );
  });
  tearDown(() async {
    await repo.dispose();
    await api.dispose();
  });
  test('opt in mode applies flags and page; profiles never share in-memory snapshot', () async {
    api.supportsLightweightConferenceCatalog = true;
    api.conferences = (_) async =>
        wire.ListConferencesResponse(conferences: [wire.Conference(id: 'new')]);
    await repo.fetchCatalogPage(
      bookmarkedOnly: true,
      omitStatistics: false,
      query: ' name ',
      offset: 20,
      limit: 50,
    );
    final call = api.calls.single as wire.ListConferencesRequest;
    expect(call.query, 'name');
    expect(call.page.offset.toInt(), 20);
    expect(call.page.limit, 50);
    expect(call.bookmarkedOnly, isTrue);
    expect(call.omitStatistics, isFalse);
    expect(call.sort, wire.ConferenceSort.CONFERENCE_SORT_CATALOG);
    api.switchSession();
    api.conferences = (_) async => wire.ListConferencesResponse(
      conferences: [wire.Conference(id: 'other')],
    );
    expect((await repo.fetchCatalogPage()).conferences.single.id, 'other');
  });
  test(
    'favorite navigation uses all lightweight pages and not general catalog',
    () async {
      api.supportsLightweightConferenceCatalog = true;
      api.conferences = (r) async => wire.ListConferencesResponse(
        conferences: [
          wire.Conference(
            id: r.page.offset == Int64.ZERO ? 'z' : 'a',
            name: r.page.offset == Int64.ZERO ? 'Zulu' : 'alpha',
          ),
        ],
        hasMore: r.page.offset == Int64.ZERO,
      );
      final result = await repo.favoriteSnapshot();
      expect(result.map((c) => c.id), ['a', 'z']);
      final calls = api.calls.cast<wire.ListConferencesRequest>();
      expect(calls.length, 2);
      expect(
        calls.every(
          (r) => r.bookmarkedOnly && r.omitStatistics && r.page.limit == 100,
        ),
        isTrue,
      );
    },
  );
  test('old server uses bookmarks RPC and retains canonical complete catalog fallback', () async {
    api.bookmarks = (_) async => wire.ListBookmarksResponse(
      bookmarks: [
        wire.Bookmark(
          conference: wire.Conference(id: 'favorite', name: 'Favorite'),
        ),
      ],
    );
    expect(
      (await repo.fetchCatalogPage(bookmarkedOnly: true)).conferences.single.id,
      'favorite',
    );
    expect(api.calls.single, isA<wire.PageRequest>());
    api.conferences = (_) async => wire.ListConferencesResponse(
      conferences: [
        wire.Conference(id: 'z', name: 'Zulu'),
        wire.Conference(id: 'a', name: 'alpha'),
      ],
    );
    expect((await repo.fetchCatalogPage()).conferences.map((c) => c.id), [
      'a',
      'z',
    ]);
    final call = api.calls.last as wire.ListConferencesRequest;
    expect(call.sort, wire.ConferenceSort.CONFERENCE_SORT_NAME);
    expect(call.omitStatistics, isFalse);
    expect(call.bookmarkedOnly, isFalse);
  });
  for (final cancel in [false, true]) {
    test(
      'late catalog does not survive ${cancel ? "cancellation" : "session change"}',
      () async {
        api.supportsLightweightConferenceCatalog = true;
        final pending = Completer<wire.ListConferencesResponse>();
        api.conferences = (_) => pending.future;
        final token = RpcCancellation();
        final result = repo.fetchCatalogPage(cancellation: token);
        final checked = expectLater(result, throwsA(isA<CancelledException>()));
        if (cancel) {
          await token.cancel();
        } else {
          api.switchSession();
        }
        pending.complete(
          wire.ListConferencesResponse(
            conferences: [wire.Conference(id: 'private')],
          ),
        );
        await checked;
      },
    );
  }
  test(
    'transport error cannot return statistics from incompatible cached mode',
    () async {
      api.conferences = (_) async => wire.ListConferencesResponse(
        conferences: [wire.Conference(id: 'cached')],
      );
      await repo.fetchConferences();
      api.supportsLightweightConferenceCatalog = true;
      api.conferences = (_) async => throw const NetworkException();
      await expectLater(
        repo.fetchCatalogPage(bookmarkedOnly: true, omitStatistics: false),
        throwsA(isA<NetworkException>()),
      );
    },
  );
}
