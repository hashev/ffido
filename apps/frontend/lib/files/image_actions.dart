import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/message_links.dart';
import 'uue_files.dart';
import 'image_share_cache_native.dart'
    if (dart.library.js_interop) 'image_share_cache_web.dart'
    as cache;

Future<void> cleanupImageShares() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return;
  try {
    await cache.cleanup();
  } catch (_) {
    /* Startup must remain usable if temporary storage is unavailable. */
  }
}

enum ImageActionResult { handedOff, cancelled, unsupported }

abstract class ImageActions {
  bool get canShare;
  Future<bool> openBrowser(Uri uri);
  Future<ImageActionResult> share(
    String name,
    String mime,
    Uint8List bytes,
    Rect origin, {
    bool Function()? isActive,
  });
  Future<void> cancelPending() async {}
  Future<bool> save(String name, Uint8List bytes);
}

class PlatformImageActions implements ImageActions {
  static const channel = MethodChannel('org.ffido/images');
  final Future<bool> Function(Uri)? launch;
  final Future<ShareResult> Function(ShareParams)? send;
  final UueFiles? files;
  PlatformImageActions({this.launch, this.send, this.files}) {
    if (!android) unawaited(cache.cleanup().catchError((Object _) {}));
  }
  bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  bool get canShare => kIsWeb || defaultTargetPlatform != TargetPlatform.linux;
  @override
  Future<bool> openBrowser(Uri uri) async {
    if (!webUri(uri)) return false;
    if (launch != null) return launch!(uri);
    if (android) {
      return await channel.invokeMethod<bool>('openBrowser', {
            'url': uri.toString(),
          }) ??
          false;
    }
    return launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }

  @override
  Future<ImageActionResult> share(
    String name,
    String mime,
    Uint8List bytes,
    Rect origin, {
    bool Function()? isActive,
  }) async {
    if (isActive != null && !isActive()) return ImageActionResult.cancelled;
    if (!canShare) return ImageActionResult.unsupported;
    if (android && send == null) {
      final result = await channel.invokeMethod<String>('share', {
        'name': safeUueName(name),
        'mime': mime,
        'bytes': bytes,
      });
      return switch (result) {
        'handedOff' => ImageActionResult.handedOff,
        'cancelled' => ImageActionResult.cancelled,
        _ => ImageActionResult.unsupported,
      };
    }
    final file = kIsWeb || send != null
        ? XFile.fromData(bytes, mimeType: mime, name: safeUueName(name))
        : await cache.prepare(safeUueName(name), mime, bytes);
    if (isActive != null && !isActive()) return ImageActionResult.cancelled;
    final result = await (send ?? SharePlus.instance.share)(
      ShareParams(
        files: [file],
        fileNameOverrides: [safeUueName(name)],
        sharePositionOrigin: origin,
        downloadFallbackEnabled: false,
        mailToFallbackEnabled: false,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => ImageActionResult.handedOff,
      ShareResultStatus.dismissed => ImageActionResult.cancelled,
      ShareResultStatus.unavailable => ImageActionResult.unsupported,
    };
  }

  @override
  Future<void> cancelPending() async {
    if (android) await channel.invokeMethod<void>('cancel');
  }

  @override
  Future<bool> save(String name, Uint8List bytes) =>
      (files ?? uueFiles).save(safeUueName(name), bytes);
}
