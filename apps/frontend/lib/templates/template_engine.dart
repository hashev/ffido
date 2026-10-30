import 'dart:convert';
import 'dart:math' show max;

import '../models/conference.dart';
import '../utils/ftn_text.dart';
import 'template_model.dart';
export 'template_model.dart';

class TemplateLimits {
  static const template = 64 * 1024, result = 1024 * 1024;
  static void check(String text) {
    if (utf8.encode(text).length > template) {
      throw const FormatException('Шаблон больше 64 КиБ');
    }
  }
}

class TemplateEngine {
  TemplateResult render(String template, TemplateContext context) {
    final run = _Run(context);
    try {
      TemplateLimits.check(template);
      run.lines(templateLf(template), 'шаблон');
    } on FormatException catch (e) {
      run.issue('шаблон', 1, 1, 'limit', e.message);
      run.output.clear();
      run.cursor = null;
    }
    return TemplateResult(
      run.output.toString(),
      run.subject,
      run.toName,
      run.cursor ?? run.output.length,
      List.unmodifiable(run.diagnostics),
    );
  }

  /// Validate every reachable action and area.
  List<TemplateDiagnostic> validate(String template) {
    final found = <String, TemplateDiagnostic>{};
    for (final action in TemplateAction.values) {
      for (final kind in [AreaKind.echo, AreaKind.netmail, AreaKind.local]) {
        final run = _Run(
          TemplateContext(action: action, kind: kind, name: 'moderator'),
        );
        try {
          TemplateLimits.check(template);
          run.lines(templateLf(template), 'шаблон');
        } on FormatException catch (e) {
          run.issue('шаблон', 1, 1, 'limit', e.message);
        }
        for (final d in run.diagnostics) {
          found['${d.source}:${d.line}:${d.column}:${d.code}'] = d;
        }
      }
    }
    return found.values.toList();
  }
}

class _Token {
  final String name;
  final int start, end;
  final List<String> args;
  _Token(this.name, this.start, this.end, this.args);
}

final _names = templateTokens.keys.toList()
  ..sort((a, b) => b.length.compareTo(a.length));
final _word = RegExp(r'[A-Za-z0-9_]');
final _unknown = RegExp(r'[A-Za-z][A-Za-z0-9_]*');

class _Run {
  final TemplateContext c;
  final output = StringBuffer();
  final diagnostics = <TemplateDiagnostic>[];
  late String subject = c.subject, toName = c.toName;
  int? cursor;
  int outputBytes = 0;
  _Run(this.c);

  void issue(
    String source,
    int line,
    int column,
    String code,
    String message, {
    bool error = true,
  }) => diagnostics.add(
    TemplateDiagnostic(source, line, column, code, message, error: error),
  );

  bool condition(String name) => switch (name) {
    'new' => c.action == TemplateAction.newMessage,
    'reply' => c.action == TemplateAction.reply,
    'quoted' => c.action == TemplateAction.quoted,
    'forward' => c.action == TemplateAction.forward,
    'notforward' => c.action != TemplateAction.forward,
    'net' => c.kind == AreaKind.netmail,
    'echo' => c.kind == AreaKind.echo,
    'local' => c.kind != AreaKind.echo && c.kind != AreaKind.netmail,
    'moderator' => c.name.toLowerCase().contains('moderator'),
    _ => false,
  };

  List<_Token> scan(String text, String source, int line, {int depth = 0}) {
    if (depth > 16) {
      throw const FormatException('Вложенность параметров больше 16');
    }
    final tokens = <_Token>[];
    for (var i = 0; i < text.length;) {
      if (text[i] != '@') {
        i++;
        continue;
      }
      final start = i++;
      if (i < text.length && text[i] == '@') {
        tokens.add(_Token('@', start, ++i, []));
        continue;
      }
      final lower = text.substring(i).toLowerCase();
      String? name;
      for (final candidate in _names) {
        if (!lower.startsWith(candidate)) continue;
        final end = i + candidate.length;
        if (templateConditions.contains(candidate) ||
            templateCommands.contains(candidate) ||
            end == text.length ||
            !_word.hasMatch(text[end])) {
          name = candidate;
          break;
        }
      }
      if (name == null) {
        final match = _unknown.matchAsPrefix(text, i);
        if (match == null) {
          tokens.add(_Token('@', start, i, []));
          continue;
        }
        name = match.group(0)!;
        i = match.end;
        tokens.add(_Token(name, start, i, []));
        continue;
      }
      i += name.length;
      final args = <String>[];
      final maxArgs = switch (name) {
        'align' || 'pad' => 2,
        'pipe' || 'tr' => 1,
        'oname' || 'ofname' || 'olname' || 'opseudo' => 2,
        'dname' ||
        'dfname' ||
        'dlname' ||
        'tname' ||
        'tfname' ||
        'tlname' ||
        'pseudo' ||
        'tpseudo' ||
        'dpseudo' => 3,
        _ => name.endsWith('addr') ? 1 : 0,
      };
      while (args.length < maxArgs && i < text.length && text[i] == '{') {
        final begin = ++i;
        var nested = 1;
        while (i < text.length && nested > 0) {
          if (text[i] == '{') nested++;
          if (nested + depth > 16) {
            throw const FormatException('Вложенность параметров больше 16');
          }
          if (text[i] == '}') nested--;
          i++;
        }
        if (nested != 0) {
          issue(source, line, begin, 'braces', 'Не закрыта фигурная скобка');
          args.add(text.substring(begin));
        } else {
          args.add(text.substring(begin, i - 1));
        }
      }
      tokens.add(_Token(name, start, i, args));
    }
    return tokens;
  }

  void append(String value) {
    outputBytes += utf8.encode(value).length;
    if (outputBytes > TemplateLimits.result) {
      throw const FormatException('Результат шаблона больше 1 МиБ');
    }
    output.write(value);
  }

  void lines(String text, String source) {
    final parts = text.split('\n');
    for (var n = 0; n < parts.length; n++) {
      final line = parts[n];
      if (n == parts.length - 1 && line.isEmpty) break;
      if (line.trimLeft().startsWith(';')) continue;
      final tokens = scan(line, source, n + 1);
      var skip = false;
      for (final t in tokens.where(
        (t) => templateConditions.contains(t.name),
      )) {
        if (templateTokens[t.name] == TemplateSupport.inactive) {
          issue(
            source,
            n + 1,
            t.start + 1,
            'inactive',
            '@${t.name}: режим GoldED не используется в FFIDO',
            error: false,
          );
        }
        if (!condition(t.name)) skip = true;
      }
      if (skip) continue;
      final commands = tokens.where((t) => templateCommands.contains(t.name));
      if (commands.isNotEmpty) {
        final t = commands.first;
        if (templateTokens[t.name] == TemplateSupport.unavailable) {
          unavailable(t, source, n + 1);
          continue;
        }
        final value = expand(line.substring(t.end), source, n + 1).trim();
        switch (t.name) {
          case 'setsubj':
          case 'forcesubj':
          case 'setto':
          case 'forceto':
            final clean =
                value.length >= 2 &&
                    ((value.startsWith('"') && value.endsWith('"')) ||
                        (value.startsWith("'") && value.endsWith("'")))
                ? value.substring(1, value.length - 1)
                : value;
            if (t.name.endsWith('subj')) {
              if (subject.trim().isEmpty || t.name == 'forcesubj') {
                subject = clean;
              }
            } else if (toName.trim().isEmpty || t.name == 'forceto') {
              toName = clean;
            }
        }
        continue;
      }

      final rendered = expand(line, source, n + 1, baseOffset: output.length);
      append(rendered);
      if (n < parts.length - 1) append('\n');
    }
  }

  void unavailable(_Token t, String source, int line) => issue(
    source,
    line,
    t.start + 1,
    'unavailable',
    const {'include', 'random'}.contains(t.name)
        ? '@${t.name}: внешние файлы не поддерживаются; вставьте нужный текст прямо в шаблон'
        : '@${t.name}: команда ОС, функция GoldED или данные, недоступные в FFIDO',
  );

  String expand(
    String text,
    String source,
    int line, {
    int depth = 0,
    int baseOffset = 0,
  }) {
    final result = StringBuffer();
    var end = 0;
    for (final t in scan(text, source, line, depth: depth)) {
      result.write(text.substring(end, t.start));
      end = t.end;
      if (t.name == '@') {
        result.write('@');
        continue;
      }
      final support = templateTokens[t.name];
      if (support == null) {
        issue(
          source,
          line,
          t.start + 1,
          'unknown',
          'Неизвестная конструкция @${t.name}; для текста используйте @@',
        );
        continue;
      }
      if (support == TemplateSupport.unavailable) {
        unavailable(t, source, line);
        continue;
      }
      if (templateConditions.contains(t.name)) continue;
      switch (t.name) {
        case 'position':
          cursor ??= baseOffset + result.length;
        case 'quote':
          if (c.action == TemplateAction.quoted && c.original != null) {
            result.write(quoteReply(c.original!.body, c.original!.fromName));
          }
        case 'message':
          if (c.action == TemplateAction.forward) {
            result.write(c.original?.body ?? '');
          }
        case 'align':
        case 'pad':
          if (t.args.isEmpty) {
            issue(
              source,
              line,
              t.start + 1,
              'format',
              '@${t.name}: нужны параметры',
            );
            continue;
          }
          if (t.name == 'align') {
            final width = int.tryParse(t.args[0]);
            final fill = t.args.length > 1 ? t.args[1] : ' ';
            if (width == null ||
                width < 0 ||
                width > TemplateLimits.result ||
                fill.runes.length != 1) {
              issue(
                source,
                line,
                t.start + 1,
                'format',
                'Неверная ширина или символ заполнения',
              );
              continue;
            }
            final count = max(0, width - result.toString().runes.length);
            result.write(fill * count);
          } else {
            final match = RegExp(
              r'^(.)([LlRrCc])([0-9]+)$',
              unicode: true,
            ).firstMatch(t.args[0]);
            final width = match == null ? null : int.tryParse(match[3]!);
            if (match == null ||
                width == null ||
                width > TemplateLimits.result ||
                t.args.length != 2) {
              issue(
                source,
                line,
                t.start + 1,
                'format',
                'Неверный формат @pad{_L10}{текст}',
              );
              continue;
            }
            var chars = expand(
              t.args[1],
              source,
              line,
              depth: depth + 1,
            ).runes.toList();
            final alignment = match[2]!.toUpperCase();
            if (chars.length > width) {
              final start = alignment == 'L'
                  ? 0
                  : alignment == 'R'
                  ? chars.length - width
                  : (chars.length - width) ~/ 2;
              chars = chars.sublist(start, start + width);
            }
            final diff = width - chars.length;
            final left = alignment == 'L'
                ? 0
                : alignment == 'R'
                ? diff
                : diff ~/ 2;
            result.write(
              '${match[1]! * left}${String.fromCharCodes(chars)}${match[1]! * (diff - left)}',
            );
          }
        default:
          result.write(value(t, source, line));
      }
      if (result.length > TemplateLimits.result) {
        throw const FormatException('Результат шаблона больше 1 МиБ');
      }
    }
    result.write(text.substring(end));
    return result.toString();
  }

  String first(String value) => value.trim().split(RegExp(r'\s+')).first;
  String last(String value) => value.trim().split(RegExp(r'\s+')).last;
  bool eq(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
  String value(_Token t, String source, int line) {
    final o = c.original;
    final n = t.name;
    String selected(String text, List<bool> flags, int limit) {
      for (var i = 0; i < t.args.length && i < flags.length; i++) {
        if (flags[i]) text = t.args[i];
      }
      return limit == 0 ? text : String.fromCharCodes(text.runes.take(limit));
    }

    final byMe = o != null && eq(o.fromName, c.name);
    final byYou = o != null && eq(o.fromName, toName);
    final toMe = o != null && eq(o.toName, c.name);
    final toYou = o != null && eq(o.toName, toName);
    final originalAll = o != null && eq(o.toName, 'All');
    final names = <String, String>{
      'oname': o?.fromName ?? '',
      'ofname': first(o?.fromName ?? ''),
      'olname': last(o?.fromName ?? ''),
      'dname': o?.toName ?? '',
      'dfname': first(o?.toName ?? ''),
      'dlname': last(o?.toName ?? ''),
      'cname': c.name,
      'cfname': first(c.name),
      'clname': last(c.name),
      'fname': c.name,
      'ffname': first(c.name),
      'flname': last(c.name),
      'tname': toName,
      'tfname': first(toName),
      'tlname': last(toName),
    };
    if (names.containsKey(n)) {
      final flags = n.startsWith('o')
          ? [byMe, byYou]
          : n.startsWith('d')
          ? [toMe, toYou, originalAll]
          : n.startsWith('t')
          ? [eq(toName, c.name), false, eq(toName, 'All')]
          : <bool>[];
      return selected(
        names[n]!,
        flags,
        n == 'oname' ||
                n == 'dname' ||
                n == 'cname' ||
                n == 'fname' ||
                n == 'tname'
            ? 34
            : 0,
      );
    }
    if (n.endsWith('addr')) {
      var address = switch (n[0]) {
        'o' => o?.fromAddress ?? '',
        'd' => o?.toAddress ?? '',
        't' => c.toAddress,
        _ => c.address,
      };
      if (n.contains('3d')) {
        address = address.replaceFirst(RegExp(r'\.[0-9]+(?=@|$)'), '');
      }
      if (!t.args.contains('domain')) address = address.split('@').first;
      return String.fromCharCodes(address.runes.take(19));
    }
    if (n.endsWith('pseudo')) {
      String pseudo(String text) => text.trim().split(RegExp(r'[\s@.]')).first;
      final f = pseudo(c.name),
          target = eq(toName, 'All') ? '' : pseudo(toName);
      final text = switch (n) {
        'fpseudo' || 'cpseudo' => f,
        'opseudo' =>
          byMe
              ? f
              : byYou
              ? target
              : '',
        'dpseudo' =>
          toMe
              ? f
              : toYou
              ? target
              : '',
        _ => target,
      };
      return selected(
        text,
        n == 'opseudo'
            ? [byMe, byYou]
            : n == 'dpseudo'
            ? [toMe, toYou, originalAll]
            : n == 'pseudo' || n == 'tpseudo'
            ? [false, false, eq(toName, 'All')]
            : [],
        0,
      );
    }
    String date(DateTime? d) => d == null
        ? ''
        : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    String time(DateTime? d) => d == null
        ? ''
        : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    final old = o?.date.toLocal();
    if (const {'tagline', 'tearline', 'origin'}.contains(n)) {
      issue(
        source,
        line,
        t.start + 1,
        'footer',
        'Явная вставка @$n может дублировать серверное оформление',
        error: false,
      );
    }
    final offset = c.now.timeZoneOffset;
    final minutes = offset.inMinutes.abs();
    return switch (n) {
      'oecho' => c.originalArea.isEmpty ? c.area : c.originalArea,
      'odesc' =>
        c.originalDescription.isEmpty ? c.description : c.originalDescription,
      'cecho' => c.area,
      'cdesc' => c.description,
      'subject' =>
        c.action == TemplateAction.newMessage ? subject : o?.subject ?? '',
      'odate' => date(old),
      'otime' => time(old),
      'odtime' => old == null ? '' : '${date(old)} ${time(old)}',
      'cdate' => date(c.now),
      'ctime' => time(c.now),
      'cdtime' => '${date(c.now)} ${time(c.now)}',
      'ctzoffset' =>
        '${offset.isNegative ? '-' : '+'}${(minutes ~/ 60).toString().padLeft(2, '0')}${(minutes % 60).toString().padLeft(2, '0')}',
      'version' || 'ver' => c.version,
      'rev' => c.revision,
      'pid' || 'longpid' || 'widepid' => 'FFIDO ${c.version}',
      'osver' || 'osslash' => c.platform,
      'uptime' => c.uptime.toString().split('.').first,
      'tagline' || 'tearline' => c.tagline,
      'origin' => c.origin,
      _ => '',
    };
  }
}
