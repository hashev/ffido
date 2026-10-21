import 'dart:convert';
import 'dart:typed_data';

import 'update_metadata.dart';

class UpdateResponse {
  const UpdateResponse(this.status, this.bytes, [this.headers = const {}]);
  final int status;
  final Uint8List bytes;
  final Map<String, String> headers;
}

typedef UpdateFetch = Future<UpdateResponse> Function(
  Uri uri, {
  String? etag,
  int limit,
});

class UpdateRateLimit implements Exception {
  UpdateRateLimit(this.retryAt);
  final DateTime retryAt;
  @override
  String toString() =>
      'Источник обновлений временно ограничил запросы. Повторите позже.';
}

class AvailableUpdate {
  AvailableUpdate(
    this.manifest,
    this.package,
    this.manifestBytes,
    this.signatureBytes,
    this.notes,
  );
  final UpdateManifest manifest;
  final UpdatePackage package;
  final Uint8List manifestBytes, signatureBytes;
  final String notes;
}

class UpdateService {
  UpdateService({
    required this.fetch,
    required this.keys,
    required this.installed,
    required this.platform,
    Map<String, dynamic>? cache,
  }) : cache = cache ?? {};
  final UpdateFetch fetch;
  final Map<String, dynamic> keys;
  final UpdateIdentity installed;
  final UpdatePlatform platform;
  final Map<String, dynamic> cache;
  DateTime? retryAt;

  Future<UpdateResponse> _get(
    Uri uri, {
    int limit = updateMetadataLimit,
    bool cached = false,
  }) async {
    validateUpdateUri(uri);
    if (retryAt != null && DateTime.now().isBefore(retryAt!)) {
      throw UpdateRateLimit(retryAt!);
    }
    final old = cache[uri.toString()];
    final response = await fetch(
      uri,
      etag: cached && old is Map ? old['etag'] as String? : null,
      limit: limit,
    ).timeout(const Duration(seconds: 30));
    if (response.status == 429 ||
        response.status == 403 &&
            response.headers['x-ratelimit-remaining'] == '0') {
      final reset = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
      final delay = int.tryParse(response.headers['retry-after'] ?? '');
      retryAt = reset != null
          ? DateTime.fromMillisecondsSinceEpoch(reset * 1000)
          : DateTime.now().add(Duration(seconds: delay ?? 3600));
      if (!retryAt!.isAfter(DateTime.now())) {
        retryAt = DateTime.now().add(const Duration(minutes: 1));
      }
      throw UpdateRateLimit(retryAt!);
    }
    if (response.status == 304 &&
        cached &&
        old is Map &&
        old['bytes'] is String) {
      final bytes = base64Decode(old['bytes'] as String);
      if (bytes.length > limit) {
        throw const FormatException('Слишком большой кеш обновлений');
      }
      return UpdateResponse(200, bytes);
    }
    if (response.status != 200) {
      throw Exception('Источник обновлений вернул HTTP ${response.status}');
    }
    if (response.bytes.length > limit) {
      throw const FormatException('Слишком большой ответ обновления');
    }
    if (cached) {
      cache[uri.toString()] = {
        'etag': response.headers['etag'],
        'bytes': base64Encode(response.bytes),
      };
    }
    return response;
  }

  Future<AvailableUpdate?> check(
    String channel, {
    int minimumSequence = 0,
  }) async {
    if (minimumSequence < installed.buildNumber) {
      minimumSequence = installed.buildNumber;
    }
    if (!{'stable', 'dev'}.contains(channel)) {
      throw const FormatException('Неизвестный канал');
    }
    if (installed.isLocal || keys.isEmpty) return null;
    AvailableUpdate? selected;
    var incompatible = false;
    var stale = false;
    for (var page = 1; page <= 20; ++page) {
      final uri = Uri.https('api.github.com', '/repos/hashev/ffido/releases', {
        'per_page': '30',
        'page': '$page',
      });
      final response = await _get(uri, cached: true);
      final releases = jsonDecode(utf8.decode(response.bytes));
      if (releases is! List) {
        throw const FormatException('Некорректный список выпусков');
      }
      for (final value in releases) {
        final release = updateObject(value);
        if (release['draft'] != false ||
            channel == 'stable' && release['prerelease'] != false) {
          continue;
        }
        final tag = release['tag_name'];
        if (tag is! String ||
            !RegExp(r'^v\d+\.\d+\.\d+(?:-dev\.\d+\.[0-9a-f]{12})?$')
                .hasMatch(tag)) {
          continue;
        }
        final match = RegExp(
          r'^v(\d+\.\d+\.\d+)(?:-dev\.(\d+)\.([0-9a-f]{12}))?$',
        ).firstMatch(tag)!;
        final advertised = UpdateIdentity({
          'version': match[1],
          'tag': tag,
          'stable': match[2] == null,
          'build_number': int.parse(match[2] ?? '1'),
          'sha': match[3] == null ? '0' * 40 : '${match[3]}${'0' * 28}',
        });
        // Retired signing keys on historical releases must not block discovery.
        // Every newer candidate still requires its actual signed identity.
        if (!advertised.newerThan(installed, channel)) continue;
        final assets = release['assets'];
        if (assets is! List) {
          throw const FormatException('Некорректные файлы выпуска');
        }
        final byName = <String, Map<String, dynamic>>{};
        for (final asset in assets) {
          final row = updateObject(asset);
          if (row['name'] is String) byName[row['name'] as String] = row;
        }
        if (!byName.containsKey('release-manifest.json') ||
            !byName.containsKey('release-manifest.sig')) {
          continue;
        }
        Future<Uint8List> getAsset(String name, int limit) async {
          final expected = updateAssetUri(tag, name);
          if (byName[name]?['browser_download_url'] != expected.toString()) {
            throw const FormatException('Адрес файла не соответствует выпуску');
          }
          return (await _get(expected, limit: limit)).bytes;
        }

        final raw = await getAsset(
          'release-manifest.json',
          updateMetadataLimit,
        );
        final sig = await getAsset('release-manifest.sig', 4096);
        final manifest = await UpdateManifest.verify(raw, sig, keys);
        if (manifest.identity.tag != tag ||
            manifest.identity.stable == release['prerelease']) {
          throw const FormatException('Подмена идентичности выпуска');
        }
        if (!manifest.identity.newerThan(
          installed,
          channel,
          android: platform.os == 'android' || platform.os == 'macos',
        )) {
          continue;
        }
        if (manifest.sequence < minimumSequence) {
          stale = true;
          continue;
        }
        final package = manifest.clientPackage(platform);
        if (package == null) {
          incompatible = true;
          continue;
        }
        if (byName[package.file]?['browser_download_url'] !=
                package.uri.toString() ||
            byName[package.file]?['size'] != package.size) {
          throw const FormatException('Файл пакета не соответствует манифесту');
        }
        if (selected == null ||
            compareParts(
                  manifest.identity.order,
                  selected.manifest.identity.order,
                ) >
                0) {
          selected = AvailableUpdate(
            manifest,
            package,
            raw,
            sig,
            release['body'] is String ? release['body'] as String : '',
          );
        }
      }
      if (releases.length < 30) {
        if (selected == null && stale) {
          throw const FormatException('Источник вернул устаревший выпуск');
        }
        if (selected == null && incompatible) {
          throw const FormatException(
            'Новый выпуск не поддерживает вашу ОС или архитектуру',
          );
        }
        return selected;
      }
    }
    throw const FormatException(
      'Слишком много страниц выпусков; проверка не завершена',
    );
  }
}
