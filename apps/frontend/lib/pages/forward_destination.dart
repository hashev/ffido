import 'dart:async';
import 'package:flutter/material.dart';
import '../api/api_exceptions.dart';
import '../models/conference.dart';
import '../repositories/conference_repository.dart';

class ForwardDestination extends StatefulWidget {
  final ConferenceRepository repository;
  const ForwardDestination({super.key, required this.repository});
  @override
  State<ForwardDestination> createState() => _ForwardDestinationState();
}

class _ForwardDestinationState extends State<ForwardDestination> {
  final search = TextEditingController();
  List<Conference> rows = [];
  int version = 0, offset = 0;
  bool loading = false, hasMore = false;
  String? error;
  Timer? debounce;
  late final StreamSubscription<int> subscription;
  @override
  void initState() {
    super.initState();
    subscription = widget.repository.sessionChanges.listen((_) {
      ++version;
      if (mounted) Navigator.pop(context);
    });
    load();
  }

  @override
  void dispose() {
    ++version;
    debounce?.cancel();
    search.dispose();
    unawaited(subscription.cancel());
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (more && loading) return;
    final current = ++version;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.repository.searchConferences(
        query: search.text,
        offset: more ? offset : 0,
      );
      if (!mounted || current != version) return;
      setState(() {
        offset = (more ? offset : 0) + result.conferences.length;
        final known = more ? rows.map((c) => c.id).toSet() : <String>{};
        final added = result.conferences.where(
          (c) => c.kind == AreaKind.echo && c.canPost && known.add(c.id),
        );
        rows = more ? [...rows, ...added] : added.toList();
        hasMore = result.hasMore && result.conferences.isNotEmpty;
        loading = false;
      });
    } catch (e) {
      if (!mounted || current != version) return;
      setState(() {
        loading = false;
        error = e is CancelledException ? null : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Выберите эху для пересылки')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: search,
            decoration: const InputDecoration(labelText: 'Поиск эхи'),
            onChanged: (_) {
              ++version;
              debounce?.cancel();
              setState(() {
                rows = [];
                hasMore = false;
                loading = true;
              });
              debounce = Timer(const Duration(milliseconds: 300), () => load());
            },
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (error != null)
          TextButton(onPressed: () => load(), child: const Text('Повторить')),
        if (!loading && error == null && rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Нет доступных для публикации эх'),
          ),
        Expanded(
          child: ListView(
            children: [
              for (final row in rows)
                ListTile(
                  title: Text(row.name),
                  subtitle: Text(row.id),
                  onTap: loading ? null : () => Navigator.pop(context, row),
                ),
              if (hasMore)
                TextButton(
                  onPressed: loading ? null : () => load(more: true),
                  child: const Text('Загрузить ещё'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
