"""Public release discovery, with authenticated manifests and bounded pagination."""
import json
import re
import common


def releases(installed, keys, channel, minimum_sequence=0, fetch=common.fetch):
    if channel not in {'stable', 'dev'}:
        raise ValueError('Unknown update channel')
    candidates = []
    stale = False
    for page in range(1, 21):
        raw = fetch(f'https://api.github.com/repos/hashev/ffido/releases?per_page=30&page={page}')
        rows = json.loads(raw)
        if not isinstance(rows, list):
            raise ValueError('Invalid GitHub release list')
        for row in rows:
            if row.get('draft') is not False or channel == 'stable' and row.get('prerelease') is not False:
                continue
            assets = {asset['name']: asset for asset in row.get('assets', [])}
            if not {'release-manifest.json', 'release-manifest.sig'} <= assets.keys():
                continue
            tag = row.get('tag_name', '')
            match = re.fullmatch(r'v(\d+\.\d+\.\d+)(?:-dev\.(\d+)\.([0-9a-f]{12}))?', tag)
            if match is None: continue
            # Historical signatures may use retired keys. Only candidates newer
            # by tag require authentication; the signed identity is still checked.
            advertised = {'version': match[1], 'tag': tag, 'stable': match[2] is None,
                          'build_number': int(match[2] or 1), 'sha': (match[3]+'0'*28) if match[3] else '0'*40}
            if not common.newer(advertised, installed, channel): continue
            def asset(name, limit):
                url = common.asset_url(tag, name)
                if assets[name].get('browser_download_url') != url:
                    raise ValueError('Release asset refers to another repository/version')
                return fetch(url, limit=limit)
            data = asset('release-manifest.json', common.MAX_METADATA)
            signature = asset('release-manifest.sig', common.MAX_SIGNATURE)
            manifest = common.verify_manifest(data, signature, keys)
            identity = manifest['identity']
            if identity['tag'] != tag or identity['stable'] == row['prerelease']:
                raise ValueError('Release identity mismatch')
            if common.newer(identity, installed, channel):
                if manifest['update_sequence'] < minimum_sequence:
                    stale = True
                    continue
                for package in manifest['packages']:
                    remote = assets.get(package['file'], {})
                    if remote.get('browser_download_url') != common.asset_url(tag, package['file']) or remote.get('size') != package['size']:
                        raise ValueError('Published package differs from update manifest')
                candidates.append((manifest, data, signature))
        if len(rows) < 30:
            if not candidates and stale: raise ValueError('Stale update manifest')
            return sorted(candidates, key=lambda item: common.version_key(item[0]['identity']), reverse=True)
    raise ValueError('Release pagination limit exceeded; result is incomplete')
