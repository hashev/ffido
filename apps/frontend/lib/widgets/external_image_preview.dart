import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../files/image_actions.dart';
import '../media/external_image.dart';
import '../media/message_images.dart';

class ExternalImagePreview extends StatelessWidget {
  final MessageImages owner;
  final ImageEntry entry;
  final ImageActions? actions;
  const ExternalImagePreview({
    super.key,
    required this.owner,
    required this.entry,
    this.actions,
  });
  @override
  Widget build(BuildContext context) => Card(
    semanticContainer: false,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.loading) const Text('Загрузка изображения…'),
          if (entry.thumbnail != null && entry.source != null)
            Semantics(
              label: 'Открыть изображение на весь экран',
              button: true,
              child: InkWell(
                onTap: () {
                  owner.touch(entry);
                  final source = entry.source!;
                  unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ExternalImageViewer(
                          owner: owner,
                          source: source,
                          actions: actions ?? PlatformImageActions(),
                        ),
                      ),
                    ),
                  );
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                    maxWidth: 480,
                    maxHeight: 300,
                  ),
                  child: RawImage(image: entry.thumbnail, fit: BoxFit.contain),
                ),
              ),
            ),
          if (entry.error != null) Text(entry.error!),
          if (!entry.loading && entry.source == null)
            TextButton(
              onPressed: owner.active ? () => owner.retry(entry) : null,
              child: const Text('Повторить загрузку изображения'),
            ),
        ],
      ),
    ),
  );
}

class ExternalImageViewer extends StatefulWidget {
  final MessageImages owner;
  final ExternalImage source;
  final ImageActions actions;
  const ExternalImageViewer({
    super.key,
    required this.owner,
    required this.source,
    required this.actions,
  });
  @override
  State<ExternalImageViewer> createState() => _ExternalImageViewerState();
}

class _ExternalImageViewerState extends State<ExternalImageViewer> {
  ui.Image? image;
  bool busy = false;
  String? note;
  @override
  void initState() {
    super.initState();
    widget.owner.addListener(changed);
    unawaited(decode());
  }

  Future<void> decode() async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(widget.source.bytes);
      final frame = await codec.getNextFrame();
      if (!mounted || !widget.owner.active) {
        frame.image.dispose();
        return;
      }
      setState(() => image = frame.image);
    } catch (_) {
      if (mounted && widget.owner.active) {
        setState(() => note = 'Не удалось показать изображение');
      }
    } finally {
      codec?.dispose();
    }
  }

  void changed() {
    if (!widget.owner.active && mounted) {
      unawaited(widget.actions.cancelPending().catchError((Object _) {}));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final route = ModalRoute.of(context);
          if (route != null && route.isActive) {
            Navigator.of(context).removeRoute(route);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    widget.owner.removeListener(changed);
    image?.dispose();
    super.dispose();
  }

  Future<void> act({required bool share}) async {
    if (busy || !widget.owner.active) return;
    setState(() {
      busy = true;
      note = null;
    });
    final source = widget.source;
    try {
      if (share) {
        final box = context.findRenderObject() as RenderBox?;
        final rect = box == null
            ? const Rect.fromLTWH(0, 0, 1, 1)
            : box.localToGlobal(Offset.zero) & box.size;
        final result = await widget.actions.share(
          source.name,
          source.mime,
          source.bytes,
          rect,
          isActive: () => mounted && widget.owner.active,
        );
        if (!mounted || !widget.owner.active) return;
        setState(
          () => note = switch (result) {
            ImageActionResult.handedOff => 'Файл передан системному диалогу',
            ImageActionResult.cancelled => null,
            ImageActionResult.unsupported =>
              'Отправка недоступна. Можно сохранить изображение.',
          },
        );
      } else {
        final saved = await widget.actions.save(source.name, source.bytes);
        if (mounted && widget.owner.active && saved) {
          setState(() => note = 'Файл передан для сохранения');
        }
      }
    } catch (_) {
      if (mounted && widget.owner.active) {
        setState(
          () => note =
              'Действие не удалось. Можно повторить или сохранить изображение.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
    },
    child: Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            Navigator.of(context).pop();
            return null;
          },
        ),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Закрыть изображение',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('Изображение'),
            actions: [
              if (widget.actions.canShare)
                IconButton(
                  tooltip: 'Поделиться изображением',
                  onPressed: busy || !widget.owner.active
                      ? null
                      : () => act(share: true),
                  icon: const Icon(Icons.share),
                ),
              IconButton(
                tooltip: 'Сохранить изображение',
                onPressed: busy || !widget.owner.active
                    ? null
                    : () => act(share: false),
                icon: const Icon(Icons.save_alt),
              ),
            ],
          ),
          body: Column(
            children: [
              if (note != null) Text(note!),
              Expanded(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 8,
                  child: Center(
                    child: RawImage(image: image, fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
