import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conference.dart';
import '../repositories/conference_repository.dart';

String crosspostHeader(String primaryName, List<Conference> additional) {
  final sorted = [...additional]
    ..sort((a, b) {
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return name != 0 ? name : a.id.compareTo(b.id);
    });
  return '* Originally in $primaryName\n${sorted.map((a) => '* Crossposted in ${a.name}').join('\n')}\n\n';
}

class CrosspostDestinations extends StatefulWidget {
  final ConferenceRepository repository;
  final String primaryId, primaryName;
  final List<Conference> selected;
  const CrosspostDestinations({
    super.key,
    required this.repository,
    required this.primaryId,
    required this.primaryName,
    required this.selected,
  });
  @override
  State<CrosspostDestinations> createState() => _CrosspostDestinationsState();
}

class _CrosspostDestinationsState extends State<CrosspostDestinations> {
  final search = TextEditingController();
  late final Map<String, Conference> selected;
  List<Conference> rows = [];
  int version = 0, offset = 0;
  bool loading = false, hasMore = false;
  String? error;
  Timer? debounce;
  late final StreamSubscription<int> subscription;
  @override
  void initState() {
    super.initState();
    selected = {
      for (final area in widget.selected)
        if (area.id != widget.primaryId) area.id: area,
    };
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
        final known = more ? rows.map((a) => a.id).toSet() : <String>{};
        final added = result.conferences.where(
          (a) =>
              a.id != widget.primaryId &&
              a.kind == AreaKind.echo &&
              a.canPost &&
              !a.unsupportedFormat &&
              known.add(a.id),
        );
        rows = more ? [...rows, ...added] : added.toList();
        hasMore = result.hasMore && result.conferences.isNotEmpty;
        loading = false;
      });
    } catch (_) {
      if (!mounted || current != version) return;
      setState(() {
        loading = false;
        error = 'Не удалось загрузить эхи';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Кросспостинг'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, selected.values.toList()),
          child: const Text('Готово'),
        ),
      ],
    ),
    body: Column(
      children: [
        ListTile(
          title: Text('Исходная эха: ${widget.primaryName}'),
          subtitle: Text('Выбрано дополнительных эх: ${selected.length}/20'),
          leading: const Icon(Icons.check_box),
        ),
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
                loading = true;
                hasMore = false;
              });
              debounce = Timer(const Duration(milliseconds: 300), () => load());
            },
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          TextButton(
            onPressed: () => load(more: offset > 0 && rows.isNotEmpty),
            child: Text('$error. Повторить'),
          ),
        if (!loading && error == null && rows.isEmpty)
          const Text('Нет доступных для публикации эх'),
        Expanded(
          child: ListView(
            children: [
              for (final area in rows)
                CheckboxListTile(
                  title: Text(area.name),
                  subtitle: Text(area.id),
                  value: selected.containsKey(area.id),
                  onChanged:
                      !selected.containsKey(area.id) && selected.length >= 20
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            selected[area.id] = area;
                          } else {
                            selected.remove(area.id);
                          }
                        }),
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
