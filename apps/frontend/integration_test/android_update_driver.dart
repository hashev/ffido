// Release-only QA entry point, never used by the application's normal build.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:fido/updates/update_metadata.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/session_store.dart';

const bridge = MethodChannel('ffido/updates');
const stage = String.fromEnvironment('FFIDO_QA_STAGE', defaultValue: 'A');
const origin = String.fromEnvironment('FFIDO_QA_ORIGIN');
const endpoint = 'https://update-qa.invalid:8080';
const secret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
  final preferences = await SharedPreferences.getInstance();
  const store = SecureSessionStore();
  if (stage == 'A' && !preferences.containsKey('ffido_update_qa_sentinel')) {
    await preferences.setString('ffido_update_qa_sentinel', 'preserve-me');
    await store.write(endpoint, secret);
  }
  final record = {
    'stage': stage,
    'preferences':
        preferences.getString('ffido_update_qa_sentinel') == 'preserve-me',
    'secureSession': await store.read(endpoint) == secret,
  };
  debugPrint('FFIDO_UPDATE_QA ${jsonEncode(record)}');
  runApp(MaterialApp(home: UpdateQA(record: record)));
}

class UpdateQA extends StatefulWidget {
  const UpdateQA({super.key, required this.record});
  final Map<String, Object> record;
  @override
  State<UpdateQA> createState() => _UpdateQAState();
}

class _UpdateQAState extends State<UpdateQA> {
  String message = '';
  bool busy = false;
  Future<void> install(String name) async {
    setState(() {
      busy = true;
      message = 'Downloading $name';
    });
    try {
      final info = await bridge.invokeMapMethod<String, dynamic>('info');
      final directory = Directory(info!['cacheDirectory'] as String);
      final file = File('${directory.path}/update-qa.apk');
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(
          Uri.parse('$origin/$name.apk'),
        )).close();
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}');
        }
        await response.pipe(file.openWrite());
        if (name == 'B' &&
            const bool.fromEnvironment('FFIDO_QA_VERIFY_MANIFEST')) {
          Future<Uint8List> fetch(String asset) async {
            final response = await (await client.getUrl(
              Uri.parse('$origin/$asset'),
            )).close();
            if (response.statusCode != 200) {
              throw HttpException('Missing signed QA manifest');
            }
            return Uint8List.fromList(
              await response.fold<List<int>>(
                [],
                (bytes, chunk) => bytes..addAll(chunk),
              ),
            );
          }

          final manifest = await UpdateManifest.verify(
            await fetch('release-manifest.json'),
            await fetch('release-manifest.sig'),
            updateObject(
              jsonDecode(
                await rootBundle.loadString('assets/updates/public_keys.json'),
              ),
            ),
          );
          final package = manifest.clientPackage(
            UpdatePlatform('android', 'universal', [info['sdk'] as int]),
          );
          if (package == null ||
              package.file != 'B.apk' ||
              manifest.identity.buildNumber != 41002 ||
              await file.length() != package.size ||
              (await crypto.sha256.bind(file.openRead()).first).toString() !=
                  package.sha256) {
            throw StateError('Signed production-key manifest differs from APK');
          }
          debugPrint(
            'FFIDO_UPDATE_QA ${jsonEncode({'manifestVerified': true, 'stage': stage})}',
          );
        }
      } finally {
        client.close(force: true);
      }
      final result = await bridge.invokeMethod<bool>('install', {
        'path': file.path,
      });
      message = result == true ? 'installed' : 'cancelled';
    } catch (error) {
      message = '$error';
    }
    debugPrint(
      'FFIDO_UPDATE_QA ${jsonEncode({'stage': stage, 'result': message})}',
    );
    if (mounted) {
      setState(() {
        busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('FFIDO release update QA $stage')),
    body: ListView(
      children: [
        Text(jsonEncode(widget.record)),
        Text(message),
        for (final name in ['B', 'foreign-key', 'foreign-id', 'A', 'lower'])
          ElevatedButton(
            onPressed: busy ? null : () => install(name),
            child: Text('Install $name'),
          ),
      ],
    ),
  );
}
