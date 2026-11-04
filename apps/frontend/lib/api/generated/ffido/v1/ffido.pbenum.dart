// This is a generated file - do not edit.
//
// Generated from ffido/v1/ffido.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class ConferenceSort extends $pb.ProtobufEnum {
  static const ConferenceSort CONFERENCE_SORT_UNSPECIFIED =
      ConferenceSort._(0, _omitEnumNames ? '' : 'CONFERENCE_SORT_UNSPECIFIED');
  static const ConferenceSort CONFERENCE_SORT_NAME =
      ConferenceSort._(1, _omitEnumNames ? '' : 'CONFERENCE_SORT_NAME');
  static const ConferenceSort CONFERENCE_SORT_LAST_MESSAGE =
      ConferenceSort._(2, _omitEnumNames ? '' : 'CONFERENCE_SORT_LAST_MESSAGE');
  static const ConferenceSort CONFERENCE_SORT_UNREAD =
      ConferenceSort._(3, _omitEnumNames ? '' : 'CONFERENCE_SORT_UNREAD');
  static const ConferenceSort CONFERENCE_SORT_CATALOG =
      ConferenceSort._(4, _omitEnumNames ? '' : 'CONFERENCE_SORT_CATALOG');

  static const $core.List<ConferenceSort> values = <ConferenceSort>[
    CONFERENCE_SORT_UNSPECIFIED,
    CONFERENCE_SORT_NAME,
    CONFERENCE_SORT_LAST_MESSAGE,
    CONFERENCE_SORT_UNREAD,
    CONFERENCE_SORT_CATALOG,
  ];

  static final $core.List<ConferenceSort?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static ConferenceSort? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ConferenceSort._(super.value, super.name);
}

class MessageSort extends $pb.ProtobufEnum {
  static const MessageSort MESSAGE_SORT_UNSPECIFIED =
      MessageSort._(0, _omitEnumNames ? '' : 'MESSAGE_SORT_UNSPECIFIED');
  static const MessageSort MESSAGE_SORT_DATE_ASCENDING =
      MessageSort._(1, _omitEnumNames ? '' : 'MESSAGE_SORT_DATE_ASCENDING');
  static const MessageSort MESSAGE_SORT_DATE_DESCENDING =
      MessageSort._(2, _omitEnumNames ? '' : 'MESSAGE_SORT_DATE_DESCENDING');

  static const $core.List<MessageSort> values = <MessageSort>[
    MESSAGE_SORT_UNSPECIFIED,
    MESSAGE_SORT_DATE_ASCENDING,
    MESSAGE_SORT_DATE_DESCENDING,
  ];

  static final $core.List<MessageSort?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static MessageSort? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const MessageSort._(super.value, super.name);
}

class AreaKind extends $pb.ProtobufEnum {
  static const AreaKind AREA_KIND_ECHO =
      AreaKind._(0, _omitEnumNames ? '' : 'AREA_KIND_ECHO');
  static const AreaKind AREA_KIND_NETMAIL =
      AreaKind._(1, _omitEnumNames ? '' : 'AREA_KIND_NETMAIL');
  static const AreaKind AREA_KIND_LOCAL =
      AreaKind._(2, _omitEnumNames ? '' : 'AREA_KIND_LOCAL');
  static const AreaKind AREA_KIND_BAD =
      AreaKind._(3, _omitEnumNames ? '' : 'AREA_KIND_BAD');
  static const AreaKind AREA_KIND_DUPE =
      AreaKind._(4, _omitEnumNames ? '' : 'AREA_KIND_DUPE');
  static const AreaKind AREA_KIND_ROBOTS =
      AreaKind._(5, _omitEnumNames ? '' : 'AREA_KIND_ROBOTS');

  static const $core.List<AreaKind> values = <AreaKind>[
    AREA_KIND_ECHO,
    AREA_KIND_NETMAIL,
    AREA_KIND_LOCAL,
    AREA_KIND_BAD,
    AREA_KIND_DUPE,
    AREA_KIND_ROBOTS,
  ];

  static final $core.List<AreaKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static AreaKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AreaKind._(super.value, super.name);
}

class AreaAvailability extends $pb.ProtobufEnum {
  static const AreaAvailability AREA_AVAILABILITY_AVAILABLE =
      AreaAvailability._(
          0, _omitEnumNames ? '' : 'AREA_AVAILABILITY_AVAILABLE');
  static const AreaAvailability AREA_AVAILABILITY_UNSUPPORTED_FORMAT =
      AreaAvailability._(
          1, _omitEnumNames ? '' : 'AREA_AVAILABILITY_UNSUPPORTED_FORMAT');

  static const $core.List<AreaAvailability> values = <AreaAvailability>[
    AREA_AVAILABILITY_AVAILABLE,
    AREA_AVAILABILITY_UNSUPPORTED_FORMAT,
  ];

  static final $core.List<AreaAvailability?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static AreaAvailability? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AreaAvailability._(super.value, super.name);
}

class MailDirection extends $pb.ProtobufEnum {
  static const MailDirection MAIL_DIRECTION_UNSPECIFIED =
      MailDirection._(0, _omitEnumNames ? '' : 'MAIL_DIRECTION_UNSPECIFIED');
  static const MailDirection MAIL_DIRECTION_INCOMING =
      MailDirection._(1, _omitEnumNames ? '' : 'MAIL_DIRECTION_INCOMING');
  static const MailDirection MAIL_DIRECTION_OUTGOING =
      MailDirection._(2, _omitEnumNames ? '' : 'MAIL_DIRECTION_OUTGOING');

  static const $core.List<MailDirection> values = <MailDirection>[
    MAIL_DIRECTION_UNSPECIFIED,
    MAIL_DIRECTION_INCOMING,
    MAIL_DIRECTION_OUTGOING,
  ];

  static final $core.List<MailDirection?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static MailDirection? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const MailDirection._(super.value, super.name);
}

class SaveStatus extends $pb.ProtobufEnum {
  static const SaveStatus SAVE_STATUS_UNSPECIFIED =
      SaveStatus._(0, _omitEnumNames ? '' : 'SAVE_STATUS_UNSPECIFIED');

  /// Подтверждает durable локальную запись, без обещания доставки в FidoNet.
  static const SaveStatus SAVE_STATUS_SAVED_LOCALLY =
      SaveStatus._(1, _omitEnumNames ? '' : 'SAVE_STATUS_SAVED_LOCALLY');

  static const $core.List<SaveStatus> values = <SaveStatus>[
    SAVE_STATUS_UNSPECIFIED,
    SAVE_STATUS_SAVED_LOCALLY,
  ];

  static final $core.List<SaveStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static SaveStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SaveStatus._(super.value, super.name);
}

class UueState extends $pb.ProtobufEnum {
  static const UueState UUE_STATE_UNSPECIFIED =
      UueState._(0, _omitEnumNames ? '' : 'UUE_STATE_UNSPECIFIED');
  static const UueState UUE_STATE_READY =
      UueState._(1, _omitEnumNames ? '' : 'UUE_STATE_READY');
  static const UueState UUE_STATE_INCOMPLETE =
      UueState._(2, _omitEnumNames ? '' : 'UUE_STATE_INCOMPLETE');
  static const UueState UUE_STATE_CONFLICT =
      UueState._(3, _omitEnumNames ? '' : 'UUE_STATE_CONFLICT');
  static const UueState UUE_STATE_CORRUPT =
      UueState._(4, _omitEnumNames ? '' : 'UUE_STATE_CORRUPT');

  static const $core.List<UueState> values = <UueState>[
    UUE_STATE_UNSPECIFIED,
    UUE_STATE_READY,
    UUE_STATE_INCOMPLETE,
    UUE_STATE_CONFLICT,
    UUE_STATE_CORRUPT,
  ];

  static final $core.List<UueState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static UueState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const UueState._(super.value, super.name);
}

/// Последовательный поиск открывает только найденное письмо, без изменения пропущенных.
class MessageSearchScope extends $pb.ProtobufEnum {
  static const MessageSearchScope MESSAGE_SEARCH_SCOPE_UNSPECIFIED =
      MessageSearchScope._(
          0, _omitEnumNames ? '' : 'MESSAGE_SEARCH_SCOPE_UNSPECIFIED');
  static const MessageSearchScope MESSAGE_SEARCH_HEADER_ONLY =
      MessageSearchScope._(
          1, _omitEnumNames ? '' : 'MESSAGE_SEARCH_HEADER_ONLY');
  static const MessageSearchScope MESSAGE_SEARCH_HEADER_AND_BODY =
      MessageSearchScope._(
          2, _omitEnumNames ? '' : 'MESSAGE_SEARCH_HEADER_AND_BODY');

  static const $core.List<MessageSearchScope> values = <MessageSearchScope>[
    MESSAGE_SEARCH_SCOPE_UNSPECIFIED,
    MESSAGE_SEARCH_HEADER_ONLY,
    MESSAGE_SEARCH_HEADER_AND_BODY,
  ];

  static final $core.List<MessageSearchScope?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static MessageSearchScope? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const MessageSearchScope._(super.value, super.name);
}

class MessageSearchField extends $pb.ProtobufEnum {
  static const MessageSearchField MESSAGE_SEARCH_FIELD_UNSPECIFIED =
      MessageSearchField._(
          0, _omitEnumNames ? '' : 'MESSAGE_SEARCH_FIELD_UNSPECIFIED');
  static const MessageSearchField MESSAGE_SEARCH_FROM_NAME =
      MessageSearchField._(1, _omitEnumNames ? '' : 'MESSAGE_SEARCH_FROM_NAME');
  static const MessageSearchField MESSAGE_SEARCH_FROM_ADDRESS =
      MessageSearchField._(
          2, _omitEnumNames ? '' : 'MESSAGE_SEARCH_FROM_ADDRESS');
  static const MessageSearchField MESSAGE_SEARCH_TO_NAME =
      MessageSearchField._(3, _omitEnumNames ? '' : 'MESSAGE_SEARCH_TO_NAME');
  static const MessageSearchField MESSAGE_SEARCH_TO_ADDRESS =
      MessageSearchField._(
          4, _omitEnumNames ? '' : 'MESSAGE_SEARCH_TO_ADDRESS');
  static const MessageSearchField MESSAGE_SEARCH_SUBJECT =
      MessageSearchField._(5, _omitEnumNames ? '' : 'MESSAGE_SEARCH_SUBJECT');
  static const MessageSearchField MESSAGE_SEARCH_BODY =
      MessageSearchField._(6, _omitEnumNames ? '' : 'MESSAGE_SEARCH_BODY');

  static const $core.List<MessageSearchField> values = <MessageSearchField>[
    MESSAGE_SEARCH_FIELD_UNSPECIFIED,
    MESSAGE_SEARCH_FROM_NAME,
    MESSAGE_SEARCH_FROM_ADDRESS,
    MESSAGE_SEARCH_TO_NAME,
    MESSAGE_SEARCH_TO_ADDRESS,
    MESSAGE_SEARCH_SUBJECT,
    MESSAGE_SEARCH_BODY,
  ];

  static final $core.List<MessageSearchField?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static MessageSearchField? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const MessageSearchField._(super.value, super.name);
}

class TechnicalEncodingStatus extends $pb.ProtobufEnum {
  static const TechnicalEncodingStatus TECHNICAL_ENCODING_STATUS_UNSPECIFIED =
      TechnicalEncodingStatus._(
          0, _omitEnumNames ? '' : 'TECHNICAL_ENCODING_STATUS_UNSPECIFIED');
  static const TechnicalEncodingStatus TECHNICAL_ENCODING_STATUS_KNOWN =
      TechnicalEncodingStatus._(
          1, _omitEnumNames ? '' : 'TECHNICAL_ENCODING_STATUS_KNOWN');
  static const TechnicalEncodingStatus TECHNICAL_ENCODING_STATUS_UNDETERMINED =
      TechnicalEncodingStatus._(
          2, _omitEnumNames ? '' : 'TECHNICAL_ENCODING_STATUS_UNDETERMINED');

  static const $core.List<TechnicalEncodingStatus> values =
      <TechnicalEncodingStatus>[
    TECHNICAL_ENCODING_STATUS_UNSPECIFIED,
    TECHNICAL_ENCODING_STATUS_KNOWN,
    TECHNICAL_ENCODING_STATUS_UNDETERMINED,
  ];

  static final $core.List<TechnicalEncodingStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static TechnicalEncodingStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TechnicalEncodingStatus._(super.value, super.name);
}

/// Персональное представление; не является ограничением доступа к FTN-письмам.
class PersonalMessageFilterScope extends $pb.ProtobufEnum {
  static const PersonalMessageFilterScope
      PERSONAL_MESSAGE_FILTER_SCOPE_UNSPECIFIED = PersonalMessageFilterScope._(
          0, _omitEnumNames ? '' : 'PERSONAL_MESSAGE_FILTER_SCOPE_UNSPECIFIED');
  static const PersonalMessageFilterScope
      PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS = PersonalMessageFilterScope._(
          1, _omitEnumNames ? '' : 'PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS');
  static const PersonalMessageFilterScope
      PERSONAL_MESSAGE_FILTER_SCOPE_CONFERENCE = PersonalMessageFilterScope._(
          2, _omitEnumNames ? '' : 'PERSONAL_MESSAGE_FILTER_SCOPE_CONFERENCE');

  static const $core.List<PersonalMessageFilterScope> values =
      <PersonalMessageFilterScope>[
    PERSONAL_MESSAGE_FILTER_SCOPE_UNSPECIFIED,
    PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS,
    PERSONAL_MESSAGE_FILTER_SCOPE_CONFERENCE,
  ];

  static final $core.List<PersonalMessageFilterScope?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static PersonalMessageFilterScope? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PersonalMessageFilterScope._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
