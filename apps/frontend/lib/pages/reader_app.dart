import '../models/conference.dart';
import '../api/api_exceptions.dart';
import '../utils/refresh_on_resume.dart';

import 'dart:async';

import '../api/api_transport.dart';

import 'package:flutter/material.dart';
import 'package:fido/fido_conference.dart';
import 'package:fido/conference_card.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/main.dart';
import 'package:fido/utils/debouncer.dart';
import 'package:fido/pages/bookmarks_screen.dart';
import 'package:fido/pages/history_screen.dart';
import 'package:fido/pages/profile_screen.dart';
import 'package:fido/repositories/conference_repository.dart';
import 'package:fido/repositories/account_repository.dart';
import 'package:fido/repositories/message_repository.dart';

class MainScreen extends StatefulWidget {
  final ConferenceRepository? repository;

  const MainScreen({super.key, this.repository});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with RefreshOnResume<MainScreen> {
  @override
  bool get resumeRefreshEnabled => _selectedBottomIndex == 0;
  @override
  Future<void> refreshOnResume() => _refreshConferences();

  List<FidoConference> conferences = [];
  bool isLoading = true;
  String errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _debouncer = Debouncer(duration: Duration(milliseconds: 300));
  int _selectedBottomIndex = 0;
  int _requestVersion = 0;
  RpcCancellation? _cancellation;
  StreamSubscription<int>? _sessionSubscription;
  bool _hasMore = false;
  final Set<String> _pendingBookmarks = {};
  String? _bookmarkError;
  late final AccountRepository _account;

  ConferenceRepository get _repository =>
      widget.repository ?? conferenceRepository;

  @override
  void initState() {
    super.initState();
    _account = AccountRepository(
      _repository.transport,
      onBookmarksChanged: _repository.clearCache,
    );
    _sessionSubscription = _repository.sessionChanges.listen((_) {
      conferences = [];
      _pendingBookmarks.clear();
      _bookmarkError = null;
      _loadConferences();
    });
    _loadConferences();
  }

  @override
  void dispose() {
    ++_requestVersion;
    unawaited(_cancellation?.cancel());
    unawaited(_sessionSubscription?.cancel());
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  Future<void> _loadConferences({
    bool forceRefresh = false,
    bool more = false,
  }) async {
    final version = ++_requestVersion;
    unawaited(_cancellation?.cancel());
    final cancellation = _cancellation = RpcCancellation();
    final offset = more ? conferences.length : 0;
    final query = _searchController.text.trim();
    try {
      setState(() {
        isLoading = true;
        errorMessage = '';
      });
      final response = query.isEmpty
          ? await _repository.fetchConferences(
              forceRefresh: forceRefresh,
              offset: offset,
              cancellation: cancellation,
            )
          : await _repository.searchConferences(
              query: query,
              offset: offset,
              cancellation: cancellation,
            );
      if (!mounted || version != _requestVersion) return;

      final loadedConferences = response.conferences
          .map(
            (conf) => FidoConference(
              id: conf.id,
              name: conf.name,
              description: conf.description,
              unreadCount: conf.unreadCount,
              icon: Icons.forum,
              isBookmarked: conf.isBookmarked,
              canRead: conf.canRead,
              canPost: conf.canPost,
              kind: conf.kind,
              personalMailbox: conf.personalMailbox,
              storageFormat: conf.storageFormat,
              unsupportedFormat: conf.unsupportedFormat,
              statisticsKnown: conf.statisticsKnown,
            ),
          )
          .toList();
      setState(() {
        conferences = more
            ? [...conferences, ...loadedConferences]
            : loadedConferences;
        conferences.sort((a, b) {
          final group = a.kind.groupLabel.compareTo(b.kind.groupLabel);
          return group == 0
              ? a.name.compareTo(b.name)
              : a.kind.index.compareTo(b.kind.index);
        });
        _hasMore = response.hasMore;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        isLoading = false;
        if ((e is ApiException && e.isAccessDenied) ||
            conferences.any((c) => c.kind != AreaKind.echo)) {
          conferences = [];
        }
        errorMessage = query.isEmpty
            ? 'Ошибка загрузки конференций: $e'
            : 'Ошибка поиска: $e';
      });
    }
  }

  void _onSearchChanged(String value) {
    // Инвалидируем результат сразу, ещё до отправки отложенного поиска.
    ++_requestVersion;
    _debouncer.cancel();
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    if (value.trim().isEmpty) {
      _loadConferences();
    } else {
      _debouncer.run(() => _loadConferences());
    }
  }

  Future<void> _refreshConferences() async {
    _debouncer.cancel();
    await _loadConferences(forceRefresh: true);
  }

  // Метод для перехода к экрану сообщений
  Future<void> _navigateToMessageScreen(FidoConference conference) async {
    final epoch = _repository.epoch;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MessageScreen(
          conferenceId: conference.id,
          onAccessDenied: _repository.clearCache,
          canRead: conference.canRead,
          canPost: conference.canPost,
          kind: conference.kind,
          personalMailbox: conference.personalMailbox,
          conferenceName: conference.name,
          conferenceDescription: conference.description,
          repository: MessageRepository(_repository.transport),
        ),
      ),
    );
    if (mounted && epoch == _repository.epoch) await _refreshConferences();
  }

  Future<void> _toggleBookmark(FidoConference conference) async {
    if (!_pendingBookmarks.add(conference.id)) return;
    final epoch = _repository.epoch;
    setState(() => _bookmarkError = null);
    try {
      await _repository.toggleBookmark(conference.id, conference.isBookmarked);
      if (!mounted || epoch != _repository.epoch) return;
      await _refreshConferences();
    } catch (e) {
      if (!mounted || epoch != _repository.epoch) return;
      setState(() {
        _bookmarkError = e.toString();
        if (e is ApiException && e.isAccessDenied) {
          conferences.removeWhere((value) => value.id == conference.id);
        }
      });
    } finally {
      if (mounted && epoch == _repository.epoch) {
        setState(() => _pendingBookmarks.remove(conference.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'FFIDO',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshConferences,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedBottomIndex,
        children: [
          _buildMainConferenceList(),
          BookmarksScreen(
            repository: _account,
            active: _selectedBottomIndex == 1,
          ),
          HistoryScreen(
            repository: _account,
            active: _selectedBottomIndex == 2,
          ),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedBottomIndex,
        onTap: (index) {
          if (index == 0 && _selectedBottomIndex != 0) {
            unawaited(_refreshConferences());
          }
          setState(() {
            _selectedBottomIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Главная',
            tooltip: 'Главная',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_border),
            activeIcon: Icon(Icons.bookmark),
            tooltip: 'Закладки',
            label: 'Закладки',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            activeIcon: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    width: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              child: Icon(Icons.history),
            ),
            label: 'История',
            tooltip: 'История',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Профиль',
            tooltip: 'Профиль',
          ),
        ],
      ),
    );
  }

  /// Основной экран со списком конференций (вкладка "Главная")
  Widget _buildMainConferenceList() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Поиск конференций...',
              prefixIcon: Icon(
                Icons.search,
                color: colorScheme.onSurfaceVariant,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Очистить поиск',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            style: TextStyle(color: colorScheme.onSurface),
            onChanged: _onSearchChanged,
          ),
        ),
        if (_bookmarkError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_bookmarkError!),
          ),
        Expanded(child: _buildConferenceList()),
      ],
    );
  }

  Widget _buildConferenceList() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Загрузка конференций...'),
          ],
        ),
      );
    }

    if (errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshConferences,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (conferences.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.forum_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'Конференции не найдены'
                  : 'По запросу "${_searchController.text}" ничего не найдено',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshConferences,
      child: ListView.builder(
        itemCount: conferences.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == conferences.length) {
            return TextButton(
              onPressed: () => _loadConferences(more: true),
              child: const Text("Загрузить ещё"),
            );
          }
          final conference = conferences[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (index == 0 ||
                  conferences[index - 1].kind.groupLabel !=
                      conference.kind.groupLabel)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    conference.kind.groupLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ConferenceCard(
                conference: conference,
                onTap: () {
                  if (!_pendingBookmarks.contains(conference.id)) {
                    _navigateToMessageScreen(conference);
                  }
                },
                onBookmark: conference.canRead
                    ? () => _toggleBookmark(conference)
                    : null,
                bookmarkPending: _pendingBookmarks.contains(conference.id),
              ),
            ],
          );
        },
      ),
    );
  }
}
