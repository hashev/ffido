import '../platform/desktop_profile.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_host_stub.dart'
    if (dart.library.io) 'update_host_io.dart'
    as host;
import 'update_metadata.dart';
import 'android_install_result.dart';
import 'update_service.dart';

enum UpdatePhase { idle, checking, available, downloading, installing, error }

class UpdateController extends ChangeNotifier {
  UpdateController({this.service, this.preferences, this._installer});
  static const native = MethodChannel('ffido/updates');
  UpdateService? service;
  SharedPreferences? preferences;
  final Future<void> Function(AvailableUpdate, void Function(double))?
  _installer;
  final Map<Object, bool Function()> _guards = {};
  bool _started = false,
      deferred = false,
      _cancelRequested = false,
      startupFailure = false;
  String channel = 'stable', message = '';
  double progress = 0;
  UpdatePhase phase = UpdatePhase.idle;
  AvailableUpdate? available;
  DateTime? lastCheck;
  AndroidInstallResult? installResult;
  Map<String, Object?> _installDiagnostic = {};
  bool get isAndroid => service?.platform.os == 'android';

  String get diagnosticSummary => const JsonEncoder.withIndent('  ').convert({
    'installed': service?.installed.tag,
    'installed_build': service?.installed.buildNumber,
    'channel': channel,
    ..._installDiagnostic,
    if (installResult != null) 'outcome': installResult!.outcome,
    if (installResult?.status != null) 'android_status': installResult!.status,
  });

  Future<void> _rememberInstall(AvailableUpdate update) async {
    // Derive the public URL from the verified release, never from an error or redirect.
    _installDiagnostic = {
      'target': update.manifest.identity.tag,
      'target_build': update.manifest.identity.buildNumber,
      'sha256': update.package.sha256,
      'source': updateAssetUri(
        update.manifest.identity.tag,
        update.package.file,
      ).toString(),
    };
    installResult = null;
    await preferences?.setString(
      'ffido_android_diagnostic_v1',
      jsonEncode(_installDiagnostic),
    );
  }

  void _applyInstallResult(Object? value) {
    final result = AndroidInstallResult.parse(value);
    installResult = result;
    phase = switch (result.outcome) {
      'pending' => UpdatePhase.installing,
      'success' || 'cancelled' || 'permission_denied' => UpdatePhase.available,
      _ => UpdatePhase.error,
    };
    message = result.message;
    startupFailure = result.outcome != 'success' && available == null;
    notifyListeners();
  }

  Future<void> resume() async {
    if (phase == UpdatePhase.downloading || phase == UpdatePhase.checking) {
      return;
    }
    if (isAndroid) {
      try {
        final value = await native.invokeMapMethod<String, dynamic>('recover');
        if (value != null) _applyInstallResult(value);
      } on PlatformException {
        // No verdict is inferred when the OS result is unavailable.
      }
    }
    await check();
  }

  bool get canExit => _guards.values.every((guard) => guard());
  bool get busy => {
    UpdatePhase.checking,
    UpdatePhase.downloading,
    UpdatePhase.installing,
  }.contains(phase);
  bool get showNotice => (available != null || startupFailure) && !deferred;
  void guardExit(Object owner, bool Function() guard) => _guards[owner] = guard;
  void removeExitGuard(Object owner) => _guards.remove(owner);
  Future<void> start() async {
    if (_started || kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
      return;
    }
    _started = true;
    try {
      await DesktopProfile.ready;
      preferences ??= await SharedPreferences.getInstance();
      if (service == null) {
        final installed = UpdateIdentity(
          updateObject(
            jsonDecode(
              await rootBundle.loadString('assets/updates/identity.json'),
            ),
          ),
          local: true,
        );
        final keys = updateObject(
          jsonDecode(
            await rootBundle.loadString('assets/updates/public_keys.json'),
          ),
        );
        final UpdatePlatform platform;
        if (defaultTargetPlatform == TargetPlatform.android) {
          final info = await native.invokeMapMethod<String, dynamic>('info');
          platform = UpdatePlatform('android', 'universal', [
            info?['sdk'] as int? ?? 0,
          ]);
        } else {
          platform = await host.currentUpdatePlatform();
        }
        Map<String, dynamic> cache;
        try {
          cache = updateObject(
            jsonDecode(preferences!.getString('ffido_update_cache_v1') ?? '{}'),
          );
        } catch (_) {
          cache = {};
        }
        service = UpdateService(
          fetch: host.fetchUpdate,
          keys: keys,
          installed: installed,
          platform: platform,
          cache: cache,
        );
      }
      channel =
          preferences!.getString('ffido_update_channel_v1') ??
          (service!.installed.stable ? 'stable' : 'dev');
      if (!{'stable', 'dev'}.contains(channel)) channel = 'stable';
      final retry = preferences!.getInt('ffido_update_retry_v1');
      if (retry != null) {
        service!.retryAt = DateTime.fromMillisecondsSinceEpoch(retry);
      }
      native.setMethodCallHandler((call) async {
        if (call.method == 'canExit') return canExit;
        if (call.method == 'installResult' && isAndroid) {
          _applyInstallResult(call.arguments);
          return null;
        }
        if (call.method == 'progress') {
          final fields = Map<String, dynamic>.from(call.arguments as Map);
          progress = (fields['progress'] as num?)?.toDouble() ?? 0;
          final installing = fields['stage'] == 'installing';
          phase = installing ? UpdatePhase.installing : UpdatePhase.downloading;
          message = installing
              ? 'Устанавливаем обновление…'
              : 'Загружаем и проверяем обновление…';
          notifyListeners();
        }
        return null;
      });
      if (isAndroid) {
        // Restore only validated public fields, never arbitrary persisted error text.
        try {
          final saved = updateObject(
            jsonDecode(
              preferences!.getString('ffido_android_diagnostic_v1') ?? '{}',
            ),
          );
          final tag = saved['target'];
          final hash = saved['sha256'];
          final source = saved['source'];
          if (tag is String &&
              RegExp(r'^v\d+\.\d+\.\d+(?:-dev\.\d+\.[0-9a-f]{12})?$')
                  .hasMatch(tag) &&
              hash is String &&
              RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) &&
              source is String &&
              saved['target_build'] is int) {
            final uri = Uri.parse(source);
            validateUpdateUri(uri);
            if (uri == updateAssetUri(tag, uri.pathSegments.last)) {
              _installDiagnostic = {
                'target': tag,
                'target_build': saved['target_build'] as int,
                'sha256': hash,
                'source': source,
              };
            }
          }
        } catch (_) {
          /* Ignore invalid local diagnostics. */
        }
      }
      final previousError = await host.consumeDesktopError();
      await check();
      if (isAndroid) {
        final recovered = await native.invokeMapMethod<String, dynamic>(
          'recover',
        );
        if (recovered != null) _applyInstallResult(recovered);
      }
      if (previousError != null) {
        startupFailure = true;
        phase = UpdatePhase.error;
        message = previousError;
        notifyListeners();
      }
    } catch (_) {
      message = 'Проверка обновлений недоступна в этой сборке';
      notifyListeners();
    }
  }

  Future<void> check({bool manual = false}) async {
    if (busy || service == null) return;
    if (!manual &&
        lastCheck != null &&
        DateTime.now().difference(lastCheck!) < const Duration(hours: 6)) {
      return;
    }
    if (service!.keys.isEmpty || service!.installed.isLocal) {
      message = 'Автоматические обновления не настроены в этой сборке';
      notifyListeners();
      return;
    }
    startupFailure = false;
    phase = UpdatePhase.checking;
    if (manual) message = 'Проверяем обновления…';
    notifyListeners();
    try {
      available = await service!.check(
        channel,
        minimumSequence: preferences?.getInt('ffido_update_sequence_v1') ?? 0,
      );
      lastCheck = DateTime.now();
      if (available != null) {
        final old = preferences?.getInt('ffido_update_sequence_v1') ?? 0;
        if (available!.manifest.sequence > old) {
          await preferences?.setInt(
            'ffido_update_sequence_v1',
            available!.manifest.sequence,
          );
        }
        phase = UpdatePhase.available;
        message = 'Доступна версия ${available!.manifest.identity.tag}';
      } else {
        phase = UpdatePhase.idle;
        message = 'Установлена актуальная версия';
      }
      await preferences?.setString(
        'ffido_update_cache_v1',
        jsonEncode(service!.cache),
      );
    } catch (error) {
      phase = UpdatePhase.error;
      message = manual ? 'Не удалось проверить обновление: $error' : '';
      lastCheck = DateTime.now();
      if (error is UpdateRateLimit) {
        await preferences?.setInt(
          'ffido_update_retry_v1',
          error.retryAt.millisecondsSinceEpoch,
        );
      }
    }
    notifyListeners();
  }

  Future<void> setChannel(String value) async {
    if (busy || !{'stable', 'dev'}.contains(value)) return;
    channel = value;
    available = null;
    deferred = false;
    await preferences?.setString('ffido_update_channel_v1', value);
    await check(manual: true);
  }

  void later() {
    deferred = true;
    notifyListeners();
  }

  Future<void> cancel() async {
    if (phase != UpdatePhase.downloading) return;
    _cancelRequested = true;
    message = 'Отменяем загрузку…';
    notifyListeners();
    if (service?.platform.os == 'macos') {
      await native.invokeMethod<void>('cancel');
    }
  }

  Future<void> install() async {
    final update = available;
    if (update == null || busy) return;
    if (!canExit) {
      message = 'Сначала завершите отправку или закройте редактор сообщения, сохранив текст. Обновление можно установить позже.';
      notifyListeners();
      return;
    }
    _cancelRequested = false;
    phase = UpdatePhase.downloading;
    progress = 0;
    deferred = false;
    message = 'Загружаем обновление…';
    notifyListeners();
    try {
      if (isAndroid) await _rememberInstall(update);
      void report(double value) {
        if (_cancelRequested) throw StateError('Загрузка отменена');
        progress = value;
        notifyListeners();
      }

      if (_installer != null) {
        await _installer(update, report);
      } else if (service!.platform.os == 'macos') {
        final feeds = update.manifest.json['macos_appcasts'] as List? ?? [];
        final feed = feeds
            .map(updateObject)
            .where((value) => value['package_id'] == update.package.id)
            .firstOrNull;
        if (feed == null) {
          throw const FormatException('Отсутствует macOS appcast');
        }
        final feedResponse = await host.fetchUpdate(
          updateAssetUri(update.manifest.identity.tag, feed['file'] as String),
        );
        if (feedResponse.status != 200 ||
            feedResponse.bytes.length != feed['size'] ||
            crypto.sha256.convert(feedResponse.bytes).toString() !=
                feed['sha256']) {
          throw const FormatException(
            'Appcast не соответствует подписанному манифесту',
          );
        }
        final envelope = updateObject(
          jsonDecode(utf8.decode(update.signatureBytes)),
        );
        await native.invokeMethod<void>('installMacOS', {
          'url': updateAssetUri(
            update.manifest.identity.tag,
            feed['file'] as String,
          ).toString(),
          'publicKey': service!.keys[envelope['key_id']],
          'version': update.manifest.identity.buildNumber.toString(),
          'packageURL': update.package.uri.toString(),
        });
      } else {
        String? stagingDirectory;
        if (service!.platform.os == 'android') {
          final info = await native.invokeMapMethod<String, dynamic>('info');
          stagingDirectory = info?['cacheDirectory'] as String?;
          if (stagingDirectory == null || stagingDirectory.isEmpty) {
            throw StateError('Не удалось получить закрытый кеш установщика');
          }
        }
        final path = await host.downloadUpdate(
          update,
          report,
          cancelled: () => _cancelRequested,
          stagingDirectory: stagingDirectory,
        );
        if (!canExit) {
          throw StateError(
            'Открыт редактор или выполняется отправка. Завершите работу и повторите установку.',
          );
        }
        phase = UpdatePhase.installing;
        message = 'Устанавливаем обновление…';
        notifyListeners();
        if (service!.platform.os == 'windows' ||
            service!.platform.os == 'linux') {
          await host.installDesktop(path);
          return;
        }
        final installed = await native.invokeMapMethod<String, dynamic>(
          'install',
          {'path': path, 'tag': update.manifest.identity.tag},
        );
        _applyInstallResult(installed);
        return;
      }
      phase = UpdatePhase.available;
      message = 'Установка передана системе. Подтвердите обновление, если появится запрос.';
    } catch (error) {
      phase = UpdatePhase.error;
      if (isAndroid && error is PlatformException && error.details is Map) {
        _applyInstallResult(error.details);
      } else {
        message = 'Не удалось установить обновление: $error';
      }
    }
    notifyListeners();
  }
}

final appUpdates = UpdateController();
