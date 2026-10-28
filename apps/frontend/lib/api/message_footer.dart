import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_exceptions.dart';

export 'message_footer_snapshot.dart';
import 'generated/ffido/v1/ffido.pb.dart' as wire;

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
