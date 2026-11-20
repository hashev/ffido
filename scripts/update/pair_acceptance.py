"""Isolated QA RPC fixture; refuses production endpoints and FTN addresses.

Small protobuf wire helpers are confined to this test fixture. Field numbers
come from contracts/ffido/v1/ffido.proto. Production clients use generated code.
"""
import argparse
import base64
import contextlib
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import time
import urllib.parse

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
import pair_probe


def varint(value):
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128); value >>= 7
    result.append(value)
    return bytes(result)


def field(number, value):
    if isinstance(value, int):
        return varint(number << 3)+varint(value)
    value = value.encode() if isinstance(value, str) else value
    return varint((number << 3) | 2)+varint(len(value))+value


def fields(data):
    offset, result = 0, {}
    def read():
        nonlocal offset
        value = shift = 0
        while offset < len(data) and shift < 70:
            byte = data[offset]; offset += 1
            value |= (byte & 127) << shift
            if byte < 128:
                return value
            shift += 7
        raise ValueError('Invalid fixture protobuf')
    while offset < len(data):
        key = read(); number, wire = key >> 3, key & 7
        if number == 0:
            raise ValueError('Invalid fixture protobuf field number')
        if wire == 0:
            value = read()
        else:
            size = read() if wire == 2 else {1: 8, 5: 4}.get(wire, -1)
            if size < 0 or offset+size > len(data):
                raise ValueError('Invalid fixture protobuf field')
            value, offset = data[offset:offset+size], offset+size
        result.setdefault(number, []).append(value)
    return result


def private_json(path, value):
    with Path(path).open('w') as output:
        os.fchmod(output.fileno(), 0o600)
        json.dump(value, output)


def state_hashes(database):
    tables = ('users', 'tokens', 'telegram_bindings', 'mailbox_bindings', 'read_status',
              'operations', 'uue_uploads', 'crosspost_groups')
    result = {}
    with contextlib.closing(sqlite3.connect(database.as_uri()+'?mode=ro', uri=True)) as db:
        aliases = {}
        if db.execute("select name from sqlite_master where name='restored_generations'").fetchone():
            aliases = dict(db.execute('select physical_generation,logical_generation from restored_generations'))
        for table in tables:
            cursor = db.execute('select * from '+table)
            names = [x[0] for x in cursor.description]
            rows = []
            for row in cursor:
                value = {}
                for name, item in zip(names, row):
                    if table == 'mailbox_bindings' and name == 'files':
                        continue  # Physical identities legitimately change on copy.
                    if 'generation' in name and isinstance(item, str):
                        item = aliases.get(item, item)
                    value[name] = item.hex() if isinstance(item, bytes) else item
                rows.append(hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest())
            result[table] = sorted(rows)
    return result


def proof(config):
    user = json.dumps({'id': 42, 'first_name': 'Isolated QA'}, separators=(',', ':'))
    values = {'auth_date': str(int(time.time())), 'query_id': 'pair-fixture', 'user': user}
    checked = str(config['bot_id'])+':WebAppData\n'+'\n'.join(k+'='+v for k, v in sorted(values.items()))
    key = Ed25519PrivateKey.from_private_bytes(bytes.fromhex(config['telegram_key']))
    values['signature'] = base64.urlsafe_b64encode(key.sign(checked.encode())).decode().rstrip('=')
    return urllib.parse.urlencode(values)


def run(config, mode):
    endpoint = urllib.parse.urlsplit(config['endpoint'])
    if endpoint.hostname not in {'localhost', '127.0.0.1', '::1'} or not config.get('isolated'):
        raise ValueError('QA fixture refuses non-loopback endpoints')
    root = Path(config['root'])
    if (root/'.ffido-isolated-pair-fixture').read_text() != config['isolation_id']:
        raise ValueError('Missing isolated fixture identity')
    state = Path(config['state'])
    def call(method, payload=b'', token=None, status=0):
        return pair_probe.call(config['endpoint'], config['ca'], config['origin'], method, payload, token, status)
    if mode not in {'seed-telegram', 'capture-state', 'verify-state'}:
        pair_probe.gateway(config['endpoint'], config['ca'], config['origin'])
    if mode in {'capture-state', 'verify-state'}:
        saved = json.loads(state.read_text())
        current = state_hashes(root/'metadata.db')
        if mode == 'capture-state':
            if any(not rows for rows in current.values()):
                raise ValueError('Receipt/session fixture must not be empty')
            saved['baseline'] = current
            private_json(state, saved)
        elif any(not set(rows) <= set(current[table]) for table, rows in saved['baseline'].items()):
            raise ValueError('Identity, mailbox or receipt state lost')
    elif mode == 'seed':
        tokens = [fields(call('Login', field(1, 'Point'+str(i))+field(2, '2:1/2.'+str(i))+
                              field(3, 'fixture'+str(i))))[1][0].decode() for i in (1, 2)]
        page = field(1, field(2, 100))+field(3, 1)
        catalogs = [fields(call('ListConferences', page, token)).get(1, []) for token in tokens]
        private_json(state.with_name('catalog.private.json'),
                     [{fields(x)[1][0].decode(): fields(x).get(2, [b''])[0].decode() for x in catalog}
                      for catalog in catalogs])
        areas = [{fields(x)[1][0].decode().upper(): fields(x)[1][0].decode() for x in catalog}
                 for catalog in catalogs]
        own = [next(value for value in catalog.values() if value not in set(areas[1-i].values()))
               for i, catalog in enumerate(areas)]
        message = field(1, areas[0]['QA.A'])+field(2, 'pair-crosspost')+field(3, 'All')+field(5, 'Isolated pair')+field(6, 'QA only')
        crosspost = field(1, message)+field(2, areas[0]['QA.B'])
        crossed = call('CreateCrosspost', crosspost, tokens[0])
        if fields(crossed).get(1) != [1] or len(fields(crossed).get(2, [])) != 2:
            raise ValueError('Crosspost fixture did not complete')
        reference = fields(fields(crossed)[2][0])[1][0]
        call('MarkRead', reference, tokens[0])
        data = b'isolated-pair-uue\x00\xff'
        upload = field(1, 'pair-uue')+field(2, 'pair.bin')+field(3, len(data))+field(4, hashlib.sha256(data).hexdigest())+field(6, data)
        call('UploadUueChunk', upload, tokens[0])
        commit = field(1, field(1, areas[0]['QA.A'])+field(2, 'pair-uue')+field(3, 'All')+field(5, 'QA UUE')+field(6, 'QA only'))
        committed = call('CommitUue', commit, tokens[0])
        private_json(state, {'tokens': tokens, 'own': own, 'crosspost': crosspost.hex(),
                             'crossed': crossed.hex(), 'commit': commit.hex(), 'committed': committed.hex(),
                             'reference': reference.hex()})
    elif mode == 'seed-telegram':
        # Test data construction while the fixture backend is stopped; never restore by SQL.
        saved = json.loads(state.read_text())
        with contextlib.closing(sqlite3.connect(root/'metadata.db')) as db, db:
            addresses = {x[0] for x in db.execute('select ftn_address from users')}
            if not addresses <= {'2:1/2.1', '2:1/2.2'}:
                raise ValueError('Foreign user in isolated fixture')
            rows = db.execute('select t.digest,t.user_id,t.fingerprint from tokens t join users u '
                              'on u.user_id=t.user_id where u.ftn_address=? and t.revoked=0',
                              ('2:1/2.1',)).fetchall()
            if len(rows) != 1:
                raise ValueError('Expected one source session for the isolated point')
            digest, user, fingerprint = rows[0]
            db.execute('insert into telegram_bindings(user_id,bot_id,telegram_user_id,fingerprint,revision) values(?,?,?,?,?)',
                       (user, config['bot_id'], 42, fingerprint, 'pair-telegram-revision'))
            db.execute('update tokens set telegram_revision=? where digest=?', ('pair-telegram-revision', digest))
    else:
        saved = json.loads(state.read_text())
        for token in saved['tokens']:
            call('RestoreSession', token=token)
        if fields(call('GetTelegramBinding', token=saved['tokens'][0])).get(1) != [1]:
            raise ValueError('Telegram binding lost')
        for i, token in enumerate(saved['tokens']):
            call('GetConference', field(1, saved['own'][i]), token)
            # Foreign point mailbox must remain unavailable.
            try:
                call('GetConference', field(1, saved['own'][1-i]), token)
            except pair_probe.GrpcError as error:
                if error.status not in {5, 7}:
                    raise
            else:
                raise ValueError('Foreign mailbox exposed')
        if mode == 'verify-target':
            token = fields(call('LoginWithTelegram', field(1, proof(config))+field(2, '2:1/2.1')))[1][0].decode()
            call('RestoreSession', token=token)
        if call('CreateCrosspost', bytes.fromhex(saved['crosspost']), saved['tokens'][0]).hex() != saved['crossed']:
            raise ValueError('Crosspost receipt changed on retry')
        if call('CommitUue', bytes.fromhex(saved['commit']), saved['tokens'][0]).hex() != saved['committed']:
            raise ValueError('UUE receipt changed on retry')
        # Only archive reads promise to preserve read_at and reading history.
        archived = fields(call('ReadArchiveMessage',
                               field(1, bytes.fromhex(saved['reference']))+field(3, 1024)+field(4, 1),
                               saved['tokens'][0]))
        detail = fields(archived[1][0])
        if detail.get(11) != [1]:
            raise ValueError('Read state lost')
    print('Isolated pair acceptance passed: '+mode)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['seed', 'seed-telegram', 'capture-state', 'verify-state',
                                        'verify-source', 'verify-target'])
    parser.add_argument('--fixture', type=Path, required=True)
    args = parser.parse_args()
    run(json.loads(args.fixture.read_text()), args.mode)
