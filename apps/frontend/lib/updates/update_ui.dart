import 'update_host_stub.dart'
    if (dart.library.io) 'update_host_io.dart'
    as host;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'update_controller.dart';

class UpdateShell extends StatefulWidget {
  const UpdateShell({super.key, required this.child, this.controller});
  final Widget child;
  final UpdateController? controller;
  @override
  State<UpdateShell> createState() => _UpdateShellState();
}

class _UpdateShellState extends State<UpdateShell> with WidgetsBindingObserver {
  UpdateController get controller => widget.controller ?? appUpdates;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(host.confirmDesktopStartup());
        unawaited(controller.start());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(controller.check());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      children: [
        if (controller.showNotice)
          Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.message.isNotEmpty
                            ? controller.message
                            : 'Доступно обновление ${controller.available?.manifest.identity.version ?? ''}',
                      ),
                    ),
                    if (controller.phase == UpdatePhase.downloading)
                      TextButton(
                        onPressed: controller.cancel,
                        child: const Text('Отменить'),
                      ),
                    if (controller.busy)
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          value: controller.progress > 0
                              ? controller.progress
                              : null,
                        ),
                      )
                    else ...[
                      TextButton(
                        onPressed: controller.available != null
                            ? controller.install
                            : () => controller.check(manual: true),
                        child: Text(
                          controller.available != null
                              ? 'Обновить'
                              : 'Проверить',
                        ),
                      ),
                      TextButton(
                        onPressed: controller.later,
                        child: const Text('Позже'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    ),
  );
}

class UpdateScreen extends StatelessWidget {
  const UpdateScreen({super.key, this.controller});
  final UpdateController? controller;
  @override
  Widget build(BuildContext context) {
    final updates = controller ?? appUpdates;
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Обновления FFIDO')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Установлена: ${updates.service?.installed.tag ?? 'определяется…'}',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: updates.channel,
              decoration: const InputDecoration(labelText: 'Канал обновлений'),
              items: const [
                DropdownMenuItem(
                  value: 'stable',
                  child: Text('Стабильные версии'),
                ),
                DropdownMenuItem(
                  value: 'dev',
                  child: Text('Предварительные версии'),
                ),
              ],
              onChanged: updates.busy
                  ? null
                  : (value) {
                      if (value != null) unawaited(updates.setChannel(value));
                    },
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: updates.busy
                  ? null
                  : () => updates.check(manual: true),
              child: const Text('Проверить обновления'),
            ),
            if (updates.available != null) ...[
              Text('Доступна: ${updates.available!.manifest.identity.tag}'),
              FilledButton(
                onPressed: updates.busy ? null : updates.install,
                child: const Text('Обновить'),
              ),
              if (updates.available!.notes.isNotEmpty)
                SelectableText(updates.available!.notes),
            ],
            if (updates.busy)
              LinearProgressIndicator(
                value: updates.progress > 0 ? updates.progress : null,
              ),
            if (updates.message.isNotEmpty)
              Text(updates.message, key: const Key('update-message')),
            const SizedBox(height: 16),
            const Text(
              'На macOS после обновления может потребоваться разрешить доступ к Keychain или войти снова.',
            ),
          ],
        ),
      ),
    );
  }
}

class UpdateButton extends StatelessWidget {
  const UpdateButton({super.key});
  @override
  Widget build(BuildContext context) =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.iOS
      ? const SizedBox.shrink()
      : IconButton(
          tooltip: 'Обновления приложения',
          icon: const Icon(Icons.system_update_alt),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const UpdateScreen())),
        );
}
