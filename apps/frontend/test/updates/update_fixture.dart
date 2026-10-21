import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:fido/updates/update_metadata.dart';
import 'package:fido/updates/update_service.dart';

Map<String, dynamic> identity(
  String version,
  int build, {
  bool stable = true,
}) => {
  'version': version,
  'build_number': build,
  'sha': 'a' * 40,
  'stable': stable,
  'tag': 'v$version${stable ? '' : '-dev.$build.aaaaaaaaaaaa'}',
};

class UpdateFixture {
  late Map<String, dynamic> keys, manifest, release;
  late Uint8List raw, sig;
  late AvailableUpdate available;
  final calls = <String>[];
  final etags = <String?>[];
  Future<void> initialize({
    String os = 'linux',
    String arch = 'x86_64',
    bool stable = true,
    String version = '2.0.0',
    int build = 1002,
  }) async {
    final key = await Ed25519().newKeyPairFromSeed(List.generate(32, (i) => i));
    final public = await key.extractPublicKey();
    keys = {'test': base64Encode(public.bytes)};
    final compat = {
      'protocol_major': 1,
      'client_protocol_min': 1,
      'client_protocol_max': 1,
      'server_protocol_min': 1,
      'server_protocol_max': 1,
      'state_schema_min': 9,
      'state_schema_max': 9,
      'config_format': 1,
      'jam_format': 'JAM-1',
    };
    final candidate = identity(version, build, stable: stable);
    final package = {
      ...candidate,
      'id': 'client-$os-$arch',
      'component': 'client',
      'platform': {'os': os, 'architecture': arch},
      'min_os': os == 'android'
          ? {'api': 24}
          : {'version': '24.04', 'distribution': 'ubuntu'},
      'size': 3,
      'file': 'client.tar.gz',
      'sha256': 'b' * 64,
      'compatibility': compat,
      'signing': 'release',
    };
    manifest = {
      'schema_version': 1,
      'identity': candidate,
      'update_sequence': build,
      'channel': stable ? 'stable' : 'dev',
      'compatibility': compat,
      'packages': [package],
    };
    raw = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    sig = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'key_id': 'test',
          'algorithm': 'Ed25519',
          'signature': base64Encode(
            (await Ed25519().sign(raw, keyPair: key)).bytes,
          ),
        }),
      ),
    );
    final verified = await UpdateManifest.verify(raw, sig, keys);
    available = AvailableUpdate(
      verified,
      verified.packages.single,
      raw,
      sig,
      'Описание версии',
    );
    release = {
      'draft': false,
      'prerelease': !stable,
      'tag_name': candidate['tag'],
      'body': 'Описание версии',
      'assets': [
        for (final name in [
          'release-manifest.json',
          'release-manifest.sig',
          'client.tar.gz',
        ])
          {
            'name': name,
            'size': 3,
            'browser_download_url': updateAssetUri(
              candidate['tag'] as String,
              name,
            ).toString(),
          },
      ],
    };
  }

  Future<UpdateResponse> fetch(
    Uri uri, {
    String? etag,
    int limit = updateMetadataLimit,
  }) async {
    calls.add(uri.toString());
    etags.add(etag);
    if (uri.host == 'api.github.com') {
      return UpdateResponse(
        200,
        Uint8List.fromList(utf8.encode(jsonEncode([release]))),
        {'etag': 'test-etag'},
      );
    }
    return UpdateResponse(200, uri.path.endsWith('.sig') ? sig : raw);
  }

  UpdateService service({
    UpdateFetch? fetcher,
    UpdatePlatform platform = const UpdatePlatform('linux', 'x86_64', [
      24,
      4,
    ], distribution: 'ubuntu'),
  }) => UpdateService(
    fetch: fetcher ?? fetch,
    keys: keys,
    installed: UpdateIdentity(identity('1.0.0', 1001)),
    platform: platform,
  );
}
