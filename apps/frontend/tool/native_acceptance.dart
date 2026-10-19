import 'dart:convert';
import 'dart:io';
import 'package:grpc/grpc.dart' as grpc;
import 'package:fido/api/api_client.dart';
import 'acceptance_flow.dart';

Future<void> main() async {
  final input =
      jsonDecode(await stdin.transform(utf8.decoder).join())
          as Map<String, dynamic>;
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
    final a = await client.login(
      endpoint: client.endpoint.toString(),
      name: 'Алексей',
      address: '2:1/2',
      password: input['passwordA'] as String,
    );
    final b = await client.login(
      endpoint: client.endpoint.toString(),
      name: 'Борис',
      address: '2:1/3',
      password: input['passwordB'] as String,
    );
    await acceptance(client, a.sessionSecret, b.sessionSecret, 'native');
    stdout.writeln('PASS: native Dart gRPC acceptance');
  } finally {
    await client.dispose();
  }
}
