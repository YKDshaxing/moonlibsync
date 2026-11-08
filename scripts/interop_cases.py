"""Reviewable deterministic input plan; no library output defines expectations."""
import hashlib
import itertools
import json
from pathlib import Path
from fixture_data import cases as fixed_cases

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / 'tests/interop/matrix.json').read_text(encoding='utf-8'))


def case(group, name, old, new, block, strong, **meta):
    return dict(group=group, id=f'{group}-{name}', old=old, new=new,
                block=block, strong=strong, **meta)


class LCG:
    def __init__(self, seed):
        self.state = seed

    def next(self):
        self.state = (1664525 * self.state + 1013904223) & 0xffffffff
        return self.state

    def bytes(self, n):
        return bytes(self.next() >> 24 for _ in range(n))


def make_cases():
    out = []
    for name, _, old, new, block, strong in fixed_cases():
        out.append(case('fixed', name, old, new, block, strong))
    for block in (1, 2, 64, 2048):
        for strong in (1, 16, 32):
            for size in sorted(set((0, 1, block - 1, block, block + 1, 2 * block - 1, 2 * block))):
                old = bytes((i * 73 + 19) % 256 for i in range(size))
                out.append(case('signature-boundary', f'{block}-{strong}-{size}', old, b'\x00\x80\xff' + old + b'\x7f', block, strong))
    for block in (1, 2, 64, 2048):
        old = bytes((i * 73 + 19 + i // block) % 256 for i in range(2 * block + max(1, block // 2)))
        for name, new in [('tail-at-eof', b'\xff\x00\x80' + old), ('tail-in-middle', old[2 * block:] + old[:2 * block] + b'!'), ('changed-short', old[:-1] + b'\x55')]:
            out.append(case('short-tail', f'{block}-{name}', old, new, block, 32))
    old = bytes(0x10 + i // 64 for i in range(512))
    for name, new, floor in [('insert', old[:256] + b'\x00\x80\xff' + old[256:], 512), ('same', old, 512), ('local-edit', old[:70] + b'!' + old[71:330] + b'?' + old[331:], 384)]:
        out.append(case('reuse', name, old, new, 64, 32, copy_floor=floor))
    names = ['same', 'different', 'insert-head', 'insert-middle', 'insert-tail', 'delete-head', 'delete-middle', 'delete-tail', 'replace-head', 'replace-middle', 'replace-tail', 'move-block', 'tail-middle']
    for ordinal, name in enumerate(names):
        block, strong = CONFIG['parameters'][ordinal % 6]
        old = bytes((i * 73 + 19 + i // block * 11) % 256 for i in range(3 * block + max(1, block // 2)))
        middle = block
        new = {'same': old, 'different': b'\x55' * len(old), 'insert-head': b'\x00\x80\xff' + old, 'insert-middle': old[:middle] + b'\x00\x80\xff' + old[middle:], 'insert-tail': old + b'\x00\x80\xff', 'delete-head': old[1:], 'delete-middle': old[:middle] + old[middle+1:], 'delete-tail': old[:-1], 'replace-head': b'\xff' + old[1:], 'replace-middle': old[:middle] + b'\x80' + old[middle+1:], 'replace-tail': old[:-1] + b'\x00', 'move-block': old[block:2*block] + old[:block] + old[2*block:], 'tail-middle': old[3*block:] + old[:3*block] + b'!'}[name]
        out.append(case('edits', name, old, new, block, strong))
    spec = CONFIG['exhaustive']
    words = [bytes(w) for size in spec['lengths'] for w in itertools.product(spec['alphabet'], repeat=size)]
    assert len(words) == 13
    for a, old in enumerate(words):
        for b, new in enumerate(words):
            for block in spec['blocks']:
                out.append(case('exhaustive', f'{a}-{b}-{block}', old, new, block, spec['strong']))
    spec = CONFIG['random']
    for ordinal in range(spec['samples']):
        seed = (spec['seed'] + ordinal * 0x9e3779b9) & 0xffffffff
        rng = LCG(seed)
        length = rng.next() % 8193
        if ordinal % 3 == 0:
            old = rng.bytes(length)
        elif ordinal % 3 == 1:
            pattern = rng.bytes(1 + rng.next() % 16)
            old = (pattern * (length // len(pattern) + 1))[:length]
        else:
            old = bytes((i * 73 + 19) % 256 for i in range(length))
        edits, new, trace = 1 + rng.next() % 6, old, []
        for j in range(edits):
            op = (ordinal + j) % 6
            pos = rng.next() % (len(new) + 1)
            n = 1 + rng.next() % 32
            payload = rng.bytes(n)
            before = len(new)
            if op == 0:
                new = new[:pos] + payload + new[pos:]
            elif op == 1:
                new = new[:pos] + new[pos+n:]
            elif op == 2:
                take = min(n, len(new) - pos)
                new = new[:pos] + payload[:take] + new[pos+take:]
            elif op == 3:
                chunk = new[pos:pos+n]
                rest = new[:pos] + new[pos+len(chunk):]
                dest = rng.next() % (len(rest) + 1)
                new = rest[:dest] + chunk + rest[dest:]
            elif op == 4:
                new = new[:-min(n, len(new))] if rng.next() & 1 and new else new + payload
            elif new:
                pos %= len(new)
                new = new[:pos] + payload[:1] + new[pos+1:]
            trace.append(dict(op=op, position=pos, size=n, before=before, after=len(new)))
        assert len(new) <= spec['max_new_length']
        block, strong = CONFIG['parameters'][ordinal % 6]
        out.append(case('random', str(ordinal), old, new, block, strong, seed=seed, edit_count=edits, trace=trace))
    assert len(out) == CONFIG['expected_cases'] and len({c['id'] for c in out}) == len(out)
    assert {g: sum(c['group'] == g for c in out) for g in CONFIG['groups']} == CONFIG['groups']
    return out


def fingerprint(cases):
    h = hashlib.sha256()
    for c in cases:
        metadata = {k: v for k, v in c.items() if k not in ('old', 'new')}
        for part in (json.dumps(metadata, sort_keys=True, separators=(',', ':')).encode(), c['old'], c['new']):
            h.update(len(part).to_bytes(8, 'big'))
            h.update(part)
    return h.hexdigest()
