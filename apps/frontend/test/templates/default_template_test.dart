import 'package:flutter_test/flutter_test.dart';
import 'package:fido/templates/default_template.dart';
import 'package:fido/templates/template_engine.dart';

import 'template_engine_test.dart' show context, original;

void main() {
  final engine = TemplateEngine();

  test('built-in template validates for every action and area', () {
    expect(engine.validate(defaultMessageTemplate), isEmpty);
  });

  for (final action in TemplateAction.values) {
    test('built-in ${action.name} preserves formatting and cursor', () {
      final result = engine.render(
        defaultMessageTemplate,
        context(action: action),
      );
      const greeting = 'Hello, Иван!\n';
      const signature = 'Best Regards, Юрий\n';
      final hour = original.date.toLocal().hour.toString().padLeft(2, '0');
      final line = '30.10.2026 $hour:00:00, from Иван Петров -> All:\n';
      const bar =
          '=============================================================================\n';
      final prefix = action == TemplateAction.forward
          ? '$bar* Forwarded by Юрий Хашев (2:1/1.4)\n'
                '* Area : RU.OLD ()\n'
                '* From : Иван Петров, 2:1/2.3 (30.10.2026 $hour:00:00)\n'
                '* To   : All\n'
                '* Subj : Тема\n'
                '$barПривет\nAB> глубже\n$bar\n\n'
          : '\n\n';
      final reply = switch (action) {
        TemplateAction.reply =>
          'Reply to message from <30.10.2026>, Иван Петров -> All:\n\n',
        TemplateAction.quoted => '\n',
        _ => '\n',
      };
      final quote = action == TemplateAction.quoted
          ? '$lineИП> Привет\nAB>> глубже\n\n\n'
          : '\n';
      final beforeCursor =
          '$prefix$greeting${action == TemplateAction.newMessage ? '\n' : ''}';
      expect(result.diagnostics, isEmpty);
      expect(result.body, '$beforeCursor\n\n$reply$quote\n$signature');
      expect(result.cursor, beforeCursor.length);
      expect(result.body, isNot(contains('@Position')));
    });
  }

  test('All uses unchanged GoldED pseudo semantics', () {
    final result = engine.render(
      defaultMessageTemplate,
      context(action: TemplateAction.newMessage, to: 'All'),
    );
    expect(result.body, contains('Hello, !\n'));
  });
}
