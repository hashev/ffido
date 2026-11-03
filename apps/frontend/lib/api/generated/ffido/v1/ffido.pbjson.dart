// This is a generated file - do not edit.
//
// Generated from ffido/v1/ffido.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use conferenceSortDescriptor instead')
const ConferenceSort$json = {
  '1': 'ConferenceSort',
  '2': [
    {'1': 'CONFERENCE_SORT_UNSPECIFIED', '2': 0},
    {'1': 'CONFERENCE_SORT_NAME', '2': 1},
    {'1': 'CONFERENCE_SORT_LAST_MESSAGE', '2': 2},
    {'1': 'CONFERENCE_SORT_UNREAD', '2': 3},
  ],
};

/// Descriptor for `ConferenceSort`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List conferenceSortDescriptor = $convert.base64Decode(
    'Cg5Db25mZXJlbmNlU29ydBIfChtDT05GRVJFTkNFX1NPUlRfVU5TUEVDSUZJRUQQABIYChRDT0'
    '5GRVJFTkNFX1NPUlRfTkFNRRABEiAKHENPTkZFUkVOQ0VfU09SVF9MQVNUX01FU1NBR0UQAhIa'
    'ChZDT05GRVJFTkNFX1NPUlRfVU5SRUFEEAM=');

@$core.Deprecated('Use messageSortDescriptor instead')
const MessageSort$json = {
  '1': 'MessageSort',
  '2': [
    {'1': 'MESSAGE_SORT_UNSPECIFIED', '2': 0},
    {'1': 'MESSAGE_SORT_DATE_ASCENDING', '2': 1},
    {'1': 'MESSAGE_SORT_DATE_DESCENDING', '2': 2},
  ],
};

/// Descriptor for `MessageSort`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List messageSortDescriptor = $convert.base64Decode(
    'CgtNZXNzYWdlU29ydBIcChhNRVNTQUdFX1NPUlRfVU5TUEVDSUZJRUQQABIfChtNRVNTQUdFX1'
    'NPUlRfREFURV9BU0NFTkRJTkcQARIgChxNRVNTQUdFX1NPUlRfREFURV9ERVNDRU5ESU5HEAI=');

@$core.Deprecated('Use areaKindDescriptor instead')
const AreaKind$json = {
  '1': 'AreaKind',
  '2': [
    {'1': 'AREA_KIND_ECHO', '2': 0},
    {'1': 'AREA_KIND_NETMAIL', '2': 1},
    {'1': 'AREA_KIND_LOCAL', '2': 2},
    {'1': 'AREA_KIND_BAD', '2': 3},
    {'1': 'AREA_KIND_DUPE', '2': 4},
    {'1': 'AREA_KIND_ROBOTS', '2': 5},
  ],
};

/// Descriptor for `AreaKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List areaKindDescriptor = $convert.base64Decode(
    'CghBcmVhS2luZBISCg5BUkVBX0tJTkRfRUNITxAAEhUKEUFSRUFfS0lORF9ORVRNQUlMEAESEw'
    'oPQVJFQV9LSU5EX0xPQ0FMEAISEQoNQVJFQV9LSU5EX0JBRBADEhIKDkFSRUFfS0lORF9EVVBF'
    'EAQSFAoQQVJFQV9LSU5EX1JPQk9UUxAF');

@$core.Deprecated('Use areaAvailabilityDescriptor instead')
const AreaAvailability$json = {
  '1': 'AreaAvailability',
  '2': [
    {'1': 'AREA_AVAILABILITY_AVAILABLE', '2': 0},
    {'1': 'AREA_AVAILABILITY_UNSUPPORTED_FORMAT', '2': 1},
  ],
};

/// Descriptor for `AreaAvailability`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List areaAvailabilityDescriptor = $convert.base64Decode(
    'ChBBcmVhQXZhaWxhYmlsaXR5Eh8KG0FSRUFfQVZBSUxBQklMSVRZX0FWQUlMQUJMRRAAEigKJE'
    'FSRUFfQVZBSUxBQklMSVRZX1VOU1VQUE9SVEVEX0ZPUk1BVBAB');

@$core.Deprecated('Use mailDirectionDescriptor instead')
const MailDirection$json = {
  '1': 'MailDirection',
  '2': [
    {'1': 'MAIL_DIRECTION_UNSPECIFIED', '2': 0},
    {'1': 'MAIL_DIRECTION_INCOMING', '2': 1},
    {'1': 'MAIL_DIRECTION_OUTGOING', '2': 2},
  ],
};

/// Descriptor for `MailDirection`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List mailDirectionDescriptor = $convert.base64Decode(
    'Cg1NYWlsRGlyZWN0aW9uEh4KGk1BSUxfRElSRUNUSU9OX1VOU1BFQ0lGSUVEEAASGwoXTUFJTF'
    '9ESVJFQ1RJT05fSU5DT01JTkcQARIbChdNQUlMX0RJUkVDVElPTl9PVVRHT0lORxAC');

@$core.Deprecated('Use saveStatusDescriptor instead')
const SaveStatus$json = {
  '1': 'SaveStatus',
  '2': [
    {'1': 'SAVE_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'SAVE_STATUS_SAVED_LOCALLY', '2': 1},
  ],
};

/// Descriptor for `SaveStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List saveStatusDescriptor = $convert.base64Decode(
    'CgpTYXZlU3RhdHVzEhsKF1NBVkVfU1RBVFVTX1VOU1BFQ0lGSUVEEAASHQoZU0FWRV9TVEFUVV'
    'NfU0FWRURfTE9DQUxMWRAB');

@$core.Deprecated('Use uueStateDescriptor instead')
const UueState$json = {
  '1': 'UueState',
  '2': [
    {'1': 'UUE_STATE_UNSPECIFIED', '2': 0},
    {'1': 'UUE_STATE_READY', '2': 1},
    {'1': 'UUE_STATE_INCOMPLETE', '2': 2},
    {'1': 'UUE_STATE_CONFLICT', '2': 3},
    {'1': 'UUE_STATE_CORRUPT', '2': 4},
  ],
};

/// Descriptor for `UueState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List uueStateDescriptor = $convert.base64Decode(
    'CghVdWVTdGF0ZRIZChVVVUVfU1RBVEVfVU5TUEVDSUZJRUQQABITCg9VVUVfU1RBVEVfUkVBRF'
    'kQARIYChRVVUVfU1RBVEVfSU5DT01QTEVURRACEhYKElVVRV9TVEFURV9DT05GTElDVBADEhUK'
    'EVVVRV9TVEFURV9DT1JSVVBUEAQ=');

@$core.Deprecated('Use messageSearchScopeDescriptor instead')
const MessageSearchScope$json = {
  '1': 'MessageSearchScope',
  '2': [
    {'1': 'MESSAGE_SEARCH_SCOPE_UNSPECIFIED', '2': 0},
    {'1': 'MESSAGE_SEARCH_HEADER_ONLY', '2': 1},
    {'1': 'MESSAGE_SEARCH_HEADER_AND_BODY', '2': 2},
  ],
};

/// Descriptor for `MessageSearchScope`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List messageSearchScopeDescriptor = $convert.base64Decode(
    'ChJNZXNzYWdlU2VhcmNoU2NvcGUSJAogTUVTU0FHRV9TRUFSQ0hfU0NPUEVfVU5TUEVDSUZJRU'
    'QQABIeChpNRVNTQUdFX1NFQVJDSF9IRUFERVJfT05MWRABEiIKHk1FU1NBR0VfU0VBUkNIX0hF'
    'QURFUl9BTkRfQk9EWRAC');

@$core.Deprecated('Use messageSearchFieldDescriptor instead')
const MessageSearchField$json = {
  '1': 'MessageSearchField',
  '2': [
    {'1': 'MESSAGE_SEARCH_FIELD_UNSPECIFIED', '2': 0},
    {'1': 'MESSAGE_SEARCH_FROM_NAME', '2': 1},
    {'1': 'MESSAGE_SEARCH_FROM_ADDRESS', '2': 2},
    {'1': 'MESSAGE_SEARCH_TO_NAME', '2': 3},
    {'1': 'MESSAGE_SEARCH_TO_ADDRESS', '2': 4},
    {'1': 'MESSAGE_SEARCH_SUBJECT', '2': 5},
    {'1': 'MESSAGE_SEARCH_BODY', '2': 6},
  ],
};

/// Descriptor for `MessageSearchField`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List messageSearchFieldDescriptor = $convert.base64Decode(
    'ChJNZXNzYWdlU2VhcmNoRmllbGQSJAogTUVTU0FHRV9TRUFSQ0hfRklFTERfVU5TUEVDSUZJRU'
    'QQABIcChhNRVNTQUdFX1NFQVJDSF9GUk9NX05BTUUQARIfChtNRVNTQUdFX1NFQVJDSF9GUk9N'
    'X0FERFJFU1MQAhIaChZNRVNTQUdFX1NFQVJDSF9UT19OQU1FEAMSHQoZTUVTU0FHRV9TRUFSQ0'
    'hfVE9fQUREUkVTUxAEEhoKFk1FU1NBR0VfU0VBUkNIX1NVQkpFQ1QQBRIXChNNRVNTQUdFX1NF'
    'QVJDSF9CT0RZEAY=');

@$core.Deprecated('Use technicalEncodingStatusDescriptor instead')
const TechnicalEncodingStatus$json = {
  '1': 'TechnicalEncodingStatus',
  '2': [
    {'1': 'TECHNICAL_ENCODING_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'TECHNICAL_ENCODING_STATUS_KNOWN', '2': 1},
    {'1': 'TECHNICAL_ENCODING_STATUS_UNDETERMINED', '2': 2},
  ],
};

/// Descriptor for `TechnicalEncodingStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List technicalEncodingStatusDescriptor = $convert.base64Decode(
    'ChdUZWNobmljYWxFbmNvZGluZ1N0YXR1cxIpCiVURUNITklDQUxfRU5DT0RJTkdfU1RBVFVTX1'
    'VOU1BFQ0lGSUVEEAASIwofVEVDSE5JQ0FMX0VOQ09ESU5HX1NUQVRVU19LTk9XThABEioKJlRF'
    'Q0hOSUNBTF9FTkNPRElOR19TVEFUVVNfVU5ERVRFUk1JTkVEEAI=');

@$core.Deprecated('Use personalMessageFilterScopeDescriptor instead')
const PersonalMessageFilterScope$json = {
  '1': 'PersonalMessageFilterScope',
  '2': [
    {'1': 'PERSONAL_MESSAGE_FILTER_SCOPE_UNSPECIFIED', '2': 0},
    {'1': 'PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS', '2': 1},
    {'1': 'PERSONAL_MESSAGE_FILTER_SCOPE_CONFERENCE', '2': 2},
  ],
};

/// Descriptor for `PersonalMessageFilterScope`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List personalMessageFilterScopeDescriptor = $convert.base64Decode(
    'ChpQZXJzb25hbE1lc3NhZ2VGaWx0ZXJTY29wZRItCilQRVJTT05BTF9NRVNTQUdFX0ZJTFRFUl'
    '9TQ09QRV9VTlNQRUNJRklFRBAAEisKJ1BFUlNPTkFMX01FU1NBR0VfRklMVEVSX1NDT1BFX0FM'
    'TF9FQ0hPUxABEiwKKFBFUlNPTkFMX01FU1NBR0VfRklMVEVSX1NDT1BFX0NPTkZFUkVOQ0UQAg'
    '==');

@$core.Deprecated('Use pageRequestDescriptor instead')
const PageRequest$json = {
  '1': 'PageRequest',
  '2': [
    {'1': 'offset', '3': 1, '4': 1, '5': 3, '10': 'offset'},
    {'1': 'limit', '3': 2, '4': 1, '5': 5, '10': 'limit'},
  ],
};

/// Descriptor for `PageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pageRequestDescriptor = $convert.base64Decode(
    'CgtQYWdlUmVxdWVzdBIWCgZvZmZzZXQYASABKANSBm9mZnNldBIUCgVsaW1pdBgCIAEoBVIFbG'
    'ltaXQ=');

@$core.Deprecated('Use listConferencesRequestDescriptor instead')
const ListConferencesRequest$json = {
  '1': 'ListConferencesRequest',
  '2': [
    {
      '1': 'page',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.PageRequest',
      '10': 'page'
    },
    {'1': 'query', '3': 2, '4': 1, '5': 9, '10': 'query'},
    {
      '1': 'sort',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.ConferenceSort',
      '10': 'sort'
    },
  ],
};

/// Descriptor for `ListConferencesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listConferencesRequestDescriptor = $convert.base64Decode(
    'ChZMaXN0Q29uZmVyZW5jZXNSZXF1ZXN0EikKBHBhZ2UYASABKAsyFS5mZmlkby52MS5QYWdlUm'
    'VxdWVzdFIEcGFnZRIUCgVxdWVyeRgCIAEoCVIFcXVlcnkSLAoEc29ydBgDIAEoDjIYLmZmaWRv'
    'LnYxLkNvbmZlcmVuY2VTb3J0UgRzb3J0');

@$core.Deprecated('Use getConferenceRequestDescriptor instead')
const GetConferenceRequest$json = {
  '1': 'GetConferenceRequest',
  '2': [
    {'1': 'conference_id', '3': 1, '4': 1, '5': 9, '10': 'conferenceId'},
  ],
};

/// Descriptor for `GetConferenceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getConferenceRequestDescriptor = $convert.base64Decode(
    'ChRHZXRDb25mZXJlbmNlUmVxdWVzdBIjCg1jb25mZXJlbmNlX2lkGAEgASgJUgxjb25mZXJlbm'
    'NlSWQ=');

@$core.Deprecated('Use conferenceDescriptor instead')
const Conference$json = {
  '1': 'Conference',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
    {'1': 'unread_count', '3': 4, '4': 1, '5': 3, '10': 'unreadCount'},
    {'1': 'total_count', '3': 5, '4': 1, '5': 3, '10': 'totalCount'},
    {
      '1': 'last_message_date',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'lastMessageDate'
    },
    {'1': 'is_bookmarked', '3': 7, '4': 1, '5': 8, '10': 'isBookmarked'},
    {'1': 'can_read', '3': 8, '4': 1, '5': 8, '10': 'canRead'},
    {'1': 'can_post', '3': 9, '4': 1, '5': 8, '10': 'canPost'},
    {
      '1': 'kind',
      '3': 10,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.AreaKind',
      '10': 'kind'
    },
    {'1': 'storage_format', '3': 11, '4': 1, '5': 9, '10': 'storageFormat'},
    {
      '1': 'availability',
      '3': 12,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.AreaAvailability',
      '10': 'availability'
    },
    {
      '1': 'statistics_known',
      '3': 13,
      '4': 1,
      '5': 8,
      '9': 0,
      '10': 'statisticsKnown',
      '17': true
    },
    {'1': 'personal_mailbox', '3': 14, '4': 1, '5': 8, '10': 'personalMailbox'},
    {
      '1': 'last_opened_message_id',
      '3': 15,
      '4': 1,
      '5': 9,
      '10': 'lastOpenedMessageId'
    },
    {
      '1': 'position_revision',
      '3': 16,
      '4': 1,
      '5': 4,
      '10': 'positionRevision'
    },
  ],
  '8': [
    {'1': '_statistics_known'},
  ],
};

/// Descriptor for `Conference`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List conferenceDescriptor = $convert.base64Decode(
    'CgpDb25mZXJlbmNlEg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEiAKC2Rlc2'
    'NyaXB0aW9uGAMgASgJUgtkZXNjcmlwdGlvbhIhCgx1bnJlYWRfY291bnQYBCABKANSC3VucmVh'
    'ZENvdW50Eh8KC3RvdGFsX2NvdW50GAUgASgDUgp0b3RhbENvdW50EkYKEWxhc3RfbWVzc2FnZV'
    '9kYXRlGAYgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIPbGFzdE1lc3NhZ2VEYXRl'
    'EiMKDWlzX2Jvb2ttYXJrZWQYByABKAhSDGlzQm9va21hcmtlZBIZCghjYW5fcmVhZBgIIAEoCF'
    'IHY2FuUmVhZBIZCghjYW5fcG9zdBgJIAEoCFIHY2FuUG9zdBImCgRraW5kGAogASgOMhIuZmZp'
    'ZG8udjEuQXJlYUtpbmRSBGtpbmQSJQoOc3RvcmFnZV9mb3JtYXQYCyABKAlSDXN0b3JhZ2VGb3'
    'JtYXQSPgoMYXZhaWxhYmlsaXR5GAwgASgOMhouZmZpZG8udjEuQXJlYUF2YWlsYWJpbGl0eVIM'
    'YXZhaWxhYmlsaXR5Ei4KEHN0YXRpc3RpY3Nfa25vd24YDSABKAhIAFIPc3RhdGlzdGljc0tub3'
    'duiAEBEikKEHBlcnNvbmFsX21haWxib3gYDiABKAhSD3BlcnNvbmFsTWFpbGJveBIzChZsYXN0'
    'X29wZW5lZF9tZXNzYWdlX2lkGA8gASgJUhNsYXN0T3BlbmVkTWVzc2FnZUlkEisKEXBvc2l0aW'
    '9uX3JldmlzaW9uGBAgASgEUhBwb3NpdGlvblJldmlzaW9uQhMKEV9zdGF0aXN0aWNzX2tub3du');

@$core.Deprecated('Use listConferencesResponseDescriptor instead')
const ListConferencesResponse$json = {
  '1': 'ListConferencesResponse',
  '2': [
    {
      '1': 'conferences',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.Conference',
      '10': 'conferences'
    },
    {'1': 'total', '3': 2, '4': 1, '5': 3, '10': 'total'},
    {'1': 'has_more', '3': 3, '4': 1, '5': 8, '10': 'hasMore'},
  ],
};

/// Descriptor for `ListConferencesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listConferencesResponseDescriptor = $convert.base64Decode(
    'ChdMaXN0Q29uZmVyZW5jZXNSZXNwb25zZRI2Cgtjb25mZXJlbmNlcxgBIAMoCzIULmZmaWRvLn'
    'YxLkNvbmZlcmVuY2VSC2NvbmZlcmVuY2VzEhQKBXRvdGFsGAIgASgDUgV0b3RhbBIZCghoYXNf'
    'bW9yZRgDIAEoCFIHaGFzTW9yZQ==');

@$core.Deprecated('Use listMessagesRequestDescriptor instead')
const ListMessagesRequest$json = {
  '1': 'ListMessagesRequest',
  '2': [
    {'1': 'conference_id', '3': 1, '4': 1, '5': 9, '10': 'conferenceId'},
    {
      '1': 'page',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.PageRequest',
      '10': 'page'
    },
    {'1': 'query', '3': 3, '4': 1, '5': 9, '10': 'query'},
    {
      '1': 'sort',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.MessageSort',
      '10': 'sort'
    },
    {'1': 'anchor_message_id', '3': 5, '4': 1, '5': 9, '10': 'anchorMessageId'},
    {
      '1': 'respect_personal_filters',
      '3': 6,
      '4': 1,
      '5': 8,
      '10': 'respectPersonalFilters'
    },
  ],
};

/// Descriptor for `ListMessagesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listMessagesRequestDescriptor = $convert.base64Decode(
    'ChNMaXN0TWVzc2FnZXNSZXF1ZXN0EiMKDWNvbmZlcmVuY2VfaWQYASABKAlSDGNvbmZlcmVuY2'
    'VJZBIpCgRwYWdlGAIgASgLMhUuZmZpZG8udjEuUGFnZVJlcXVlc3RSBHBhZ2USFAoFcXVlcnkY'
    'AyABKAlSBXF1ZXJ5EikKBHNvcnQYBCABKA4yFS5mZmlkby52MS5NZXNzYWdlU29ydFIEc29ydB'
    'IqChFhbmNob3JfbWVzc2FnZV9pZBgFIAEoCVIPYW5jaG9yTWVzc2FnZUlkEjgKGHJlc3BlY3Rf'
    'cGVyc29uYWxfZmlsdGVycxgGIAEoCFIWcmVzcGVjdFBlcnNvbmFsRmlsdGVycw==');

@$core.Deprecated('Use messageReferenceDescriptor instead')
const MessageReference$json = {
  '1': 'MessageReference',
  '2': [
    {'1': 'conference_id', '3': 1, '4': 1, '5': 9, '10': 'conferenceId'},
    {'1': 'message_id', '3': 2, '4': 1, '5': 9, '10': 'messageId'},
  ],
};

/// Descriptor for `MessageReference`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageReferenceDescriptor = $convert.base64Decode(
    'ChBNZXNzYWdlUmVmZXJlbmNlEiMKDWNvbmZlcmVuY2VfaWQYASABKAlSDGNvbmZlcmVuY2VJZB'
    'IdCgptZXNzYWdlX2lkGAIgASgJUgltZXNzYWdlSWQ=');

@$core.Deprecated('Use messageDescriptor instead')
const Message$json = {
  '1': 'Message',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'conference_id', '3': 2, '4': 1, '5': 9, '10': 'conferenceId'},
    {'1': 'from_name', '3': 3, '4': 1, '5': 9, '10': 'fromName'},
    {'1': 'from_address', '3': 4, '4': 1, '5': 9, '10': 'fromAddress'},
    {'1': 'to_name', '3': 5, '4': 1, '5': 9, '10': 'toName'},
    {'1': 'to_address', '3': 6, '4': 1, '5': 9, '10': 'toAddress'},
    {'1': 'subject', '3': 7, '4': 1, '5': 9, '10': 'subject'},
    {
      '1': 'date',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'date'
    },
    {'1': 'body', '3': 9, '4': 1, '5': 9, '10': 'body'},
    {'1': 'body_preview', '3': 10, '4': 1, '5': 9, '10': 'bodyPreview'},
    {'1': 'is_read', '3': 11, '4': 1, '5': 8, '10': 'isRead'},
    {'1': 'thread_id', '3': 12, '4': 1, '5': 9, '10': 'threadId'},
    {'1': 'in_reply_to', '3': 13, '4': 1, '5': 9, '10': 'inReplyTo'},
    {'1': 'ftn_message_id', '3': 14, '4': 1, '5': 9, '10': 'ftnMessageId'},
    {'1': 'attributes', '3': 15, '4': 1, '5': 13, '10': 'attributes'},
    {
      '1': 'direction',
      '3': 16,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.MailDirection',
      '10': 'direction'
    },
    {
      '1': 'position_revision',
      '3': 17,
      '4': 1,
      '5': 4,
      '10': 'positionRevision'
    },
    {
      '1': 'personal_collapse',
      '3': 18,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.PersonalMessageCollapse',
      '10': 'personalCollapse'
    },
  ],
};

/// Descriptor for `Message`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageDescriptor = $convert.base64Decode(
    'CgdNZXNzYWdlEg4KAmlkGAEgASgJUgJpZBIjCg1jb25mZXJlbmNlX2lkGAIgASgJUgxjb25mZX'
    'JlbmNlSWQSGwoJZnJvbV9uYW1lGAMgASgJUghmcm9tTmFtZRIhCgxmcm9tX2FkZHJlc3MYBCAB'
    'KAlSC2Zyb21BZGRyZXNzEhcKB3RvX25hbWUYBSABKAlSBnRvTmFtZRIdCgp0b19hZGRyZXNzGA'
    'YgASgJUgl0b0FkZHJlc3MSGAoHc3ViamVjdBgHIAEoCVIHc3ViamVjdBIuCgRkYXRlGAggASgL'
    'MhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIEZGF0ZRISCgRib2R5GAkgASgJUgRib2R5Ei'
    'EKDGJvZHlfcHJldmlldxgKIAEoCVILYm9keVByZXZpZXcSFwoHaXNfcmVhZBgLIAEoCFIGaXNS'
    'ZWFkEhsKCXRocmVhZF9pZBgMIAEoCVIIdGhyZWFkSWQSHgoLaW5fcmVwbHlfdG8YDSABKAlSCW'
    'luUmVwbHlUbxIkCg5mdG5fbWVzc2FnZV9pZBgOIAEoCVIMZnRuTWVzc2FnZUlkEh4KCmF0dHJp'
    'YnV0ZXMYDyABKA1SCmF0dHJpYnV0ZXMSNQoJZGlyZWN0aW9uGBAgASgOMhcuZmZpZG8udjEuTW'
    'FpbERpcmVjdGlvblIJZGlyZWN0aW9uEisKEXBvc2l0aW9uX3JldmlzaW9uGBEgASgEUhBwb3Np'
    'dGlvblJldmlzaW9uEk4KEXBlcnNvbmFsX2NvbGxhcHNlGBIgASgLMiEuZmZpZG8udjEuUGVyc2'
    '9uYWxNZXNzYWdlQ29sbGFwc2VSEHBlcnNvbmFsQ29sbGFwc2U=');

@$core.Deprecated('Use listMessagesResponseDescriptor instead')
const ListMessagesResponse$json = {
  '1': 'ListMessagesResponse',
  '2': [
    {
      '1': 'messages',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.Message',
      '10': 'messages'
    },
    {'1': 'total', '3': 2, '4': 1, '5': 3, '10': 'total'},
    {'1': 'has_more', '3': 3, '4': 1, '5': 8, '10': 'hasMore'},
    {
      '1': 'actual_offset',
      '3': 4,
      '4': 1,
      '5': 3,
      '9': 0,
      '10': 'actualOffset',
      '17': true
    },
  ],
  '8': [
    {'1': '_actual_offset'},
  ],
};

/// Descriptor for `ListMessagesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listMessagesResponseDescriptor = $convert.base64Decode(
    'ChRMaXN0TWVzc2FnZXNSZXNwb25zZRItCghtZXNzYWdlcxgBIAMoCzIRLmZmaWRvLnYxLk1lc3'
    'NhZ2VSCG1lc3NhZ2VzEhQKBXRvdGFsGAIgASgDUgV0b3RhbBIZCghoYXNfbW9yZRgDIAEoCFIH'
    'aGFzTW9yZRIoCg1hY3R1YWxfb2Zmc2V0GAQgASgDSABSDGFjdHVhbE9mZnNldIgBAUIQCg5fYW'
    'N0dWFsX29mZnNldA==');

@$core.Deprecated('Use messageFooterDescriptor instead')
const MessageFooter$json = {
  '1': 'MessageFooter',
  '2': [
    {'1': 'tagline', '3': 1, '4': 1, '5': 9, '10': 'tagline'},
    {'1': 'origin', '3': 2, '4': 1, '5': 9, '10': 'origin'},
  ],
};

/// Descriptor for `MessageFooter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageFooterDescriptor = $convert.base64Decode(
    'Cg1NZXNzYWdlRm9vdGVyEhgKB3RhZ2xpbmUYASABKAlSB3RhZ2xpbmUSFgoGb3JpZ2luGAIgAS'
    'gJUgZvcmlnaW4=');

@$core.Deprecated('Use createMessageRequestDescriptor instead')
const CreateMessageRequest$json = {
  '1': 'CreateMessageRequest',
  '2': [
    {'1': 'conference_id', '3': 1, '4': 1, '5': 9, '10': 'conferenceId'},
    {'1': 'operation_id', '3': 2, '4': 1, '5': 9, '10': 'operationId'},
    {'1': 'to_name', '3': 3, '4': 1, '5': 9, '10': 'toName'},
    {'1': 'to_address', '3': 4, '4': 1, '5': 9, '10': 'toAddress'},
    {'1': 'subject', '3': 5, '4': 1, '5': 9, '10': 'subject'},
    {'1': 'body', '3': 6, '4': 1, '5': 9, '10': 'body'},
    {'1': 'in_reply_to', '3': 7, '4': 1, '5': 9, '10': 'inReplyTo'},
    {
      '1': 'footer',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.MessageFooter',
      '10': 'footer'
    },
    {
      '1': 'expected_preview_digest',
      '3': 9,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'expectedPreviewDigest',
      '17': true
    },
  ],
  '8': [
    {'1': '_expected_preview_digest'},
  ],
};

/// Descriptor for `CreateMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createMessageRequestDescriptor = $convert.base64Decode(
    'ChRDcmVhdGVNZXNzYWdlUmVxdWVzdBIjCg1jb25mZXJlbmNlX2lkGAEgASgJUgxjb25mZXJlbm'
    'NlSWQSIQoMb3BlcmF0aW9uX2lkGAIgASgJUgtvcGVyYXRpb25JZBIXCgd0b19uYW1lGAMgASgJ'
    'UgZ0b05hbWUSHQoKdG9fYWRkcmVzcxgEIAEoCVIJdG9BZGRyZXNzEhgKB3N1YmplY3QYBSABKA'
    'lSB3N1YmplY3QSEgoEYm9keRgGIAEoCVIEYm9keRIeCgtpbl9yZXBseV90bxgHIAEoCVIJaW5S'
    'ZXBseVRvEi8KBmZvb3RlchgIIAEoCzIXLmZmaWRvLnYxLk1lc3NhZ2VGb290ZXJSBmZvb3Rlch'
    'I7ChdleHBlY3RlZF9wcmV2aWV3X2RpZ2VzdBgJIAEoCUgAUhVleHBlY3RlZFByZXZpZXdEaWdl'
    'c3SIAQFCGgoYX2V4cGVjdGVkX3ByZXZpZXdfZGlnZXN0');

@$core.Deprecated('Use createCrosspostRequestDescriptor instead')
const CreateCrosspostRequest$json = {
  '1': 'CreateCrosspostRequest',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.CreateMessageRequest',
      '10': 'message'
    },
    {
      '1': 'additional_conference_ids',
      '3': 2,
      '4': 3,
      '5': 9,
      '10': 'additionalConferenceIds'
    },
  ],
};

/// Descriptor for `CreateCrosspostRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createCrosspostRequestDescriptor = $convert.base64Decode(
    'ChZDcmVhdGVDcm9zc3Bvc3RSZXF1ZXN0EjgKB21lc3NhZ2UYASABKAsyHi5mZmlkby52MS5Dcm'
    'VhdGVNZXNzYWdlUmVxdWVzdFIHbWVzc2FnZRI6ChlhZGRpdGlvbmFsX2NvbmZlcmVuY2VfaWRz'
    'GAIgAygJUhdhZGRpdGlvbmFsQ29uZmVyZW5jZUlkcw==');

@$core.Deprecated('Use crosspostCopyDescriptor instead')
const CrosspostCopy$json = {
  '1': 'CrosspostCopy',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.MessageReference',
      '10': 'message'
    },
    {'1': 'ftn_message_id', '3': 2, '4': 1, '5': 9, '10': 'ftnMessageId'},
  ],
};

/// Descriptor for `CrosspostCopy`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List crosspostCopyDescriptor = $convert.base64Decode(
    'Cg1Dcm9zc3Bvc3RDb3B5EjQKB21lc3NhZ2UYASABKAsyGi5mZmlkby52MS5NZXNzYWdlUmVmZX'
    'JlbmNlUgdtZXNzYWdlEiQKDmZ0bl9tZXNzYWdlX2lkGAIgASgJUgxmdG5NZXNzYWdlSWQ=');

@$core.Deprecated('Use createCrosspostResponseDescriptor instead')
const CreateCrosspostResponse$json = {
  '1': 'CreateCrosspostResponse',
  '2': [
    {'1': 'complete', '3': 1, '4': 1, '5': 8, '10': 'complete'},
    {
      '1': 'saved',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.CrosspostCopy',
      '10': 'saved'
    },
    {'1': 'total', '3': 3, '4': 1, '5': 5, '10': 'total'},
    {'1': 'pending_code', '3': 4, '4': 1, '5': 5, '10': 'pendingCode'},
  ],
};

/// Descriptor for `CreateCrosspostResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createCrosspostResponseDescriptor = $convert.base64Decode(
    'ChdDcmVhdGVDcm9zc3Bvc3RSZXNwb25zZRIaCghjb21wbGV0ZRgBIAEoCFIIY29tcGxldGUSLQ'
    'oFc2F2ZWQYAiADKAsyFy5mZmlkby52MS5Dcm9zc3Bvc3RDb3B5UgVzYXZlZBIUCgV0b3RhbBgD'
    'IAEoBVIFdG90YWwSIQoMcGVuZGluZ19jb2RlGAQgASgFUgtwZW5kaW5nQ29kZQ==');

@$core.Deprecated('Use createMessageResponseDescriptor instead')
const CreateMessageResponse$json = {
  '1': 'CreateMessageResponse',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.MessageReference',
      '10': 'message'
    },
    {'1': 'ftn_message_id', '3': 2, '4': 1, '5': 9, '10': 'ftnMessageId'},
    {
      '1': 'status',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.SaveStatus',
      '10': 'status'
    },
  ],
};

/// Descriptor for `CreateMessageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createMessageResponseDescriptor = $convert.base64Decode(
    'ChVDcmVhdGVNZXNzYWdlUmVzcG9uc2USNAoHbWVzc2FnZRgBIAEoCzIaLmZmaWRvLnYxLk1lc3'
    'NhZ2VSZWZlcmVuY2VSB21lc3NhZ2USJAoOZnRuX21lc3NhZ2VfaWQYAiABKAlSDGZ0bk1lc3Nh'
    'Z2VJZBIsCgZzdGF0dXMYAyABKA4yFC5mZmlkby52MS5TYXZlU3RhdHVzUgZzdGF0dXM=');

@$core.Deprecated('Use getThreadRequestDescriptor instead')
const GetThreadRequest$json = {
  '1': 'GetThreadRequest',
  '2': [
    {'1': 'conference_id', '3': 1, '4': 1, '5': 9, '10': 'conferenceId'},
    {'1': 'thread_id', '3': 2, '4': 1, '5': 9, '10': 'threadId'},
    {
      '1': 'page',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.PageRequest',
      '10': 'page'
    },
    {
      '1': 'respect_personal_filters',
      '3': 4,
      '4': 1,
      '5': 8,
      '10': 'respectPersonalFilters'
    },
  ],
};

/// Descriptor for `GetThreadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getThreadRequestDescriptor = $convert.base64Decode(
    'ChBHZXRUaHJlYWRSZXF1ZXN0EiMKDWNvbmZlcmVuY2VfaWQYASABKAlSDGNvbmZlcmVuY2VJZB'
    'IbCgl0aHJlYWRfaWQYAiABKAlSCHRocmVhZElkEikKBHBhZ2UYAyABKAsyFS5mZmlkby52MS5Q'
    'YWdlUmVxdWVzdFIEcGFnZRI4ChhyZXNwZWN0X3BlcnNvbmFsX2ZpbHRlcnMYBCABKAhSFnJlc3'
    'BlY3RQZXJzb25hbEZpbHRlcnM=');

@$core.Deprecated('Use bookmarkDescriptor instead')
const Bookmark$json = {
  '1': 'Bookmark',
  '2': [
    {
      '1': 'conference',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.Conference',
      '10': 'conference'
    },
    {
      '1': 'added_at',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'addedAt'
    },
  ],
};

/// Descriptor for `Bookmark`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bookmarkDescriptor = $convert.base64Decode(
    'CghCb29rbWFyaxI0Cgpjb25mZXJlbmNlGAEgASgLMhQuZmZpZG8udjEuQ29uZmVyZW5jZVIKY2'
    '9uZmVyZW5jZRI1CghhZGRlZF9hdBgCIAEoCzIaLmdvb2dsZS5wcm90b2J1Zi5UaW1lc3RhbXBS'
    'B2FkZGVkQXQ=');

@$core.Deprecated('Use listBookmarksResponseDescriptor instead')
const ListBookmarksResponse$json = {
  '1': 'ListBookmarksResponse',
  '2': [
    {
      '1': 'bookmarks',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.Bookmark',
      '10': 'bookmarks'
    },
    {'1': 'total', '3': 2, '4': 1, '5': 3, '10': 'total'},
    {'1': 'has_more', '3': 3, '4': 1, '5': 8, '10': 'hasMore'},
  ],
};

/// Descriptor for `ListBookmarksResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listBookmarksResponseDescriptor = $convert.base64Decode(
    'ChVMaXN0Qm9va21hcmtzUmVzcG9uc2USMAoJYm9va21hcmtzGAEgAygLMhIuZmZpZG8udjEuQm'
    '9va21hcmtSCWJvb2ttYXJrcxIUCgV0b3RhbBgCIAEoA1IFdG90YWwSGQoIaGFzX21vcmUYAyAB'
    'KAhSB2hhc01vcmU=');

@$core.Deprecated('Use historyEntryDescriptor instead')
const HistoryEntry$json = {
  '1': 'HistoryEntry',
  '2': [
    {
      '1': 'conference',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.Conference',
      '10': 'conference'
    },
    {
      '1': 'viewed_at',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'viewedAt'
    },
  ],
};

/// Descriptor for `HistoryEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List historyEntryDescriptor = $convert.base64Decode(
    'CgxIaXN0b3J5RW50cnkSNAoKY29uZmVyZW5jZRgBIAEoCzIULmZmaWRvLnYxLkNvbmZlcmVuY2'
    'VSCmNvbmZlcmVuY2USNwoJdmlld2VkX2F0GAIgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVz'
    'dGFtcFIIdmlld2VkQXQ=');

@$core.Deprecated('Use listHistoryResponseDescriptor instead')
const ListHistoryResponse$json = {
  '1': 'ListHistoryResponse',
  '2': [
    {
      '1': 'history',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.HistoryEntry',
      '10': 'history'
    },
    {'1': 'total', '3': 2, '4': 1, '5': 3, '10': 'total'},
    {'1': 'has_more', '3': 3, '4': 1, '5': 8, '10': 'hasMore'},
  ],
};

/// Descriptor for `ListHistoryResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listHistoryResponseDescriptor = $convert.base64Decode(
    'ChNMaXN0SGlzdG9yeVJlc3BvbnNlEjAKB2hpc3RvcnkYASADKAsyFi5mZmlkby52MS5IaXN0b3'
    'J5RW50cnlSB2hpc3RvcnkSFAoFdG90YWwYAiABKANSBXRvdGFsEhkKCGhhc19tb3JlGAMgASgI'
    'UgdoYXNNb3Jl');

@$core.Deprecated('Use profileDescriptor instead')
const Profile$json = {
  '1': 'Profile',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'address', '3': 3, '4': 1, '5': 9, '10': 'address'},
    {'1': 'email', '3': 4, '4': 1, '5': 9, '10': 'email'},
    {
      '1': 'registered_at',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'registeredAt'
    },
  ],
};

/// Descriptor for `Profile`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List profileDescriptor = $convert.base64Decode(
    'CgdQcm9maWxlEhcKB3VzZXJfaWQYASABKAlSBnVzZXJJZBISCgRuYW1lGAIgASgJUgRuYW1lEh'
    'gKB2FkZHJlc3MYAyABKAlSB2FkZHJlc3MSFAoFZW1haWwYBCABKAlSBWVtYWlsEj8KDXJlZ2lz'
    'dGVyZWRfYXQYBSABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUgxyZWdpc3RlcmVkQX'
    'Q=');

@$core.Deprecated('Use errorDetailsDescriptor instead')
const ErrorDetails$json = {
  '1': 'ErrorDetails',
  '2': [
    {
      '1': 'violations',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.FieldViolation',
      '10': 'violations'
    },
  ],
};

/// Descriptor for `ErrorDetails`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorDetailsDescriptor = $convert.base64Decode(
    'CgxFcnJvckRldGFpbHMSOAoKdmlvbGF0aW9ucxgBIAMoCzIYLmZmaWRvLnYxLkZpZWxkVmlvbG'
    'F0aW9uUgp2aW9sYXRpb25z');

@$core.Deprecated('Use fieldViolationDescriptor instead')
const FieldViolation$json = {
  '1': 'FieldViolation',
  '2': [
    {'1': 'field', '3': 1, '4': 1, '5': 9, '10': 'field'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `FieldViolation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fieldViolationDescriptor = $convert.base64Decode(
    'Cg5GaWVsZFZpb2xhdGlvbhIUCgVmaWVsZBgBIAEoCVIFZmllbGQSGAoHbWVzc2FnZRgCIAEoCV'
    'IHbWVzc2FnZQ==');

@$core.Deprecated('Use loginRequestDescriptor instead')
const LoginRequest$json = {
  '1': 'LoginRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'address', '3': 2, '4': 1, '5': 9, '10': 'address'},
    {'1': 'password', '3': 3, '4': 1, '5': 9, '10': 'password'},
  ],
};

/// Descriptor for `LoginRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loginRequestDescriptor = $convert.base64Decode(
    'CgxMb2dpblJlcXVlc3QSEgoEbmFtZRgBIAEoCVIEbmFtZRIYCgdhZGRyZXNzGAIgASgJUgdhZG'
    'RyZXNzEhoKCHBhc3N3b3JkGAMgASgJUghwYXNzd29yZA==');

@$core.Deprecated('Use sessionInfoDescriptor instead')
const SessionInfo$json = {
  '1': 'SessionInfo',
  '2': [
    {
      '1': 'supports_message_footer',
      '3': 3,
      '4': 1,
      '5': 8,
      '10': 'supportsMessageFooter'
    },
    {
      '1': 'profile',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.Profile',
      '10': 'profile'
    },
    {
      '1': 'expires_at',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'expiresAt'
    },
  ],
};

/// Descriptor for `SessionInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sessionInfoDescriptor = $convert.base64Decode(
    'CgtTZXNzaW9uSW5mbxI2ChdzdXBwb3J0c19tZXNzYWdlX2Zvb3RlchgDIAEoCFIVc3VwcG9ydH'
    'NNZXNzYWdlRm9vdGVyEisKB3Byb2ZpbGUYASABKAsyES5mZmlkby52MS5Qcm9maWxlUgdwcm9m'
    'aWxlEjkKCmV4cGlyZXNfYXQYAiABKAsyGi5nb29nbGUucHJvdG9idWYuVGltZXN0YW1wUglleH'
    'BpcmVzQXQ=');

@$core.Deprecated('Use loginResponseDescriptor instead')
const LoginResponse$json = {
  '1': 'LoginResponse',
  '2': [
    {'1': 'session_secret', '3': 1, '4': 1, '5': 9, '10': 'sessionSecret'},
    {
      '1': 'session',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.SessionInfo',
      '10': 'session'
    },
  ],
};

/// Descriptor for `LoginResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List loginResponseDescriptor = $convert.base64Decode(
    'Cg1Mb2dpblJlc3BvbnNlEiUKDnNlc3Npb25fc2VjcmV0GAEgASgJUg1zZXNzaW9uU2VjcmV0Ei'
    '8KB3Nlc3Npb24YAiABKAsyFS5mZmlkby52MS5TZXNzaW9uSW5mb1IHc2Vzc2lvbg==');

@$core.Deprecated('Use markConferenceReadRequestDescriptor instead')
const MarkConferenceReadRequest$json = {
  '1': 'MarkConferenceReadRequest',
  '2': [
    {'1': 'conference_id', '3': 1, '4': 1, '5': 9, '10': 'conferenceId'},
    {'1': 'operation_id', '3': 2, '4': 1, '5': 9, '10': 'operationId'},
  ],
};

/// Descriptor for `MarkConferenceReadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List markConferenceReadRequestDescriptor =
    $convert.base64Decode(
        'ChlNYXJrQ29uZmVyZW5jZVJlYWRSZXF1ZXN0EiMKDWNvbmZlcmVuY2VfaWQYASABKAlSDGNvbm'
        'ZlcmVuY2VJZBIhCgxvcGVyYXRpb25faWQYAiABKAlSC29wZXJhdGlvbklk');

@$core.Deprecated('Use markConferenceReadResponseDescriptor instead')
const MarkConferenceReadResponse$json = {
  '1': 'MarkConferenceReadResponse',
  '2': [
    {'1': 'marked_count', '3': 1, '4': 1, '5': 3, '10': 'markedCount'},
    {'1': 'snapshot_count', '3': 2, '4': 1, '5': 3, '10': 'snapshotCount'},
    {'1': 'generation', '3': 3, '4': 1, '5': 9, '10': 'generation'},
  ],
};

/// Descriptor for `MarkConferenceReadResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List markConferenceReadResponseDescriptor =
    $convert.base64Decode(
        'ChpNYXJrQ29uZmVyZW5jZVJlYWRSZXNwb25zZRIhCgxtYXJrZWRfY291bnQYASABKANSC21hcm'
        'tlZENvdW50EiUKDnNuYXBzaG90X2NvdW50GAIgASgDUg1zbmFwc2hvdENvdW50Eh4KCmdlbmVy'
        'YXRpb24YAyABKAlSCmdlbmVyYXRpb24=');

@$core.Deprecated('Use uueLimitsDescriptor instead')
const UueLimits$json = {
  '1': 'UueLimits',
  '2': [
    {'1': 'max_file_bytes', '3': 1, '4': 1, '5': 4, '10': 'maxFileBytes'},
    {'1': 'part_body_bytes', '3': 2, '4': 1, '5': 13, '10': 'partBodyBytes'},
    {'1': 'max_parts', '3': 3, '4': 1, '5': 13, '10': 'maxParts'},
    {'1': 'chunk_bytes', '3': 4, '4': 1, '5': 13, '10': 'chunkBytes'},
    {'1': 'preview_pixels', '3': 5, '4': 1, '5': 4, '10': 'previewPixels'},
    {
      '1': 'preview_dimension',
      '3': 6,
      '4': 1,
      '5': 13,
      '10': 'previewDimension'
    },
  ],
};

/// Descriptor for `UueLimits`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uueLimitsDescriptor = $convert.base64Decode(
    'CglVdWVMaW1pdHMSJAoObWF4X2ZpbGVfYnl0ZXMYASABKARSDG1heEZpbGVCeXRlcxImCg9wYX'
    'J0X2JvZHlfYnl0ZXMYAiABKA1SDXBhcnRCb2R5Qnl0ZXMSGwoJbWF4X3BhcnRzGAMgASgNUght'
    'YXhQYXJ0cxIfCgtjaHVua19ieXRlcxgEIAEoDVIKY2h1bmtCeXRlcxIlCg5wcmV2aWV3X3BpeG'
    'VscxgFIAEoBFINcHJldmlld1BpeGVscxIrChFwcmV2aWV3X2RpbWVuc2lvbhgGIAEoDVIQcHJl'
    'dmlld0RpbWVuc2lvbg==');

@$core.Deprecated('Use uuePartReferenceDescriptor instead')
const UuePartReference$json = {
  '1': 'UuePartReference',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.MessageReference',
      '10': 'message'
    },
    {'1': 'block_index', '3': 2, '4': 1, '5': 13, '10': 'blockIndex'},
  ],
};

/// Descriptor for `UuePartReference`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uuePartReferenceDescriptor = $convert.base64Decode(
    'ChBVdWVQYXJ0UmVmZXJlbmNlEjQKB21lc3NhZ2UYASABKAsyGi5mZmlkby52MS5NZXNzYWdlUm'
    'VmZXJlbmNlUgdtZXNzYWdlEh8KC2Jsb2NrX2luZGV4GAIgASgNUgpibG9ja0luZGV4');

@$core.Deprecated('Use uuePartDescriptor instead')
const UuePart$json = {
  '1': 'UuePart',
  '2': [
    {
      '1': 'source',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.UuePartReference',
      '10': 'source'
    },
    {'1': 'from_address', '3': 2, '4': 1, '5': 9, '10': 'fromAddress'},
    {'1': 'to_address', '3': 3, '4': 1, '5': 9, '10': 'toAddress'},
    {'1': 'subject', '3': 4, '4': 1, '5': 9, '10': 'subject'},
    {'1': 'transfer_id', '3': 5, '4': 1, '5': 9, '10': 'transferId'},
    {'1': 'part', '3': 6, '4': 1, '5': 13, '10': 'part'},
    {'1': 'total', '3': 7, '4': 1, '5': 13, '10': 'total'},
    {'1': 'filename', '3': 8, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'decoded_size', '3': 9, '4': 1, '5': 4, '10': 'decodedSize'},
    {'1': 'sha256', '3': 10, '4': 1, '5': 9, '10': 'sha256'},
    {'1': 'body_start', '3': 11, '4': 1, '5': 13, '10': 'bodyStart'},
    {'1': 'body_end', '3': 12, '4': 1, '5': 13, '10': 'bodyEnd'},
    {'1': 'diagnostic', '3': 13, '4': 1, '5': 9, '10': 'diagnostic'},
    {'1': 'date', '3': 14, '4': 1, '5': 9, '10': 'date'},
    {
      '1': 'direction',
      '3': 15,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.MailDirection',
      '10': 'direction'
    },
  ],
};

/// Descriptor for `UuePart`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uuePartDescriptor = $convert.base64Decode(
    'CgdVdWVQYXJ0EjIKBnNvdXJjZRgBIAEoCzIaLmZmaWRvLnYxLlV1ZVBhcnRSZWZlcmVuY2VSBn'
    'NvdXJjZRIhCgxmcm9tX2FkZHJlc3MYAiABKAlSC2Zyb21BZGRyZXNzEh0KCnRvX2FkZHJlc3MY'
    'AyABKAlSCXRvQWRkcmVzcxIYCgdzdWJqZWN0GAQgASgJUgdzdWJqZWN0Eh8KC3RyYW5zZmVyX2'
    'lkGAUgASgJUgp0cmFuc2ZlcklkEhIKBHBhcnQYBiABKA1SBHBhcnQSFAoFdG90YWwYByABKA1S'
    'BXRvdGFsEhoKCGZpbGVuYW1lGAggASgJUghmaWxlbmFtZRIhCgxkZWNvZGVkX3NpemUYCSABKA'
    'RSC2RlY29kZWRTaXplEhYKBnNoYTI1NhgKIAEoCVIGc2hhMjU2Eh0KCmJvZHlfc3RhcnQYCyAB'
    'KA1SCWJvZHlTdGFydBIZCghib2R5X2VuZBgMIAEoDVIHYm9keUVuZBIeCgpkaWFnbm9zdGljGA'
    '0gASgJUgpkaWFnbm9zdGljEhIKBGRhdGUYDiABKAlSBGRhdGUSNQoJZGlyZWN0aW9uGA8gASgO'
    'MhcuZmZpZG8udjEuTWFpbERpcmVjdGlvblIJZGlyZWN0aW9u');

@$core.Deprecated('Use searchUuePartsRequestDescriptor instead')
const SearchUuePartsRequest$json = {
  '1': 'SearchUuePartsRequest',
  '2': [
    {'1': 'conference_id', '3': 1, '4': 1, '5': 9, '10': 'conferenceId'},
    {'1': 'generation', '3': 2, '4': 1, '5': 9, '10': 'generation'},
    {'1': 'after_number', '3': 3, '4': 1, '5': 13, '10': 'afterNumber'},
    {'1': 'limit', '3': 4, '4': 1, '5': 13, '10': 'limit'},
  ],
};

/// Descriptor for `SearchUuePartsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchUuePartsRequestDescriptor = $convert.base64Decode(
    'ChVTZWFyY2hVdWVQYXJ0c1JlcXVlc3QSIwoNY29uZmVyZW5jZV9pZBgBIAEoCVIMY29uZmVyZW'
    '5jZUlkEh4KCmdlbmVyYXRpb24YAiABKAlSCmdlbmVyYXRpb24SIQoMYWZ0ZXJfbnVtYmVyGAMg'
    'ASgNUgthZnRlck51bWJlchIUCgVsaW1pdBgEIAEoDVIFbGltaXQ=');

@$core.Deprecated('Use searchUuePartsResponseDescriptor instead')
const SearchUuePartsResponse$json = {
  '1': 'SearchUuePartsResponse',
  '2': [
    {
      '1': 'parts',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.UuePart',
      '10': 'parts'
    },
    {'1': 'generation', '3': 2, '4': 1, '5': 9, '10': 'generation'},
    {'1': 'next_number', '3': 3, '4': 1, '5': 13, '10': 'nextNumber'},
    {'1': 'has_more', '3': 4, '4': 1, '5': 8, '10': 'hasMore'},
  ],
};

/// Descriptor for `SearchUuePartsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchUuePartsResponseDescriptor = $convert.base64Decode(
    'ChZTZWFyY2hVdWVQYXJ0c1Jlc3BvbnNlEicKBXBhcnRzGAEgAygLMhEuZmZpZG8udjEuVXVlUG'
    'FydFIFcGFydHMSHgoKZ2VuZXJhdGlvbhgCIAEoCVIKZ2VuZXJhdGlvbhIfCgtuZXh0X251bWJl'
    'chgDIAEoDVIKbmV4dE51bWJlchIZCghoYXNfbW9yZRgEIAEoCFIHaGFzTW9yZQ==');

@$core.Deprecated('Use assembleUueRequestDescriptor instead')
const AssembleUueRequest$json = {
  '1': 'AssembleUueRequest',
  '2': [
    {
      '1': 'sources',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.UuePartReference',
      '10': 'sources'
    },
    {'1': 'explicit_order', '3': 2, '4': 1, '5': 8, '10': 'explicitOrder'},
  ],
};

/// Descriptor for `AssembleUueRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List assembleUueRequestDescriptor = $convert.base64Decode(
    'ChJBc3NlbWJsZVV1ZVJlcXVlc3QSNAoHc291cmNlcxgBIAMoCzIaLmZmaWRvLnYxLlV1ZVBhcn'
    'RSZWZlcmVuY2VSB3NvdXJjZXMSJQoOZXhwbGljaXRfb3JkZXIYAiABKAhSDWV4cGxpY2l0T3Jk'
    'ZXI=');

@$core.Deprecated('Use uueAttachmentDescriptor instead')
const UueAttachment$json = {
  '1': 'UueAttachment',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'filename', '3': 2, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'size', '3': 3, '4': 1, '5': 4, '10': 'size'},
    {'1': 'sha256', '3': 4, '4': 1, '5': 9, '10': 'sha256'},
    {
      '1': 'checksum_verified',
      '3': 5,
      '4': 1,
      '5': 8,
      '10': 'checksumVerified'
    },
    {
      '1': 'state',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.UueState',
      '10': 'state'
    },
    {'1': 'missing_parts', '3': 7, '4': 3, '5': 13, '10': 'missingParts'},
    {
      '1': 'sources',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.UuePartReference',
      '10': 'sources'
    },
    {'1': 'diagnostic', '3': 9, '4': 1, '5': 9, '10': 'diagnostic'},
  ],
};

/// Descriptor for `UueAttachment`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uueAttachmentDescriptor = $convert.base64Decode(
    'Cg1VdWVBdHRhY2htZW50Eg4KAmlkGAEgASgJUgJpZBIaCghmaWxlbmFtZRgCIAEoCVIIZmlsZW'
    '5hbWUSEgoEc2l6ZRgDIAEoBFIEc2l6ZRIWCgZzaGEyNTYYBCABKAlSBnNoYTI1NhIrChFjaGVj'
    'a3N1bV92ZXJpZmllZBgFIAEoCFIQY2hlY2tzdW1WZXJpZmllZBIoCgVzdGF0ZRgGIAEoDjISLm'
    'ZmaWRvLnYxLlV1ZVN0YXRlUgVzdGF0ZRIjCg1taXNzaW5nX3BhcnRzGAcgAygNUgxtaXNzaW5n'
    'UGFydHMSNAoHc291cmNlcxgIIAMoCzIaLmZmaWRvLnYxLlV1ZVBhcnRSZWZlcmVuY2VSB3NvdX'
    'JjZXMSHgoKZGlhZ25vc3RpYxgJIAEoCVIKZGlhZ25vc3RpYw==');

@$core.Deprecated('Use getUueChunkRequestDescriptor instead')
const GetUueChunkRequest$json = {
  '1': 'GetUueChunkRequest',
  '2': [
    {'1': 'attachment_id', '3': 1, '4': 1, '5': 9, '10': 'attachmentId'},
    {'1': 'offset', '3': 2, '4': 1, '5': 4, '10': 'offset'},
    {'1': 'max_bytes', '3': 3, '4': 1, '5': 13, '10': 'maxBytes'},
  ],
};

/// Descriptor for `GetUueChunkRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getUueChunkRequestDescriptor = $convert.base64Decode(
    'ChJHZXRVdWVDaHVua1JlcXVlc3QSIwoNYXR0YWNobWVudF9pZBgBIAEoCVIMYXR0YWNobWVudE'
    'lkEhYKBm9mZnNldBgCIAEoBFIGb2Zmc2V0EhsKCW1heF9ieXRlcxgDIAEoDVIIbWF4Qnl0ZXM=');

@$core.Deprecated('Use uueChunkDescriptor instead')
const UueChunk$json = {
  '1': 'UueChunk',
  '2': [
    {'1': 'data', '3': 1, '4': 1, '5': 12, '10': 'data'},
    {'1': 'offset', '3': 2, '4': 1, '5': 4, '10': 'offset'},
    {'1': 'total_size', '3': 3, '4': 1, '5': 4, '10': 'totalSize'},
    {'1': 'eof', '3': 4, '4': 1, '5': 8, '10': 'eof'},
  ],
};

/// Descriptor for `UueChunk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uueChunkDescriptor = $convert.base64Decode(
    'CghVdWVDaHVuaxISCgRkYXRhGAEgASgMUgRkYXRhEhYKBm9mZnNldBgCIAEoBFIGb2Zmc2V0Eh'
    '0KCnRvdGFsX3NpemUYAyABKARSCXRvdGFsU2l6ZRIQCgNlb2YYBCABKAhSA2VvZg==');

@$core.Deprecated('Use uueOperationReferenceDescriptor instead')
const UueOperationReference$json = {
  '1': 'UueOperationReference',
  '2': [
    {'1': 'operation_id', '3': 1, '4': 1, '5': 9, '10': 'operationId'},
  ],
};

/// Descriptor for `UueOperationReference`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uueOperationReferenceDescriptor = $convert.base64Decode(
    'ChVVdWVPcGVyYXRpb25SZWZlcmVuY2USIQoMb3BlcmF0aW9uX2lkGAEgASgJUgtvcGVyYXRpb2'
    '5JZA==');

@$core.Deprecated('Use uploadUueChunkRequestDescriptor instead')
const UploadUueChunkRequest$json = {
  '1': 'UploadUueChunkRequest',
  '2': [
    {'1': 'operation_id', '3': 1, '4': 1, '5': 9, '10': 'operationId'},
    {'1': 'filename', '3': 2, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'file_size', '3': 3, '4': 1, '5': 4, '10': 'fileSize'},
    {'1': 'sha256', '3': 4, '4': 1, '5': 9, '10': 'sha256'},
    {'1': 'offset', '3': 5, '4': 1, '5': 4, '10': 'offset'},
    {'1': 'data', '3': 6, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `UploadUueChunkRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadUueChunkRequestDescriptor = $convert.base64Decode(
    'ChVVcGxvYWRVdWVDaHVua1JlcXVlc3QSIQoMb3BlcmF0aW9uX2lkGAEgASgJUgtvcGVyYXRpb2'
    '5JZBIaCghmaWxlbmFtZRgCIAEoCVIIZmlsZW5hbWUSGwoJZmlsZV9zaXplGAMgASgEUghmaWxl'
    'U2l6ZRIWCgZzaGEyNTYYBCABKAlSBnNoYTI1NhIWCgZvZmZzZXQYBSABKARSBm9mZnNldBISCg'
    'RkYXRhGAYgASgMUgRkYXRh');

@$core.Deprecated('Use uueUploadStatusDescriptor instead')
const UueUploadStatus$json = {
  '1': 'UueUploadStatus',
  '2': [
    {'1': 'received_bytes', '3': 1, '4': 1, '5': 4, '10': 'receivedBytes'},
    {'1': 'complete', '3': 2, '4': 1, '5': 8, '10': 'complete'},
  ],
};

/// Descriptor for `UueUploadStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uueUploadStatusDescriptor = $convert.base64Decode(
    'Cg9VdWVVcGxvYWRTdGF0dXMSJQoOcmVjZWl2ZWRfYnl0ZXMYASABKARSDXJlY2VpdmVkQnl0ZX'
    'MSGgoIY29tcGxldGUYAiABKAhSCGNvbXBsZXRl');

@$core.Deprecated('Use commitUueRequestDescriptor instead')
const CommitUueRequest$json = {
  '1': 'CommitUueRequest',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.CreateMessageRequest',
      '10': 'message'
    },
  ],
};

/// Descriptor for `CommitUueRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commitUueRequestDescriptor = $convert.base64Decode(
    'ChBDb21taXRVdWVSZXF1ZXN0EjgKB21lc3NhZ2UYASABKAsyHi5mZmlkby52MS5DcmVhdGVNZX'
    'NzYWdlUmVxdWVzdFIHbWVzc2FnZQ==');

@$core.Deprecated('Use uueSendStatusDescriptor instead')
const UueSendStatus$json = {
  '1': 'UueSendStatus',
  '2': [
    {'1': 'operation_id', '3': 1, '4': 1, '5': 9, '10': 'operationId'},
    {'1': 'state', '3': 2, '4': 1, '5': 9, '10': 'state'},
    {'1': 'total_parts', '3': 3, '4': 1, '5': 13, '10': 'totalParts'},
    {'1': 'saved_parts', '3': 4, '4': 1, '5': 13, '10': 'savedParts'},
    {
      '1': 'messages',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.MessageReference',
      '10': 'messages'
    },
    {'1': 'diagnostic', '3': 6, '4': 1, '5': 9, '10': 'diagnostic'},
    {'1': 'filename', '3': 7, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'file_size', '3': 8, '4': 1, '5': 4, '10': 'fileSize'},
    {'1': 'sha256', '3': 9, '4': 1, '5': 9, '10': 'sha256'},
  ],
};

/// Descriptor for `UueSendStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uueSendStatusDescriptor = $convert.base64Decode(
    'Cg1VdWVTZW5kU3RhdHVzEiEKDG9wZXJhdGlvbl9pZBgBIAEoCVILb3BlcmF0aW9uSWQSFAoFc3'
    'RhdGUYAiABKAlSBXN0YXRlEh8KC3RvdGFsX3BhcnRzGAMgASgNUgp0b3RhbFBhcnRzEh8KC3Nh'
    'dmVkX3BhcnRzGAQgASgNUgpzYXZlZFBhcnRzEjYKCG1lc3NhZ2VzGAUgAygLMhouZmZpZG8udj'
    'EuTWVzc2FnZVJlZmVyZW5jZVIIbWVzc2FnZXMSHgoKZGlhZ25vc3RpYxgGIAEoCVIKZGlhZ25v'
    'c3RpYxIaCghmaWxlbmFtZRgHIAEoCVIIZmlsZW5hbWUSGwoJZmlsZV9zaXplGAggASgEUghmaW'
    'xlU2l6ZRIWCgZzaGEyNTYYCSABKAlSBnNoYTI1Ng==');

@$core.Deprecated('Use findMessageRequestDescriptor instead')
const FindMessageRequest$json = {
  '1': 'FindMessageRequest',
  '2': [
    {'1': 'conference_id', '3': 1, '4': 1, '5': 9, '10': 'conferenceId'},
    {'1': 'query', '3': 2, '4': 1, '5': 9, '10': 'query'},
    {
      '1': 'scope',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.MessageSearchScope',
      '10': 'scope'
    },
    {
      '1': 'sort',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.MessageSort',
      '10': 'sort'
    },
    {'1': 'start_message_id', '3': 5, '4': 1, '5': 9, '10': 'startMessageId'},
    {'1': 'include_start', '3': 6, '4': 1, '5': 8, '10': 'includeStart'},
    {
      '1': 'respect_personal_filters',
      '3': 7,
      '4': 1,
      '5': 8,
      '10': 'respectPersonalFilters'
    },
  ],
};

/// Descriptor for `FindMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List findMessageRequestDescriptor = $convert.base64Decode(
    'ChJGaW5kTWVzc2FnZVJlcXVlc3QSIwoNY29uZmVyZW5jZV9pZBgBIAEoCVIMY29uZmVyZW5jZU'
    'lkEhQKBXF1ZXJ5GAIgASgJUgVxdWVyeRIyCgVzY29wZRgDIAEoDjIcLmZmaWRvLnYxLk1lc3Nh'
    'Z2VTZWFyY2hTY29wZVIFc2NvcGUSKQoEc29ydBgEIAEoDjIVLmZmaWRvLnYxLk1lc3NhZ2VTb3'
    'J0UgRzb3J0EigKEHN0YXJ0X21lc3NhZ2VfaWQYBSABKAlSDnN0YXJ0TWVzc2FnZUlkEiMKDWlu'
    'Y2x1ZGVfc3RhcnQYBiABKAhSDGluY2x1ZGVTdGFydBI4ChhyZXNwZWN0X3BlcnNvbmFsX2ZpbH'
    'RlcnMYByABKAhSFnJlc3BlY3RQZXJzb25hbEZpbHRlcnM=');

@$core.Deprecated('Use searchMatchDescriptor instead')
const SearchMatch$json = {
  '1': 'SearchMatch',
  '2': [
    {
      '1': 'field',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.MessageSearchField',
      '10': 'field'
    },
    {'1': 'start_utf16', '3': 2, '4': 1, '5': 13, '10': 'startUtf16'},
    {'1': 'length_utf16', '3': 3, '4': 1, '5': 13, '10': 'lengthUtf16'},
  ],
};

/// Descriptor for `SearchMatch`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchMatchDescriptor = $convert.base64Decode(
    'CgtTZWFyY2hNYXRjaBIyCgVmaWVsZBgBIAEoDjIcLmZmaWRvLnYxLk1lc3NhZ2VTZWFyY2hGaW'
    'VsZFIFZmllbGQSHwoLc3RhcnRfdXRmMTYYAiABKA1SCnN0YXJ0VXRmMTYSIQoMbGVuZ3RoX3V0'
    'ZjE2GAMgASgNUgtsZW5ndGhVdGYxNg==');

@$core.Deprecated('Use findMessageResponseDescriptor instead')
const FindMessageResponse$json = {
  '1': 'FindMessageResponse',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.Message',
      '10': 'message'
    },
    {
      '1': 'matches',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.SearchMatch',
      '10': 'matches'
    },
  ],
};

/// Descriptor for `FindMessageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List findMessageResponseDescriptor = $convert.base64Decode(
    'ChNGaW5kTWVzc2FnZVJlc3BvbnNlEisKB21lc3NhZ2UYASABKAsyES5mZmlkby52MS5NZXNzYW'
    'dlUgdtZXNzYWdlEi8KB21hdGNoZXMYAiADKAsyFS5mZmlkby52MS5TZWFyY2hNYXRjaFIHbWF0'
    'Y2hlcw==');

@$core.Deprecated('Use messageTechnicalSubfieldDescriptor instead')
const MessageTechnicalSubfield$json = {
  '1': 'MessageTechnicalSubfield',
  '2': [
    {'1': 'low_id', '3': 1, '4': 1, '5': 13, '10': 'lowId'},
    {'1': 'high_id', '3': 2, '4': 1, '5': 13, '10': 'highId'},
    {'1': 'value', '3': 3, '4': 1, '5': 12, '10': 'value'},
  ],
};

/// Descriptor for `MessageTechnicalSubfield`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageTechnicalSubfieldDescriptor =
    $convert.base64Decode(
        'ChhNZXNzYWdlVGVjaG5pY2FsU3ViZmllbGQSFQoGbG93X2lkGAEgASgNUgVsb3dJZBIXCgdoaW'
        'doX2lkGAIgASgNUgZoaWdoSWQSFAoFdmFsdWUYAyABKAxSBXZhbHVl');

@$core.Deprecated('Use messageTechnicalDataDescriptor instead')
const MessageTechnicalData$json = {
  '1': 'MessageTechnicalData',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.MessageReference',
      '10': 'message'
    },
    {'1': 'attributes', '3': 2, '4': 1, '5': 13, '10': 'attributes'},
    {'1': 'attributes2', '3': 3, '4': 1, '5': 13, '10': 'attributes2'},
    {
      '1': 'subfields',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.MessageTechnicalSubfield',
      '10': 'subfields'
    },
    {
      '1': 'encoding_status',
      '3': 5,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.TechnicalEncodingStatus',
      '10': 'encodingStatus'
    },
    {
      '1': 'effective_encoding',
      '3': 6,
      '4': 1,
      '5': 9,
      '10': 'effectiveEncoding'
    },
  ],
};

/// Descriptor for `MessageTechnicalData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageTechnicalDataDescriptor = $convert.base64Decode(
    'ChRNZXNzYWdlVGVjaG5pY2FsRGF0YRI0CgdtZXNzYWdlGAEgASgLMhouZmZpZG8udjEuTWVzc2'
    'FnZVJlZmVyZW5jZVIHbWVzc2FnZRIeCgphdHRyaWJ1dGVzGAIgASgNUgphdHRyaWJ1dGVzEiAK'
    'C2F0dHJpYnV0ZXMyGAMgASgNUgthdHRyaWJ1dGVzMhJACglzdWJmaWVsZHMYBCADKAsyIi5mZm'
    'lkby52MS5NZXNzYWdlVGVjaG5pY2FsU3ViZmllbGRSCXN1YmZpZWxkcxJKCg9lbmNvZGluZ19z'
    'dGF0dXMYBSABKA4yIS5mZmlkby52MS5UZWNobmljYWxFbmNvZGluZ1N0YXR1c1IOZW5jb2Rpbm'
    'dTdGF0dXMSLQoSZWZmZWN0aXZlX2VuY29kaW5nGAYgASgJUhFlZmZlY3RpdmVFbmNvZGluZw==');

@$core.Deprecated('Use personalMessageFilterDescriptor instead')
const PersonalMessageFilter$json = {
  '1': 'PersonalMessageFilter',
  '2': [
    {'1': 'rule_id', '3': 1, '4': 1, '5': 9, '10': 'ruleId'},
    {'1': 'enabled', '3': 2, '4': 1, '5': 8, '10': 'enabled'},
    {
      '1': 'scope',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.PersonalMessageFilterScope',
      '10': 'scope'
    },
    {'1': 'conference_id', '3': 4, '4': 1, '5': 9, '10': 'conferenceId'},
    {'1': 'author_contains', '3': 5, '4': 1, '5': 9, '10': 'authorContains'},
    {'1': 'address_equals', '3': 6, '4': 1, '5': 9, '10': 'addressEquals'},
    {'1': 'subject_contains', '3': 7, '4': 1, '5': 9, '10': 'subjectContains'},
  ],
};

/// Descriptor for `PersonalMessageFilter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List personalMessageFilterDescriptor = $convert.base64Decode(
    'ChVQZXJzb25hbE1lc3NhZ2VGaWx0ZXISFwoHcnVsZV9pZBgBIAEoCVIGcnVsZUlkEhgKB2VuYW'
    'JsZWQYAiABKAhSB2VuYWJsZWQSOgoFc2NvcGUYAyABKA4yJC5mZmlkby52MS5QZXJzb25hbE1l'
    'c3NhZ2VGaWx0ZXJTY29wZVIFc2NvcGUSIwoNY29uZmVyZW5jZV9pZBgEIAEoCVIMY29uZmVyZW'
    '5jZUlkEicKD2F1dGhvcl9jb250YWlucxgFIAEoCVIOYXV0aG9yQ29udGFpbnMSJQoOYWRkcmVz'
    'c19lcXVhbHMYBiABKAlSDWFkZHJlc3NFcXVhbHMSKQoQc3ViamVjdF9jb250YWlucxgHIAEoCV'
    'IPc3ViamVjdENvbnRhaW5z');

@$core.Deprecated('Use personalMessageFilterSetDescriptor instead')
const PersonalMessageFilterSet$json = {
  '1': 'PersonalMessageFilterSet',
  '2': [
    {'1': 'revision', '3': 1, '4': 1, '5': 4, '10': 'revision'},
    {
      '1': 'rules',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.PersonalMessageFilter',
      '10': 'rules'
    },
  ],
};

/// Descriptor for `PersonalMessageFilterSet`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List personalMessageFilterSetDescriptor = $convert.base64Decode(
    'ChhQZXJzb25hbE1lc3NhZ2VGaWx0ZXJTZXQSGgoIcmV2aXNpb24YASABKARSCHJldmlzaW9uEj'
    'UKBXJ1bGVzGAIgAygLMh8uZmZpZG8udjEuUGVyc29uYWxNZXNzYWdlRmlsdGVyUgVydWxlcw==');

@$core.Deprecated('Use replacePersonalMessageFiltersRequestDescriptor instead')
const ReplacePersonalMessageFiltersRequest$json = {
  '1': 'ReplacePersonalMessageFiltersRequest',
  '2': [
    {
      '1': 'expected_revision',
      '3': 1,
      '4': 1,
      '5': 4,
      '10': 'expectedRevision'
    },
    {'1': 'operation_id', '3': 2, '4': 1, '5': 9, '10': 'operationId'},
    {
      '1': 'rules',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.PersonalMessageFilter',
      '10': 'rules'
    },
  ],
};

/// Descriptor for `ReplacePersonalMessageFiltersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List replacePersonalMessageFiltersRequestDescriptor =
    $convert.base64Decode(
        'CiRSZXBsYWNlUGVyc29uYWxNZXNzYWdlRmlsdGVyc1JlcXVlc3QSKwoRZXhwZWN0ZWRfcmV2aX'
        'Npb24YASABKARSEGV4cGVjdGVkUmV2aXNpb24SIQoMb3BlcmF0aW9uX2lkGAIgASgJUgtvcGVy'
        'YXRpb25JZBI1CgVydWxlcxgDIAMoCzIfLmZmaWRvLnYxLlBlcnNvbmFsTWVzc2FnZUZpbHRlcl'
        'IFcnVsZXM=');

@$core.Deprecated('Use replacePersonalMessageFiltersResponseDescriptor instead')
const ReplacePersonalMessageFiltersResponse$json = {
  '1': 'ReplacePersonalMessageFiltersResponse',
  '2': [
    {'1': 'revision', '3': 1, '4': 1, '5': 4, '10': 'revision'},
  ],
};

/// Descriptor for `ReplacePersonalMessageFiltersResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List replacePersonalMessageFiltersResponseDescriptor =
    $convert.base64Decode(
        'CiVSZXBsYWNlUGVyc29uYWxNZXNzYWdlRmlsdGVyc1Jlc3BvbnNlEhoKCHJldmlzaW9uGAEgAS'
        'gEUghyZXZpc2lvbg==');

@$core.Deprecated('Use personalMessageCollapseDescriptor instead')
const PersonalMessageCollapse$json = {
  '1': 'PersonalMessageCollapse',
  '2': [
    {'1': 'rules_revision', '3': 1, '4': 1, '5': 4, '10': 'rulesRevision'},
    {'1': 'matched_rule_ids', '3': 2, '4': 3, '5': 9, '10': 'matchedRuleIds'},
  ],
};

/// Descriptor for `PersonalMessageCollapse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List personalMessageCollapseDescriptor = $convert.base64Decode(
    'ChdQZXJzb25hbE1lc3NhZ2VDb2xsYXBzZRIlCg5ydWxlc19yZXZpc2lvbhgBIAEoBFINcnVsZX'
    'NSZXZpc2lvbhIoChBtYXRjaGVkX3J1bGVfaWRzGAIgAygJUg5tYXRjaGVkUnVsZUlkcw==');

@$core.Deprecated('Use getMessagePresentationRequestDescriptor instead')
const GetMessagePresentationRequest$json = {
  '1': 'GetMessagePresentationRequest',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.MessageReference',
      '10': 'message'
    },
    {'1': 'reveal', '3': 2, '4': 1, '5': 8, '10': 'reveal'},
    {'1': 'search_query', '3': 3, '4': 1, '5': 9, '10': 'searchQuery'},
    {
      '1': 'search_scope',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.MessageSearchScope',
      '10': 'searchScope'
    },
  ],
};

/// Descriptor for `GetMessagePresentationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getMessagePresentationRequestDescriptor = $convert.base64Decode(
    'Ch1HZXRNZXNzYWdlUHJlc2VudGF0aW9uUmVxdWVzdBI0CgdtZXNzYWdlGAEgASgLMhouZmZpZG'
    '8udjEuTWVzc2FnZVJlZmVyZW5jZVIHbWVzc2FnZRIWCgZyZXZlYWwYAiABKAhSBnJldmVhbBIh'
    'CgxzZWFyY2hfcXVlcnkYAyABKAlSC3NlYXJjaFF1ZXJ5Ej8KDHNlYXJjaF9zY29wZRgEIAEoDj'
    'IcLmZmaWRvLnYxLk1lc3NhZ2VTZWFyY2hTY29wZVILc2VhcmNoU2NvcGU=');

@$core.Deprecated('Use collapsedMessageHeadersDescriptor instead')
const CollapsedMessageHeaders$json = {
  '1': 'CollapsedMessageHeaders',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.MessageReference',
      '10': 'message'
    },
    {'1': 'from_name', '3': 2, '4': 1, '5': 9, '10': 'fromName'},
    {'1': 'from_address', '3': 3, '4': 1, '5': 9, '10': 'fromAddress'},
    {'1': 'subject', '3': 4, '4': 1, '5': 9, '10': 'subject'},
    {
      '1': 'date',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'date'
    },
    {'1': 'is_read', '3': 6, '4': 1, '5': 8, '10': 'isRead'},
    {'1': 'thread_id', '3': 7, '4': 1, '5': 9, '10': 'threadId'},
    {'1': 'in_reply_to', '3': 8, '4': 1, '5': 9, '10': 'inReplyTo'},
  ],
};

/// Descriptor for `CollapsedMessageHeaders`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List collapsedMessageHeadersDescriptor = $convert.base64Decode(
    'ChdDb2xsYXBzZWRNZXNzYWdlSGVhZGVycxI0CgdtZXNzYWdlGAEgASgLMhouZmZpZG8udjEuTW'
    'Vzc2FnZVJlZmVyZW5jZVIHbWVzc2FnZRIbCglmcm9tX25hbWUYAiABKAlSCGZyb21OYW1lEiEK'
    'DGZyb21fYWRkcmVzcxgDIAEoCVILZnJvbUFkZHJlc3MSGAoHc3ViamVjdBgEIAEoCVIHc3Viam'
    'VjdBIuCgRkYXRlGAUgASgLMhouZ29vZ2xlLnByb3RvYnVmLlRpbWVzdGFtcFIEZGF0ZRIXCgdp'
    'c19yZWFkGAYgASgIUgZpc1JlYWQSGwoJdGhyZWFkX2lkGAcgASgJUgh0aHJlYWRJZBIeCgtpbl'
    '9yZXBseV90bxgIIAEoCVIJaW5SZXBseVRv');

@$core.Deprecated('Use messagePresentationDescriptor instead')
const MessagePresentation$json = {
  '1': 'MessagePresentation',
  '2': [
    {'1': 'rules_revision', '3': 1, '4': 1, '5': 4, '10': 'rulesRevision'},
    {'1': 'matched_rule_ids', '3': 2, '4': 3, '5': 9, '10': 'matchedRuleIds'},
    {
      '1': 'visible',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.Message',
      '9': 0,
      '10': 'visible'
    },
    {
      '1': 'collapsed',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.CollapsedMessageHeaders',
      '9': 0,
      '10': 'collapsed'
    },
    {
      '1': 'matches',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.SearchMatch',
      '10': 'matches'
    },
  ],
  '8': [
    {'1': 'content'},
  ],
};

/// Descriptor for `MessagePresentation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messagePresentationDescriptor = $convert.base64Decode(
    'ChNNZXNzYWdlUHJlc2VudGF0aW9uEiUKDnJ1bGVzX3JldmlzaW9uGAEgASgEUg1ydWxlc1Jldm'
    'lzaW9uEigKEG1hdGNoZWRfcnVsZV9pZHMYAiADKAlSDm1hdGNoZWRSdWxlSWRzEi0KB3Zpc2li'
    'bGUYAyABKAsyES5mZmlkby52MS5NZXNzYWdlSABSB3Zpc2libGUSQQoJY29sbGFwc2VkGAQgAS'
    'gLMiEuZmZpZG8udjEuQ29sbGFwc2VkTWVzc2FnZUhlYWRlcnNIAFIJY29sbGFwc2VkEi8KB21h'
    'dGNoZXMYBSADKAsyFS5mZmlkby52MS5TZWFyY2hNYXRjaFIHbWF0Y2hlc0IJCgdjb250ZW50');

@$core.Deprecated('Use searchArchiveMessagesRequestDescriptor instead')
const SearchArchiveMessagesRequest$json = {
  '1': 'SearchArchiveMessagesRequest',
  '2': [
    {'1': 'conference_ids', '3': 1, '4': 3, '5': 9, '10': 'conferenceIds'},
    {'1': 'query', '3': 2, '4': 1, '5': 9, '10': 'query'},
    {
      '1': 'scope',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.MessageSearchScope',
      '10': 'scope'
    },
    {
      '1': 'from',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'from'
    },
    {
      '1': 'to',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.google.protobuf.Timestamp',
      '10': 'to'
    },
    {
      '1': 'sort',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.MessageSort',
      '10': 'sort'
    },
    {'1': 'limit', '3': 7, '4': 1, '5': 5, '10': 'limit'},
    {'1': 'cursor', '3': 8, '4': 1, '5': 9, '10': 'cursor'},
  ],
};

/// Descriptor for `SearchArchiveMessagesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchArchiveMessagesRequestDescriptor = $convert.base64Decode(
    'ChxTZWFyY2hBcmNoaXZlTWVzc2FnZXNSZXF1ZXN0EiUKDmNvbmZlcmVuY2VfaWRzGAEgAygJUg'
    '1jb25mZXJlbmNlSWRzEhQKBXF1ZXJ5GAIgASgJUgVxdWVyeRIyCgVzY29wZRgDIAEoDjIcLmZm'
    'aWRvLnYxLk1lc3NhZ2VTZWFyY2hTY29wZVIFc2NvcGUSLgoEZnJvbRgEIAEoCzIaLmdvb2dsZS'
    '5wcm90b2J1Zi5UaW1lc3RhbXBSBGZyb20SKgoCdG8YBSABKAsyGi5nb29nbGUucHJvdG9idWYu'
    'VGltZXN0YW1wUgJ0bxIpCgRzb3J0GAYgASgOMhUuZmZpZG8udjEuTWVzc2FnZVNvcnRSBHNvcn'
    'QSFAoFbGltaXQYByABKAVSBWxpbWl0EhYKBmN1cnNvchgIIAEoCVIGY3Vyc29y');

@$core.Deprecated('Use archiveSearchResultDescriptor instead')
const ArchiveSearchResult$json = {
  '1': 'ArchiveSearchResult',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.Message',
      '10': 'message'
    },
    {'1': 'snippet', '3': 2, '4': 1, '5': 9, '10': 'snippet'},
    {
      '1': 'matches',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.SearchMatch',
      '10': 'matches'
    },
  ],
};

/// Descriptor for `ArchiveSearchResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List archiveSearchResultDescriptor = $convert.base64Decode(
    'ChNBcmNoaXZlU2VhcmNoUmVzdWx0EisKB21lc3NhZ2UYASABKAsyES5mZmlkby52MS5NZXNzYW'
    'dlUgdtZXNzYWdlEhgKB3NuaXBwZXQYAiABKAlSB3NuaXBwZXQSLwoHbWF0Y2hlcxgDIAMoCzIV'
    'LmZmaWRvLnYxLlNlYXJjaE1hdGNoUgdtYXRjaGVz');

@$core.Deprecated('Use searchArchiveMessagesResponseDescriptor instead')
const SearchArchiveMessagesResponse$json = {
  '1': 'SearchArchiveMessagesResponse',
  '2': [
    {
      '1': 'results',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.ffido.v1.ArchiveSearchResult',
      '10': 'results'
    },
    {'1': 'complete', '3': 2, '4': 1, '5': 8, '10': 'complete'},
    {
      '1': 'incomplete_reason',
      '3': 3,
      '4': 1,
      '5': 9,
      '10': 'incompleteReason'
    },
    {'1': 'next_cursor', '3': 4, '4': 1, '5': 9, '10': 'nextCursor'},
  ],
};

/// Descriptor for `SearchArchiveMessagesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchArchiveMessagesResponseDescriptor = $convert.base64Decode(
    'Ch1TZWFyY2hBcmNoaXZlTWVzc2FnZXNSZXNwb25zZRI3CgdyZXN1bHRzGAEgAygLMh0uZmZpZG'
    '8udjEuQXJjaGl2ZVNlYXJjaFJlc3VsdFIHcmVzdWx0cxIaCghjb21wbGV0ZRgCIAEoCFIIY29t'
    'cGxldGUSKwoRaW5jb21wbGV0ZV9yZWFzb24YAyABKAlSEGluY29tcGxldGVSZWFzb24SHwoLbm'
    'V4dF9jdXJzb3IYBCABKAlSCm5leHRDdXJzb3I=');

@$core.Deprecated('Use readArchiveMessageRequestDescriptor instead')
const ReadArchiveMessageRequest$json = {
  '1': 'ReadArchiveMessageRequest',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.MessageReference',
      '10': 'message'
    },
    {'1': 'body_offset', '3': 2, '4': 1, '5': 4, '10': 'bodyOffset'},
    {'1': 'body_limit', '3': 3, '4': 1, '5': 13, '10': 'bodyLimit'},
    {'1': 'reveal', '3': 4, '4': 1, '5': 8, '10': 'reveal'},
  ],
};

/// Descriptor for `ReadArchiveMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readArchiveMessageRequestDescriptor = $convert.base64Decode(
    'ChlSZWFkQXJjaGl2ZU1lc3NhZ2VSZXF1ZXN0EjQKB21lc3NhZ2UYASABKAsyGi5mZmlkby52MS'
    '5NZXNzYWdlUmVmZXJlbmNlUgdtZXNzYWdlEh8KC2JvZHlfb2Zmc2V0GAIgASgEUgpib2R5T2Zm'
    'c2V0Eh0KCmJvZHlfbGltaXQYAyABKA1SCWJvZHlMaW1pdBIWCgZyZXZlYWwYBCABKAhSBnJldm'
    'VhbA==');

@$core.Deprecated('Use readArchiveMessageResponseDescriptor instead')
const ReadArchiveMessageResponse$json = {
  '1': 'ReadArchiveMessageResponse',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.Message',
      '10': 'message'
    },
    {'1': 'body_offset', '3': 2, '4': 1, '5': 4, '10': 'bodyOffset'},
    {'1': 'next_offset', '3': 3, '4': 1, '5': 4, '10': 'nextOffset'},
    {'1': 'complete', '3': 4, '4': 1, '5': 8, '10': 'complete'},
    {'1': 'collapsed', '3': 5, '4': 1, '5': 8, '10': 'collapsed'},
  ],
};

/// Descriptor for `ReadArchiveMessageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readArchiveMessageResponseDescriptor = $convert.base64Decode(
    'ChpSZWFkQXJjaGl2ZU1lc3NhZ2VSZXNwb25zZRIrCgdtZXNzYWdlGAEgASgLMhEuZmZpZG8udj'
    'EuTWVzc2FnZVIHbWVzc2FnZRIfCgtib2R5X29mZnNldBgCIAEoBFIKYm9keU9mZnNldBIfCgtu'
    'ZXh0X29mZnNldBgDIAEoBFIKbmV4dE9mZnNldBIaCghjb21wbGV0ZRgEIAEoCFIIY29tcGxldG'
    'USHAoJY29sbGFwc2VkGAUgASgIUgljb2xsYXBzZWQ=');

@$core.Deprecated('Use getArchiveThreadRequestDescriptor instead')
const GetArchiveThreadRequest$json = {
  '1': 'GetArchiveThreadRequest',
  '2': [
    {
      '1': 'message',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.MessageReference',
      '10': 'message'
    },
    {
      '1': 'page',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.ffido.v1.PageRequest',
      '10': 'page'
    },
  ],
};

/// Descriptor for `GetArchiveThreadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getArchiveThreadRequestDescriptor = $convert.base64Decode(
    'ChdHZXRBcmNoaXZlVGhyZWFkUmVxdWVzdBI0CgdtZXNzYWdlGAEgASgLMhouZmZpZG8udjEuTW'
    'Vzc2FnZVJlZmVyZW5jZVIHbWVzc2FnZRIpCgRwYWdlGAIgASgLMhUuZmZpZG8udjEuUGFnZVJl'
    'cXVlc3RSBHBhZ2U=');

@$core.Deprecated('Use messagePreviewDescriptor instead')
const MessagePreview$json = {
  '1': 'MessagePreview',
  '2': [
    {'1': 'conference_id', '3': 1, '4': 1, '5': 9, '10': 'conferenceId'},
    {'1': 'from_name', '3': 2, '4': 1, '5': 9, '10': 'fromName'},
    {'1': 'from_address', '3': 3, '4': 1, '5': 9, '10': 'fromAddress'},
    {'1': 'to_name', '3': 4, '4': 1, '5': 9, '10': 'toName'},
    {'1': 'to_address', '3': 5, '4': 1, '5': 9, '10': 'toAddress'},
    {'1': 'subject', '3': 6, '4': 1, '5': 9, '10': 'subject'},
    {'1': 'body', '3': 7, '4': 1, '5': 9, '10': 'body'},
    {
      '1': 'effective_encoding',
      '3': 8,
      '4': 1,
      '5': 9,
      '10': 'effectiveEncoding'
    },
    {'1': 'wire_body_bytes', '3': 9, '4': 1, '5': 4, '10': 'wireBodyBytes'},
    {'1': 'preview_digest', '3': 10, '4': 1, '5': 9, '10': 'previewDigest'},
    {
      '1': 'kind',
      '3': 11,
      '4': 1,
      '5': 14,
      '6': '.ffido.v1.AreaKind',
      '10': 'kind'
    },
    {'1': 'public_message', '3': 12, '4': 1, '5': 8, '10': 'publicMessage'},
    {'1': 'in_reply_to', '3': 13, '4': 1, '5': 9, '10': 'inReplyTo'},
  ],
};

/// Descriptor for `MessagePreview`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messagePreviewDescriptor = $convert.base64Decode(
    'Cg5NZXNzYWdlUHJldmlldxIjCg1jb25mZXJlbmNlX2lkGAEgASgJUgxjb25mZXJlbmNlSWQSGw'
    'oJZnJvbV9uYW1lGAIgASgJUghmcm9tTmFtZRIhCgxmcm9tX2FkZHJlc3MYAyABKAlSC2Zyb21B'
    'ZGRyZXNzEhcKB3RvX25hbWUYBCABKAlSBnRvTmFtZRIdCgp0b19hZGRyZXNzGAUgASgJUgl0b0'
    'FkZHJlc3MSGAoHc3ViamVjdBgGIAEoCVIHc3ViamVjdBISCgRib2R5GAcgASgJUgRib2R5Ei0K'
    'EmVmZmVjdGl2ZV9lbmNvZGluZxgIIAEoCVIRZWZmZWN0aXZlRW5jb2RpbmcSJgoPd2lyZV9ib2'
    'R5X2J5dGVzGAkgASgEUg13aXJlQm9keUJ5dGVzEiUKDnByZXZpZXdfZGlnZXN0GAogASgJUg1w'
    'cmV2aWV3RGlnZXN0EiYKBGtpbmQYCyABKA4yEi5mZmlkby52MS5BcmVhS2luZFIEa2luZBIlCg'
    '5wdWJsaWNfbWVzc2FnZRgMIAEoCFINcHVibGljTWVzc2FnZRIeCgtpbl9yZXBseV90bxgNIAEo'
    'CVIJaW5SZXBseVRv');
