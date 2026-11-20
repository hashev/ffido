import 'dart:convert';

class WebDraftStore {
  WebDraftStore({
    required this.readValue,
    required this.listKeys,
    required this.writeValue,
    required this.removeValue,
  });
  final String? Function(String) readValue;
  final Set<String> Function() listKeys;
  final Future<bool> Function(String, String) writeValue;
  final Future<bool> Function(String) removeValue;
  static WebDraftStore? active;
  String? scope;
  Future<void> _tail = Future.value();
  Future<void> _mutate(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Set<String> scopesForNode(String id) {
    final result = <String>{};
    for (final key in listKeys().where(
      (k) => k.startsWith('ffido_web_draft_v1:'),
    )) {
      try {
        final profile = utf8.decode(base64Url.decode(key.split(':')[1]));
        final parts = jsonDecode(profile);
        if (parts is List && parts.isNotEmpty && parts.first == id) {
          result.add(profile);
        }
      } catch (_) {
        /* Ignore unrelated or damaged records. */
      }
    }
    return result;
  }

  String key(String profile, String id) =>
      'ffido_web_draft_v1:${base64Url.encode(utf8.encode(profile))}:$id';
  List<Map<String, dynamic>> list(String profile) {
    final prefix = key(profile, '');
    final result = <Map<String, dynamic>>[];
    for (final k in listKeys().where((k) => k.startsWith(prefix))) {
      try {
        final value = jsonDecode(readValue(k)!);
        if (value is Map<String, dynamic>) {
          result.add({...value, 'draftId': k.substring(prefix.length)});
        }
      } catch (_) {
        /* A damaged record must not become a send operation. */
      }
    }
    return result;
  }

  Future<void> write(String profile, String id, Map<String, dynamic> value) =>
      _mutate(() async {
        if (!await writeValue(key(profile, id), jsonEncode(value))) {
          throw StateError('Не удалось сохранить черновик');
        }
      });

  Future<void> remove(String profile, String id) => _mutate(() async {
    if (!await removeValue(key(profile, id))) {
      throw StateError('Не удалось удалить черновик');
    }
  });

  Future<void> clear(String profile) => _mutate(() async {
    final prefix = key(profile, '');
    for (final k in listKeys().where((k) => k.startsWith(prefix)).toList()) {
      if (!await removeValue(k)) {
        throw StateError('Не удалось удалить черновики');
      }
    }
  });

  Future<List<int>> freeze(
    String profile,
    String operation,
    String rpc,
    List<int> bytes,
    String identity,
  ) async {
    late List<int> frozen;
    await _mutate(() async {
      final id = 'send:$operation';
      final previous = list(profile)
          .where((r) => r['draftId'] == id)
          .firstOrNull;
      if (previous != null) {
        if (previous['rpc'] != rpc || previous['identity'] != identity) {
          throw StateError(
            'Нельзя изменить неопределённую отправку под прежним ключом',
          );
        }
        frozen = base64Decode(previous['wire'] as String);
        return;
      }
      frozen = List.of(bytes);
      if (!await writeValue(
        key(profile, id),
        jsonEncode({
          'operationId': operation,
          'rpc': rpc,
          'identity': identity,
          'wire': base64Encode(frozen),
        }),
      )) {
        throw StateError('Не удалось сохранить операцию');
      }
    });
    return frozen;
  }

  Future<void> complete(String profile, String operation) async {
    await _tail;
    for (final record in list(
      profile,
    ).where((r) => r['operationId'] == operation)) {
      await remove(profile, record['draftId'] as String);
    }
  }
}
