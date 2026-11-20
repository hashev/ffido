import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'uue_file_types.dart';
import 'uue_picker.dart';

@JS('Telegram.WebApp.initData')
external JSString? get _telegramInitData;

bool _inTelegram() {
  try {
    return _telegramInitData?.toDart.isNotEmpty ?? false;
  } catch (_) {
    return false;
  }
}

extension type _SharePromise(JSObject _) implements JSObject {
  external JSAny? then(JSFunction fulfilled, JSFunction rejected);
}

Future<UueSaveResult> _shareFiles(web.ShareData data) {
  final completion = Completer<UueSaveResult>();
  try {
    if (!web.window.navigator.canShare(data)) {
      return Future.value(UueSaveResult.unsupported);
    }
    final promise = web.window.navigator.share(data);
    _SharePromise(promise).then(
      ((JSAny? value) {
        completion.complete(UueSaveResult.shared);
      }).toJS,
      ((JSAny? error) {
        final cancelled =
            error != null &&
            error.isA<web.DOMException>() &&
            (error as web.DOMException).name == 'AbortError';
        completion.complete(
          cancelled ? UueSaveResult.cancelled : UueSaveResult.unsupported,
        );
      }).toJS,
    );
  } catch (_) {
    completion.complete(UueSaveResult.unsupported);
  }
  return completion.future;
}

class PlatformUueFiles implements UueFiles {
  PlatformUueFiles({
    bool Function()? inTelegram,
    Future<UueSaveResult> Function(web.ShareData)? share,
  }) : inTelegram = inTelegram ?? _inTelegram,
       share = share ?? _shareFiles;

  final bool Function() inTelegram;
  final Future<UueSaveResult> Function(web.ShareData) share;

  @override
  bool get requiresSaveGesture => inTelegram();

  @override
  Future<SelectedUueFile?> pick(int maxBytes) => pickUueFile(maxBytes);
  @override
  Future<UueSaveResult> save(String name, Uint8List bytes) async {
    name = safeUueName(name);
    if (bytes.length > 16 * 1024 * 1024) throw uueFileLimit();
    if (inTelegram()) {
      // Embedded hosts may silently discard blob downloads. Keep private bytes
      // local and use the native file share bridge, without URL fallbacks.
      try {
        final file = web.File(
          [bytes.toJS].toJS,
          name,
          web.FilePropertyBag(type: 'application/octet-stream'),
        );
        return await share(web.ShareData(files: [file].toJS));
      } catch (_) {
        return UueSaveResult.unsupported;
      }
    }
    final body = web.document.body;
    if (body == null) return UueSaveResult.unsupported;
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final url = web.URL.createObjectURL(blob);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = name;
    try {
      body.append(link);
      link.click();
      return UueSaveResult.downloadRequested;
    } finally {
      link.remove();
      Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
    }
  }
}
