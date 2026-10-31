import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/templates/template_settings.dart';
import 'package:fido/templates/default_template.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'ffido_origin_v1': 'origin',
      'ffido_tagline_v1': 'tagline',
    }),
  );
  test('missing vs empty, persistence and independent reset', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = TemplateSettings(prefs);
    expect(settings.read()!.text, defaultMessageTemplate);
    expect(prefs.containsKey(TemplateSettings.key), isFalse);
    await settings.save(TemplateBundle(''));
    expect(TemplateSettings(prefs).read()!.text, '');
    await settings.save(TemplateBundle('Привет @cfname'));
    expect(TemplateSettings(prefs).read()!.text, 'Привет @cfname');
    await settings.reset();
    expect(settings.read()!.text, defaultMessageTemplate);
    expect(prefs.containsKey(TemplateSettings.key), isFalse);
    expect(prefs.getString('ffido_origin_v1'), 'origin');
    expect(prefs.getString('ffido_tagline_v1'), 'tagline');
    expect(TemplateSettings(prefs).read()!.text, defaultMessageTemplate);
  });
  test('invalid saves and failed writes preserve working version', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = TemplateSettings(prefs);
    await settings.save(TemplateBundle('Рабочий'));
    await expectLater(
      settings.save(TemplateBundle('@pipe{bad}')),
      throwsFormatException,
    );
    await expectLater(
      TemplateSettings(
        prefs,
        write: (_) async => false,
      ).save(TemplateBundle('Другой')),
      throwsFormatException,
    );
    expect(settings.read()!.text, 'Рабочий');
    await expectLater(
      settings.save(TemplateBundle('@include missing')),
      throwsFormatException,
    );
    await prefs.setString(TemplateSettings.key, 'broken');
    expect(settings.read, throwsFormatException);
  });
  test('schema validation rejects corrupt data', () {
    for (final raw in [
      'null',
      '{}',
      '{"version":2}',
      '{"version":1,"text":42}',
    ]) {
      expect(() => TemplateBundle.decode(raw), throwsFormatException);
    }
  });
}
