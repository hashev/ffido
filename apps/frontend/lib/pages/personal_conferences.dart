import '../models/conference.dart';
import '../api/api_exceptions.dart';
import '../utils/refresh_on_resume.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_transport.dart';
import '../main.dart';
import '../repositories/account_repository.dart';
import 'message_screen.dart';
import '../repositories/message_repository.dart';

/// Закладки и история используют одинаковую пагинацию и смену сессии.
class PersonalConferences extends StatefulWidget {
  final bool history;
  final AccountRepository? repository;
  final bool active;
  const PersonalConferences({
    super.key,
    required this.history,
    this.repository,
    this.active = true,
  });
  @override
  State<PersonalConferences> createState() => _PersonalConferencesState();
}

class _PersonalConferencesState extends State<PersonalConferences>
    with RefreshOnResume<PersonalConferences> {
  @override
  bool get resumeRefreshEnabled => widget.active;
  @override
  Future<void> refreshOnResume() => load();

  AccountRepository get repository => widget.repository ?? accountRepository;
  List<PersonalConferenceEntry> entries = [];
  bool loading = false, hasMore = false;
  String? error;
  int version = 0;
  RpcCancellation? cancellation;
  late final StreamSubscription<int> subscription;
  final Set<String> removing = {};
  @override
  void initState() {
    super.initState();
    subscription = repository.sessionChanges.listen((_) {
      entries = [];
      removing.clear();
      ++version;
      unawaited(cancellation?.cancel());
      setState(() {});
      if (widget.active) load();
    });
    if (widget.active) load();
  }

  @override
  void didUpdateWidget(covariant PersonalConferences oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) load();
  }

  @override
  void dispose() {
    ++version;
    unawaited(cancellation?.cancel());
    unawaited(subscription.cancel());
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final current = ++version;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final offset = more ? entries.length : 0;
      final page = widget.history
          ? await repository.getHistory(offset: offset, cancellation: token)
          : await repository.getBookmarks(offset: offset, cancellation: token);
      if (!mounted || current != version) return;
      setState(() {
        entries = more ? [...entries, ...page.entries] : page.entries;
        hasMore = page.hasMore;
        loading = false;
      });
    } catch (e) {
      if (!mounted || current != version) return;
      setState(() {
        loading = false;
        error = e.toString();
        if (e is ApiException && e.isAccessDenied) entries = [];
      });
    }
  }

  Future<void> clear() async {
    final current = ++version;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await repository.clearHistory(cancellation: token);
      if (!mounted || current != version) return;
      setState(() {
        entries = [];
        hasMore = false;
        loading = false;
      });
    } catch (e) {
      if (!mounted || current != version) return;
      setState(() {
        loading = false;
        error = e.toString();
        if (e is ApiException && e.isAccessDenied) entries = [];
      });
    }
  }

  Future<void> remove(PersonalConferenceEntry entry) async {
    final id = entry.conference.id;
    if (!removing.add(id)) return;
    final epoch = repository.epoch;
    setState(() {});
    try {
      await repository.removeBookmark(id);
      if (!mounted || epoch != repository.epoch) return;
      await load();
    } catch (e) {
      if (!mounted || epoch != repository.epoch) return;
      setState(() => error = e.toString());
    } finally {
      if (mounted && epoch == repository.epoch) {
        setState(() => removing.remove(id));
      }
    }
  }

  Future<void> open(PersonalConferenceEntry entry) async {
    final epoch = repository.epoch;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageScreen(
          conferenceId: entry.conference.id,
          onAccessDenied: repository.onBookmarksChanged,
          canRead: entry.conference.canRead,
          canPost: entry.conference.canPost,
          kind: entry.conference.kind,
          personalMailbox: entry.conference.personalMailbox,
          conferenceName: entry.conference.name,
          conferenceDescription: entry.conference.description,
          repository: MessageRepository(repository.transport),
        ),
      ),
    );
    if (mounted && epoch == repository.epoch) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.history ? 'История' : 'Закладки'),
      actions: [
        IconButton(
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Обновить',
        ),
        if (widget.history)
          IconButton(
            onPressed: loading ? null : clear,
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Очистить историю',
          ),
      ],
    ),
    body: Column(
      children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(error!),
                TextButton(onPressed: load, child: const Text('Повторить')),
              ],
            ),
          ),
        if (!loading && error == null && entries.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                widget.history ? 'История просмотров пуста' : 'Нет закладок',
              ),
            ),
          ),
        if (entries.isNotEmpty)
          Expanded(
            child: ListView.builder(
              itemCount: entries.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == entries.length) {
                  return TextButton(
                    onPressed: loading ? null : () => load(more: true),
                    child: const Text('Загрузить ещё'),
                  );
                }
                final entry = entries[index];
                return ListTile(
                  title: Text(entry.conference.name),
                  subtitle: Text(
                    '${entry.conference.kind.groupLabel} · ${entry.conference.description}',
                  ),
                  trailing: !widget.history
                      ? IconButton(
                          tooltip: 'Удалить из закладок',
                          onPressed: removing.contains(entry.conference.id)
                              ? null
                              : () => remove(entry),
                          icon: const Icon(Icons.bookmark_remove),
                        )
                      : entry.date == null
                      ? null
                      : Text(entry.date!.toLocal().toString()),
                  onTap: removing.contains(entry.conference.id)
                      ? null
                      : () => open(entry),
                );
              },
            ),
          ),
      ],
    ),
  );
}
