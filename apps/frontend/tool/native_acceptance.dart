import 'dart:convert';
import 'dart:io';
import 'package:grpc/grpc.dart' as grpc;
import 'package:fido/api/api_client.dart';
import 'package:fido/api/generated/ffido/v1/ffido.pbgrpc.dart' as wire;
import 'acceptance_flow.dart';

Future<void> main() async {
  final input =
      jsonDecode(await stdin.transform(utf8.decoder).join())
          as Map<String, dynamic>;
  grpc.ClientChannel createChannel(Uri uri) => grpc.ClientChannel(
    uri.host,
    port: uri.port,
    options: grpc.ChannelOptions(
      credentials: grpc.ChannelCredentials.secure(
        certificates: File(input['ca'] as String).readAsBytesSync(),
      ),
    ),
  );
  // No credentials in this probe: retain transport diagnostics before API error mapping.
  final probe = createChannel(Uri.parse(input['endpoint'] as String));
  try {
    await wire.FfidoClient(probe).listConferences(
      wire.ListConferencesRequest(),
      options: grpc.CallOptions(timeout: const Duration(seconds: 15)),
    );
    throw StateError('Unauthenticated TLS probe unexpectedly succeeded');
  } on grpc.GrpcError catch (error) {
    if (error.code != grpc.StatusCode.unauthenticated) {
      throw StateError('TLS gRPC probe: ${error.code}: ${error.message}');
    }
    stdout.writeln(
      'PASS: TLS gRPC transport and unauthenticated access denial',
    );
  } finally {
    await probe.terminate();
  }
  final client = ApiClient(
    endpoint: input['endpoint'] as String,
    channelFactory: createChannel,
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
