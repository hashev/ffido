import 'dart:typed_data';

import 'package:fido/api/response_budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;

void main() {
  test(
    'native and web unary responses are bounded before protobuf parsing',
    () {
      var decoded = false;
      final interceptor = ResponseBudget();
      final method = grpc.ClientMethod<int, int>('/fixture', (_) => [], (
        bytes,
      ) {
        decoded = true;
        return bytes.length;
      });
      for (final size in [10 * 1024 * 1024, ResponseBudget.maxBytes]) {
        decoded = false;
        expect(
          () => interceptor.interceptUnary(method, 0, grpc.CallOptions(), (
            wrapped,
            request,
            options,
          ) {
            expect(wrapped.responseDeserializer(Uint8List(size)), size);
            throw StateError('parsed');
          }),
          throwsStateError,
        );
        expect(decoded, isTrue);
      }
      decoded = false;
      expect(
        () => interceptor.interceptUnary(method, 0, grpc.CallOptions(), (
          wrapped,
          request,
          options,
        ) {
          wrapped.responseDeserializer(Uint8List(ResponseBudget.maxBytes + 1));
          throw StateError('must not parse');
        }),
        throwsA(
          isA<grpc.GrpcError>().having(
            (error) => error.code,
            'code',
            grpc.StatusCode.resourceExhausted,
          ),
        ),
      );
      expect(decoded, isFalse);
    },
  );
}
