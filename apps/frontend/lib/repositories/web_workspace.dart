import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_exceptions.dart';
import '../api/generated/ffido/v1/ffido.pb.dart' as wire;
import '../files/uue_file_types.dart';
import 'uue_repository.dart';
import '../platform/telegram_environment.dart';
import 'backend_directory.dart';
import 'web_draft_store.dart';

class WebProfile {
  WebProfile(this.node, this.profile);
  final BackendEntry node;
  final wire.Profile profile;
  String get scope =>
      jsonEncode([node.id, node.endpoint.toString(), profile.address]);
}

class WebWorkspace extends ChangeNotifier {
  WebWorkspace(this.client, this.preferences, this.directory, this.telegram) {
    drafts = WebDraftStore(
      readValue: preferences.getString,
      listKeys: preferences.getKeys,
      writeValue: preferences.setString,
      removeValue: preferences.remove,
    );
    WebDraftStore.active = drafts;
    client.endpointPolicy = (endpoint) =>
        directory.knownEntries.any((n) => n.endpoint == endpoint);
  }
  final ApiClient client;
  final SharedPreferences preferences;
  final BackendDirectoryRepository directory;
  final TelegramHost telegram;
  late final WebDraftStore drafts;
  final profiles = <WebProfile>[];
  final errors = <String, String>{};
  final telegramSupported = <String, bool>{};
  final invalidTelegramProof = <String>{};
  final _sessions = <String, wire.LoginResponse>{};
  final _telegramSessions = <String>{};
  WebProfile? selected;
  String notice = '';
  static const lastKey = 'ffido_web_last_profile_v1';
  String stopped(String scope) => 'ffido_web_signed_out:$scope';
  bool hasRememberedSession(WebProfile profile) =>
      _sessions.containsKey(profile.scope);

  Future<void> refresh() async {
    await directory.load();
    final active = selected;
    if (active != null &&
        (!directory.isAccepted(active.node) ||
            directory.current?.find(active.node.id)?.endpoint !=
                active.node.endpoint)) {
      await client.clearAuthToken();
      drafts.scope = null;
      selected = null;
    }
    profiles.removeWhere(
      (p) => directory.current?.find(p.node.id)?.endpoint != p.node.endpoint,
    );
    notifyListeners();
  }

  Future<void> discover(BackendEntry node) async {
    if (!directory.isAccepted(node) ||
        directory.current?.find(node.id)?.endpoint != node.endpoint) {
      throw StateError('Подтвердите адрес узла');
    }
    try {
      final supported = await client.supportsTelegram(node.endpoint.toString());
      telegramSupported[node.id] = supported;
      profiles.removeWhere(
        (p) => p.node.id == node.id && !_sessions.containsKey(p.scope),
      );
      if (supported && telegram.initData.isNotEmpty) {
        final result = await client.telegramProfiles(
          node.endpoint.toString(),
          telegram.initData,
        );
        if (!directory.isAccepted(node)) {
          throw StateError('Узел больше не разрешён');
        }
        for (final profile in result.profiles) {
          final entry = WebProfile(node, profile);
          profiles.removeWhere((p) => p.scope == entry.scope);
          profiles.add(entry);
        }
      }
      errors.remove(node.id);
      invalidTelegramProof.remove(node.id);
    } catch (error) {
      if (error is UnauthorizedException && telegram.initData.isNotEmpty) {
        invalidTelegramProof.add(node.id);
      }
      telegramSupported.remove(node.id);
      errors[node.id] = telegram.initData.isEmpty
          ? 'Узел недоступен. Повторите запрос.'
          : 'Не удалось проверить профили. Проверьте сеть; при устаревшем входе переоткройте Mini App.';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> restore() async {
    await refresh();
    if (telegram.initData.isEmpty) return;
    final hinted = telegram.startNode;
    var known = directory.knownEntries;
    if (hinted != null && hinted.isNotEmpty) {
      known = known.where((n) => n.id == hinted).toList();
    }
    await Future.wait(
      known.map((node) async {
        try {
          await discover(node);
        } catch (_) {}
      }),
    );
    final last = preferences.getString(lastKey);
    WebProfile? target;
    for (final profile in profiles) {
      if (profile.scope == last) target = profile;
    }
    target ??= profiles.length == 1 ? profiles.single : null;
    if (target != null && preferences.getBool(stopped(target.scope)) != true) {
      await select(target);
    }
  }

  Future<void> select(WebProfile profile) async {
    if (!directory.isAccepted(profile.node) ||
        directory.current?.find(profile.node.id)?.endpoint !=
            profile.node.endpoint) {
      throw StateError('Узел больше не разрешён');
    }
    final captured = client.epoch;
    try {
      final saved = _sessions[profile.scope];
      if (saved != null) {
        await client.configure(
          endpoint: profile.node.endpoint.toString(),
          token: saved.sessionSecret,
        );
        try {
          await client.restoreSession();
        } on UnauthorizedException {
          _sessions.remove(profile.scope);
          if (telegram.initData.isEmpty) rethrow;
          _sessions[profile.scope] = await client.loginWithTelegram(
            endpoint: profile.node.endpoint.toString(),
            initData: telegram.initData,
            address: profile.profile.address,
          );
          _telegramSessions.add(profile.scope);
        }
      } else {
        if (telegram.initData.isEmpty) {
          throw StateError('Введите HPT-пароль для выбранного профиля');
        }
        _sessions[profile.scope] = await client.loginWithTelegram(
          endpoint: profile.node.endpoint.toString(),
          initData: telegram.initData,
          address: profile.profile.address,
        );
        _telegramSessions.add(profile.scope);
      }
      await _selected(profile);
    } catch (_) {
      if (client.epoch != captured || client.session == null) {
        await _retireCurrent();
      }
      rethrow;
    }
  }

  Future<void> hptLogin(
    BackendEntry node,
    String name,
    String address,
    String password,
  ) async {
    if (invalidTelegramProof.contains(node.id)) {
      throw const UnauthorizedException(
        message:
            'Данные запуска Telegram недействительны. Переоткройте Mini App.',
      );
    }
    if (!directory.isAccepted(node) ||
        directory.current?.find(node.id)?.endpoint != node.endpoint) {
      throw StateError('Подтвердите адрес узла');
    }
    final result = await client.login(
      endpoint: node.endpoint.toString(),
      name: name,
      address: address,
      password: password,
    );
    final profile = WebProfile(node, result.session.profile);
    profiles.removeWhere((p) => p.scope == profile.scope);
    profiles.add(profile);
    _sessions[profile.scope] = result;
    _telegramSessions.remove(profile.scope);
    await _selected(profile);
  }

  Future<void> _retireCurrent() async {
    selected = null;
    drafts.scope = null;
    await client.clearAuthToken();
    notifyListeners();
  }

  Future<void> _selected(WebProfile profile) async {
    if (!directory.isAccepted(profile.node) ||
        directory.current?.find(profile.node.id)?.endpoint !=
            profile.node.endpoint) {
      await _retireCurrent();
      throw StateError('Узел больше не разрешён');
    }
    if (client.session?.profile.address != profile.profile.address) {
      await _retireCurrent();
      throw StateError('Сервер вернул другой профиль');
    }
    selected = profile;
    drafts.scope = profile.scope;
    await preferences.setString(lastKey, profile.scope);
    await preferences.remove(stopped(profile.scope));
    notifyListeners();
  }

  Future<void> signOut({bool unbind = false}) async {
    final profile = selected;
    if (profile == null) return;
    if (unbind) {
      try {
        await client.unbindTelegram();
        await drafts.clear(profile.scope);
        if (!_telegramSessions.contains(profile.scope)) {
          notifyListeners();
          return;
        }
      } catch (error) {
        try {
          await signOut();
        } on NetworkException {
          /* Both remote revocations remain unconfirmed. */
        }
        throw NetworkException(
          message: 'Локальный сеанс завершён; отвязка Telegram на сервере не подтверждена.',
          originalError: error,
        );
      }
    }
    await preferences.setBool(stopped(profile.scope), true);
    drafts.scope = null;
    await drafts.clear(profile.scope);
    _sessions.remove(profile.scope);
    _telegramSessions.remove(profile.scope);
    selected = null;
    drafts.scope = null;
    try {
      if (unbind) {
        await client.clearAuthToken();
      } else {
        await client.logout();
      }
    } on UnauthorizedException {
      // The server has already confirmed that this token cannot authorize RPCs.
    } catch (error) {
      throw NetworkException(
        message:
            'Локальный сеанс завершён; отзыв сессии на сервере не подтверждён.',
        originalError: error,
      );
    } finally {
      notifyListeners();
    }
  }

  Future<void> forget(String id) async {
    final scopes =
        profiles.where((p) => p.node.id == id).map((p) => p.scope).toSet()
          ..addAll(drafts.scopesForNode(id));
    Object? revokeError;
    for (final scope in scopes) {
      final session = _sessions[scope];
      if (session != null) {
        try {
          final parts = jsonDecode(scope) as List;
          await client.revokeSessionAt(
            parts[1] as String,
            session.sessionSecret,
          );
        } catch (error) {
          revokeError = error;
        }
      }
    }
    final active = selected;
    if (active?.node.id == id) {
      try {
        await signOut();
      } catch (_) {
        await client.clearAuthToken();
      }
    }
    for (final scope in scopes) {
      await drafts.clear(scope);
      _sessions.remove(scope);
      _telegramSessions.remove(scope);
    }
    profiles.removeWhere((p) => p.node.id == id);
    await directory.forget(id);
    errors.remove(id);
    notifyListeners();
    if (revokeError != null) {
      throw StateError(
        'Локальные данные удалены; серверный отзыв не подтверждён',
      );
    }
  }

  Future<void> recover(Map<String, dynamic> record) async {
    final profile = selected;
    if (profile == null ||
        !client.hasToken ||
        !directory.isAccepted(profile.node)) {
      throw StateError('Войдите в профиль');
    }
    final operation = record['operationId'] as String;
    final bytes = base64Decode(record['wire'] as String);
    final captured = client.epoch;
    bool complete;
    switch (record['rpc']) {
      case 'CreateMessage':
        final request = wire.CreateMessageRequest.fromBuffer(bytes);
        if (request.operationId != operation) {
          throw StateError('Повреждена операция');
        }
        final result = await client.createMessage(request);
        complete = result.status == wire.SaveStatus.SAVE_STATUS_SAVED_LOCALLY;
      case 'CreateCrosspost':
        final request = wire.CreateCrosspostRequest.fromBuffer(bytes);
        if (request.message.operationId != operation) {
          throw StateError('Повреждена операция');
        }
        complete = (await client.createCrosspost(request)).complete;
      case 'CommitUue':
        final request = wire.CommitUueRequest.fromBuffer(bytes);
        if (request.message.operationId != operation) {
          throw StateError('Повреждена операция');
        }
        final status = await client.getUueSendStatus(
          wire.UueOperationReference(operationId: operation),
        );
        if (status.state == 'uploading') {
          throw StateError(
            'Загрузка не завершена. Файл потребуется выбрать заново; автоматическая новая отправка запрещена.',
          );
        }
        complete = (await client.commitUue(request)).state == 'completed';
      default:
        throw StateError('Неизвестная операция');
    }
    if (captured != client.epoch || selected?.scope != profile.scope) {
      throw StateError('Профиль изменён');
    }
    if (!complete) {
      throw StateError(
        'Не все части сохранены; результат остаётся неопределённым',
      );
    }
    await drafts.complete(profile.scope, operation);
    notifyListeners();
  }

  Future<void> resumeUue(
    Map<String, dynamic> record,
    SelectedUueFile file,
  ) async {
    final profile = selected;
    if (profile == null ||
        record['rpc'] != 'CommitUue' ||
        !directory.isAccepted(profile.node)) {
      throw StateError('Войдите в профиль');
    }
    final request = wire.CommitUueRequest.fromBuffer(
      base64Decode(record['wire'] as String),
    ).message;
    final operation = record['operationId'] as String;
    if (request.operationId != operation) {
      throw StateError('Повреждена операция');
    }
    final captured = client.epoch;
    final result = await UueRepository(client).send(
      UueDraft(
        conference: request.conferenceId,
        operation: operation,
        subject: request.subject,
        body: request.body,
        toName: request.toName,
        toAddress: request.toAddress,
        reply: request.inReplyTo,
        useFooter: request.hasFooter(),
        file: file,
      ),
    );
    if (captured != client.epoch || selected?.scope != profile.scope) {
      throw StateError('Профиль изменён');
    }
    if (!result.complete) {
      throw StateError('Не все части сохранены; повторите ту же операцию');
    }
    notifyListeners();
  }
}
