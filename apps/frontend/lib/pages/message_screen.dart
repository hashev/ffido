import '../widgets/adaptive_layout.dart';
import '../widgets/message_actions.dart';

import 'dart:math';

import 'personal_message_filters_screen.dart';
import '../api/generated/ffido/v1/ffido.pb.dart' as filter_wire;
import '../widgets/message_technical_dialog.dart';
import '../templates/template_engine.dart';
import '../templates/template_settings.dart';
import '../api/message_footer.dart';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

import '../updates/update_controller.dart';
import '../utils/refresh_on_resume.dart';
import '../widgets/uue_body.dart';
import '../files/uue_files.dart';
import '../models/uue.dart';
import '../repositories/uue_repository.dart';
import '../utils/ftn_text.dart';

import 'dart:async';

import 'package:flutter/rendering.dart' show ScrollDirection;

import '../models/message_search.dart';
import '../widgets/search_highlight.dart';
import '../widgets/message_search_dialog.dart';

import 'package:flutter/material.dart';
import 'package:grpc/grpc_or_grpcweb.dart' show StatusCode;

import '../api/api_transport.dart';
import '../api/api_exceptions.dart';
import '../main.dart';
import '../models/message.dart';
import '../models/conference.dart';
import '../repositories/conference_repository.dart';
import 'forward_destination.dart';
import 'reply_destination.dart';
import '../shortcuts/command_scope.dart';
import '../shortcuts/desktop_commands.dart';
import 'crosspost_destinations.dart';
import '../repositories/message_repository.dart';

String _correspondent(String name, String address) =>
    address.trim().isEmpty ? '$name (адрес не указан)' : '$name <$address>';

class MessageScreen extends StatefulWidget {
  final String conferenceId, conferenceName, conferenceDescription;
  final MessageRepository? repository;
  final Future<TemplateBundle?> Function()? loadTemplate;
  final ConferenceRepository? conferences;
  final bool canRead, canPost, unsupportedFormat;
  final AreaKind kind;
  final bool personalMailbox;
  final List<Conference> conferenceOrder;
  final Future<List<Conference>> Function(RpcCancellation)? loadFavoriteOrder;
  final Future<void> Function()? onAccessDenied;
  final void Function(String)? onAreaAccessDenied;
  const MessageScreen({
    super.key,
    required this.conferenceId,
    required this.conferenceName,
    required this.conferenceDescription,
    this.repository,
    this.loadTemplate,
    this.conferences,
    this.canRead = false,
    this.canPost = false,
    this.unsupportedFormat = false,
    this.kind = AreaKind.echo,
    this.personalMailbox = false,
    this.conferenceOrder = const [],
    this.loadFavoriteOrder,
    this.onAccessDenied,
    this.onAreaAccessDenied,
  });
  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen>
    with RefreshOnResume<MessageScreen> {
  @override
  bool get resumeRefreshEnabled => !unreadBusy && !bulkBusy && !searchBusy;

  @override
  Future<void> refreshOnResume() async {
    if (kind == AreaKind.echo) {
      try {
        if (await repository.filters.ensure()) {
          await refreshPersonalView();
          return;
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            error = '$e';
            retry = refreshOnResume;
          });
        }
        return;
      }
    }
    final message = selected;
    final epoch = repository.epoch;
    await load(
      preserveThread: personalMailbox,
      preserveOpenedMessage: personalMailbox,
    );
    if (!personalMailbox &&
        mounted &&
        repository.epoch == epoch &&
        message != null) {
      await open(message);
    }
  }

  late Conference activeConference;
  late List<Conference> conferenceOrder;
  bool favoriteOrderLoaded = false;
  late final int orderEpoch;
  final Set<String> opened = {};
  bool echoesExhausted = false;
  String get conferenceId => activeConference.id;
  String get conferenceName => activeConference.name;
  bool get canRead => activeConference.canRead;
  bool get canPost => activeConference.canPost;
  AreaKind get kind => activeConference.kind;
  bool get personalMailbox => activeConference.personalMailbox;
  bool get unreadNavigation => kind == AreaKind.echo && threadId == null;
  bool unread(Message message) =>
      !message.isRead && !opened.contains('$conferenceId/${message.id}');
  Iterable<Conference> nextEchoes() sync* {
    if (repository.epoch != orderEpoch) return;
    final index = conferenceOrder.indexWhere((c) => c.id == conferenceId);
    if (index < 0 && widget.loadFavoriteOrder == null) return;
    final start = index < 0 ? 0 : index + 1;
    final seen = <String>{conferenceId};
    for (var step = 0; step < conferenceOrder.length; step++) {
      final entry = conferenceOrder[(start + step) % conferenceOrder.length];
      if (entry.kind == AreaKind.echo &&
          entry.canRead &&
          !entry.unsupportedFormat &&
          seen.add(entry.id)) {
        yield entry;
      }
    }
  }

  bool get hasNextEcho =>
      repository.epoch == orderEpoch &&
      !echoesExhausted &&
      ((widget.loadFavoriteOrder != null && !favoriteOrderLoaded) ||
          nextEchoes().isNotEmpty);

  bool canNavigate(int direction) {
    if (loading || bulkBusy || unreadBusy || !canRead) return false;
    final index = messages.indexWhere((m) => m.id == selected?.id);
    if (unreadNavigation) {
      final rows = direction > 0
          ? messages.skip(index + 1)
          : messages.take(index < 0 ? 0 : index);
      return rows.any(unread) ||
          (direction > 0 ? hasMore || hasNextEcho : firstOffset > 0);
    }
    return selected != null &&
        (direction > 0
            ? index + 1 < messages.length || hasMore
            : index > 0 || firstOffset > 0);
  }

  MessageRepository get repository => widget.repository ?? messageRepository;
  List<Message> messages = [];
  Message? selected;
  bool loading = false, hasMore = false, listStale = false;
  String? error;
  Future<void> Function()? retry;
  int pageOffset = 0, firstOffset = 0;
  String? lastOpenedMessageId;
  int positionRevision = 0;
  DateTime? mailboxUpdatedAt;
  final listController = ScrollController();
  final bodyController = ScrollController();
  int version = 0;
  String? bulkOperation;
  bool bulkBusy = false, unreadBusy = false;
  RpcCancellation? bulkCancellation;
  String? threadId;
  RpcCancellation? cancellation;
  String searchQuery = '';
  bool searchHeadersOnly = false,
      searchBusy = false,
      searchDialogOpen = false,
      revealSearch = false;
  String? searchLastId, searchNotice;
  MessageSearchResult? searchResult;
  RpcCancellation? searchCancellation;
  void resetSearch({bool clearQuery = false}) {
    searchResult = null;
    searchLastId = null;
    searchNotice = null;
    revealSearch = false;
    if (clearQuery) {
      searchQuery = '';
      searchHeadersOnly = false;
    }
  }

  Future<void> showSearch() async {
    if (commandReason(DesktopCommand.search) != null) {
      return;
    }
    final epoch = repository.epoch;
    searchDialogOpen = true;
    final choice = await showDialog<({String query, bool headersOnly})>(
      context: context,
      builder: (_) => MessageSearchDialog(
        query: searchQuery,
        headersOnly: searchHeadersOnly,
      ),
    );
    searchDialogOpen = false;
    if (!mounted || epoch != repository.epoch || choice == null) return;
    if (choice.query != searchQuery ||
        choice.headersOnly != searchHeadersOnly) {
      resetSearch();
    }
    searchQuery = choice.query;
    searchHeadersOnly = choice.headersOnly;
    await findNext();
  }

  void cancelSearch() {
    ++version;
    unawaited(searchCancellation?.cancel());
    setState(() {
      searchBusy = false;
      loading = false;
      searchNotice = 'Поиск отменён';
    });
  }

  Future<void> findNext() async {
    if (loading || !canRead || searchQuery.isEmpty) return;
    final current = ++version, epoch = repository.epoch;
    final area = conferenceId;
    final token = searchCancellation = RpcCancellation();
    unawaited(cancellation?.cancel());
    final anchor = searchLastId ?? selected?.id;
    final includeStart = searchLastId == null;
    setState(() {
      searchBusy = true;
      loading = true;
      error = null;
      searchNotice = null;
    });
    bool valid() =>
        mounted &&
        current == version &&
        epoch == repository.epoch &&
        area == conferenceId;
    try {
      final result = await repository.findMessage(
        conferenceId: area,
        query: searchQuery,
        headersOnly: searchHeadersOnly,
        startMessageId: anchor,
        includeStart: includeStart,
        cancellation: token,
      );
      if (!valid()) return;
      if (result == null) {
        setState(() {
          searchResult = null;
          revealSearch = false;
          searchNotice = 'До конца области совпадений нет';
        });
        return;
      }
      setState(() {
        selected = result.message;
        filterNeedsOpen = false;
        searchResult = result;
        searchLastId = result.message.id;
        revealSearch = true;
        threadId = null;
        if (!result.message.isCollapsed) {
          opened.add('$area/${result.message.id}');
        }
        if (personalMailbox &&
            result.message.positionRevision >= positionRevision) {
          positionRevision = result.message.positionRevision;
          lastOpenedMessageId = result.message.id;
        }
      });
      try {
        final page = await repository.getConferenceMessages(
          conferenceId: area,
          anchorMessageId: result.message.id,
          cancellation: token,
        );
        if (!valid()) return;
        setState(() {
          messages = page.messages;
          firstOffset = page.actualOffset ?? 0;
          pageOffset = firstOffset + messages.length;
          hasMore = page.hasMore;
        });
      } catch (e) {
        if (!valid()) return;
        if (e is ApiException &&
            (e.isAccessDenied || e is UnauthorizedException)) {
          rethrow;
        }
        setState(() {
          messages = [];
          hasMore = false;
          searchNotice = 'Письмо найдено. Не удалось обновить список: $e';
        });
      }
    } catch (e) {
      if (!valid()) return;
      if (e is ApiException &&
          (e.isAccessDenied || e is UnauthorizedException)) {
        await accessDenied();
      }
      if (!valid()) return;
      setState(() {
        searchNotice =
            e is ApiException && e.statusCode == StatusCode.unimplemented
            ? 'Сервер не поддерживает поиск. Обновите сервер.'
            : 'Ошибка поиска: $e';
      });
    } finally {
      if (valid()) {
        setState(() {
          searchBusy = false;
          loading = false;
        });
      }
    }
  }

  Widget searchHeader(String text, int field, {TextStyle? style}) {
    final ranges = searchResult?.matches[field] ?? const <SearchRange>[];
    return SearchReveal(
      offset: ranges.isEmpty ? null : ranges.first.start,
      enabled: revealSearch && searchResult?.firstField == field,
      child: SelectableText.rich(
        TextSpan(
          children: highlightSearch(
            [TextSpan(text: text)],
            ranges,
            Theme.of(context).colorScheme.tertiaryContainer,
          ),
        ),
        style: style,
      ),
    );
  }

  Widget correspondent(
    String label,
    String name,
    String address,
    int nameField,
    int addressField,
  ) {
    final text = '$label ${_correspondent(name, address)}';
    final ranges = <SearchRange>[
      for (final range
          in searchResult?.matches[nameField] ?? const <SearchRange>[])
        SearchRange(
          range.start + label.length + 1,
          range.end + label.length + 1,
        ),
      for (final range
          in searchResult?.matches[addressField] ?? const <SearchRange>[])
        SearchRange(
          range.start + label.length + name.length + 3,
          range.end + label.length + name.length + 3,
        ),
    ];
    return SearchReveal(
      offset: ranges.isEmpty ? null : ranges.first.start,
      enabled:
          revealSearch &&
          (searchResult?.firstField == nameField ||
              searchResult?.firstField == addressField),
      child: SelectableText.rich(
        TextSpan(
          children: highlightSearch(
            [TextSpan(text: text)],
            ranges,
            Theme.of(context).colorScheme.tertiaryContainer,
          ),
        ),
      ),
    );
  }

  late final StreamSubscription<int> subscription;
  @override
  void initState() {
    super.initState();
    activeConference = Conference(
      id: widget.conferenceId,
      name: widget.conferenceName,
      description: widget.conferenceDescription,
      unreadCount: 0,
      totalCount: 0,
      canRead: widget.canRead,
      canPost: widget.canPost,
      unsupportedFormat: widget.unsupportedFormat,
      kind: widget.kind,
      personalMailbox: widget.personalMailbox,
    );
    conferenceOrder = List.unmodifiable(widget.conferenceOrder);
    orderEpoch = repository.epoch;
    subscription = repository.sessionChanges.listen((_) {
      resetSearch(clearQuery: true);
      searchBusy = false;
      unawaited(searchCancellation?.cancel());
      opened.clear();
      echoesExhausted = true;
      bulkOperation = null;
      bulkBusy = false;
      unreadBusy = false;
      unawaited(bulkCancellation?.cancel());
      messages = [];
      selected = null;
      lastOpenedMessageId = null;
      positionRevision = 0;
      mailboxUpdatedAt = null;
      load();
    });
    load();
  }

  @override
  void dispose() {
    ++version;
    unawaited(searchCancellation?.cancel());
    listController.dispose();
    bodyController.dispose();
    unawaited(cancellation?.cancel());
    unawaited(subscription.cancel());
    unawaited(bulkCancellation?.cancel());
    super.dispose();
  }

  Future<void> load({
    bool more = false,
    bool thread = false,
    bool preserveThread = false,
    bool preserveOpenedMessage = false,
    String? anchorMessageId,
  }) async {
    if (searchBusy || unreadBusy || !canRead || (more && loading)) return;
    if (!more) resetSearch();
    if (!more) {
      echoesExhausted = false;
      favoriteOrderLoaded = false;
    }
    final current = ++version;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    final parent = selected;
    if (thread && parent != null) threadId = parent.id;
    if (!more && !thread && !preserveThread) threadId = null;
    setState(() {
      loading = true;
      error = null;
      listStale = false;
      retry = () => load(
        more: more,
        thread: thread,
        preserveThread: preserveThread,
        preserveOpenedMessage: preserveOpenedMessage,
        anchorMessageId: anchorMessageId,
      );
    });
    try {
      if (personalMailbox && !more) {
        final state = await repository.getMailboxState(
          conferenceId,
          cancellation: token,
        );
        if (!mounted || current != version) return;
        if (!state.personalMailbox || !state.canRead) {
          throw const ApiException(
            message: 'Доступ к личному ящику отозван',
            statusCode: StatusCode.permissionDenied,
          );
        }
        if (state.positionRevision >= positionRevision) {
          lastOpenedMessageId = state.lastOpenedMessageId;
          positionRevision = state.positionRevision;
        }
      }
      final keptMessage =
          preserveOpenedMessage &&
              personalMailbox &&
              parent != null &&
              lastOpenedMessageId == parent.id
          ? parent
          : null;
      final keptIndex = keptMessage == null
          ? -1
          : messages.indexWhere((message) => message.id == keptMessage.id);
      if (threadId != null) {
        final result = await repository.getThreadPage(
          conferenceId: conferenceId,
          threadId: threadId!,
          offset: more
              ? pageOffset
              : keptIndex < 0
              ? 0
              : ((firstOffset + keptIndex) ~/ 100) * 100,
          limit: 100,
          cancellation: token,
        );
        if (!mounted || current != version) return;
        setState(() {
          acceptPage(
            result.messages,
            result.hasMore,
            more,
            actualOffset: result.actualOffset,
            keptMessage: keptMessage,
          );
          if (personalMailbox && !more) {
            mailboxUpdatedAt = DateTime.now();
          }
          loading = false;
        });
      } else {
        final result = await repository.getConferenceMessages(
          conferenceId: conferenceId,
          offset: more ? pageOffset : 0,
          anchorMessageId: anchorMessageId ?? keptMessage?.id,
          cancellation: token,
        );
        if (!mounted || current != version) return;
        setState(() {
          acceptPage(
            result.messages,
            result.hasMore,
            more,
            actualOffset: result.actualOffset,
            keptMessage: keptMessage,
          );
          if (personalMailbox && !more) {
            mailboxUpdatedAt = DateTime.now();
          }
          loading = false;
        });
      }
    } catch (e) {
      if (!mounted || current != version) return;
      if (e is ApiException && e.isAccessDenied) await accessDenied();
      if (!mounted || current != version) return;
      setState(() {
        loading = false;
        if (personalMailbox) {
          messages = [];
          selected = null;
          hasMore = false;
          lastOpenedMessageId = null;
        }
        error = e is NotFoundException
            ? 'Список устарел. Обновите сообщения.'
            : e.toString();
        listStale = e is NotFoundException;
        if (listStale) retry = () => load();
      });
    }
  }

  void acceptPage(
    List<Message> rows,
    bool moreAvailable,
    bool more, {
    int? actualOffset,
    Message? keptMessage,
  }) {
    if (more && messages.isNotEmpty) {
      final first = messages.first.id;
      final separator = first.lastIndexOf('#');
      if (separator > 0 &&
          rows.any((row) {
            final end = row.id.lastIndexOf('#');
            return end > 0 &&
                row.id.substring(0, end) != first.substring(0, separator);
          })) {
        throw const NotFoundException(message: 'Поколение базы изменилось');
      }
    }
    if (!more) firstOffset = actualOffset ?? 0;
    pageOffset = (actualOffset ?? (more ? pageOffset : 0)) + rows.length;
    final known = more ? messages.map((m) => m.id).toSet() : <String>{};
    final added = rows.where((m) => known.add(m.id)).toList();
    messages = more ? [...messages, ...added] : added;
    hasMore = moreAvailable && rows.isNotEmpty && added.isNotEmpty;
    if (!more) {
      selected =
          keptMessage != null &&
              rows.any((message) => message.id == keptMessage.id)
          ? keptMessage
          : null;
    }
  }

  Future<void> navigateUnread(int direction) async {
    final current = ++version;
    final epoch = repository.epoch;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    final selectedId = selected?.id;
    bool valid() => mounted && current == version && epoch == repository.epoch;
    void check() {
      if (!valid()) throw const CancelledException();
    }

    setState(() {
      loading = true;
      error = null;
      listStale = false;
      retry = () => navigate(direction);
    });
    try {
      var destination = activeConference;
      Iterator<Conference>? candidates;
      Future<Iterator<Conference>> getCandidates() async {
        if (candidates != null) return candidates!;
        if (widget.loadFavoriteOrder != null && !favoriteOrderLoaded) {
          final order = await widget.loadFavoriteOrder!(token);
          check();
          conferenceOrder = List.unmodifiable(order);
          favoriteOrderLoaded = true;
        }
        return candidates = nextEchoes().iterator;
      }

      var inCurrent = true;
      while (true) {
        final rows = <Message>[];
        final seen = <String>{};
        var offset = 0;
        var more = true;
        var foundCurrent = selectedId == null || !inCurrent;
        Message? candidate;
        while (more) {
          final page = await (() async {
            try {
              return await repository.getConferenceMessages(
                conferenceId: destination.id,
                offset: offset,
                cancellation: token,
              );
            } on ApiException catch (e) {
              check();
              if (inCurrent ||
                  (!e.isAccessDenied && e.statusCode != StatusCode.notFound)) {
                rethrow;
              }
              return null;
            }
          })();
          if (page == null) break;
          check();
          final added = page.messages.where((m) => seen.add(m.id)).toList();
          // Opaque IDs include a JAM generation. Never combine generations.
          final reference = inCurrent ? selectedId : rows.firstOrNull?.id;
          if (reference != null && reference.contains('#')) {
            final generation = reference.substring(
              0,
              reference.lastIndexOf('#'),
            );
            if (added.any((m) => !m.id.startsWith('$generation#'))) {
              throw const NotFoundException(
                message: 'Поколение базы изменилось',
              );
            }
          }
          rows.addAll(added);
          offset = (page.actualOffset ?? offset) + page.messages.length;
          more = page.hasMore && added.isNotEmpty;
          for (final message in added) {
            if (inCurrent && message.id == selectedId) {
              foundCurrent = true;
              continue;
            }
            final eligible =
                !message.isRead &&
                !opened.contains('${destination.id}/${message.id}');
            if (!eligible) continue;
            if (direction > 0 && foundCurrent) {
              candidate = message;
              break;
            }
            if (direction < 0 && !foundCurrent) candidate = message;
          }
          if (direction > 0 && candidate != null ||
              direction < 0 && foundCurrent) {
            break;
          }
        }
        if (!foundCurrent && inCurrent && selectedId != null) {
          throw const NotFoundException(
            message: 'Список устарел. Обновите сообщения.',
          );
        }
        if (candidate != null) {
          final result = await (() async {
            try {
              return await repository.getMessage(
                conferenceId: destination.id,
                messageId: candidate!.id,
                cancellation: token,
              );
            } on ApiException catch (e) {
              check();
              if (inCurrent ||
                  (!e.isAccessDenied && e.statusCode != StatusCode.notFound)) {
                rethrow;
              }
              return null;
            }
          })();
          check();
          if (result != null) {
            if (result.id != candidate.id) throw const NotFoundException();
            setState(() {
              activeConference = destination;
              messages = rows
                  .map((m) => m.id == result.id ? result : m)
                  .toList();
              selected = result;
              filterNeedsOpen = false;
              if (!result.isCollapsed) {
                opened.add('${destination.id}/${result.id}');
              }
              firstOffset = 0;
              pageOffset = offset;
              hasMore = more;
              loading = false;
              if (!inCurrent) {
                bulkOperation = null;
                lastOpenedMessageId = null;
                positionRevision = 0;
                mailboxUpdatedAt = null;
              }
            });
            if (bodyController.hasClients) bodyController.jumpTo(0);
            return;
          }
        }
        if (inCurrent) {
          setState(() {
            messages = rows;
            firstOffset = 0;
            pageOffset = offset;
            hasMore = false;
          });
        }
        if (direction < 0) break;
        Conference? next;
        final iterator = await getCandidates();
        while (repository.epoch == orderEpoch && iterator.moveNext()) {
          final entry = iterator.current;
          try {
            final fresh = await repository.getMailboxState(
              entry.id,
              cancellation: token,
            );
            check();
            if (fresh.id == entry.id &&
                fresh.kind == AreaKind.echo &&
                fresh.canRead &&
                !fresh.unsupportedFormat) {
              if (fresh.statisticsKnown && fresh.unreadCount == 0) continue;
              next = fresh;
              break;
            }
          } on ApiException catch (e) {
            check();
            if (!e.isAccessDenied && e.statusCode != StatusCode.notFound) {
              rethrow;
            }
          }
        }
        if (next == null) {
          echoesExhausted = true;
          break;
        }
        destination = next;
        inCurrent = false;
      }
      if (valid()) setState(() => loading = false);
    } catch (e) {
      if (!valid()) return;
      if (e is ApiException && e.isAccessDenied) await accessDenied();
      if (!valid()) return;
      setState(() {
        loading = false;
        error = e is NotFoundException
            ? 'Список устарел. Обновите сообщения.'
            : e.toString();
        listStale = e is NotFoundException;
        retry = listStale ? () => load() : () => navigate(direction);
      });
    }
  }

  Future<void> navigate(int direction) async {
    if (loading || bulkBusy) return;
    resetSearch();
    if (unreadNavigation) {
      await navigateUnread(direction);
      return;
    }
    if (selected == null) return;
    final id = selected!.id;
    var index = messages.indexWhere((m) => m.id == id);
    if (index < 0) return;
    if (direction > 0 && index + 1 == messages.length && hasMore) {
      final epoch = repository.epoch;
      await load(more: true);
      if (!mounted || repository.epoch != epoch || selected?.id != id) return;
      if (error != null) {
        if (!listStale) {
          setState(() => retry = () => navigate(direction));
        }
        return;
      }
      index = messages.indexWhere((m) => m.id == id);
    }
    if (direction < 0 && index == 0 && firstOffset > 0 && threadId == null) {
      final current = ++version;
      final token = cancellation = RpcCancellation();
      setState(() => loading = true);
      try {
        final result = await repository.getConferenceMessages(
          conferenceId: conferenceId,
          offset: (firstOffset - 20).clamp(0, firstOffset),
          cancellation: token,
        );
        if (!mounted || current != version || selected?.id != id) return;
        final separator = id.lastIndexOf('#');
        if (separator > 0 &&
            result.messages.any((row) {
              final end = row.id.lastIndexOf('#');
              return end <= 0 ||
                  row.id.substring(0, end) != id.substring(0, separator);
            })) {
          throw const NotFoundException(message: 'Поколение базы изменилось');
        }
        final known = messages.map((message) => message.id).toSet();
        final previous = result.messages
            .where((message) => !known.contains(message.id))
            .toList();
        setState(() {
          messages = [...previous, ...messages];
          firstOffset =
              result.actualOffset ?? (firstOffset - 20).clamp(0, firstOffset);
          loading = false;
        });
        index = messages.indexWhere((message) => message.id == id);
      } catch (e) {
        if (!mounted || current != version) return;
        if (e is ApiException && e.isAccessDenied) await accessDenied();
        if (!mounted || current != version) return;
        setState(() {
          loading = false;
          error = e.toString();
          retry = () => load();
          if (personalMailbox) {
            messages = [];
            selected = null;
            hasMore = false;
          }
        });
        return;
      }
    }
    final target = index + direction;
    if (target >= 0 && target < messages.length) await open(messages[target]);
  }

  Future<void> open(Message message) async {
    if (loading || unreadBusy || bulkBusy) return;
    resetSearch();
    final current = ++version;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    setState(() {
      loading = true;
      error = null;
      listStale = false;
      retry = () => open(message);
    });
    try {
      final result = await repository.getMessage(
        conferenceId: conferenceId,
        messageId: message.id,
        cancellation: token,
      );
      if (!mounted || current != version) return;
      if (result.id != message.id) throw const NotFoundException();
      setState(() {
        selected = result;
        filterNeedsOpen = false;
        if (!result.isCollapsed) {
          opened.add('$conferenceId/${result.id}');
        }
        if (personalMailbox && result.positionRevision >= positionRevision) {
          positionRevision = result.positionRevision;
          lastOpenedMessageId = result.id;
        }
        loading = false;
        final index = messages.indexWhere((m) => m.id == result.id);
        if (index >= 0) messages[index] = result;
      });
      if (bodyController.hasClients) bodyController.jumpTo(0);
    } catch (e) {
      if (!mounted || current != version) return;
      if (e is ApiException && e.isAccessDenied) await accessDenied();
      if (!mounted || current != version) return;
      setState(() {
        loading = false;
        if (personalMailbox) {
          messages = [];
          selected = null;
          hasMore = false;
          lastOpenedMessageId = null;
        }
        error = e is NotFoundException
            ? 'Список устарел. Обновите сообщения.'
            : e.toString();
        listStale = e is NotFoundException;
        if (listStale) retry = () => load();
      });
    }
  }

  Future<void> continueReading() async {
    final id = lastOpenedMessageId;
    if (id == null || loading) return;
    await load(anchorMessageId: id);
    if (!mounted) return;
    if (listStale) {
      await load();
      return;
    }
    if (error != null) return;
    final index = messages.indexWhere((message) => message.id == id);
    if (index >= 0) await open(messages[index]);
  }

  Future<void> compose({
    bool reply = false,
    bool forward = false,
    bool quoted = true,
    bool crossAreaReply = false,
    bool personalOnly = false,
  }) async {
    if (filteredSelection && (reply || forward || crossAreaReply)) return;
    if (((forward || crossAreaReply) && kind != AreaKind.echo) ||
        commandBusy ||
        activeConference.unsupportedFormat ||
        ((reply || forward || crossAreaReply) && selected == null) ||
        (!forward && !crossAreaReply && !canPost) ||
        ((reply || forward || crossAreaReply) && !canRead)) {
      return;
    }
    setState(() => composerOpen = true);
    try {
      final epoch = repository.epoch;
      Conference? destination;
      if (forward || crossAreaReply) {
        destination = await Navigator.push<Conference>(
          context,
          MaterialPageRoute(
            builder: (_) => crossAreaReply
                ? ReplyDestination(
                    repository: widget.conferences ?? conferenceRepository,
                    sourceId: conferenceId,
                    personalOnly: personalOnly,
                  )
                : ForwardDestination(
                    repository: widget.conferences ?? conferenceRepository,
                  ),
          ),
        );
        if (!mounted || destination == null || repository.epoch != epoch) {
          return;
        }
      }
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => _ComposeScreen(
            repository: repository,
            onAccessDenied: accessDenied,
            conferenceId: conferenceId,
            kind: kind,
            conferenceName: conferenceName,
            conferences: crossAreaReply
                ? (widget.conferences ?? conferenceRepository)
                : widget.conferences ??
                      (widget.repository == null ? conferenceRepository : null),
            destination: destination,
            original: reply || forward || crossAreaReply ? selected : null,
            forward: forward,
            crossAreaReply: crossAreaReply,
            quoted: quoted,
            loadTemplate: widget.loadTemplate,
            conferenceDescription: widget.conferenceDescription,
          ),
        ),
      );
      if (mounted && result == true && !forward && !crossAreaReply) {
        load(preserveThread: personalMailbox);
      }
    } finally {
      if (mounted) setState(() => composerOpen = false);
    }
  }

  Future<void> accessDenied() async {
    widget.onAreaAccessDenied?.call(conferenceId);
    resetSearch();
    if (mounted) {
      setState(() {
        messages = [];
        selected = null;
        hasMore = false;
        lastOpenedMessageId = null;
        positionRevision = 0;
        mailboxUpdatedAt = null;
      });
    }
    await widget.onAccessDenied?.call();
  }

  Future<void> markSelectedUnread() async {
    final message = selected;
    if (message == null ||
        loading ||
        bulkBusy ||
        unreadBusy ||
        !canRead ||
        activeConference.unsupportedFormat) {
      return;
    }
    final captured = repository.epoch;
    final current = ++version;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    setState(() {
      loading = true;
      unreadBusy = true;
      error = null;
    });
    try {
      await repository.markAsUnread(
        conferenceId: conferenceId,
        messageId: message.id,
        cancellation: token,
      );
      if (!mounted || captured != repository.epoch || current != version) {
        return;
      }
      setState(() {
        opened.remove('$conferenceId/${message.id}');
        echoesExhausted = false;
        messages = messages
            .map(
              (row) => row.id == message.id
                  ? Message.fromJson({...row.toJson(), 'is_read': false})
                  : row,
            )
            .toList();
        selected = null;
      });
      await refreshAfterUnread(captured);
    } catch (e) {
      if (!mounted || captured != repository.epoch || current != version) {
        return;
      }
      if (e is ApiException && e.isAccessDenied) await accessDenied();
      if (!mounted || captured != repository.epoch) return;
      setState(() {
        error = 'Не удалось подтвердить пометку непрочитанности: $e';
        retry = markSelectedUnread;
      });
    } finally {
      if (mounted && captured == repository.epoch) {
        setState(() {
          unreadBusy = false;
          loading = false;
        });
      }
    }
  }

  Future<void> refreshAfterUnread(int captured) async {
    if (!mounted || captured != repository.epoch) return;
    setState(() {
      loading = true;
      unreadBusy = true;
      error = null;
    });
    try {
      final conferences =
          widget.conferences ??
          (widget.repository == null ? conferenceRepository : null);
      if (conferences != null) {
        await conferences.clearCache();
        if (!mounted || captured != repository.epoch) return;
        final fresh = await conferences.getConferenceById(
          conferenceId,
          cancellation: cancellation,
        );
        if (!mounted || captured != repository.epoch) return;
        if (fresh != null) {
          setState(() => activeConference = fresh);
          if (!fresh.canRead) {
            throw const ApiException(
              message: 'Доступ к области отозван',
              statusCode: StatusCode.permissionDenied,
            );
          }
        }
      }
      await refreshBulkPage(captured);
    } catch (e) {
      if (!mounted || captured != repository.epoch) return;
      if (e is ApiException && e.isAccessDenied) await accessDenied();
      if (!mounted || captured != repository.epoch) return;
      setState(() {
        error = 'Письмо помечено непрочитанным. Не удалось обновить список: $e';
        retry = () => refreshAfterUnread(captured);
      });
    } finally {
      if (mounted && captured == repository.epoch) {
        setState(() {
          loading = false;
          unreadBusy = false;
        });
      }
    }
  }

  Future<void> markAreaRead() async {
    if (bulkBusy ||
        unreadBusy ||
        !canRead ||
        activeConference.unsupportedFormat) {
      return;
    }
    final captured = repository.epoch;
    if (bulkOperation == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Отметить всё прочитанным'),
          content: Text(
            'Отметить все сообщения в «$conferenceName» прочитанными? '
            'Это относится ко всей области, включая сообщения вне текущей страницы и цепочки.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Отметить'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || captured != repository.epoch) return;
      bulkOperation = MessageRepository.newOperationId();
    }
    final token = bulkCancellation = RpcCancellation();
    setState(() => bulkBusy = true);
    var confirmed = false;
    try {
      await repository.markConferenceRead(
        conferenceId: conferenceId,
        operationId: bulkOperation!,
        cancellation: token,
      );
      if (!mounted || captured != repository.epoch) return;
      confirmed = true;
      bulkOperation = null;
      if (widget.conferences != null || widget.repository == null) {
        await (widget.conferences ?? conferenceRepository).clearCache();
      }
      if (!mounted || captured != repository.epoch) return;
      await refreshBulkPage(captured);
      if (!mounted || captured != repository.epoch) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщения отмечены прочитанными')),
      );
    } catch (e) {
      if (!mounted || captured != repository.epoch) return;
      final definitive =
          e is ApiException && ![4, 13, 14, 1, 2].contains(e.statusCode);
      if (!confirmed && definitive) bulkOperation = null;
      final message = confirmed
          ? 'Отметка сохранена. Не удалось обновить список: $e'
          : bulkOperation != null
          ? 'Результат не подтверждён. Выберите «Проверить/повторить»: $e'
          : '$e';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted && captured == repository.epoch) {
        setState(() => bulkBusy = false);
      }
    }
  }

  Future<void> refreshBulkPage(int captured) async {
    final current = ++version;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    final refreshed = <Message>[];
    final count = messages.isEmpty ? 20 : messages.length;
    var more = false;
    for (var offset = firstOffset; offset < firstOffset + count;) {
      final limit = (firstOffset + count - offset).clamp(1, 100);
      final result = threadId == null
          ? await repository.getConferenceMessages(
              conferenceId: conferenceId,
              offset: offset,
              limit: limit,
              cancellation: token,
            )
          : await repository.getThreadPage(
              conferenceId: conferenceId,
              threadId: threadId!,
              offset: offset,
              limit: limit,
              cancellation: token,
            );
      if (!mounted || captured != repository.epoch || current != version) {
        return;
      }
      refreshed.addAll(result.messages);
      more = result.hasMore;
      if (!more || result.messages.isEmpty) break;
      offset += result.messages.length;
    }
    if (!mounted || captured != repository.epoch || current != version) return;
    setState(() {
      messages = refreshed;
      hasMore = more;
      pageOffset = firstOffset + refreshed.length;
      loading = false;
      error = null;
      for (final message in refreshed) {
        if (message.id == selected?.id) {
          selected = Message.fromJson({
            ...selected!.toJson(),
            'is_read': message.isRead,
          });
          break;
        }
      }
    });
  }

  String _filterReason(String id) {
    final rules = repository.filters.snapshot?.rules.where(
      (r) => r.ruleId == id,
    );
    return rules != null && rules.isNotEmpty
        ? personalRuleDescription(rules.first)
        : 'Совпало правило $id';
  }

  bool filtersOpen = false, filterNeedsOpen = false;
  bool get filteredSelection =>
      selected?.isCollapsed == true || filterNeedsOpen;
  Future<void> refreshPersonalView() async {
    final captured = repository.epoch, current = ++version;
    final previous = selected;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await repository.filters.refresh(cancellation: token);
      final target = max(20, messages.length), rows = <Message>[];
      var offset = firstOffset, more = false;
      while (rows.length < target) {
        final limit = min(100, target - rows.length);
        final page = threadId != null
            ? await repository.getThreadPage(
                conferenceId: conferenceId,
                threadId: threadId!,
                offset: offset,
                limit: limit,
                cancellation: token,
              )
            : await repository.getConferenceMessages(
                conferenceId: conferenceId,
                offset: offset,
                limit: limit,
                cancellation: token,
              );
        rows.addAll(page.messages);
        offset += page.messages.length;
        more = page.hasMore;
        if (!more || page.messages.isEmpty) break;
      }
      if (!mounted || captured != repository.epoch || current != version) {
        return;
      }
      setState(() {
        messages = rows;
        pageOffset = offset;
        hasMore = more;
        loading = false;
        if (previous != null) {
          final matches = rows.where((r) => r.id == previous.id);
          if (matches.isEmpty) {
            selected = null;
            filterNeedsOpen = false;
          } else if (matches.first.isCollapsed) {
            selected = matches.first;
            filterNeedsOpen = false;
            searchResult = searchResult?.message.id == previous.id
                ? MessageSearchResult(matches.first, {})
                : null;
          } else if (previous.isCollapsed || filterNeedsOpen) {
            selected = matches.first;
            filterNeedsOpen = true;
            searchResult = searchResult?.message.id == previous.id
                ? MessageSearchResult(matches.first, {})
                : null;
          }
        }
      });
    } catch (e) {
      if (mounted &&
          captured == repository.epoch &&
          current == version &&
          e is ApiException &&
          e.isAccessDenied) {
        await accessDenied();
      }
      if (mounted && captured == repository.epoch && current == version) {
        setState(() {
          loading = false;
          error = '$e';
          retry = refreshPersonalView;
        });
      }
    }
  }

  Future<void> managePersonalFilters([Message? message, String? field]) async {
    if (commandBusy || kind != AreaKind.echo || !canRead) return;
    final captured = repository.epoch;
    filter_wire.PersonalMessageFilter? initial;
    if (message != null && field != null) {
      final value = switch (field) {
        'author' => message.fromName,
        'address' => message.fromAddress,
        _ => message.subject,
      };
      if (value.trim().isEmpty) return;
      initial = filter_wire.PersonalMessageFilter(
        ruleId: newPersonalRuleId(),
        enabled: true,
        scope: filter_wire
            .PersonalMessageFilterScope
            .PERSONAL_MESSAGE_FILTER_SCOPE_CONFERENCE,
        conferenceId: conferenceId,
        authorContains: field == 'author' ? value : '',
        addressEquals: field == 'address' ? value : '',
        subjectContains: field == 'subject' ? value : '',
      );
    }
    setState(() => filtersOpen = true);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PersonalMessageFiltersScreen(
            repository: repository.filters,
            conferenceId: conferenceId,
            initialRule: initial,
          ),
        ),
      );
      if (mounted &&
          captured == repository.epoch &&
          repository.filters.supported == true) {
        await refreshPersonalView();
      }
    } finally {
      if (mounted) setState(() => filtersOpen = false);
    }
  }

  Future<void> showFilteredRow(Message message) async {
    final captured = repository.epoch;
    await open(message);
    if (mounted &&
        repository.epoch == captured &&
        selected?.id == message.id &&
        selected!.isCollapsed) {
      await revealPersonalMessage();
    }
  }

  Future<void> revealPersonalMessage() async {
    final source = selected;
    if (source == null || commandBusy) return;
    final captured = repository.epoch, current = ++version;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    final searching = searchResult != null;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await repository.getPresentation(
        conferenceId: conferenceId,
        messageId: source.id,
        reveal: source.isCollapsed,
        query: searching ? searchQuery : '',
        headersOnly: searchHeadersOnly,
        cancellation: token,
      );
      if (!mounted || captured != repository.epoch || current != version) {
        return;
      }
      setState(() {
        selected = result.message;
        filterNeedsOpen = false;
        loading = false;
        if (!result.message.isCollapsed) {
          opened.add('$conferenceId/${source.id}');
        }
        final index = messages.indexWhere((m) => m.id == source.id);
        if (index >= 0) messages[index] = result.message;
        searchResult = searching ? result : null;
        revealSearch = searching;
      });
    } catch (e) {
      if (!mounted || captured != repository.epoch || current != version) {
        return;
      }
      if (e is ApiException && e.isAccessDenied) await accessDenied();
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
          retry = revealPersonalMessage;
        });
      }
    }
  }

  bool technicalOpen = false;
  Future<void> showTechnicalData(String messageId) async {
    if (commandBusy || !canRead || activeConference.unsupportedFormat) return;
    final captured = repository.epoch;
    final previousFocus = FocusManager.instance.primaryFocus;
    setState(() => technicalOpen = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => MessageTechnicalDialog(
          repository: repository,
          conferenceId: conferenceId,
          messageId: messageId,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => technicalOpen = false);
        if (repository.epoch == captured &&
            previousFocus?.context != null &&
            previousFocus!.canRequestFocus) {
          previousFocus.requestFocus();
        }
      }
    }
  }

  bool composerOpen = false;
  bool get commandBusy =>
      loading ||
      bulkBusy ||
      unreadBusy ||
      searchBusy ||
      searchDialogOpen ||
      composerOpen ||
      technicalOpen ||
      filtersOpen;

  String? commandReason(DesktopCommand command) {
    if (commandBusy) return 'Операция выполняется';
    if (activeConference.unsupportedFormat) {
      return 'Формат области не поддерживается';
    }
    if (command == DesktopCommand.compose) {
      return canPost ? null : 'Нет права публикации';
    }
    if (!canRead) return 'Нет права чтения';
    if (command == DesktopCommand.unread) {
      if (!unreadNavigation) return 'Только в обычной эхе, вне цепочки';
      return canNavigate(1) ? null : 'Дальнейших непрочитанных сообщений нет';
    }
    if (command == DesktopCommand.reply && filteredSelection) {
      return 'Сначала покажите письмо';
    }
    if (command == DesktopCommand.reply && !canPost) {
      return 'Нет права публикации';
    }
    if ((command == DesktopCommand.reply || command == DesktopCommand.list) &&
        selected == null) {
      return 'Нет открытого письма';
    }
    return null;
  }

  void returnToList() {
    if (commandReason(DesktopCommand.list) != null) return;
    if (personalMailbox) {
      unawaited(load(preserveThread: true));
    } else {
      setState(() => selected = null);
    }
  }

  Map<DesktopCommand, CommandAction> get readerCommands => {
    for (final command in DesktopCommand.values.where(
      (c) => c != DesktopCommand.help,
    ))
      command: commandReason(command) != null
          ? CommandAction.disabled(commandReason(command)!)
          : CommandAction.enabled(switch (command) {
              DesktopCommand.unread => () => unawaited(navigate(1)),
              DesktopCommand.reply => () => unawaited(compose(reply: true)),
              DesktopCommand.compose => () => unawaited(compose()),
              DesktopCommand.search => () => unawaited(showSearch()),
              DesktopCommand.list => returnToList,
              DesktopCommand.help => () {},
            }),
  };

  @override
  Widget build(BuildContext context) => CommandScope(
    actions: readerCommands,
    child: NotificationListener<UserScrollNotification>(
      onNotification: (event) {
        if (event.direction != ScrollDirection.idle && revealSearch) {
          setState(() => revealSearch = false);
        }
        return false;
      },
      child: buildReader(context),
    ),
  );

  Widget buildReader(BuildContext context) {
    final compact =
        LayoutWidth.of(MediaQuery.sizeOf(context).width) == LayoutWidth.compact;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          conferenceName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!compact || !canRead || activeConference.unsupportedFormat)
            const CommandHelpButton(),
          if (canRead && !activeConference.unsupportedFormat)
            CommandIconButton(
              command: DesktopCommand.search,
              label: 'Поиск по письмам',
              icon: Icons.search,
              onPressed: commandReason(DesktopCommand.search) == null
                  ? showSearch
                  : null,
            ),
          if (!compact &&
              canRead &&
              kind == AreaKind.echo &&
              !activeConference.unsupportedFormat)
            IconButton(
              tooltip: 'Персональные фильтры',
              onPressed: commandBusy ? null : () => managePersonalFilters(),
              icon: const Icon(Icons.filter_alt_outlined),
            ),
          if (canRead && !activeConference.unsupportedFormat)
            PopupMenuButton<String>(
              tooltip: 'Действия области',
              enabled: !bulkBusy && !unreadBusy && !loading,
              onSelected: (action) {
                if (action == 'refresh') {
                  load(preserveThread: personalMailbox);
                } else if (action == 'filters') {
                  managePersonalFilters();
                } else if (action == 'help') {
                  CommandHelpButton.show(context);
                } else if (action.startsWith('filter:')) {
                  managePersonalFilters(selected!, action.substring(7));
                } else if (action == 'technical') {
                  showTechnicalData(selected!.id);
                } else if (action == 'unread') {
                  markSelectedUnread();
                } else {
                  markAreaRead();
                }
              },
              itemBuilder: (_) => [
                if (compact) ...[
                  PopupMenuItem(
                    value: 'refresh',
                    enabled: !commandBusy,
                    child: const ListTile(
                      leading: Icon(Icons.refresh),
                      title: Text('Обновить'),
                    ),
                  ),
                  if (kind == AreaKind.echo)
                    PopupMenuItem(
                      value: 'filters',
                      enabled: !commandBusy,
                      child: const ListTile(
                        leading: Icon(Icons.filter_alt_outlined),
                        title: Text('Персональные фильтры'),
                      ),
                    ),
                  if (desktopCommandsEnabled())
                    const PopupMenuItem(
                      value: 'help',
                      child: ListTile(
                        leading: Icon(Icons.help_outline),
                        title: Text('Горячие клавиши'),
                      ),
                    ),
                ],
                if (selected != null && kind == AreaKind.echo)
                  for (final entry in {
                    'author': 'Свернуть по автору',
                    'address': 'Свернуть по адресу',
                    'subject': 'Свернуть по теме',
                  }.entries)
                    PopupMenuItem(
                      value: 'filter:${entry.key}',
                      child: Text(entry.value),
                    ),
                if (selected != null)
                  const PopupMenuItem(
                    value: 'technical',
                    child: Text('Технические данные'),
                  ),
                if (selected != null)
                  const PopupMenuItem(
                    value: 'unread',
                    child: Text('Пометить непрочитанным'),
                  ),
                PopupMenuItem(
                  value: 'read',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.done_all),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          bulkOperation == null
                              ? 'Отметить всё прочитанным'
                              : 'Проверить/повторить',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          if (canRead && (!compact || activeConference.unsupportedFormat))
            IconButton(
              onPressed: loading
                  ? null
                  : () => load(preserveThread: personalMailbox),
              icon: const Icon(Icons.refresh),
              tooltip: 'Обновить',
            ),
          if (canPost)
            CommandIconButton(
              command: DesktopCommand.compose,
              label: 'Новое сообщение',
              icon: Icons.create,
              onPressed: commandReason(DesktopCommand.compose) == null
                  ? () => compose()
                  : null,
            ),
        ],
      ),
      bottomNavigationBar: selected == null && !unreadNavigation
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: ReaderNavigation(
                  previous: canNavigate(-1) ? () => navigate(-1) : null,
                  next: !commandBusy && canNavigate(1)
                      ? () => navigate(1)
                      : null,
                  nextTooltip: unreadNavigation
                      ? commandTooltip(
                          DesktopCommand.unread,
                          'Следующее непрочитанное',
                        )
                      : 'Следующее',
                ),
              ),
            ),
      body: AdaptiveContent(
        maxWidth: selected == null
            ? AdaptiveContent.listWidth
            : AdaptiveContent.readerWidth,
        child: Column(
          children: [
            if (searchQuery.isNotEmpty)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Поиск: $searchQuery'),
                  TextButton(
                    onPressed: loading ? null : findNext,
                    child: const Text('Найти далее'),
                  ),
                  TextButton(
                    onPressed: searchBusy
                        ? cancelSearch
                        : () => setState(() => resetSearch(clearQuery: true)),
                    child: Text(
                      searchBusy ? 'Отменить поиск' : 'Закрыть поиск',
                    ),
                  ),
                ],
              ),
            if (searchNotice != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(searchNotice!),
              ),
            if (unreadNavigation &&
                !loading &&
                !canNavigate(1) &&
                error == null)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Дальнейших непрочитанных сообщений нет'),
              ),
            if (!canRead)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  canPost
                      ? "Разрешена только отправка сообщений"
                      : "Нет доступа к конференции",
                ),
              ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(error!),
                    TextButton(
                      onPressed: loading ? null : retry,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            if (personalMailbox && mailboxUpdatedAt != null && error == null)
              Text(
                'Обновлено с сервера: ${mailboxUpdatedAt!.toIso8601String().substring(11, 19)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            if (personalMailbox && threadId != null)
              TextButton(
                onPressed: loading ? null : () => load(),
                child: const Text('Все письма'),
              ),
            if (personalMailbox &&
                selected == null &&
                threadId == null &&
                lastOpenedMessageId != null &&
                error == null)
              TextButton.icon(
                onPressed: loading ? null : continueReading,
                icon: const Icon(Icons.bookmark_outline),
                label: const Text('Продолжить с последнего открытого письма'),
              ),
            if (selected != null && filteredSelection)
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected!.subject,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${selected!.fromName} <${selected!.fromAddress}>',
                        ),
                        Text(
                          filteredSelection && selected!.isCollapsed
                              ? 'Письмо свернуто персональным фильтром'
                              : 'Правило больше не действует. Письмо доступно к чтению.',
                        ),
                        for (final id in selected!.matchedFilterIds)
                          Text(_filterReason(id)),
                        FilledButton(
                          onPressed: commandBusy ? null : revealPersonalMessage,
                          child: Text(
                            selected!.isCollapsed ? 'Показать' : 'Открыть',
                          ),
                        ),
                        TextButton(
                          onPressed: commandBusy
                              ? null
                              : () => managePersonalFilters(),
                          child: const Text('Управление правилами'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (selected != null && !filteredSelection)
              Expanded(
                child: SingleChildScrollView(
                  controller: bodyController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: commandTooltip(
                          DesktopCommand.list,
                          'К списку',
                        ),
                        excludeFromSemantics: true,
                        child: TextButton(
                          onPressed: commandReason(DesktopCommand.list) == null
                              ? returnToList
                              : null,
                          child: const Text('К списку'),
                        ),
                      ),
                      if (personalMailbox &&
                          selected!.direction != MailDirection.unspecified)
                        Text(
                          selected!.direction == MailDirection.outgoing
                              ? 'Исходящее'
                              : 'Входящее',
                        ),
                      if (searchResult == null) ...[
                        Text(
                          'От: ${_correspondent(selected!.fromName, selected!.fromAddress)}',
                        ),
                        Text(
                          'К: ${_correspondent(selected!.toName, selected!.toAddress)}',
                        ),
                      ] else ...[
                        correspondent(
                          'От:',
                          selected!.fromName,
                          selected!.fromAddress,
                          1,
                          2,
                        ),
                        correspondent(
                          'К:',
                          selected!.toName,
                          selected!.toAddress,
                          3,
                          4,
                        ),
                      ],
                      Text(
                        selected!.date.toLocal().toString().split('.').first,
                      ),
                      if (searchResult == null)
                        Text(
                          selected!.subject,
                          style: Theme.of(context).textTheme.titleLarge,
                        )
                      else
                        searchHeader(
                          selected!.subject,
                          5,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      const Divider(),
                      UueBody(
                        key: ValueKey(
                          '${selected!.id}:${selected!.body.hashCode}:${repository.epoch}',
                        ),
                        repository: repository.uue,
                        conference: conferenceId,
                        message: selected!,
                        searchRanges: searchResult?.matches[6] ?? const [],
                        revealSearch:
                            revealSearch && searchResult?.firstField == 6,
                      ),
                      MessageActions(
                        actions: [
                          if (canPost)
                            MessageAction(
                              label: kind.replyLabel,
                              icon: Icons.reply,
                              tooltip: commandTooltip(
                                DesktopCommand.reply,
                                kind.replyLabel,
                              ),
                              onPressed:
                                  commandReason(DesktopCommand.reply) == null
                                  ? () => compose(reply: true)
                                  : null,
                              variantsLabel: 'Вид ответа',
                              onVariant:
                                  commandReason(DesktopCommand.reply) == null
                                  ? (quoted) =>
                                        compose(reply: true, quoted: quoted)
                                  : null,
                            ),
                          if (canRead && kind == AreaKind.echo) ...[
                            MessageAction(
                              label: 'Переслать',
                              icon: Icons.forward,
                              onPressed: commandBusy
                                  ? null
                                  : () => compose(forward: true),
                            ),
                            for (final personal in [true, false])
                              MessageAction(
                                label: personal
                                    ? 'Ответить лично'
                                    : 'Ответить в другую область…',
                                icon: personal
                                    ? Icons.person_outline
                                    : Icons.reply_all,
                                onPressed: commandBusy
                                    ? null
                                    : () => compose(
                                        crossAreaReply: true,
                                        personalOnly: personal,
                                      ),
                                variantsLabel: personal
                                    ? 'Вид личного ответа'
                                    : 'Вид ответа в другую область',
                                onVariant: commandBusy
                                    ? null
                                    : (quoted) => compose(
                                        crossAreaReply: true,
                                        personalOnly: personal,
                                        quoted: quoted,
                                      ),
                              ),
                          ],
                          MessageAction(
                            label: 'Цепочка сообщений',
                            icon: Icons.account_tree_outlined,
                            onPressed: commandBusy
                                ? null
                                : () => load(thread: true),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (selected == null && messages.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  key: const PageStorageKey('message-list'),
                  controller: listController,
                  itemCount: messages.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return TextButton(
                        onPressed: loading ? null : () => load(more: true),
                        child: const Text('Загрузить ещё'),
                      );
                    }
                    final message = messages[index];
                    return ListTile(
                      title: Text(
                        message.subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${personalMailbox && message.direction != MailDirection.unspecified ? (message.direction == MailDirection.outgoing ? 'Исходящее · ' : 'Входящее · ') : ''}${message.fromName}\n${(message.isCollapsed ? "Письмо свернуто персональным фильтром" : message.bodyPreview ?? "").replaceAll(RegExp(r'\s+'), ' ').trim()}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      leading: Icon(message.isRead ? Icons.drafts : Icons.mail),
                      trailing: canRead && !activeConference.unsupportedFormat
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (message.isCollapsed)
                                  TextButton(
                                    onPressed: commandBusy
                                        ? null
                                        : () => showFilteredRow(message),
                                    child: const Text('Показать'),
                                  ),
                                PopupMenuButton<String>(
                                  tooltip: 'Действия письма',
                                  enabled: !commandBusy,
                                  onSelected: (action) {
                                    if (action == 'technical') {
                                      showTechnicalData(message.id);
                                    } else if (action == 'show') {
                                      showFilteredRow(message);
                                    } else {
                                      managePersonalFilters(message, action);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (message.isCollapsed)
                                      const PopupMenuItem(
                                        value: 'show',
                                        child: Text('Показать'),
                                      ),
                                    if (kind == AreaKind.echo)
                                      for (final entry in {
                                        'author': 'Свернуть по автору',
                                        'address': 'Свернуть по адресу',
                                        'subject': 'Свернуть по теме',
                                      }.entries)
                                        PopupMenuItem(
                                          value: entry.key,
                                          child: Text(entry.value),
                                        ),
                                    const PopupMenuItem(
                                      value: 'technical',
                                      child: Text('Технические данные'),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : null,
                      onTap: loading ? null : () => open(message),
                    );
                  },
                ),
              ),
            if (canRead &&
                selected == null &&
                !loading &&
                error == null &&
                messages.isEmpty)
              const Expanded(child: Center(child: Text('Сообщений нет'))),
          ],
        ),
      ),
    );
  }
}

class _ComposeScreen extends StatefulWidget {
  final MessageRepository repository;
  final Future<void> Function() onAccessDenied;
  final String conferenceId, conferenceName, conferenceDescription;
  final Future<TemplateBundle?> Function()? loadTemplate;
  final bool quoted;
  final ConferenceRepository? conferences;
  final Conference? destination;
  final Message? original;
  final bool forward;
  final bool crossAreaReply;
  final AreaKind kind;
  const _ComposeScreen({
    required this.repository,
    required this.onAccessDenied,
    required this.conferenceId,
    required this.conferenceName,
    required this.conferenceDescription,
    this.loadTemplate,
    this.quoted = true,
    this.conferences,
    this.destination,
    this.original,
    required this.forward,
    this.crossAreaReply = false,
    required this.kind,
  });
  @override
  State<_ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<_ComposeScreen> {
  final toName = TextEditingController(),
      toAddress = TextEditingController(),
      subject = TextEditingController(),
      body = FtnTextController();
  String operationId = MessageRepository.newOperationId();
  final cancellation = RpcCancellation();
  bool sending = false, uncertain = false;
  bool templateReady = false;
  String? templateError;
  bool customTemplate = false;
  SelectedUueFile? attachment;
  UueCapabilities? uueLimits;
  bool uueLoading = true;
  String? uueError;
  int uploaded = 0;
  UueDraft? frozenUue;
  final composerScroll = ScrollController();
  Future<void> loadUueLimits() async {
    setState(() {
      uueLoading = true;
      uueError = null;
    });
    try {
      final limits = await widget.repository.uue.capabilities();
      if (mounted && widget.repository.epoch == epoch) {
        setState(() {
          uueLimits = limits;
          uueLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          uueLoading = false;
          uueError = 'Не удалось получить лимиты UUE';
        });
      }
    }
  }

  Future<void> pickFile() async {
    final limits = uueLimits;
    if (!templateReady || limits == null || sending || uncertain) return;
    try {
      final file = await uueFiles.pick(limits.fileBytes);
      if (mounted && widget.repository.epoch == epoch && file != null) {
        setState(() {
          attachment = file;
          error = null;
          operationId = MessageRepository.newOperationId();
        });
      }
    } catch (e) {
      if (mounted && widget.repository.epoch == epoch) {
        setState(
          () => error = e is ValidationException
              ? e.message
              : 'Не удалось прочитать выбранный файл. Выберите его ещё раз.',
        );
      }
    }
  }

  Conference? destination;
  List<Conference> crosspostAreas = [];
  AreaKind get targetKind => destination?.kind ?? widget.kind;
  String? get replyId =>
      widget.forward || widget.crossAreaReply ? null : widget.original?.id;
  bool destinationTypeChanged = false;
  bool get canCrosspost =>
      !widget.crossAreaReply && targetKind == AreaKind.echo;
  String get primaryId => destination?.id ?? widget.conferenceId;
  String get primaryName => destination?.name ?? widget.conferenceName;
  String? frozenCrosspostSignature;
  ({
    String conferenceId,
    List<String> additional,
    String operationId,
    String toName,
    String toAddress,
    String subject,
    String body,
    String? inReplyTo,
  })?
  frozenCrosspost;
  bool allowClose = false;
  Future<void> selectCrosspost() async {
    final selected = await Navigator.push<List<Conference>>(
      context,
      MaterialPageRoute(
        builder: (_) => CrosspostDestinations(
          repository: widget.conferences!,
          primaryId: primaryId,
          primaryName: primaryName,
          selected: crosspostAreas,
        ),
      ),
    );
    if (!mounted || widget.repository.epoch != epoch || selected == null) {
      return;
    }
    setState(() {
      crosspostAreas = selected;
      operationId = MessageRepository.newOperationId();
    });
  }

  Future<bool> confirmClose() async {
    if (crosspostAreas.isEmpty || (!sending && !uncertain)) return true;
    if (sending) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: const Text('Закрыть незавершённую отправку?'),
            content: const Text(
              'Часть копий могла сохраниться. После закрытия повтор из этого редактора будет недоступен.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Продолжить'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Закрыть'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String? error;
  late final int epoch;
  late final StreamSubscription<int> subscription;
  @override
  void initState() {
    super.initState();
    appUpdates.guardExit(
      this,
      // Не завершаем приложение, пока открыт редактор или ожидается отправка.
      () => false,
    );
    epoch = widget.repository.epoch;
    unawaited(loadUueLimits());
    destination = widget.destination;
    subscription = widget.repository.sessionChanges.listen((_) {
      unawaited(cancellation.cancel());
      if (!mounted) return;
      setState(() => allowClose = true);
      unawaited(
        WidgetsBinding.instance.endOfFrame.then((_) {
          if (!mounted) return;
          final route = ModalRoute.of(context)!;
          Navigator.popUntil(context, (candidate) => candidate == route);
          if (mounted) Navigator.pop(context, false);
        }),
      );
    });
    final original = widget.original;
    toName.text = original != null && !widget.forward
        ? widget.crossAreaReply
              ? original.fromName
              : original.replyName
        : widget.kind == AreaKind.netmail
        ? ''
        : 'All';
    toAddress.text = original != null && !widget.forward
        ? widget.crossAreaReply
              ? original.fromAddress
              : original.replyAddress
        : '';
    if (original != null) {
      final prefix = widget.forward ? 'Fwd: ' : 'Re: ';
      subject.text =
          original.subject.toLowerCase().startsWith(prefix.trim().toLowerCase())
          ? original.subject
          : '$prefix${original.subject}';
      if (widget.forward) {
        body.text =
            '--- Forwarded message ---\nArea: ${widget.conferenceId}\nFrom: ${original.fromName} <${original.fromAddress}>\nDate: ${original.date}\nSubject: ${original.subject}\n\n${original.body}';
      } else if (widget.quoted) {
        body.text = quoteReply(original.body, original.fromName);
        body.selection = TextSelection.collapsed(offset: body.text.length);
      }
    }
    unawaited(initializeTemplate());
  }

  Future<void> initializeTemplate() async {
    try {
      final bundle =
          await (widget.loadTemplate?.call() ??
              TemplateSettings.load().then((settings) => settings.read()));
      if (!mounted || widget.repository.epoch != epoch) return;
      if (bundle != null) {
        final profile = await widget.repository.getAuthorProfile(
          cancellation: cancellation,
        );
        final footer = await MessageFooterSettings.load();
        if (!mounted || widget.repository.epoch != epoch) return;
        final result = TemplateEngine().render(
          bundle.text,
          TemplateContext(
            action: widget.forward
                ? TemplateAction.forward
                : widget.original == null
                ? TemplateAction.newMessage
                : widget.quoted
                ? TemplateAction.quoted
                : TemplateAction.reply,
            kind: targetKind,
            original: widget.original,
            name: profile.name,
            address: profile.address,
            toName: toName.text,
            toAddress: toAddress.text,
            subject: subject.text,
            area: primaryName,
            description:
                destination?.description ?? widget.conferenceDescription,
            originalArea: widget.conferenceName,
            originalDescription: widget.conferenceDescription,
            version: footer.version,
            revision: footer.revision,
            platform: kIsWeb ? 'Web' : defaultTargetPlatform.name,
            tagline: footer.tagline,
            origin: footer.origin,
            uptime: applicationUptime.elapsed,
          ),
        );
        if (!result.valid) {
          throw FormatException(
            result.diagnostics.where((d) => d.error).join('\n'),
          );
        }
        body.text = result.body;
        body.selection = TextSelection.collapsed(offset: result.cursor);
        subject.text = result.subject;
        toName.text = result.toName;
        customTemplate = true;
      }
      setState(() => templateReady = true);
    } catch (e) {
      if (mounted && widget.repository.epoch == epoch) {
        setState(() => templateError = 'Не удалось применить шаблон: $e');
      }
    }
  }

  @override
  void dispose() {
    appUpdates.removeExitGuard(this);
    unawaited(cancellation.cancel());
    unawaited(subscription.cancel());
    composerScroll.dispose();
    toName.dispose();
    toAddress.dispose();
    subject.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> changeDestination() async {
    final target = await Navigator.push<Conference>(
      context,
      MaterialPageRoute(
        builder: (_) => widget.crossAreaReply
            ? ReplyDestination(
                repository: widget.conferences!,
                sourceId: widget.conferenceId,
              )
            : ForwardDestination(repository: widget.conferences!),
      ),
    );
    if (!mounted || widget.repository.epoch != epoch || target == null) return;
    if (widget.crossAreaReply &&
        targetKind == AreaKind.netmail &&
        target.kind == AreaKind.echo) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Опубликовать ответ в эхе?'),
          content: Text(
            'Ответ в ${target.name} будет доступен всем участникам эхи.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Выбрать эху'),
            ),
          ],
        ),
      );
      if (!mounted || widget.repository.epoch != epoch || confirmed != true) {
        return;
      }
    }
    setState(() {
      destinationTypeChanged =
          destinationTypeChanged || targetKind != target.kind;
      destination = target;
      frozenUue = null;
      crosspostAreas.removeWhere((area) => area.id == target.id);
      operationId = MessageRepository.newOperationId();
    });
  }

  Future<void> send() async {
    if (!templateReady || sending || widget.repository.epoch != epoch) return;
    setState(() {
      sending = true;
      error = null;
    });
    var submitted = false;
    try {
      if ((widget.forward || widget.crossAreaReply) && !uncertain) {
        final target = destination;
        if (target == null) {
          throw const ValidationException(message: 'Выберите эху назначения');
        }
        final current = await widget.conferences!.getConferenceById(
          target.id,
          cancellation: cancellation,
        );
        if (!mounted || widget.repository.epoch != epoch) return;
        if (current == null ||
            current.id != target.id ||
            (widget.crossAreaReply
                ? !isReplyDestination(current, widget.conferenceId) ||
                      current.kind != target.kind
                : current.kind != AreaKind.echo || !current.canPost)) {
          if (!widget.crossAreaReply) setState(() => destination = null);
          throw const ValidationException(
            message: 'Публикация в выбранную область недоступна. Проверьте назначение или выберите другое.',
          );
        }
      }
      if (targetKind == AreaKind.netmail &&
          (toName.text.trim().isEmpty ||
              !RegExp(r'^[1-9][0-9]*:[1-9][0-9]*/[0-9]+(?:\.[0-9]+)?$')
                  .hasMatch(toAddress.text))) {
        throw const ValidationException(
          message: 'Укажите имя и полный FTN-адрес получателя',
        );
      }
      submitted = true;
      if (crosspostAreas.isNotEmpty) {
        final signature = [
          primaryId,
          ...crosspostAreas.map((a) => a.id),
          toName.text,
          toAddress.text,
          subject.text,
          body.text,
          replyId ?? '',
        ].join('\u0000');
        if (!uncertain && frozenCrosspostSignature != signature) {
          operationId = MessageRepository.newOperationId();
          frozenCrosspostSignature = signature;
        }
        if (!uncertain) {
          frozenCrosspost = (
            conferenceId: primaryId,
            additional: List.unmodifiable(crosspostAreas.map((a) => a.id)),
            operationId: operationId,
            toName: toName.text,
            toAddress: toAddress.text,
            subject: subject.text,
            body: body.text,
            inReplyTo: replyId,
          );
        }
        final draft = frozenCrosspost!;
        final result = await widget.repository.sendCrosspost(
          conferenceId: draft.conferenceId,
          additionalConferenceIds: draft.additional,
          operationId: draft.operationId,
          toName: draft.toName,
          toAddress: draft.toAddress,
          subject: draft.subject,
          body: draft.body,
          inReplyTo: draft.inReplyTo,
          cancellation: cancellation,
        );
        if (!mounted || widget.repository.epoch != epoch) return;
        if (!result.complete) {
          setState(() {
            sending = false;
            uncertain = true;
            error =
                'Сохранено копий: ${result.saved.length}/${result.total}. Повторите отправку, чтобы продолжить.';
          });
          return;
        }
      } else if (attachment != null) {
        frozenUue ??= UueDraft(
          conference: primaryId,
          operation: operationId,
          subject: subject.text,
          body: body.text,
          toName: toName.text,
          toAddress: toAddress.text,
          reply: replyId ?? '',
          file: attachment!,
          useFooter: targetKind == AreaKind.echo,
        );
        final result = await widget.repository.uue.send(
          frozenUue!,
          cancellation: cancellation,
          progress: (count, total) {
            if (mounted) setState(() => uploaded = count);
          },
        );
        if (!mounted || widget.repository.epoch != epoch) return;
        if (!result.complete) {
          setState(() {
            sending = false;
            uncertain = true;
            error =
                'Сохранено частей: ${result.saved}/${result.total}. Повторите отправку, чтобы продолжить.';
          });
          return;
        }
      } else {
        await widget.repository.sendMessage(
          conferenceId: primaryId,
          toName: toName.text,
          toAddress: toAddress.text,
          subject: subject.text,
          body: body.text,
          inReplyTo: replyId,
          operationId: operationId,
          useFooter: targetKind == AreaKind.echo,
          cancellation: cancellation,
        );
      }
      if (widget.forward || widget.crossAreaReply) {
        await widget.conferences!.clearCache();
      }
      if (!mounted || widget.repository.epoch != epoch) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение сохранено локально')),
      );
      if (crosspostAreas.isNotEmpty) {
        setState(() => allowClose = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted || widget.repository.epoch != epoch) return;
      if (crosspostAreas.isEmpty && e is ApiException && e.isAccessDenied) {
        if (widget.forward && !uncertain) {
          destination = null;
        } else if (!widget.forward && !widget.crossAreaReply) {
          await widget.onAccessDenied();
        }
      }
      if (!mounted || widget.repository.epoch != epoch) return;
      setState(() {
        sending = false;
        if (crosspostAreas.isEmpty &&
            !uncertain &&
            !(e is ApiException && e.hasUncertainCommit)) {
          operationId = MessageRepository.newOperationId();
          frozenUue = null;
        }
        uncertain =
            uncertain ||
            (submitted &&
                (crosspostAreas.isNotEmpty
                    ? e is! ApiException ||
                          !const {3, 5, 6, 12, 16}.contains(e.statusCode)
                    : e is ApiException && e.hasUncertainCommit));
        if (e is ApiException &&
            e.statusCode == 12 &&
            crosspostAreas.isNotEmpty) {
          error = 'Сервер не поддерживает кросспостинг. Обновите сервер; черновик сохранён в редакторе.';
          return;
        }
        error = uncertain
            ? 'Подтверждение не получено. Повторите отправку с тем же текстом: дубликат не будет создан.'
            : e.toString();
      });
      if (widget.forward &&
          destination == null &&
          !uncertain &&
          composerScroll.hasClients) {
        FocusScope.of(context).unfocus();
        composerScroll.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) => CommandScope(
    readerUnavailableReason: 'Команды читателя недоступны в редакторе',
    child: buildComposer(context),
  );

  Widget sendButton() => ElevatedButton(
    onPressed: sending || !templateReady ? null : send,
    child: Text(
      sending
          ? 'Сохранение...'
          : uncertain
          ? 'Повторить отправку'
          : 'Отправить',
    ),
  );

  Widget buildComposer(BuildContext context) => PopScope(
    canPop: allowClose || crosspostAreas.isEmpty || (!sending && !uncertain),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop) return;
      if (await confirmClose() && context.mounted) {
        setState(() {
          uncertain = false;
          sending = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Сообщение'),
        actions: [
          const CommandHelpButton(),
          if (canCrosspost)
            PopupMenuButton<String>(
              tooltip: 'Дополнительно',
              enabled:
                  templateReady &&
                  widget.conferences != null &&
                  !sending &&
                  !uncertain,
              onSelected: (_) => selectCrosspost(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'crosspost',
                  enabled: attachment == null,
                  child: Text(
                    attachment == null
                        ? 'Кросспостинг'
                        : 'Кросспостинг — только текст, уберите UUE',
                  ),
                ),
              ],
            ),
        ],
      ),
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : SafeArea(
              child: AdaptiveContent(
                maxWidth: AdaptiveContent.formWidth,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: sendButton(),
                ),
              ),
            ),
      body: AdaptiveContent(
        maxWidth: AdaptiveContent.formWidth,
        child: ListView(
          controller: composerScroll,
          padding: const EdgeInsets.all(16),
          children: [
            if (error != null) Text(error!),

            if (!templateReady && templateError == null)
              const LinearProgressIndicator(),
            if (templateError != null) ...[
              Text(templateError!),
              TextButton(
                onPressed: () => setState(() {
                  templateReady = true;
                  templateError = null;
                }),
                child: const Text('Использовать штатное оформление'),
              ),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/settings'),
                child: const Text('Открыть настройки шаблона'),
              ),
            ],
            if (widget.forward && customTemplate)
              const Text(
                'Шаблон применён при открытии. После смены эхи проверьте оформление вручную.',
              ),
            Text(
              '${targetKind == AreaKind.echo
                  ? 'Эха'
                  : targetKind == AreaKind.netmail
                  ? 'Netmail'
                  : targetKind.groupLabel}: ${destination?.name ?? (widget.forward ? "не выбрана" : widget.conferenceName)}',
            ),
            if (widget.crossAreaReply && targetKind == AreaKind.netmail)
              const Text('Личный ответ получателю через Netmail.'),
            if (widget.crossAreaReply && destinationTypeChanged)
              const Text(
                'Шаблон уже применён. После смены типа области проверьте оформление вручную.',
              ),
            if (crosspostAreas.isNotEmpty) ...[
              Text(
                'Кросспостинг: ${crosspostAreas.map((a) => a.name).join(', ')}',
              ),
              const Text('Блок в начале каждой копии:'),
              SelectableText(
                crosspostHeader(primaryName, crosspostAreas),
                style: ftnTextStyle(Theme.of(context).colorScheme),
              ),
            ],
            if (widget.original != null &&
                !widget.forward &&
                targetKind == AreaKind.echo)
              const Text(
                'Ответ будет опубликован в эхе и доступен всем участникам.',
              ),
            if (widget.forward || widget.crossAreaReply) ...[
              Text(
                'Источник: ${widget.conferenceName} (${widget.conferenceId})',
              ),
              TextButton(
                onPressed: !templateReady || sending || uncertain
                    ? null
                    : changeDestination,
                child: Text(
                  widget.crossAreaReply
                      ? 'Изменить область назначения'
                      : 'Изменить эху назначения',
                ),
              ),
            ],
            TextField(
              controller: toName,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              enabled:
                  templateReady &&
                  !sending &&
                  !uncertain &&
                  (widget.original == null ||
                      widget.forward ||
                      widget.crossAreaReply),
              decoration: const InputDecoration(labelText: 'Получатель'),
            ),
            TextField(
              controller: toAddress,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              enabled:
                  templateReady &&
                  !sending &&
                  !uncertain &&
                  (widget.original == null ||
                      widget.forward ||
                      widget.crossAreaReply),
              decoration: const InputDecoration(
                labelText: 'FTN-адрес получателя',
              ),
            ),
            TextField(
              controller: subject,
              enabled: templateReady && !sending && !uncertain,
              decoration: const InputDecoration(labelText: 'Тема'),
            ),
            TextField(
              controller: body,
              style: ftnTextStyle(Theme.of(context).colorScheme),
              enabled: templateReady && !sending && !uncertain,
              minLines: 6,
              maxLines: null,
              decoration: const InputDecoration(labelText: 'Текст'),
            ),
            if (widget.kind == AreaKind.echo ||
                widget.kind == AreaKind.netmail) ...[
              if (crosspostAreas.isNotEmpty)
                const Text(
                  'Чтобы прикрепить UUE-файл, сначала снимите выбор эх кросспостинга.',
                ),
              TextButton.icon(
                onPressed:
                    sending ||
                        uncertain ||
                        uueLimits == null ||
                        crosspostAreas.isNotEmpty
                    ? null
                    : pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(
                  uueLoading ? 'Проверка UUE...' : 'Прикрепить файл UUE',
                ),
              ),
              if (!uueLoading && uueLimits == null)
                if (uueError != null)
                  TextButton(
                    onPressed: loadUueLimits,
                    child: Text('$uueError. Повторить'),
                  )
                else
                  const Text('Сервер не поддерживает отправку UUE'),
              if (attachment != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.insert_drive_file),
                    title: Text(attachment!.name),
                    subtitle: Text(
                      '${attachment!.bytes.length} байт · примерно ${((attachment!.bytes.length * 62 / 45 + body.text.length + 256) / ((uueLimits?.partBytes ?? 32768) - 512)).ceil()} частей${sending ? " · загружено $uploaded байт" : ""}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Убрать файл',
                      onPressed: sending || uncertain
                          ? null
                          : () => setState(() {
                              attachment = null;
                              frozenUue = null;
                              operationId = MessageRepository.newOperationId();
                            }),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
            ],
            if (MediaQuery.viewInsetsOf(context).bottom > 0) sendButton(),
          ],
        ),
      ),
    ),
  );
}
