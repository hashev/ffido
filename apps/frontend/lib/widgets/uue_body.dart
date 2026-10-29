import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api/api_transport.dart';
import '../files/uue_files.dart';
import '../files/image_actions.dart';
import '../models/message.dart';
import '../models/uue.dart';
import '../repositories/uue_repository.dart';
import '../utils/ftn_text.dart';
import '../utils/uue_image.dart';
import '../media/message_images.dart';
import '../utils/message_links.dart';
import 'message_link_text.dart';
import 'external_image_preview.dart';

class UueBody extends StatefulWidget {
  final UueRepository repository;
  final String conference;
  final Message message;
  final MessageImages Function(String)? createImages;
  final ImageActions? imageActions;
  const UueBody({
    super.key,
    required this.repository,
    required this.conference,
    required this.message,
    this.createImages,
    this.imageActions,
  });
  @override
  State<UueBody> createState() => _UueBodyState();
}

class _UueBodyState extends State<UueBody> {
  final cancellation = RpcCancellation();
  List<UuePart> parts = [];
  String? error;
  bool raw = false;
  late final MessageImages images;
  late final int initialEpoch;
  late final StreamSubscription<int> sessionSubscription;
  @override
  void initState() {
    super.initState();
    initialEpoch = widget.repository.epoch;
    images =
        (widget.createImages?.call(widget.message.body) ??
              MessageImages(widget.message.body))
          ..addListener(imagesChanged);
    images.more();
    sessionSubscription = widget.repository.sessionChanges.listen((_) {
      images.invalidate();
      if (mounted) setState(() => parts = []);
    });
    unawaited(load());
  }

  void imagesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    images.removeListener(imagesChanged);
    images.dispose();
    unawaited(cancellation.cancel());
    unawaited(sessionSubscription.cancel());
    super.dispose();
  }

  Future<void> load() async {
    final body = widget.message.body;
    final lines = body.split('\n');
    if (!lines.any(uueBeginLine.hasMatch) &&
        !RegExp(r'\[\d+/\d+\]$').hasMatch(widget.message.subject) &&
        (lines.isEmpty || !uueDataLine(lines.first))) {
      return;
    }
    try {
      if (await widget.repository.capabilities() == null) return;
      final result = await widget.repository.messageParts(
        widget.conference,
        widget.message.id,
        cancellation: cancellation,
      );
      if (mounted && !cancellation.isCancelled) setState(() => parts = result);
    } catch (_) {
      if (mounted && !cancellation.isCancelled) {
        setState(() => error = 'Вложения недоступны. Исходный текст сохранён.');
      }
    }
  }

  final shownImages = <Uri>{};
  Widget text(String value) {
    final available = {
      for (final entry in images.entries.take(images.visible))
        if (entry.showPreview) entry.uri: entry,
    };
    final slots = <int, List<ImageEntry>>{};
    for (final link in messageLinks(value)) {
      final uri = link.uri.removeFragment();
      final entry = available[uri];
      if (entry == null || !shownImages.add(uri)) continue;
      // Keep source line boundaries, independent of wrapping on the screen.
      final newline = value.indexOf('\n', link.end);
      final end = newline < 0 ? value.length : newline + 1;
      (slots[end] ??= []).add(entry);
    }
    final children = <Widget>[];
    var start = 0;
    void addText(int end) {
      if (end <= start) return;
      children.add(
        MessageLinkText(
          value.substring(start, end),
          actions: widget.imageActions,
          sharedSelection: images.entries.isNotEmpty,
        ),
      );
      start = end;
    }

    for (final slot in slots.entries) {
      addText(slot.key);
      for (final entry in slot.value) {
        children.add(
          SelectionContainer.disabled(
            child: ExternalImagePreview(
              key: ValueKey(entry.uri),
              owner: images,
              entry: entry,
              actions: widget.imageActions,
            ),
          ),
        );
      }
    }
    addText(value.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget moreImages() => images.visible < images.entries.length
      ? SelectionContainer.disabled(
          child: TextButton(
            onPressed: images.more,
            child: const Text('Загрузить ещё изображения'),
          ),
        )
      : const SizedBox.shrink();
  @override
  Widget build(BuildContext context) => SelectionArea(child: body(context));

  Widget body(BuildContext context) {
    shownImages.clear();
    if (initialEpoch != widget.repository.epoch) return const SizedBox.shrink();
    if (raw || parts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) Text(error!),
          if (parts.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => raw = false),
              child: const Text('Показать вложения'),
            ),
          text(widget.message.body),
          moreImages(),
        ],
      );
    }
    final bytes = utf8.encode(widget.message.body);
    final children = <Widget>[];
    var offset = 0;
    final ordered = parts.toList()..sort((a, b) => a.begin.compareTo(b.begin));
    for (final part in ordered) {
      if (part.begin < offset ||
          part.end < part.begin ||
          part.end > bytes.length) {
        return text(widget.message.body);
      }
      if (part.begin > offset) {
        children.add(text(utf8.decode(bytes.sublist(offset, part.begin))));
      }
      children.add(
        UueAttachmentCard(
          key: ValueKey(part.source.key),
          repository: widget.repository,
          part: part,
        ),
      );
      offset = part.end;
    }
    if (offset < bytes.length) {
      children.add(text(utf8.decode(bytes.sublist(offset))));
    }
    children.add(moreImages());
    children.add(
      TextButton(
        onPressed: () => setState(() => raw = true),
        child: const Text('Показать исходный UUE'),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class UueAttachmentCard extends StatefulWidget {
  final UueRepository repository;
  final UuePart part;
  final UueFiles? files;
  const UueAttachmentCard({
    super.key,
    required this.repository,
    required this.part,
    this.files,
  });
  @override
  State<UueAttachmentCard> createState() => _UueAttachmentCardState();
}

class _UueAttachmentCardState extends State<UueAttachmentCard> {
  final cancellation = RpcCancellation();
  UueAttachment? attachment;
  ui.Image? image;
  bool busy = false, saving = false;
  String? error, previewNote;
  int searched = 0;
  bool choosing = false;
  bool selectedMultipart = false;
  late final int epoch;
  late final StreamSubscription<int> subscription;
  @override
  void initState() {
    super.initState();
    epoch = widget.repository.epoch;
    subscription = widget.repository.sessionChanges.listen((_) {
      unawaited(cancellation.cancel());
      if (choosing && mounted) Navigator.of(context).pop();
      image?.dispose();
      image = null;
      if (mounted) {
        setState(() {
          attachment = null;
          error = 'Сессия изменилась';
        });
      }
    });
    unawaited(collect(automatic: true));
  }

  @override
  void dispose() {
    image?.dispose();
    unawaited(cancellation.cancel());
    unawaited(subscription.cancel());
    super.dispose();
  }

  bool get active =>
      mounted && epoch == widget.repository.epoch && !cancellation.isCancelled;
  Future<List<UuePart>?> confirm(List<UuePart> parts) async {
    final order = parts.toList();
    final selected = parts.map((p) => p.source.key).toSet();
    choosing = true;
    try {
      return await showDialog<List<UuePart>>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Подтвердите части UUE'),
            content: SizedBox(
              width: 600,
              height: 380,
              child: Column(
                children: [
                  const Text(
                    'Без идентификатора и контрольной суммы совпадения темы и номеров недостаточно. Проверьте состав и порядок.',
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: order.length,
                      itemBuilder: (_, index) {
                        final part = order[index];
                        return Row(
                          children: [
                            Checkbox(
                              value: selected.contains(part.source.key),
                              onChanged: (v) => update(() {
                                if (v == true) {
                                  selected.add(part.source.key);
                                } else {
                                  selected.remove(part.source.key);
                                }
                              }),
                            ),
                            Expanded(
                              child: Text(
                                '${part.part}/${part.total} · ${part.subject}\n${part.date}\n${part.source.message}',
                              ),
                            ),
                            IconButton(
                              tooltip: 'Выше',
                              onPressed: index == 0
                                  ? null
                                  : () => update(() {
                                      final p = order.removeAt(index);
                                      order.insert(index - 1, p);
                                    }),
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: 'Ниже',
                              onPressed: index + 1 == order.length
                                  ? null
                                  : () => update(() {
                                      final p = order.removeAt(index);
                                      order.insert(index + 1, p);
                                    }),
                              icon: const Icon(Icons.arrow_downward),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                        dialog,
                        order
                            .where((p) => selected.contains(p.source.key))
                            .toList(),
                      ),
                child: const Text('Подтвердить и собрать'),
              ),
            ],
          ),
        ),
      );
    } finally {
      choosing = false;
    }
  }

  Future<void> collect({bool automatic = false, bool manual = false}) async {
    if (busy || !active) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      List<UuePart> sources = [widget.part];
      if (widget.part.total > 1 || !automatic || manual) {
        sources = await widget.repository.findParts(
          widget.part,
          cancellation: cancellation,
          progress: (count) {
            if (active) setState(() => searched = count);
          },
        );
      }
      if (!active) return;
      final legacy =
          !widget.part.verifiedFormat &&
          (sources.length > 1 || widget.part.total > 1);
      final choose =
          !widget.part.verifiedFormat &&
          (manual || (legacy && widget.part.total <= 1));
      if (choose) {
        final selection = await confirm(sources);
        if (!active || selection == null) return;
        sources = selection;
      }
      setState(() {
        attachment = null;
        selectedMultipart = sources.length > 1;
        image?.dispose();
        image = null;
      });
      final result = await widget.repository.assemble(
        sources,
        confirmed: choose,
        cancellation: cancellation,
      );
      if (!active) return;
      image?.dispose();
      image = null;
      setState(() {
        attachment = result;
        previewNote = null;
      });
      if (result.state == UueFileState.ready) await preview(result);
    } catch (_) {
      if (active) {
        setState(() {
          error = 'Не удалось собрать вложение. Можно повторить поиск.';
          image?.dispose();
          image = null;
        });
      }
    } finally {
      if (active) setState(() => busy = false);
    }
  }

  Future<void> preview(UueAttachment file) async {
    final limits = await widget.repository.capabilities();
    if (!active || limits == null) return;
    final bytes = await widget.repository.download(
      file,
      cancellation: cancellation,
    );
    if (!active) return;
    final info = uueImageInfo(bytes);
    if (info == null) return;
    if (!info.allowed(limits.previewPixels, limits.previewDimension)) {
      setState(() => previewNote = 'Изображение слишком большое для preview');
      return;
    }
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: min(1000, info.width),
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      if (!active) {
        frame.image.dispose();
        return;
      }
      setState(() => image = frame.image);
    } catch (_) {
      if (active) {
        setState(
          () => previewNote = 'Preview недоступен; файл можно сохранить',
        );
      }
    } finally {
      codec?.dispose();
    }
  }

  Future<void> save() async {
    final file = attachment;
    if (file == null || saving || !active) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final bytes = await widget.repository.download(
        file,
        cancellation: cancellation,
      );
      if (!active) return;
      final saved = await (widget.files ?? uueFiles).save(
        safeUueName(file.name),
        bytes,
      );
      if (!mounted) return;
      if (active && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл передан для сохранения')),
        );
      }
    } catch (_) {
      if (active) {
        setState(() {
          error = 'Не удалось сохранить файл';
          image?.dispose();
          image = null;
        });
      }
    } finally {
      if (active) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (epoch != widget.repository.epoch) return const SizedBox.shrink();
    final file = attachment;
    final status = switch (file?.state) {
      UueFileState.ready =>
        '${file!.size} байт · ${file.verified ? "SHA-256 проверен" : "Контрольная сумма отсутствует"}',
      UueFileState.incomplete =>
        'Не хватает частей: ${file!.missing.join(", ")}',
      UueFileState.conflict => 'Конфликт частей',
      UueFileState.corrupt => 'Повреждённое вложение',
      _ => 'Часть ${widget.part.part}/${widget.part.total}',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_file),
                const SizedBox(width: 8),
                Expanded(child: Text(file?.name ?? widget.part.filename)),
              ],
            ),
            Text(status),
            if (!widget.part.verifiedFormat &&
                (widget.part.total > 1 || selectedMultipart))
              const Text(
                'Контрольной суммы нет; возможно смешивание частей разных передач',
              ),
            if (busy)
              Text(
                searched == 0
                    ? 'Сборка...'
                    : 'Поиск: проверено около $searched писем',
              ),
            if (image != null)
              Semantics(
                container: true,
                label: 'Предпросмотр изображения',
                image: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: RawImage(image: image, fit: BoxFit.contain),
                ),
              ),
            if (previewNote != null) Text(previewNote!),
            if (error != null) Text(error!),
            Wrap(
              spacing: 8,
              children: [
                if (file?.state != UueFileState.ready)
                  TextButton.icon(
                    onPressed: busy || !active ? null : collect,
                    icon: const Icon(Icons.search),
                    label: const Text('Найти части'),
                  ),
                if (!widget.part.verifiedFormat)
                  TextButton.icon(
                    onPressed: busy || saving || !active
                        ? null
                        : () => collect(manual: true),
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('Выбрать части'),
                  ),
                TextButton.icon(
                  onPressed:
                      file?.state == UueFileState.ready &&
                          !saving &&
                          !busy &&
                          active
                      ? save
                      : null,
                  icon: const Icon(Icons.save_alt),
                  label: Text(saving ? 'Сохранение...' : 'Сохранить файл'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
