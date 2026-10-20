import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart' as grpc;
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:fido/files/uue_file_types.dart';
import 'package:fido/repositories/uue_repository.dart';
import 'package:fido/models/uue.dart';

Future<void> main(List<String> args) async {
  final config =
      jsonDecode(await File(args[0]).readAsString()) as Map<String, dynamic>;
  final clients = <ApiClient>[];
  Future<ApiClient> login(int point) async {
    final api = ApiClient(
      endpoint: config['endpoint'],
      channelFactory: (uri) => grpc.ClientChannel(
        uri.host,
        port: uri.port,
        options: grpc.ChannelOptions(
          credentials: grpc.ChannelCredentials.secure(
            certificates: File(config['ca']).readAsBytesSync(),
            authority: 'localhost',
          ),
        ),
      ),
    );
    clients.add(api);
    await api.login(
      endpoint: config['endpoint'],
      name: 'UUE Point $point',
      address: '2:1/2.$point',
      password: 'fixture',
    );
    return api;
  }

  Future<String> box(ApiClient api) async => (await api.listConferences(
    wire.ListConferencesRequest(
      page: wire.PageRequest(limit: 100),
      sort: wire.ConferenceSort.CONFERENCE_SORT_NAME,
    ),
  )).conferences.singleWhere((c) => c.personalMailbox).id;
  try {
    final one = await login(1), two = await login(2);
    final first = await box(one), second = await box(two);
    final binary = await File('${config['root']}/binary.bin').readAsBytes(),
        image = await File('${config['root']}/image.bin').readAsBytes();
    if (args[1] == 'send') {
      for (final data in [
        (first, binary, 'uue-net', '2:1/2.2'),
        ('ECHO', image, 'uue-echo', ''),
      ]) {
        final sent = await UueRepository(one).send(
          UueDraft(
            conference: data.$1,
            operation: data.$3,
            subject: data.$3,
            body: 'Н синтетический текст',
            toName: 'Point2',
            toAddress: data.$4,
            file: SelectedUueFile('${data.$3}.bin', data.$2),
          ),
        );
        if (!sent.complete || sent.saved < 2) {
          throw StateError('Expected complete multipart ${data.$3}');
        }
      }
    } else {
      for (final data in [
        (one, 'ECHO', 'uue-echo', image),
        (one, first, 'uue-net', binary),
        (two, second, 'uue-net', binary),
        (two, second, 'uue-external', binary),
        (two, second, 'uue-legacy', binary),
        (two, second, 'uue-legacy-image', image),
      ]) {
        final repository = UueRepository(data.$1);
        final raw = await data.$1.searchUueParts(
          wire.SearchUuePartsRequest(conferenceId: data.$2, limit: 100),
        );
        final anchor = raw.parts.firstWhere(
          (p) => p.subject.startsWith('${data.$3} ['),
        );
        final found = await repository.findParts(UuePart.fromWire(anchor));
        final file = await repository.assemble(found.reversed.toList());
        if (data.$3.startsWith('uue-legacy') &&
            (file.verified || file.diagnostic.isEmpty)) {
          throw StateError('Legacy assembly must retain its mixing warning');
        }
        final decoded = await repository.download(file);
        if (base64Encode(decoded) != base64Encode(data.$4)) {
          throw StateError('Bytes differ ${data.$3}');
        }
        if (data.$2 == first) {
          try {
            await two.getUueChunk(
              wire.GetUueChunkRequest(attachmentId: file.id, maxBytes: 1),
            );
            throw StateError('Cross-point cache access');
          } on ApiException {
            // The other point must not receive this private cached file.
          }
        }
      }
    }
    stdout.writeln('PASS: UUE ${args[1]} on isolated authenticated TLS server');
  } finally {
    for (final client in clients) {
      await client.dispose();
    }
  }
}
