import 'dart:convert';

import 'package:fixnum/fixnum.dart';

import '../api/api_transport.dart';
import '../api/api_exceptions.dart';
import '../api/generated/ffido/v1/ffido.pb.dart' as wire;

class PersonalMessageFiltersRepository {
  final ApiTransport api;
  PersonalMessageFiltersRepository(this.api);
  int _epoch = -1;
  String? _scope;
  bool? _supported;
  wire.PersonalMessageFilterSet? _snapshot;
  Int64 _minimum = Int64.ZERO;
  int get epoch => api.epoch;
  Stream<int> get sessionChanges => api.sessionChanges;
  void _sync() {
    if (_epoch != epoch || _scope != api.cacheScope) {
      _epoch = epoch;
      _scope = api.cacheScope;
      _supported = null;
      _snapshot = null;
      _minimum = Int64.ZERO;
    }
  }

  bool? get supported {
    _sync();
    return _supported;
  }

  wire.PersonalMessageFilterSet? get snapshot {
    _sync();
    return _snapshot?.deepCopy();
  }

  bool _less(Int64 a, Int64 b) =>
      BigInt.parse(a.toStringUnsigned()) < BigInt.parse(b.toStringUnsigned());
  void _check(int captured, RpcCancellation? token) {
    if (captured != epoch ||
        _scope != api.cacheScope ||
        token?.isCancelled == true) {
      throw const CancelledException();
    }
  }

  Future<bool> ensure({RpcCancellation? cancellation}) async {
    _sync();
    if (_supported != null) return _supported!;
    await refresh(cancellation: cancellation);
    return _supported!;
  }

  Future<void> refresh({RpcCancellation? cancellation}) async {
    _sync();
    final captured = epoch;
    _check(captured, cancellation);
    try {
      final value = await api.getPersonalMessageFilters(
        cancellation: cancellation,
      );
      _check(captured, cancellation);
      if (_less(value.revision, _minimum) ||
          value.rules.length > 200 ||
          value.rules.map((r) => r.ruleId).toSet().length !=
              value.rules.length) {
        throw const ServerException(
          message: 'Некорректная версия персональных фильтров',
        );
      }
      if (value.revision == Int64.ZERO && value.rules.isNotEmpty) {
        throw const ServerException(message: 'Некорректная версия правил');
      }
      for (final rule in value.rules) {
        try {
          validateRule(rule);
        } on ValidationException {
          throw const ServerException(
            message: 'Сервер вернул некорректное правило',
          );
        }
      }
      _snapshot = value.deepCopy();
      _minimum = value.revision;
      _supported = true;
    } on ApiException catch (e) {
      _check(captured, cancellation);
      if (e.statusCode != 12) rethrow;
      _supported = false;
      _snapshot = null;
    }
  }

  void observe(Int64 revision) {
    _sync();
    if (_less(revision, _minimum)) throw const CancelledException();
    _minimum = revision;
  }

  Future<void> save(
    wire.ReplacePersonalMessageFiltersRequest request, {
    RpcCancellation? cancellation,
  }) async {
    _sync();
    final captured = epoch;
    _check(captured, cancellation);
    if (request.rules.length > 200 ||
        request.writeToBuffer().length > 256 * 1024) {
      throw const ValidationException(message: 'Не более 200 правил');
    }
    for (final rule in request.rules) {
      validateRule(rule);
    }
    final result = await api.replacePersonalMessageFilters(
      request,
      cancellation: cancellation,
    );
    _check(captured, cancellation);
    if (result.revision != request.expectedRevision + Int64.ONE ||
        request.expectedRevision == Int64(-1)) {
      throw const ServerException(
        message: 'Некорректная версия сохранённых правил',
      );
    }
    if (!_less(result.revision, _minimum)) _minimum = result.revision;
    await refresh(cancellation: cancellation);
  }

  static void validateRule(wire.PersonalMessageFilter rule) {
    final uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (rule.addressEquals.isNotEmpty) {
      final parts = RegExp(r'^(\d+):(\d+)/(\d+)(?:\.(\d+))?$')
          .firstMatch(rule.addressEquals);
      if (parts == null ||
          [1, 2, 3, 4].any(
            (i) =>
                parts.group(i) != null &&
                (int.tryParse(parts.group(i)!) == null ||
                    int.parse(parts.group(i)!) > 65535 ||
                    i < 3 && int.parse(parts.group(i)!) == 0),
          )) {
        throw const ValidationException(
          message: 'Укажите числовой FTN-адрес zone:net/node.point',
        );
      }
    }
    if (!uuid.hasMatch(rule.ruleId) ||
        ![
          wire
              .PersonalMessageFilterScope
              .PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS,
          wire
              .PersonalMessageFilterScope
              .PERSONAL_MESSAGE_FILTER_SCOPE_CONFERENCE,
        ].contains(rule.scope) ||
        (rule.scope ==
                wire
                    .PersonalMessageFilterScope
                    .PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS
            ? rule.conferenceId.isNotEmpty
            : rule.conferenceId.isEmpty) ||
        utf8.encode(rule.authorContains).length > 256 ||
        utf8.encode(rule.subjectContains).length > 256 ||
        utf8.encode(rule.addressEquals).length > 64 ||
        [
          rule.authorContains,
          rule.addressEquals,
          rule.subjectContains,
        ].every((s) => s.trim().isEmpty)) {
      throw const ValidationException(
        message: 'Укажите условие и область действия; имя и тема — до 256 байт',
      );
    }
  }
}
