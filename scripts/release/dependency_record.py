#!/usr/bin/env python3
"""Record sources/notices for native dependencies and generate a CMake cache."""
import pathlib
import subprocess
import sys
import json
import os
import platform
work = pathlib.Path(sys.argv[1]).resolve()
prefix = work/'prefix'
legal = prefix/'share/ffido/legal'
legal.mkdir(parents=True, exist_ok=True)
versions = {}
for name in ('abseil', 'protobuf', 'grpc', 'huskylib', 'smapi', 'fidoconf', 'areafix', 'hpt', 'grpc/third_party/grpc-proto'):
    source = work/name
    name = name.replace('/', '-')
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    versions[name] = revision
    with (legal/f'{name}-{revision}.tar.gz').open('wb') as out:
        subprocess.run(['git', '-C', str(source), 'archive', '--format=tar.gz', 'HEAD'], stdout=out, check=True)
    for filename in ('LICENSE', 'COPYING', 'NOTICE', 'LICENSE.txt'):
        if (source/filename).is_file():
            (legal/f'{name}-{filename}').write_bytes((source/filename).read_bytes())
(legal/'revisions.json').write_text(json.dumps(versions, indent=2)+'\n')
values = {'CMAKE_PREFIX_PATH': prefix, 'Protobuf_DIR': prefix/'lib/cmake/protobuf',
          'gRPC_DIR': prefix/'lib/cmake/grpc', 'absl_DIR': prefix/'lib/cmake/absl',
          'utf8_range_DIR': prefix/'lib/cmake/utf8_range', 'FFIDO_HUSKY_ROOT': prefix,
          'FFIDO_FIDOCONFIG_INCLUDE': prefix/'include',
          'FFIDO_SMAPI_INCLUDE': prefix/'include',
          'FFIDO_FIDOCONFIG_SOURCE': work/'fidoconf',
          'FFIDO_SMAPI_VERSION_INCLUDE': work/'smapi/smapi'}
if platform.system() == 'Darwin':
    values['CMAKE_OSX_DEPLOYMENT_TARGET'] = os.environ.get('MACOSX_DEPLOYMENT_TARGET', platform.mac_ver()[0])
for key, lib in [('FFIDO_FIDOCONFIG_LIBRARY', 'fidoconfig'),
                 ('FFIDO_HUSKY_LIBRARY', 'husky'), ('FFIDO_SMAPI_LIBRARY', 'smapi')]:
    values[key] = prefix/f'lib/lib{lib}.a'
(prefix/'ffido-cache.cmake').write_text('\n'.join(
    f'set({key} [[{value}]] CACHE STRING "Release dependency" FORCE)' for key, value in values.items())+'\n')
