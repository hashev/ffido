import 'package:flutter_test/flutter_test.dart';
import 'package:fido/templates/template_model.dart';

void main() {
  test(
    'registry separates portable operations, absent modes and host features',
    () {
      for (final name in ['new', 'quote', 'pad', 'forceto', 'tfname']) {
        expect(templateTokens[name], TemplateSupport.supported);
      }
      for (final name in ['header', 'changed', 'quotebuf']) {
        expect(templateTokens[name], TemplateSupport.inactive);
      }
      for (final name in [
        'pipe',
        'forcefrom',
        'omsgid',
        'tr',
        'include',
        'random',
      ]) {
        expect(templateTokens[name], TemplateSupport.unavailable);
      }
      expect(templateConditions.every(templateTokens.containsKey), isTrue);
      expect(templateCommands.every(templateTokens.containsKey), isTrue);
    },
  );
  test('line endings normalize for copy-paste', () {
    expect(templateLf('a\r\nb\rc'), 'a\nb\nc');
  });
}
