import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fido/updates/update_metadata.dart';
import 'package:fido/updates/update_service.dart';

import 'update_fixture.dart';

void main() {
  late UpdateFixture fixture;
  setUp(() async {
    fixture = UpdateFixture();
    await fixture.initialize();
  });
  test('подпись проверяет точные байты и запрещает replay', () async {
    expect(
      (await UpdateManifest.verify(
        fixture.raw,
        fixture.sig,
        fixture.keys,
      )).identity.version,
      '2.0.0',
    );
    expect(
      UpdateManifest.verify(
        Uint8List.fromList([...fixture.raw, 32]),
        fixture.sig,
        fixture.keys,
      ),
      throwsFormatException,
    );
    expect(
      UpdateManifest.verify(fixture.raw, fixture.sig, {}),
      throwsFormatException,
    );
    expect(
      UpdateManifest.verify(
        fixture.raw,
        fixture.sig,
        fixture.keys,
        minimumSequence: 1003,
      ),
      throwsFormatException,
    );
  });
  test('числовой порядок версий, каналы и Android build', () {
    expect(
      UpdateIdentity(identity('1.10.0', 1002))
          .newerThan(UpdateIdentity(identity('1.9.0', 1001)), 'stable'),
      isTrue,
    );
    expect(
      UpdateIdentity(identity('2.0.0', 1002, stable: false))
          .newerThan(UpdateIdentity(identity('1.0.0', 1001)), 'stable'),
      isFalse,
    );
    expect(
      UpdateIdentity(identity('2.0.0', 1000)).newerThan(
        UpdateIdentity(identity('1.0.0', 1001)),
        'dev',
        android: true,
      ),
      isFalse,
    );
    expect(
      UpdateIdentity(identity('2.0.0', 1002))
          .newerThan(UpdateIdentity(identity('1.0.0', 1001)), 'dev'),
      isTrue,
    );
  });
  test('выбор платформы и минимальной ОС', () {
    final package = fixture.available.package;
    expect(
      const UpdatePlatform('linux', 'x86_64', [
        22,
        4,
      ], distribution: 'ubuntu').supports(package),
      isFalse,
    );
    expect(
      const UpdatePlatform('linux', 'arm64', [
        24,
        4,
      ], distribution: 'ubuntu').supports(package),
      isFalse,
    );
    expect(
      const UpdatePlatform('linux', 'x86_64', [
        24,
        4,
      ], distribution: 'debian').supports(package),
      isFalse,
    );
  });
  test('проверка находит подписанный совместимый пакет', () async {
    expect(
      (await fixture.service().check('stable'))?.package.id,
      'client-linux-x86_64',
    );
  });
  test('старые кандидаты не блокируют уже обнаруженный новый релиз', () async {
    final newest = UpdateFixture();
    await newest.initialize(version: '3.0.0', build: 1003);
    for (final rows in [
      [
        newest.release,
        fixture.release,
        {
          'draft': false,
          'prerelease': false,
          'tag_name': 'v1.0.0',
          'assets': 'historical assets must not be fetched',
        },
      ],
      [fixture.release, newest.release],
    ]) {
      final service = fixture.service(
        fetcher: (uri, {etag, limit = updateMetadataLimit}) async {
          if (uri.host == 'api.github.com') {
            return UpdateResponse(
              200,
              Uint8List.fromList(utf8.encode(jsonEncode(rows))),
            );
          }
          return uri.path.contains('/v3.0.0/')
              ? newest.fetch(uri, limit: limit)
              : fixture.fetch(uri, limit: limit);
        },
      );
      expect(
        (await service.check(
          'stable',
          minimumSequence: 1003,
        ))?.manifest.identity.tag,
        'v3.0.0',
      );
    }
  });
  test('HTTP 304 использует кеш, сохраняя проверку подписи', () async {
    var cached = false;
    final service = fixture.service(
      fetcher: (uri, {etag, limit = updateMetadataLimit}) async {
        if (uri.host == 'api.github.com' && cached) {
          expect(etag, 'test-etag');
          return UpdateResponse(304, Uint8List(0));
        }
        return fixture.fetch(uri, etag: etag, limit: limit);
      },
    );
    await service.check('stable');
    cached = true;
    expect((await service.check('stable'))?.manifest.identity.version, '2.0.0');
  });
  test('pagination не ограничивается первой страницей', () async {
    final service = fixture.service(
      fetcher: (uri, {etag, limit = updateMetadataLimit}) async {
        if (uri.host == 'api.github.com' &&
            uri.queryParameters['page'] == '1') {
          return UpdateResponse(
            200,
            Uint8List.fromList(
              utf8.encode(jsonEncode(List.filled(30, {'draft': true}))),
            ),
          );
        }
        return fixture.fetch(uri, etag: etag, limit: limit);
      },
    );
    expect((await service.check('stable'))?.manifest.identity.version, '2.0.0');
    expect(fixture.calls.any((url) => url.contains('page=2')), isTrue);
  });
  test('rate limit запоминается и запрещает ранний повтор', () async {
    var count = 0;
    final service = fixture.service(
      fetcher: (uri, {etag, limit = updateMetadataLimit}) async {
        count++;
        return UpdateResponse(429, Uint8List(0), {'retry-after': '60'});
      },
    );
    await expectLater(service.check('stable'), throwsA(isA<UpdateRateLimit>()));
    await expectLater(service.check('stable'), throwsA(isA<UpdateRateLimit>()));
    expect(count, 1);
  });
  test('offline и timeout не считаются актуальной версией', () async {
    for (final error in [StateError('offline'), TimeoutException('timeout')]) {
      final service = fixture.service(
        fetcher: (uri, {etag, limit = updateMetadataLimit}) async =>
            throw error,
      );
      await expectLater(service.check('stable'), throwsA(same(error)));
    }
  });
  test('несовместимая платформа и устаревший manifest дают ошибку', () async {
    await expectLater(
      fixture
          .service(
            platform: const UpdatePlatform('linux', 'arm64', [
              24,
              4,
            ], distribution: 'ubuntu'),
          )
          .check('stable'),
      throwsFormatException,
    );
    await expectLater(
      fixture.service().check('stable', minimumSequence: 1003),
      throwsFormatException,
    );
  });
  test(
    'неподписанный старый релиз пропускается, подмена URL запрещена',
    () async {
      fixture.release['assets'] = [];
      expect(await fixture.service().check('stable'), isNull);
      await fixture.initialize();
      (fixture.release['assets'] as List).first['browser_download_url'] =
          'https://evil.test/package';
      await expectLater(
        fixture.service().check('stable'),
        throwsFormatException,
      );
    },
  );
}
