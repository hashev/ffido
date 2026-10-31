import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/conference.dart';
import '../models/message.dart';
import '../updates/update_controller.dart';
import 'template_engine.dart';
import 'template_settings.dart';

const templateExample =
    'Привет, @tfname!\n@quoted@oname написал @odate @otime:\n@quote\n@position\nС уважением, @cfname\n';
const _actions = [
  'Новое письмо',
  'Ответ без цитаты',
  'Ответ с цитатой',
  'Пересылка',
];

class TemplateSettingsPanel extends StatefulWidget {
  final SharedPreferences? preferences;
  final TemplateSettings? settings;
  const TemplateSettingsPanel({super.key, this.preferences, this.settings});
  @override
  State<TemplateSettingsPanel> createState() => _TemplateSettingsPanelState();
}

class _TemplateSettingsPanelState extends State<TemplateSettingsPanel>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final text = TextEditingController();
  TemplateSettings? settings;
  String saved = '', message = '';
  bool busy = false, loaded = false;
  List<TemplateDiagnostic> diagnostics = [];
  String get snapshot => TemplateBundle(text.text).encode();
  @override
  void initState() {
    super.initState();
    appUpdates.guardExit(this, () => loaded && !busy && snapshot == saved);
    load();
  }

  Future<void> load() async {
    try {
      final store =
          widget.settings ??
          TemplateSettings(
            widget.preferences ?? await SharedPreferences.getInstance(),
          );
      if (!mounted) return;
      settings = store;
      final raw = store.preferences.getString(TemplateSettings.key);
      if (raw != null) {
        final bundle = TemplateBundle.decode(raw);
        text.text = bundle.text;
      }
    } catch (_) {
      message = 'Не удалось прочитать шаблон. Исправьте его или сбросьте настройки шаблона.';
    }
    if (mounted) {
      setState(() {
        loaded = true;
        saved = snapshot;
      });
    }
  }

  @override
  void dispose() {
    appUpdates.removeExitGuard(this);
    text.dispose();
    super.dispose();
  }

  Future<void> save({bool reset = false}) async {
    if (settings == null || busy) return;
    setState(() => busy = true);
    try {
      if (reset) {
        await settings!.reset();
      } else {
        final bundle = TemplateBundle(templateLf(text.text));
        diagnostics = bundle.validate();
        if (diagnostics.any((d) => d.error)) {
          setState(() => message = 'Исправьте ошибки шаблона');
          return;
        }
        await settings!.save(bundle);
      }
      if (!mounted) return;
      setState(() {
        if (reset) {
          text.clear();
          diagnostics = [];
        }
        saved = snapshot;
        message = reset ? 'Шаблон сброшен' : 'Шаблон сохранён';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Не удалось сохранить шаблон; введённый текст сохранён в форме',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Совместимость с GoldED'),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Один .tpl для всех областей. @quoted — ответ с цитатой, @reply — без неё. @quote вставляет FTN-цитату, @message — тело пересылки, @position задаёт курсор. Условия действуют на всю строку; @@ выводит буквальный @.\n\nИмена: c — профиль, f/t — отправитель/получатель черновика, o/d — стороны оригинала. fname/lname — первое/последнее имя. Альтернативы {я}{ты}{всем} выбираются по контексту. Даты dd.MM.yyyy, время HH:mm:ss, локальная зона. Ширины и обрезка используют Unicode.\n\n@include и @random не поддерживаются: подключение внешних файлов отсутствует. Вставьте нужную подпись прямо в текст шаблона.\n\nСмена отправителя, программы ОС, TRANSLATE, внутренние функции и недоступные метаданные GoldED не поддерживаются. Tagline/Origin автоматически добавляет прежний механизм; явная вставка в тело может дублировать оформление. Подробная таблица и примеры — в README клиента.\n',
              ),
              for (final status in TemplateSupport.values) ...[
                Text(switch (status) {
                  TemplateSupport.supported => 'Поддерживаются',
                  TemplateSupport.inactive => 'Неактивные режимы',
                  TemplateSupport.unavailable => 'Недоступны',
                }, style: const TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(
                  templateTokens.entries
                      .where((e) => e.value == status)
                      .map((e) => '@${e.key}')
                      .join(', '),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
  void preview() => showDialog<void>(
    context: context,
    builder: (context) => TemplatePreview(bundle: TemplateBundle(text.text)),
  );
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const Text('Шаблон писем'),
        const Text(
          'Общий .tpl для новых писем, ответов и пересылок. Хранится только на этом устройстве.',
        ),
        TextField(
          key: const Key('message-template'),
          controller: text,
          enabled: loaded && !busy,
          minLines: 6,
          maxLines: null,
          decoration: const InputDecoration(labelText: 'Шаблон GoldED (.tpl)'),
        ),
        Wrap(
          children: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() => text.text = templateExample),
              child: const Text('Вставить пример'),
            ),
            TextButton(
              onPressed: help,
              child: const Text('Справка по шаблонам'),
            ),
          ],
        ),
        OutlinedButton(
          onPressed: busy || !loaded ? null : preview,
          child: const Text('Предпросмотр шаблона'),
        ),
        FilledButton(
          onPressed: busy || !loaded ? null : save,
          child: const Text('Сохранить шаблон'),
        ),
        TextButton(
          onPressed: busy || !loaded ? null : () => save(reset: true),
          child: const Text('Сбросить шаблон'),
        ),
        if (message.isNotEmpty)
          Text(message, key: const Key('template-status')),
        for (final d in diagnostics) Text(d.toString()),
      ],
    );
  }
}

class TemplatePreview extends StatefulWidget {
  final TemplateBundle bundle;
  const TemplatePreview({super.key, required this.bundle});
  @override
  State<TemplatePreview> createState() => _TemplatePreviewState();
}

class _TemplatePreviewState extends State<TemplatePreview> {
  TemplateAction action = TemplateAction.quoted;
  AreaKind kind = AreaKind.echo;
  @override
  Widget build(BuildContext context) {
    final result = TemplateEngine().render(
      widget.bundle.text,
      TemplateContext(
        action: action,
        kind: kind,
        name: 'Юрий Хашев',
        address: '2:5020/100.1',
        toName: 'Иван Петров',
        toAddress: '2:5020/100.2',
        subject: 'Re: Пример',
        area: 'RU.TEST',
        description: 'Тестовая эха',
        originalArea: 'RU.TEST',
        version: 'пример',
        now: DateTime(2026, 10, 30, 13),
        original: action == TemplateAction.newMessage
            ? null
            : Message(
                id: 'example',
                fromName: 'Иван Петров',
                fromAddress: '2:5020/100.2',
                toName: 'Юрий Хашев',
                toAddress: '2:5020/100.1',
                subject: 'Пример',
                body: 'Исходное письмо\nAB> Вложенная цитата',
                date: DateTime(2026, 10, 29, 12),
              ),
      ),
    );
    final diagnostics = TemplateEngine().validate(widget.bundle.text);
    final cursor = result.cursor.clamp(0, result.body.length);
    return AlertDialog(
      title: const Text('Предпросмотр — примерные данные'),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<TemplateAction>(
                key: const Key('template-preview-action'),
                value: action,
                isExpanded: true,
                onChanged: (v) => setState(() => action = v!),
                items: TemplateAction.values
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(_actions[v.index]),
                      ),
                    )
                    .toList(),
              ),
              DropdownButton<AreaKind>(
                value: kind,
                isExpanded: true,
                onChanged: (v) => setState(() => kind = v!),
                items: [AreaKind.echo, AreaKind.netmail, AreaKind.local]
                    .map(
                      (v) =>
                          DropdownMenuItem(value: v, child: Text(v.groupLabel)),
                    )
                    .toList(),
              ),
              Text(
                'Тема: ${result.subject}\nПолучатель: ${result.toName} <2:5020/100.2>',
              ),
              if (result.valid)
                SelectableText(
                  '${result.body.substring(0, cursor)}▏${result.body.substring(cursor)}',
                  key: const Key('template-preview-body'),
                ),
              for (final d in diagnostics) Text(d.toString()),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
