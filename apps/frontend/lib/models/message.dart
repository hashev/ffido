enum MailDirection { unspecified, incoming, outgoing }

/// Модель сообщения FidoNet/NTP
class Message {
  final String id;
  final String fromName;
  final String fromAddress;
  final String toName;
  final String toAddress;
  final String subject;
  final String body;
  final DateTime date;
  final String? threadId;
  final String? inReplyTo;
  final bool isRead;
  final MailDirection direction;
  final int positionRevision;
  final String? bodyPreview;
  final List<Attachment> attachments;

  Message({
    required this.id,
    required this.fromName,
    required this.fromAddress,
    required this.toName,
    required this.toAddress,
    required this.subject,
    required this.body,
    required this.date,
    this.threadId,
    this.inReplyTo,
    this.isRead = false,
    this.direction = MailDirection.unspecified,
    this.positionRevision = 0,
    this.bodyPreview,
    this.attachments = const [],
  });

  /// Создание из JSON (ответ API — полное сообщение)
  factory Message.fromJson(Map<String, dynamic> json) {
    final attachmentsJson = json['attachments'] as List<dynamic>?;
    return Message(
      id: json['id'] as String,
      fromName: json['from_name'] as String,
      fromAddress: json['from_address'] as String,
      toName: json['to_name'] as String,
      toAddress: json['to_address'] as String,
      subject: json['subject'] as String,
      body: json['body'] as String,
      date: DateTime.parse(json['date'] as String),
      threadId: json['thread_id'] as String?,
      inReplyTo: json['in_reply_to'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      direction: MailDirection.values[json['direction'] as int? ?? 0],
      positionRevision: json['position_revision'] as int? ?? 0,
      bodyPreview: json['body_preview'] as String?,
      attachments: attachmentsJson != null
          ? attachmentsJson
                .map((e) => Attachment.fromJson(e as Map<String, dynamic>))
                .toList()
          : [],
    );
  }

  /// Создание из JSON (ответ API — превью сообщения в списке)
  factory Message.fromJsonPreview(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      fromName: json['from_name'] as String,
      fromAddress: json['from_address'] as String,
      toName: json['to_name'] as String,
      toAddress: json['to_address'] as String,
      subject: json['subject'] as String,
      body: json['body_preview'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
      threadId: json['thread_id'] as String?,
      inReplyTo: json['in_reply_to'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      direction: MailDirection.values[json['direction'] as int? ?? 0],
      positionRevision: json['position_revision'] as int? ?? 0,
      bodyPreview: json['body_preview'] as String?,
    );
  }

  /// Преобразование в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from_name': fromName,
      'from_address': fromAddress,
      'to_name': toName,
      'to_address': toAddress,
      'subject': subject,
      'body': body,
      'date': date.toIso8601String(),
      'thread_id': threadId,
      'in_reply_to': inReplyTo,
      'is_read': isRead,
      'direction': direction.index,
      'position_revision': positionRevision,
      'body_preview':
          bodyPreview ?? body.substring(0, body.length.clamp(0, 100)),
      'attachments': attachments.map((a) => a.toJson()).toList(),
    };
  }

  String get replyName =>
      direction == MailDirection.outgoing ? toName : fromName;
  String get replyAddress =>
      direction == MailDirection.outgoing ? toAddress : fromAddress;

  /// JSON для отправки ответа на сообщение
  Map<String, dynamic> toJsonForReply({
    required String subject,
    required String body,
    String? toName,
    String? toAddress,
  }) {
    return {
      'to_name': toName ?? replyName,
      'to_address': toAddress ?? replyAddress,
      'subject': subject,
      'body': body,
      'in_reply_to': id,
    };
  }

  Message copyWith({
    String? id,
    String? fromName,
    String? fromAddress,
    String? toName,
    String? toAddress,
    String? subject,
    String? body,
    DateTime? date,
    String? threadId,
    String? inReplyTo,
    bool? isRead,
    String? bodyPreview,
    List<Attachment>? attachments,
  }) {
    return Message(
      id: id ?? this.id,
      fromName: fromName ?? this.fromName,
      fromAddress: fromAddress ?? this.fromAddress,
      toName: toName ?? this.toName,
      toAddress: toAddress ?? this.toAddress,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      date: date ?? this.date,
      threadId: threadId ?? this.threadId,
      inReplyTo: inReplyTo ?? this.inReplyTo,
      isRead: isRead ?? this.isRead,
      direction: direction,
      positionRevision: positionRevision,
      bodyPreview: bodyPreview ?? this.bodyPreview,
      attachments: attachments ?? this.attachments,
    );
  }

  @override
  String toString() =>
      'Message(id: $id, subject: $subject, from: $fromName, date: $date)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Message && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Модель списка сообщений с пагинацией
class MessageListResponse {
  final List<Message> messages;
  final int total;
  final bool hasMore;
  final int? actualOffset;

  MessageListResponse({
    required this.messages,
    required this.total,
    required this.hasMore,
    this.actualOffset,
  });

  factory MessageListResponse.fromJson(Map<String, dynamic> json) {
    final list = json['messages'] as List<dynamic>;
    return MessageListResponse(
      messages: list
          .map((e) => Message.fromJsonPreview(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
      actualOffset: json['actual_offset'] as int?,
    );
  }
}

/// Модель вложения
class Attachment {
  final String id;
  final String filename;
  final String mimeType;
  final int size;
  final String? url;

  Attachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.size,
    this.url,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as String,
      filename: json['filename'] as String,
      mimeType: json['mime_type'] as String,
      size: json['size'] as int,
      url: json['url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'mime_type': mimeType,
      'size': size,
      'url': url,
    };
  }
}
