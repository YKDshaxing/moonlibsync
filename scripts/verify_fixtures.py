"""Read-only integrity verification; --export only transports verified bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
from fixture_data import SHA, cases, render_constants
from opcode_vectors import verify_opcodes, check_transport

ROOT = Path(__file__).resolve().parents[1]


def verify(base):
    base = base.resolve()
    manifest = json.loads((base / 'manifest.json').read_text(encoding='utf-8'))
    assert manifest['format'] == 1 and manifest['upstream']['commit'] == SHA
    assert manifest['upstream']['version'] == 'v2.3.4'
    assert manifest['upstream']['repository'] == 'https://github.com/librsync/librsync'
    assert manifest['tool_version'].startswith('rdiff (librsync 2.3.4)')
    expected = {c[0]: c for c in cases()}
    ids, paths = set(), set()
    for case in manifest['cases']:
        name = case['id']
        assert name not in ids and name in expected, 'Duplicate/unknown case ID'
        ids.add(name)
        _, purpose, old, new, block, strong = expected[name]
        assert (case['block_len'], case['strong_sum_len']) == (block, strong)
        assert case['profile'] == 'RS_RK_BLAKE2_SIG_MAGIC'
        local = set()
        for spec in case['files']:
            path = spec['path']
            target = (base / path).resolve()
            assert target.is_relative_to(base) and not Path(path).is_absolute(), 'Escaping path'
            assert path not in paths, 'Duplicate file registration'
            paths.add(path)
            local.add(path)
            data = target.read_bytes()
            assert len(data) == spec['length'] and hashlib.sha256(data).hexdigest() == spec['sha256'], path
        assert local == {name + '/' + f for f in ('old.bin', 'new.bin', 'old.sig', 'update.delta')}
        assert (base / name / 'old.bin').read_bytes() == old
        assert (base / name / 'new.bin').read_bytes() == new
        sig = (base / name / 'old.sig').read_bytes()
        assert struct.unpack('>III', sig[:12]) == (0x72730147, block, strong)
        assert len(sig) == 12 + ((len(old) + block - 1) // block) * (4 + strong)
    assert ids == set(expected), 'Missing cases'
    opcode_records, rendered = verify_opcodes(base / 'opcodes')
    check_transport(rendered)
    actual = {p.relative_to(base).as_posix() for p in base.rglob('*') if p.is_file()}
    assert actual == paths | {'manifest.json', 'opcodes/vectors.json', 'opcodes/manifest.json'}, 'Unregistered/missing fixture files'
    print(f'Handwritten opcode integrity verified separately: {len(opcode_records)} vectors')
    return len(ids), sum((base / p).stat().st_size for p in paths)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', nargs='?', type=Path, default=ROOT / 'tests/fixtures')
    parser.add_argument('--export', type=Path)
    args = parser.parse_args()
    count, size = verify(args.directory)
    constants = render_constants(args.directory)
    if args.export:
        args.export.write_bytes(constants)
    else:
        assert (ROOT / 'reference_bytes_wbtest.mbt').read_bytes() == constants, 'Byte transport drift'
    print(f'Verified {count} cases, {count * 4} files, {size} bytes')
