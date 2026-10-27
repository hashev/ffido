import 'dart:convert';
import 'dart:io';

import 'package:fido/api/api_client.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pb.dart' as wire;
import 'package:grpc/grpc.dart' as grpc;

Future<void> main() async {
  final input = jsonDecode(
    await stdin.transform(utf8.decoder).join(),
  ) as Map<String, dynamic>;
  final client = ApiClient(
    endpoint: input['endpoint'] as String,
    channelFactory: (uri) => grpc.ClientChannel(
      uri.host,
      port: uri.port,
      options: grpc.ChannelOptions(
        credentials: grpc.ChannelCredentials.secure(
          certificates: File(input['ca'] as String).readAsBytesSync(),
        ),
      ),
    ),
  );
  try {
    final token =
        input['token'] as String? ??
        (await client.login(
          endpoint: client.endpoint.toString(),
          name: 'Alice',
          address: '2:1/2',
          password: input['password'] as String,
        )).sessionSecret;
    await client.setAuthToken(token);
    final request = wire.CreateCrosspostRequest(
      message: wire.CreateMessageRequest(
        conferenceId: 'RU.ONE',
        operationId: 'native-crosspost',
        toName: 'All',
        subject: 'Crosspost',
        body: 'Text',
      ),
      additionalConferenceIds: ['RU.THREE', 'RU.TWO'],
    );
    final result = await client.createCrosspost(request);
    if (!result.complete ||
        result.saved.length != 3 ||
        result.saved.map((c) => c.ftnMessageId).toSet().length != 3) {
      throw StateError('Incomplete crosspost or duplicate FTN identities');
    }
    for (final copy in result.saved) {
      final detail = await client.getMessage(copy.message);
      if (!detail.body.startsWith(
        '* Originally in RU.ONE\n* Crossposted in RU.THREE\n* Crossposted in RU.TWO\n\nText',
      )) {
        throw StateError('Invalid GoldED header');
      }
    }
    if (input['copies'] != null &&
        jsonEncode(input['copies']) != jsonEncode(result.toProto3Json())) {
      throw StateError('Retry changed copy references');
    }
    stdout.writeln(
      jsonEncode({'token': token, 'copies': result.toProto3Json()}),
    );
  } finally {
    await client.dispose();
  }
}
