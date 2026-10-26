#!/usr/bin/env python3
"""Install the locked Android emulator/image archive, never an unversioned latest."""
import argparse
import hashlib
from pathlib import Path
import shutil
import tempfile
import time
import urllib.request
import zipfile
import xml.etree.ElementTree as ET

from dependency_lock import load


def extract(archive, destination):
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            target = destination/entry.filename
            if not target.resolve().is_relative_to(destination.resolve()) or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Unsafe SDK archive member')
        package.extractall(destination)
        for entry in package.infolist():
            mode = (entry.external_attr >> 16) & 0o777
            if mode:
                (destination/entry.filename).chmod(mode)


def revision(path):
    try:
        for line in (path/'source.properties').read_text().splitlines():
            if line.startswith('Pkg.Revision=') or line.startswith('Pkg.Revision ='):
                return line.split('=', 1)[1].strip()
    except FileNotFoundError:
        pass
    return None


def register_emulator(directory, version):
    # sdkmanager normally creates this metadata after extracting the archive.
    # Generic packages cannot be discovered from source.properties alone.
    root = ET.Element('common:repository', {
        'xmlns:common': 'http://schemas.android.com/repository/android/common/02',
        'xmlns:generic': 'http://schemas.android.com/repository/android/generic/02',
        'xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance'})
    package = ET.SubElement(root, 'localPackage', {'path': 'emulator', 'obsolete': 'false'})
    ET.SubElement(package, 'type-details', {'xsi:type': 'generic:genericDetailsType'})
    revision_element = ET.SubElement(package, 'revision')
    for name, value in zip(('major', 'minor', 'micro'), version.split('.')):
        ET.SubElement(revision_element, name).text = value
    ET.SubElement(package, 'display-name').text = 'Android Emulator'
    ET.ElementTree(root).write(directory/'package.xml', encoding='utf-8', xml_declaration=True)


def install(sdk, name, lock):
    item = lock['android'][name]
    if name == 'emulator':
        parent, directory = sdk, sdk/'emulator'
    else:
        parts = item['package'].split(';')
        parent = sdk/'system-images'/parts[1]/parts[2]
        directory = parent/parts[3]
    marker = directory/'.ffido-archive'
    if marker.is_file() and marker.read_text() == item['sha1'] and revision(directory) == item['revision']:
        if name == 'emulator':
            register_emulator(directory, item['revision'])
        print(f'Locked Android SDK hit: {name} revision {item["revision"]}')
        return
    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary)/'archive.zip'
        print(f'Downloading locked Android SDK: {name} revision {item["revision"]}', flush=True)
        started = progress = time.monotonic()
        downloaded = 0
        with urllib.request.urlopen(item['url'], timeout=60) as response, archive.open('wb') as out:
            while chunk := response.read(4*1024*1024):
                out.write(chunk)
                downloaded += len(chunk)
                now = time.monotonic()
                if now-started > 600:
                    raise TimeoutError('Locked Android SDK download exceeded 10 minutes')
                if now-progress >= 30:
                    print(f'Android SDK {name}: {downloaded/1024/1024:.0f} MiB in {now-started:.0f}s', flush=True)
                    progress = now
        with archive.open('rb') as source:
            actual = hashlib.file_digest(source, 'sha1').hexdigest()
        if actual != item['sha1']:
            raise ValueError('Android SDK archive checksum mismatch')
        staged = Path(temporary)/'staged'
        staged.mkdir()
        extract(archive, staged)
        source = staged/directory.name
        if revision(source) != item['revision']:
            raise ValueError('Android SDK archive revision mismatch')
        if directory.exists():
            shutil.rmtree(directory)
        parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, directory)
        marker.write_text(item['sha1'])
        if name == 'emulator':
            register_emulator(directory, item['revision'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sdk', type=Path)
    parser.add_argument('name', choices=['emulator', '24', '25', '35'])
    args = parser.parse_args()
    install(args.sdk.resolve(), args.name, load())
