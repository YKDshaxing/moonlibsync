"""Read-only handwritten opcode integrity; --export transports bytes only."""
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def verify_opcodes(base):
    base = base.resolve()
    manifest = json.loads((base / 'manifest.json').read_text(encoding='utf-8'))
    assert manifest['format'] == 1
    paths = set()
    for f in manifest['files']:
        path = f['path']
        target = (base / path).resolve()
        assert not Path(path).is_absolute() and target.is_relative_to(base)
        assert path not in paths
        paths.add(path)
        data = target.read_bytes()
        assert len(data) == f['length'] and hashlib.sha256(data).hexdigest() == f['sha256']
    assert paths == {'vectors.json'}
    assert {p.relative_to(base).as_posix() for p in base.rglob('*') if p.is_file()} == paths | {'manifest.json'}
    records = json.loads((base / 'vectors.json').read_text(encoding='utf-8'))['vectors']
    assert len({r['id'] for r in records}) == len(records)
    lines = ['// Handwritten opcode bytes: tests/fixtures/opcodes/vectors.json.',
        '// Transport only: scripts/opcode_vectors.py --export <path>.', '', '///|',
        'fn opcode_vectors() -> Array[(Bytes, String)] {', '  [']
    for r in records:
        data = bytes.fromhex(r['hex'])
        escaped = ''.join('\\x%02x' % b for b in data)
        line = f'    (b"{escaped}", "{r["expect"]}"),'
        if len(line) <= 80:
            lines.append(line)
        else:
            lines += ['    (', f'      b"{escaped}",', f'      "{r["expect"]}",', '    ),']
    rendered = '\n'.join(lines + ['  ]', '}', ''])
    return records, rendered


def check_transport(rendered):
    norm = lambda s: re.sub(r'"(?:\\.|[^"\\])*"|\s+', lambda m: m[0] if m[0].startswith('"') else '', s)
    assert norm((ROOT / 'opcode_bytes_wbtest.mbt').read_text(encoding='utf-8')) == norm(rendered)


if __name__ == '__main__':
    records, rendered = verify_opcodes(ROOT / 'tests/fixtures/opcodes')
    if len(sys.argv) == 3 and sys.argv[1] == '--export':
        Path(sys.argv[2]).write_text(rendered, encoding='utf-8', newline='\n')
    else:
        assert not sys.argv[1:]
        check_transport(rendered)
    print(f'Handwritten opcode integrity verified: {len(records)} vectors, 1 data file + 1 manifest')
