import 'generated/ffido/v1/ffido.pb.dart' as wire;
import 'message_footer.dart';

Future<({wire.MessageFooter footer, bool hasOverrides})?>
loadFooterPreferences() async {
  final settings = await MessageFooterSettings.load();
  return (footer: settings.snapshot(), hasOverrides: settings.hasOverrides);
}
