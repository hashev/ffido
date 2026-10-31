import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Composing any message now reads identity for the effective template context.
void mockMessageIdentity() {
  rootBundle.evict('assets/updates/identity.json');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        if (message == null ||
            utf8.decode(
                  message.buffer.asUint8List(
                    message.offsetInBytes,
                    message.lengthInBytes,
                  ),
                ) !=
                'assets/updates/identity.json') {
          return null;
        }
        return ByteData.sublistView(
          Uint8List.fromList(
            utf8.encode('{"version":"test","build_number":1}'),
          ),
        );
      });
}
