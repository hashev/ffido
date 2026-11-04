import '../widgets/adaptive_layout.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_transport.dart';
import '../models/conference.dart';
import '../repositories/conference_repository.dart';

bool isReplyDestination(Conference area, String sourceId) =>
    area.id != sourceId &&
    area.canPost &&
    !area.unsupportedFormat &&
    area.storageFormat.toUpperCase() == 'JAM' &&
    (area.kind == AreaKind.netmail || area.kind == AreaKind.echo);

/// Loads every live page before deciding whether a personal destination is unique.
class ReplyDestination extends StatefulWidget {
  final ConferenceRepository repository;
  final String sourceId;
  final bool personalOnly;
  const ReplyDestination({
    super.key,
    required this.repository,
    required this.sourceId,
    this.personalOnly = false,
  });

  @override
  State<ReplyDestination> createState() => _ReplyDestinationState();
}

class _ReplyDestinationState extends State<ReplyDestination> {
  final search = TextEditingController();
  final cancellation = RpcCancellation();
  late final StreamSubscription<int> subscription;
  List<Conference> rows = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    subscription = widget.repository.sessionChanges.listen((_) {
      unawaited(cancellation.cancel());
      if (mounted) Navigator.pop(context);
    });
    load();
  }

  @override
  void dispose() {
    unawaited(cancellation.cancel());
    unawaited(subscription.cancel());
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final epoch = widget.repository.epoch;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final catalog = await widget.repository.fetchAllConferences(
        allowCacheFallback: false,
        cancellation: cancellation,
      );
      if (!mounted ||
          cancellation.isCancelled ||
          widget.repository.epoch != epoch) {
        return;
      }
      final available =
          catalog.conferences
              .where(
                (area) =>
                    isReplyDestination(area, widget.sourceId) &&
                    (!widget.personalOnly || area.kind == AreaKind.netmail),
              )
              .toList()
            ..sort((a, b) {
              final group = (a.kind == AreaKind.netmail ? 0 : 1).compareTo(
                b.kind == AreaKind.netmail ? 0 : 1,
              );
              if (group != 0) return group;
              final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
              return name != 0 ? name : a.id.compareTo(b.id);
            });
      if (widget.personalOnly && available.length == 1) {
        Navigator.pop(context, available.single);
        return;
      }
      setState(() {
        rows = available;
        loading = false;
      });
    } catch (e) {
      if (!mounted ||
          cancellation.isCancelled ||
          widget.repository.epoch != epoch) {
        return;
      }
      setState(() {
        loading = false;
        error = 'Не удалось загрузить назначения: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final visible = rows.where(
      (a) => '${a.name} ${a.description} ${a.id}'.toLowerCase().contains(query),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.personalOnly ? 'Личный ответ' : 'Область для ответа',
        ),
      ),
      body: AdaptiveContent(
        maxWidth: AdaptiveContent.listWidth,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Поиск области'),
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) ...[
              Text(error!),
              TextButton(onPressed: load, child: const Text('Повторить')),
            ],
            if (!loading && error == null && visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  rows.isNotEmpty
                      ? 'Ничего не найдено'
                      : widget.personalOnly
                      ? 'Нет доступного для отправки Netmail. Настройте личный ящик на сервере.'
                      : 'Нет доступных областей для ответа',
                ),
              ),
            ...[
              if (!loading && error == null)
                for (final area in visible)
                  ListTile(
                    title: Text(area.name),
                    subtitle: Text(
                      '${area.kind == AreaKind.netmail ? "Netmail · лично" : "Эха · всем участникам"}\n${area.id}',
                    ),
                    onTap: () => Navigator.pop(context, area),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
