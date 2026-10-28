import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_exceptions.dart';
import 'api_transport.dart';
import 'generated/ffido/v1/ffido.pb.dart' as wire;

/// Only the authenticated server session can advertise support for this extension.
abstract interface class MessageFooterSupport {
  bool get supportsMessageFooter;
}

class MessageFooterSettings {
  static const taglineKey = 'ffido_tagline_v1';
  static const originKey = 'ffido_origin_v1';
  static const defaultOrigin = 'https://github.com/hashev/ffido';
  final SharedPreferences preferences;
  final String version;
  MessageFooterSettings(this.preferences, this.version);
  static Future<MessageFooterSettings> load([
    SharedPreferences? preferences,
  ]) async {
    final identity = jsonDecode(
      await rootBundle.loadString('assets/updates/identity.json'),
    ) as Map;
    return MessageFooterSettings(
      preferences ?? await SharedPreferences.getInstance(),
      identity['version'] as String,
    );
  }

  String get defaultTagline => 'FFIDO $version';
  String get tagline => preferences.getString(taglineKey) ?? defaultTagline;
  String get origin => preferences.getString(originKey) ?? defaultOrigin;
  bool get hasOverrides =>
      preferences.containsKey(taglineKey) || preferences.containsKey(originKey);
  static void validate(String value, String field) {
    if (utf8.decode(utf8.encode(value)) != value ||
        utf8.encode(value).length > 256 ||
        value.runes.any((c) => c < 32 || c == 127)) {
      throw ValidationException(
        message: 'Используйте одну строку до 256 байт без управляющих символов',
        fieldErrors: {
          field: ['Некорректное значение'],
        },
      );
    }
  }

  Future<void> save(String tagline, String origin) async {
    validate(tagline, 'tagline');
    validate(origin, 'origin');
    if (tagline.isEmpty || tagline == defaultTagline) {
      await preferences.remove(taglineKey);
    } else {
      await preferences.setString(taglineKey, tagline);
    }
    if (origin.isEmpty || origin == defaultOrigin) {
      await preferences.remove(originKey);
    } else {
      await preferences.setString(originKey, origin);
    }
  }

  Future<void> reset() => save('', '');
  wire.MessageFooter snapshot() {
    validate(tagline, 'tagline');
    validate(origin, 'origin');
    return wire.MessageFooter(tagline: tagline, origin: origin);
  }
}

/// Freeze the footer with the operation, including absence on legacy servers.
/// Session changes discard all snapshots; failed preflight can be retried after reset.
class MessageFooterSnapshots {
  final ApiTransport api;
  final Map<String, Future<wire.MessageFooter?>> _operations = {};
  int _epoch = -1;
  MessageFooterSnapshots(this.api);
  Future<wire.MessageFooter?> capture(
    String operation, {
    bool enabled = true,
  }) async {
    if (!enabled || api is! MessageFooterSupport) return null;
    if (_epoch != api.epoch) {
      _operations.clear();
      _epoch = api.epoch;
    }
    final future = _operations.putIfAbsent(operation, () async {
      final settings = await MessageFooterSettings.load();
      if (!(api as MessageFooterSupport).supportsMessageFooter) {
        if (settings.hasOverrides) {
          throw const ValidationException(
            message: 'Сервер не поддерживает Tagline/Origin. Обновите сервер или сбросьте оформление; черновик сохранён.',
          );
        }
        return null;
      }
      return settings.snapshot();
    });
    try {
      return (await future)?.deepCopy();
    } catch (_) {
      if (identical(_operations[operation], future)) {
        _operations.remove(operation);
      }
      rethrow;
    }
  }
}
