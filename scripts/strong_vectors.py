"""Independent hashlib vectors. Only explicit --write updates saved expectations."""
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'tests/strongsum-vectors.json'
MOON = ROOT / 'strongsum_vectors_wbtest.mbt'


def inputs():
    return [b'', b'\x00', b'abc', b'\x00\x7f\x80\xff'] + [
        bytes((i * 73 + 19) % 256 for i in range(n))
        for n in (127, 128, 129, 255, 256, 257)]


def render(records):
    lines = ['// Generated from tests/strongsum-vectors.json; scripts/strong_vectors.py --write.',
             '', '///|', 'fn strong_reference_vectors() -> Array[(Bytes, Bytes)] {', '  [']
    for r in records:
        def literal(h):
            return 'b"' + ''.join('\\x' + h[i:i+2] for i in range(0, len(h), 2)) + '"'
        lines += ['    (', '      ' + literal(r['input_hex']) + ',',
                  '      ' + literal(r['blake2b256']) + ',', '    ),']
    return '\n'.join(lines + ['  ]', '}', ''])


def verify():
    saved = json.loads(DATA.read_text(encoding='utf-8'))
    records = saved['vectors']
    assert saved['algorithm'] == 'hashlib.blake2b(data, digest_size=32)'
    assert [r['input_hex'] for r in records] == [x.hex() for x in inputs()]
    for r, data in zip(records, inputs()):
        assert r['blake2b256'] == hashlib.blake2b(data, digest_size=32).hexdigest()
    # Formatting may change whitespace, but cannot add/delete code or bytes.
    # Ignore formatting whitespace only OUTSIDE strings; data bytes stay exact.
    normalize = lambda s: re.sub(r'"(?:\\.|[^"\\])*"|\s+',
        lambda m: m.group(0) if m.group(0).startswith('"') else '', s)
    assert normalize(MOON.read_text(encoding='utf-8')) == normalize(render(records)), 'Saved MoonBit vector drift'
    print(f'Independent BLAKE2b-256 vectors verified: {len(records)}; oracle {sys.version}')


if __name__ == '__main__':
    if sys.argv[1:] == ['--write']:
        records = [dict(input_hex=d.hex(), blake2b256=hashlib.blake2b(d, digest_size=32).hexdigest()) for d in inputs()]
        DATA.write_text(json.dumps(dict(algorithm='hashlib.blake2b(data, digest_size=32)',
            python=sys.version, rule='empty; 00; ASCII abc; 007f80ff; (i*73+19)%256 for lengths 127,128,129,255,256,257',
            source='https://docs.python.org/3/library/hashlib.html#blake2', vectors=records), indent=2) + '\n', encoding='utf-8', newline='\n')
        MOON.write_text(render(records), encoding='utf-8', newline='\n')
    else:
        assert not sys.argv[1:]
        verify()
