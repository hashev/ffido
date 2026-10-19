import 'dart:js_interop';
import 'package:fido/api/api_client.dart';
import 'package:fido/api/api_exceptions.dart';
import 'acceptance_flow.dart';

@JS('ffidoEndpoint')
external JSString get endpoint;
@JS('ffidoPasswordA')
external JSString get passwordA;
@JS('ffidoPasswordB')
external JSString get passwordB;
@JS('ffidoRejectOrigin')
external JSBoolean get rejectOrigin;
@JS('ffidoHtmlResponse')
external JSBoolean get htmlResponse;
@JS('ffidoReport')
external void report(JSString value);
Future<void> main() async {
  final client = ApiClient(endpoint: endpoint.toDart, readAttempts: 1);
  try {
    if (htmlResponse.toDart) {
      await client.setAuthToken('a' * 64);
      try {
        await client.getProfile();
        throw StateError('HTML response was accepted');
      } on ApiException catch (error) {
        if (error.rpcName != 'GetProfile' ||
            error.toString().contains('<html>')) {
          throw StateError('Uncontrolled HTML diagnostic');
        }
        report(
          'PASS: HTML gateway response is a controlled named RPC error'.toJS,
        );
      }
    } else if (rejectOrigin.toDart) {
      await client.setAuthToken('a' * 64);
      try {
        await client.getProfile();
        throw StateError('Foreign origin was accepted');
      } catch (error) {
        if (error is StateError) rethrow;
        report('PASS: foreign origin denied'.toJS);
      }
    } else {
      final a = await client.login(
        endpoint: endpoint.toDart,
        name: 'Алексей',
        address: '2:1/2',
        password: passwordA.toDart,
      );
      final b = await client.login(
        endpoint: endpoint.toDart,
        name: 'Борис',
        address: '2:1/3',
        password: passwordB.toDart,
      );
      await acceptance(client, a.sessionSecret, b.sessionSecret, 'browser');
      report(
        'PASS: browser gRPC-Web Unicode Empty identity retry and trailers'.toJS,
      );
    }
  } catch (error) {
    report('FAIL: $error'.toJS);
  } finally {
    await client.dispose();
  }
}
