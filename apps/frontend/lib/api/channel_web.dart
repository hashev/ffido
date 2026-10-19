import 'package:grpc/grpc_web.dart' as grpc;
import 'package:grpc/service_api.dart' as rpc;

const defaultEndpoint = String.fromEnvironment(
  'FFIDO_ENDPOINT',
  defaultValue: 'https://localhost:8443',
);
rpc.ClientChannel createChannel(Uri endpoint) =>
    grpc.GrpcWebClientChannel.xhr(endpoint);
