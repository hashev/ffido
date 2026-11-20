@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:fido/files/uue_files_web.dart';
import 'package:fido/files/uue_picker.dart';
import 'package:fido/files/uue_file_types.dart';
import 'package:file_selector/file_selector.dart';

@JS('Object.defineProperty')
external void defineProperty(
  JSObject target,
  JSString name,
  JSObject descriptor,
);
@JS('Object.getOwnPropertyDescriptor')
external JSObject? ownDescriptor(JSObject target, JSString name);

void main() {
  test('host detection uses nonempty Telegram initData, not an installed SDK alone', () async {
    final previous = globalContext.getProperty<JSAny?>('Telegram'.toJS);
    try {
      globalContext.setProperty(
        'Telegram'.toJS,
        {
          'WebApp': {'initData': ''},
        }.jsify(),
      );
      expect(PlatformUueFiles().requiresSaveGesture, isFalse);
      globalContext.setProperty(
        'Telegram'.toJS,
        {
          'WebApp': {'initData': 'fixture'},
        }.jsify(),
      );
      var exports = 0;
      final files = PlatformUueFiles(
        share: (_) async {
          exports++;
          return UueSaveResult.cancelled;
        },
      );
      expect(files.requiresSaveGesture, isTrue);
      expect(await files.save('a.bin', Uint8List(1)), UueSaveResult.cancelled);
      expect(exports, 1);
    } finally {
      globalContext.setProperty('Telegram'.toJS, previous);
    }
  });
  test('real Web Share bridge maps resolution, AbortError and unsupported without anchors', () async {
    final navigator = web.window.navigator;
    final previousCanShare = ownDescriptor(navigator, 'canShare'.toJS);
    final previousShare = ownDescriptor(navigator, 'share'.toJS);
    var anchors = 0;
    final click = ((web.Event event) {
      if ((event.target as web.Element?)?.tagName == 'A') anchors++;
    }).toJS;
    web.document.addEventListener('click', click, true.toJS);
    void restore(String name, JSObject? descriptor) {
      if (descriptor == null) {
        navigator.delete(name.toJS);
      } else {
        defineProperty(navigator, name.toJS, descriptor);
      }
    }

    try {
      for (final failure in [null, 'AbortError', 'NotAllowedError']) {
        defineProperty(
          navigator,
          'canShare'.toJS,
          {
                'configurable': true,
                'value': ((web.ShareData data) => true).toJS,
              }.jsify()
              as JSObject,
        );
        defineProperty(
          navigator,
          'share'.toJS,
          {
                'configurable': true,
                'value': ((web.ShareData data) => JSPromise<JSAny?>(
                  ((JSFunction resolve, JSFunction reject) {
                    if (failure == null) {
                      resolve.callAsFunction(null);
                    } else {
                      reject.callAsFunction(
                        null,
                        web.DOMException('test', failure),
                      );
                    }
                  }).toJS,
                )).toJS,
              }.jsify()
              as JSObject,
        );
        expect(
          await PlatformUueFiles(inTelegram: () => true)
              .save('a.bin', Uint8List(1)),
          failure == null
              ? UueSaveResult.shared
              : failure == 'AbortError'
              ? UueSaveResult.cancelled
              : UueSaveResult.unsupported,
        );
      }
      defineProperty(
        navigator,
        'canShare'.toJS,
        {
              'configurable': true,
              'value': ((web.ShareData data) => false).toJS,
            }.jsify()
            as JSObject,
      );
      expect(
        await PlatformUueFiles(inTelegram: () => true)
            .save('a.bin', Uint8List(1)),
        UueSaveResult.unsupported,
      );
      expect(anchors, 0);
    } finally {
      restore('share', previousShare);
      restore('canShare', previousCanShare);
      web.document.removeEventListener('click', click, true.toJS);
    }
  });
  test('Telegram exports exact private bytes without a URL', () async {
    final bytes = Uint8List.fromList([0, 255, 65]);
    final files = PlatformUueFiles(
      inTelegram: () => true,
      share: (data) async {
        final file = data.files.toDart.single;
        expect(file.name, 'private.bin');
        expect(data.getProperty<JSAny?>('url'.toJS), isNull);
        final received = (await file.arrayBuffer().toDart).toDart.asUint8List();
        expect(received, bytes);
        return UueSaveResult.shared;
      },
    );
    expect(await files.save('../private.bin', bytes), UueSaveResult.shared);
  });
  test(
    'Telegram cancellation and unavailable hosts never claim saved',
    () async {
      for (final result in [
        UueSaveResult.shared,
        UueSaveResult.cancelled,
        UueSaveResult.unsupported,
      ]) {
        final files = PlatformUueFiles(
          inTelegram: () => true,
          share: (_) async => result,
        );
        expect(await files.save('a.bin', Uint8List(1)), result);
      }
      final files = PlatformUueFiles(
        inTelegram: () => true,
        share: (_) async => throw UnsupportedError('No Web Share file support'),
      );
      expect(
        await files.save('a.bin', Uint8List(1)),
        UueSaveResult.unsupported,
      );
    },
  );
  test(
    'browser selection preserves the supplied filename and exact bytes',
    () async {
      final bytes = Uint8List.fromList([0, 255, 65]);
      final file = await pickUueFile(
        3,
        chooseFile: () async => XFile.fromData(bytes, name: 'picked.bin'),
      );
      expect(file!.name, 'picked.bin');
      expect(file.bytes, bytes);
      expect(await pickUueFile(3, chooseFile: () async => null), isNull);
    },
  );
  test(
    'download uses a private blob and safe filename without an auth URL',
    () async {
      String? url, name;
      final callback = ((web.Event event) {
        final element = event.target as web.Element?;
        if (element?.tagName != 'A') return;
        final link = element as web.HTMLAnchorElement;
        event.preventDefault();
        url = link.href;
        name = link.download;
      }).toJS;
      web.document.addEventListener('click', callback, true.toJS);
      try {
        final bytes = Uint8List.fromList([0, 255, 65]);
        expect(
          await PlatformUueFiles(inTelegram: () => false)
              .save('../private.bin', bytes),
          UueSaveResult.downloadRequested,
        );
        expect(name, 'private.bin');
        expect(url, startsWith('blob:'));
        expect(url, isNot(contains('Bearer')));
        final response = await web.window.fetch(url!.toJS).toDart;
        final received = (await response.arrayBuffer().toDart).toDart
            .asUint8List();
        expect(received, bytes);
      } finally {
        web.document.removeEventListener('click', callback, true.toJS);
      }
    },
  );
}
