import '../widgets/adaptive_layout.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_exceptions.dart';
import '../api/api_transport.dart';
import '../conference_card.dart';
import '../fido_conference.dart';
import '../main.dart';
import '../models/conference.dart';
import '../repositories/account_repository.dart';
import '../repositories/conference_repository.dart';
import '../repositories/message_repository.dart';
import '../utils/debouncer.dart';
import '../utils/refresh_on_resume.dart';
import 'message_screen.dart';

/// Каталог и избранное разделяют представление, но не состояние загрузки.
class PersonalConferences extends StatefulWidget {
  final bool history, catalog, active;
  final AccountRepository? repository;
  final ConferenceRepository? conferences;
  final VoidCallback? onChooseAreas;
  const PersonalConferences({
    super.key,
    required this.history,
    this.catalog = false,
    this.repository,
    this.conferences,
    this.active = true,
    this.onChooseAreas,
  });
  @override
  State<PersonalConferences> createState() => PersonalConferencesState();
}

class PersonalConferencesState extends State<PersonalConferences>
    with RefreshOnResume<PersonalConferences> {
  @override
  bool get resumeRefreshEnabled => widget.active;
  @override
  Future<void> refreshOnResume() => load();
  AccountRepository get repository => widget.repository ?? accountRepository;
  late ConferenceRepository conferences;
  late final Future<void> ready;
  StreamSubscription<int>? sessionSubscription;
  StreamSubscription<ConferenceChange>? changeSubscription;
  final controller = ScrollController();
  final search = TextEditingController();
  final debouncer = Debouncer(duration: const Duration(milliseconds: 300));
  List<PersonalConferenceEntry> entries = [];
  final pending = <String>{};
  final failedUpdates = <String>{};
  bool loading = false,
      hasMore = false,
      loaded = false,
      dirty = false,
      opening = false;
  String? error;
  String? bookmarkError;
  Future<void> Function()? retryBookmark;
  int version = 0;
  RpcCancellation? cancellation;
  @override
  void initState() {
    super.initState();
    loading = widget.active;
    controller.addListener(() {
      if (widget.active &&
          controller.position.extentAfter < 250 &&
          hasMore &&
          !loading &&
          error == null) {
        unawaited(load(more: true));
      }
    });
    ready = initialize();
    unawaited(
      ready.then((_) {
        if (mounted && widget.active && !loaded) unawaited(load());
      }),
    );
  }

  Future<void> initialize() async {
    conferences =
        widget.conferences ??
        ConferenceRepository(
          apiClient: repository.transport,
          prefs: await SharedPreferences.getInstance(),
        );
    if (!mounted) {
      if (widget.conferences == null) await conferences.dispose();
      return;
    }
    sessionSubscription = repository.sessionChanges.listen((_) {
      ++version;
      unawaited(cancellation?.cancel());
      entries = [];
      pending.clear();
      failedUpdates.clear();
      retryUpdate = null;
      loaded = false;
      dirty = false;
      error = null;
      bookmarkError = null;
      retryBookmark = null;
      hasMore = false;
      loading = false;
      search.clear();
      debouncer.cancel();
      setState(() {});
      if (widget.active) unawaited(load());
    });
    changeSubscription = conferences.changes.listen(
      (event) => unawaited(changed(event)),
    );
  }

  @override
  void didUpdateWidget(covariant PersonalConferences oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && (!loaded || dirty)) {
      unawaited(load());
    }
  }

  @override
  void dispose() {
    ++version;
    unawaited(cancellation?.cancel());
    unawaited(sessionSubscription?.cancel());
    unawaited(changeSubscription?.cancel());
    if (widget.conferences == null && changeSubscription != null) {
      unawaited(conferences.dispose());
    }
    controller.dispose();
    search.dispose();
    debouncer.dispose();
    super.dispose();
  }

  Future<void> changed(ConferenceChange event) async {
    if (!mounted) return;
    if (event.revoked) {
      failedUpdates.remove(event.id);
      setState(() {
        entries.removeWhere((e) => e.conference.id == event.id);
      });
      return;
    }
    if (widget.history) {
      if (event.bookmarked != null) return;
      dirty = true;
      if (widget.active) await load();
      return;
    }
    final index = entries.indexWhere((e) => e.conference.id == event.id);
    if (event.bookmarked != null) {
      setState(() {
        if (!widget.catalog) {
          dirty = true;
          if (!event.bookmarked!) {
            entries.removeWhere((e) => e.conference.id == event.id);
          }
        } else if (index >= 0) {
          final old = entries[index];
          entries[index] = PersonalConferenceEntry(
            old.conference.copyWith(isBookmarked: event.bookmarked!),
            old.date,
          );
        }
      });
      return;
    }
    if (widget.catalog || index < 0) return;
    final epoch = repository.epoch, captured = version;
    try {
      final fresh = await conferences.getConferenceById(event.id);
      if (!mounted || epoch != repository.epoch || captured != version) return;
      setState(() {
        failedUpdates.remove(event.id);
        if (failedUpdates.isEmpty && retryUpdate != null) {
          error = null;
          retryUpdate = null;
        }
        final position = entries.indexWhere((e) => e.conference.id == event.id);
        if (position < 0) return;
        if (fresh == null || !fresh.canRead || !fresh.isBookmarked) {
          entries.removeAt(position);
        } else {
          entries[position] = PersonalConferenceEntry(
            fresh,
            entries[position].date,
          );
        }
      });
    } catch (e) {
      if (!mounted || epoch != repository.epoch || captured != version) return;
      if (e is ApiException && e.isAccessDenied) {
        conferences.notifyDenied(event.id);
        setState(() => error = e.toString());
        return;
      }
      setState(() {
        failedUpdates.add(event.id);
        error = 'Не удалось обновить счётчик: $e';
      });
      retryUpdate = () async {
        for (final id in failedUpdates.toList()) {
          await changed(ConferenceChange(id));
        }
      };
    }
  }

  Future<void> Function()? retryUpdate;
  Future<void> load({bool more = false}) async {
    if (more && loading) return;
    if (!more) debouncer.cancel();
    if (more && dirty) more = false;
    final current = ++version;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    setState(() {
      loading = true;
      error = null;
      retryUpdate = null;
      failedUpdates.clear();
    });
    try {
      await ready;
      if (!mounted || current != version) return;
      final offset = more ? entries.length : 0;
      final List<PersonalConferenceEntry> rows;
      final bool next;
      if (widget.history) {
        final page = await repository.getHistory(
          offset: offset,
          cancellation: token,
        );
        rows = page.entries;
        next = page.hasMore;
      } else {
        final page = await conferences.fetchCatalogPage(
          bookmarkedOnly: !widget.catalog,
          omitStatistics: widget.catalog,
          query: search.text.trim(),
          offset: offset,
          cancellation: token,
        );
        rows = page.conferences
            .map((c) => PersonalConferenceEntry(c, null))
            .toList();
        next = page.hasMore;
      }
      if (!mounted || current != version) return;
      final combined = <String, PersonalConferenceEntry>{
        if (more)
          for (final e in entries) e.conference.id: e,
        for (final e in rows) e.conference.id: e,
      };
      if (more && next && combined.length == entries.length) {
        throw const ServerException(
          message: 'Загрузка списка не продвигается. Обновите список.',
        );
      }
      setState(() {
        entries = combined.values.toList();
        hasMore = next;
        loading = false;
        loaded = true;
        dirty = false;
      });
    } catch (e) {
      if (!mounted || current != version) return;
      setState(() {
        loading = false;
        error = e.toString();
        if (e is ApiException && e.isAccessDenied) {
          entries = [];
          loaded = false;
        }
      });
    }
  }

  Future<void> toggle(PersonalConferenceEntry entry) async {
    final id = entry.conference.id;
    if (!pending.add(id)) return;
    final epoch = repository.epoch;
    setState(() {
      bookmarkError = null;
      retryBookmark = null;
    });
    try {
      await conferences.toggleBookmark(
        id,
        widget.catalog ? entry.conference.isBookmarked : true,
      );
    } catch (e) {
      if (!mounted || epoch != repository.epoch) return;
      setState(() {
        bookmarkError = e.toString();
        retryBookmark = () => toggle(entry);
        if (e is ApiException && e.isAccessDenied) {
          entries.removeWhere((e) => e.conference.id == id);
        }
      });
    } finally {
      if (mounted && epoch == repository.epoch) {
        setState(() => pending.remove(id));
      }
    }
  }

  Future<void> open(PersonalConferenceEntry entry) async {
    if (opening || pending.contains(entry.conference.id)) return;
    opening = true;
    final epoch = repository.epoch;
    final touched = <String>{};
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MessageScreen(
            conferenceId: entry.conference.id,
            conferenceName: entry.conference.name,
            conferenceDescription: entry.conference.description,
            canRead: entry.conference.canRead,
            canPost: entry.conference.canPost,
            kind: entry.conference.kind,
            unsupportedFormat: entry.conference.unsupportedFormat,
            personalMailbox: entry.conference.personalMailbox,
            conferences: conferences,
            repository: MessageRepository(
              repository.transport,
              onChanged: touched.add,
            ),
            loadFavoriteOrder: (token) =>
                conferences.favoriteSnapshot(cancellation: token),
            onAccessDenied: conferences.clearCache,
            onAreaAccessDenied: conferences.notifyDenied,
          ),
        ),
      );
      if (mounted && epoch == repository.epoch) conferences.notifyRead(touched);
    } finally {
      opening = false;
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
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.history
            ? 'История'
            : widget.catalog
            ? 'Все области'
            : 'Избранное',
      ),
      actions: [
        IconButton(
          tooltip: 'Обновить',
          icon: const Icon(Icons.refresh),
          onPressed: () => load(),
        ),
        if (widget.history)
          IconButton(
            tooltip: 'Очистить историю',
            icon: const Icon(Icons.delete_sweep),
            onPressed: loading ? null : clear,
          ),
      ],
    ),
    body: AdaptiveContent(
      maxWidth: AdaptiveContent.listWidth,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (widget.catalog)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: search,
                          decoration: InputDecoration(
                            hintText: 'Поиск конференций...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Очистить поиск',
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      search.clear();
                                      searchChanged('');
                                    },
                                  ),
                          ),
                          onChanged: searchChanged,
                        ),
                      ),
                    if (loading) const LinearProgressIndicator(),
                    if (bookmarkError != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(bookmarkError!),
                            TextButton(
                              onPressed: retryBookmark,
                              child: const Text('Повторить изменение закладки'),
                            ),
                          ],
                        ),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(error!),
                            TextButton(
                              onPressed:
                                  retryUpdate ??
                                  () =>
                                      load(more: entries.isNotEmpty && hasMore),
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (!loading && error == null && entries.isEmpty)
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.history
                              ? 'История просмотров пуста'
                              : widget.catalog
                              ? 'Конференции не найдены'
                              : 'Нет закладок',
                        ),
                        if (!widget.history &&
                            !widget.catalog &&
                            widget.onChooseAreas != null)
                          TextButton(
                            onPressed: widget.onChooseAreas,
                            child: const Text('Выбрать эхи'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (entries.isNotEmpty)
              Expanded(
                child: RefreshIndicator(
                  onRefresh: load,
                  child: ListView.builder(
                    controller: controller,
                    itemCount: entries.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == entries.length) {
                        return TextButton(
                          onPressed: loading ? null : () => load(more: true),
                          child: const Text('Загрузить ещё'),
                        );
                      }
                      final e = entries[index], c = e.conference;
                      if (widget.history) {
                        return ListTile(
                          title: Text(c.name),
                          subtitle: Text(
                            '${c.kind.groupLabel} · ${c.description}${e.date == null ? '' : '\n${e.date!.toLocal()}'}',
                          ),
                          onTap: () => open(e),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (index == 0 ||
                              entries[index - 1].conference.kind != c.kind)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(
                                c.kind.groupLabel,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ConferenceCard(
                            conference: FidoConference(
                              id: c.id,
                              name: c.name,
                              description: c.description,
                              unreadCount: c.unreadCount,
                              icon: Icons.forum,
                              isBookmarked: !widget.catalog || c.isBookmarked,
                              canRead: c.canRead,
                              canPost: c.canPost,
                              kind: c.kind,
                              personalMailbox: c.personalMailbox,
                              storageFormat: c.storageFormat,
                              unsupportedFormat: c.unsupportedFormat,
                              statisticsKnown: c.statisticsKnown,
                            ),
                            showStatistics: !widget.catalog,
                            showZeroCount: true,
                            onTap: () => open(e),
                            onBookmark: c.canRead || !widget.catalog
                                ? () => toggle(e)
                                : null,
                            bookmarkPending: pending.contains(c.id),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  void searchChanged(String value) {
    if (controller.hasClients) controller.jumpTo(0);
    ++version;
    unawaited(cancellation?.cancel());
    debouncer.cancel();
    setState(() {
      error = null;
      entries = [];
      hasMore = false;
      loading = true;
    });
    if (value.trim().isEmpty) {
      unawaited(load());
    } else {
      debouncer.run(() => load());
    }
  }
}
