// Optional deployment check against the real C++ server and isolated JAM files.
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/api/model_mapping.dart';

void main() {
  final binary = Platform.environment['FFIDO_E2E_BACKEND'];
  test(
    'real Flutter transport isolates owner and two points across server restart',
    () async {
      final root = await Directory.systemTemp.createTemp('ffido-private-e2e-');
      Process? server;
      final log = StringBuffer();
      Future<void> stop() async {
        final current = server;
        server = null;
        if (current != null) {
          current.kill(ProcessSignal.sigterm);
          expect(
            await current.exitCode.timeout(const Duration(seconds: 10)),
            0,
            reason: log.toString(),
          );
        }
      }

      addTearDown(() async {
        await stop();
        await root.delete(recursive: true);
      });
      final cert = '${root.path}/cert.pem', key = '${root.path}/key.pem';
      Future<void> openssl(List<String> arguments) async {
        final result = await Process.run('openssl', arguments);
        expect(result.exitCode, 0, reason: result.stderr.toString());
      }

      await openssl([
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-days',
        '1',
        '-subj',
        '/CN=FFIDO isolated test CA',
        '-addext',
        'basicConstraints=critical,CA:TRUE',
        '-keyout',
        '${root.path}/ca.key',
        '-out',
        '${root.path}/ca.pem',
      ]);
      await openssl([
        'req',
        '-new',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-subj',
        '/CN=localhost',
        '-keyout',
        key,
        '-out',
        '${root.path}/server.csr',
      ]);
      await File('${root.path}/extensions').writeAsString(
        'subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n',
      );
      await openssl([
        'x509',
        '-req',
        '-days',
        '1',
        '-in',
        '${root.path}/server.csr',
        '-CA',
        '${root.path}/ca.pem',
        '-CAkey',
        '${root.path}/ca.key',
        '-CAcreateserial',
        '-extfile',
        '${root.path}/extensions',
        '-out',
        cert,
      ]);
      for (final name in ['ECHO', 'MAIL', 'LOCAL', 'BAD', 'DUPE', 'ROBOT']) {
        final header = ByteData(1024);
        header.setUint32(0, 0x004d414a, Endian.little);
        header.setUint32(4, 123, Endian.little);
        header.setUint32(16, 0xffffffff, Endian.little);
        header.setUint32(20, 1, Endian.little);
        await File(
          '${root.path}/$name.jhr',
        ).writeAsBytes(header.buffer.asUint8List());
        for (final ext in ['jdt', 'jdx']) {
          await File('${root.path}/$name.$ext').writeAsBytes([]);
        }
      }
      await File(
        '${root.path}/areas.cfg',
      ).writeAsString('EchoArea ECHO ${root.path}/ECHO -b JAM\n');
      await File('${root.path}/hpt.cfg').writeAsString('''Name Fixture
Sysop Test
Location Test
Address 2:1/2.1
Link Boss
AKA 2:1/2
OurAKA 2:1/2.1
Password owner-fixture
Link P1
AKA 2:1/2.2
OurAKA 2:1/2.1
Password p1-fixture
Link P2
AKA 2:1/2.3
OurAKA 2:1/2.1
Password p2-fixture
EchoArea ECHO ${root.path}/ECHO -b JAM 2:1/2 2:1/2.2 2:1/2.3
NetmailArea MAIL ${root.path}/MAIL -b JAM
LocalArea LOCAL ${root.path}/LOCAL -b JAM
BadArea BAD ${root.path}/BAD -b JAM
DupeArea DUPE ${root.path}/DUPE -b JAM
NetArea ROBOT ${root.path}/ROBOT -b JAM
RobotsArea ROBOT
LocalArea OLD ${root.path}/OLD -b Squish
''');
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final config = <String, dynamic>{
        'auth': {
          'hpt_config_path': 'hpt.cfg',
          'session_key_path': 'session.key',
          'owner_addresses': ['2:1/2.1'],
        },
        'ftn': {
          'areacfg_path': 'areas.cfg',
          'jam_base_path': '.',
          'default_encoding': 'cp866',
          'coordination_lock': 'hpt.lock',
        },
        'database': {'metadata_path': 'metadata.db'},
        'server': {
          'ip': '127.0.0.1',
          'port': port,
          'tls_certificate': cert,
          'tls_private_key': key,
        },
      };
      Future<void> start() async {
        await File(
          '${root.path}/config.json',
        ).writeAsString(jsonEncode(config));
        server = await Process.start(binary!, ['${root.path}/config.json']);
        server!.stdout.transform(utf8.decoder).listen(log.write);
        server!.stderr.transform(utf8.decoder).listen(log.write);
        var ready = false;
        for (var i = 0; i < 100; i++) {
          try {
            final socket = await Socket.connect(
              '127.0.0.1',
              port,
              timeout: const Duration(milliseconds: 100),
            );
            await socket.close();
            ready = true;
            break;
          } on SocketException {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
        expect(ready, isTrue, reason: log.toString());
      }

      await start();
      final certificate = await File('${root.path}/ca.pem').readAsBytes();
      final api = ApiClient(
        endpoint: 'https://127.0.0.1:$port',
        readAttempts: 1,
        channelFactory: (uri) => ClientChannel(
          uri.host,
          port: uri.port,
          options: ChannelOptions(
            credentials: ChannelCredentials.secure(
              certificates: certificate,
              authority: 'localhost',
            ),
          ),
        ),
      );
      addTearDown(api.dispose);
      const net = '@ffido/1/6d61696c', local = '@ffido/2/6c6f63616c';
      wire.ListConferencesRequest list() => wire.ListConferencesRequest(
        page: wire.PageRequest(limit: 100),
        sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
      );
      await api.login(
        endpoint: 'https://127.0.0.1:$port',
        name: 'Одинаковое имя',
        address: '2:1/2.1',
        password: 'owner-fixture',
      );
      var catalog = await api.listConferences(list());
      expect(catalog.total.toInt(), 7);
      final old = mapConference(
        catalog.conferences.singleWhere((c) => c.name == 'OLD'),
      );
      expect(old.statisticsKnown, isFalse);
      expect(old.unsupportedFormat, isTrue);
      final request = wire.CreateMessageRequest(
        conferenceId: net,
        operationId: 'e2e-net',
        toName: 'Николай',
        toAddress: '2:1/3.4',
        subject: 'Н тема',
        body: 'Н текст',
      );
      final sent = await api.createMessage(request);
      final detail = await api.getMessage(sent.message);
      expect(detail.fromAddress, '2:1/2.1');
      expect(detail.fromName, 'Одинаковое имя');
      expect(detail.subject, 'H тема');
      expect(detail.body, 'H текст\n');
      await api.addBookmark(wire.GetConferenceRequest(conferenceId: net));
      final reply = request.deepCopy()
        ..operationId = 'e2e-reply'
        ..inReplyTo = sent.message.messageId;
      await api.createMessage(reply);
      final localRequest = request.deepCopy()
        ..conferenceId = local
        ..operationId = 'e2e-local';
      await api.createMessage(localRequest);
      for (final area in [
        '@ffido/3/626164',
        '@ffido/4/64757065',
        '@ffido/5/726f626f74',
      ]) {
        await expectLater(
          api.createMessage(request.deepCopy()..conferenceId = area),
          throwsA(isA<ApiException>()),
        );
      }
      for (final point in [2, 3]) {
        await api.login(
          endpoint: 'https://127.0.0.1:$port',
          name: 'Одинаковое имя',
          address: '2:1/2.$point',
          password: 'p${point - 1}-fixture',
        );
        catalog = await api.listConferences(list());
        expect(catalog.conferences.single.name, 'ECHO');
        await expectLater(
          api.getConference(wire.GetConferenceRequest(conferenceId: net)),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          api.getMessage(sent.message),
          throwsA(isA<ApiException>()),
        );
        expect(
          (await api.listBookmarks(wire.PageRequest(limit: 100))).total.toInt(),
          0,
        );
        expect(
          (await api.listHistory(wire.PageRequest(limit: 100))).total.toInt(),
          0,
        );
      }
      await api.login(
        endpoint: 'https://127.0.0.1:$port',
        name: 'Одинаковое имя',
        address: '2:1/2.1',
        password: 'owner-fixture',
      );
      await stop();
      await start();
      final repeated = await api.createMessage(request);
      expect(repeated.message.messageId, sent.message.messageId);
      expect(
        (await File('${root.path}/MAIL.jdx').length()),
        16,
      ); // original + reply, no retry duplicate.
      await stop();
      (config['auth'] as Map<String, dynamic>)['owner_addresses'] = <String>[];
      await start();
      await expectLater(
        api.getConference(wire.GetConferenceRequest(conferenceId: net)),
        throwsA(isA<ApiException>()),
      );
      expect(
        (await api.listBookmarks(wire.PageRequest(limit: 100))).total.toInt(),
        0,
      );
      await stop();
      (config['auth'] as Map<String, dynamic>)['owner_addresses'] = ['2:1/2.1'];
      await start();
      expect(
        (await api.listBookmarks(wire.PageRequest(limit: 100))).total.toInt(),
        1,
      );
    },
    skip: binary == null
        ? 'Set FFIDO_E2E_BACKEND to built fidoback for isolated end-to-end check'
        : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
