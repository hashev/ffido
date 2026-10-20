import 'package:flutter/material.dart';

import '../repositories/account_repository.dart';
import 'personal_conferences.dart';

class BookmarksScreen extends StatelessWidget {
  final AccountRepository? repository;
  final bool active;
  const BookmarksScreen({super.key, this.repository, this.active = true});
  @override
  Widget build(BuildContext context) => PersonalConferences(
    history: false,
    repository: repository,
    active: active,
  );
}
