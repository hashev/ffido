import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:fixnum/fixnum.dart';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;

// Independent Type-2+ wire reader: packet envelope and message author are distinct.
Iterable<Map<String, Object>> packedMessages(Uint8List bytes) sync* {
  if (bytes.length < 60) return;
  final data = ByteData.sublistView(bytes);
  int word(int offset) => data.getUint16(offset, Endian.little);
  if (word(18) != 2) return;
  var position = 58;
  String string() {
    final end = bytes.indexOf(0, position);
    if (end < position) {
      throw const FormatException('Truncated FTN packet string');
    }
    final value = latin1.decode(bytes.sublist(position, end));
    position = end + 1;
    return value;
  }

  while (position + 2 <= bytes.length && word(position) != 0) {
    if (word(position) != 2 || position + 14 > bytes.length) {
      throw const FormatException('Invalid FTN message header');
    }
    var origin =
        '${word(46) == 0 ? word(34) : word(46)}:${word(position + 6)}/${word(position + 2)}';
    var destination =
        '${word(48) == 0 ? word(36) : word(48)}:${word(position + 8)}/${word(position + 4)}';
    final attributes = word(position + 10);
    position += 14;
    string();
    final to = string(), from = string(), subject = string(), body = string();
    var originPoint = word(50), destinationPoint = word(52);
    var msgid = '';
    for (final line in body.split('\r')) {
      if (!line.startsWith('\x01')) continue;
      final parts = line.substring(1).trim().split(RegExp(r'\s+'));
      if (parts.length == 2 && parts[0] == 'FMPT') {
        originPoint = int.parse(parts[1]);
      }
      if (parts.length == 2 && parts[0] == 'TOPT') {
        destinationPoint = int.parse(parts[1]);
      }
      if (parts.length == 3 && parts[0] == 'INTL') {
        destination = parts[1];
        origin = parts[2];
      }
      if (line.startsWith('\x01MSGID: ')) msgid = line.substring(8).trim();
    }
    if (originPoint != 0 && !origin.contains('.')) origin += '.$originPoint';
    if (destinationPoint != 0 && !destination.contains('.')) {
      destination += '.$destinationPoint';
    }
    yield {
      'origin': origin,
      'destination': destination,
      'attributes': attributes,
      'to': to,
      'from': from,
      'subject': subject,
      'body': body,
      'msgid': msgid,
    };
  }
}

void main() {
  final binary = Platform.environment['FFIDO_E2E_BACKEND'];
  final hpt = Platform.environment['FFIDO_TEST_HPT'];
  test(
    'phone laptop and another point share isolated durable mail through actual HPT',
    () async {
      final root = await Directory.systemTemp.createTemp('ffido-point-e2e-');
      final project = Directory.current.parent.parent;
      final admin = '${File(binary!).parent.path}/ffido-admin';
      final wrapper = '${project.path}/scripts/run_hpt.py';
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
      for (final name in ['ECHO', 'IN', 'OUT', 'LOCAL', 'BAD', 'DUPE']) {
        final header = ByteData(1024);
        header.setUint32(0, 0x004d414a, Endian.little);
        header.setUint32(4, 123, Endian.little);
        header.setUint32(16, 0xffffffff, Endian.little);
        header.setUint32(20, 1, Endian.little);
        await File('${root.path}/$name.jhr')
            .writeAsBytes(header.buffer.asUint8List());
        for (final extension in ['jdt', 'jdx']) {
          await File('${root.path}/$name.$extension').writeAsBytes([]);
        }
      }
      final directories = {
        'Inbound': 'inbound',
        'ProtInbound': 'protinbound',
        'Outbound': 'outbound',
        'TempInbound': 'tmpin',
        'TempOutbound': 'tmpout',
        'LogFileDir': 'logs',
        'DupeHistoryDir': 'dupes',
        'NodelistDir': 'nodelist',
      };
      final hptText = StringBuffer(
        'Name FFIDO fixture\nSysop Test\nLocation Test\nAddress 2:1/2\n',
      );
      for (final entry in directories.entries) {
        await Directory('${root.path}/${entry.value}').create();
        hptText.writeln('${entry.key} ${root.path}/${entry.value}');
      }
      hptText.writeln(
        'MsgBaseDir ${root.path}\nEchoTossLog ${root.path}/logs/toss.log',
      );
      for (final point in [1, 2, 3, 4]) {
        hptText.writeln(
          'Link Point$point\nAKA 2:1/2.$point\nOurAKA 2:1/2\nPassword p$point-fixture\nAllowEmptyPktPwd on',
        );
      }
      hptText.writeln(
        'Link Remote\nAKA 2:1/9\nOurAKA 2:1/2\nPassword remote-fixture\nAllowEmptyPktPwd on',
      );
      hptText.writeln(
        'KeepTrsMail on\nPackNetMailOnScan off\nRoute nopack 2:1/2.1 2:1/2.2\nRoute normal 2:1/9 2:1/9.*\nRoute normal noroute *',
      );
      hptText.writeln(
        'EchoArea ECHO ${root.path}/ECHO -b JAM 2:1/2.1 2:1/2.2 2:1/2.3 2:1/2.4',
      );
      for (final name in ['IN', 'OUT']) {
        hptText.writeln(
          'NetmailArea $name ${root.path}/$name -b JAM -dupeCheck off',
        );
      }
      hptText.writeln(
        'LocalArea LOCAL ${root.path}/LOCAL -b JAM\nBadArea BAD ${root.path}/BAD -b JAM\nDupeArea DUPE ${root.path}/DUPE -b JAM',
      );
      final hptConfig = File('${root.path}/hpt.cfg');
      await hptConfig.writeAsString(hptText.toString());
      await File('${root.path}/areas.cfg')
          .writeAsString('EchoArea ECHO ${root.path}/ECHO -b JAM\n');
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final points = [
        for (final point in [1, 2])
          {'address': '2:1/2.$point', 'jam_base': 'points/p$point'},
      ];
      final config = <String, dynamic>{
        'auth': {
          'hpt_config_path': 'hpt.cfg',
          'session_key_path': 'session.key',
          'owner_addresses': ['2:1/2.3'],
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
        'point_mail': {
          'enabled': true,
          'ingress_areas': ['IN'],
          'egress_area': 'OUT',
          'points': points,
        },
      };
      final configFile = File('${root.path}/config.json');
      Future<void> save() =>
          configFile.writeAsString(jsonEncode(config)).then((_) {});
      Future<void> run(String executable, List<String> arguments) async {
        final result = await Process.run(executable, arguments);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }

      await save();
      await run(admin, ['provision-mailboxes', configFile.path]);
      Future<void> cycle() => run('python3', [
        wrapper,
        '--config',
        configFile.path,
        '--cycle',
        '--admin',
        admin,
        '--hpt',
        hpt!,
      ]);
      Future<void> start() async {
        await save();
        server = await Process.start(binary, [configFile.path]);
        server!.stdout.transform(utf8.decoder).listen(log.write);
        server!.stderr.transform(utf8.decoder).listen(log.write);
        var ready = false;
        for (var i = 0; i < 100; i++) {
          try {
            final s = await Socket.connect(
              '127.0.0.1',
              port,
              timeout: const Duration(milliseconds: 100),
            );
            await s.close();
            ready = true;
            break;
          } on SocketException {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
        expect(ready, isTrue, reason: log.toString());
      }

      // Import a shared MSGID for two recipients, a boss letter, ordinary point and transit.
      final fixture = '${project.path}/apps/backend/tests/support';
      final generated = await Process.run('python3', [
        '-c',
        'import sys;sys.path.insert(0,sys.argv[1]);from hpt_routing_fixture import packet;sys.stdout.buffer.write(packet([("p1",2,1),("p2",2,2),("boss",2,0),("ordinary",2,4),("transit",7,1)],True))',
        fixture,
      ], stdoutEncoding: null);
      expect(generated.exitCode, 0);
      final incoming = generated.stdout as List<int>;
      await File('${root.path}/protinbound/input.pkt').writeAsBytes(incoming);
      await cycle();
      await start();
      final certificate = await File('${root.path}/ca.pem').readAsBytes();
      ApiClient client() {
        final result = ApiClient(
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
        addTearDown(result.dispose);
        return result;
      }

      final phone = client(),
          laptop = client(),
          p2 = client(),
          owner = client(),
          ordinary = client();
      Future<void> login(
        ApiClient api,
        int point, {
        String name = 'Нина',
        String? password,
      }) => api
          .login(
            endpoint: 'https://127.0.0.1:$port',
            name: name,
            address: '2:1/2.$point',
            password: password ?? 'p$point-fixture',
          )
          .then((_) {});
      await login(phone, 1);
      await login(laptop, 1, name: 'Другой клиент');
      await login(p2, 2);
      await login(owner, 3);
      await login(ordinary, 4);
      wire.ListConferencesRequest catalogRequest() =>
          wire.ListConferencesRequest(
            page: wire.PageRequest(limit: 100),
            sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
          );
      final catalog = await phone.listConferences(catalogRequest());
      expect(catalog.total.toInt(), 2);
      final mailbox = catalog.conferences.singleWhere((c) => c.personalMailbox);
      final firstId = mailbox.id;
      final other = (await p2.listConferences(catalogRequest())).conferences
          .singleWhere((c) => c.personalMailbox);
      expect(
        (await owner.listConferences(catalogRequest())).conferences
            .where((c) => c.personalMailbox),
        isEmpty,
      );
      expect(
        (await ordinary.listConferences(catalogRequest()))
            .conferences
            .single
            .name,
        'ECHO',
      );
      wire.ListMessagesRequest page(
        String id, {
        String? anchor,
        int offset = 0,
        int limit = 100,
      }) => wire.ListMessagesRequest(
        conferenceId: id,
        page: wire.PageRequest(offset: Int64(offset), limit: limit),
        anchorMessageId: anchor,
        sort: wire.MessageSort.MESSAGE_SORT_DATE_DESCENDING,
      );
      var rows = await phone.listMessages(page(firstId));
      expect(rows.total.toInt(), 1);
      final first = rows.messages.single;
      expect(first.direction, wire.MailDirection.MAIL_DIRECTION_INCOMING);
      expect(first.isRead, isFalse);
      for (final api in [p2, owner, ordinary]) {
        await expectLater(
          api.getConference(wire.GetConferenceRequest(conferenceId: firstId)),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          api.getMessage(
            wire.MessageReference(conferenceId: firstId, messageId: first.id),
          ),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          api.listMessages(page(firstId, anchor: first.id)),
          throwsA(isA<ApiException>()),
        );
        final reference = wire.MessageReference(
          conferenceId: firstId,
          messageId: first.id,
        );
        await expectLater(
          api.markRead(reference),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          api.getThread(
            wire.GetThreadRequest(
              conferenceId: firstId,
              threadId: first.id,
              page: wire.PageRequest(limit: 20),
            ),
          ),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          api.addBookmark(wire.GetConferenceRequest(conferenceId: firstId)),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          api.createMessage(
            wire.CreateMessageRequest(
              conferenceId: firstId,
              operationId: 'forbidden',
              toName: 'Remote',
              toAddress: '2:1/9.7',
              subject: 'Subject',
              body: 'Body',
            ),
          ),
          throwsA(isA<ApiException>()),
        );
      }
      final opened = await phone.getMessage(
        wire.MessageReference(conferenceId: firstId, messageId: first.id),
      );
      expect(opened.positionRevision.toInt(), greaterThan(0));
      final laptopState = await laptop.getConference(
        wire.GetConferenceRequest(conferenceId: firstId),
      );
      expect(laptopState.unreadCount.toInt(), 0);
      expect(laptopState.lastOpenedMessageId, first.id);
      expect(
        (await p2.getConference(
          wire.GetConferenceRequest(conferenceId: other.id),
        )).unreadCount.toInt(),
        1,
      );
      await phone.addBookmark(wire.GetConferenceRequest(conferenceId: firstId));
      expect(
        (await laptop.listBookmarks(wire.PageRequest(limit: 100))).total
            .toInt(),
        1,
      );
      expect(
        (await p2.listBookmarks(wire.PageRequest(limit: 100))).total.toInt(),
        0,
      );
      expect(
        (await laptop.listHistory(wire.PageRequest(limit: 100))).total.toInt(),
        1,
      );
      expect(
        (await p2.listHistory(wire.PageRequest(limit: 100))).total.toInt(),
        0,
      );
      final search = catalogRequest()..query = 'Моя почта';
      expect((await phone.listConferences(search)).total.toInt(), 1);
      await expectLater(
        phone.listMessages(
          page(
            firstId,
            anchor: (await p2.listMessages(page(other.id))).messages.first.id,
          ),
        ),
        throwsA(isA<ApiException>()),
      );

      wire.CreateMessageRequest send(
        String operation, {
        String to = '2:1/9.7',
        String parent = '',
      }) => wire.CreateMessageRequest(
        conferenceId: firstId,
        operationId: operation,
        toName: 'Николай',
        toAddress: to,
        subject: 'Н тема',
        body: 'Н текст',
        inReplyTo: parent,
      );
      final request = send('external');
      final sent = await phone.createMessage(request);
      expect(
        (await laptop.createMessage(request)).message.messageId,
        sent.message.messageId,
      );
      final changed = request.deepCopy()..body = 'changed';
      await expectLater(
        phone.createMessage(changed),
        throwsA(isA<ApiException>()),
      );
      final reply = await phone.createMessage(
        send('incoming-reply', parent: first.id),
      );
      await phone.createMessage(send('local', to: '2:1/2.2'));
      for (var i = 0; i < 22; i++) {
        await phone.createMessage(send('history-$i'));
      }
      // An explicit read on the phone establishes a position beyond the first newest page.
      await phone.getMessage(
        wire.MessageReference(conferenceId: firstId, messageId: first.id),
      );
      final anchored = await laptop.listMessages(
        page(firstId, anchor: first.id, limit: 20),
      );
      expect(anchored.actualOffset.toInt(), 20);
      expect(anchored.messages.any((m) => m.id == first.id), isTrue);
      await cycle();
      await cycle();
      rows = await laptop.listMessages(page(firstId));
      expect(rows.total.toInt(), 26);
      final saved = await laptop.getMessage(sent.message);
      expect(saved.fromAddress, '2:1/2.1');
      expect(saved.fromName, 'Hина');
      expect(saved.toAddress, '2:1/9.7');
      expect(saved.subject, 'H тема');
      expect(saved.body, 'H текст\n');
      expect(saved.direction, wire.MailDirection.MAIL_DIRECTION_OUTGOING);
      final incomingReply = await phone.getMessage(reply.message);
      expect(incomingReply.toAddress, '2:1/9.7');
      final ownReply = send('own-reply', parent: sent.message.messageId)
        ..toAddress = ''
        ..toName = '';
      final ownSent = await phone.createMessage(ownReply);
      expect((await phone.getMessage(ownSent.message)).toAddress, '2:1/9.7');
      final p2Rows = await p2.listMessages(page(other.id));
      expect(p2Rows.total.toInt(), 2);
      expect(p2Rows.messages.every((m) => !m.isRead), isTrue);
      var packets = '';
      final wireMessages = <Map<String, Object>>[];
      await for (final entry in Directory(
        '${root.path}/outbound',
      ).list(recursive: true)) {
        if (entry is File) {
          final bytes = await entry.readAsBytes();
          packets += latin1.decode(bytes);
          wireMessages.addAll(packedMessages(bytes));
        }
      }
      expect(packets, contains(sent.ftnMessageId));
      final exported = wireMessages.singleWhere(
        (message) => message['msgid'] == sent.ftnMessageId,
      );
      expect(exported['origin'], '2:1/2.1');
      expect(exported['destination'], '2:1/9.7');
      expect((exported['attributes'] as int) & 1, 1);
      expect(exported['from'], latin1.decode([0x48, 0xa8, 0xad, 0xa0]));
      expect(
        exported['body'] as String,
        contains(latin1.decode([0x48, 0x20, 0xe2, 0xa5, 0xaa, 0xe1, 0xe2])),
      );

      expect(packets, contains('REPLY: 2:1/9.7 12345678'));
      expect(packets, contains('Marker ordinary'));
      expect(packets, contains('Marker transit'));
      expect(packets, isNot(contains('Marker p1')));
      expect(packets, isNot(contains('Marker p2')));
      // Repeated toss is deduplicated by origin+destination+MSGID, including ordinary transit.
      await File('${root.path}/protinbound/repeat.pkt').writeAsBytes(incoming);
      await cycle();
      expect((await p2.listMessages(page(other.id))).total.toInt(), 2);
      final personalBytes = <String, List<int>>{};
      await for (final entry in Directory('${root.path}/points').list()) {
        if (entry is File) {
          personalBytes[entry.path] = await entry.readAsBytes();
        }
      }
      await stop();
      (config['point_mail'] as Map<String, dynamic>)['points'] = [points[1]];
      await start();
      await expectLater(
        laptop.getConference(wire.GetConferenceRequest(conferenceId: firstId)),
        throwsA(isA<ApiException>()),
      );
      for (final entry in personalBytes.entries) {
        expect(await File(entry.key).readAsBytes(), entry.value);
      }
      await stop();
      (config['point_mail'] as Map<String, dynamic>)['points'] = points;
      await start();
      expect((await laptop.listMessages(page(firstId))).total.toInt(), 27);
      await stop();
      await hptConfig.writeAsString(
        hptText.toString().replaceFirst(
          'Password p1-fixture',
          'Password p1-new',
        ),
      );
      await start();
      await expectLater(laptop.restoreSession(), throwsA(isA<ApiException>()));
      await expectLater(login(laptop, 1), throwsA(isA<ApiException>()));
      await login(laptop, 1, password: 'p1-new');
      expect(
        (await laptop.createMessage(request)).message.messageId,
        sent.message.messageId,
      );
      expect(
        (await laptop.getConference(
          wire.GetConferenceRequest(conferenceId: firstId),
        )).lastOpenedMessageId,
        ownSent.message.messageId,
      );

      expect((await laptop.listMessages(page(firstId))).total.toInt(), 27);
      // Large synthetic echo: bulk read must not decode bodies or touch JAM/JLR.
      await stop();
      const total = 100000;
      final baseHeader = ByteData(1024)
        ..setUint32(0, 0x004d414a, Endian.little)
        ..setUint32(4, 123, Endian.little)
        ..setUint32(12, total, Endian.little)
        ..setUint32(16, 0xffffffff, Endian.little)
        ..setUint32(20, 1, Endian.little);
      final headers = BytesBuilder()..add(baseHeader.buffer.asUint8List());
      final index = BytesBuilder();
      for (var n = 1; n <= total; n++) {
        final header = ByteData(76)
          ..setUint32(0, 0x004d414a, Endian.little)
          ..setUint16(4, 1, Endian.little)
          ..setUint32(48, n, Endian.little)
          ..setUint32(52, 0x00400000, Endian.little);
        headers.add(header.buffer.asUint8List());
        final record = ByteData(8)
          ..setUint32(0, 0xffffffff, Endian.little)
          ..setUint32(4, 1024 + (n - 1) * 76, Endian.little);
        index.add(record.buffer.asUint8List());
      }
      await File('${root.path}/ECHO.jhr').writeAsBytes(headers.takeBytes());
      await File('${root.path}/ECHO.jdx').writeAsBytes(index.takeBytes());
      await File('${root.path}/ECHO.jdt').writeAsBytes([]);
      await File('${root.path}/ECHO.jlr').writeAsBytes([1, 2, 3, 4]);
      final original = <String, List<int>>{};
      for (final ext in ['jhr', 'jdx', 'jdt', 'jlr']) {
        original[ext] = await File('${root.path}/ECHO.$ext').readAsBytes();
      }
      await start();
      await login(phone, 1, password: 'p1-new');
      final bulk = wire.MarkConferenceReadRequest(
        conferenceId: 'ECHO',
        operationId: 'large-bulk',
      );
      final watch = Stopwatch()..start();
      final marked = await laptop.markConferenceRead(bulk);
      watch.stop();
      debugPrint('Bulk echo 100000 messages: ${watch.elapsedMilliseconds} ms');
      expect(marked.snapshotCount.toInt(), total);
      expect(marked.markedCount.toInt(), total);
      for (final ext in original.keys) {
        expect(
          await File('${root.path}/ECHO.$ext').readAsBytes(),
          original[ext],
        );
      }
      final echoRef = wire.GetConferenceRequest(conferenceId: 'ECHO');
      expect((await phone.getConference(echoRef)).unreadCount.toInt(), 0);
      expect((await p2.getConference(echoRef)).unreadCount.toInt(), total);
      await laptop.createMessage(
        wire.CreateMessageRequest(
          conferenceId: 'ECHO',
          operationId: 'new-after-bulk',
          subject: 'new arrival',
          body: 'Not part of the earlier snapshot',
          toName: 'All',
        ),
      );
      await stop();
      await start();
      final replay = await phone.markConferenceRead(bulk);
      expect(replay.writeToBuffer(), marked.writeToBuffer());
      expect((await laptop.getConference(echoRef)).unreadCount.toInt(), 1);
    },
    skip: binary == null || hpt == null
        ? 'Set FFIDO_E2E_BACKEND and FFIDO_TEST_HPT for isolated real transport check'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
