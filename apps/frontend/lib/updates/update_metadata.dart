import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const updateMetadataLimit = 2 * 1024 * 1024;
const updatePackageLimit = 2 * 1024 * 1024 * 1024;

Map<String, dynamic> updateObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Некорректные сведения об обновлении');
  }
  return value;
}

int updateInteger(
  Object? value, {
  int minimum = 0,
  int maximum = 9007199254740991,
}) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException('Некорректное число в обновлении');
  }
  return value;
}

int compareParts(List<int> a, List<int> b) {
  for (var i = 0; i < a.length || i < b.length; ++i) {
    final difference = (i < a.length ? a[i] : 0).compareTo(
      i < b.length ? b[i] : 0,
    );
    if (difference != 0) return difference;
  }
  return 0;
}

class UpdateIdentity {
  UpdateIdentity(this.json, {bool local = false}) {
    final version = json['version'];
    if (version is! String ||
        !RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
            .hasMatch(version) ||
        json['sha'] is! String ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(json['sha'] as String) ||
        json['stable'] is! bool) {
      throw const FormatException('Некорректная версия обновления');
    }
    updateInteger(json['build_number'], minimum: 1, maximum: 1999999999);
    final expected =
        'v$version${stable ? '' : '-dev.$buildNumber.${(json['sha'] as String).substring(0, 12)}'}';
    if (json['tag'] != expected && !(local && isLocal)) {
      throw const FormatException('Версия не соответствует тегу выпуска');
    }
  }
  final Map<String, dynamic> json;
  String get version => json['version'] as String;
  String get tag => json['tag'] as String;
  bool get stable => json['stable'] as bool;
  int get buildNumber => json['build_number'] as int;
  bool get isLocal => (json['tag'] as String? ?? '').contains('-check.');
  List<int> get order => [
    ...version.split('.').map(int.parse),
    stable ? 1 : 0,
    stable ? 0 : buildNumber,
  ];
  bool newerThan(
    UpdateIdentity installed,
    String channel, {
    bool android = false,
  }) =>
      !installed.isLocal &&
      (channel == 'dev' || stable) &&
      compareParts(order, installed.order) > 0 &&
      (!android || buildNumber > installed.buildNumber);
}

Uri updateAssetUri(String tag, String file) {
  if (!RegExp(r'^v\d+\.\d+\.\d+(?:-dev\.\d+\.[0-9a-f]{12})?$').hasMatch(tag) ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$').hasMatch(file)) {
    throw const FormatException('Некорректное имя пакета');
  }
  return Uri.https('github.com', '/hashev/ffido/releases/download/$tag/$file');
}

void validateUpdateUri(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.hasFragment ||
      !{
        'github.com',
        'api.github.com',
        'release-assets.githubusercontent.com',
        'objects.githubusercontent.com',
      }.contains(uri.host)) {
    throw const FormatException('Недоверенный адрес обновления');
  }
  if ((uri.host == 'github.com' &&
          !uri.path.startsWith('/hashev/ffido/releases/')) ||
      (uri.host == 'api.github.com' &&
          !uri.path.startsWith('/repos/hashev/ffido/releases'))) {
    throw const FormatException('Другой репозиторий обновлений');
  }
}

class UpdatePlatform {
  const UpdatePlatform(
    this.os,
    this.architecture,
    this.version, {
    this.distribution,
    this.build = 0,
  });
  final String os, architecture;
  final List<int> version;
  final String? distribution;
  final int build;
  bool supports(UpdatePackage package) {
    final platform = updateObject(package.json['platform']);
    if (platform['os'] != os || platform['architecture'] != architecture) {
      return false;
    }
    final minimum = updateObject(package.json['min_os']);
    if (os == 'android') {
      return version.first >= updateInteger(minimum['api'], minimum: 24);
    }
    if (os == 'linux' && minimum['distribution'] != distribution) return false;
    final text = minimum['version'];
    if (text is! String || !RegExp(r'^\d+(?:\.\d+)*$').hasMatch(text)) {
      return false;
    }
    return compareParts(version, text.split('.').map(int.parse).toList()) >=
            0 &&
        (os != 'windows' ||
            build >= updateInteger(minimum['build'], minimum: 1));
  }
}

class UpdatePackage {
  UpdatePackage(this.json, UpdateIdentity identity) {
    for (final field in ['version', 'sha', 'tag', 'stable', 'build_number']) {
      if (json[field] != identity.json[field]) {
        throw const FormatException('Смешанные версии пакетов');
      }
    }
    final platform = updateObject(json['platform']);
    if (json['component'] != 'client' && json['component'] != 'server') {
      throw const FormatException('Неизвестный компонент');
    }
    if (json['id'] !=
        '${json['component']}-${platform['os']}-${platform['architecture']}') {
      throw const FormatException('Некорректная платформа');
    }
    updateObject(json['min_os']);
    updateInteger(json['size'], minimum: 1, maximum: updatePackageLimit);
    if (json['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(json['sha256'] as String)) {
      throw const FormatException('Некорректная контрольная сумма');
    }
    uri = updateAssetUri(identity.tag, json['file'] as String);
    if (platform['os'] == 'android' && json['signing'] != 'release') {
      throw const FormatException('Неподписанный APK');
    }
  }
  final Map<String, dynamic> json;
  late final Uri uri;
  String get id => json['id'] as String;
  String get file => json['file'] as String;
  int get size => json['size'] as int;
  String get sha256 => json['sha256'] as String;
}

class UpdateManifest {
  UpdateManifest._(this.json) {
    if (json['schema_version'] != 1) {
      throw const FormatException('Неизвестный формат обновлений');
    }
    identity = UpdateIdentity(updateObject(json['identity']));
    sequence = updateInteger(json['update_sequence'], minimum: 1);
    if (sequence != identity.buildNumber ||
        json['channel'] != (identity.stable ? 'stable' : 'dev')) {
      throw const FormatException('Несогласованные сведения выпуска');
    }
    final compatibility = updateObject(json['compatibility']);
    for (final prefix in [
      'client_protocol',
      'server_protocol',
      'state_schema',
    ]) {
      if (updateInteger(compatibility['${prefix}_min'], minimum: 1) >
          updateInteger(compatibility['${prefix}_max'], minimum: 1)) {
        throw const FormatException('Некорректный диапазон совместимости');
      }
    }
    updateInteger(compatibility['protocol_major'], minimum: 1);
    updateInteger(compatibility['config_format'], minimum: 1);
    if (compatibility['jam_format'] is! String) {
      throw const FormatException('Неизвестный формат JAM');
    }
    final rows = json['packages'];
    if (rows is! List || rows.isEmpty || rows.length > 32) {
      throw const FormatException('Некорректный список пакетов');
    }
    packages = rows
        .map((row) => UpdatePackage(updateObject(row), identity))
        .toList();
    if (packages.map((row) => row.id).toSet().length != packages.length ||
        packages.map((row) => row.file).toSet().length != packages.length) {
      throw const FormatException('Повтор пакета');
    }
    for (final package in packages) {
      if (jsonEncode(package.json['compatibility']) !=
          jsonEncode(compatibility)) {
        throw const FormatException('Несогласованная совместимость пакета');
      }
    }
  }
  final Map<String, dynamic> json;
  late final UpdateIdentity identity;
  late final int sequence;
  late final List<UpdatePackage> packages;
  static Future<UpdateManifest> verify(
    Uint8List bytes,
    Uint8List signatureBytes,
    Map<String, dynamic> keys, {
    int minimumSequence = 0,
  }) async {
    if (bytes.length > updateMetadataLimit || signatureBytes.length > 4096) {
      throw const FormatException('Слишком большой манифест');
    }
    final envelope = updateObject(jsonDecode(utf8.decode(signatureBytes)));
    final key = keys[envelope['key_id']];
    if (envelope['algorithm'] != 'Ed25519' || key is! String) {
      throw const FormatException('Неизвестный ключ обновлений');
    }
    final valid = await Ed25519().verify(
      bytes,
      signature: Signature(
        base64Decode(envelope['signature'] as String),
        publicKey: SimplePublicKey(
          base64Decode(key),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) {
      throw const FormatException('Подпись обновления не прошла проверку');
    }
    final manifest = UpdateManifest._(
      updateObject(jsonDecode(utf8.decode(bytes))),
    );
    if (manifest.sequence < minimumSequence) {
      throw const FormatException('Получен устаревший манифест');
    }
    return manifest;
  }

  UpdatePackage? clientPackage(UpdatePlatform platform) {
    for (final package in packages) {
      if (package.json['component'] == 'client' && platform.supports(package)) {
        return package;
      }
    }
    return null;
  }
}
