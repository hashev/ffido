import 'package:flutter/material.dart';
import 'package:fido/fido_conference.dart';

import 'models/conference.dart';

/// Виджет карточки конференции
class ConferenceCard extends StatelessWidget {
  final FidoConference conference;
  final VoidCallback onTap;
  final VoidCallback? onBookmark;
  final bool bookmarkPending;
  final bool showStatistics;
  final bool showZeroCount;

  const ConferenceCard({
    super.key,
    required this.conference,
    required this.onTap,
    this.onBookmark,
    this.bookmarkPending = false,
    this.showStatistics = true,
    this.showZeroCount = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary,
          child: Icon(conference.icon, color: colorScheme.onPrimary, size: 24),
        ),
        title: Text(
          conference.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge!
              .copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          conference.unsupportedFormat
              ? 'Формат ${conference.storageFormat} не поддерживается. Статистика неизвестна.'
              : showStatistics && !conference.statisticsKnown
              ? 'Статистика недоступна'
              : conference.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showStatistics &&
                (conference.kind == AreaKind.echo ||
                    (conference.canRead &&
                        (conference.kind == AreaKind.netmail ||
                            conference.kind == AreaKind.local))) &&
                (showZeroCount ||
                    conference.unreadCount > 0 ||
                    !conference.statisticsKnown))
              Semantics(
                container: true,
                excludeSemantics: true,
                label: conference.statisticsKnown
                    ? 'Непрочитанных: ${conference.unreadCount}'
                    : 'Количество непрочитанных неизвестно',
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        conference.statisticsKnown && conference.unreadCount > 0
                        ? colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    conference.statisticsKnown
                        ? conference.unreadCount.toString()
                        : '—',
                    style: TextStyle(
                      color:
                          conference.unreadCount > 0 &&
                              conference.statisticsKnown
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            if (onBookmark != null || bookmarkPending)
              IconButton(
                tooltip: conference.isBookmarked
                    ? 'Удалить из закладок'
                    : 'Добавить в закладки',
                onPressed: bookmarkPending ? null : onBookmark,
                icon: Icon(
                  conference.isBookmarked
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                ),
              ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        onTap: conference.unsupportedFormat ? null : onTap,
      ),
    );
  }
}
