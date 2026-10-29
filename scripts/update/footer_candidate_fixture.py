"""Local signed candidate transport for isolated footer upgrade acceptance.

Only the copied updater accepts the loopback registry and temporary public key.
Production trust/allowlists and already-published manifests remain unchanged.
"""
import base64
import json
from pathlib import Path
import re
import time
import urllib.request

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

ROOT = Path(__file__).resolve().parents[2]


def prepare(work, run, registry, number):
    run(['docker', 'run', '-d', '--name', registry, '-p', f'127.0.0.1:{number}:5000',
         '--tmpfs', '/var/lib/registry', 'registry:3.0.0'])
    for _ in range(30):
        try:
            urllib.request.urlopen(f'http://127.0.0.1:{number}/v2/', timeout=2).close()
            break
        except OSError: time.sleep(1)
    else: raise RuntimeError('Local registry did not become ready')
    repository = f'127.0.0.1:{number}/hashev/ffido'
    image = 'docker.io/hashev/ffido:1.0.7'
    build = json.loads(run(['docker', 'run', '--rm', '--entrypoint', 'cat', image, '/opt/ffido/BUILD.json']))
    # The existing 1.0.7 binary already supports schemas 9 and 10. Only metadata
    # differs in this private candidate; this is not a new published release.
    import sys
    sys.path.insert(0, str(ROOT/'scripts/release'))
    from update_metadata import COMPATIBILITY
    build['compatibility'] = dict(COMPATIBILITY)
    (work/'candidate-BUILD.json').write_text(json.dumps(build))
    dockerfile = work/'Dockerfile.candidate'
    dockerfile.write_text(f'FROM {image}\nCOPY candidate-BUILD.json /opt/ffido/BUILD.json\n')
    ref = repository+':candidate'
    run(['docker', 'build', '--platform', 'linux/amd64', '-f', dockerfile, '-t', ref, work])
    run(['docker', 'push', ref]); run(['docker', 'pull', ref])
    info = json.loads(run(['docker', 'image', 'inspect', ref]))[0]
    digest = next(v.split('@')[1] for v in info['RepoDigests'] if v.startswith(repository+'@'))
    shadow = work/'updater-fixture'; shadow.mkdir()
    for name in ['common.py', 'discovery.py', 'server.py', 'ffido-docker-update.py']:
        source = (ROOT/'scripts/update'/name).read_text()
        source = source.replace('(?:docker.io/)?hashev/ffido', re.escape(repository)).replace('docker.io/hashev/ffido', repository)
        (shadow/name).write_text(source)
    key = Ed25519PrivateKey.generate()
    (shadow/'public_keys.json').write_text(json.dumps({'qa': base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()}))
    package = {**build, 'id': 'server-linux-x86_64', 'component': 'server',
               'platform': {'os': 'linux', 'architecture': 'x86_64'},
               'min_os': {'version': '24.04', 'distribution': 'ubuntu'},
               'file': 'qa.tar.gz', 'size': 1, 'sha256': '0'*64}
    manifest = {'schema_version': 1, 'identity': {k: build[k] for k in ['tag', 'version', 'sha', 'stable', 'build_number']},
                'channel': 'stable', 'update_sequence': build['build_number'],
                'compatibility': build['compatibility'], 'packages': [package],
                'container': {'image': repository, 'digest': digest, 'sha': build['sha'],
                              'release_tag': build['tag'], 'version': build['version'], 'tag': build['tag'][1:]}}
    raw = json.dumps(manifest).encode()
    (shadow/'manifest.json').write_bytes(raw)
    (shadow/'manifest.sig').write_text(json.dumps({'algorithm': 'Ed25519', 'key_id': 'qa', 'signature': base64.b64encode(key.sign(raw)).decode()}))
    launcher = shadow/'launch.py'
    launcher.write_text('''import json,pathlib,runpy,discovery,common
root=pathlib.Path(__file__).parent
original=discovery.releases
def fetch(url,limit=common.MAX_METADATA):
 if url.startswith('https://api.github.com/'):
  tag=json.loads((root/'manifest.json').read_bytes())['identity']['tag']
  return json.dumps([{'draft':False,'prerelease':False,'tag_name':tag,'assets':[{'name':n,'browser_download_url':common.asset_url(tag,n),'size':1} for n in ['release-manifest.json','release-manifest.sig','qa.tar.gz']]}]).encode()
 return (root/('manifest.sig' if url.endswith('.sig') else 'manifest.json')).read_bytes()
discovery.releases=lambda *a,**kw:original(*a,**kw,fetch=fetch)
runpy.run_path(str(root/'ffido-docker-update.py'),run_name='__main__')
''')
    return launcher, repository+'@'+digest
