import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'template_engine.dart';

class TemplateBundle {
  final String text;
  const TemplateBundle(this.text);
  List<TemplateDiagnostic> validate() => TemplateEngine().validate(text);
  String encode() => jsonEncode({'version': 1, 'text': text});
  static TemplateBundle decode(String raw) {
    if (utf8.encode(raw).length > 512 * 1024) {
      throw const FormatException('Настройки шаблона слишком велики');
    }
    final data = jsonDecode(raw);
    if (data is! Map || data['version'] != 1 || data['text'] is! String) {
      throw const FormatException('Повреждены настройки шаблона');
    }
    TemplateLimits.check(data['text'] as String);
    return TemplateBundle(data['text'] as String);
  }
}

class TemplateSettings {
  static const key = 'ffido_message_template_v1';
  final SharedPreferences preferences;
  final Future<bool> Function(String)? write;
  TemplateSettings(this.preferences, {this.write});
  static Future<TemplateSettings> load() async =>
      TemplateSettings(await SharedPreferences.getInstance());
  TemplateBundle? read() {
    final raw = preferences.getString(key);
    if (raw == null) return null;
    final bundle = TemplateBundle.decode(raw);
    if (bundle.validate().any((d) => d.error)) {
      throw const FormatException(
        'Сохранённый шаблон содержит ошибки; откройте настройки',
      );
    }
    return bundle;
  }

  Future<void> save(TemplateBundle bundle) async {
    final errors = bundle.validate().where((d) => d.error).toList();
    if (errors.isNotEmpty) {
      throw FormatException(errors.map((d) => d.toString()).join('\n'));
    }
    final raw = bundle.encode();
    final previous = preferences.getString(key);
    try {
      if (!await (write?.call(raw) ?? preferences.setString(key, raw))) {
        throw const FormatException('Не удалось сохранить шаблон');
      }
    } catch (_) {
      // SharedPreferences updates its in-memory cache before the platform write.
      if (write == null) {
        try {
          if (previous == null) {
            await preferences.remove(key);
          } else {
            await preferences.setString(key, previous);
          }
        } catch (_) {
          /* Keep the original write error visible. */
        }
      }
      rethrow;
    }
  }

  Future<void> reset() async {
    final previous = preferences.getString(key);
    try {
      if (!await preferences.remove(key)) {
        throw const FormatException('Не удалось сбросить шаблон');
      }
    } catch (_) {
      if (previous != null) {
        try {
          await preferences.setString(key, previous);
        } catch (_) {
          /* Original error wins. */
        }
      }
      rethrow;
    }
  }
}
