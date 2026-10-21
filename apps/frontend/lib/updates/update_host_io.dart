import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'update_metadata.dart';
import 'update_service.dart';

Future<UpdatePlatform> currentUpdatePlatform() async {
  final os = Platform.operatingSystem;
  final arch =
      Abi.current() == Abi.macosArm64 || Abi.current() == Abi.linuxArm64
      ? 'arm64'
      : 'x86_64';
  final version = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?')
      .firstMatch(Platform.operatingSystemVersion);
  final numbers = version == null
      ? <int>[]
      : [for (var i = 1; i <= 3; ++i) int.parse(version.group(i) ?? '0')];
  if (os == 'android') {
    // Android reports its SDK through the installer bridge, not the Linux kernel.
    throw UnsupportedError(
      'Android SDK must be supplied by the native update bridge',
    );
  }
  if (os == 'linux') {
    final text = await File('/etc/os-release').readAsString();
    String? field(String name) => RegExp(
      '^$name="?([^"\n]+)',
      multiLine: true,
    ).firstMatch(text)?.group(1);
    final distribution = field('ID');
    final linuxVersion = field('VERSION_ID');
    return UpdatePlatform(
      os,
      arch,
      linuxVersion?.split('.').map(int.parse).toList() ?? [],
      distribution: distribution,
    );
  }
  if (os == 'windows') {
    final build =
        int.tryParse(
          RegExp(r'[Bb]uild (\d+)')
                  .firstMatch(Platform.operatingSystemVersion)
                  ?.group(1) ??
              '',
        ) ??
        0;
    return UpdatePlatform(os, arch, numbers, build: build);
  }
  return UpdatePlatform(os, arch, numbers);
}

Future<HttpClientResponse> _open(
  HttpClient client,
  Uri uri, {
  String? etag,
}) async {
  for (var redirects = 0; redirects <= 5; ++redirects) {
    validateUpdateUri(uri);
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 30));
    request.followRedirects = false;
    request.headers.set('User-Agent', 'FFIDO-Updater');
    if (etag != null) request.headers.set('If-None-Match', etag);
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
      return response;
    }
    final location = response.headers.value('location');
    await response.drain<void>().timeout(const Duration(seconds: 30));
    if (location == null) {
      throw const FormatException('Не указан адрес перенаправления');
    }
    uri = uri.resolve(location);
    etag = null;
  }
  throw const FormatException('Слишком много перенаправлений');
}

Future<UpdateResponse> fetchUpdate(
  Uri uri, {
  String? etag,
  int limit = updateMetadataLimit,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final response = await _open(client, uri, etag: etag);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > limit) {
        throw const FormatException('Слишком большой ответ обновления');
      }
      bytes.add(chunk);
    }
    return UpdateResponse(response.statusCode, bytes.takeBytes(), {
      for (final name in [
        'etag',
        'retry-after',
        'x-ratelimit-reset',
        'x-ratelimit-remaining',
      ])
        if (response.headers.value(name) != null)
          name: response.headers.value(name)!,
    });
  } finally {
    client.close(force: true);
  }
}

Future<String> downloadUpdate(
  AvailableUpdate update,
  void Function(double) progress, {
  bool Function()? cancelled,
  String? stagingDirectory,
}) async {
  final parent = stagingDirectory == null
      ? Directory.systemTemp
      : Directory(stagingDirectory);
  final directory = await parent.createTemp('ffido-update-');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final file = File('${directory.path}/${update.package.file}');
  IOSink? sink;
  try {
    final response = await _open(client, update.package.uri);
    if (response.statusCode != 200) {
      throw HttpException('Загрузка вернула HTTP ${response.statusCode}');
    }
    sink = file.openWrite();
    var size = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      if (cancelled?.call() == true) throw StateError('Загрузка отменена');
      size += chunk.length;
      if (size > update.package.size) {
        throw const FormatException('Пакет превышает заявленный размер');
      }
      sink.add(chunk);
      progress(size / update.package.size);
    }
    if (cancelled?.call() == true) throw StateError('Загрузка отменена');
    await sink.flush();
    await sink.close();
    sink = null;
    if (size != update.package.size ||
        (await sha256.bind(file.openRead()).first).toString() !=
            update.package.sha256) {
      throw const FormatException(
        'Пакет повреждён: контрольная сумма не совпала',
      );
    }
    await File('${directory.path}/release-manifest.json')
        .writeAsBytes(update.manifestBytes, flush: true);
    await File('${directory.path}/release-manifest.sig')
        .writeAsBytes(update.signatureBytes, flush: true);
    return file.path;
  } catch (_) {
    await sink?.close();
    await directory.delete(recursive: true);
    rethrow;
  } finally {
    client.close(force: true);
  }
}

RandomAccessFile? _desktopLease;
Future<void> acquireDesktopLease() async {
  if (!Platform.isWindows && !Platform.isLinux) return;
  final root = File(Platform.resolvedExecutable).parent;
  final name = root.uri.pathSegments.where((part) => part.isNotEmpty).last;
  final lock = File('${root.parent.path}/.$name-running.lock');
  try {
    if (!Platform.isWindows && ((await root.parent.stat()).mode & 0x12) != 0) {
      return; // Shared writable parents cannot safely own installation locks.
    }
    if (await FileSystemEntity.isLink(lock.path)) {
      throw const FileSystemException('Небезопасный lock');
    }
    _desktopLease = await lock.open(mode: FileMode.append);
    await _desktopLease!.setPosition(0);
    await _desktopLease!.lock(FileLock.shared);
  } on FileSystemException catch (error) {
    await _desktopLease?.close();
    if (![5, 13, 30].contains(error.osError?.errorCode)) rethrow;
    _desktopLease = null;
    // Read-only installations remain usable and require an operator to update.
  }
}

Future<void> installDesktop(String archive) async {
  final root = File(Platform.resolvedExecutable).parent;
  final name = Platform.isWindows ? 'ffido-updater.exe' : 'ffido-updater';
  final helper = File('${root.path}/$name');
  if (!await helper.exists()) {
    throw const FileSystemException('В этой сборке нет установщика');
  }
  if (_desktopLease == null) {
    throw const FileSystemException(
      'Перенесите FFIDO в личный каталог с правами записи и повторите обновление',
    );
  }
  await _desktopLease!.unlock();
  try {
    await _desktopLease!.lock(FileLock.exclusive);
  } on FileSystemException {
    await _desktopLease!.lock(FileLock.shared);
    throw const FileSystemException(
      'Закройте другие окна FFIDO и повторите обновление',
    );
  }
  await _desktopLease!.unlock();
  await _desktopLease!.lock(FileLock.shared);
  final work = await Directory.systemTemp.createTemp('ffido-installer-');
  final copied = await helper.copy('${work.path}/$name');
  if (!Platform.isWindows) {
    final mode = await Process.run('chmod', ['700', copied.path]);
    if (mode.exitCode != 0) {
      throw const FileSystemException('Не удалось подготовить установщик');
    }
  }
  final arguments = [
    '--root',
    root.path,
    '--package',
    archive,
    '--executable',
    File(Platform.resolvedExecutable).uri.pathSegments.last,
  ];
  final validation = await Process.run(copied.path, [
    ...arguments,
    '--preflight',
  ]).timeout(const Duration(seconds: 30));
  if (validation.exitCode != 0) {
    final detail = validation.stderr.toString().trim();
    final message = detail.contains('private installation parent')
        ? 'Перенесите FFIDO в личный каталог без общей записи и повторите обновление.'
        : detail.contains('updater is active')
        ? 'Другое окно уже выполняет обновление. Дождитесь его завершения.'
        : detail.contains('not writable') ||
              detail.contains('Permission denied')
        ? 'Нет прав на замену приложения. Перенесите FFIDO в доступный для записи каталог.'
        : detail.isEmpty
        ? 'Не удалось подготовить установку; проверьте права записи'
        : detail;
    throw FileSystemException(message);
  }
  await Process.start(copied.path, arguments, mode: ProcessStartMode.detached);
  exit(0);
}

Future<void> confirmDesktopStartup() async {
  if (!Platform.isWindows && !Platform.isLinux) return;
  final root = File(Platform.resolvedExecutable).parent;
  final probe = File('${root.path}/.ffido-launch-probe');
  if (await probe.exists()) {
    final token = await probe.readAsString();
    if (RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
      // Publish only after the writer has closed its Windows file handle.
      // The updater can then read and remove the complete marker immediately.
      final pending = File('${root.path}/.ffido-ready.tmp');
      await pending.writeAsString(token, flush: true);
      await pending.rename('${root.path}/.ffido-ready');
    }
  }
}

Future<String?> consumeDesktopError() async {
  if (!Platform.isWindows && !Platform.isLinux) return null;
  final root = File(Platform.resolvedExecutable).parent;
  final file = File('${root.path}/.ffido-update-error');
  try {
    if (await FileSystemEntity.isLink(file.path) ||
        !await file.exists() ||
        await file.length() > 8192) {
      return null;
    }
    final value = await file.readAsString();
    await file.delete();
    return value;
  } on FileSystemException {
    return null;
  }
}
