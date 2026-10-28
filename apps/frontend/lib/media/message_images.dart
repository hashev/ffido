import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../utils/message_links.dart';
import 'external_image.dart';

class ImageEntry {
  final Uri uri;
  ExternalImage? source;
  ui.Image? thumbnail;
  String? error;
  bool loading = false, requested = false;
  ImageEntry(this.uri);
  void release() {
    source = null;
    thumbnail?.dispose();
    thumbnail = null;
  }
}

/// One owner per message/epoch. Neither the queue nor cache survives its reader.
class MessageImages extends ChangeNotifier {
  final List<ImageEntry> entries;
  final ExternalImageLoad Function() createLoad;
  final int cacheBudget;
  final _running = <ImageEntry, ExternalImageLoad>{};
  final _queue = Queue<ImageEntry>();
  final _lru = <ImageEntry>{};
  bool active = true;
  int visible = 0;
  MessageImages(
    String body, {
    ExternalImageLoad Function()? createLoad,
    this.cacheBudget = 32 * 1024 * 1024,
  }) : entries = {
         for (final link in messageLinks(body)) link.uri.removeFragment(),
       }.map(ImageEntry.new).toList(),
       createLoad = createLoad ?? ExternalImageLoad.new;
  int get cachedBytes =>
      _lru.fold(0, (n, e) => n + (e.source?.bytes.length ?? 0));
  void more() {
    if (!active) return;
    final end = min(visible + 10, entries.length);
    for (var i = visible; i < end; i++) {
      _enqueue(entries[i]);
    }
    visible = end;
    notifyListeners();
    _pump();
  }

  void retry(ImageEntry entry) {
    if (!active || entry.loading) return;
    _enqueue(entry);
    notifyListeners();
    _pump();
  }

  void _enqueue(ImageEntry e) {
    e.requested = true;
    e.loading = true;
    e.error = null;
    _queue.add(e);
  }

  void touch(ImageEntry e) {
    if (_lru.remove(e)) _lru.add(e);
  }

  void _pump() {
    while (active && _running.length < 2 && _queue.isNotEmpty) {
      final entry = _queue.removeFirst(), load = createLoad();
      _running[entry] = load;
      unawaited(_load(entry, load));
    }
  }

  Future<void> _load(ImageEntry entry, ExternalImageLoad load) async {
    ui.Image? decoded;
    try {
      final source = await load.load(entry.uri);
      if (!active) return;
      final scale = min(1.0, 1000 / max(source.info.width, source.info.height));
      final codec = await ui.instantiateImageCodec(
        source.bytes,
        targetWidth: max(1, (source.info.width * scale).round()),
        targetHeight: max(1, (source.info.height * scale).round()),
        allowUpscaling: false,
      );
      try {
        decoded = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      if (!active) return;
      entry.release();
      entry.source = source;
      entry.thumbnail = decoded;
      decoded = null;
      touch(entry);
      _lru.add(entry);
      while (cachedBytes > cacheBudget && _lru.isNotEmpty) {
        final old = _lru.first;
        _lru.remove(old);
        old.release();
        old.error = 'Изображение выгружено из памяти. Загрузить повторно';
      }
    } catch (error) {
      if (active) entry.error = error is ImageLoadException ? error.message : 'Не удалось загрузить изображение: сеть, TLS, ограничения браузера или повреждённый файл';
    } finally {
      decoded?.dispose();
      load.cancel();
      _running.remove(entry);
      entry.loading = false;
      if (active) {
        notifyListeners();
        _pump();
      }
    }
  }

  void invalidate() {
    if (!active) return;
    active = false;
    for (final load in _running.values) {
      load.cancel();
    }
    _queue.clear();
    for (final e in entries) {
      e.release();
    }
    _lru.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    invalidate();
    super.dispose();
  }
}
