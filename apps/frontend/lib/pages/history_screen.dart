import 'package:flutter/material.dart';
import '../repositories/account_repository.dart';
import 'personal_conferences.dart';

class HistoryScreen extends StatelessWidget {
  final AccountRepository? repository;
  final bool active;
  const HistoryScreen({super.key, this.repository, this.active = true});
  @override
  Widget build(BuildContext context) => PersonalConferences(
    history: true,
    repository: repository,
    active: active,
  );
}
