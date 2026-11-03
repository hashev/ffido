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
    $core.bool? respectPersonalFilters,
  }) {
    final result = ListMessagesRequest._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (page != null) result.page = page;
    if (query != null) result.query = query;
    if (sort != null) result.sort = sort;
    if (anchorMessageId != null) result.anchorMessageId = anchorMessageId;
    if (respectPersonalFilters != null)
      result.respectPersonalFilters = respectPersonalFilters;
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
    ..aOB(6, _omitFieldNames ? '' : 'respectPersonalFilters')
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

  @$pb.TagNumber(6)
  $core.bool get respectPersonalFilters => $_getBF(5);
  @$pb.TagNumber(6)
  set respectPersonalFilters($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRespectPersonalFilters() => $_has(5);
  @$pb.TagNumber(6)
  void clearRespectPersonalFilters() => $_clearField(6);
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
    PersonalMessageCollapse? personalCollapse,
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
    if (personalCollapse != null) result.personalCollapse = personalCollapse;
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
    ..aOM<PersonalMessageCollapse>(
        18, _omitFieldNames ? '' : 'personalCollapse',
        subBuilder: PersonalMessageCollapse.$_createMessage)
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

  @$pb.TagNumber(18)
  PersonalMessageCollapse get personalCollapse => $_getN(17);
  @$pb.TagNumber(18)
  set personalCollapse(PersonalMessageCollapse value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasPersonalCollapse() => $_has(17);
  @$pb.TagNumber(18)
  void clearPersonalCollapse() => $_clearField(18);
  @$pb.TagNumber(18)
  PersonalMessageCollapse ensurePersonalCollapse() => $_ensure(17);
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

class MessageFooter extends $pb.GeneratedMessage {
  factory MessageFooter({
    $core.String? tagline,
    $core.String? origin,
  }) {
    final result = MessageFooter._();
    if (tagline != null) result.tagline = tagline;
    if (origin != null) result.origin = origin;
    return result;
  }

  MessageFooter._();

  factory MessageFooter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessageFooter()..mergeFromBuffer(data, registry);
  factory MessageFooter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessageFooter()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MessageFooter',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: MessageFooter.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'tagline')
    ..aOS(2, _omitFieldNames ? '' : 'origin')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessageFooter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessageFooter copyWith(void Function(MessageFooter) updates) =>
      super.copyWith((message) => updates(message as MessageFooter))
          as MessageFooter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MessageFooter() / MessageFooter.new instead')
  static MessageFooter create() => MessageFooter._();
  static $pb.GeneratedMessage $_createMessage() => MessageFooter._();
  @$core.override
  MessageFooter createEmptyInstance() => MessageFooter._();
  @$core.pragma('dart2js:noInline')
  static MessageFooter getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MessageFooter>(
          MessageFooter.$_createMessage);
  static MessageFooter? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get tagline => $_getSZ(0);
  @$pb.TagNumber(1)
  set tagline($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTagline() => $_has(0);
  @$pb.TagNumber(1)
  void clearTagline() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get origin => $_getSZ(1);
  @$pb.TagNumber(2)
  set origin($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOrigin() => $_has(1);
  @$pb.TagNumber(2)
  void clearOrigin() => $_clearField(2);
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
    MessageFooter? footer,
    $core.String? expectedPreviewDigest,
  }) {
    final result = CreateMessageRequest._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (operationId != null) result.operationId = operationId;
    if (toName != null) result.toName = toName;
    if (toAddress != null) result.toAddress = toAddress;
    if (subject != null) result.subject = subject;
    if (body != null) result.body = body;
    if (inReplyTo != null) result.inReplyTo = inReplyTo;
    if (footer != null) result.footer = footer;
    if (expectedPreviewDigest != null)
      result.expectedPreviewDigest = expectedPreviewDigest;
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
    ..aOM<MessageFooter>(8, _omitFieldNames ? '' : 'footer',
        subBuilder: MessageFooter.$_createMessage)
    ..aOS(9, _omitFieldNames ? '' : 'expectedPreviewDigest')
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

  @$pb.TagNumber(8)
  MessageFooter get footer => $_getN(7);
  @$pb.TagNumber(8)
  set footer(MessageFooter value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasFooter() => $_has(7);
  @$pb.TagNumber(8)
  void clearFooter() => $_clearField(8);
  @$pb.TagNumber(8)
  MessageFooter ensureFooter() => $_ensure(7);

  @$pb.TagNumber(9)
  $core.String get expectedPreviewDigest => $_getSZ(8);
  @$pb.TagNumber(9)
  set expectedPreviewDigest($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasExpectedPreviewDigest() => $_has(8);
  @$pb.TagNumber(9)
  void clearExpectedPreviewDigest() => $_clearField(9);
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
    $core.bool? respectPersonalFilters,
  }) {
    final result = GetThreadRequest._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (threadId != null) result.threadId = threadId;
    if (page != null) result.page = page;
    if (respectPersonalFilters != null)
      result.respectPersonalFilters = respectPersonalFilters;
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
    ..aOB(4, _omitFieldNames ? '' : 'respectPersonalFilters')
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

  @$pb.TagNumber(4)
  $core.bool get respectPersonalFilters => $_getBF(3);
  @$pb.TagNumber(4)
  set respectPersonalFilters($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRespectPersonalFilters() => $_has(3);
  @$pb.TagNumber(4)
  void clearRespectPersonalFilters() => $_clearField(4);
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
    $core.bool? supportsMessageFooter,
  }) {
    final result = SessionInfo._();
    if (profile != null) result.profile = profile;
    if (expiresAt != null) result.expiresAt = expiresAt;
    if (supportsMessageFooter != null)
      result.supportsMessageFooter = supportsMessageFooter;
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
    ..aOB(3, _omitFieldNames ? '' : 'supportsMessageFooter')
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

  @$pb.TagNumber(3)
  $core.bool get supportsMessageFooter => $_getBF(2);
  @$pb.TagNumber(3)
  set supportsMessageFooter($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSupportsMessageFooter() => $_has(2);
  @$pb.TagNumber(3)
  void clearSupportsMessageFooter() => $_clearField(3);
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

class FindMessageRequest extends $pb.GeneratedMessage {
  factory FindMessageRequest({
    $core.String? conferenceId,
    $core.String? query,
    MessageSearchScope? scope,
    MessageSort? sort,
    $core.String? startMessageId,
    $core.bool? includeStart,
    $core.bool? respectPersonalFilters,
  }) {
    final result = FindMessageRequest._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (query != null) result.query = query;
    if (scope != null) result.scope = scope;
    if (sort != null) result.sort = sort;
    if (startMessageId != null) result.startMessageId = startMessageId;
    if (includeStart != null) result.includeStart = includeStart;
    if (respectPersonalFilters != null)
      result.respectPersonalFilters = respectPersonalFilters;
    return result;
  }

  FindMessageRequest._();

  factory FindMessageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FindMessageRequest()..mergeFromBuffer(data, registry);
  factory FindMessageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FindMessageRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FindMessageRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: FindMessageRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'conferenceId')
    ..aOS(2, _omitFieldNames ? '' : 'query')
    ..aE<MessageSearchScope>(3, _omitFieldNames ? '' : 'scope',
        enumValues: MessageSearchScope.values)
    ..aE<MessageSort>(4, _omitFieldNames ? '' : 'sort',
        enumValues: MessageSort.values)
    ..aOS(5, _omitFieldNames ? '' : 'startMessageId')
    ..aOB(6, _omitFieldNames ? '' : 'includeStart')
    ..aOB(7, _omitFieldNames ? '' : 'respectPersonalFilters')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FindMessageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FindMessageRequest copyWith(void Function(FindMessageRequest) updates) =>
      super.copyWith((message) => updates(message as FindMessageRequest))
          as FindMessageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FindMessageRequest() / FindMessageRequest.new instead')
  static FindMessageRequest create() => FindMessageRequest._();
  static $pb.GeneratedMessage $_createMessage() => FindMessageRequest._();
  @$core.override
  FindMessageRequest createEmptyInstance() => FindMessageRequest._();
  @$core.pragma('dart2js:noInline')
  static FindMessageRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FindMessageRequest>(
          FindMessageRequest.$_createMessage);
  static FindMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conferenceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conferenceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConferenceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConferenceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get query => $_getSZ(1);
  @$pb.TagNumber(2)
  set query($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasQuery() => $_has(1);
  @$pb.TagNumber(2)
  void clearQuery() => $_clearField(2);

  @$pb.TagNumber(3)
  MessageSearchScope get scope => $_getN(2);
  @$pb.TagNumber(3)
  set scope(MessageSearchScope value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasScope() => $_has(2);
  @$pb.TagNumber(3)
  void clearScope() => $_clearField(3);

  @$pb.TagNumber(4)
  MessageSort get sort => $_getN(3);
  @$pb.TagNumber(4)
  set sort(MessageSort value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSort() => $_has(3);
  @$pb.TagNumber(4)
  void clearSort() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get startMessageId => $_getSZ(4);
  @$pb.TagNumber(5)
  set startMessageId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasStartMessageId() => $_has(4);
  @$pb.TagNumber(5)
  void clearStartMessageId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get includeStart => $_getBF(5);
  @$pb.TagNumber(6)
  set includeStart($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIncludeStart() => $_has(5);
  @$pb.TagNumber(6)
  void clearIncludeStart() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get respectPersonalFilters => $_getBF(6);
  @$pb.TagNumber(7)
  set respectPersonalFilters($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRespectPersonalFilters() => $_has(6);
  @$pb.TagNumber(7)
  void clearRespectPersonalFilters() => $_clearField(7);
}

class SearchMatch extends $pb.GeneratedMessage {
  factory SearchMatch({
    MessageSearchField? field_1,
    $core.int? startUtf16,
    $core.int? lengthUtf16,
  }) {
    final result = SearchMatch._();
    if (field_1 != null) result.field_1 = field_1;
    if (startUtf16 != null) result.startUtf16 = startUtf16;
    if (lengthUtf16 != null) result.lengthUtf16 = lengthUtf16;
    return result;
  }

  SearchMatch._();

  factory SearchMatch.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchMatch()..mergeFromBuffer(data, registry);
  factory SearchMatch.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchMatch()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchMatch',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: SearchMatch.$_createMessage)
    ..aE<MessageSearchField>(1, _omitFieldNames ? '' : 'field',
        enumValues: MessageSearchField.values)
    ..aI(2, _omitFieldNames ? '' : 'startUtf16', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'lengthUtf16',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchMatch clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchMatch copyWith(void Function(SearchMatch) updates) =>
      super.copyWith((message) => updates(message as SearchMatch))
          as SearchMatch;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SearchMatch() / SearchMatch.new instead')
  static SearchMatch create() => SearchMatch._();
  static $pb.GeneratedMessage $_createMessage() => SearchMatch._();
  @$core.override
  SearchMatch createEmptyInstance() => SearchMatch._();
  @$core.pragma('dart2js:noInline')
  static SearchMatch getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SearchMatch>(
          SearchMatch.$_createMessage);
  static SearchMatch? _defaultInstance;

  @$pb.TagNumber(1)
  MessageSearchField get field_1 => $_getN(0);
  @$pb.TagNumber(1)
  set field_1(MessageSearchField value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasField_1() => $_has(0);
  @$pb.TagNumber(1)
  void clearField_1() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get startUtf16 => $_getIZ(1);
  @$pb.TagNumber(2)
  set startUtf16($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStartUtf16() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartUtf16() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get lengthUtf16 => $_getIZ(2);
  @$pb.TagNumber(3)
  set lengthUtf16($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLengthUtf16() => $_has(2);
  @$pb.TagNumber(3)
  void clearLengthUtf16() => $_clearField(3);
}

class FindMessageResponse extends $pb.GeneratedMessage {
  factory FindMessageResponse({
    Message? message,
    $core.Iterable<SearchMatch>? matches,
  }) {
    final result = FindMessageResponse._();
    if (message != null) result.message = message;
    if (matches != null) result.matches.addAll(matches);
    return result;
  }

  FindMessageResponse._();

  factory FindMessageResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FindMessageResponse()..mergeFromBuffer(data, registry);
  factory FindMessageResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FindMessageResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FindMessageResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: FindMessageResponse.$_createMessage)
    ..aOM<Message>(1, _omitFieldNames ? '' : 'message',
        subBuilder: Message.$_createMessage)
    ..pPM<SearchMatch>(2, _omitFieldNames ? '' : 'matches',
        subBuilder: SearchMatch.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FindMessageResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FindMessageResponse copyWith(void Function(FindMessageResponse) updates) =>
      super.copyWith((message) => updates(message as FindMessageResponse))
          as FindMessageResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use FindMessageResponse() / FindMessageResponse.new instead')
  static FindMessageResponse create() => FindMessageResponse._();
  static $pb.GeneratedMessage $_createMessage() => FindMessageResponse._();
  @$core.override
  FindMessageResponse createEmptyInstance() => FindMessageResponse._();
  @$core.pragma('dart2js:noInline')
  static FindMessageResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FindMessageResponse>(
          FindMessageResponse.$_createMessage);
  static FindMessageResponse? _defaultInstance;

  /// Отсутствие message означает конец поиска, а не ошибку.
  @$pb.TagNumber(1)
  Message get message => $_getN(0);
  @$pb.TagNumber(1)
  set message(Message value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);
  @$pb.TagNumber(1)
  Message ensureMessage() => $_ensure(0);

  @$pb.TagNumber(2)
  $pb.PbList<SearchMatch> get matches => $_getList(1);
}

/// Сырые технические подполя: порядок, high_id и пустые значения значимы.
class MessageTechnicalSubfield extends $pb.GeneratedMessage {
  factory MessageTechnicalSubfield({
    $core.int? lowId,
    $core.int? highId,
    $core.List<$core.int>? value,
  }) {
    final result = MessageTechnicalSubfield._();
    if (lowId != null) result.lowId = lowId;
    if (highId != null) result.highId = highId;
    if (value != null) result.value = value;
    return result;
  }

  MessageTechnicalSubfield._();

  factory MessageTechnicalSubfield.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessageTechnicalSubfield()..mergeFromBuffer(data, registry);
  factory MessageTechnicalSubfield.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessageTechnicalSubfield()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MessageTechnicalSubfield',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: MessageTechnicalSubfield.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'lowId', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'highId', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'value', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessageTechnicalSubfield clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessageTechnicalSubfield copyWith(
          void Function(MessageTechnicalSubfield) updates) =>
      super.copyWith((message) => updates(message as MessageTechnicalSubfield))
          as MessageTechnicalSubfield;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use MessageTechnicalSubfield() / MessageTechnicalSubfield.new instead')
  static MessageTechnicalSubfield create() => MessageTechnicalSubfield._();
  static $pb.GeneratedMessage $_createMessage() => MessageTechnicalSubfield._();
  @$core.override
  MessageTechnicalSubfield createEmptyInstance() =>
      MessageTechnicalSubfield._();
  @$core.pragma('dart2js:noInline')
  static MessageTechnicalSubfield getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MessageTechnicalSubfield>(
          MessageTechnicalSubfield.$_createMessage);
  static MessageTechnicalSubfield? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get lowId => $_getIZ(0);
  @$pb.TagNumber(1)
  set lowId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLowId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLowId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get highId => $_getIZ(1);
  @$pb.TagNumber(2)
  set highId($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHighId() => $_has(1);
  @$pb.TagNumber(2)
  void clearHighId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get value => $_getN(2);
  @$pb.TagNumber(3)
  set value($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasValue() => $_has(2);
  @$pb.TagNumber(3)
  void clearValue() => $_clearField(3);
}

class MessageTechnicalData extends $pb.GeneratedMessage {
  factory MessageTechnicalData({
    MessageReference? message,
    $core.int? attributes,
    $core.int? attributes2,
    $core.Iterable<MessageTechnicalSubfield>? subfields,
    TechnicalEncodingStatus? encodingStatus,
    $core.String? effectiveEncoding,
  }) {
    final result = MessageTechnicalData._();
    if (message != null) result.message = message;
    if (attributes != null) result.attributes = attributes;
    if (attributes2 != null) result.attributes2 = attributes2;
    if (subfields != null) result.subfields.addAll(subfields);
    if (encodingStatus != null) result.encodingStatus = encodingStatus;
    if (effectiveEncoding != null) result.effectiveEncoding = effectiveEncoding;
    return result;
  }

  MessageTechnicalData._();

  factory MessageTechnicalData.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessageTechnicalData()..mergeFromBuffer(data, registry);
  factory MessageTechnicalData.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessageTechnicalData()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MessageTechnicalData',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: MessageTechnicalData.$_createMessage)
    ..aOM<MessageReference>(1, _omitFieldNames ? '' : 'message',
        subBuilder: MessageReference.$_createMessage)
    ..aI(2, _omitFieldNames ? '' : 'attributes', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'attributes2',
        fieldType: $pb.PbFieldType.OU3)
    ..pPM<MessageTechnicalSubfield>(4, _omitFieldNames ? '' : 'subfields',
        subBuilder: MessageTechnicalSubfield.$_createMessage)
    ..aE<TechnicalEncodingStatus>(5, _omitFieldNames ? '' : 'encodingStatus',
        enumValues: TechnicalEncodingStatus.values)
    ..aOS(6, _omitFieldNames ? '' : 'effectiveEncoding')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessageTechnicalData clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessageTechnicalData copyWith(void Function(MessageTechnicalData) updates) =>
      super.copyWith((message) => updates(message as MessageTechnicalData))
          as MessageTechnicalData;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use MessageTechnicalData() / MessageTechnicalData.new instead')
  static MessageTechnicalData create() => MessageTechnicalData._();
  static $pb.GeneratedMessage $_createMessage() => MessageTechnicalData._();
  @$core.override
  MessageTechnicalData createEmptyInstance() => MessageTechnicalData._();
  @$core.pragma('dart2js:noInline')
  static MessageTechnicalData getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MessageTechnicalData>(
          MessageTechnicalData.$_createMessage);
  static MessageTechnicalData? _defaultInstance;

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
  $core.int get attributes => $_getIZ(1);
  @$pb.TagNumber(2)
  set attributes($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAttributes() => $_has(1);
  @$pb.TagNumber(2)
  void clearAttributes() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get attributes2 => $_getIZ(2);
  @$pb.TagNumber(3)
  set attributes2($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAttributes2() => $_has(2);
  @$pb.TagNumber(3)
  void clearAttributes2() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<MessageTechnicalSubfield> get subfields => $_getList(3);

  @$pb.TagNumber(5)
  TechnicalEncodingStatus get encodingStatus => $_getN(4);
  @$pb.TagNumber(5)
  set encodingStatus(TechnicalEncodingStatus value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasEncodingStatus() => $_has(4);
  @$pb.TagNumber(5)
  void clearEncodingStatus() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get effectiveEncoding => $_getSZ(5);
  @$pb.TagNumber(6)
  set effectiveEncoding($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEffectiveEncoding() => $_has(5);
  @$pb.TagNumber(6)
  void clearEffectiveEncoding() => $_clearField(6);
}

class PersonalMessageFilter extends $pb.GeneratedMessage {
  factory PersonalMessageFilter({
    $core.String? ruleId,
    $core.bool? enabled,
    PersonalMessageFilterScope? scope,
    $core.String? conferenceId,
    $core.String? authorContains,
    $core.String? addressEquals,
    $core.String? subjectContains,
  }) {
    final result = PersonalMessageFilter._();
    if (ruleId != null) result.ruleId = ruleId;
    if (enabled != null) result.enabled = enabled;
    if (scope != null) result.scope = scope;
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (authorContains != null) result.authorContains = authorContains;
    if (addressEquals != null) result.addressEquals = addressEquals;
    if (subjectContains != null) result.subjectContains = subjectContains;
    return result;
  }

  PersonalMessageFilter._();

  factory PersonalMessageFilter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PersonalMessageFilter()..mergeFromBuffer(data, registry);
  factory PersonalMessageFilter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PersonalMessageFilter()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PersonalMessageFilter',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: PersonalMessageFilter.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'ruleId')
    ..aOB(2, _omitFieldNames ? '' : 'enabled')
    ..aE<PersonalMessageFilterScope>(3, _omitFieldNames ? '' : 'scope',
        enumValues: PersonalMessageFilterScope.values)
    ..aOS(4, _omitFieldNames ? '' : 'conferenceId')
    ..aOS(5, _omitFieldNames ? '' : 'authorContains')
    ..aOS(6, _omitFieldNames ? '' : 'addressEquals')
    ..aOS(7, _omitFieldNames ? '' : 'subjectContains')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PersonalMessageFilter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PersonalMessageFilter copyWith(
          void Function(PersonalMessageFilter) updates) =>
      super.copyWith((message) => updates(message as PersonalMessageFilter))
          as PersonalMessageFilter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PersonalMessageFilter() / PersonalMessageFilter.new instead')
  static PersonalMessageFilter create() => PersonalMessageFilter._();
  static $pb.GeneratedMessage $_createMessage() => PersonalMessageFilter._();
  @$core.override
  PersonalMessageFilter createEmptyInstance() => PersonalMessageFilter._();
  @$core.pragma('dart2js:noInline')
  static PersonalMessageFilter getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PersonalMessageFilter>(
          PersonalMessageFilter.$_createMessage);
  static PersonalMessageFilter? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get ruleId => $_getSZ(0);
  @$pb.TagNumber(1)
  set ruleId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRuleId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRuleId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get enabled => $_getBF(1);
  @$pb.TagNumber(2)
  set enabled($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEnabled() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnabled() => $_clearField(2);

  @$pb.TagNumber(3)
  PersonalMessageFilterScope get scope => $_getN(2);
  @$pb.TagNumber(3)
  set scope(PersonalMessageFilterScope value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasScope() => $_has(2);
  @$pb.TagNumber(3)
  void clearScope() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get conferenceId => $_getSZ(3);
  @$pb.TagNumber(4)
  set conferenceId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConferenceId() => $_has(3);
  @$pb.TagNumber(4)
  void clearConferenceId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get authorContains => $_getSZ(4);
  @$pb.TagNumber(5)
  set authorContains($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAuthorContains() => $_has(4);
  @$pb.TagNumber(5)
  void clearAuthorContains() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get addressEquals => $_getSZ(5);
  @$pb.TagNumber(6)
  set addressEquals($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAddressEquals() => $_has(5);
  @$pb.TagNumber(6)
  void clearAddressEquals() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get subjectContains => $_getSZ(6);
  @$pb.TagNumber(7)
  set subjectContains($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSubjectContains() => $_has(6);
  @$pb.TagNumber(7)
  void clearSubjectContains() => $_clearField(7);
}

class PersonalMessageFilterSet extends $pb.GeneratedMessage {
  factory PersonalMessageFilterSet({
    $fixnum.Int64? revision,
    $core.Iterable<PersonalMessageFilter>? rules,
  }) {
    final result = PersonalMessageFilterSet._();
    if (revision != null) result.revision = revision;
    if (rules != null) result.rules.addAll(rules);
    return result;
  }

  PersonalMessageFilterSet._();

  factory PersonalMessageFilterSet.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PersonalMessageFilterSet()..mergeFromBuffer(data, registry);
  factory PersonalMessageFilterSet.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PersonalMessageFilterSet()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PersonalMessageFilterSet',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: PersonalMessageFilterSet.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'revision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPM<PersonalMessageFilter>(2, _omitFieldNames ? '' : 'rules',
        subBuilder: PersonalMessageFilter.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PersonalMessageFilterSet clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PersonalMessageFilterSet copyWith(
          void Function(PersonalMessageFilterSet) updates) =>
      super.copyWith((message) => updates(message as PersonalMessageFilterSet))
          as PersonalMessageFilterSet;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PersonalMessageFilterSet() / PersonalMessageFilterSet.new instead')
  static PersonalMessageFilterSet create() => PersonalMessageFilterSet._();
  static $pb.GeneratedMessage $_createMessage() => PersonalMessageFilterSet._();
  @$core.override
  PersonalMessageFilterSet createEmptyInstance() =>
      PersonalMessageFilterSet._();
  @$core.pragma('dart2js:noInline')
  static PersonalMessageFilterSet getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PersonalMessageFilterSet>(
          PersonalMessageFilterSet.$_createMessage);
  static PersonalMessageFilterSet? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get revision => $_getI64(0);
  @$pb.TagNumber(1)
  set revision($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRevision() => $_has(0);
  @$pb.TagNumber(1)
  void clearRevision() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<PersonalMessageFilter> get rules => $_getList(1);
}

class ReplacePersonalMessageFiltersRequest extends $pb.GeneratedMessage {
  factory ReplacePersonalMessageFiltersRequest({
    $fixnum.Int64? expectedRevision,
    $core.String? operationId,
    $core.Iterable<PersonalMessageFilter>? rules,
  }) {
    final result = ReplacePersonalMessageFiltersRequest._();
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    if (operationId != null) result.operationId = operationId;
    if (rules != null) result.rules.addAll(rules);
    return result;
  }

  ReplacePersonalMessageFiltersRequest._();

  factory ReplacePersonalMessageFiltersRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReplacePersonalMessageFiltersRequest()..mergeFromBuffer(data, registry);
  factory ReplacePersonalMessageFiltersRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReplacePersonalMessageFiltersRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReplacePersonalMessageFiltersRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ReplacePersonalMessageFiltersRequest.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'expectedRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(2, _omitFieldNames ? '' : 'operationId')
    ..pPM<PersonalMessageFilter>(3, _omitFieldNames ? '' : 'rules',
        subBuilder: PersonalMessageFilter.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReplacePersonalMessageFiltersRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReplacePersonalMessageFiltersRequest copyWith(
          void Function(ReplacePersonalMessageFiltersRequest) updates) =>
      super.copyWith((message) =>
              updates(message as ReplacePersonalMessageFiltersRequest))
          as ReplacePersonalMessageFiltersRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReplacePersonalMessageFiltersRequest() / ReplacePersonalMessageFiltersRequest.new instead')
  static ReplacePersonalMessageFiltersRequest create() =>
      ReplacePersonalMessageFiltersRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      ReplacePersonalMessageFiltersRequest._();
  @$core.override
  ReplacePersonalMessageFiltersRequest createEmptyInstance() =>
      ReplacePersonalMessageFiltersRequest._();
  @$core.pragma('dart2js:noInline')
  static ReplacePersonalMessageFiltersRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
              ReplacePersonalMessageFiltersRequest>(
          ReplacePersonalMessageFiltersRequest.$_createMessage);
  static ReplacePersonalMessageFiltersRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get expectedRevision => $_getI64(0);
  @$pb.TagNumber(1)
  set expectedRevision($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasExpectedRevision() => $_has(0);
  @$pb.TagNumber(1)
  void clearExpectedRevision() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get operationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set operationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOperationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<PersonalMessageFilter> get rules => $_getList(2);
}

class ReplacePersonalMessageFiltersResponse extends $pb.GeneratedMessage {
  factory ReplacePersonalMessageFiltersResponse({
    $fixnum.Int64? revision,
  }) {
    final result = ReplacePersonalMessageFiltersResponse._();
    if (revision != null) result.revision = revision;
    return result;
  }

  ReplacePersonalMessageFiltersResponse._();

  factory ReplacePersonalMessageFiltersResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReplacePersonalMessageFiltersResponse()..mergeFromBuffer(data, registry);
  factory ReplacePersonalMessageFiltersResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReplacePersonalMessageFiltersResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReplacePersonalMessageFiltersResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance:
          ReplacePersonalMessageFiltersResponse.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'revision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReplacePersonalMessageFiltersResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReplacePersonalMessageFiltersResponse copyWith(
          void Function(ReplacePersonalMessageFiltersResponse) updates) =>
      super.copyWith((message) =>
              updates(message as ReplacePersonalMessageFiltersResponse))
          as ReplacePersonalMessageFiltersResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReplacePersonalMessageFiltersResponse() / ReplacePersonalMessageFiltersResponse.new instead')
  static ReplacePersonalMessageFiltersResponse create() =>
      ReplacePersonalMessageFiltersResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      ReplacePersonalMessageFiltersResponse._();
  @$core.override
  ReplacePersonalMessageFiltersResponse createEmptyInstance() =>
      ReplacePersonalMessageFiltersResponse._();
  @$core.pragma('dart2js:noInline')
  static ReplacePersonalMessageFiltersResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
              ReplacePersonalMessageFiltersResponse>(
          ReplacePersonalMessageFiltersResponse.$_createMessage);
  static ReplacePersonalMessageFiltersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get revision => $_getI64(0);
  @$pb.TagNumber(1)
  set revision($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRevision() => $_has(0);
  @$pb.TagNumber(1)
  void clearRevision() => $_clearField(1);
}

class PersonalMessageCollapse extends $pb.GeneratedMessage {
  factory PersonalMessageCollapse({
    $fixnum.Int64? rulesRevision,
    $core.Iterable<$core.String>? matchedRuleIds,
  }) {
    final result = PersonalMessageCollapse._();
    if (rulesRevision != null) result.rulesRevision = rulesRevision;
    if (matchedRuleIds != null) result.matchedRuleIds.addAll(matchedRuleIds);
    return result;
  }

  PersonalMessageCollapse._();

  factory PersonalMessageCollapse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PersonalMessageCollapse()..mergeFromBuffer(data, registry);
  factory PersonalMessageCollapse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PersonalMessageCollapse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PersonalMessageCollapse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: PersonalMessageCollapse.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'rulesRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPS(2, _omitFieldNames ? '' : 'matchedRuleIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PersonalMessageCollapse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PersonalMessageCollapse copyWith(
          void Function(PersonalMessageCollapse) updates) =>
      super.copyWith((message) => updates(message as PersonalMessageCollapse))
          as PersonalMessageCollapse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PersonalMessageCollapse() / PersonalMessageCollapse.new instead')
  static PersonalMessageCollapse create() => PersonalMessageCollapse._();
  static $pb.GeneratedMessage $_createMessage() => PersonalMessageCollapse._();
  @$core.override
  PersonalMessageCollapse createEmptyInstance() => PersonalMessageCollapse._();
  @$core.pragma('dart2js:noInline')
  static PersonalMessageCollapse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PersonalMessageCollapse>(
          PersonalMessageCollapse.$_createMessage);
  static PersonalMessageCollapse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get rulesRevision => $_getI64(0);
  @$pb.TagNumber(1)
  set rulesRevision($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRulesRevision() => $_has(0);
  @$pb.TagNumber(1)
  void clearRulesRevision() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get matchedRuleIds => $_getList(1);
}

class GetMessagePresentationRequest extends $pb.GeneratedMessage {
  factory GetMessagePresentationRequest({
    MessageReference? message,
    $core.bool? reveal,
    $core.String? searchQuery,
    MessageSearchScope? searchScope,
  }) {
    final result = GetMessagePresentationRequest._();
    if (message != null) result.message = message;
    if (reveal != null) result.reveal = reveal;
    if (searchQuery != null) result.searchQuery = searchQuery;
    if (searchScope != null) result.searchScope = searchScope;
    return result;
  }

  GetMessagePresentationRequest._();

  factory GetMessagePresentationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetMessagePresentationRequest()..mergeFromBuffer(data, registry);
  factory GetMessagePresentationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetMessagePresentationRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetMessagePresentationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: GetMessagePresentationRequest.$_createMessage)
    ..aOM<MessageReference>(1, _omitFieldNames ? '' : 'message',
        subBuilder: MessageReference.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'reveal')
    ..aOS(3, _omitFieldNames ? '' : 'searchQuery')
    ..aE<MessageSearchScope>(4, _omitFieldNames ? '' : 'searchScope',
        enumValues: MessageSearchScope.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMessagePresentationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetMessagePresentationRequest copyWith(
          void Function(GetMessagePresentationRequest) updates) =>
      super.copyWith(
              (message) => updates(message as GetMessagePresentationRequest))
          as GetMessagePresentationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetMessagePresentationRequest() / GetMessagePresentationRequest.new instead')
  static GetMessagePresentationRequest create() =>
      GetMessagePresentationRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      GetMessagePresentationRequest._();
  @$core.override
  GetMessagePresentationRequest createEmptyInstance() =>
      GetMessagePresentationRequest._();
  @$core.pragma('dart2js:noInline')
  static GetMessagePresentationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetMessagePresentationRequest>(
          GetMessagePresentationRequest.$_createMessage);
  static GetMessagePresentationRequest? _defaultInstance;

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
  $core.bool get reveal => $_getBF(1);
  @$pb.TagNumber(2)
  set reveal($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReveal() => $_has(1);
  @$pb.TagNumber(2)
  void clearReveal() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get searchQuery => $_getSZ(2);
  @$pb.TagNumber(3)
  set searchQuery($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSearchQuery() => $_has(2);
  @$pb.TagNumber(3)
  void clearSearchQuery() => $_clearField(3);

  @$pb.TagNumber(4)
  MessageSearchScope get searchScope => $_getN(3);
  @$pb.TagNumber(4)
  set searchScope(MessageSearchScope value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSearchScope() => $_has(3);
  @$pb.TagNumber(4)
  void clearSearchScope() => $_clearField(4);
}

class CollapsedMessageHeaders extends $pb.GeneratedMessage {
  factory CollapsedMessageHeaders({
    MessageReference? message,
    $core.String? fromName,
    $core.String? fromAddress,
    $core.String? subject,
    $2.Timestamp? date,
    $core.bool? isRead,
    $core.String? threadId,
    $core.String? inReplyTo,
  }) {
    final result = CollapsedMessageHeaders._();
    if (message != null) result.message = message;
    if (fromName != null) result.fromName = fromName;
    if (fromAddress != null) result.fromAddress = fromAddress;
    if (subject != null) result.subject = subject;
    if (date != null) result.date = date;
    if (isRead != null) result.isRead = isRead;
    if (threadId != null) result.threadId = threadId;
    if (inReplyTo != null) result.inReplyTo = inReplyTo;
    return result;
  }

  CollapsedMessageHeaders._();

  factory CollapsedMessageHeaders.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CollapsedMessageHeaders()..mergeFromBuffer(data, registry);
  factory CollapsedMessageHeaders.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CollapsedMessageHeaders()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CollapsedMessageHeaders',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: CollapsedMessageHeaders.$_createMessage)
    ..aOM<MessageReference>(1, _omitFieldNames ? '' : 'message',
        subBuilder: MessageReference.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'fromName')
    ..aOS(3, _omitFieldNames ? '' : 'fromAddress')
    ..aOS(4, _omitFieldNames ? '' : 'subject')
    ..aOM<$2.Timestamp>(5, _omitFieldNames ? '' : 'date',
        subBuilder: $2.Timestamp.$_createMessage)
    ..aOB(6, _omitFieldNames ? '' : 'isRead')
    ..aOS(7, _omitFieldNames ? '' : 'threadId')
    ..aOS(8, _omitFieldNames ? '' : 'inReplyTo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CollapsedMessageHeaders clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CollapsedMessageHeaders copyWith(
          void Function(CollapsedMessageHeaders) updates) =>
      super.copyWith((message) => updates(message as CollapsedMessageHeaders))
          as CollapsedMessageHeaders;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CollapsedMessageHeaders() / CollapsedMessageHeaders.new instead')
  static CollapsedMessageHeaders create() => CollapsedMessageHeaders._();
  static $pb.GeneratedMessage $_createMessage() => CollapsedMessageHeaders._();
  @$core.override
  CollapsedMessageHeaders createEmptyInstance() => CollapsedMessageHeaders._();
  @$core.pragma('dart2js:noInline')
  static CollapsedMessageHeaders getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CollapsedMessageHeaders>(
          CollapsedMessageHeaders.$_createMessage);
  static CollapsedMessageHeaders? _defaultInstance;

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
  $core.String get fromName => $_getSZ(1);
  @$pb.TagNumber(2)
  set fromName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFromName() => $_has(1);
  @$pb.TagNumber(2)
  void clearFromName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get fromAddress => $_getSZ(2);
  @$pb.TagNumber(3)
  set fromAddress($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFromAddress() => $_has(2);
  @$pb.TagNumber(3)
  void clearFromAddress() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get subject => $_getSZ(3);
  @$pb.TagNumber(4)
  set subject($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSubject() => $_has(3);
  @$pb.TagNumber(4)
  void clearSubject() => $_clearField(4);

  @$pb.TagNumber(5)
  $2.Timestamp get date => $_getN(4);
  @$pb.TagNumber(5)
  set date($2.Timestamp value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasDate() => $_has(4);
  @$pb.TagNumber(5)
  void clearDate() => $_clearField(5);
  @$pb.TagNumber(5)
  $2.Timestamp ensureDate() => $_ensure(4);

  @$pb.TagNumber(6)
  $core.bool get isRead => $_getBF(5);
  @$pb.TagNumber(6)
  set isRead($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasIsRead() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsRead() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get threadId => $_getSZ(6);
  @$pb.TagNumber(7)
  set threadId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasThreadId() => $_has(6);
  @$pb.TagNumber(7)
  void clearThreadId() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get inReplyTo => $_getSZ(7);
  @$pb.TagNumber(8)
  set inReplyTo($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasInReplyTo() => $_has(7);
  @$pb.TagNumber(8)
  void clearInReplyTo() => $_clearField(8);
}

enum MessagePresentation_Content { visible, collapsed, notSet }

class MessagePresentation extends $pb.GeneratedMessage {
  factory MessagePresentation({
    $fixnum.Int64? rulesRevision,
    $core.Iterable<$core.String>? matchedRuleIds,
    Message? visible,
    CollapsedMessageHeaders? collapsed,
    $core.Iterable<SearchMatch>? matches,
  }) {
    final result = MessagePresentation._();
    if (rulesRevision != null) result.rulesRevision = rulesRevision;
    if (matchedRuleIds != null) result.matchedRuleIds.addAll(matchedRuleIds);
    if (visible != null) result.visible = visible;
    if (collapsed != null) result.collapsed = collapsed;
    if (matches != null) result.matches.addAll(matches);
    return result;
  }

  MessagePresentation._();

  factory MessagePresentation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessagePresentation()..mergeFromBuffer(data, registry);
  factory MessagePresentation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessagePresentation()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, MessagePresentation_Content>
      _MessagePresentation_ContentByTag = {
    3: MessagePresentation_Content.visible,
    4: MessagePresentation_Content.collapsed,
    0: MessagePresentation_Content.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MessagePresentation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: MessagePresentation.$_createMessage)
    ..oo(0, [3, 4])
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'rulesRevision', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPS(2, _omitFieldNames ? '' : 'matchedRuleIds')
    ..aOM<Message>(3, _omitFieldNames ? '' : 'visible',
        subBuilder: Message.$_createMessage)
    ..aOM<CollapsedMessageHeaders>(4, _omitFieldNames ? '' : 'collapsed',
        subBuilder: CollapsedMessageHeaders.$_createMessage)
    ..pPM<SearchMatch>(5, _omitFieldNames ? '' : 'matches',
        subBuilder: SearchMatch.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessagePresentation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessagePresentation copyWith(void Function(MessagePresentation) updates) =>
      super.copyWith((message) => updates(message as MessagePresentation))
          as MessagePresentation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use MessagePresentation() / MessagePresentation.new instead')
  static MessagePresentation create() => MessagePresentation._();
  static $pb.GeneratedMessage $_createMessage() => MessagePresentation._();
  @$core.override
  MessagePresentation createEmptyInstance() => MessagePresentation._();
  @$core.pragma('dart2js:noInline')
  static MessagePresentation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MessagePresentation>(
          MessagePresentation.$_createMessage);
  static MessagePresentation? _defaultInstance;

  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  MessagePresentation_Content whichContent() =>
      _MessagePresentation_ContentByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearContent() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $fixnum.Int64 get rulesRevision => $_getI64(0);
  @$pb.TagNumber(1)
  set rulesRevision($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRulesRevision() => $_has(0);
  @$pb.TagNumber(1)
  void clearRulesRevision() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get matchedRuleIds => $_getList(1);

  @$pb.TagNumber(3)
  Message get visible => $_getN(2);
  @$pb.TagNumber(3)
  set visible(Message value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasVisible() => $_has(2);
  @$pb.TagNumber(3)
  void clearVisible() => $_clearField(3);
  @$pb.TagNumber(3)
  Message ensureVisible() => $_ensure(2);

  @$pb.TagNumber(4)
  CollapsedMessageHeaders get collapsed => $_getN(3);
  @$pb.TagNumber(4)
  set collapsed(CollapsedMessageHeaders value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCollapsed() => $_has(3);
  @$pb.TagNumber(4)
  void clearCollapsed() => $_clearField(4);
  @$pb.TagNumber(4)
  CollapsedMessageHeaders ensureCollapsed() => $_ensure(3);

  @$pb.TagNumber(5)
  $pb.PbList<SearchMatch> get matches => $_getList(4);
}

/// Архивные RPC не изменяют прочитанность, историю или позицию чтения.
class SearchArchiveMessagesRequest extends $pb.GeneratedMessage {
  factory SearchArchiveMessagesRequest({
    $core.Iterable<$core.String>? conferenceIds,
    $core.String? query,
    MessageSearchScope? scope,
    $2.Timestamp? from,
    $2.Timestamp? to,
    MessageSort? sort,
    $core.int? limit,
    $core.String? cursor,
  }) {
    final result = SearchArchiveMessagesRequest._();
    if (conferenceIds != null) result.conferenceIds.addAll(conferenceIds);
    if (query != null) result.query = query;
    if (scope != null) result.scope = scope;
    if (from != null) result.from = from;
    if (to != null) result.to = to;
    if (sort != null) result.sort = sort;
    if (limit != null) result.limit = limit;
    if (cursor != null) result.cursor = cursor;
    return result;
  }

  SearchArchiveMessagesRequest._();

  factory SearchArchiveMessagesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchArchiveMessagesRequest()..mergeFromBuffer(data, registry);
  factory SearchArchiveMessagesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchArchiveMessagesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchArchiveMessagesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: SearchArchiveMessagesRequest.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'conferenceIds')
    ..aOS(2, _omitFieldNames ? '' : 'query')
    ..aE<MessageSearchScope>(3, _omitFieldNames ? '' : 'scope',
        enumValues: MessageSearchScope.values)
    ..aOM<$2.Timestamp>(4, _omitFieldNames ? '' : 'from',
        subBuilder: $2.Timestamp.$_createMessage)
    ..aOM<$2.Timestamp>(5, _omitFieldNames ? '' : 'to',
        subBuilder: $2.Timestamp.$_createMessage)
    ..aE<MessageSort>(6, _omitFieldNames ? '' : 'sort',
        enumValues: MessageSort.values)
    ..aI(7, _omitFieldNames ? '' : 'limit')
    ..aOS(8, _omitFieldNames ? '' : 'cursor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchArchiveMessagesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchArchiveMessagesRequest copyWith(
          void Function(SearchArchiveMessagesRequest) updates) =>
      super.copyWith(
              (message) => updates(message as SearchArchiveMessagesRequest))
          as SearchArchiveMessagesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SearchArchiveMessagesRequest() / SearchArchiveMessagesRequest.new instead')
  static SearchArchiveMessagesRequest create() =>
      SearchArchiveMessagesRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      SearchArchiveMessagesRequest._();
  @$core.override
  SearchArchiveMessagesRequest createEmptyInstance() =>
      SearchArchiveMessagesRequest._();
  @$core.pragma('dart2js:noInline')
  static SearchArchiveMessagesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SearchArchiveMessagesRequest>(
          SearchArchiveMessagesRequest.$_createMessage);
  static SearchArchiveMessagesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get conferenceIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get query => $_getSZ(1);
  @$pb.TagNumber(2)
  set query($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasQuery() => $_has(1);
  @$pb.TagNumber(2)
  void clearQuery() => $_clearField(2);

  @$pb.TagNumber(3)
  MessageSearchScope get scope => $_getN(2);
  @$pb.TagNumber(3)
  set scope(MessageSearchScope value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasScope() => $_has(2);
  @$pb.TagNumber(3)
  void clearScope() => $_clearField(3);

  @$pb.TagNumber(4)
  $2.Timestamp get from => $_getN(3);
  @$pb.TagNumber(4)
  set from($2.Timestamp value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasFrom() => $_has(3);
  @$pb.TagNumber(4)
  void clearFrom() => $_clearField(4);
  @$pb.TagNumber(4)
  $2.Timestamp ensureFrom() => $_ensure(3);

  @$pb.TagNumber(5)
  $2.Timestamp get to => $_getN(4);
  @$pb.TagNumber(5)
  set to($2.Timestamp value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasTo() => $_has(4);
  @$pb.TagNumber(5)
  void clearTo() => $_clearField(5);
  @$pb.TagNumber(5)
  $2.Timestamp ensureTo() => $_ensure(4);

  @$pb.TagNumber(6)
  MessageSort get sort => $_getN(5);
  @$pb.TagNumber(6)
  set sort(MessageSort value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasSort() => $_has(5);
  @$pb.TagNumber(6)
  void clearSort() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get limit => $_getIZ(6);
  @$pb.TagNumber(7)
  set limit($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLimit() => $_has(6);
  @$pb.TagNumber(7)
  void clearLimit() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get cursor => $_getSZ(7);
  @$pb.TagNumber(8)
  set cursor($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCursor() => $_has(7);
  @$pb.TagNumber(8)
  void clearCursor() => $_clearField(8);
}

class ArchiveSearchResult extends $pb.GeneratedMessage {
  factory ArchiveSearchResult({
    Message? message,
    $core.String? snippet,
    $core.Iterable<SearchMatch>? matches,
  }) {
    final result = ArchiveSearchResult._();
    if (message != null) result.message = message;
    if (snippet != null) result.snippet = snippet;
    if (matches != null) result.matches.addAll(matches);
    return result;
  }

  ArchiveSearchResult._();

  factory ArchiveSearchResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ArchiveSearchResult()..mergeFromBuffer(data, registry);
  factory ArchiveSearchResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ArchiveSearchResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ArchiveSearchResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ArchiveSearchResult.$_createMessage)
    ..aOM<Message>(1, _omitFieldNames ? '' : 'message',
        subBuilder: Message.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'snippet')
    ..pPM<SearchMatch>(3, _omitFieldNames ? '' : 'matches',
        subBuilder: SearchMatch.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArchiveSearchResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArchiveSearchResult copyWith(void Function(ArchiveSearchResult) updates) =>
      super.copyWith((message) => updates(message as ArchiveSearchResult))
          as ArchiveSearchResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ArchiveSearchResult() / ArchiveSearchResult.new instead')
  static ArchiveSearchResult create() => ArchiveSearchResult._();
  static $pb.GeneratedMessage $_createMessage() => ArchiveSearchResult._();
  @$core.override
  ArchiveSearchResult createEmptyInstance() => ArchiveSearchResult._();
  @$core.pragma('dart2js:noInline')
  static ArchiveSearchResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ArchiveSearchResult>(
          ArchiveSearchResult.$_createMessage);
  static ArchiveSearchResult? _defaultInstance;

  @$pb.TagNumber(1)
  Message get message => $_getN(0);
  @$pb.TagNumber(1)
  set message(Message value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);
  @$pb.TagNumber(1)
  Message ensureMessage() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get snippet => $_getSZ(1);
  @$pb.TagNumber(2)
  set snippet($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSnippet() => $_has(1);
  @$pb.TagNumber(2)
  void clearSnippet() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<SearchMatch> get matches => $_getList(2);
}

class SearchArchiveMessagesResponse extends $pb.GeneratedMessage {
  factory SearchArchiveMessagesResponse({
    $core.Iterable<ArchiveSearchResult>? results,
    $core.bool? complete,
    $core.String? incompleteReason,
    $core.String? nextCursor,
  }) {
    final result = SearchArchiveMessagesResponse._();
    if (results != null) result.results.addAll(results);
    if (complete != null) result.complete = complete;
    if (incompleteReason != null) result.incompleteReason = incompleteReason;
    if (nextCursor != null) result.nextCursor = nextCursor;
    return result;
  }

  SearchArchiveMessagesResponse._();

  factory SearchArchiveMessagesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchArchiveMessagesResponse()..mergeFromBuffer(data, registry);
  factory SearchArchiveMessagesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchArchiveMessagesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchArchiveMessagesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: SearchArchiveMessagesResponse.$_createMessage)
    ..pPM<ArchiveSearchResult>(1, _omitFieldNames ? '' : 'results',
        subBuilder: ArchiveSearchResult.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'complete')
    ..aOS(3, _omitFieldNames ? '' : 'incompleteReason')
    ..aOS(4, _omitFieldNames ? '' : 'nextCursor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchArchiveMessagesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchArchiveMessagesResponse copyWith(
          void Function(SearchArchiveMessagesResponse) updates) =>
      super.copyWith(
              (message) => updates(message as SearchArchiveMessagesResponse))
          as SearchArchiveMessagesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SearchArchiveMessagesResponse() / SearchArchiveMessagesResponse.new instead')
  static SearchArchiveMessagesResponse create() =>
      SearchArchiveMessagesResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      SearchArchiveMessagesResponse._();
  @$core.override
  SearchArchiveMessagesResponse createEmptyInstance() =>
      SearchArchiveMessagesResponse._();
  @$core.pragma('dart2js:noInline')
  static SearchArchiveMessagesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SearchArchiveMessagesResponse>(
          SearchArchiveMessagesResponse.$_createMessage);
  static SearchArchiveMessagesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ArchiveSearchResult> get results => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get complete => $_getBF(1);
  @$pb.TagNumber(2)
  set complete($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasComplete() => $_has(1);
  @$pb.TagNumber(2)
  void clearComplete() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get incompleteReason => $_getSZ(2);
  @$pb.TagNumber(3)
  set incompleteReason($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIncompleteReason() => $_has(2);
  @$pb.TagNumber(3)
  void clearIncompleteReason() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get nextCursor => $_getSZ(3);
  @$pb.TagNumber(4)
  set nextCursor($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNextCursor() => $_has(3);
  @$pb.TagNumber(4)
  void clearNextCursor() => $_clearField(4);
}

class ReadArchiveMessageRequest extends $pb.GeneratedMessage {
  factory ReadArchiveMessageRequest({
    MessageReference? message,
    $fixnum.Int64? bodyOffset,
    $core.int? bodyLimit,
    $core.bool? reveal,
  }) {
    final result = ReadArchiveMessageRequest._();
    if (message != null) result.message = message;
    if (bodyOffset != null) result.bodyOffset = bodyOffset;
    if (bodyLimit != null) result.bodyLimit = bodyLimit;
    if (reveal != null) result.reveal = reveal;
    return result;
  }

  ReadArchiveMessageRequest._();

  factory ReadArchiveMessageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadArchiveMessageRequest()..mergeFromBuffer(data, registry);
  factory ReadArchiveMessageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadArchiveMessageRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadArchiveMessageRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ReadArchiveMessageRequest.$_createMessage)
    ..aOM<MessageReference>(1, _omitFieldNames ? '' : 'message',
        subBuilder: MessageReference.$_createMessage)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'bodyOffset', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(3, _omitFieldNames ? '' : 'bodyLimit', fieldType: $pb.PbFieldType.OU3)
    ..aOB(4, _omitFieldNames ? '' : 'reveal')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadArchiveMessageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadArchiveMessageRequest copyWith(
          void Function(ReadArchiveMessageRequest) updates) =>
      super.copyWith((message) => updates(message as ReadArchiveMessageRequest))
          as ReadArchiveMessageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReadArchiveMessageRequest() / ReadArchiveMessageRequest.new instead')
  static ReadArchiveMessageRequest create() => ReadArchiveMessageRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      ReadArchiveMessageRequest._();
  @$core.override
  ReadArchiveMessageRequest createEmptyInstance() =>
      ReadArchiveMessageRequest._();
  @$core.pragma('dart2js:noInline')
  static ReadArchiveMessageRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReadArchiveMessageRequest>(
          ReadArchiveMessageRequest.$_createMessage);
  static ReadArchiveMessageRequest? _defaultInstance;

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
  $fixnum.Int64 get bodyOffset => $_getI64(1);
  @$pb.TagNumber(2)
  set bodyOffset($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBodyOffset() => $_has(1);
  @$pb.TagNumber(2)
  void clearBodyOffset() => $_clearField(2);

  /// 1–65536 UTF-8 bytes; граница блока не разрывает символ.
  @$pb.TagNumber(3)
  $core.int get bodyLimit => $_getIZ(2);
  @$pb.TagNumber(3)
  set bodyLimit($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBodyLimit() => $_has(2);
  @$pb.TagNumber(3)
  void clearBodyLimit() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get reveal => $_getBF(3);
  @$pb.TagNumber(4)
  set reveal($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasReveal() => $_has(3);
  @$pb.TagNumber(4)
  void clearReveal() => $_clearField(4);
}

class ReadArchiveMessageResponse extends $pb.GeneratedMessage {
  factory ReadArchiveMessageResponse({
    Message? message,
    $fixnum.Int64? bodyOffset,
    $fixnum.Int64? nextOffset,
    $core.bool? complete,
    $core.bool? collapsed,
  }) {
    final result = ReadArchiveMessageResponse._();
    if (message != null) result.message = message;
    if (bodyOffset != null) result.bodyOffset = bodyOffset;
    if (nextOffset != null) result.nextOffset = nextOffset;
    if (complete != null) result.complete = complete;
    if (collapsed != null) result.collapsed = collapsed;
    return result;
  }

  ReadArchiveMessageResponse._();

  factory ReadArchiveMessageResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadArchiveMessageResponse()..mergeFromBuffer(data, registry);
  factory ReadArchiveMessageResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadArchiveMessageResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadArchiveMessageResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: ReadArchiveMessageResponse.$_createMessage)
    ..aOM<Message>(1, _omitFieldNames ? '' : 'message',
        subBuilder: Message.$_createMessage)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'bodyOffset', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'nextOffset', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(4, _omitFieldNames ? '' : 'complete')
    ..aOB(5, _omitFieldNames ? '' : 'collapsed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadArchiveMessageResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadArchiveMessageResponse copyWith(
          void Function(ReadArchiveMessageResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ReadArchiveMessageResponse))
          as ReadArchiveMessageResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReadArchiveMessageResponse() / ReadArchiveMessageResponse.new instead')
  static ReadArchiveMessageResponse create() => ReadArchiveMessageResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      ReadArchiveMessageResponse._();
  @$core.override
  ReadArchiveMessageResponse createEmptyInstance() =>
      ReadArchiveMessageResponse._();
  @$core.pragma('dart2js:noInline')
  static ReadArchiveMessageResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReadArchiveMessageResponse>(
          ReadArchiveMessageResponse.$_createMessage);
  static ReadArchiveMessageResponse? _defaultInstance;

  /// body содержит только запрошенный блок, остальные поля — заголовки.
  @$pb.TagNumber(1)
  Message get message => $_getN(0);
  @$pb.TagNumber(1)
  set message(Message value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => $_clearField(1);
  @$pb.TagNumber(1)
  Message ensureMessage() => $_ensure(0);

  @$pb.TagNumber(2)
  $fixnum.Int64 get bodyOffset => $_getI64(1);
  @$pb.TagNumber(2)
  set bodyOffset($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBodyOffset() => $_has(1);
  @$pb.TagNumber(2)
  void clearBodyOffset() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get nextOffset => $_getI64(2);
  @$pb.TagNumber(3)
  set nextOffset($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasNextOffset() => $_has(2);
  @$pb.TagNumber(3)
  void clearNextOffset() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get complete => $_getBF(3);
  @$pb.TagNumber(4)
  set complete($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasComplete() => $_has(3);
  @$pb.TagNumber(4)
  void clearComplete() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get collapsed => $_getBF(4);
  @$pb.TagNumber(5)
  set collapsed($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCollapsed() => $_has(4);
  @$pb.TagNumber(5)
  void clearCollapsed() => $_clearField(5);
}

class GetArchiveThreadRequest extends $pb.GeneratedMessage {
  factory GetArchiveThreadRequest({
    MessageReference? message,
    PageRequest? page,
  }) {
    final result = GetArchiveThreadRequest._();
    if (message != null) result.message = message;
    if (page != null) result.page = page;
    return result;
  }

  GetArchiveThreadRequest._();

  factory GetArchiveThreadRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetArchiveThreadRequest()..mergeFromBuffer(data, registry);
  factory GetArchiveThreadRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetArchiveThreadRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetArchiveThreadRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: GetArchiveThreadRequest.$_createMessage)
    ..aOM<MessageReference>(1, _omitFieldNames ? '' : 'message',
        subBuilder: MessageReference.$_createMessage)
    ..aOM<PageRequest>(2, _omitFieldNames ? '' : 'page',
        subBuilder: PageRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetArchiveThreadRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetArchiveThreadRequest copyWith(
          void Function(GetArchiveThreadRequest) updates) =>
      super.copyWith((message) => updates(message as GetArchiveThreadRequest))
          as GetArchiveThreadRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GetArchiveThreadRequest() / GetArchiveThreadRequest.new instead')
  static GetArchiveThreadRequest create() => GetArchiveThreadRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetArchiveThreadRequest._();
  @$core.override
  GetArchiveThreadRequest createEmptyInstance() => GetArchiveThreadRequest._();
  @$core.pragma('dart2js:noInline')
  static GetArchiveThreadRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GetArchiveThreadRequest>(
          GetArchiveThreadRequest.$_createMessage);
  static GetArchiveThreadRequest? _defaultInstance;

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
  PageRequest get page => $_getN(1);
  @$pb.TagNumber(2)
  set page(PageRequest value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPage() => $_has(1);
  @$pb.TagNumber(2)
  void clearPage() => $_clearField(2);
  @$pb.TagNumber(2)
  PageRequest ensurePage() => $_ensure(1);
}

class MessagePreview extends $pb.GeneratedMessage {
  factory MessagePreview({
    $core.String? conferenceId,
    $core.String? fromName,
    $core.String? fromAddress,
    $core.String? toName,
    $core.String? toAddress,
    $core.String? subject,
    $core.String? body,
    $core.String? effectiveEncoding,
    $fixnum.Int64? wireBodyBytes,
    $core.String? previewDigest,
    AreaKind? kind,
    $core.bool? publicMessage,
    $core.String? inReplyTo,
  }) {
    final result = MessagePreview._();
    if (conferenceId != null) result.conferenceId = conferenceId;
    if (fromName != null) result.fromName = fromName;
    if (fromAddress != null) result.fromAddress = fromAddress;
    if (toName != null) result.toName = toName;
    if (toAddress != null) result.toAddress = toAddress;
    if (subject != null) result.subject = subject;
    if (body != null) result.body = body;
    if (effectiveEncoding != null) result.effectiveEncoding = effectiveEncoding;
    if (wireBodyBytes != null) result.wireBodyBytes = wireBodyBytes;
    if (previewDigest != null) result.previewDigest = previewDigest;
    if (kind != null) result.kind = kind;
    if (publicMessage != null) result.publicMessage = publicMessage;
    if (inReplyTo != null) result.inReplyTo = inReplyTo;
    return result;
  }

  MessagePreview._();

  factory MessagePreview.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessagePreview()..mergeFromBuffer(data, registry);
  factory MessagePreview.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MessagePreview()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MessagePreview',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'ffido.v1'),
      createEmptyInstance: MessagePreview.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'conferenceId')
    ..aOS(2, _omitFieldNames ? '' : 'fromName')
    ..aOS(3, _omitFieldNames ? '' : 'fromAddress')
    ..aOS(4, _omitFieldNames ? '' : 'toName')
    ..aOS(5, _omitFieldNames ? '' : 'toAddress')
    ..aOS(6, _omitFieldNames ? '' : 'subject')
    ..aOS(7, _omitFieldNames ? '' : 'body')
    ..aOS(8, _omitFieldNames ? '' : 'effectiveEncoding')
    ..a<$fixnum.Int64>(
        9, _omitFieldNames ? '' : 'wireBodyBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(10, _omitFieldNames ? '' : 'previewDigest')
    ..aE<AreaKind>(11, _omitFieldNames ? '' : 'kind',
        enumValues: AreaKind.values)
    ..aOB(12, _omitFieldNames ? '' : 'publicMessage')
    ..aOS(13, _omitFieldNames ? '' : 'inReplyTo')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessagePreview clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MessagePreview copyWith(void Function(MessagePreview) updates) =>
      super.copyWith((message) => updates(message as MessagePreview))
          as MessagePreview;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MessagePreview() / MessagePreview.new instead')
  static MessagePreview create() => MessagePreview._();
  static $pb.GeneratedMessage $_createMessage() => MessagePreview._();
  @$core.override
  MessagePreview createEmptyInstance() => MessagePreview._();
  @$core.pragma('dart2js:noInline')
  static MessagePreview getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MessagePreview>(
          MessagePreview.$_createMessage);
  static MessagePreview? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conferenceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conferenceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConferenceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConferenceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get fromName => $_getSZ(1);
  @$pb.TagNumber(2)
  set fromName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFromName() => $_has(1);
  @$pb.TagNumber(2)
  void clearFromName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get fromAddress => $_getSZ(2);
  @$pb.TagNumber(3)
  set fromAddress($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFromAddress() => $_has(2);
  @$pb.TagNumber(3)
  void clearFromAddress() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get toName => $_getSZ(3);
  @$pb.TagNumber(4)
  set toName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasToName() => $_has(3);
  @$pb.TagNumber(4)
  void clearToName() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get toAddress => $_getSZ(4);
  @$pb.TagNumber(5)
  set toAddress($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasToAddress() => $_has(4);
  @$pb.TagNumber(5)
  void clearToAddress() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get subject => $_getSZ(5);
  @$pb.TagNumber(6)
  set subject($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSubject() => $_has(5);
  @$pb.TagNumber(6)
  void clearSubject() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get body => $_getSZ(6);
  @$pb.TagNumber(7)
  set body($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasBody() => $_has(6);
  @$pb.TagNumber(7)
  void clearBody() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get effectiveEncoding => $_getSZ(7);
  @$pb.TagNumber(8)
  set effectiveEncoding($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasEffectiveEncoding() => $_has(7);
  @$pb.TagNumber(8)
  void clearEffectiveEncoding() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get wireBodyBytes => $_getI64(8);
  @$pb.TagNumber(9)
  set wireBodyBytes($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasWireBodyBytes() => $_has(8);
  @$pb.TagNumber(9)
  void clearWireBodyBytes() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get previewDigest => $_getSZ(9);
  @$pb.TagNumber(10)
  set previewDigest($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasPreviewDigest() => $_has(9);
  @$pb.TagNumber(10)
  void clearPreviewDigest() => $_clearField(10);

  @$pb.TagNumber(11)
  AreaKind get kind => $_getN(10);
  @$pb.TagNumber(11)
  set kind(AreaKind value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasKind() => $_has(10);
  @$pb.TagNumber(11)
  void clearKind() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.bool get publicMessage => $_getBF(11);
  @$pb.TagNumber(12)
  set publicMessage($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(12)
  $core.bool hasPublicMessage() => $_has(11);
  @$pb.TagNumber(12)
  void clearPublicMessage() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get inReplyTo => $_getSZ(12);
  @$pb.TagNumber(13)
  set inReplyTo($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasInReplyTo() => $_has(12);
  @$pb.TagNumber(13)
  void clearInReplyTo() => $_clearField(13);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
