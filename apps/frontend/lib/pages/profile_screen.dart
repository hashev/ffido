import '../utils/refresh_on_resume.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_transport.dart';
import '../models/api_response.dart';
import '../repositories/account_repository.dart';
import '../main.dart' show accountRepository;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.repository});
  final AccountRepository? repository;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with RefreshOnResume<ProfileScreen> {
  @override
  Future<void> refreshOnResume() => _load();

  UserProfile? _profile;
  bool _loading = true;
  String _error = '';
  int _version = 0;
  RpcCancellation _request = RpcCancellation();
  late final StreamSubscription<int> _sessions;
  AccountRepository get _repository => widget.repository ?? accountRepository;
  @override
  void initState() {
    super.initState();
    _sessions = _repository.sessionChanges.listen((_) {
      _profile = null;
      _load();
    });
    _load();
  }

  @override
  void dispose() {
    unawaited(_request.cancel());
    unawaited(_sessions.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_version;
    unawaited(_request.cancel());
    _request = RpcCancellation();
    setState(() {
      _loading = true;
      _profile = null;
      _error = '';
    });
    try {
      final profile = await _repository.getProfile(cancellation: _request);
      if (!mounted || version != _version) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _version) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Профиль'),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Обновить',
        ),
      ],
    ),
    body: _loading
        ? const Center(child: Text('Загрузка профиля...'))
        : _error.isNotEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error),
                TextButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          )
        : _profile == null
        ? const Center(child: Text('Профиль не найден'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _profile!.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(_profile!.address),
              if (_profile!.email != null) Text(_profile!.email!),
              if (_profile!.registeredAt != null)
                Text(
                  'Регистрация: ${_profile!.registeredAt!.toIso8601String()}',
                ),
            ],
          ),
  );
}
