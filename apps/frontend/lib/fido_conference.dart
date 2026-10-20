import 'package:flutter/material.dart';

import 'models/conference.dart';

class FidoConference {
  final String id;
  final String name; // name of conference
  final String description; // description of conference
  final int unreadCount; // count of unread messages
  final IconData icon; // icon for conference
  final bool isBookmarked;
  final bool canRead, canPost;
  final bool personalMailbox;
  final AreaKind kind;
  final bool unsupportedFormat, statisticsKnown;
  final String storageFormat;

  FidoConference({
    this.id = '',
    required this.name,
    required this.description,
    required this.unreadCount,
    required this.icon,
    this.isBookmarked = false,
    this.canRead = false,
    this.canPost = false,
    this.personalMailbox = false,
    this.kind = AreaKind.echo,
    this.unsupportedFormat = false,
    this.statisticsKnown = true,
    this.storageFormat = 'JAM',
  });
}
