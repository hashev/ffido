import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

class BackendEntry {
  const BackendEntry({
    required this.id,
    required this.name,
    required this.ftnAddress,
    required this.endpoint,
  });
  final String id;
  final String name;
  final String ftnAddress;
  final Uri endpoint;
}

class BackendDirectory {
  const BackendDirectory(this.entries);
  final List<BackendEntry> entries;

  factory BackendDirectory.parse(String source) {
    if (utf8.encode(source).length > 1024 * 1024) {
      throw const FormatException('Каталог слишком велик');
    }
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic> ||
        value['schema'] != 1 ||
        value['servers'] is! List) {
      throw const FormatException('Неподдерживаемый каталог узлов');
    }
    final servers = value['servers'] as List;
    if (servers.length > 1000) {
      throw const FormatException('Слишком много узлов');
    }
    final ids = <String>{};
    final entries = <BackendEntry>[];
    for (final row in servers) {
      if (row is! Map<String, dynamic> ||
          row['id'] is! String ||
          row['name'] is! String ||
          row['ftn_address'] is! String ||
          row['endpoint'] is! String) {
        throw const FormatException('Некорректная запись узла');
      }
      final id = row['id'] as String;
      final name = row['name'] as String;
      final address = row['ftn_address'] as String;
      if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(id) ||
          !ids.add(id) ||
          name.trim().isEmpty ||
          name.length > 256 ||
          !RegExp(r'^\d+:\d+/\d+(?:\.\d+)?$').hasMatch(address)) {
        throw const FormatException('Некорректный идентификатор узла');
      }
      entries.add(
        BackendEntry(
          id: id,
          name: name,
          ftnAddress: address,
          endpoint: ApiClient.validateEndpoint(row['endpoint'] as String),
        ),
      );
    }
    return BackendDirectory(List.unmodifiable(entries));
  }

  BackendEntry? find(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}

class BackendDirectoryRepository {
  BackendDirectoryRepository(this.preferences, this.fetch);
  final SharedPreferences preferences;
  final Future<String> Function() fetch;
  static const cacheKey = 'ffido_web_directory_v1';
  static const historyKey = 'ffido_web_nodes_v1';
  BackendDirectory? current;
  bool stale = false;
  Object? loadError;

  Map<String, String> get acceptedEndpoints {
    try {
      final value = jsonDecode(preferences.getString(historyKey) ?? '{}');
      if (value is! Map<String, dynamic>) return {};
      return value.map(
        (key, endpoint) => MapEntry(
          key,
          ApiClient.validateEndpoint(endpoint as String).toString(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> load() async {
    try {
      final source = await fetch();
      final directory = BackendDirectory.parse(source);
      if (!await preferences.setString(cacheKey, source)) {
        throw StateError('Не удалось сохранить каталог');
      }
      current = directory;
      stale = false;
      loadError = null;
    } catch (error) {
      loadError = error;
      stale = true;
      final saved = preferences.getString(cacheKey);
      if (current == null && saved != null) {
        try {
          current = BackendDirectory.parse(saved);
        } catch (_) {
          /* Keep first-run failure visible. */
        }
      }
      if (current == null) rethrow;
    }
  }

  bool isAccepted(BackendEntry entry) =>
      current?.find(entry.id)?.endpoint == entry.endpoint &&
      acceptedEndpoints[entry.id] == entry.endpoint.toString();
  List<BackendEntry> get knownEntries =>
      current?.entries.where(isAccepted).toList() ?? [];

  Future<void> accept(BackendEntry entry) async {
    final actual = current?.find(entry.id);
    if (actual == null || actual.endpoint != entry.endpoint) {
      throw StateError('Узел больше не разрешён');
    }
    final history = acceptedEndpoints..[entry.id] = entry.endpoint.toString();
    if (!await preferences.setString(historyKey, jsonEncode(history))) {
      throw StateError('Не удалось сохранить узел');
    }
  }

  Future<void> forget(String id) async {
    final history = acceptedEndpoints..remove(id);
    if (!await preferences.setString(historyKey, jsonEncode(history))) {
      throw StateError('Не удалось удалить узел');
    }
  }
}
