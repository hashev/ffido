"""Independent classic UUE fixture oracle; no FFIDO encoder/decoder is imported."""
import binascii
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
fixture = json.loads((root / 'golded-multipart.json').read_text())
raw = (root / 'golded-single.uue').read_bytes()
expected = bytes.fromhex(fixture['expected_hex'])
lines = raw.splitlines(keepends=True)
assert lines[0] == b'begin 644 all-bytes.bin\n'
assert lines[-2:] == [b'`\n', b'end\n']
assert b''.join(binascii.a2b_uu(line) for line in lines[1:-2]) == expected
assembled = []
for number, part in enumerate(fixture['parts'], 1):
    assert part['subject'].endswith(f'[{number}/3]')
    for line in part['body'].splitlines(keepends=True):
        if re.fullmatch(r'(?:sum -r/size [0-9]+/[0-9]+ section.*|section [0-9]+ end.*)\n', line, re.I):
            break
        assembled.append(line.encode())
assert b''.join(assembled) == raw
print('Classic single/multipart fixtures verified independently with binascii')
