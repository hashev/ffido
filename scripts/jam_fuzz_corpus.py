#!/usr/bin/env python3
"""Create synthetic bounded JAM parser seeds in a build directory."""
import argparse
from pathlib import Path
import struct


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    base = struct.pack('<7I', 0x004d414a, 123, 0, 1, 0xffffffff, 1, 0) + bytes(996)
    message = struct.pack('<IHH17I', 0x004d414a, 1, 0, 0, 0, 0xffffffff, 0xffffffff,
                          0, 0, 0, 123, 123, 0, 1, 0, 0, 0, 5, 0xffffffff, 0)
    index = struct.pack('<II', 0xffffffff, 1024)

    def save(name, header, slots=index, text=b'hello'):
        (args.output / (name + '.bin')).write_bytes(
            struct.pack('<II', len(header), len(slots)) + header + slots + text)

    save('valid', base + message)
    save('empty', base[:12] + struct.pack('<I', 0) + base[16:], b'', b'')
    save('deleted', base[:12] + struct.pack('<I', 0) + base[16:], struct.pack('<II', 0xffffffff, 0xffffffff), b'')
    save('truncated-base', base[:1000])
    save('truncated-message', base + message[:30])
    save('truncated-index', base + message, b'partial')
    damaged = bytearray(base + message)
    struct.pack_into('<I', damaged, 1024 + 8, 0xffffffff)
    save('huge-subfields', damaged)
    damaged = bytearray(base + message)
    struct.pack_into('<I', damaged, 1024 + 64, 0xffffffff)
    save('huge-body', damaged)
    damaged = bytearray(base + message)
    struct.pack_into('<H', damaged, 1024 + 4, 2)
    save('bad-revision', damaged)


if __name__ == '__main__':
    main()
