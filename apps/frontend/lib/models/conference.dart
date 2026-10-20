enum AreaKind { echo, netmail, local, bad, dupe, robots }

extension AreaKindLabels on AreaKind {
  String get groupLabel => switch (this) {
    AreaKind.echo => 'Эхи',
    AreaKind.netmail => 'Личная почта',
    AreaKind.local => 'Локальные',
    _ => 'Служебные',
  };
  String get replyLabel => switch (this) {
    AreaKind.netmail => 'Ответить лично',
    AreaKind.local => 'Локальный ответ',
    _ => 'Ответить в эху',
  };
}

/// Модель конференции FidoNet/NTP
class Conference {
  final String id;
  final String name;
  final String description;
  final int unreadCount;
  final int totalCount;
  final DateTime? lastMessageDate;
  final int iconCode;
  final String? iconFontFamily;
  final String? iconFontPackage;
  final bool isBookmarked;
  final bool canRead;
  final bool canPost;
  final AreaKind kind;
  final String storageFormat;
  final bool unsupportedFormat;
  final bool statisticsKnown;
  final bool personalMailbox;
  final String? lastOpenedMessageId;
  final int positionRevision;

  Conference({
    required this.id,
    required this.name,
    required this.description,
    required this.unreadCount,
    required this.totalCount,
    this.lastMessageDate,
    this.iconCode = 0,
    this.iconFontFamily,
    this.iconFontPackage,
    this.isBookmarked = false,
    this.canRead = false,
    this.canPost = false,
    this.kind = AreaKind.echo,
    this.storageFormat = 'JAM',
    this.unsupportedFormat = false,
    this.statisticsKnown = true,
    this.personalMailbox = false,
    this.lastOpenedMessageId,
    this.positionRevision = 0,
  });

  /// Создание из JSON (ответ API)
  factory Conference.fromJson(Map<String, dynamic> json) {
    return Conference(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      unreadCount: json['unread_count'] as int? ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
      lastMessageDate: json['last_message_date'] != null
          ? DateTime.parse(json['last_message_date'] as String)
          : null,
      iconCode: json['icon_code'] as int? ?? 0,
      iconFontFamily: json['icon_font_family'] as String?,
      iconFontPackage: json['icon_font_package'] as String?,
      isBookmarked: json['is_bookmarked'] as bool? ?? false,
      canRead: json['can_read'] as bool? ?? false,
      canPost: json['can_post'] as bool? ?? false,
      kind: AreaKind.values[json['kind'] as int? ?? 0],
      storageFormat: json['storage_format'] as String? ?? 'JAM',
      unsupportedFormat: json['unsupported_format'] as bool? ?? false,
      statisticsKnown: json['statistics_known'] as bool? ?? true,
      personalMailbox: json['personal_mailbox'] as bool? ?? false,
      lastOpenedMessageId: json['last_opened_message_id'] as String?,
      positionRevision: json['position_revision'] as int? ?? 0,
    );
  }

  /// Преобразование в JSON (для локального кеширования)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'unread_count': unreadCount,
      'total_count': totalCount,
      'last_message_date': lastMessageDate?.toIso8601String(),
      'icon_code': iconCode,
      'icon_font_family': iconFontFamily,
      'icon_font_package': iconFontPackage,
      'is_bookmarked': isBookmarked,
      'can_read': canRead,
      'can_post': canPost,
      'kind': kind.index,
      'storage_format': storageFormat,
      'unsupported_format': unsupportedFormat,
      'statistics_known': statisticsKnown,
      'personal_mailbox': personalMailbox,
      'last_opened_message_id': lastOpenedMessageId,
      'position_revision': positionRevision,
    };
  }

  Conference copyWith({
    String? id,
    String? name,
    String? description,
    int? unreadCount,
    int? totalCount,
    DateTime? lastMessageDate,
    int? iconCode,
    String? iconFontFamily,
    String? iconFontPackage,
    bool? isBookmarked,
    bool? canRead,
    bool? canPost,
  }) {
    return Conference(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      unreadCount: unreadCount ?? this.unreadCount,
      totalCount: totalCount ?? this.totalCount,
      lastMessageDate: lastMessageDate ?? this.lastMessageDate,
      iconCode: iconCode ?? this.iconCode,
      iconFontFamily: iconFontFamily ?? this.iconFontFamily,
      iconFontPackage: iconFontPackage ?? this.iconFontPackage,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      canRead: canRead ?? this.canRead,
      canPost: canPost ?? this.canPost,
      kind: kind,
      storageFormat: storageFormat,
      unsupportedFormat: unsupportedFormat,
      statisticsKnown: statisticsKnown,
      personalMailbox: personalMailbox,
      lastOpenedMessageId: lastOpenedMessageId,
      positionRevision: positionRevision,
    );
  }

  @override
  String toString() => 'Conference(id: $id, name: $name, unread: $unreadCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Conference && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Модель списка конференций с пагинацией
class ConferenceListResponse {
  final List<Conference> conferences;
  final int total;
  final bool hasMore;

  ConferenceListResponse({
    required this.conferences,
    required this.total,
    required this.hasMore,
  });

  factory ConferenceListResponse.fromJson(Map<String, dynamic> json) {
    final list = json['conferences'] as List<dynamic>;
    return ConferenceListResponse(
      conferences: list
          .map((e) => Conference.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}
