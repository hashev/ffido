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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $2;

import 'ffido.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'ffido.pbenum.dart';

/// offset >= 0, limit от 1 до 100; нулевой limit не означает unlimited.
class PageRequest extends $pb.GeneratedMessage {
  factory PageRequest({
    $fixnum.Int64? offset,
    $core.int? limit,
  }) {
    final result = PageRequest._();
    if (offset != null) result.offset = offset;
    if (limit != null) result.limit = limit;
    return result;
  }

  PageRequest._();

  factory PageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PageRequest()..mergeFromBuffer(data, registry);
  factory PageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PageRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PageRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: PageRequest.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'offset')
    ..aI(2, _omitFieldNames ? '' : 'limit')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PageRequest copyWith(void Function(PageRequest) updates) =>
      super.copyWith((message) => updates(message as PageRequest))
          as PageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PageRequest() / PageRequest.new instead')
  static PageRequest create() => PageRequest._();
  static $pb.GeneratedMessage $_createMessage() => PageRequest._();
  @$core.override
  PageRequest createEmptyInstance() => PageRequest._();
  @$core.pragma('dart2js:noInline')
  static PageRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PageRequest>(
          PageRequest.$_createMessage);
  static PageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get offset => $_getI64(0);
  @$pb.TagNumber(1)
  set offset($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOffset() => $_has(0);
  @$pb.TagNumber(1)
  void clearOffset() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get limit => $_getIZ(1);
  @$pb.TagNumber(2)
  set limit($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => $_clearField(2);
}

class ListConferencesRequest extends $pb.GeneratedMessage {
  factory ListConferencesRequest({
    PageRequest? page,
    $core.String? query,
    ConferenceSort? sort,
  }) {
    final result = ListConferencesRequest._();
    if (page != null) result.page = page;
    if (query != null) result.query = query;
    if (sort != null) result.sort = sort;
    return result;
  }

  ListConferencesRequest._();

  factory ListConferencesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListConferencesRequest()..mergeFromBuffer(data, registry);
  factory ListConferencesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListConferencesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListConferencesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ListConferencesRequest.$_createMessage)
    ..aOM<PageRequest>(1, _omitFieldNames ? '' : 'page',
        subBuilder: PageRequest.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'query')
    ..aE<ConferenceSort>(3, _omitFieldNames ? '' : 'sort',
        enumValues: ConferenceSort.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListConferencesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListConferencesRequest copyWith(
          void Function(ListConferencesRequest) updates) =>
      super.copyWith((message) => updates(message as ListConferencesRequest))
          as ListConferencesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListConferencesRequest() / ListConferencesRequest.new instead')
  static ListConferencesRequest create() => ListConferencesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListConferencesRequest._();
  @$core.override
  ListConferencesRequest createEmptyInstance() => ListConferencesRequest._();
  @$core.pragma('dart2js:noInline')
  static ListConferencesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListConferencesRequest>(
          ListConferencesRequest.$_createMessage);
  static ListConferencesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  PageRequest get page => $_getN(0);
  @$pb.TagNumber(1)
  set page(PageRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPage() => $_has(0);
  @$pb.TagNumber(1)
  void clearPage() => $_clearField(1);
  @$pb.TagNumber(1)
  PageRequest ensurePage() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get query => $_getSZ(1);
  @$pb.TagNumber(2)
  set query($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasQuery() => $_has(1);
  @$pb.TagNumber(2)
  void clearQuery() => $_clearField(2);

  @$pb.TagNumber(3)
  ConferenceSort get sort => $_getN(2);
  @$pb.TagNumber(3)
  set sort(ConferenceSort value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasSort() => $_has(2);
  @$pb.TagNumber(3)
  void clearSort() => $_clearField(3);
}

class GetConferenceRequest extends $pb.GeneratedMessage {
  factory GetConferenceRequest({
    $core.String? conferenceId,
  }) {
    final result = GetConferenceRequest._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    return result;
  }

  GetConferenceRequest._();

  factory GetConferenceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetConferenceRequest()..mergeFromBuffer(data, registry);
  factory GetConferenceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetConferenceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetConferenceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: GetConferenceRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'conferenceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetConferenceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetConferenceRequest copyWith(void Function(GetConferenceRequest) updates) =>
      super.copyWith((message) => updates(message as GetConferenceRequest))
          as GetConferenceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetConferenceRequest() / GetConferenceRequest.new instead')
  static GetConferenceRequest create() => GetConferenceRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetConferenceRequest._();
  @$core.override
  GetConferenceRequest createEmptyInstance() => GetConferenceRequest._();
  @$core.pragma('dart2js:noInline')
  static GetConferenceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetConferenceRequest>(
          GetConferenceRequest.$_createMessage);
  static GetConferenceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conferenceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conferenceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConferenceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConferenceId() => $_clearField(1);
}

class Conference extends $pb.GeneratedMessage {
  factory Conference({
    $core.String? id,
    $core.String? name,
    $core.String? description,
    $fixnum.Int64? unreadCount,
    $fixnum.Int64? totalCount,
    $2.Timestamp? lastMessageDate,
    $core.bool? isBookmarked,
    $core.bool? canRead,
    $core.bool? canPost,
    AreaKind? kind,
    $core.String? storageFormat,
    AreaAvailability? availability,
    $core.bool? statisticsKnown,
    $core.bool? personalMailbox,
    $core.String? lastOpenedMessageId,
    $fixnum.Int64? positionRevision,
  }) {
    final result = Conference._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (description != null) result.description = description;
    if (unreadCount != null) result.unreadCount = unreadCount;
    if (totalCount != null) result.totalCount = totalCount;
    if (lastMessageDate != null) result.lastMessageDate = lastMessageDate;
    if (isBookmarked != null) result.isBookmarked = isBookmarked;
    if (canRead != null) result.canRead = canRead;
    if (canPost != null) result.canPost = canPost;
    if (kind != null) result.kind = kind;
    if (storageFormat != null) result.storageFormat = storageFormat;
    if (availability != null) result.availability = availability;
    if (statisticsKnown != null) result.statisticsKnown = statisticsKnown;
    if (personalMailbox != null) result.personalMailbox = personalMailbox;
    if (lastOpenedMessageId != null)
      result.lastOpenedMessageId = lastOpenedMessageId;
    if (positionRevision != null) result.positionRevision = positionRevision;
    return result;
  }

  Conference._();

  factory Conference.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Conference()..mergeFromBuffer(data, registry);
  factory Conference.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Conference()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Conference',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: Conference.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..aInt64(4, _omitFieldNames ? '' : 'unreadCount')
    ..aInt64(5, _omitFieldNames ? '' : 'totalCount')
    ..aOM<$2.Timestamp>(6, _omitFieldNames ? '' : 'lastMessageDate',
        subBuilder: $2.Timestamp.$_createMessage)
    ..aOB(7, _omitFieldNames ? '' : 'isBookmarked')
    ..aOB(8, _omitFieldNames ? '' : 'canRead')
    ..aOB(9, _omitFieldNames ? '' : 'canPost')
    ..aE<AreaKind>(10, _omitFieldNames ? '' : 'kind',
        enumValues: AreaKind.values)
    ..aOS(11, _omitFieldNames ? '' : 'storageFormat')
    ..aE<AreaAvailability>(12, _omitFieldNames ? '' : 'availability',
        enumValues: AreaAvailability.values)
    ..aOB(13, _omitFieldNames ? '' : 'statisticsKnown')
    ..aOB(14, _omitFieldNames ? '' : 'personalMailbox')
    ..aOS(15, _omitFieldNames ? '' : 'lastOpenedMessageId')
    ..a<$fixnum.Int64>(
        16, _omitFieldNames ? '' : 'positionRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Conference clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Conference copyWith(void Function(Conference) updates) =>
      super.copyWith((message) => updates(message as Conference)) as Conference;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Conference() / Conference.new instead')
  static Conference create() => Conference._();
  static $pb.GeneratedMessage $_createMessage() => Conference._();
  @$core.override
  Conference createEmptyInstance() => Conference._();
  @$core.pragma('dart2js:noInline')
  static Conference getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Conference>(Conference.$_createMessage);
  static Conference? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get unreadCount => $_getI64(3);
  @$pb.TagNumber(4)
  set unreadCount($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUnreadCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearUnreadCount() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get totalCount => $_getI64(4);
  @$pb.TagNumber(5)
  set totalCount($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTotalCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalCount() => $_clearField(5);

  @$pb.TagNumber(6)
  $2.Timestamp get lastMessageDate => $_getN(5);
  @$pb.TagNumber(6)
  set lastMessageDate($2.Timestamp value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasLastMessageDate() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastMessageDate() => $_clearField(6);
  @$pb.TagNumber(6)
  $2.Timestamp ensureLastMessageDate() => $_ensure(5);

  @$pb.TagNumber(7)
  $core.bool get isBookmarked => $_getBF(6);
  @$pb.TagNumber(7)
  set isBookmarked($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsBookmarked() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsBookmarked() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get canRead => $_getBF(7);
  @$pb.TagNumber(8)
  set canRead($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCanRead() => $_has(7);
  @$pb.TagNumber(8)
  void clearCanRead() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get canPost => $_getBF(8);
  @$pb.TagNumber(9)
  set canPost($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCanPost() => $_has(8);
  @$pb.TagNumber(9)
  void clearCanPost() => $_clearField(9);

  @$pb.TagNumber(10)
  AreaKind get kind => $_getN(9);
  @$pb.TagNumber(10)
  set kind(AreaKind value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasKind() => $_has(9);
  @$pb.TagNumber(10)
  void clearKind() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get storageFormat => $_getSZ(10);
  @$pb.TagNumber(11)
  set storageFormat($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasStorageFormat() => $_has(10);
  @$pb.TagNumber(11)
  void clearStorageFormat() => $_clearField(11);

  @$pb.TagNumber(12)
  AreaAvailability get availability => $_getN(11);
  @$pb.TagNumber(12)
  set availability(AreaAvailability value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasAvailability() => $_has(11);
  @$pb.TagNumber(12)
  void clearAvailability() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.bool get statisticsKnown => $_getBF(12);
  @$pb.TagNumber(13)
  set statisticsKnown($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(13)
  $core.bool hasStatisticsKnown() => $_has(12);
  @$pb.TagNumber(13)
  void clearStatisticsKnown() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.bool get personalMailbox => $_getBF(13);
  @$pb.TagNumber(14)
  set personalMailbox($core.bool value) => $_setBool(13, value);
  @$pb.TagNumber(14)
  $core.bool hasPersonalMailbox() => $_has(13);
  @$pb.TagNumber(14)
  void clearPersonalMailbox() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get lastOpenedMessageId => $_getSZ(14);
  @$pb.TagNumber(15)
  set lastOpenedMessageId($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasLastOpenedMessageId() => $_has(14);
  @$pb.TagNumber(15)
  void clearLastOpenedMessageId() => $_clearField(15);

  @$pb.TagNumber(16)
  $fixnum.Int64 get positionRevision => $_getI64(15);
  @$pb.TagNumber(16)
  set positionRevision($fixnum.Int64 value) => $_setInt64(15, value);
  @$pb.TagNumber(16)
  $core.bool hasPositionRevision() => $_has(15);
  @$pb.TagNumber(16)
  void clearPositionRevision() => $_clearField(16);
}

class ListConferencesResponse extends $pb.GeneratedMessage {
  factory ListConferencesResponse({
    $core.Iterable<Conference>? conferences,
    $fixnum.Int64? total,
    $core.bool? hasMore,
  }) {
    final result = ListConferencesResponse._();
    if (conferences != null) result.conferences.addAll(conferences);
    if (total != null) result.total = total;
    if (hasMore != null) result.hasMore = hasMore;
    return result;
  }

  ListConferencesResponse._();

  factory ListConferencesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListConferencesResponse()..mergeFromBuffer(data, registry);
  factory ListConferencesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListConferencesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListConferencesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ListConferencesResponse.$_createMessage)
    ..pPM<Conference>(1, _omitFieldNames ? '' : 'conferences',
        subBuilder: Conference.$_createMessage)
    ..aInt64(2, _omitFieldNames ? '' : 'total')
    ..aOB(3, _omitFieldNames ? '' : 'hasMore')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListConferencesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListConferencesResponse copyWith(
          void Function(ListConferencesResponse) updates) =>
      super.copyWith((message) => updates(message as ListConferencesResponse))
          as ListConferencesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListConferencesResponse() / ListConferencesResponse.new instead')
  static ListConferencesResponse create() => ListConferencesResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListConferencesResponse._();
  @$core.override
  ListConferencesResponse createEmptyInstance() => ListConferencesResponse._();
  @$core.pragma('dart2js:noInline')
  static ListConferencesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListConferencesResponse>(
          ListConferencesResponse.$_createMessage);
  static ListConferencesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Conference> get conferences => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get total => $_getI64(1);
  @$pb.TagNumber(2)
  set total($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotal() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotal() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get hasMore => $_getBF(2);
  @$pb.TagNumber(3)
  set hasMore($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHasMore() => $_has(2);
  @$pb.TagNumber(3)
  void clearHasMore() => $_clearField(3);
}

class ListMessagesRequest extends $pb.GeneratedMessage {
  factory ListMessagesRequest({
    $core.String? conferenceId,
    PageRequest? page,
    $core.String? query,
    MessageSort? sort,
    $core.String? anchorMessageId,
  }) {
    final result = ListMessagesRequest._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (page != null) result.page = page;
    if (query != null) result.query = query;
    if (sort != null) result.sort = sort;
    if (anchorMessageId != null) result.anchorMessageId = anchorMessageId;
    return result;
  }

  ListMessagesRequest._();

  factory ListMessagesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListMessagesRequest()..mergeFromBuffer(data, registry);
  factory ListMessagesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListMessagesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMessagesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ListMessagesRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'conferenceId')
    ..aOM<PageRequest>(2, _omitFieldNames ? '' : 'page',
        subBuilder: PageRequest.$_createMessage)
    ..aOS(3, _omitFieldNames ? '' : 'query')
    ..aE<MessageSort>(4, _omitFieldNames ? '' : 'sort',
        enumValues: MessageSort.values)
    ..aOS(5, _omitFieldNames ? '' : 'anchorMessageId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMessagesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMessagesRequest copyWith(void Function(ListMessagesRequest) updates) =>
      super.copyWith((message) => updates(message as ListMessagesRequest))
          as ListMessagesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListMessagesRequest() / ListMessagesRequest.new instead')
  static ListMessagesRequest create() => ListMessagesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ListMessagesRequest._();
  @$core.override
  ListMessagesRequest createEmptyInstance() => ListMessagesRequest._();
  @$core.pragma('dart2js:noInline')
  static ListMessagesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMessagesRequest>(
          ListMessagesRequest.$_createMessage);
  static ListMessagesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conferenceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conferenceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConferenceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConferenceId() => $_clearField(1);

  @$pb.TagNumber(2)
  PageRequest get page => $_getN(1);
  @$pb.TagNumber(2)
  set page(PageRequest value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPage() => $_has(1);
  @$pb.TagNumber(2)
  void clearPage() => $_clearField(2);
  @$pb.TagNumber(2)
  PageRequest ensurePage() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.String get query => $_getSZ(2);
  @$pb.TagNumber(3)
  set query($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasQuery() => $_has(2);
  @$pb.TagNumber(3)
  void clearQuery() => $_clearField(3);

  @$pb.TagNumber(4)
  MessageSort get sort => $_getN(3);
  @$pb.TagNumber(4)
  set sort(MessageSort value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSort() => $_has(3);
  @$pb.TagNumber(4)
  void clearSort() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get anchorMessageId => $_getSZ(4);
  @$pb.TagNumber(5)
  set anchorMessageId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAnchorMessageId() => $_has(4);
  @$pb.TagNumber(5)
  void clearAnchorMessageId() => $_clearField(5);
}

/// message_id — непрозрачный локальный ID с generation, а не FTN MsgID.
class MessageReference extends $pb.GeneratedMessage {
  factory MessageReference({
    $core.String? conferenceId,
    $core.String? messageId,
  }) {
    final result = MessageReference._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (messageId != null) result.messageId = messageId;
    return result;
  }

  MessageReference._();

  factory MessageReference.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessageReference()..mergeFromBuffer(data, registry);
  factory MessageReference.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessageReference()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MessageReference',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: MessageReference.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'conferenceId')
    ..aOS(2, _omitFieldNames ? '' : 'messageId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessageReference clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessageReference copyWith(void Function(MessageReference) updates) =>
      super.copyWith((message) => updates(message as MessageReference))
          as MessageReference;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MessageReference() / MessageReference.new instead')
  static MessageReference create() => MessageReference._();
  static $pb.GeneratedMessage $_createMessage() => MessageReference._();
  @$core.override
  MessageReference createEmptyInstance() => MessageReference._();
  @$core.pragma('dart2js:noInline')
  static MessageReference getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MessageReference>(
          MessageReference.$_createMessage);
  static MessageReference? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conferenceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conferenceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConferenceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConferenceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get messageId => $_getSZ(1);
  @$pb.TagNumber(2)
  set messageId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessageId() => $_clearField(2);
}

class Message extends $pb.GeneratedMessage {
  factory Message({
    $core.String? id,
    $core.String? conferenceId,
    $core.String? fromName,
    $core.String? fromAddress,
    $core.String? toName,
    $core.String? toAddress,
    $core.String? subject,
    $2.Timestamp? date,
    $core.String? body,
    $core.String? bodyPreview,
    $core.bool? isRead,
    $core.String? threadId,
    $core.String? inReplyTo,
    $core.String? ftnMessageId,
    $core.int? attributes,
    MailDirection? direction,
    $fixnum.Int64? positionRevision,
  }) {
    final result = Message._();
    if (id != null) result.id = id;
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (fromName != null) result.fromName = fromName;
    if (fromAddress != null) result.fromAddress = fromAddress;
    if (toName != null) result.toName = toName;
    if (toAddress != null) result.toAddress = toAddress;
    if (subject != null) result.subject = subject;
    if (date != null) result.date = date;
    if (body != null) result.body = body;
    if (bodyPreview != null) result.bodyPreview = bodyPreview;
    if (isRead != null) result.isRead = isRead;
    if (threadId != null) result.threadId = threadId;
    if (inReplyTo != null) result.inReplyTo = inReplyTo;
    if (ftnMessageId != null) result.ftnMessageId = ftnMessageId;
    if (attributes != null) result.attributes = attributes;
    if (direction != null) result.direction = direction;
    if (positionRevision != null) result.positionRevision = positionRevision;
    return result;
  }

  Message._();

  factory Message.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Message()..mergeFromBuffer(data, registry);
  factory Message.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Message()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Message',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: Message.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'conferenceId')
    ..aOS(3, _omitFieldNames ? '' : 'fromName')
    ..aOS(4, _omitFieldNames ? '' : 'fromAddress')
    ..aOS(5, _omitFieldNames ? '' : 'toName')
    ..aOS(6, _omitFieldNames ? '' : 'toAddress')
    ..aOS(7, _omitFieldNames ? '' : 'subject')
    ..aOM<$2.Timestamp>(8, _omitFieldNames ? '' : 'date',
        subBuilder: $2.Timestamp.$_createMessage)
    ..aOS(9, _omitFieldNames ? '' : 'body')
    ..aOS(10, _omitFieldNames ? '' : 'bodyPreview')
    ..aOB(11, _omitFieldNames ? '' : 'isRead')
    ..aOS(12, _omitFieldNames ? '' : 'threadId')
    ..aOS(13, _omitFieldNames ? '' : 'inReplyTo')
    ..aOS(14, _omitFieldNames ? '' : 'ftnMessageId')
    ..aI(15, _omitFieldNames ? '' : 'attributes',
        fieldType: $pb.PbFieldType.OU3)
    ..aE<MailDirection>(16, _omitFieldNames ? '' : 'direction',
        enumValues: MailDirection.values)
    ..a<$fixnum.Int64>(
        17, _omitFieldNames ? '' : 'positionRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Message clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Message copyWith(void Function(Message) updates) =>
      super.copyWith((message) => updates(message as Message)) as Message;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Message() / Message.new instead')
  static Message create() => Message._();
  static $pb.GeneratedMessage $_createMessage() => Message._();
  @$core.override
  Message createEmptyInstance() => Message._();
  @$core.pragma('dart2js:noInline')
  static Message getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Message>(Message.$_createMessage);
  static Message? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get conferenceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set conferenceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConferenceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearConferenceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get fromName => $_getSZ(2);
  @$pb.TagNumber(3)
  set fromName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFromName() => $_has(2);
  @$pb.TagNumber(3)
  void clearFromName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get fromAddress => $_getSZ(3);
  @$pb.TagNumber(4)
  set fromAddress($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFromAddress() => $_has(3);
  @$pb.TagNumber(4)
  void clearFromAddress() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get toName => $_getSZ(4);
  @$pb.TagNumber(5)
  set toName($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasToName() => $_has(4);
  @$pb.TagNumber(5)
  void clearToName() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get toAddress => $_getSZ(5);
  @$pb.TagNumber(6)
  set toAddress($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasToAddress() => $_has(5);
  @$pb.TagNumber(6)
  void clearToAddress() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get subject => $_getSZ(6);
  @$pb.TagNumber(7)
  set subject($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSubject() => $_has(6);
  @$pb.TagNumber(7)
  void clearSubject() => $_clearField(7);

  @$pb.TagNumber(8)
  $2.Timestamp get date => $_getN(7);
  @$pb.TagNumber(8)
  set date($2.Timestamp value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasDate() => $_has(7);
  @$pb.TagNumber(8)
  void clearDate() => $_clearField(8);
  @$pb.TagNumber(8)
  $2.Timestamp ensureDate() => $_ensure(7);

  /// В списках передаётся preview; полный текст доступен через GetMessage.
  @$pb.TagNumber(9)
  $core.String get body => $_getSZ(8);
  @$pb.TagNumber(9)
  set body($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasBody() => $_has(8);
  @$pb.TagNumber(9)
  void clearBody() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get bodyPreview => $_getSZ(9);
  @$pb.TagNumber(10)
  set bodyPreview($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasBodyPreview() => $_has(9);
  @$pb.TagNumber(10)
  void clearBodyPreview() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get isRead => $_getBF(10);
  @$pb.TagNumber(11)
  set isRead($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasIsRead() => $_has(10);
  @$pb.TagNumber(11)
  void clearIsRead() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get threadId => $_getSZ(11);
  @$pb.TagNumber(12)
  set threadId($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasThreadId() => $_has(11);
  @$pb.TagNumber(12)
  void clearThreadId() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get inReplyTo => $_getSZ(12);
  @$pb.TagNumber(13)
  set inReplyTo($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasInReplyTo() => $_has(12);
  @$pb.TagNumber(13)
  void clearInReplyTo() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get ftnMessageId => $_getSZ(13);
  @$pb.TagNumber(14)
  set ftnMessageId($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasFtnMessageId() => $_has(13);
  @$pb.TagNumber(14)
  void clearFtnMessageId() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get attributes => $_getIZ(14);
  @$pb.TagNumber(15)
  set attributes($core.int value) => $_setUnsignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasAttributes() => $_has(14);
  @$pb.TagNumber(15)
  void clearAttributes() => $_clearField(15);

  @$pb.TagNumber(16)
  MailDirection get direction => $_getN(15);
  @$pb.TagNumber(16)
  set direction(MailDirection value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasDirection() => $_has(15);
  @$pb.TagNumber(16)
  void clearDirection() => $_clearField(16);

  @$pb.TagNumber(17)
  $fixnum.Int64 get positionRevision => $_getI64(16);
  @$pb.TagNumber(17)
  set positionRevision($fixnum.Int64 value) => $_setInt64(16, value);
  @$pb.TagNumber(17)
  $core.bool hasPositionRevision() => $_has(16);
  @$pb.TagNumber(17)
  void clearPositionRevision() => $_clearField(17);
}

class ListMessagesResponse extends $pb.GeneratedMessage {
  factory ListMessagesResponse({
    $core.Iterable<Message>? messages,
    $fixnum.Int64? total,
    $core.bool? hasMore,
    $fixnum.Int64? actualOffset,
  }) {
    final result = ListMessagesResponse._();
    if (messages != null) result.messages.addAll(messages);
    if (total != null) result.total = total;
    if (hasMore != null) result.hasMore = hasMore;
    if (actualOffset != null) result.actualOffset = actualOffset;
    return result;
  }

  ListMessagesResponse._();

  factory ListMessagesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListMessagesResponse()..mergeFromBuffer(data, registry);
  factory ListMessagesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListMessagesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListMessagesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ListMessagesResponse.$_createMessage)
    ..pPM<Message>(1, _omitFieldNames ? '' : 'messages',
        subBuilder: Message.$_createMessage)
    ..aInt64(2, _omitFieldNames ? '' : 'total')
    ..aOB(3, _omitFieldNames ? '' : 'hasMore')
    ..aInt64(4, _omitFieldNames ? '' : 'actualOffset')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMessagesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListMessagesResponse copyWith(void Function(ListMessagesResponse) updates) =>
      super.copyWith((message) => updates(message as ListMessagesResponse))
          as ListMessagesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListMessagesResponse() / ListMessagesResponse.new instead')
  static ListMessagesResponse create() => ListMessagesResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListMessagesResponse._();
  @$core.override
  ListMessagesResponse createEmptyInstance() => ListMessagesResponse._();
  @$core.pragma('dart2js:noInline')
  static ListMessagesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListMessagesResponse>(
          ListMessagesResponse.$_createMessage);
  static ListMessagesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Message> get messages => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get total => $_getI64(1);
  @$pb.TagNumber(2)
  set total($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotal() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotal() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get hasMore => $_getBF(2);
  @$pb.TagNumber(3)
  set hasMore($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHasMore() => $_has(2);
  @$pb.TagNumber(3)
  void clearHasMore() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get actualOffset => $_getI64(3);
  @$pb.TagNumber(4)
  set actualOffset($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasActualOffset() => $_has(3);
  @$pb.TagNumber(4)
  void clearActualOffset() => $_clearField(4);
}

class CreateMessageRequest extends $pb.GeneratedMessage {
  factory CreateMessageRequest({
    $core.String? conferenceId,
    $core.String? operationId,
    $core.String? toName,
    $core.String? toAddress,
    $core.String? subject,
    $core.String? body,
    $core.String? inReplyTo,
  }) {
    final result = CreateMessageRequest._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (operationId != null) result.operationId = operationId;
    if (toName != null) result.toName = toName;
    if (toAddress != null) result.toAddress = toAddress;
    if (subject != null) result.subject = subject;
    if (body != null) result.body = body;
    if (inReplyTo != null) result.inReplyTo = inReplyTo;
    return result;
  }

  CreateMessageRequest._();

  factory CreateMessageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateMessageRequest()..mergeFromBuffer(data, registry);
  factory CreateMessageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateMessageRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMessageRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: CreateMessageRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'conferenceId')
    ..aOS(2, _omitFieldNames ? '' : 'operationId')
    ..aOS(3, _omitFieldNames ? '' : 'toName')
    ..aOS(4, _omitFieldNames ? '' : 'toAddress')
    ..aOS(5, _omitFieldNames ? '' : 'subject')
    ..aOS(6, _omitFieldNames ? '' : 'body')
    ..aOS(7, _omitFieldNames ? '' : 'inReplyTo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMessageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMessageRequest copyWith(void Function(CreateMessageRequest) updates) =>
      super.copyWith((message) => updates(message as CreateMessageRequest))
          as CreateMessageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateMessageRequest() / CreateMessageRequest.new instead')
  static CreateMessageRequest create() => CreateMessageRequest._();
  static $pb.GeneratedMessage $_createMessage() => CreateMessageRequest._();
  @$core.override
  CreateMessageRequest createEmptyInstance() => CreateMessageRequest._();
  @$core.pragma('dart2js:noInline')
  static CreateMessageRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMessageRequest>(
          CreateMessageRequest.$_createMessage);
  static CreateMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conferenceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conferenceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConferenceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConferenceId() => $_clearField(1);

  /// Ключ сохраняется клиентом при повторе неопределённого результата.
  @$pb.TagNumber(2)
  $core.String get operationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set operationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOperationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get toName => $_getSZ(2);
  @$pb.TagNumber(3)
  set toName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasToName() => $_has(2);
  @$pb.TagNumber(3)
  void clearToName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get toAddress => $_getSZ(3);
  @$pb.TagNumber(4)
  set toAddress($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasToAddress() => $_has(3);
  @$pb.TagNumber(4)
  void clearToAddress() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get subject => $_getSZ(4);
  @$pb.TagNumber(5)
  set subject($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSubject() => $_has(4);
  @$pb.TagNumber(5)
  void clearSubject() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get body => $_getSZ(5);
  @$pb.TagNumber(6)
  set body($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBody() => $_has(5);
  @$pb.TagNumber(6)
  void clearBody() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get inReplyTo => $_getSZ(6);
  @$pb.TagNumber(7)
  set inReplyTo($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasInReplyTo() => $_has(6);
  @$pb.TagNumber(7)
  void clearInReplyTo() => $_clearField(7);
}

/// Text-only group; conference_id is the mandatory original area.
class CreateCrosspostRequest extends $pb.GeneratedMessage {
  factory CreateCrosspostRequest({
    CreateMessageRequest? message,
    $core.Iterable<$core.String>? additionalConferenceIds,
  }) {
    final result = CreateCrosspostRequest._();
    if (message != null) result.message = message;
    if (additionalConferenceIds != null)
      result.additionalConferenceIds.addAll(additionalConferenceIds);
    return result;
  }

  CreateCrosspostRequest._();

  factory CreateCrosspostRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateCrosspostRequest()..mergeFromBuffer(data, registry);
  factory CreateCrosspostRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateCrosspostRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateCrosspostRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: CreateCrosspostRequest.$_createMessage)
    ..aOM<CreateMessageRequest>(1, _omitFieldNames ? '' : 'message',
        subBuilder: CreateMessageRequest.$_createMessage)
    ..pPS(2, _omitFieldNames ? '' : 'additionalConferenceIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateCrosspostRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateCrosspostRequest copyWith(
          void Function(CreateCrosspostRequest) updates) =>
      super.copyWith((message) => updates(message as CreateCrosspostRequest))
          as CreateCrosspostRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateCrosspostRequest() / CreateCrosspostRequest.new instead')
  static CreateCrosspostRequest create() => CreateCrosspostRequest._();
  static $pb.GeneratedMessage $_createMessage() => CreateCrosspostRequest._();
  @$core.override
  CreateCrosspostRequest createEmptyInstance() => CreateCrosspostRequest._();
  @$core.pragma('dart2js:noInline')
  static CreateCrosspostRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateCrosspostRequest>(
          CreateCrosspostRequest.$_createMessage);
  static CreateCrosspostRequest? _defaultInstance;

  @$pb.TagNumber(1)
  CreateMessageRequest get message => $_getN(0);
  @$pb.TagNumber(1)
  set message(CreateMessageRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);
  @$pb.TagNumber(1)
  CreateMessageRequest ensureMessage() => $_ensure(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get additionalConferenceIds => $_getList(1);
}

class CrosspostCopy extends $pb.GeneratedMessage {
  factory CrosspostCopy({
    MessageReference? message,
    $core.String? ftnMessageId,
  }) {
    final result = CrosspostCopy._();
    if (message != null) result.message = message;
    if (ftnMessageId != null) result.ftnMessageId = ftnMessageId;
    return result;
  }

  CrosspostCopy._();

  factory CrosspostCopy.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CrosspostCopy()..mergeFromBuffer(data, registry);
  factory CrosspostCopy.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CrosspostCopy()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CrosspostCopy',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: CrosspostCopy.$_createMessage)
    ..aOM<MessageReference>(1, _omitFieldNames ? '' : 'message',
        subBuilder: MessageReference.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'ftnMessageId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CrosspostCopy clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CrosspostCopy copyWith(void Function(CrosspostCopy) updates) =>
      super.copyWith((message) => updates(message as CrosspostCopy))
          as CrosspostCopy;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CrosspostCopy() / CrosspostCopy.new instead')
  static CrosspostCopy create() => CrosspostCopy._();
  static $pb.GeneratedMessage $_createMessage() => CrosspostCopy._();
  @$core.override
  CrosspostCopy createEmptyInstance() => CrosspostCopy._();
  @$core.pragma('dart2js:noInline')
  static CrosspostCopy getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CrosspostCopy>(
          CrosspostCopy.$_createMessage);
  static CrosspostCopy? _defaultInstance;

  @$pb.TagNumber(1)
  MessageReference get message => $_getN(0);
  @$pb.TagNumber(1)
  set message(MessageReference value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);
  @$pb.TagNumber(1)
  MessageReference ensureMessage() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get ftnMessageId => $_getSZ(1);
  @$pb.TagNumber(2)
  set ftnMessageId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFtnMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFtnMessageId() => $_clearField(2);
}

class CreateCrosspostResponse extends $pb.GeneratedMessage {
  factory CreateCrosspostResponse({
    $core.bool? complete,
    $core.Iterable<CrosspostCopy>? saved,
    $core.int? total,
    $core.int? pendingCode,
  }) {
    final result = CreateCrosspostResponse._();
    if (complete != null) result.complete = complete;
    if (saved != null) result.saved.addAll(saved);
    if (total != null) result.total = total;
    if (pendingCode != null) result.pendingCode = pendingCode;
    return result;
  }

  CreateCrosspostResponse._();

  factory CreateCrosspostResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateCrosspostResponse()..mergeFromBuffer(data, registry);
  factory CreateCrosspostResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateCrosspostResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateCrosspostResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: CreateCrosspostResponse.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'complete')
    ..pPM<CrosspostCopy>(2, _omitFieldNames ? '' : 'saved',
        subBuilder: CrosspostCopy.$_createMessage)
    ..aI(3, _omitFieldNames ? '' : 'total')
    ..aI(4, _omitFieldNames ? '' : 'pendingCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateCrosspostResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateCrosspostResponse copyWith(
          void Function(CreateCrosspostResponse) updates) =>
      super.copyWith((message) => updates(message as CreateCrosspostResponse))
          as CreateCrosspostResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateCrosspostResponse() / CreateCrosspostResponse.new instead')
  static CreateCrosspostResponse create() => CreateCrosspostResponse._();
  static $pb.GeneratedMessage $_createMessage() => CreateCrosspostResponse._();
  @$core.override
  CreateCrosspostResponse createEmptyInstance() => CreateCrosspostResponse._();
  @$core.pragma('dart2js:noInline')
  static CreateCrosspostResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateCrosspostResponse>(
          CreateCrosspostResponse.$_createMessage);
  static CreateCrosspostResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get complete => $_getBF(0);
  @$pb.TagNumber(1)
  set complete($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasComplete() => $_has(0);
  @$pb.TagNumber(1)
  void clearComplete() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<CrosspostCopy> get saved => $_getList(1);

  @$pb.TagNumber(3)
  $core.int get total => $_getIZ(2);
  @$pb.TagNumber(3)
  set total($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotal() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotal() => $_clearField(3);

  /// gRPC status code for the first unfinished copy; no private storage details.
  @$pb.TagNumber(4)
  $core.int get pendingCode => $_getIZ(3);
  @$pb.TagNumber(4)
  set pendingCode($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPendingCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearPendingCode() => $_clearField(4);
}

class CreateMessageResponse extends $pb.GeneratedMessage {
  factory CreateMessageResponse({
    MessageReference? message,
    $core.String? ftnMessageId,
    SaveStatus? status,
  }) {
    final result = CreateMessageResponse._();
    if (message != null) result.message = message;
    if (ftnMessageId != null) result.ftnMessageId = ftnMessageId;
    if (status != null) result.status = status;
    return result;
  }

  CreateMessageResponse._();

  factory CreateMessageResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateMessageResponse()..mergeFromBuffer(data, registry);
  factory CreateMessageResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateMessageResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateMessageResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: CreateMessageResponse.$_createMessage)
    ..aOM<MessageReference>(1, _omitFieldNames ? '' : 'message',
        subBuilder: MessageReference.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'ftnMessageId')
    ..aE<SaveStatus>(3, _omitFieldNames ? '' : 'status',
        enumValues: SaveStatus.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMessageResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateMessageResponse copyWith(
          void Function(CreateMessageResponse) updates) =>
      super.copyWith((message) => updates(message as CreateMessageResponse))
          as CreateMessageResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CreateMessageResponse() / CreateMessageResponse.new instead')
  static CreateMessageResponse create() => CreateMessageResponse._();
  static $pb.GeneratedMessage $_createMessage() => CreateMessageResponse._();
  @$core.override
  CreateMessageResponse createEmptyInstance() => CreateMessageResponse._();
  @$core.pragma('dart2js:noInline')
  static CreateMessageResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateMessageResponse>(
          CreateMessageResponse.$_createMessage);
  static CreateMessageResponse? _defaultInstance;

  @$pb.TagNumber(1)
  MessageReference get message => $_getN(0);
  @$pb.TagNumber(1)
  set message(MessageReference value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);
  @$pb.TagNumber(1)
  MessageReference ensureMessage() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get ftnMessageId => $_getSZ(1);
  @$pb.TagNumber(2)
  set ftnMessageId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFtnMessageId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFtnMessageId() => $_clearField(2);

  @$pb.TagNumber(3)
  SaveStatus get status => $_getN(2);
  @$pb.TagNumber(3)
  set status(SaveStatus value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatus() => $_clearField(3);
}

class GetThreadRequest extends $pb.GeneratedMessage {
  factory GetThreadRequest({
    $core.String? conferenceId,
    $core.String? threadId,
    PageRequest? page,
  }) {
    final result = GetThreadRequest._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (threadId != null) result.threadId = threadId;
    if (page != null) result.page = page;
    return result;
  }

  GetThreadRequest._();

  factory GetThreadRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetThreadRequest()..mergeFromBuffer(data, registry);
  factory GetThreadRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetThreadRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetThreadRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: GetThreadRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'conferenceId')
    ..aOS(2, _omitFieldNames ? '' : 'threadId')
    ..aOM<PageRequest>(3, _omitFieldNames ? '' : 'page',
        subBuilder: PageRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetThreadRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetThreadRequest copyWith(void Function(GetThreadRequest) updates) =>
      super.copyWith((message) => updates(message as GetThreadRequest))
          as GetThreadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetThreadRequest() / GetThreadRequest.new instead')
  static GetThreadRequest create() => GetThreadRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetThreadRequest._();
  @$core.override
  GetThreadRequest createEmptyInstance() => GetThreadRequest._();
  @$core.pragma('dart2js:noInline')
  static GetThreadRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetThreadRequest>(
          GetThreadRequest.$_createMessage);
  static GetThreadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conferenceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conferenceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConferenceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConferenceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get threadId => $_getSZ(1);
  @$pb.TagNumber(2)
  set threadId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasThreadId() => $_has(1);
  @$pb.TagNumber(2)
  void clearThreadId() => $_clearField(2);

  @$pb.TagNumber(3)
  PageRequest get page => $_getN(2);
  @$pb.TagNumber(3)
  set page(PageRequest value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPage() => $_has(2);
  @$pb.TagNumber(3)
  void clearPage() => $_clearField(3);
  @$pb.TagNumber(3)
  PageRequest ensurePage() => $_ensure(2);
}

class Bookmark extends $pb.GeneratedMessage {
  factory Bookmark({
    Conference? conference,
    $2.Timestamp? addedAt,
  }) {
    final result = Bookmark._();
    if (conference != null) result.conference = conference;
    if (addedAt != null) result.addedAt = addedAt;
    return result;
  }

  Bookmark._();

  factory Bookmark.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Bookmark()..mergeFromBuffer(data, registry);
  factory Bookmark.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Bookmark()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bookmark',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: Bookmark.$_createMessage)
    ..aOM<Conference>(1, _omitFieldNames ? '' : 'conference',
        subBuilder: Conference.$_createMessage)
    ..aOM<$2.Timestamp>(2, _omitFieldNames ? '' : 'addedAt',
        subBuilder: $2.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bookmark clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bookmark copyWith(void Function(Bookmark) updates) =>
      super.copyWith((message) => updates(message as Bookmark)) as Bookmark;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Bookmark() / Bookmark.new instead')
  static Bookmark create() => Bookmark._();
  static $pb.GeneratedMessage $_createMessage() => Bookmark._();
  @$core.override
  Bookmark createEmptyInstance() => Bookmark._();
  @$core.pragma('dart2js:noInline')
  static Bookmark getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bookmark>(Bookmark.$_createMessage);
  static Bookmark? _defaultInstance;

  @$pb.TagNumber(1)
  Conference get conference => $_getN(0);
  @$pb.TagNumber(1)
  set conference(Conference value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasConference() => $_has(0);
  @$pb.TagNumber(1)
  void clearConference() => $_clearField(1);
  @$pb.TagNumber(1)
  Conference ensureConference() => $_ensure(0);

  @$pb.TagNumber(2)
  $2.Timestamp get addedAt => $_getN(1);
  @$pb.TagNumber(2)
  set addedAt($2.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasAddedAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearAddedAt() => $_clearField(2);
  @$pb.TagNumber(2)
  $2.Timestamp ensureAddedAt() => $_ensure(1);
}

class ListBookmarksResponse extends $pb.GeneratedMessage {
  factory ListBookmarksResponse({
    $core.Iterable<Bookmark>? bookmarks,
    $fixnum.Int64? total,
    $core.bool? hasMore,
  }) {
    final result = ListBookmarksResponse._();
    if (bookmarks != null) result.bookmarks.addAll(bookmarks);
    if (total != null) result.total = total;
    if (hasMore != null) result.hasMore = hasMore;
    return result;
  }

  ListBookmarksResponse._();

  factory ListBookmarksResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListBookmarksResponse()..mergeFromBuffer(data, registry);
  factory ListBookmarksResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListBookmarksResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListBookmarksResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ListBookmarksResponse.$_createMessage)
    ..pPM<Bookmark>(1, _omitFieldNames ? '' : 'bookmarks',
        subBuilder: Bookmark.$_createMessage)
    ..aInt64(2, _omitFieldNames ? '' : 'total')
    ..aOB(3, _omitFieldNames ? '' : 'hasMore')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListBookmarksResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListBookmarksResponse copyWith(
          void Function(ListBookmarksResponse) updates) =>
      super.copyWith((message) => updates(message as ListBookmarksResponse))
          as ListBookmarksResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ListBookmarksResponse() / ListBookmarksResponse.new instead')
  static ListBookmarksResponse create() => ListBookmarksResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListBookmarksResponse._();
  @$core.override
  ListBookmarksResponse createEmptyInstance() => ListBookmarksResponse._();
  @$core.pragma('dart2js:noInline')
  static ListBookmarksResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListBookmarksResponse>(
          ListBookmarksResponse.$_createMessage);
  static ListBookmarksResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Bookmark> get bookmarks => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get total => $_getI64(1);
  @$pb.TagNumber(2)
  set total($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotal() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotal() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get hasMore => $_getBF(2);
  @$pb.TagNumber(3)
  set hasMore($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHasMore() => $_has(2);
  @$pb.TagNumber(3)
  void clearHasMore() => $_clearField(3);
}

class HistoryEntry extends $pb.GeneratedMessage {
  factory HistoryEntry({
    Conference? conference,
    $2.Timestamp? viewedAt,
  }) {
    final result = HistoryEntry._();
    if (conference != null) result.conference = conference;
    if (viewedAt != null) result.viewedAt = viewedAt;
    return result;
  }

  HistoryEntry._();

  factory HistoryEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HistoryEntry()..mergeFromBuffer(data, registry);
  factory HistoryEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HistoryEntry()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HistoryEntry',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: HistoryEntry.$_createMessage)
    ..aOM<Conference>(1, _omitFieldNames ? '' : 'conference',
        subBuilder: Conference.$_createMessage)
    ..aOM<$2.Timestamp>(2, _omitFieldNames ? '' : 'viewedAt',
        subBuilder: $2.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HistoryEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HistoryEntry copyWith(void Function(HistoryEntry) updates) =>
      super.copyWith((message) => updates(message as HistoryEntry))
          as HistoryEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HistoryEntry() / HistoryEntry.new instead')
  static HistoryEntry create() => HistoryEntry._();
  static $pb.GeneratedMessage $_createMessage() => HistoryEntry._();
  @$core.override
  HistoryEntry createEmptyInstance() => HistoryEntry._();
  @$core.pragma('dart2js:noInline')
  static HistoryEntry getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HistoryEntry>(
          HistoryEntry.$_createMessage);
  static HistoryEntry? _defaultInstance;

  @$pb.TagNumber(1)
  Conference get conference => $_getN(0);
  @$pb.TagNumber(1)
  set conference(Conference value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasConference() => $_has(0);
  @$pb.TagNumber(1)
  void clearConference() => $_clearField(1);
  @$pb.TagNumber(1)
  Conference ensureConference() => $_ensure(0);

  @$pb.TagNumber(2)
  $2.Timestamp get viewedAt => $_getN(1);
  @$pb.TagNumber(2)
  set viewedAt($2.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasViewedAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearViewedAt() => $_clearField(2);
  @$pb.TagNumber(2)
  $2.Timestamp ensureViewedAt() => $_ensure(1);
}

class ListHistoryResponse extends $pb.GeneratedMessage {
  factory ListHistoryResponse({
    $core.Iterable<HistoryEntry>? history,
    $fixnum.Int64? total,
    $core.bool? hasMore,
  }) {
    final result = ListHistoryResponse._();
    if (history != null) result.history.addAll(history);
    if (total != null) result.total = total;
    if (hasMore != null) result.hasMore = hasMore;
    return result;
  }

  ListHistoryResponse._();

  factory ListHistoryResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListHistoryResponse()..mergeFromBuffer(data, registry);
  factory ListHistoryResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ListHistoryResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListHistoryResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ListHistoryResponse.$_createMessage)
    ..pPM<HistoryEntry>(1, _omitFieldNames ? '' : 'history',
        subBuilder: HistoryEntry.$_createMessage)
    ..aInt64(2, _omitFieldNames ? '' : 'total')
    ..aOB(3, _omitFieldNames ? '' : 'hasMore')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListHistoryResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListHistoryResponse copyWith(void Function(ListHistoryResponse) updates) =>
      super.copyWith((message) => updates(message as ListHistoryResponse))
          as ListHistoryResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ListHistoryResponse() / ListHistoryResponse.new instead')
  static ListHistoryResponse create() => ListHistoryResponse._();
  static $pb.GeneratedMessage $_createMessage() => ListHistoryResponse._();
  @$core.override
  ListHistoryResponse createEmptyInstance() => ListHistoryResponse._();
  @$core.pragma('dart2js:noInline')
  static ListHistoryResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListHistoryResponse>(
          ListHistoryResponse.$_createMessage);
  static ListHistoryResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<HistoryEntry> get history => $_getList(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get total => $_getI64(1);
  @$pb.TagNumber(2)
  set total($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotal() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotal() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get hasMore => $_getBF(2);
  @$pb.TagNumber(3)
  set hasMore($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHasMore() => $_has(2);
  @$pb.TagNumber(3)
  void clearHasMore() => $_clearField(3);
}

class Profile extends $pb.GeneratedMessage {
  factory Profile({
    $core.String? userId,
    $core.String? name,
    $core.String? address,
    $core.String? email,
    $2.Timestamp? registeredAt,
  }) {
    final result = Profile._();
    if (userId != null) result.userId = userId;
    if (name != null) result.name = name;
    if (address != null) result.address = address;
    if (email != null) result.email = email;
    if (registeredAt != null) result.registeredAt = registeredAt;
    return result;
  }

  Profile._();

  factory Profile.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Profile()..mergeFromBuffer(data, registry);
  factory Profile.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Profile()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Profile',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: Profile.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'address')
    ..aOS(4, _omitFieldNames ? '' : 'email')
    ..aOM<$2.Timestamp>(5, _omitFieldNames ? '' : 'registeredAt',
        subBuilder: $2.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Profile clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Profile copyWith(void Function(Profile) updates) =>
      super.copyWith((message) => updates(message as Profile)) as Profile;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Profile() / Profile.new instead')
  static Profile create() => Profile._();
  static $pb.GeneratedMessage $_createMessage() => Profile._();
  @$core.override
  Profile createEmptyInstance() => Profile._();
  @$core.pragma('dart2js:noInline')
  static Profile getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Profile>(Profile.$_createMessage);
  static Profile? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get address => $_getSZ(2);
  @$pb.TagNumber(3)
  set address($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAddress() => $_has(2);
  @$pb.TagNumber(3)
  void clearAddress() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get email => $_getSZ(3);
  @$pb.TagNumber(4)
  set email($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEmail() => $_has(3);
  @$pb.TagNumber(4)
  void clearEmail() => $_clearField(4);

  @$pb.TagNumber(5)
  $2.Timestamp get registeredAt => $_getN(4);
  @$pb.TagNumber(5)
  set registeredAt($2.Timestamp value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasRegisteredAt() => $_has(4);
  @$pb.TagNumber(5)
  void clearRegisteredAt() => $_clearField(5);
  @$pb.TagNumber(5)
  $2.Timestamp ensureRegisteredAt() => $_ensure(4);
}

/// Сериализованный ErrorDetails передаётся в ffido-error-details-bin trailers.
/// Только публичная диагностика: без путей, SQL, токенов и payload запроса.
class ErrorDetails extends $pb.GeneratedMessage {
  factory ErrorDetails({
    $core.Iterable<FieldViolation>? violations,
  }) {
    final result = ErrorDetails._();
    if (violations != null) result.violations.addAll(violations);
    return result;
  }

  ErrorDetails._();

  factory ErrorDetails.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ErrorDetails()..mergeFromBuffer(data, registry);
  factory ErrorDetails.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ErrorDetails()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ErrorDetails',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ErrorDetails.$_createMessage)
    ..pPM<FieldViolation>(1, _omitFieldNames ? '' : 'violations',
        subBuilder: FieldViolation.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorDetails clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ErrorDetails copyWith(void Function(ErrorDetails) updates) =>
      super.copyWith((message) => updates(message as ErrorDetails))
          as ErrorDetails;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ErrorDetails() / ErrorDetails.new instead')
  static ErrorDetails create() => ErrorDetails._();
  static $pb.GeneratedMessage $_createMessage() => ErrorDetails._();
  @$core.override
  ErrorDetails createEmptyInstance() => ErrorDetails._();
  @$core.pragma('dart2js:noInline')
  static ErrorDetails getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ErrorDetails>(
          ErrorDetails.$_createMessage);
  static ErrorDetails? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<FieldViolation> get violations => $_getList(0);
}

class FieldViolation extends $pb.GeneratedMessage {
  factory FieldViolation({
    $core.String? field_1,
    $core.String? message,
  }) {
    final result = FieldViolation._();
    if (field_1 != null) result.field_1 = field_1;
    if (message != null) result.message = message;
    return result;
  }

  FieldViolation._();

  factory FieldViolation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FieldViolation()..mergeFromBuffer(data, registry);
  factory FieldViolation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FieldViolation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FieldViolation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: FieldViolation.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'field')
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FieldViolation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FieldViolation copyWith(void Function(FieldViolation) updates) =>
      super.copyWith((message) => updates(message as FieldViolation))
          as FieldViolation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FieldViolation() / FieldViolation.new instead')
  static FieldViolation create() => FieldViolation._();
  static $pb.GeneratedMessage $_createMessage() => FieldViolation._();
  @$core.override
  FieldViolation createEmptyInstance() => FieldViolation._();
  @$core.pragma('dart2js:noInline')
  static FieldViolation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FieldViolation>(
          FieldViolation.$_createMessage);
  static FieldViolation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get field_1 => $_getSZ(0);
  @$pb.TagNumber(1)
  set field_1($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasField_1() => $_has(0);
  @$pb.TagNumber(1)
  void clearField_1() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);
}

class LoginRequest extends $pb.GeneratedMessage {
  factory LoginRequest({
    $core.String? name,
    $core.String? address,
    $core.String? password,
  }) {
    final result = LoginRequest._();
    if (name != null) result.name = name;
    if (address != null) result.address = address;
    if (password != null) result.password = password;
    return result;
  }

  LoginRequest._();

  factory LoginRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LoginRequest()..mergeFromBuffer(data, registry);
  factory LoginRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LoginRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoginRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: LoginRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'address')
    ..aOS(3, _omitFieldNames ? '' : 'password')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginRequest copyWith(void Function(LoginRequest) updates) =>
      super.copyWith((message) => updates(message as LoginRequest))
          as LoginRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LoginRequest() / LoginRequest.new instead')
  static LoginRequest create() => LoginRequest._();
  static $pb.GeneratedMessage $_createMessage() => LoginRequest._();
  @$core.override
  LoginRequest createEmptyInstance() => LoginRequest._();
  @$core.pragma('dart2js:noInline')
  static LoginRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoginRequest>(
          LoginRequest.$_createMessage);
  static LoginRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get address => $_getSZ(1);
  @$pb.TagNumber(2)
  set address($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAddress() => $_has(1);
  @$pb.TagNumber(2)
  void clearAddress() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get password => $_getSZ(2);
  @$pb.TagNumber(3)
  set password($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPassword() => $_has(2);
  @$pb.TagNumber(3)
  void clearPassword() => $_clearField(3);
}

class SessionInfo extends $pb.GeneratedMessage {
  factory SessionInfo({
    Profile? profile,
    $2.Timestamp? expiresAt,
  }) {
    final result = SessionInfo._();
    if (profile != null) result.profile = profile;
    if (expiresAt != null) result.expiresAt = expiresAt;
    return result;
  }

  SessionInfo._();

  factory SessionInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SessionInfo()..mergeFromBuffer(data, registry);
  factory SessionInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SessionInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SessionInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: SessionInfo.$_createMessage)
    ..aOM<Profile>(1, _omitFieldNames ? '' : 'profile',
        subBuilder: Profile.$_createMessage)
    ..aOM<$2.Timestamp>(2, _omitFieldNames ? '' : 'expiresAt',
        subBuilder: $2.Timestamp.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionInfo copyWith(void Function(SessionInfo) updates) =>
      super.copyWith((message) => updates(message as SessionInfo))
          as SessionInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SessionInfo() / SessionInfo.new instead')
  static SessionInfo create() => SessionInfo._();
  static $pb.GeneratedMessage $_createMessage() => SessionInfo._();
  @$core.override
  SessionInfo createEmptyInstance() => SessionInfo._();
  @$core.pragma('dart2js:noInline')
  static SessionInfo getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SessionInfo>(
          SessionInfo.$_createMessage);
  static SessionInfo? _defaultInstance;

  @$pb.TagNumber(1)
  Profile get profile => $_getN(0);
  @$pb.TagNumber(1)
  set profile(Profile value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasProfile() => $_has(0);
  @$pb.TagNumber(1)
  void clearProfile() => $_clearField(1);
  @$pb.TagNumber(1)
  Profile ensureProfile() => $_ensure(0);

  @$pb.TagNumber(2)
  $2.Timestamp get expiresAt => $_getN(1);
  @$pb.TagNumber(2)
  set expiresAt($2.Timestamp value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasExpiresAt() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpiresAt() => $_clearField(2);
  @$pb.TagNumber(2)
  $2.Timestamp ensureExpiresAt() => $_ensure(1);
}

class LoginResponse extends $pb.GeneratedMessage {
  factory LoginResponse({
    $core.String? sessionSecret,
    SessionInfo? session,
  }) {
    final result = LoginResponse._();
    if (sessionSecret != null) result.sessionSecret = sessionSecret;
    if (session != null) result.session = session;
    return result;
  }

  LoginResponse._();

  factory LoginResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LoginResponse()..mergeFromBuffer(data, registry);
  factory LoginResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LoginResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LoginResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: LoginResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sessionSecret')
    ..aOM<SessionInfo>(2, _omitFieldNames ? '' : 'session',
        subBuilder: SessionInfo.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LoginResponse copyWith(void Function(LoginResponse) updates) =>
      super.copyWith((message) => updates(message as LoginResponse))
          as LoginResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LoginResponse() / LoginResponse.new instead')
  static LoginResponse create() => LoginResponse._();
  static $pb.GeneratedMessage $_createMessage() => LoginResponse._();
  @$core.override
  LoginResponse createEmptyInstance() => LoginResponse._();
  @$core.pragma('dart2js:noInline')
  static LoginResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LoginResponse>(
          LoginResponse.$_createMessage);
  static LoginResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionSecret => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionSecret($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionSecret() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionSecret() => $_clearField(1);

  @$pb.TagNumber(2)
  SessionInfo get session => $_getN(1);
  @$pb.TagNumber(2)
  set session(SessionInfo value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSession() => $_has(1);
  @$pb.TagNumber(2)
  void clearSession() => $_clearField(2);
  @$pb.TagNumber(2)
  SessionInfo ensureSession() => $_ensure(1);
}

/// Одна атомарная отметка снимка эхи, повтор определяется пользовательским operation_id.
class MarkConferenceReadRequest extends $pb.GeneratedMessage {
  factory MarkConferenceReadRequest({
    $core.String? conferenceId,
    $core.String? operationId,
  }) {
    final result = MarkConferenceReadRequest._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (operationId != null) result.operationId = operationId;
    return result;
  }

  MarkConferenceReadRequest._();

  factory MarkConferenceReadRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MarkConferenceReadRequest()..mergeFromBuffer(data, registry);
  factory MarkConferenceReadRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MarkConferenceReadRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MarkConferenceReadRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: MarkConferenceReadRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'conferenceId')
    ..aOS(2, _omitFieldNames ? '' : 'operationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MarkConferenceReadRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MarkConferenceReadRequest copyWith(
          void Function(MarkConferenceReadRequest) updates) =>
      super.copyWith((message) => updates(message as MarkConferenceReadRequest))
          as MarkConferenceReadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use MarkConferenceReadRequest() / MarkConferenceReadRequest.new instead')
  static MarkConferenceReadRequest create() => MarkConferenceReadRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      MarkConferenceReadRequest._();
  @$core.override
  MarkConferenceReadRequest createEmptyInstance() =>
      MarkConferenceReadRequest._();
  @$core.pragma('dart2js:noInline')
  static MarkConferenceReadRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MarkConferenceReadRequest>(
          MarkConferenceReadRequest.$_createMessage);
  static MarkConferenceReadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conferenceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conferenceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConferenceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConferenceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get operationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set operationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOperationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperationId() => $_clearField(2);
}

class MarkConferenceReadResponse extends $pb.GeneratedMessage {
  factory MarkConferenceReadResponse({
    $fixnum.Int64? markedCount,
    $fixnum.Int64? snapshotCount,
    $core.String? generation,
  }) {
    final result = MarkConferenceReadResponse._();
    if (markedCount != null) result.markedCount = markedCount;
    if (snapshotCount != null) result.snapshotCount = snapshotCount;
    if (generation != null) result.generation = generation;
    return result;
  }

  MarkConferenceReadResponse._();

  factory MarkConferenceReadResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MarkConferenceReadResponse()..mergeFromBuffer(data, registry);
  factory MarkConferenceReadResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MarkConferenceReadResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MarkConferenceReadResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: MarkConferenceReadResponse.$_createMessage)
    ..aInt64(1, _omitFieldNames ? '' : 'markedCount')
    ..aInt64(2, _omitFieldNames ? '' : 'snapshotCount')
    ..aOS(3, _omitFieldNames ? '' : 'generation')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MarkConferenceReadResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MarkConferenceReadResponse copyWith(
          void Function(MarkConferenceReadResponse) updates) =>
      super.copyWith(
              (message) => updates(message as MarkConferenceReadResponse))
          as MarkConferenceReadResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use MarkConferenceReadResponse() / MarkConferenceReadResponse.new instead')
  static MarkConferenceReadResponse create() => MarkConferenceReadResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      MarkConferenceReadResponse._();
  @$core.override
  MarkConferenceReadResponse createEmptyInstance() =>
      MarkConferenceReadResponse._();
  @$core.pragma('dart2js:noInline')
  static MarkConferenceReadResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MarkConferenceReadResponse>(
          MarkConferenceReadResponse.$_createMessage);
  static MarkConferenceReadResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get markedCount => $_getI64(0);
  @$pb.TagNumber(1)
  set markedCount($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMarkedCount() => $_has(0);
  @$pb.TagNumber(1)
  void clearMarkedCount() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get snapshotCount => $_getI64(1);
  @$pb.TagNumber(2)
  set snapshotCount($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSnapshotCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearSnapshotCount() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get generation => $_getSZ(2);
  @$pb.TagNumber(3)
  set generation($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGeneration() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeneration() => $_clearField(3);
}

/// Additive UUE extension. UNIMPLEMENTED means ordinary text-only operation.
class UueLimits extends $pb.GeneratedMessage {
  factory UueLimits({
    $fixnum.Int64? maxFileBytes,
    $core.int? partBodyBytes,
    $core.int? maxParts,
    $core.int? chunkBytes,
    $fixnum.Int64? previewPixels,
    $core.int? previewDimension,
  }) {
    final result = UueLimits._();
    if (maxFileBytes != null) result.maxFileBytes = maxFileBytes;
    if (partBodyBytes != null) result.partBodyBytes = partBodyBytes;
    if (maxParts != null) result.maxParts = maxParts;
    if (chunkBytes != null) result.chunkBytes = chunkBytes;
    if (previewPixels != null) result.previewPixels = previewPixels;
    if (previewDimension != null) result.previewDimension = previewDimension;
    return result;
  }

  UueLimits._();

  factory UueLimits.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueLimits()..mergeFromBuffer(data, registry);
  factory UueLimits.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueLimits()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UueLimits',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: UueLimits.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'maxFileBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(2, _omitFieldNames ? '' : 'partBodyBytes',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'maxParts', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'chunkBytes', fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'previewPixels', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(6, _omitFieldNames ? '' : 'previewDimension',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueLimits clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueLimits copyWith(void Function(UueLimits) updates) =>
      super.copyWith((message) => updates(message as UueLimits)) as UueLimits;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UueLimits() / UueLimits.new instead')
  static UueLimits create() => UueLimits._();
  static $pb.GeneratedMessage $_createMessage() => UueLimits._();
  @$core.override
  UueLimits createEmptyInstance() => UueLimits._();
  @$core.pragma('dart2js:noInline')
  static UueLimits getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UueLimits>(UueLimits.$_createMessage);
  static UueLimits? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get maxFileBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set maxFileBytes($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMaxFileBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearMaxFileBytes() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get partBodyBytes => $_getIZ(1);
  @$pb.TagNumber(2)
  set partBodyBytes($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPartBodyBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearPartBodyBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxParts => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxParts($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxParts() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxParts() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get chunkBytes => $_getIZ(3);
  @$pb.TagNumber(4)
  set chunkBytes($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasChunkBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearChunkBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get previewPixels => $_getI64(4);
  @$pb.TagNumber(5)
  set previewPixels($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPreviewPixels() => $_has(4);
  @$pb.TagNumber(5)
  void clearPreviewPixels() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get previewDimension => $_getIZ(5);
  @$pb.TagNumber(6)
  set previewDimension($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPreviewDimension() => $_has(5);
  @$pb.TagNumber(6)
  void clearPreviewDimension() => $_clearField(6);
}

class UuePartReference extends $pb.GeneratedMessage {
  factory UuePartReference({
    MessageReference? message,
    $core.int? blockIndex,
  }) {
    final result = UuePartReference._();
    if (message != null) result.message = message;
    if (blockIndex != null) result.blockIndex = blockIndex;
    return result;
  }

  UuePartReference._();

  factory UuePartReference.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UuePartReference()..mergeFromBuffer(data, registry);
  factory UuePartReference.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UuePartReference()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UuePartReference',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: UuePartReference.$_createMessage)
    ..aOM<MessageReference>(1, _omitFieldNames ? '' : 'message',
        subBuilder: MessageReference.$_createMessage)
    ..aI(2, _omitFieldNames ? '' : 'blockIndex', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UuePartReference clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UuePartReference copyWith(void Function(UuePartReference) updates) =>
      super.copyWith((message) => updates(message as UuePartReference))
          as UuePartReference;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UuePartReference() / UuePartReference.new instead')
  static UuePartReference create() => UuePartReference._();
  static $pb.GeneratedMessage $_createMessage() => UuePartReference._();
  @$core.override
  UuePartReference createEmptyInstance() => UuePartReference._();
  @$core.pragma('dart2js:noInline')
  static UuePartReference getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UuePartReference>(
          UuePartReference.$_createMessage);
  static UuePartReference? _defaultInstance;

  @$pb.TagNumber(1)
  MessageReference get message => $_getN(0);
  @$pb.TagNumber(1)
  set message(MessageReference value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);
  @$pb.TagNumber(1)
  MessageReference ensureMessage() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.int get blockIndex => $_getIZ(1);
  @$pb.TagNumber(2)
  set blockIndex($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBlockIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearBlockIndex() => $_clearField(2);
}

class UuePart extends $pb.GeneratedMessage {
  factory UuePart({
    UuePartReference? source,
    $core.String? fromAddress,
    $core.String? toAddress,
    $core.String? subject,
    $core.String? transferId,
    $core.int? part,
    $core.int? total,
    $core.String? filename,
    $fixnum.Int64? decodedSize,
    $core.String? sha256,
    $core.int? bodyStart,
    $core.int? bodyEnd,
    $core.String? diagnostic,
    $core.String? date,
    MailDirection? direction,
  }) {
    final result = UuePart._();
    if (source != null) result.source = source;
    if (fromAddress != null) result.fromAddress = fromAddress;
    if (toAddress != null) result.toAddress = toAddress;
    if (subject != null) result.subject = subject;
    if (transferId != null) result.transferId = transferId;
    if (part != null) result.part = part;
    if (total != null) result.total = total;
    if (filename != null) result.filename = filename;
    if (decodedSize != null) result.decodedSize = decodedSize;
    if (sha256 != null) result.sha256 = sha256;
    if (bodyStart != null) result.bodyStart = bodyStart;
    if (bodyEnd != null) result.bodyEnd = bodyEnd;
    if (diagnostic != null) result.diagnostic = diagnostic;
    if (date != null) result.date = date;
    if (direction != null) result.direction = direction;
    return result;
  }

  UuePart._();

  factory UuePart.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UuePart()..mergeFromBuffer(data, registry);
  factory UuePart.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UuePart()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UuePart',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: UuePart.$_createMessage)
    ..aOM<UuePartReference>(1, _omitFieldNames ? '' : 'source',
        subBuilder: UuePartReference.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'fromAddress')
    ..aOS(3, _omitFieldNames ? '' : 'toAddress')
    ..aOS(4, _omitFieldNames ? '' : 'subject')
    ..aOS(5, _omitFieldNames ? '' : 'transferId')
    ..aI(6, _omitFieldNames ? '' : 'part', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'total', fieldType: $pb.PbFieldType.OU3)
    ..aOS(8, _omitFieldNames ? '' : 'filename')
    ..a<$fixnum.Int64>(
        9, _omitFieldNames ? '' : 'decodedSize', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(10, _omitFieldNames ? '' : 'sha256')
    ..aI(11, _omitFieldNames ? '' : 'bodyStart', fieldType: $pb.PbFieldType.OU3)
    ..aI(12, _omitFieldNames ? '' : 'bodyEnd', fieldType: $pb.PbFieldType.OU3)
    ..aOS(13, _omitFieldNames ? '' : 'diagnostic')
    ..aOS(14, _omitFieldNames ? '' : 'date')
    ..aE<MailDirection>(15, _omitFieldNames ? '' : 'direction',
        enumValues: MailDirection.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UuePart clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UuePart copyWith(void Function(UuePart) updates) =>
      super.copyWith((message) => updates(message as UuePart)) as UuePart;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UuePart() / UuePart.new instead')
  static UuePart create() => UuePart._();
  static $pb.GeneratedMessage $_createMessage() => UuePart._();
  @$core.override
  UuePart createEmptyInstance() => UuePart._();
  @$core.pragma('dart2js:noInline')
  static UuePart getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UuePart>(UuePart.$_createMessage);
  static UuePart? _defaultInstance;

  @$pb.TagNumber(1)
  UuePartReference get source => $_getN(0);
  @$pb.TagNumber(1)
  set source(UuePartReference value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSource() => $_has(0);
  @$pb.TagNumber(1)
  void clearSource() => $_clearField(1);
  @$pb.TagNumber(1)
  UuePartReference ensureSource() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get fromAddress => $_getSZ(1);
  @$pb.TagNumber(2)
  set fromAddress($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFromAddress() => $_has(1);
  @$pb.TagNumber(2)
  void clearFromAddress() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get toAddress => $_getSZ(2);
  @$pb.TagNumber(3)
  set toAddress($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasToAddress() => $_has(2);
  @$pb.TagNumber(3)
  void clearToAddress() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get subject => $_getSZ(3);
  @$pb.TagNumber(4)
  set subject($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSubject() => $_has(3);
  @$pb.TagNumber(4)
  void clearSubject() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get transferId => $_getSZ(4);
  @$pb.TagNumber(5)
  set transferId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTransferId() => $_has(4);
  @$pb.TagNumber(5)
  void clearTransferId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get part => $_getIZ(5);
  @$pb.TagNumber(6)
  set part($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPart() => $_has(5);
  @$pb.TagNumber(6)
  void clearPart() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get total => $_getIZ(6);
  @$pb.TagNumber(7)
  set total($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTotal() => $_has(6);
  @$pb.TagNumber(7)
  void clearTotal() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get filename => $_getSZ(7);
  @$pb.TagNumber(8)
  set filename($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasFilename() => $_has(7);
  @$pb.TagNumber(8)
  void clearFilename() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get decodedSize => $_getI64(8);
  @$pb.TagNumber(9)
  set decodedSize($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasDecodedSize() => $_has(8);
  @$pb.TagNumber(9)
  void clearDecodedSize() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get sha256 => $_getSZ(9);
  @$pb.TagNumber(10)
  set sha256($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasSha256() => $_has(9);
  @$pb.TagNumber(10)
  void clearSha256() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get bodyStart => $_getIZ(10);
  @$pb.TagNumber(11)
  set bodyStart($core.int value) => $_setUnsignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasBodyStart() => $_has(10);
  @$pb.TagNumber(11)
  void clearBodyStart() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get bodyEnd => $_getIZ(11);
  @$pb.TagNumber(12)
  set bodyEnd($core.int value) => $_setUnsignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasBodyEnd() => $_has(11);
  @$pb.TagNumber(12)
  void clearBodyEnd() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get diagnostic => $_getSZ(12);
  @$pb.TagNumber(13)
  set diagnostic($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasDiagnostic() => $_has(12);
  @$pb.TagNumber(13)
  void clearDiagnostic() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get date => $_getSZ(13);
  @$pb.TagNumber(14)
  set date($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasDate() => $_has(13);
  @$pb.TagNumber(14)
  void clearDate() => $_clearField(14);

  @$pb.TagNumber(15)
  MailDirection get direction => $_getN(14);
  @$pb.TagNumber(15)
  set direction(MailDirection value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasDirection() => $_has(14);
  @$pb.TagNumber(15)
  void clearDirection() => $_clearField(15);
}

class SearchUuePartsRequest extends $pb.GeneratedMessage {
  factory SearchUuePartsRequest({
    $core.String? conferenceId,
    $core.String? generation,
    $core.int? afterNumber,
    $core.int? limit,
  }) {
    final result = SearchUuePartsRequest._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (generation != null) result.generation = generation;
    if (afterNumber != null) result.afterNumber = afterNumber;
    if (limit != null) result.limit = limit;
    return result;
  }

  SearchUuePartsRequest._();

  factory SearchUuePartsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchUuePartsRequest()..mergeFromBuffer(data, registry);
  factory SearchUuePartsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchUuePartsRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchUuePartsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: SearchUuePartsRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'conferenceId')
    ..aOS(2, _omitFieldNames ? '' : 'generation')
    ..aI(3, _omitFieldNames ? '' : 'afterNumber',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'limit', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchUuePartsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchUuePartsRequest copyWith(
          void Function(SearchUuePartsRequest) updates) =>
      super.copyWith((message) => updates(message as SearchUuePartsRequest))
          as SearchUuePartsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SearchUuePartsRequest() / SearchUuePartsRequest.new instead')
  static SearchUuePartsRequest create() => SearchUuePartsRequest._();
  static $pb.GeneratedMessage $_createMessage() => SearchUuePartsRequest._();
  @$core.override
  SearchUuePartsRequest createEmptyInstance() => SearchUuePartsRequest._();
  @$core.pragma('dart2js:noInline')
  static SearchUuePartsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SearchUuePartsRequest>(
          SearchUuePartsRequest.$_createMessage);
  static SearchUuePartsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conferenceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conferenceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConferenceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConferenceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get generation => $_getSZ(1);
  @$pb.TagNumber(2)
  set generation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneration() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneration() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get afterNumber => $_getIZ(2);
  @$pb.TagNumber(3)
  set afterNumber($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAfterNumber() => $_has(2);
  @$pb.TagNumber(3)
  void clearAfterNumber() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get limit => $_getIZ(3);
  @$pb.TagNumber(4)
  set limit($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLimit() => $_has(3);
  @$pb.TagNumber(4)
  void clearLimit() => $_clearField(4);
}

class SearchUuePartsResponse extends $pb.GeneratedMessage {
  factory SearchUuePartsResponse({
    $core.Iterable<UuePart>? parts,
    $core.String? generation,
    $core.int? nextNumber,
    $core.bool? hasMore,
  }) {
    final result = SearchUuePartsResponse._();
    if (parts != null) result.parts.addAll(parts);
    if (generation != null) result.generation = generation;
    if (nextNumber != null) result.nextNumber = nextNumber;
    if (hasMore != null) result.hasMore = hasMore;
    return result;
  }

  SearchUuePartsResponse._();

  factory SearchUuePartsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchUuePartsResponse()..mergeFromBuffer(data, registry);
  factory SearchUuePartsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchUuePartsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchUuePartsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: SearchUuePartsResponse.$_createMessage)
    ..pPM<UuePart>(1, _omitFieldNames ? '' : 'parts',
        subBuilder: UuePart.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'generation')
    ..aI(3, _omitFieldNames ? '' : 'nextNumber', fieldType: $pb.PbFieldType.OU3)
    ..aOB(4, _omitFieldNames ? '' : 'hasMore')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchUuePartsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchUuePartsResponse copyWith(
          void Function(SearchUuePartsResponse) updates) =>
      super.copyWith((message) => updates(message as SearchUuePartsResponse))
          as SearchUuePartsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SearchUuePartsResponse() / SearchUuePartsResponse.new instead')
  static SearchUuePartsResponse create() => SearchUuePartsResponse._();
  static $pb.GeneratedMessage $_createMessage() => SearchUuePartsResponse._();
  @$core.override
  SearchUuePartsResponse createEmptyInstance() => SearchUuePartsResponse._();
  @$core.pragma('dart2js:noInline')
  static SearchUuePartsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SearchUuePartsResponse>(
          SearchUuePartsResponse.$_createMessage);
  static SearchUuePartsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<UuePart> get parts => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get generation => $_getSZ(1);
  @$pb.TagNumber(2)
  set generation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneration() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneration() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get nextNumber => $_getIZ(2);
  @$pb.TagNumber(3)
  set nextNumber($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNextNumber() => $_has(2);
  @$pb.TagNumber(3)
  void clearNextNumber() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get hasMore => $_getBF(3);
  @$pb.TagNumber(4)
  set hasMore($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasHasMore() => $_has(3);
  @$pb.TagNumber(4)
  void clearHasMore() => $_clearField(4);
}

class AssembleUueRequest extends $pb.GeneratedMessage {
  factory AssembleUueRequest({
    $core.Iterable<UuePartReference>? sources,
    $core.bool? explicitOrder,
  }) {
    final result = AssembleUueRequest._();
    if (sources != null) result.sources.addAll(sources);
    if (explicitOrder != null) result.explicitOrder = explicitOrder;
    return result;
  }

  AssembleUueRequest._();

  factory AssembleUueRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AssembleUueRequest()..mergeFromBuffer(data, registry);
  factory AssembleUueRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AssembleUueRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AssembleUueRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: AssembleUueRequest.$_createMessage)
    ..pPM<UuePartReference>(1, _omitFieldNames ? '' : 'sources',
        subBuilder: UuePartReference.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'explicitOrder')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AssembleUueRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AssembleUueRequest copyWith(void Function(AssembleUueRequest) updates) =>
      super.copyWith((message) => updates(message as AssembleUueRequest))
          as AssembleUueRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AssembleUueRequest() / AssembleUueRequest.new instead')
  static AssembleUueRequest create() => AssembleUueRequest._();
  static $pb.GeneratedMessage $_createMessage() => AssembleUueRequest._();
  @$core.override
  AssembleUueRequest createEmptyInstance() => AssembleUueRequest._();
  @$core.pragma('dart2js:noInline')
  static AssembleUueRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AssembleUueRequest>(
          AssembleUueRequest.$_createMessage);
  static AssembleUueRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<UuePartReference> get sources => $_getList(0);

  /// False sorts validated FFIDO metadata or legacy sender/subject/numbering.
  /// Legacy automatic assembly does not prove integrity; surface the mixing warning.
  /// True uses explicitly chosen order for legacy parts, including unnumbered parts.
  @$pb.TagNumber(2)
  $core.bool get explicitOrder => $_getBF(1);
  @$pb.TagNumber(2)
  set explicitOrder($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExplicitOrder() => $_has(1);
  @$pb.TagNumber(2)
  void clearExplicitOrder() => $_clearField(2);
}

class UueAttachment extends $pb.GeneratedMessage {
  factory UueAttachment({
    $core.String? id,
    $core.String? filename,
    $fixnum.Int64? size,
    $core.String? sha256,
    $core.bool? checksumVerified,
    UueState? state,
    $core.Iterable<$core.int>? missingParts,
    $core.Iterable<UuePartReference>? sources,
    $core.String? diagnostic,
  }) {
    final result = UueAttachment._();
    if (id != null) result.id = id;
    if (filename != null) result.filename = filename;
    if (size != null) result.size = size;
    if (sha256 != null) result.sha256 = sha256;
    if (checksumVerified != null) result.checksumVerified = checksumVerified;
    if (state != null) result.state = state;
    if (missingParts != null) result.missingParts.addAll(missingParts);
    if (sources != null) result.sources.addAll(sources);
    if (diagnostic != null) result.diagnostic = diagnostic;
    return result;
  }

  UueAttachment._();

  factory UueAttachment.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueAttachment()..mergeFromBuffer(data, registry);
  factory UueAttachment.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueAttachment()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UueAttachment',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: UueAttachment.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'filename')
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'size', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(4, _omitFieldNames ? '' : 'sha256')
    ..aOB(5, _omitFieldNames ? '' : 'checksumVerified')
    ..aE<UueState>(6, _omitFieldNames ? '' : 'state',
        enumValues: UueState.values)
    ..p<$core.int>(
        7, _omitFieldNames ? '' : 'missingParts', $pb.PbFieldType.KU3)
    ..pPM<UuePartReference>(8, _omitFieldNames ? '' : 'sources',
        subBuilder: UuePartReference.$_createMessage)
    ..aOS(9, _omitFieldNames ? '' : 'diagnostic')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueAttachment clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueAttachment copyWith(void Function(UueAttachment) updates) =>
      super.copyWith((message) => updates(message as UueAttachment))
          as UueAttachment;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UueAttachment() / UueAttachment.new instead')
  static UueAttachment create() => UueAttachment._();
  static $pb.GeneratedMessage $_createMessage() => UueAttachment._();
  @$core.override
  UueAttachment createEmptyInstance() => UueAttachment._();
  @$core.pragma('dart2js:noInline')
  static UueAttachment getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UueAttachment>(
          UueAttachment.$_createMessage);
  static UueAttachment? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get filename => $_getSZ(1);
  @$pb.TagNumber(2)
  set filename($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFilename() => $_has(1);
  @$pb.TagNumber(2)
  void clearFilename() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get size => $_getI64(2);
  @$pb.TagNumber(3)
  set size($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearSize() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sha256 => $_getSZ(3);
  @$pb.TagNumber(4)
  set sha256($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSha256() => $_has(3);
  @$pb.TagNumber(4)
  void clearSha256() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get checksumVerified => $_getBF(4);
  @$pb.TagNumber(5)
  set checksumVerified($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasChecksumVerified() => $_has(4);
  @$pb.TagNumber(5)
  void clearChecksumVerified() => $_clearField(5);

  @$pb.TagNumber(6)
  UueState get state => $_getN(5);
  @$pb.TagNumber(6)
  set state(UueState value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasState() => $_has(5);
  @$pb.TagNumber(6)
  void clearState() => $_clearField(6);

  @$pb.TagNumber(7)
  $pb.PbList<$core.int> get missingParts => $_getList(6);

  @$pb.TagNumber(8)
  $pb.PbList<UuePartReference> get sources => $_getList(7);

  @$pb.TagNumber(9)
  $core.String get diagnostic => $_getSZ(8);
  @$pb.TagNumber(9)
  set diagnostic($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasDiagnostic() => $_has(8);
  @$pb.TagNumber(9)
  void clearDiagnostic() => $_clearField(9);
}

class GetUueChunkRequest extends $pb.GeneratedMessage {
  factory GetUueChunkRequest({
    $core.String? attachmentId,
    $fixnum.Int64? offset,
    $core.int? maxBytes,
  }) {
    final result = GetUueChunkRequest._();
    if (attachmentId != null) result.attachmentId = attachmentId;
    if (offset != null) result.offset = offset;
    if (maxBytes != null) result.maxBytes = maxBytes;
    return result;
  }

  GetUueChunkRequest._();

  factory GetUueChunkRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetUueChunkRequest()..mergeFromBuffer(data, registry);
  factory GetUueChunkRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetUueChunkRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetUueChunkRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: GetUueChunkRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'attachmentId')
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'offset', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(3, _omitFieldNames ? '' : 'maxBytes', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetUueChunkRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetUueChunkRequest copyWith(void Function(GetUueChunkRequest) updates) =>
      super.copyWith((message) => updates(message as GetUueChunkRequest))
          as GetUueChunkRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetUueChunkRequest() / GetUueChunkRequest.new instead')
  static GetUueChunkRequest create() => GetUueChunkRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetUueChunkRequest._();
  @$core.override
  GetUueChunkRequest createEmptyInstance() => GetUueChunkRequest._();
  @$core.pragma('dart2js:noInline')
  static GetUueChunkRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetUueChunkRequest>(
          GetUueChunkRequest.$_createMessage);
  static GetUueChunkRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get attachmentId => $_getSZ(0);
  @$pb.TagNumber(1)
  set attachmentId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAttachmentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAttachmentId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get offset => $_getI64(1);
  @$pb.TagNumber(2)
  set offset($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOffset() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffset() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxBytes => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxBytes($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxBytes() => $_clearField(3);
}

class UueChunk extends $pb.GeneratedMessage {
  factory UueChunk({
    $core.List<$core.int>? data,
    $fixnum.Int64? offset,
    $fixnum.Int64? totalSize,
    $core.bool? eof,
  }) {
    final result = UueChunk._();
    if (data != null) result.data = data;
    if (offset != null) result.offset = offset;
    if (totalSize != null) result.totalSize = totalSize;
    if (eof != null) result.eof = eof;
    return result;
  }

  UueChunk._();

  factory UueChunk.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueChunk()..mergeFromBuffer(data, registry);
  factory UueChunk.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueChunk()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UueChunk',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: UueChunk.$_createMessage)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'offset', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'totalSize', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(4, _omitFieldNames ? '' : 'eof')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueChunk clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueChunk copyWith(void Function(UueChunk) updates) =>
      super.copyWith((message) => updates(message as UueChunk)) as UueChunk;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UueChunk() / UueChunk.new instead')
  static UueChunk create() => UueChunk._();
  static $pb.GeneratedMessage $_createMessage() => UueChunk._();
  @$core.override
  UueChunk createEmptyInstance() => UueChunk._();
  @$core.pragma('dart2js:noInline')
  static UueChunk getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UueChunk>(UueChunk.$_createMessage);
  static UueChunk? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get offset => $_getI64(1);
  @$pb.TagNumber(2)
  set offset($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOffset() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffset() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get totalSize => $_getI64(2);
  @$pb.TagNumber(3)
  set totalSize($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotalSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalSize() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get eof => $_getBF(3);
  @$pb.TagNumber(4)
  set eof($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEof() => $_has(3);
  @$pb.TagNumber(4)
  void clearEof() => $_clearField(4);
}

class UueOperationReference extends $pb.GeneratedMessage {
  factory UueOperationReference({
    $core.String? operationId,
  }) {
    final result = UueOperationReference._();
    if (operationId != null) result.operationId = operationId;
    return result;
  }

  UueOperationReference._();

  factory UueOperationReference.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueOperationReference()..mergeFromBuffer(data, registry);
  factory UueOperationReference.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueOperationReference()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UueOperationReference',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: UueOperationReference.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'operationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueOperationReference clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueOperationReference copyWith(
          void Function(UueOperationReference) updates) =>
      super.copyWith((message) => updates(message as UueOperationReference))
          as UueOperationReference;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use UueOperationReference() / UueOperationReference.new instead')
  static UueOperationReference create() => UueOperationReference._();
  static $pb.GeneratedMessage $_createMessage() => UueOperationReference._();
  @$core.override
  UueOperationReference createEmptyInstance() => UueOperationReference._();
  @$core.pragma('dart2js:noInline')
  static UueOperationReference getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UueOperationReference>(
          UueOperationReference.$_createMessage);
  static UueOperationReference? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get operationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationId() => $_clearField(1);
}

class UploadUueChunkRequest extends $pb.GeneratedMessage {
  factory UploadUueChunkRequest({
    $core.String? operationId,
    $core.String? filename,
    $fixnum.Int64? fileSize,
    $core.String? sha256,
    $fixnum.Int64? offset,
    $core.List<$core.int>? data,
  }) {
    final result = UploadUueChunkRequest._();
    if (operationId != null) result.operationId = operationId;
    if (filename != null) result.filename = filename;
    if (fileSize != null) result.fileSize = fileSize;
    if (sha256 != null) result.sha256 = sha256;
    if (offset != null) result.offset = offset;
    if (data != null) result.data = data;
    return result;
  }

  UploadUueChunkRequest._();

  factory UploadUueChunkRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UploadUueChunkRequest()..mergeFromBuffer(data, registry);
  factory UploadUueChunkRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UploadUueChunkRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UploadUueChunkRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: UploadUueChunkRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'operationId')
    ..aOS(2, _omitFieldNames ? '' : 'filename')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'fileSize', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(4, _omitFieldNames ? '' : 'sha256')
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'offset', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        6, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UploadUueChunkRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UploadUueChunkRequest copyWith(
          void Function(UploadUueChunkRequest) updates) =>
      super.copyWith((message) => updates(message as UploadUueChunkRequest))
          as UploadUueChunkRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use UploadUueChunkRequest() / UploadUueChunkRequest.new instead')
  static UploadUueChunkRequest create() => UploadUueChunkRequest._();
  static $pb.GeneratedMessage $_createMessage() => UploadUueChunkRequest._();
  @$core.override
  UploadUueChunkRequest createEmptyInstance() => UploadUueChunkRequest._();
  @$core.pragma('dart2js:noInline')
  static UploadUueChunkRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UploadUueChunkRequest>(
          UploadUueChunkRequest.$_createMessage);
  static UploadUueChunkRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get operationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get filename => $_getSZ(1);
  @$pb.TagNumber(2)
  set filename($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFilename() => $_has(1);
  @$pb.TagNumber(2)
  void clearFilename() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get fileSize => $_getI64(2);
  @$pb.TagNumber(3)
  set fileSize($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFileSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearFileSize() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sha256 => $_getSZ(3);
  @$pb.TagNumber(4)
  set sha256($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSha256() => $_has(3);
  @$pb.TagNumber(4)
  void clearSha256() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get offset => $_getI64(4);
  @$pb.TagNumber(5)
  set offset($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOffset() => $_has(4);
  @$pb.TagNumber(5)
  void clearOffset() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.int> get data => $_getN(5);
  @$pb.TagNumber(6)
  set data($core.List<$core.int> value) => $_setBytes(5, value);
  @$pb.TagNumber(6)
  $core.bool hasData() => $_has(5);
  @$pb.TagNumber(6)
  void clearData() => $_clearField(6);
}

class UueUploadStatus extends $pb.GeneratedMessage {
  factory UueUploadStatus({
    $fixnum.Int64? receivedBytes,
    $core.bool? complete,
  }) {
    final result = UueUploadStatus._();
    if (receivedBytes != null) result.receivedBytes = receivedBytes;
    if (complete != null) result.complete = complete;
    return result;
  }

  UueUploadStatus._();

  factory UueUploadStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueUploadStatus()..mergeFromBuffer(data, registry);
  factory UueUploadStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueUploadStatus()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UueUploadStatus',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: UueUploadStatus.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'receivedBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(2, _omitFieldNames ? '' : 'complete')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueUploadStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueUploadStatus copyWith(void Function(UueUploadStatus) updates) =>
      super.copyWith((message) => updates(message as UueUploadStatus))
          as UueUploadStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UueUploadStatus() / UueUploadStatus.new instead')
  static UueUploadStatus create() => UueUploadStatus._();
  static $pb.GeneratedMessage $_createMessage() => UueUploadStatus._();
  @$core.override
  UueUploadStatus createEmptyInstance() => UueUploadStatus._();
  @$core.pragma('dart2js:noInline')
  static UueUploadStatus getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UueUploadStatus>(
          UueUploadStatus.$_createMessage);
  static UueUploadStatus? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get receivedBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set receivedBytes($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReceivedBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearReceivedBytes() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get complete => $_getBF(1);
  @$pb.TagNumber(2)
  set complete($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasComplete() => $_has(1);
  @$pb.TagNumber(2)
  void clearComplete() => $_clearField(2);
}

class CommitUueRequest extends $pb.GeneratedMessage {
  factory CommitUueRequest({
    CreateMessageRequest? message,
  }) {
    final result = CommitUueRequest._();
    if (message != null) result.message = message;
    return result;
  }

  CommitUueRequest._();

  factory CommitUueRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CommitUueRequest()..mergeFromBuffer(data, registry);
  factory CommitUueRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CommitUueRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommitUueRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: CommitUueRequest.$_createMessage)
    ..aOM<CreateMessageRequest>(1, _omitFieldNames ? '' : 'message',
        subBuilder: CreateMessageRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitUueRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommitUueRequest copyWith(void Function(CommitUueRequest) updates) =>
      super.copyWith((message) => updates(message as CommitUueRequest))
          as CommitUueRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CommitUueRequest() / CommitUueRequest.new instead')
  static CommitUueRequest create() => CommitUueRequest._();
  static $pb.GeneratedMessage $_createMessage() => CommitUueRequest._();
  @$core.override
  CommitUueRequest createEmptyInstance() => CommitUueRequest._();
  @$core.pragma('dart2js:noInline')
  static CommitUueRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CommitUueRequest>(
          CommitUueRequest.$_createMessage);
  static CommitUueRequest? _defaultInstance;

  /// body is the author's text only; server adds the staged UUE file.
  @$pb.TagNumber(1)
  CreateMessageRequest get message => $_getN(0);
  @$pb.TagNumber(1)
  set message(CreateMessageRequest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);
  @$pb.TagNumber(1)
  CreateMessageRequest ensureMessage() => $_ensure(0);
}

class UueSendStatus extends $pb.GeneratedMessage {
  factory UueSendStatus({
    $core.String? operationId,
    $core.String? state,
    $core.int? totalParts,
    $core.int? savedParts,
    $core.Iterable<MessageReference>? messages,
    $core.String? diagnostic,
    $core.String? filename,
    $fixnum.Int64? fileSize,
    $core.String? sha256,
  }) {
    final result = UueSendStatus._();
    if (operationId != null) result.operationId = operationId;
    if (state != null) result.state = state;
    if (totalParts != null) result.totalParts = totalParts;
    if (savedParts != null) result.savedParts = savedParts;
    if (messages != null) result.messages.addAll(messages);
    if (diagnostic != null) result.diagnostic = diagnostic;
    if (filename != null) result.filename = filename;
    if (fileSize != null) result.fileSize = fileSize;
    if (sha256 != null) result.sha256 = sha256;
    return result;
  }

  UueSendStatus._();

  factory UueSendStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueSendStatus()..mergeFromBuffer(data, registry);
  factory UueSendStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      UueSendStatus()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UueSendStatus',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: UueSendStatus.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'operationId')
    ..aOS(2, _omitFieldNames ? '' : 'state')
    ..aI(3, _omitFieldNames ? '' : 'totalParts', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'savedParts', fieldType: $pb.PbFieldType.OU3)
    ..pPM<MessageReference>(5, _omitFieldNames ? '' : 'messages',
        subBuilder: MessageReference.$_createMessage)
    ..aOS(6, _omitFieldNames ? '' : 'diagnostic')
    ..aOS(7, _omitFieldNames ? '' : 'filename')
    ..a<$fixnum.Int64>(
        8, _omitFieldNames ? '' : 'fileSize', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(9, _omitFieldNames ? '' : 'sha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueSendStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UueSendStatus copyWith(void Function(UueSendStatus) updates) =>
      super.copyWith((message) => updates(message as UueSendStatus))
          as UueSendStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use UueSendStatus() / UueSendStatus.new instead')
  static UueSendStatus create() => UueSendStatus._();
  static $pb.GeneratedMessage $_createMessage() => UueSendStatus._();
  @$core.override
  UueSendStatus createEmptyInstance() => UueSendStatus._();
  @$core.pragma('dart2js:noInline')
  static UueSendStatus getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<UueSendStatus>(
          UueSendStatus.$_createMessage);
  static UueSendStatus? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get operationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get state => $_getSZ(1);
  @$pb.TagNumber(2)
  set state($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get totalParts => $_getIZ(2);
  @$pb.TagNumber(3)
  set totalParts($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotalParts() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalParts() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get savedParts => $_getIZ(3);
  @$pb.TagNumber(4)
  set savedParts($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSavedParts() => $_has(3);
  @$pb.TagNumber(4)
  void clearSavedParts() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<MessageReference> get messages => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get diagnostic => $_getSZ(5);
  @$pb.TagNumber(6)
  set diagnostic($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDiagnostic() => $_has(5);
  @$pb.TagNumber(6)
  void clearDiagnostic() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get filename => $_getSZ(6);
  @$pb.TagNumber(7)
  set filename($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasFilename() => $_has(6);
  @$pb.TagNumber(7)
  void clearFilename() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get fileSize => $_getI64(7);
  @$pb.TagNumber(8)
  set fileSize($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasFileSize() => $_has(7);
  @$pb.TagNumber(8)
  void clearFileSize() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get sha256 => $_getSZ(8);
  @$pb.TagNumber(9)
  set sha256($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSha256() => $_has(8);
  @$pb.TagNumber(9)
  void clearSha256() => $_clearField(9);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
