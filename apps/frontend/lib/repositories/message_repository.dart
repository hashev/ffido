import '../api/message_footer_snapshot.dart';

import 'dart:math';

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
  final UueRepository uue;
  final MessageFooterSnapshots _footers;
  MessageRepository(ApiTransport apiClient)
    : _apiClient = apiClient,
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
    final response = await _apiClient.listMessages(
      wire.ListMessagesRequest(
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
    return mapMessages(response);
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
    final response = await _apiClient.getThread(
      wire.GetThreadRequest(
        conferenceId: conferenceId,
        threadId: threadId,
        page: wire.PageRequest(offset: Int64(offset), limit: limit),
      ),
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    return mapMessages(response);
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
