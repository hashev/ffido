import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/repositories/web_draft_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'drafts are scoped, persist and deletion follows queued writes',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = WebDraftStore(
        readValue: prefs.getString,
        listKeys: prefs.getKeys,
        writeValue: prefs.setString,
        removeValue: prefs.remove,
      );
      final a = jsonEncode(['node', 'https://node.example.org', '2:1/1.1']);
      final b = jsonEncode(['node', 'https://node.example.org', '2:1/1.2']);
      final writing = store.write(a, 'compose:one', {
        'operationId': 'one',
        'body': 'Текст',
      });
      final clearing = store.clear(a);
      await Future.wait([writing, clearing]);
      expect(store.list(a), isEmpty);
      await store.write(b, 'compose:two', {
        'operationId': 'two',
        'body': 'Другой текст',
      });
      final reopened = WebDraftStore(
        readValue: prefs.getString,
        listKeys: prefs.getKeys,
        writeValue: prefs.setString,
        removeValue: prefs.remove,
      );
      expect(reopened.list(b).single['body'], 'Другой текст');
      expect(reopened.scopesForNode('node'), {b});
      expect(reopened.scopesForNode('other'), isEmpty);
    },
  );
  test(
    'concurrent freeze cannot overwrite the first request identity',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = WebDraftStore(
        readValue: prefs.getString,
        listKeys: prefs.getKeys,
        writeValue: prefs.setString,
        removeValue: prefs.remove,
      );
      final first = store.freeze('profile', 'one', 'CreateMessage', [
        1,
      ], 'first');
      final second = expectLater(
        store.freeze('profile', 'one', 'CreateMessage', [2], 'different'),
        throwsStateError,
      );
      expect(await first, [1]);
      await second;
      expect(base64Decode(store.list('profile').single['wire'] as String), [1]);
      expect(
        await store.freeze('profile', 'one', 'CreateMessage', [3], 'first'),
        [1],
      );
    },
  );
  test(
    'unknown send freezes bytes across restart and rejects a changed operation',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = WebDraftStore(
        readValue: prefs.getString,
        listKeys: prefs.getKeys,
        writeValue: prefs.setString,
        removeValue: prefs.remove,
      );
      await store.write('profile', 'compose:one', {
        'operationId': 'one',
        'body': 'Text',
      });
      expect(
        await store.freeze('profile', 'one', 'CreateMessage', [
          1,
          2,
          3,
        ], 'same'),
        [1, 2, 3],
      );
      final reopened = WebDraftStore(
        readValue: prefs.getString,
        listKeys: prefs.getKeys,
        writeValue: prefs.setString,
        removeValue: prefs.remove,
      );
      expect(
        await reopened.freeze('profile', 'one', 'CreateMessage', [
          4,
          5,
          6,
        ], 'same'),
        [1, 2, 3],
      );
      await expectLater(
        reopened.freeze('profile', 'one', 'CreateMessage', [4], 'different'),
        throwsStateError,
      );
      await expectLater(
        reopened.freeze('profile', 'one', 'CommitUue', [4], 'same'),
        throwsStateError,
      );
      await reopened.complete('profile', 'one');
      expect(reopened.list('profile'), isEmpty);
    },
  );
}
