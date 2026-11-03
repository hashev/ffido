import 'package:grpc/grpc_or_grpcweb.dart' show GrpcError;
import 'package:grpc/service_api.dart' as grpc;

/// Shared by native and web calls; reject oversized bytes before protobuf parsing.
class ResponseBudget extends grpc.ClientInterceptor {
  static const maxBytes = 32 * 1024 * 1024;

  @override
  grpc.ResponseFuture<R> interceptUnary<Q, R>(
    grpc.ClientMethod<Q, R> method,
    Q request,
    grpc.CallOptions options,
    grpc.ClientUnaryInvoker<Q, R> invoker,
  ) => invoker(
    grpc.ClientMethod<Q, R>(method.path, method.requestSerializer, (bytes) {
      if (bytes.length > maxBytes) {
        throw const GrpcError.resourceExhausted('Ответ превышает лимит 32 МиБ');
      }
      return method.responseDeserializer(bytes);
    }),
    request,
    options,
  );
}
