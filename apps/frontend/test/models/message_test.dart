import 'package:flutter_test/flutter_test.dart';
import 'package:fido/models/message.dart';

void main() {
  group('Message', () {
    test('fromJson создает полное сообщение из JSON', () {
      final json = {
        'id': 'msg_123',
        'from_name': 'Иван Петров',
        'from_address': '2:5015/120.25',
        'to_name': 'Алексей Смирнов',
        'to_address': '2:5015/120.33',
        'subject': 'Тестовое сообщение',
        'body': 'Привет, это тестовое сообщение!',
        'date': '2026-04-01T14:30:00Z',
        'thread_id': 'thread_456',
        'in_reply_to': 'msg_100',
        'is_read': false,
        'body_preview': 'Привет, это тестовое...',
        'attachments': [
          {
            'id': 'att_1',
            'filename': 'test.txt',
            'mime_type': 'text/plain',
            'size': 1024,
            'url': 'https://example.com/test.txt',
          },
        ],
      };

      final message = Message.fromJson(json);

      expect(message.id, 'msg_123');
      expect(message.fromName, 'Иван Петров');
      expect(message.fromAddress, '2:5015/120.25');
      expect(message.toName, 'Алексей Смирнов');
      expect(message.toAddress, '2:5015/120.33');
      expect(message.subject, 'Тестовое сообщение');
      expect(message.body, 'Привет, это тестовое сообщение!');
      expect(message.date, DateTime.parse('2026-04-01T14:30:00Z'));
      expect(message.threadId, 'thread_456');
      expect(message.inReplyTo, 'msg_100');
      expect(message.isRead, false);
      expect(message.attachments.length, 1);
      expect(message.attachments[0].filename, 'test.txt');
    });

    test('fromJsonPreview создает превью сообщения', () {
      final json = {
        'id': 'msg_123',
        'from_name': 'Иван Петров',
        'from_address': '2:5015/120.25',
        'to_name': 'Алексей',
        'to_address': '2:5015/120.33',
        'subject': 'Тест',
        'date': '2026-04-01T14:30:00Z',
        'is_read': true,
        'body_preview': 'Краткое содержание...',
        'thread_id': 'thread_1',
      };

      final message = Message.fromJsonPreview(json);

      expect(message.id, 'msg_123');
      expect(
        message.body,
        'Краткое содержание...',
      ); // В превью body = body_preview
      expect(message.bodyPreview, 'Краткое содержание...');
      expect(message.isRead, true);
      expect(message.attachments.isEmpty, true);
    });

    test('toJsonForReply генерирует правильный JSON', () {
      final original = Message(
        id: 'msg_123',
        fromName: 'Иван',
        fromAddress: '2:5015/120.25',
        toName: 'Алексей',
        toAddress: '2:5015/120.33',
        subject: 'Оригинал',
        body: 'Тело',
        date: DateTime.now(),
      );

      final replyJson = original.toJsonForReply(
        subject: 'Re: Оригинал',
        body: 'Мой ответ',
      );

      expect(replyJson['subject'], 'Re: Оригинал');
      expect(replyJson['body'], 'Мой ответ');
      expect(replyJson['in_reply_to'], 'msg_123');
      expect(replyJson['to_name'], 'Иван');
      expect(replyJson['to_address'], '2:5015/120.25');
    });

    test('toJsonForReply сохраняет явно заданного получателя', () {
      final original = Message(
        id: 'msg',
        fromName: 'Author',
        fromAddress: 'author',
        toName: 'Recipient',
        toAddress: 'recipient',
        subject: 'Subject',
        body: 'Body',
        date: DateTime(2026),
      );
      expect(
        original.toJsonForReply(
          subject: 'Reply',
          body: 'Text',
          toName: 'Other',
          toAddress: 'other',
        ),
        {
          'to_name': 'Other',
          'to_address': 'other',
          'subject': 'Reply',
          'body': 'Text',
          'in_reply_to': 'msg',
        },
      );
    });

    test('copyWith создает копию с измененными полями', () {
      final original = Message(
        id: 'msg_1',
        fromName: 'From',
        fromAddress: 'from@addr',
        toName: 'To',
        toAddress: 'to@addr',
        subject: 'Subject',
        body: 'Body',
        date: DateTime(2026, 4, 1),
        isRead: false,
      );

      final copied = original.copyWith(isRead: true, subject: 'New Subject');

      expect(copied.isRead, true);
      expect(copied.subject, 'New Subject');
      expect(copied.id, original.id);
      expect(copied.body, original.body);
    });

    test('MessageListResponse парсится корректно', () {
      final json = {
        'messages': [
          {
            'id': 'msg1',
            'from_name': 'User1',
            'from_address': 'addr1',
            'to_name': 'User2',
            'to_address': 'addr2',
            'subject': 'Subj1',
            'date': '2026-04-01T10:00:00Z',
            'is_read': false,
            'body_preview': 'Preview 1',
          },
          {
            'id': 'msg2',
            'from_name': 'User3',
            'from_address': 'addr3',
            'to_name': 'User4',
            'to_address': 'addr4',
            'subject': 'Subj2',
            'date': '2026-04-01T11:00:00Z',
            'is_read': true,
            'body_preview': 'Preview 2',
          },
        ],
        'total': 2,
        'has_more': false,
      };

      final response = MessageListResponse.fromJson(json);

      expect(response.messages.length, 2);
      expect(response.total, 2);
      expect(response.hasMore, false);
      expect(response.messages[0].id, 'msg1');
      expect(response.messages[1].subject, 'Subj2');
    });
  });

  group('Attachment', () {
    test('fromJson создает вложение', () {
      final json = {
        'id': 'att_1',
        'filename': 'document.pdf',
        'mime_type': 'application/pdf',
        'size': 2048576,
        'url': 'https://example.com/document.pdf',
      };

      final attachment = Attachment.fromJson(json);

      expect(attachment.id, 'att_1');
      expect(attachment.filename, 'document.pdf');
      expect(attachment.mimeType, 'application/pdf');
      expect(attachment.size, 2048576);
      expect(attachment.url, 'https://example.com/document.pdf');
    });
  });
}
