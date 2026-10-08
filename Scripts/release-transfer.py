#!/usr/bin/env python3
"""Transfer an already-tested ZIP over a slow link without rebuilding it.

Unchanged compressed entries come from the previous release; original signed
vendor entries come from its pinned archive. Only remaining bytes are uploaded.
Assembly must reproduce the entire tested ZIP's SHA-256 before it can be used.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import tarfile
import zlib
from zipfile import ZipFile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def deflate(data):
    compressor = zlib.compressobj(6, zlib.DEFLATED, -15)
    return compressor.compress(data) + compressor.flush()


def compressed(data, entry):
    names, extra = struct.unpack_from('<HH', data, entry.header_offset + 26)
    start = entry.header_offset + 30 + names + extra
    return start, data[start:start + entry.compress_size]


def entry_key(name):
    # The public app name changed in 0.3.19. ZIP headers remain literal target
    # bytes; only byte-identical compressed file contents may be reused.
    for prefix in ('', '__MACOSX/'):
        old = prefix + 'StatsDirect Viewer.app/'
        if name.startswith(old):
            return prefix + 'StatsDirect.app/' + name[len(old):]
    return name


def prepare(args):
    base, target = args.base.read_bytes(), args.target.read_bytes()
    payload = bytearray()
    pieces = []

    def literal(data):
        if data:
            pieces.append({'source': 'payload', 'offset': len(payload), 'length': len(data)})
            payload.extend(data)

    with ZipFile(args.base) as old, ZipFile(args.target) as new, tarfile.open(args.vendor) as vendor:
        previous = {entry_key(entry.filename): entry for entry in old.infolist()}
        cursor = 0
        for entry in sorted(new.infolist(), key=lambda item: item.header_offset):
            start, data = compressed(target, entry)
            literal(target[cursor:start])
            reference = None
            key = entry_key(entry.filename)
            if key in previous:
                offset, candidate = compressed(base, previous[key])
                if candidate == data:
                    reference = {'source': 'base', 'offset': offset, 'length': len(data)}
            prefix = 'StatsDirect.app/Contents/Resources/TutorRuntime/'
            if reference is None and key.startswith(prefix) and data:
                name = key[len(prefix):]
                try:
                    member = vendor.getmember(name)
                    if member.isfile() and member.size <= 512 * 1024 * 1024:
                        raw = vendor.extractfile(member).read()
                        if entry.compress_type == 8 and deflate(raw) == data:
                            reference = {'source': 'vendor', 'name': name, 'length': len(data)}
                except KeyError:
                    pass
            if reference:
                pieces.append(reference)
            else:
                literal(data)
            cursor = start + entry.compress_size
        literal(target[cursor:])
    args.output.mkdir(parents=True, exist_ok=True)
    recipe = {'schema': 1, 'filename': args.target.name, 'sha256': digest(target),
              'size': len(target), 'baseSHA256': digest(base),
              'vendorSHA256': digest(args.vendor.read_bytes()),
              'payloadSHA256': digest(payload), 'pieces': pieces}
    (args.output / 'transfer-manifest.json').write_text(json.dumps(recipe, separators=(',', ':')))
    (args.output / 'transfer-payload.bin').write_bytes(payload)
    print('Transfer payload:', len(payload), 'bytes; tested ZIP:', len(target), 'bytes')


def assemble(args):
    recipe = json.loads(args.manifest.read_text())
    assert recipe['schema'] == 1 and recipe['size'] <= 2 * 1024 ** 3
    sources = {'base': args.base.read_bytes(), 'payload': args.payload.read_bytes()}
    assert digest(sources['base']) == recipe['baseSHA256'], 'Base checksum mismatch'
    assert digest(sources['payload']) == recipe['payloadSHA256'], 'Payload checksum mismatch'
    assert digest(args.vendor.read_bytes()) == recipe['vendorSHA256'], 'Vendor checksum mismatch'
    staging = args.output.with_suffix('.assembling')
    try:
        with tarfile.open(args.vendor) as vendor, staging.open('wb') as output:
            for piece in recipe['pieces']:
                if piece['source'] == 'vendor':
                    member = vendor.getmember(piece['name'])
                    assert member.isfile() and member.size <= 512 * 1024 * 1024
                    data = deflate(vendor.extractfile(member).read())
                else:
                    offset, length = piece['offset'], piece['length']
                    assert offset >= 0 and length >= 0
                    data = sources[piece['source']][offset:offset + length]
                assert len(data) == piece['length'], 'Invalid piece length'
                output.write(data)
        assert staging.stat().st_size == recipe['size'], 'Assembled size mismatch'
        assert digest(staging.read_bytes()) == recipe['sha256'], 'Assembled checksum mismatch'
        staging.replace(args.output)
        print('Verified identical tested ZIP:', recipe['sha256'])
    finally:
        staging.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('prepare')
    for name in ('base', 'vendor', 'target', 'output'):
        create.add_argument(name, type=Path)
    restore = commands.add_parser('assemble')
    for name in ('manifest', 'payload', 'base', 'vendor', 'output'):
        restore.add_argument(name, type=Path)
    args = parser.parse_args()
    (prepare if args.command == 'prepare' else assemble)(args)
