import 'dart:convert';

import 'package:flutter/material.dart';

class MessageSearchDialog extends StatefulWidget {
  final String query;
  final bool headersOnly;
  const MessageSearchDialog({
    super.key,
    required this.query,
    required this.headersOnly,
  });
  @override
  State<MessageSearchDialog> createState() => _MessageSearchDialogState();
}

class _MessageSearchDialogState extends State<MessageSearchDialog> {
  late final controller = TextEditingController(text: widget.query);
  late bool headersOnly = widget.headersOnly;
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final query = controller.text.trim();
    if (query.isEmpty || utf8.encode(query).length > 256) {
      setState(() => error = 'Введите запрос до 256 байт UTF-8');
      return;
    }
    Navigator.pop(context, (query: query, headersOnly: headersOnly));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Поиск по письмам'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'По всей текущей области, с текущего письма до конца. Повтор — со следующего найденного.',
          ),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Найти', errorText: error),
            onSubmitted: (_) => submit(),
          ),
          DropdownButtonFormField<bool>(
            isExpanded: true,
            initialValue: headersOnly,
            items: const [
              DropdownMenuItem(
                value: false,
                child: Text(
                  'Заголовки и текст',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: true,
                child: Text('Заголовки', overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (v) => setState(() => headersOnly = v ?? false),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(onPressed: submit, child: const Text('Найти далее')),
    ],
  );
}
