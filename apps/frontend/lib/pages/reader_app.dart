import 'package:flutter/material.dart';

import '../main.dart';
import '../repositories/account_repository.dart';
import '../repositories/conference_repository.dart';
import '../shortcuts/command_scope.dart';
import '../updates/update_ui.dart';
import 'personal_conferences.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  final ConferenceRepository? repository;
  const MainScreen({super.key, this.repository});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selected = 0;
  ConferenceRepository get conferences =>
      widget.repository ?? conferenceRepository;
  late final AccountRepository account = AccountRepository(
    conferences.transport,
  );
  final favoriteKey = GlobalKey<PersonalConferencesState>();
  final catalogKey = GlobalKey<PersonalConferencesState>();
  final historyKey = GlobalKey<PersonalConferencesState>();
  @override
  Widget build(BuildContext context) => CommandScope(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('FFIDO'),
        actions: [
          const CommandHelpButton(),
          const UpdateButton(),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: IndexedStack(
        index: selected,
        children: [
          PersonalConferences(
            key: favoriteKey,
            history: false,
            repository: account,
            conferences: conferences,
            active: selected == 0,
            onChooseAreas: () => setState(() => selected = 1),
          ),
          PersonalConferences(
            key: catalogKey,
            history: false,
            catalog: true,
            repository: account,
            conferences: conferences,
            active: selected == 1,
          ),
          PersonalConferences(
            key: historyKey,
            history: true,
            repository: account,
            conferences: conferences,
            active: selected == 2,
          ),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selected,
        type: BottomNavigationBarType.fixed,
        onTap: (value) => setState(() => selected = value),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_border),
            activeIcon: Icon(Icons.bookmark),
            label: 'Избранное',
            tooltip: 'Закладки',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.forum_outlined),
            activeIcon: Icon(Icons.forum),
            label: 'Области',
            tooltip: 'Все области',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'История',
            tooltip: 'История',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Профиль',
            tooltip: 'Профиль',
          ),
        ],
      ),
    ),
  );
}
