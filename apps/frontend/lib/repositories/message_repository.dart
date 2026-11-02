import '../models/message_technical_data.dart';
import 'personal_message_filters_repository.dart';
import '../api/message_footer_snapshot.dart';

import 'dart:math';
import 'dart:convert';

import '../models/message_search.dart';

import 'uue_repository.dart';

import 'package:fixnum/fixnum.dart';
import 'package:fido/api/api_transport.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/model_mapping.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/api/api_constants.dart';
import 'package:fido/models/message.dart';
import 'package:fido/models/conference.dart';
import 'package:fido/models/api_response.dart';

class MessageRepository {
  final ApiTransport _apiClient;
  final PersonalMessageFiltersRepository filters;
  final UueRepository uue;
  final MessageFooterSnapshots _footers;
  MessageRepository(ApiTransport apiClient)
    : _apiClient = apiClient,
      filters = PersonalMessageFiltersRepository(apiClient),
      uue = UueRepository(apiClient),
      _footers = MessageFooterSnapshots(apiClient);
  int _positionEpoch = -1;
  final Map<String, int> _latestRevision = {};
  int get epoch {
    final current = _apiClient.epoch;
    if (_positionEpoch != current) {
      _latestRevision.clear();
      _positionEpoch = current;
    }
    return current;
  }

  Future<MessageTechnicalData> getTechnicalData(
    String conferenceId,
    String messageId, {
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    _check(captured, cancellation);
    final result = await _apiClient.getMessageTechnicalData(
      wire.MessageReference(conferenceId: conferenceId, messageId: messageId),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    final status = result.encodingStatus;
    if (result.message.conferenceId != conferenceId ||
        result.message.messageId != messageId ||
        !(status ==
                    wire
                        .TechnicalEncodingStatus
                        .TECHNICAL_ENCODING_STATUS_KNOWN &&
                result.effectiveEncoding.isNotEmpty ||
            status ==
                    wire
                        .TechnicalEncodingStatus
                        .TECHNICAL_ENCODING_STATUS_UNDETERMINED &&
                result.effectiveEncoding.isEmpty) ||
        result.subfields.any(
          (f) => !const {4, 5, 2000}.contains(f.lowId) || f.highId > 65535,
        ) ||
        result.subfields.fold(0, (sum, f) => sum + 8 + f.value.length) >
            65536) {
      throw const ServerException(message: 'Некорректные технические данные');
    }
    return MessageTechnicalData.fromWire(result);
  }

  Future<Conference> getMailboxState(
    String conferenceId, {
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    final response = await _apiClient.getConference(
      wire.GetConferenceRequest(conferenceId: conferenceId),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    final result = mapConference(response);
    if (result.personalMailbox) {
      final known = _latestRevision[conferenceId] ?? 0;
      if (result.positionRevision < known) throw const CancelledException();
      _latestRevision[conferenceId] = result.positionRevision;
    }
    return result;
  }

  Future<UserProfile> getAuthorProfile({RpcCancellation? cancellation}) async {
    final captured = epoch;
    final profile = await _apiClient.getProfile(cancellation: cancellation);
    _check(captured, cancellation);
    return mapProfile(profile);
  }

  Stream<int> get sessionChanges => _apiClient.sessionChanges;
  static String newOperationId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  void _check(int captured, RpcCancellation? cancellation) {
    if (captured != epoch || cancellation?.isCancelled == true) {
      throw const CancelledException();
    }
  }

  /// Получение списка сообщений конференции
  ///
  /// [conferenceId] — ID конференции
  /// [offset] — смещение для пагинации
  /// [limit] — количество записей
  /// [sort] — сортировка (newest/oldest)
  Future<MessageListResponse> getConferenceMessages({
    required String conferenceId,
    int offset = ApiConstants.defaultOffset,
    int limit = ApiConstants.defaultLimit,
    String sort = ApiConstants.sortNewest,
    String? anchorMessageId,
    String query = '',
    RpcCancellation? cancellation,
  }) async {
    if (sort != ApiConstants.sortNewest && sort != ApiConstants.sortOldest) {
      throw const ValidationException(message: 'Неизвестная сортировка');
    }
    final captured = epoch;
    final respect = await filters.ensure(cancellation: cancellation);
    _check(captured, cancellation);
    final response = await _apiClient.listMessages(
      wire.ListMessagesRequest(
        respectPersonalFilters: respect,
        conferenceId: conferenceId,
        anchorMessageId: anchorMessageId,
        query: query,
        page: wire.PageRequest(offset: Int64(offset), limit: limit),
        sort: sort == ApiConstants.sortOldest
            ? wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING
            : wire.MessageSort.MESSAGE_SORT_DATE_DESCENDING,
      ),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    return _mapPersonalMessages(response, respect, cancellation);
  }

  Future<void> _observeFilters(
    Int64 revision,
    RpcCancellation? cancellation,
  ) async {
    final captured = epoch;
    filters.observe(revision);
    if (filters.snapshot?.revision != revision) {
      await filters.refresh(cancellation: cancellation);
      _check(captured, cancellation);
      if (filters.snapshot?.revision != revision) {
        throw const CancelledException();
      }
    }
  }

  Future<MessageListResponse> _mapPersonalMessages(
    wire.ListMessagesResponse value,
    bool respect,
    RpcCancellation? cancellation,
  ) async {
    final captured = epoch;
    if (respect) {
      Int64? revision;
      for (final message in value.messages) {
        if (!message.hasPersonalCollapse() ||
            message.id.isEmpty ||
            (message.personalCollapse.matchedRuleIds.isNotEmpty &&
                (message.body.isNotEmpty || message.bodyPreview.isNotEmpty))) {
          throw const ServerException(
            message: 'Некорректное представление списка',
          );
        }
        if (revision != null &&
            revision != message.personalCollapse.rulesRevision) {
          throw const ServerException(message: 'Смешанные версии фильтров');
        }
        revision = message.personalCollapse.rulesRevision;
      }
      if (revision != null) {
        await _observeFilters(revision, cancellation);
      }
    }
    _check(captured, cancellation);
    return mapMessages(value);
  }

  Future<MessageSearchResult?> findMessage({
    required String conferenceId,
    required String query,
    bool headersOnly = false,
    String? startMessageId,
    bool includeStart = true,
    String sort = ApiConstants.sortNewest,
    RpcCancellation? cancellation,
  }) async {
    query = query.trim();
    if (query.isEmpty ||
        utf8.encode(query).length > 256 ||
        (sort != ApiConstants.sortNewest && sort != ApiConstants.sortOldest)) {
      throw const ValidationException(
        message: 'Введите запрос до 256 байт UTF-8',
      );
    }
    final captured = epoch;
    final respect = await filters.ensure(cancellation: cancellation);
    _check(captured, cancellation);
    _check(captured, cancellation);
    final response = await _apiClient.findMessage(
      wire.FindMessageRequest(
        respectPersonalFilters: respect,
        conferenceId: conferenceId,
        query: query,
        scope: headersOnly
            ? wire.MessageSearchScope.MESSAGE_SEARCH_HEADER_ONLY
            : wire.MessageSearchScope.MESSAGE_SEARCH_HEADER_AND_BODY,
        sort: sort == ApiConstants.sortNewest
            ? wire.MessageSort.MESSAGE_SORT_DATE_DESCENDING
            : wire.MessageSort.MESSAGE_SORT_DATE_ASCENDING,
        startMessageId: startMessageId,
        includeStart: includeStart,
      ),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    if (!response.hasMessage()) {
      if (response.matches.isNotEmpty) {
        throw const ServerException(message: 'Некорректный результат поиска');
      }
      return null;
    }
    final collapsed =
        response.message.personalCollapse.matchedRuleIds.isNotEmpty;
    if (collapsed &&
        (response.message.body.isNotEmpty ||
            response.message.bodyPreview.isNotEmpty ||
            response.matches.isNotEmpty)) {
      throw const ServerException(message: 'Некорректное свернутое письмо');
    }
    if (respect && response.message.hasPersonalCollapse()) {
      await _observeFilters(
        response.message.personalCollapse.rulesRevision,
        cancellation,
      );
      _check(captured, cancellation);
    }
    final ranges = collapsed
        ? <int, List<SearchRange>>{}
        : MessageSearchResult.validate(response);
    final message = mapMessage(response.message);
    _latestRevision[conferenceId] = max(
      _latestRevision[conferenceId] ?? 0,
      message.positionRevision,
    );
    return MessageSearchResult(message, ranges);
  }

  Future<MessageSearchResult> getPresentation({
    required String conferenceId,
    required String messageId,
    bool reveal = false,
    String query = '',
    bool headersOnly = false,
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    _check(captured, cancellation);
    final value = await _apiClient.getMessagePresentation(
      wire.GetMessagePresentationRequest(
        message: wire.MessageReference(
          conferenceId: conferenceId,
          messageId: messageId,
        ),
        reveal: reveal,
        searchQuery: query,
        searchScope: query.isEmpty
            ? wire.MessageSearchScope.MESSAGE_SEARCH_SCOPE_UNSPECIFIED
            : headersOnly
            ? wire.MessageSearchScope.MESSAGE_SEARCH_HEADER_ONLY
            : wire.MessageSearchScope.MESSAGE_SEARCH_HEADER_AND_BODY,
      ),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    wire.Message message;
    if (value.hasCollapsed()) {
      final h = value.collapsed;
      if (reveal ||
          value.matchedRuleIds.isEmpty ||
          value.matches.isNotEmpty ||
          h.message.conferenceId != conferenceId ||
          h.message.messageId != messageId) {
        throw const ServerException(message: 'Некорректное свернутое письмо');
      }
      message = wire.Message(
        id: messageId,
        conferenceId: conferenceId,
        fromName: h.fromName,
        fromAddress: h.fromAddress,
        subject: h.subject,
        date: h.hasDate() ? h.date : null,
        isRead: h.isRead,
        threadId: h.threadId,
        inReplyTo: h.inReplyTo,
        personalCollapse: wire.PersonalMessageCollapse(
          rulesRevision: value.rulesRevision,
          matchedRuleIds: value.matchedRuleIds,
        ),
      );
    } else if (value.hasVisible()) {
      message = value.visible;
      if (message.id != messageId ||
          message.conferenceId != conferenceId ||
          message.personalCollapse.matchedRuleIds.isNotEmpty) {
        throw const ServerException(message: 'Некорректное письмо');
      }
    } else {
      throw const ServerException(
        message: 'Сервер не вернул представление письма',
      );
    }
    await _observeFilters(value.rulesRevision, cancellation);
    _check(captured, cancellation);
    final matches = value.matches.isEmpty
        ? <int, List<SearchRange>>{}
        : MessageSearchResult.validate(
            wire.FindMessageResponse(message: message, matches: value.matches),
          );
    return MessageSearchResult(mapMessage(message), matches);
  }

  /// Получение одного сообщения
  ///
  /// [conferenceId] — ID конференции
  /// [messageId] — ID сообщения
  Future<Message> getMessage({
    required String conferenceId,
    required String messageId,
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    final support = await filters.ensure(cancellation: cancellation);
    _check(captured, cancellation);
    if (support) {
      return (await getPresentation(
        conferenceId: conferenceId,
        messageId: messageId,
        cancellation: cancellation,
      )).message;
    }
    final response = await _apiClient.getMessage(
      wire.MessageReference(conferenceId: conferenceId, messageId: messageId),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    final result = mapMessage(response);
    if (result.positionRevision > (_latestRevision[conferenceId] ?? 0)) {
      _latestRevision[conferenceId] = result.positionRevision;
    }
    return result;
  }

  /// Отправка сообщения (ответ, ответ всем, новое, пересылка)
  ///
  /// [conferenceId] — ID конференции
  /// [toName] — имя получателя
  /// [toAddress] — адрес получателя
  /// [subject] — тема сообщения
  /// [body] — тело сообщения
  /// [inReplyTo] — ID сообщения, на которое отвечаем (null для нового)
  Future<SendMessageResponse> sendMessage({
    required String conferenceId,
    required String toName,
    required String toAddress,
    required String subject,
    required String body,
    String? inReplyTo,
    String? operationId,
    bool useFooter = true,
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    final operation = operationId ?? newOperationId();
    final footer = await _footers.capture(operation, enabled: useFooter);
    _check(captured, cancellation);
    final response = await _apiClient.createMessage(
      wire.CreateMessageRequest(
        conferenceId: conferenceId,
        operationId: operation,
        footer: footer,
        toName: toName,
        toAddress: toAddress,
        subject: subject,
        body: body,
        inReplyTo: inReplyTo,
      ),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    if (response.status != wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY) {
      throw const ServerException(
        message: 'Сервер не подтвердил локальное сохранение',
      );
    }
    return SendMessageResponse(
      id: response.message.messageId,
      status: 'saved_locally',
    );
  }

  Future<wire.CreateCrosspostResponse> sendCrosspost({
    required String conferenceId,
    required List<String> additionalConferenceIds,
    required String operationId,
    required String toName,
    required String toAddress,
    required String subject,
    required String body,
    String? inReplyTo,
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    final footer = await _footers.capture(operationId);
    _check(captured, cancellation);
    final response = await _apiClient.createCrosspost(
      wire.CreateCrosspostRequest(
        message: wire.CreateMessageRequest(
          conferenceId: conferenceId,
          operationId: operationId,
          footer: footer,
          toName: toName,
          toAddress: toAddress,
          subject: subject,
          body: body,
          inReplyTo: inReplyTo,
        ),
        additionalConferenceIds: additionalConferenceIds,
      ),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    final expected = {conferenceId, ...additionalConferenceIds};
    final confirmed = response.saved
        .map((copy) => copy.message.conferenceId)
        .toSet();
    if (response.total != expected.length ||
        confirmed.length != response.saved.length ||
        !expected.containsAll(confirmed) ||
        response.saved.any(
          (copy) => copy.message.messageId.isEmpty || copy.ftnMessageId.isEmpty,
        ) ||
        (response.complete && response.saved.length != response.total)) {
      throw const ServerException(
        message: 'Сервер не подтвердил все копии кросспостинга',
      );
    }
    return response;
  }

  /// Ответ на сообщение
  Future<SendMessageResponse> replyToMessage({
    required String conferenceId,
    required Message originalMessage,
    required String body,
    String? operationId,
    RpcCancellation? cancellation,
  }) async {
    final subject = originalMessage.subject.startsWith('Re: ')
        ? originalMessage.subject
        : 'Re: ${originalMessage.subject}';

    return sendMessage(
      conferenceId: conferenceId,
      toName: originalMessage.replyName,
      toAddress: originalMessage.replyAddress,
      subject: subject,
      body: body,
      inReplyTo: originalMessage.id,
      operationId: operationId,
      cancellation: cancellation,
    );
  }

  /// Ответ всем (если есть thread)
  Future<SendMessageResponse> replyToAll({
    required String conferenceId,
    required Message originalMessage,
    required String body,
    String? operationId,
    RpcCancellation? cancellation,
  }) async {
    // В эхоконференции ответ видят все участники; адресат — автор сообщения.
    return replyToMessage(
      conferenceId: conferenceId,
      originalMessage: originalMessage,
      body: body,
      operationId: operationId,
      cancellation: cancellation,
    );
  }

  /// Пересылка сообщения
  Future<SendMessageResponse> forwardMessage({
    required String conferenceId,
    required String toName,
    required String toAddress,
    required Message originalMessage,
    String? note,
    String? operationId,
    RpcCancellation? cancellation,
  }) async {
    final forwardedBody = note != null
        ? '$note\n\n--- Forwarded message ---\n'
              'From: ${originalMessage.fromName} <${originalMessage.fromAddress}>\n'
              'Date: ${originalMessage.date}\n'
              'Subject: ${originalMessage.subject}\n\n'
              '${originalMessage.body}'
        : '--- Forwarded message ---\n'
              'From: ${originalMessage.fromName} <${originalMessage.fromAddress}>\n'
              'Date: ${originalMessage.date}\n'
              'Subject: ${originalMessage.subject}\n\n'
              '${originalMessage.body}';

    final subject = originalMessage.subject.startsWith('Fwd: ')
        ? originalMessage.subject
        : 'Fwd: ${originalMessage.subject}';

    return sendMessage(
      conferenceId: conferenceId,
      toName: toName,
      toAddress: toAddress,
      subject: subject,
      body: forwardedBody,
      operationId: operationId,
      cancellation: cancellation,
    );
  }

  /// Создать новое сообщение в конференции
  Future<SendMessageResponse> composeNewMessage({
    required String conferenceId,
    required String toName,
    required String toAddress,
    required String subject,
    required String body,
    String? operationId,
    RpcCancellation? cancellation,
  }) async {
    return sendMessage(
      conferenceId: conferenceId,
      toName: toName,
      toAddress: toAddress,
      subject: subject,
      body: body,
      inReplyTo: null,
      operationId: operationId,
      cancellation: cancellation,
    );
  }

  Future<void> markConferenceRead({
    required String conferenceId,
    required String operationId,
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    try {
      await _apiClient.markConferenceRead(
        wire.MarkConferenceReadRequest(
          conferenceId: conferenceId,
          operationId: operationId,
        ),
        cancellation: cancellation,
      );
      _check(captured, cancellation);
    } on ApiException catch (error) {
      _check(captured, cancellation);
      if (error.statusCode == 12) {
        throw const ApiException(
          message: 'Сервер не поддерживает массовую отметку',
          statusCode: 12,
        );
      }
      rethrow;
    }
  }

  /// Отметить сообщение как прочитанное
  Future<void> markAsRead({
    required String conferenceId,
    required String messageId,
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    await _apiClient.markRead(
      wire.MessageReference(conferenceId: conferenceId, messageId: messageId),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
  }

  /// Убрать персональную отметку чтения, сохранив историю и позицию.
  Future<void> markAsUnread({
    required String conferenceId,
    required String messageId,
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    _check(captured, cancellation);
    try {
      await _apiClient.markUnread(
        wire.MessageReference(conferenceId: conferenceId, messageId: messageId),
        cancellation: cancellation,
      );
      _check(captured, cancellation);
    } on ApiException catch (error) {
      _check(captured, cancellation);
      if (error.statusCode == 12) {
        throw const ApiException(
          message: 'Сервер не поддерживает пометку непрочитанности. Обновите сервер.',
          statusCode: 12,
          rpcName: 'MarkUnread',
        );
      }
      rethrow;
    }
  }

  /// Получение thread (цепочки сообщений)
  Future<MessageListResponse> getThreadPage({
    required String conferenceId,
    required String threadId,
    int offset = 0,
    int limit = 20,
    RpcCancellation? cancellation,
  }) async {
    final captured = epoch;
    final respect = await filters.ensure(cancellation: cancellation);
    _check(captured, cancellation);
    final response = await _apiClient.getThread(
      wire.GetThreadRequest(
        respectPersonalFilters: respect,
        conferenceId: conferenceId,
        threadId: threadId,
        page: wire.PageRequest(offset: Int64(offset), limit: limit),
      ),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    return _mapPersonalMessages(response, respect, cancellation);
  }

  Future<List<Message>> getThread({
    required String conferenceId,
    required String threadId,
    int offset = 0,
    int limit = 20,
    RpcCancellation? cancellation,
  }) async => (await getThreadPage(
    conferenceId: conferenceId,
    threadId: threadId,
    offset: offset,
    limit: limit,
    cancellation: cancellation,
  )).messages;
}
