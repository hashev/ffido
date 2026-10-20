import 'generated/ffido/v1/ffido.pb.dart' as wire;
import '../models/conference.dart';
import '../models/message.dart';
import '../models/api_response.dart';

Conference mapConference(wire.Conference value) => Conference(
  id: value.id,
  name: value.name,
  description: value.description,
  unreadCount: value.unreadCount.toInt(),
  totalCount: value.totalCount.toInt(),
  lastMessageDate: value.hasLastMessageDate()
      ? value.lastMessageDate.toDateTime().toUtc()
      : null,
  isBookmarked: value.isBookmarked,
  canRead: value.canRead,
  canPost: value.canPost,
  kind: AreaKind.values[value.kind.value],
  storageFormat: value.storageFormat.isEmpty ? 'JAM' : value.storageFormat,
  unsupportedFormat:
      value.availability ==
      wire.AreaAvailability.AREA_AVAILABILITY_UNSUPPORTED_FORMAT,
  statisticsKnown: value.hasStatisticsKnown() ? value.statisticsKnown : true,
  personalMailbox: value.personalMailbox,
  lastOpenedMessageId: value.lastOpenedMessageId.isEmpty
      ? null
      : value.lastOpenedMessageId,
  positionRevision: value.positionRevision.toInt(),
);
ConferenceListResponse mapConferences(wire.ListConferencesResponse value) =>
    ConferenceListResponse(
      conferences: value.conferences.map(mapConference).toList(),
      total: value.total.toInt(),
      hasMore: value.hasMore,
    );
Message mapMessage(wire.Message value) => Message(
  id: value.id,
  fromName: value.fromName,
  fromAddress: value.fromAddress,
  toName: value.toName,
  toAddress: value.toAddress,
  subject: value.subject,
  body: value.body,
  bodyPreview: value.bodyPreview.isEmpty ? null : value.bodyPreview,
  date: value.hasDate()
      ? value.date.toDateTime().toUtc()
      : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  threadId: value.threadId.isEmpty ? null : value.threadId,
  inReplyTo: value.inReplyTo.isEmpty ? null : value.inReplyTo,
  isRead: value.isRead,
  direction: switch (value.direction) {
    wire.MailDirection.MAIL_DIRECTION_INCOMING => MailDirection.incoming,
    wire.MailDirection.MAIL_DIRECTION_OUTGOING => MailDirection.outgoing,
    _ => MailDirection.unspecified,
  },
  positionRevision: value.positionRevision.toInt(),
);
MessageListResponse mapMessages(wire.ListMessagesResponse value) =>
    MessageListResponse(
      messages: value.messages.map(mapMessage).toList(),
      actualOffset: value.hasActualOffset() ? value.actualOffset.toInt() : null,
      total: value.total.toInt(),
      hasMore: value.hasMore,
    );
UserProfile mapProfile(wire.Profile value) => UserProfile(
  name: value.name,
  address: value.address,
  email: value.email.isEmpty ? null : value.email,
  registeredAt: value.hasRegisteredAt()
      ? value.registeredAt.toDateTime().toUtc()
      : null,
);
