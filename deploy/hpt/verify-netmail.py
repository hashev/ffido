#!/usr/bin/env python3
"""Check actual HPT pack/toss with isolated JAM, no mailer and no network."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


def run(*args):
    result = subprocess.run(args, capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr).decode(errors='replace'))
    return result.stdout


def records(base):
    index = base.with_suffix('.jdx').read_bytes()
    header = base.with_suffix('.jhr').read_bytes()
    text = base.with_suffix('.jdt').read_bytes()
    rows = []
    for slot in range(len(index) // 8):
        at = struct.unpack_from('<I', index, slot * 8 + 4)[0]
        if at == 0xffffffff:
            continue
        fields = {}
        current = at + 76
        end = current + struct.unpack_from('<I', header, at + 8)[0]
        while current < end:
            low, high, size = struct.unpack_from('<HHI', header, current)
            current += 8
            assert high == 0 and current + size <= end
            fields.setdefault(low, []).append(header[current:current + size])
            current += size
        offset, size = struct.unpack_from('<II', header, at + 60)
        rows.append((fields, text[offset:offset + size]))
    return rows


def packets(root):
    rows, files = [], []
    for path in sorted((root / 'outbound').rglob('*')):
        if not path.is_file():
            continue
        data = path.read_bytes()
        if len(data) < 60 or struct.unpack_from('<H', data, 18)[0] != 2:
            continue
        files.append(path)
        at = 58
        while data[at:at + 2] != b'\0\0':
            assert struct.unpack_from('<H', data, at)[0] == 2
            at += 14
            fields = []
            for _ in range(5):
                end = data.index(0, at)
                fields.append(data[at:end])
                at = end + 1
            rows.append(fields)
        assert at + 2 == len(data)
    return files, rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worker', required=True)
    parser.add_argument('--control-worker', required=True)
    parser.add_argument('--tables', type=Path, required=True,
                        help='Directory containing outkoi8alt and outaltkoi8')
    parser.add_argument('--work', type=Path, required=True)
    options = parser.parse_args()
    options.work.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix='netmail-', dir=options.work)).resolve()
    for name in ('outkoi8alt', 'outaltkoi8'):
        shutil.copyfile(options.tables / name, root / name)

    def container(image, command, *args, enabled=True):
        return run('docker', 'run', '--rm', '--network', 'none',
                   '--user', f'{os.getuid()}:{os.getgid()}',
                   '-e', 'FFIDO_HPT_KOI8_CP866=' + ('1' if enabled else '0'),
                   '-v', str(root) + ':/fixture', '--entrypoint', command,
                   image, *args)

    def hpt(node, action, *, image=None, enabled=True):
        return container(image or options.worker, '/opt/ffido-hpt/bin/hpt',
                         '-c', '/fixture/' + node + '/hpt.cfg', action,
                         enabled=enabled)

    for name, address, peer in [('sender', '2:1/1', '2:1/2'),
                                 ('receiver', '2:1/2', '2:1/1')]:
        node = root / name
        node.mkdir()
        config = f'Name Netmail fixture\nSysop Test\nLocation Isolated\nAddress {address}\n'
        for key, folder in [('Inbound', 'inbound'), ('ProtInbound', 'protinbound'),
                            ('Outbound', 'outbound'), ('TempInbound', 'tmpin'),
                            ('TempOutbound', 'tmpout'), ('LogFileDir', 'logs'),
                            ('DupeHistoryDir', 'dupes'), ('NodelistDir', 'nodelist')]:
            (node / folder).mkdir()
            config += f'{key} /fixture/{name}/{folder}\n'
        (node / 'jam').mkdir()
        config += (f'MsgBaseDir /fixture/{name}/jam\nRecodeMsgBase on\n'
                   'OutTab /fixture/outkoi8alt\nInTab /fixture/outaltkoi8\n'
                   f'Link Peer\nAKA {peer}\nOurAKA {address}\nPassword fixture\n'
                   f'AllowEmptyPktPwd on\nRoute normal {peer} *\n')
        for area, kind in [('netmail', 'NetmailArea'), ('bad', 'BadArea'), ('dupe', 'DupeArea')]:
            config += f'{kind} {area} /fixture/{name}/jam/{area} -b JAM\n'
        (node / 'hpt.cfg').write_text(config)

    author, recipient = 'Иван Ёж', 'Мария Ёж'
    body = 'Проверка: Ёжик, ёлка, русский текст.\rYK> @CHRS: KOI8-R 2\r'
    subjects = ['Письмо Ёё', 'Ответ Ёё', 'Без метки Ёё', 'Две метки Ёё']
    for i, subject in enumerate(subjects):
        control = f'\1MSGID: 2:1/1 fixture{i}'
        if i != 2:
            control += '\1CHRS: KOI8-R 2'
        if i == 1:
            control += '\1REPLY: 2:1/1 fixture0'
        if i == 3:
            control += '\1chrs: KOI8-R 2'
        for key, value in [('author', author), ('recipient', recipient),
                           ('subject', subject), ('body', body), ('control', control)]:
            (root / key).write_bytes(value.encode('koi8-r'))
        container(options.worker, '/usr/local/bin/ffido-netmail-fixture',
                  '/fixture/sender/jam/netmail',
                  *('/fixture/' + key for key in ('author', 'recipient', 'subject', 'body', 'control')))
    before = records(root / 'sender/jam/netmail')
    assert len(before) == len(subjects)

    # A control proves both the previous bug and unchanged opt-out semantics.
    for name, image in [('old', options.control_worker), ('disabled', options.worker)]:
        shutil.copytree(root / 'sender', root / name)
        config = root / name / 'hpt.cfg'
        config.write_text(config.read_text().replace('/sender/', '/' + name + '/'))
        hpt(name, 'pack', image=image, enabled=name != 'disabled')
        _, broken = packets(root / name)
        assert len(broken) == len(subjects)
        assert b'\1CHRS: KOI8-R 2\r' in broken[0][4]
        assert body.encode('cp866') in broken[0][4]

    hpt('sender', 'pack')
    files, wire = packets(root / 'sender')
    assert len(wire) == len(subjects)
    for i, (_, to, sender, subject, text) in enumerate(wire):
        assert to == recipient.encode('cp866') and sender == author.encode('cp866')
        assert subject == subjects[i].encode('cp866')
        chrs = [line for line in text.split(b'\r') if line.lower().startswith(b'\1chrs:')]
        assert chrs == [b'\1CHRS: CP866 2'], chrs
        assert body.encode('cp866') in text
        assert b'\1MSGID: 2:1/1 fixture' + str(i).encode() in text
        if i == 1:
            assert b'\1REPLY: 2:1/1 fixture0\r' in text
    assert records(root / 'sender/jam/netmail') == before, 'Local payload or CHRS changed'
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
    hpt('sender', 'pack')
    assert {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in packets(root / 'sender')[0]} == hashes, 'Duplicate export'
    for i, path in enumerate(files):
        shutil.copyfile(path, root / 'receiver/protinbound' / f'{i}.pkt')
    hpt('receiver', 'toss')
    received = records(root / 'receiver/jam/netmail')
    assert len(received) == len(subjects)
    for i, (fields, text) in enumerate(received):
        assert fields[2] == [author.encode('koi8-r')]
        assert fields[3] == [recipient.encode('koi8-r')]
        assert fields[6] == [subjects[i].encode('koi8-r')]
        assert body.encode('koi8-r') in text
    report = dict(messages=len(subjects), packet_charset='CP866', chrs_exact=True,
                  received_koi8_matches=True, reply_preserved=True,
                  local_payload_unchanged=True, no_duplicate_export=True,
                  old_bug_reproduced=True, opt_out_preserved=True,
                  production_queues_not_mounted=True, network='none')
    (root / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(root=str(root), **report)))


if __name__ == '__main__':
    main()
