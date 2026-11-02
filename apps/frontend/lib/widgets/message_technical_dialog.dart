import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_exceptions.dart';
import '../api/api_transport.dart';
import '../models/message_technical_data.dart';
import '../repositories/message_repository.dart';
import '../utils/message_technical_report.dart';

class MessageTechnicalDialog extends StatefulWidget {
  final MessageRepository repository;
  final String conferenceId, messageId;
  const MessageTechnicalDialog({
    super.key,
    required this.repository,
    required this.conferenceId,
    required this.messageId,
  });
  @override
  State<MessageTechnicalDialog> createState() => _MessageTechnicalDialogState();
}

class _MessageTechnicalDialogState extends State<MessageTechnicalDialog> {
  late final int epoch;
  late final StreamSubscription<int> subscription;
  RpcCancellation? cancellation;
  bool loading = true;
  String? error;
  MessageTechnicalData? data;
  List<TechnicalRow> rows = [];
  int version = 0;
  @override
  void initState() {
    super.initState();
    epoch = widget.repository.epoch;
    subscription = widget.repository.sessionChanges.listen((_) {
      ++version;
      unawaited(cancellation?.cancel());
      if (!mounted) return;
      setState(() {
        data = null;
        rows = [];
      });
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
    load();
  }

  Future<void> load() async {
    final current = ++version;
    unawaited(cancellation?.cancel());
    final token = cancellation = RpcCancellation();
    setState(() {
      loading = true;
      error = null;
      data = null;
      rows = [];
    });
    try {
      final result = await widget.repository.getTechnicalData(
        widget.conferenceId,
        widget.messageId,
        cancellation: token,
      );
      if (!mounted || current != version || widget.repository.epoch != epoch) {
        return;
      }
      setState(() {
        loading = false;
        data = result;
        rows = technicalRows(result);
      });
    } catch (e) {
      if (!mounted || current != version || widget.repository.epoch != epoch) {
        return;
      }
      setState(() {
        loading = false;
        error = e is ApiException && e.statusCode == 12
            ? 'Для просмотра технических данных обновите сервер'
            : e is ApiException && e.isAccessDenied
            ? 'Нет доступа к техническим данным письма'
            : 'Не удалось получить технические данные: $e';
      });
    }
  }

  Future<void> copy() async {
    final snapshot = data;
    if (snapshot == null || loading || widget.repository.epoch != epoch) return;
    await Clipboard.setData(
      ClipboardData(text: messageTechnicalReport(snapshot)),
    );
    if (mounted && widget.repository.epoch == epoch) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Технические данные скопированы')),
      );
    }
  }

  @override
  void dispose() {
    ++version;
    unawaited(cancellation?.cancel());
    unawaited(subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Технические данные'),
    content: SizedBox(
      width: 640,
      height: min(600, MediaQuery.sizeOf(context).height * .6),
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  TextButton(onPressed: load, child: const Text('Повторить')),
                ],
              ),
            )
          : ListView.builder(
              itemCount: rows.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(technicalExplanation),
                  );
                }
                final row = rows[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.label,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      SelectableText(row.value),
                    ],
                  ),
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: data != null && !loading ? copy : null,
        child: const Text('Скопировать отчёт'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Закрыть'),
      ),
    ],
  );
}
