import 'package:flutter_test/flutter_test.dart';
import 'package:fido/models/conference.dart';
import 'package:fido/models/message.dart';
import 'package:fido/templates/template_engine.dart';

final original = Message(
  id: 'id',
  fromName: 'Иван Петров',
  fromAddress: '2:1/2.3',
  toName: 'All',
  toAddress: '',
  subject: 'Тема',
  body: 'Привет\nAB> глубже',
  date: DateTime.utc(2026, 10, 30, 10),
);
TemplateContext context({
  TemplateAction action = TemplateAction.quoted,
  AreaKind kind = AreaKind.echo,
  String to = 'Иван Петров',
  Message? message,
}) => TemplateContext(
  action: action,
  kind: kind,
  name: 'Юрий Хашев',
  address: '2:1/1.4',
  toName: to,
  subject: 'Re: Тема',
  original: message ?? original,
  now: DateTime(2026, 10, 30, 13, 4, 5),
  area: 'RU.TEST',
  originalArea: 'RU.OLD',
  version: '1.0.11',
  revision: '1032',
);
void main() {
  final engine = TemplateEngine();
  test('all action and area conditions, comments, escapes and case', () {
    for (final action in TemplateAction.values) {
      for (final kind in [AreaKind.echo, AreaKind.netmail, AreaKind.local]) {
        final r = engine.render(
          '@newN\n@replyR\n@quotedQ\n@forwardF\n@echoE\n@netT\n@localL\n',
          context(action: action, kind: kind),
        );
        expect(r.valid, isTrue);
        expect(
          r.body,
          '${['N', 'R', 'Q', 'F'][action.index]}\n${kind == AreaKind.echo
              ? 'E'
              : kind == AreaKind.netmail
              ? 'T'
              : 'L'}\n',
        );
      }
    }
    expect(
      engine
          .render(
            ' ; comment\n@NET@QUOTEDДа\n@echoНет\n@@new\n',
            context(kind: AreaKind.netmail),
          )
          .body,
      'Да\n@new\n',
    );
  });
  test('inactive modes discard unavailable commands', () {
    final r = engine.render(
      '@header @msgno\n@changed @pipe{bad}\n@quotedДа',
      context(),
    );
    expect(r.body, 'Да');
    expect(r.valid, isTrue);
    expect(r.diagnostics.length, 2);
    expect(engine.validate('@header @msgno').any((d) => d.error), isFalse);
  });
  test(
    'unknown tokens, boundaries and malformed parameters have locations',
    () {
      final r = engine.render('Строка\n@missing\n@oname{нет', context());
      expect(r.valid, isFalse);
      expect(
        r.diagnostics.any(
          (d) => d.line == 2 && d.column == 1 && d.code == 'unknown',
        ),
        isTrue,
      );
      expect(
        r.diagnostics.any((d) => d.line == 3 && d.code == 'braces'),
        isTrue,
      );
      expect(
        engine.render('@onameExtra @oname', context()).diagnostics.first.code,
        'unknown',
      );
    },
  );
  test('names, alternatives, dates, addresses, areas and no original', () {
    expect(
      engine
          .render(
            '@oname{я}{ты}|@dname{мне}{тебе}{всем}|@cfname|@o3daddr|@caddr|@oecho|@cecho|@subject|@cdate @ctime',
            context(),
          )
          .body,
      'ты|всем|Юрий|2:1/2|2:1/1.4|RU.OLD|RU.TEST|Тема|30.10.2026 13:04:05',
    );
    expect(engine.render('@pseudo{}{}{все}', context(to: 'All')).body, 'все');
    expect(engine.render('@oname|@odate', TemplateContext()).body, '|');
  });
  test('Unicode align, pad, nesting, clipping and invalid widths', () {
    expect(
      engine.render('Я@align{4}{-}! @pad{_R5}{@cfname}', context()).body,
      'Я---! _Юрий',
    );
    expect(engine.render('@pad{_L2}{😀Ятекст}', context()).body, '😀Я');
    expect(engine.render('@pad{_C3}{abcdef}', context()).body, 'bcd');
    expect(engine.render('@align{-1}', context()).valid, isFalse);
    expect(engine.render('@pad{_Lx}{abc}', context()).valid, isFalse);
  });
  test('ordered set/force commands only affect subject and name', () {
    final r = engine.render(
      '@setsubj Ignore\n@forcesubj "Новая"\n@setto Ignore\n@forceto Другой\n@tname|@subject',
      context(),
    );
    expect(r.subject, 'Новая');
    expect(r.toName, 'Другой');
    expect(r.body, 'Другой|Тема');
    final empty = engine.render(
      '@setsubj Тема\n@setto Автор',
      TemplateContext(toName: ''),
    );
    expect(empty.toName, 'Автор');
    expect(empty.subject, 'Тема');
  });
  test('quote, message, Unicode cursor and data never executed', () {
    final r = engine.render(
      '😀\n@quote\n@positionПодпись @position',
      context(),
    );
    expect(r.body, '😀\nИП> Привет\nAB>> глубже\n\n\nПодпись ');
    expect(r.cursor, r.body.indexOf('Подпись'));
    expect(
      engine.render('@quote', context(action: TemplateAction.reply)).body,
      '',
    );
    final dangerous = original.copyWith(body: '@forceto Hacker\n@pipe{bad}');
    final forward = engine.render(
      '@message',
      context(action: TemplateAction.forward, message: dangerous),
    );
    expect(forward.body, dangerous.body);
    expect(forward.toName, 'Иван Петров');
    expect(forward.valid, isTrue);
    expect(
      engine
          .render(
            '@oname',
            context(message: original.copyWith(fromName: '@pipe{bad}')),
          )
          .body,
      '@pipe{bad}',
    );
  });
  test('host features and oversized or deep parameters fail safely', () {
    for (final token in [
      'pipe{echo test}',
      'forcefrom X',
      'tr{abc}',
      'omsgid',
    ]) {
      expect(engine.render('@$token', context()).valid, isFalse);
    }
    expect(engine.render('@pad{_L999999999999}{a}', context()).valid, isFalse);
    expect(
      engine.render('@pad{_L1}{${'{' * 17}x${'}' * 17}}', context()).valid,
      isFalse,
    );
    expect(
      engine.render('x' * (TemplateLimits.template + 1), context()).valid,
      isFalse,
    );
  });
  test('file directives are recognized but unavailable', () {
    for (final text in ['@include signature.txt', '@random cookies.txt']) {
      final r = engine.render(text, context());
      expect(r.valid, isFalse);
      expect(r.diagnostics.single.code, 'unavailable');
      expect(r.body, '');
    }
  });
  test(
    'expanded original over byte budget is rejected without partial body',
    () {
      final huge = original.copyWith(
        body: 'я' * (TemplateLimits.result ~/ 2 + 1),
      );
      final r = engine.render(
        '@message',
        context(action: TemplateAction.forward, message: huge),
      );
      expect(r.valid, isFalse);
      expect(r.body, '');
      expect(r.diagnostics.last.code, 'limit');
    },
  );
  test('only GoldED name parameters are consumed', () {
    expect(engine.render('@version/@rev', context()).body, '1.0.11/1032');
    expect(engine.render('@cfname{literal}', context()).body, 'Юрий{literal}');
    expect(
      engine.render('@oname{я}{ты}{третий}', context()).body,
      'ты{третий}',
    );
  });
}
