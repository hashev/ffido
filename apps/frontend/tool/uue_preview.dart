// Dedicated temporary-fixture entry point; never used by the production app.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/platform/desktop_profile.dart';
import 'package:fido/repositories/message_repository.dart';
import 'package:fido/models/conference.dart';
import 'package:fido/pages/message_screen.dart';
import 'package:fido/utils/reader_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopProfile.initialize();
  final point = DesktopProfile.current.id.endsWith('2') ? 2 : 1;
  const endpoint = String.fromEnvironment('FFIDO_UUE_ENDPOINT');
  const certificate = String.fromEnvironment('FFIDO_UUE_CA');
  final api = ApiClient(
    endpoint: endpoint,
    channelFactory: (uri) => grpc.ClientChannel(
      uri.host,
      port: uri.port,
      options: grpc.ChannelOptions(
        credentials: grpc.ChannelCredentials.secure(
          certificates: base64Decode(certificate),
          authority: 'localhost',
        ),
      ),
    ),
  );
  DesktopProfile.observeIdentity(api);
  await api.login(
    endpoint: endpoint,
    name: 'UUE Point $point',
    address: '2:1/2.$point',
    password: 'fixture',
  );
  final preferences = await SharedPreferences.getInstance();
  final catalog = await api.listConferences(
    wire.ListConferencesRequest(
      page: wire.PageRequest(limit: 100),
      sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
    ),
  );
  final mailbox = catalog.conferences.singleWhere(
    (area) => area.personalMailbox,
  );
  final repository = MessageRepository(api);
  runApp(
    MaterialApp(
      theme: readerTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text('UUE QA · ${DesktopProfile.current.id} · 2:1/2.$point'),
          ),
          body: ListView(
            children: [
              ListTile(
                title: const Text('Личная почта'),
                subtitle: Text(mailbox.id),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MessageScreen(
                      conferenceId: mailbox.id,
                      conferenceName: 'Моя почта',
                      conferenceDescription: 'Временный стенд UUE',
                      canRead: true,
                      canPost: true,
                      kind: AreaKind.netmail,
                      personalMailbox: true,
                      repository: repository,
                    ),
                  ),
                ),
              ),
              ListTile(
                title: const Text('ECHO'),
                subtitle: Text(
                  'Профиль ${DesktopProfile.current.id}; сохранённых ключей: ${preferences.getKeys().length}',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MessageScreen(
                      conferenceId: 'ECHO',
                      conferenceName: 'ECHO',
                      conferenceDescription: 'Временный стенд UUE',
                      canRead: true,
                      canPost: true,
                      repository: repository,
                    ),
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
