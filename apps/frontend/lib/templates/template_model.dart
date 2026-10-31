import '../models/conference.dart';
import '../models/message.dart';

enum TemplateAction { newMessage, reply, quoted, forward }

enum TemplateSupport { supported, inactive, unavailable }

class TemplateDiagnostic {
  final String source, code, message;
  final int line, column;
  final bool error;
  const TemplateDiagnostic(
    this.source,
    this.line,
    this.column,
    this.code,
    this.message, {
    this.error = true,
  });
  @override
  String toString() => '$source:$line:$column: $message';
}

class TemplateContext {
  final TemplateAction action;
  final AreaKind kind;
  final Message? original;
  final String name, address, toName, toAddress, subject;
  final String area, description, originalArea, originalDescription;
  final String version, revision, platform, tagline, origin;
  final DateTime now;
  final Duration uptime;
  TemplateContext({
    this.action = TemplateAction.newMessage,
    this.kind = AreaKind.echo,
    this.original,
    this.name = '',
    this.address = '',
    this.toName = 'All',
    this.toAddress = '',
    this.subject = '',
    this.area = '',
    this.description = '',
    this.originalArea = '',
    this.originalDescription = '',
    this.version = '',
    this.revision = '',
    this.platform = '',
    this.tagline = '',
    this.origin = '',
    this.uptime = Duration.zero,
    DateTime? now,
  }) : now = now ?? DateTime.now();
}

class TemplateResult {
  final String body, subject, toName;
  final int cursor;
  final List<TemplateDiagnostic> diagnostics;
  bool get valid => !diagnostics.any((d) => d.error);
  const TemplateResult(
    this.body,
    this.subject,
    this.toName,
    this.cursor,
    this.diagnostics,
  );
}

/// One registry drives recognition, compatibility diagnostics and UI help.
final templateTokens = <String, TemplateSupport>{
  for (final name
      in ('new reply quoted forward notforward net echo local moderator '
              'quote message position setsubj forcesubj setto forceto '
              'oname ofname olname oaddr o3daddr dname dfname dlname daddr d3daddr '
              'cname cfname clname caddr c3daddr fname ffname flname faddr f3daddr '
              'tname tfname tlname taddr t3daddr pseudo tpseudo fpseudo cpseudo opseudo dpseudo '
              'oecho odesc cecho cdesc odate otime odtime cdate ctime cdtime ctzoffset '
              'subject version ver rev pid longpid widepid osver osslash uptime '
              'tagline tearline origin align pad')
          .split(' '))
    name: TemplateSupport.supported,
  for (final name in 'changed moved comment quotebuf write header'.split(' '))
    name: TemplateSupport.inactive,
  for (final name
      in ('otzoffset include random tr setfrom forcefrom pipe attrib spellchecker xlatexport '
              'loadlanguage msgno msgs omsgid omessageid ofrom oto cfrom cto dpgp fpgp attr '
              'areatype areapath areaname')
          .split(' '))
    name: TemplateSupport.unavailable,
};

const templateConditions = {
  'new',
  'reply',
  'quoted',
  'forward',
  'notforward',
  'net',
  'echo',
  'local',
  'moderator',
  'changed',
  'moved',
  'comment',
  'quotebuf',
  'write',
  'header',
};
const templateCommands = {
  'setsubj',
  'forcesubj',
  'setto',
  'forceto',
  'include',
  'random',
  'setfrom',
  'forcefrom',
  'attrib',
  'spellchecker',
  'xlatexport',
  'loadlanguage',
};
String templateLf(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
