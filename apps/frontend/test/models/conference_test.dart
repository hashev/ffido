import 'package:flutter_test/flutter_test.dart';
import 'package:fido/models/conference.dart';

void main() {
  test(
    'catalog order prioritizes types, then unread presence, name and ID',
    () {
      Conference item(
        String id,
        String name, {
        AreaKind kind = AreaKind.echo,
        int unread = 0,
        bool known = true,
      }) => Conference(
        id: id,
        name: name,
        description: '',
        unreadCount: unread,
        totalCount: unread,
        kind: kind,
        statisticsKnown: known,
      );
      final items = [
        item('read', 'Beta'),
        item('unread-z', 'Zulu', unread: 100),
        item('unread-a', 'alpha', unread: 1),
        item('unknown', 'alpha', unread: 900, known: false),
        item('net-z', 'Zulu', kind: AreaKind.netmail),
        item('net-a2', 'ALPHA', kind: AreaKind.netmail),
        item('net-a1', 'alpha', kind: AreaKind.netmail),
        item('local', 'local', kind: AreaKind.local),
        item('bad', 'bad', kind: AreaKind.bad),
        item('dupe', 'dupe', kind: AreaKind.dupe),
        item('robots', 'robots', kind: AreaKind.robots),
      ]..sort(Conference.compareForCatalog);
      expect(items.map((c) => c.id), [
        'net-a1',
        'net-a2',
        'net-z',
        'local',
        'bad',
        'dupe',
        'robots',
        'unread-a',
        'unread-z',
        'unknown',
        'read',
      ]);
      expect(<Conference>[]..sort(Conference.compareForCatalog), isEmpty);
    },
  );

  group('Conference', () {
    test('permissions default to denied and survive JSON and copies', () {
      final legacy = Conference.fromJson({'id': 'echo', 'name': 'Echo'});
      expect(legacy.canRead, isFalse);
      expect(legacy.canPost, isFalse);
      final allowed = legacy.copyWith(canRead: true, canPost: false);
      final restored = Conference.fromJson(allowed.toJson());
      expect(restored.canRead, isTrue);
      expect(restored.canPost, isFalse);
      expect(restored.copyWith(isBookmarked: true).canRead, isTrue);
    });
    test('fromJson создает объект из JSON', () {
      final json = {
        'id': 'comp.lang.dart',
        'name': 'comp.lang.dart',
        'description': 'Обсуждение Dart',
        'unread_count': 10,
        'total_count': 100,
        'last_message_date': '2026-04-02T18:30:00Z',
        'icon_code': 1234,
        'icon_font_family': 'MaterialIcons',
        'is_bookmarked': true,
      };

      final conference = Conference.fromJson(json);

      expect(conference.id, 'comp.lang.dart');
      expect(conference.name, 'comp.lang.dart');
      expect(conference.description, 'Обсуждение Dart');
      expect(conference.unreadCount, 10);
      expect(conference.totalCount, 100);
      expect(
        conference.lastMessageDate,
        DateTime.parse('2026-04-02T18:30:00Z'),
      );
      expect(conference.iconCode, 1234);
      expect(conference.isBookmarked, true);
    });

    test('fromJson обрабатывает null значения', () {
      final json = {
        'id': 'test.conf',
        'name': 'Test Conference',
        'description': null,
        'unread_count': null,
        'total_count': null,
        'last_message_date': null,
        'icon_code': null,
      };

      final conference = Conference.fromJson(json);

      expect(conference.description, '');
      expect(conference.unreadCount, 0);
      expect(conference.totalCount, 0);
      expect(conference.lastMessageDate, null);
      expect(conference.iconCode, 0);
      expect(conference.isBookmarked, false);
    });

    test('toJson преобразует объект обратно в JSON', () {
      final conference = Conference(
        id: 'test.conf',
        name: 'Test',
        description: 'Test conference',
        unreadCount: 5,
        totalCount: 50,
        lastMessageDate: DateTime(2026, 4, 2),
        iconCode: 1234,
        iconFontFamily: 'MaterialIcons',
        isBookmarked: true,
      );

      final json = conference.toJson();

      expect(json['id'], 'test.conf');
      expect(json['name'], 'Test');
      expect(json['description'], 'Test conference');
      expect(json['unread_count'], 5);
      expect(json['total_count'], 50);
      expect(json['is_bookmarked'], true);
    });

    test('copyWith создает копию с измененными полями', () {
      final original = Conference(
        id: 'test.conf',
        name: 'Test',
        description: 'Test conference',
        unreadCount: 5,
        totalCount: 50,
      );

      final copied = original.copyWith(unreadCount: 10, isBookmarked: true);

      expect(copied.id, original.id);
      expect(copied.name, original.name);
      expect(copied.unreadCount, 10);
      expect(copied.totalCount, original.totalCount);
      expect(copied.isBookmarked, true);
    });

    test('equality работает корректно', () {
      final conf1 = Conference(
        id: 'test.conf',
        name: 'Test',
        description: 'Desc',
        unreadCount: 0,
        totalCount: 0,
      );

      final conf2 = Conference(
        id: 'test.conf',
        name: 'Different Name',
        description: 'Different Desc',
        unreadCount: 100,
        totalCount: 1000,
      );

      final conf3 = Conference(
        id: 'other.conf',
        name: 'Test',
        description: 'Desc',
        unreadCount: 0,
        totalCount: 0,
      );

      expect(conf1 == conf2, true); // Одинаковый id
      expect(conf1 == conf3, false); // Разный id
    });

    test('ConferenceListResponse парсится корректно', () {
      final json = {
        'conferences': [
          {
            'id': 'conf1',
            'name': 'Conf 1',
            'description': 'Description 1',
            'unread_count': 5,
            'total_count': 50,
          },
          {
            'id': 'conf2',
            'name': 'Conf 2',
            'description': 'Description 2',
            'unread_count': 10,
            'total_count': 100,
          },
        ],
        'total': 2,
        'has_more': true,
      };

      final response = ConferenceListResponse.fromJson(json);

      expect(response.conferences.length, 2);
      expect(response.total, 2);
      expect(response.hasMore, true);
      expect(response.conferences[0].id, 'conf1');
      expect(response.conferences[1].id, 'conf2');
    });
  });
}
