import 'package:flutter/material.dart';

import 'dart:convert';

import '../repositories/backend_directory.dart';
import '../repositories/web_workspace.dart';
import '../widgets/adaptive_layout.dart';
import '../api/api_exceptions.dart';
import '../files/uue_files.dart';
import '../repositories/uue_repository.dart';
import '../main.dart' show messageRepository, conferenceRepository;
import 'message_screen.dart' show openWebDraft;
import 'settings.dart';

class WebSettings extends StatefulWidget {
  const WebSettings({super.key, required this.workspace});
  final WebWorkspace workspace;
  @override
  State<WebSettings> createState() => _WebSettingsState();
}

class _WebSettingsState extends State<WebSettings> {
  final name = TextEditingController(),
      address = TextEditingController(),
      password = TextEditingController();
  BackendEntry? node;
  bool busy = false;
  String message = '';
  WebWorkspace get workspace => widget.workspace;
  @override
  void initState() {
    super.initState();
    message = workspace.notice;
    workspace.notice = '';
    node = workspace.selected?.node;
    if (node == null && workspace.telegram.initData.isEmpty) {
      try {
        final last = jsonDecode(
          workspace.preferences.getString(WebWorkspace.lastKey) ?? 'null',
        );
        if (last is List &&
            last.length == 3 &&
            last[0] is String &&
            last[1] is String &&
            last[2] is String) {
          final previous = workspace.directory.current?.find(last[0] as String);
          if (previous != null &&
              workspace.directory.isAccepted(previous) &&
              previous.endpoint.toString() == last[1]) {
            node = previous;
            address.text = last[2] as String;
          }
        }
      } catch (_) {
        /* A stale selection never authorizes a connection. */
      }
    }
    final hint = workspace.telegram.startNode;
    if (hint != null && hint.isNotEmpty) {
      node = workspace.directory.current?.find(hint);
    }
    workspace.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    workspace.removeListener(changed);
    name.dispose();
    address.dispose();
    password.dispose();
    super.dispose();
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Подтвердить'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) setState(() => message = error.message);
    } on StateError catch (error) {
      if (mounted) setState(() => message = error.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Операция не завершена. Проверьте данные и сеть. Если вход Telegram устарел, переоткройте Mini App.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (!workspace.client.hasToken &&
            workspace.selected == null &&
            Navigator.canPop(context)) {
          workspace.notice = message;
          Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
        }
      }
    }
  }

  Future<void> choose(BackendEntry entry) async {
    final previous = workspace.directory.acceptedEndpoints[entry.id];
    if (previous != null && previous != entry.endpoint.toString()) {
      if (!await confirm(
        'Перенос узла',
        'Старый адрес: $previous\nНовый адрес: ${entry.endpoint}\nПотребуется новый вход.',
      )) {
        return;
      }
    }
    await workspace.directory.accept(entry);
    if (!mounted) return;
    setState(() {
      node = entry;
      password.clear();
    });
    await workspace.discover(entry);
  }

  void openReader() {
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
  }

  Widget field(
    String label,
    TextEditingController controller, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: controller,
      enabled: !busy,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: label),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final entries = workspace.directory.current?.entries ?? [];
    final active = workspace.selected;
    final drafts = active == null
        ? <Map<String, dynamic>>[]
        : workspace.drafts.list(active.scope);
    return Scaffold(
      appBar: AppBar(title: const Text('Профили FFIDO')),
      body: AdaptiveContent(
        maxWidth: AdaptiveContent.formWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (workspace.directory.stale &&
                workspace.directory.current != null)
              const Text(
                'Используется сохранённый каталог. Обновление недоступно.',
              ),
            OutlinedButton(
              onPressed: busy ? null : () => run(workspace.refresh),
              child: const Text('Обновить каталог'),
            ),
            if (workspace.directory.current == null)
              const Text(
                'Не удалось загрузить каталог узлов. Проверьте сеть и повторите загрузку.',
              ),
            if (entries.isEmpty && workspace.directory.current != null)
              const Text(
                'В каталоге пока нет узлов. После его обновления повторите загрузку.',
              ),
            for (final entry in entries)
              ListTile(
                title: Text(entry.name),
                subtitle: Text('${entry.ftnAddress}\n${entry.endpoint}'),
                selected:
                    node?.id == entry.id && node?.endpoint == entry.endpoint,
                onTap: busy ? null : () => run(() => choose(entry)),
              ),
            for (final error in workspace.errors.entries)
              Text('${error.key}: ${error.value}'),
            if (node != null &&
                !workspace.invalidTelegramProof.contains(node!.id) &&
                workspace.directory.isAccepted(node!) &&
                workspace.directory.current?.find(node!.id)?.endpoint ==
                    node!.endpoint) ...[
              const Divider(),
              Text('Вход на ${node!.name}\n${node!.endpoint}'),
              field('Имя', name),
              field('FTN-адрес', address),
              field('Пароль HPT', password, secret: true),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        try {
                          await workspace.hptLogin(
                            node!,
                            name.text,
                            address.text,
                            password.text,
                          );
                          openReader();
                        } finally {
                          password.clear();
                        }
                      }),
                child: const Text('Войти по HPT-паролю'),
              ),
            ],
            if (workspace.profiles.isNotEmpty) ...[
              const Divider(),
              const Text('Профили'),
              for (final profile in workspace.profiles)
                ListTile(
                  title: Text(
                    '${profile.profile.name} — ${profile.profile.address}',
                  ),
                  subtitle: Text(profile.node.name),
                  trailing:
                      workspace.telegram.initData.isNotEmpty &&
                          workspace.preferences.getBool(
                                workspace.stopped(profile.scope),
                              ) ==
                              true
                      ? TextButton(
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                  await workspace.select(profile);
                                  openReader();
                                }),
                          child: const Text('Войти через Telegram'),
                        )
                      : null,
                  selected: profile.scope == active?.scope,
                  onTap: busy
                      ? null
                      : () => run(() async {
                          if (workspace.telegram.initData.isEmpty &&
                              !workspace.hasRememberedSession(profile)) {
                            setState(() {
                              node = profile.node;
                              name.text = profile.profile.name;
                              address.text = profile.profile.address;
                              message =
                                  'Введите HPT-пароль для выбранного профиля';
                            });
                            return;
                          }
                          await workspace.select(profile);
                          openReader();
                        }),
                ),
            ],
            if (active != null) ...[
              for (final draft in drafts)
                ListTile(
                  title: Text(
                    draft['rpc'] != null
                        ? 'Неподтверждённая отправка'
                        : (draft['subject'] as String? ?? 'Черновик'),
                  ),
                  subtitle: Text(
                    draft['rpc'] as String? ??
                        draft['conferenceName'] as String? ??
                        '',
                  ),
                  trailing: draft['rpc'] != 'CommitUue'
                      ? null
                      : IconButton(
                          tooltip: 'Продолжить UUE с исходным файлом',
                          icon: const Icon(Icons.attach_file),
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                  final limits = await UueRepository(
                                    workspace.client,
                                  ).capabilities();
                                  if (limits == null) {
                                    throw StateError(
                                      'Сервер не поддерживает UUE',
                                    );
                                  }
                                  final file = await uueFiles.pick(
                                    limits.fileBytes,
                                  );
                                  if (file != null) {
                                    await workspace.resumeUue(draft, file);
                                  }
                                }),
                        ),
                  onTap: busy
                      ? null
                      : () => run(() async {
                          if (draft['rpc'] != null) {
                            if (await confirm(
                              'Проверить или повторить?',
                              'Будет использован исходный запрос и прежний ключ операции. Новое письмо автоматически не создаётся.',
                            )) {
                              await workspace.recover(draft);
                              if (mounted) {
                                setState(
                                  () => message = 'Сохранение подтверждено.',
                                );
                              }
                            }
                          } else {
                            await openWebDraft(
                              context,
                              draft,
                              messageRepository,
                              conferenceRepository,
                            );
                          }
                        }),
                ),
              const Divider(),
              Text(
                'Текущий профиль: ${active.profile.address}\n${active.node.name}',
              ),
              FilledButton(
                onPressed: busy ? null : openReader,
                child: const Text('Открыть почту'),
              ),
              if (workspace.telegramSupported[active.node.id] == true) ...[
                if (workspace.telegram.initData.isNotEmpty)
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            if (!await workspace.client.supportsTelegram(
                              active.node.endpoint.toString(),
                            )) {
                              if (mounted) {
                                setState(
                                  () => message =
                                      'Узел поддерживает только HPT-вход.',
                                );
                              }
                              return;
                            }
                            if (!mounted) return;
                            password.clear();
                            final accepted = await showDialog<bool>(
                              context: this.context,
                              builder: (context) => AlertDialog(
                                title: const Text('Привязать Telegram'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Профиль ${active.profile.address}. Существующая привязка будет заменена, её Telegram-сеансы отозваны.',
                                    ),
                                    TextField(
                                      key: const Key('telegram-bind-password'),
                                      controller: password,
                                      obscureText: true,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      decoration: const InputDecoration(
                                        labelText: 'Актуальный пароль HPT',
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Отмена'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Привязать'),
                                  ),
                                ],
                              ),
                            );
                            try {
                              if (accepted == true) {
                                await workspace.client.bindTelegram(
                                  initData: workspace.telegram.initData,
                                  password: password.text,
                                  replaceExisting: true,
                                );
                                if (mounted) {
                                  setState(
                                    () => message = 'Telegram привязан.',
                                  );
                                }
                              }
                            } finally {
                              password.clear();
                            }
                          }),
                    child: const Text('Привязать или заменить Telegram'),
                  ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          if (!await workspace.client.supportsTelegram(
                            active.node.endpoint.toString(),
                          )) {
                            if (mounted) {
                              setState(
                                () => message =
                                    'Узел поддерживает только HPT-вход.',
                              );
                            }
                            return;
                          }
                          final binding = await workspace.client
                              .getTelegramBinding();
                          if (mounted) {
                            setState(
                              () => message = binding.bound
                                  ? 'Telegram привязан.'
                                  : 'Telegram не привязан.',
                            );
                          }
                        }),
                  child: const Text('Проверить привязку'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          if (await confirm(
                            'Отвязать Telegram?',
                            'Будут отозваны все Telegram-сеансы этого профиля и удалены его локальные черновики. Обычные HPT-сеансы сохранятся.',
                          )) {
                            await workspace.signOut(unbind: true);
                          }
                        }),
                  child: const Text('Отвязать Telegram'),
                ),
              ],
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        if (await confirm(
                          'Завершить сеанс?',
                          'Локальные черновики и персональный кеш этого профиля будут удалены. Telegram-привязка сохранится.',
                        )) {
                          await workspace.signOut();
                        }
                      }),
                child: const Text('Завершить сеанс'),
              ),
            ],
            for (final id in workspace.directory.acceptedEndpoints.keys) ...[
              if (workspace.directory.current?.find(id)?.endpoint.toString() !=
                  workspace.directory.acceptedEndpoints[id])
                for (final scope in workspace.drafts.scopesForNode(id))
                  for (final draft
                      in workspace.drafts
                          .list(scope)
                          .where((r) => r['body'] is String))
                    ListTile(
                      title: Text('Локальный черновик узла $id'),
                      subtitle: Text(draft['subject'] as String? ?? ''),
                      onTap: busy
                          ? null
                          : () => showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                scrollable: true,
                                title: const Text(
                                  'Текст сохранённого черновика',
                                ),
                                content: SelectableText(
                                  draft['body'] as String,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Закрыть'),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      await workspace.drafts.remove(
                                        scope,
                                        draft['draftId'] as String,
                                      );
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                      changed();
                                    },
                                    child: const Text('Удалить'),
                                  ),
                                ],
                              ),
                            ),
                    ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        if (await confirm(
                          'Забыть узел $id?',
                          'Локальные сеансы, кеш и черновики всех его профилей будут удалены. Серверные Telegram-привязки сохранятся.',
                        )) {
                          await workspace.forget(id);
                          if (node?.id == id) node = null;
                        }
                      }),
                child: Text('Забыть узел $id'),
              ),
            ],
            if (busy && (ModalRoute.of(context)?.isCurrent ?? true))
              const Center(child: CircularProgressIndicator()),
            if (message.isNotEmpty)
              Semantics(liveRegion: true, child: Text(message)),
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SettingsWidget(
                          client: workspace.client,
                          preferences: workspace.preferences,
                          accountManagedExternally: true,
                        ),
                      ),
                    ),
              child: const Text('Оформление и шаблоны'),
            ),
          ],
        ),
      ),
    );
  }
}
