import 'package:grpc/grpc.dart' as grpc;
import 'package:grpc/service_api.dart' as rpc;

const defaultEndpoint = String.fromEnvironment(
  'FFIDO_ENDPOINT',
  defaultValue: 'https://localhost:8080',
);
rpc.ClientChannel createChannel(Uri endpoint) => grpc.ClientChannel(
  endpoint.host,
  port: endpoint.hasPort ? endpoint.port : 443,
  options: const grpc.ChannelOptions(
    credentials: grpc.ChannelCredentials.secure(),
  ),
);
