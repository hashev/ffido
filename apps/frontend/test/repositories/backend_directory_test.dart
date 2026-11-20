import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/repositories/backend_directory.dart';

String catalog({
  String endpoint = 'https://node.example.org',
  String id = 'test',
}) => jsonEncode({
  'schema': 1,
  'servers': [
    {
      'id': id,
      'name': 'Тестовый узел',
      'ftn_address': '2:1/1',
      'endpoint': endpoint,
    },
  ],
});

void main() {
  test(
    'published source catalog is valid and contains no credential fields',
    () {
      final source = File('web/backends.json').readAsStringSync();
      final parsed = BackendDirectory.parse(source);
      expect(parsed.entries.length, lessThanOrEqualTo(1000));
      final value = jsonDecode(source) as Map<String, dynamic>;
      for (final row in value['servers'] as List) {
        expect((row as Map).keys.toSet(), {
          'id',
          'name',
          'ftn_address',
          'endpoint',
        });
      }
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('catalog rejects injected endpoints and duplicate identifiers', () {
    final valid = BackendDirectory.parse(catalog());
    expect(valid.entries.single.name, 'Тестовый узел');
    expect(valid.find('unknown'), isNull);
    for (final endpoint in [
      'http://node.example.org',
      'https://u:p@node.example.org',
      'https://node.example.org/path',
      'https://node.example.org/?token=x',
      'https://node.example.org/#x',
    ]) {
      expect(
        () => BackendDirectory.parse(catalog(endpoint: endpoint)),
        throwsException,
      );
    }
    final value = jsonDecode(catalog()) as Map<String, dynamic>;
    (value['servers'] as List).add((value['servers'] as List).first);
    expect(
      () => BackendDirectory.parse(jsonEncode(value)),
      throwsFormatException,
    );
    expect(
      () => BackendDirectory.parse(catalog(id: '../other')),
      throwsFormatException,
    );
    expect(
      () => BackendDirectory.parse('{"schema":2,"servers":[]}'),
      throwsFormatException,
    );
  });
  test(
    'first run requires catalog, corrupt refresh preserves last good copy',
    () async {
      final prefs = await SharedPreferences.getInstance();
      String source = catalog();
      final repo = BackendDirectoryRepository(prefs, () async => source);
      await repo.load();
      expect(repo.knownEntries, isEmpty);
      await repo.accept(repo.current!.entries.single);
      expect(repo.knownEntries, hasLength(1));
      source = 'broken';
      await repo.load();
      expect(repo.stale, isTrue);
      expect(repo.knownEntries, hasLength(1));
      final reopened = BackendDirectoryRepository(
        prefs,
        () => Future.error(StateError('offline')),
      );
      await reopened.load();
      expect(reopened.knownEntries, hasLength(1));
      await reopened.forget('test');
      expect(reopened.knownEntries, isEmpty);
      SharedPreferences.setMockInitialValues({});
      final empty = BackendDirectoryRepository(
        await SharedPreferences.getInstance(),
        () async => 'broken',
      );
      await expectLater(empty.load(), throwsException);
    },
  );
  test(
    'removal blocks discovery and endpoint move requires explicit acceptance',
    () async {
      final prefs = await SharedPreferences.getInstance();
      String source = catalog();
      final repo = BackendDirectoryRepository(prefs, () async => source);
      await repo.load();
      final old = repo.current!.entries.single;
      await repo.accept(old);
      source = catalog(endpoint: 'https://other.example.org');
      await repo.load();
      expect(repo.knownEntries, isEmpty);
      expect(repo.acceptedEndpoints['test'], old.endpoint.toString());
      await expectLater(repo.accept(old), throwsStateError);
      await repo.accept(repo.current!.entries.single);
      expect(repo.knownEntries, hasLength(1));
      source = '{"schema":1,"servers":[]}';
      await repo.load();
      expect(repo.knownEntries, isEmpty);
      expect(repo.acceptedEndpoints, contains('test'));
    },
  );
}
