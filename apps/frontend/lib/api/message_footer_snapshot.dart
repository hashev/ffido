import 'api_transport.dart';
import 'api_exceptions.dart';
import 'generated/ffido/v1/ffido.pb.dart' as wire;
import 'message_footer_preferences_stub.dart'
    if (dart.library.ui) 'message_footer_preferences_flutter.dart'
    as preferences;

/// Only the authenticated server session can advertise support for this extension.
abstract interface class MessageFooterSupport {
  bool get supportsMessageFooter;
}

/// Freeze the footer with the operation, including absence on legacy servers.
/// Session changes discard all snapshots; failed preflight can be retried after reset.
class MessageFooterSnapshots {
  final ApiTransport api;
  final Map<String, Future<wire.MessageFooter?>> _operations = {};
  int _epoch = -1;
  MessageFooterSnapshots(this.api);
  Future<wire.MessageFooter?> capture(
    String operation, {
    bool enabled = true,
  }) async {
    if (!enabled || api is! MessageFooterSupport) return null;
    if (_epoch != api.epoch) {
      _operations.clear();
      _epoch = api.epoch;
    }
    final future = _operations.putIfAbsent(operation, () async {
      final settings = await preferences.loadFooterPreferences();
      if (settings == null) return null;
      if (!(api as MessageFooterSupport).supportsMessageFooter) {
        if (settings.hasOverrides) {
          throw const ValidationException(
            message: 'Сервер не поддерживает Tagline/Origin. Обновите сервер или сбросьте оформление; черновик сохранён.',
          );
        }
        return null;
      }
      return settings.footer;
    });
    try {
      return (await future)?.deepCopy();
    } catch (_) {
      if (identical(_operations[operation], future)) {
        _operations.remove(operation);
      }
      rethrow;
    }
  }
}
