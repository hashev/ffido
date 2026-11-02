import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fixnum/fixnum.dart';

import '../api/api_exceptions.dart';
import '../api/api_transport.dart';
import '../api/generated/ffido/v1/ffido.pb.dart' as wire;
import '../api/model_mapping.dart';
import '../models/conference.dart';
import '../repositories/message_repository.dart';
import '../repositories/personal_message_filters_repository.dart';
import '../utils/refresh_on_resume.dart';

String newPersonalRuleId() {
  final id = MessageRepository.newOperationId();
  return '${id.substring(0, 8)}-${id.substring(8, 12)}-4${id.substring(13, 16)}-8${id.substring(17, 20)}-${id.substring(20)}';
}

String personalRuleDescription(wire.PersonalMessageFilter rule) => [
  if (rule.authorContains.isNotEmpty) 'Автор: ${rule.authorContains}',
  if (rule.addressEquals.isNotEmpty) 'Адрес: ${rule.addressEquals}',
  if (rule.subjectContains.isNotEmpty) 'Тема: ${rule.subjectContains}',
].join(' · ');

class PersonalMessageFiltersScreen extends StatefulWidget {
  final PersonalMessageFiltersRepository repository;
  final String? conferenceId;
  final wire.PersonalMessageFilter? initialRule;
  const PersonalMessageFiltersScreen({
    super.key,
    required this.repository,
    this.conferenceId,
    this.initialRule,
  });
  @override
  State<PersonalMessageFiltersScreen> createState() =>
      _PersonalMessageFiltersScreenState();
}

class _PersonalMessageFiltersScreenState
    extends State<PersonalMessageFiltersScreen>
    with RefreshOnResume<PersonalMessageFiltersScreen> {
  final List<wire.PersonalMessageFilter> draft = [];
  List<Conference> conferences = [];
  wire.PersonalMessageFilterSet? remote;
  wire.ReplacePersonalMessageFiltersRequest? pending;
  late final StreamSubscription<int> subscription;
  late final int epoch;
  bool busy = true, initialized = false, dirty = false, conflict = false;
  bool needsReload = false, initialOffered = false;
  String? error;
  final cancellation = RpcCancellation();
  @override
  void initState() {
    super.initState();
    epoch = widget.repository.epoch;
    subscription = widget.repository.sessionChanges.listen((_) {
      draft.clear();
      remote = null;
      pending = null;
      unawaited(cancellation.cancel());
      if (mounted) {
        final nav = Navigator.of(context), route = ModalRoute.of(context)!;
        nav.popUntil((r) => r == route || r.isFirst);
        if (route.isActive) nav.removeRoute(route);
      }
    });
    unawaited(load());
  }

  @override
  Future<void> refreshOnResume() => load();
  @override
  bool get resumeRefreshEnabled => !busy;
  bool get valid =>
      mounted && epoch == widget.repository.epoch && !cancellation.isCancelled;
  Future<void> load() async {
    if (!valid) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.refresh(cancellation: cancellation);
      if (!valid) return;
      if (widget.repository.supported == false) {
        setState(() {
          busy = false;
          error = 'Персональные фильтры недоступны. Обновите сервер.';
        });
        return;
      }
      final current = widget.repository.snapshot!;
      final areas = <Conference>[];
      var offset = 0;
      while (true) {
        final page = await widget.repository.api.listConferences(
          wire.ListConferencesRequest(
            page: wire.PageRequest(offset: Int64(offset), limit: 100),
            sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
          ),
          cancellation: cancellation,
        );
        if (!valid) return;
        areas.addAll(
          page.conferences
              .map(mapConference)
              .where(
                (a) =>
                    a.kind == AreaKind.echo &&
                    a.canRead &&
                    !a.unsupportedFormat,
              ),
        );
        if (!page.hasMore) break;
        if (page.conferences.isEmpty) {
          throw const ServerException(message: 'Некорректная страница эх');
        }
        offset += page.conferences.length;
      }
      setState(() {
        final previousRevision = remote?.revision;
        remote = current;
        conferences = areas;
        if (!initialized || !dirty) {
          draft
            ..clear()
            ..addAll(current.rules.map((r) => r.deepCopy()));
        }
        if (dirty &&
            previousRevision != null &&
            previousRevision != current.revision) {
          conflict = true;
          pending = null;
        }
        needsReload = false;
        initialized = true;
        busy = false;
      });
      if (!initialOffered &&
          widget.initialRule != null &&
          !dirty &&
          draft.every((r) => r.ruleId != widget.initialRule!.ruleId)) {
        initialOffered = true;
        await edit(widget.initialRule!.deepCopy());
      }
    } catch (e) {
      if (valid) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  void change(VoidCallback action) {
    setState(() {
      action();
      dirty = true;
      pending = null;
    });
  }

  Future<void> edit([wire.PersonalMessageFilter? original]) async {
    final next = await showDialog<wire.PersonalMessageFilter>(
      context: context,
      builder: (_) => _RuleEditor(
        original: original,
        conferences: conferences,
        conferenceId: widget.conferenceId,
      ),
    );
    if (!valid || next == null) return;
    change(() {
      final i = draft.indexWhere((r) => r.ruleId == next.ruleId);
      if (i < 0) {
        draft.add(next);
      } else {
        draft[i] = next;
      }
    });
  }

  Future<void> save() async {
    if (busy || needsReload || remote == null || !dirty) return;
    pending ??= wire.ReplacePersonalMessageFiltersRequest(
      expectedRevision: remote!.revision,
      operationId: MessageRepository.newOperationId(),
      rules: draft.map((r) => r.deepCopy()),
    );
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.save(pending!, cancellation: cancellation);
      if (!valid) return;
      setState(() {
        remote = widget.repository.snapshot;
        draft
          ..clear()
          ..addAll(remote!.rules.map((r) => r.deepCopy()));
        pending = null;
        dirty = false;
        conflict = false;
        busy = false;
      });
    } catch (e) {
      if (valid) {
        setState(() {
          busy = false;
          error = e is ApiException && e.statusCode == 10
              ? 'Правила изменены на другом устройстве. Черновик сохранён; загрузите актуальные правила перед повтором.'
              : '$e';
          if (e is ApiException && e.statusCode == 10) {
            conflict = true;
            needsReload = true;
            pending = null;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(cancellation.cancel());
    unawaited(subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Персональные фильтры'),
      actions: [
        IconButton(
          tooltip: 'Обновить правила',
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(error!),
                TextButton(
                  onPressed: busy ? null : load,
                  child: const Text('Загрузить актуальные'),
                ),
              ],
            ),
          ),
        if (remote != null && conflict)
          ExpansionTile(
            title: const Text('Актуальные правила сервера'),
            subtitle: Text(
              'Ревизия ${remote!.revision.toStringUnsigned()}. Ваш набор ниже.',
            ),
            children: [
              for (final r in remote!.rules)
                ListTile(
                  title: Text(personalRuleDescription(r)),
                  subtitle: Text(
                    r.conferenceId.isEmpty ? 'Все эхи' : r.conferenceId,
                  ),
                ),
            ],
          ),
        if (widget.repository.supported != false)
          Expanded(
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Правила действуют только в эхах. Условия одного правила — И, разные правила — ИЛИ. Свернутые письма остаются в счётчиках.',
                  ),
                ),
                if (initialized && draft.isEmpty)
                  const ListTile(title: Text('Правил нет')),
                for (final rule in draft)
                  ListTile(
                    title: Text(personalRuleDescription(rule)),
                    subtitle: Text(
                      rule.conferenceId.isEmpty ? 'Все эхи' : rule.conferenceId,
                    ),
                    leading: Checkbox(
                      value: rule.enabled,
                      onChanged: busy
                          ? null
                          : (v) => change(() => rule.enabled = v!),
                    ),
                    onTap: busy ? null : () => edit(rule),
                    trailing: IconButton(
                      tooltip: 'Удалить правило',
                      onPressed: busy
                          ? null
                          : () => change(() => draft.remove(rule)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
          ),
        if (widget.repository.supported != false)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: busy || draft.length >= 200
                        ? null
                        : () => edit(),
                    child: const Text('Добавить правило'),
                  ),
                  FilledButton(
                    onPressed:
                        busy ||
                            !dirty ||
                            needsReload ||
                            (conflict &&
                                remote?.revision == pending?.expectedRevision)
                        ? null
                        : save,
                    child: Text(
                      conflict
                          ? 'Сохранить мой набор вместо актуального'
                          : 'Сохранить правила',
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _RuleEditor extends StatefulWidget {
  final wire.PersonalMessageFilter? original;
  final List<Conference> conferences;
  final String? conferenceId;
  const _RuleEditor({
    this.original,
    required this.conferences,
    this.conferenceId,
  });
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final TextEditingController author, address, subject;
  late String scope;
  late bool enabled;
  String? error;
  @override
  void initState() {
    super.initState();
    final r = widget.original;
    author = TextEditingController(text: r?.authorContains);
    address = TextEditingController(text: r?.addressEquals);
    subject = TextEditingController(text: r?.subjectContains);
    scope = r?.conferenceId ?? widget.conferenceId ?? '';
    enabled = r?.enabled ?? true;
  }

  @override
  void dispose() {
    author.dispose();
    address.dispose();
    subject.dispose();
    super.dispose();
  }

  void save() {
    final rule = wire.PersonalMessageFilter(
      ruleId: widget.original?.ruleId ?? newPersonalRuleId(),
      enabled: enabled,
      scope: scope.isEmpty
          ? wire
                .PersonalMessageFilterScope
                .PERSONAL_MESSAGE_FILTER_SCOPE_ALL_ECHOS
          : wire
                .PersonalMessageFilterScope
                .PERSONAL_MESSAGE_FILTER_SCOPE_CONFERENCE,
      conferenceId: scope,
      authorContains: author.text.trim(),
      addressEquals: address.text.trim(),
      subjectContains: subject.text.trim(),
    );
    try {
      PersonalMessageFiltersRepository.validateRule(rule);
      Navigator.pop(context, rule);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = {for (final c in widget.conferences) c.id: c.name};
    if (scope.isNotEmpty) {
      options.putIfAbsent(scope, () => '$scope (сохранённая эха)');
    }
    return AlertDialog(
      title: const Text('Правило сворачивания'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: scope,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Область действия',
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Все эхи')),
                  for (final e in options.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => scope = v!),
              ),
              TextField(
                controller: author,
                decoration: const InputDecoration(
                  labelText: 'Имя автора содержит',
                ),
              ),
              TextField(
                controller: address,
                decoration: const InputDecoration(
                  labelText: 'Точный FTN-адрес отправителя',
                ),
              ),
              TextField(
                controller: subject,
                decoration: const InputDecoration(labelText: 'Тема содержит'),
              ),
              SwitchListTile(
                title: const Text('Правило включено'),
                value: enabled,
                onChanged: (v) => setState(() => enabled = v),
              ),
              if (error != null) Text(error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: save, child: const Text('Готово')),
      ],
    );
  }
}
