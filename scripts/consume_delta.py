"""Pinned upstream signatures -> public MoonBit delta -> upstream patch, no byte-identical delta requirement."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
from interop_wire import inspect_delta

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
lock = json.loads((ROOT / 'toolchain.lock.json').read_text(encoding='utf-8'))
assert subprocess.check_output(['moonc', '-v'], text=True).strip() == lock['moonc']
build = os.environ.get('MOONLIBSYNC_BUILD_DIR', '_build')
if not os.environ.get('MOONLIBSYNC_OFFLINE_INDEX'):
    subprocess.run(['moon', 'update'], check=True)
subprocess.run([sys.executable, 'scripts/verify_fixtures.py'], check=True)
subprocess.run(['moon', '--target-dir', build, 'build', 'probes/signature', '--target', 'native'], check=True)
subprocess.run([sys.executable, 'scripts/verify_dependencies.py'], check=True)
exe = ROOT / build / 'native/debug/build/probes/signature/signature.exe'
rdiff = ROOT / '.toolchain/reference/build/rdiff'
assert rdiff.is_file()
sha = subprocess.check_output(['git', '-c', f'safe.directory={ROOT}/.toolchain/reference/source', '-C', str(ROOT / '.toolchain/reference/source'), 'rev-parse', 'HEAD'], text=True).strip()
assert sha == 'e364852674780e43d578e4239128ff7014190ed3'
assert '2.3.4' in subprocess.check_output([str(rdiff), '--version'], text=True)
manifest = json.loads((ROOT / 'tests/fixtures/manifest.json').read_text(encoding='utf-8'))
base = ROOT / '.toolchain/reference'


def run(args, cwd):
    # check=True makes any generation, tool or comparison failure mandatory.
    result = subprocess.run([str(a) for a in args], cwd=cwd, check=True)
    print('+', shlex.join(map(str, args)), 'exit=' + str(result.returncode), flush=True)


def copy_bytes(data):
    return sum(command[2] for command in inspect_delta(data) if command[0] == 'copy')


with tempfile.TemporaryDirectory(prefix='generate-', dir=base) as temp:
    root = Path(temp).resolve()
    assert root.is_relative_to(base.resolve())

    def consume(name, old, new, block, strong, saved_signature=None, reuse=False):
        folder = root / name
        folder.mkdir()
        (folder / 'old.bin').write_bytes(old)
        (folder / 'new.bin').write_bytes(new)
        if saved_signature is not None:
            (folder / 'upstream.sig').write_bytes(saved_signature)
        else:
            run([rdiff, '-H', 'blake2', '-R', 'rabinkarp', '-b', block, '-S', strong, 'signature', 'old.bin', 'upstream.sig'], folder)
        # The adapter receives only signature + new paths; basis belongs solely
        # to signature preparation above and the independent rdiff patch below.
        run([exe, 'delta', folder / 'upstream.sig', folder / 'new.bin', folder / 'moonbit.delta'], folder)
        run([rdiff, 'patch', 'old.bin', 'moonbit.delta', 'restored.bin'], folder)
        run(['cmp', 'new.bin', 'restored.bin'], folder)
        assert (folder / 'restored.bin').read_bytes() == new, name
        if reuse:
            encoded = (folder / 'moonbit.delta').read_bytes()
            copied = copy_bytes(encoded)
            # Predefined before generation: eight known whole blocks =512 bytes.
            assert copied >= 512 and len(encoded) < len(new) == 515
            print(f'Reuse gate: new={len(new)} delta={len(encoded)} COPY={copied} minimum=512', flush=True)

    for case in manifest['cases']:
        folder = ROOT / 'tests/fixtures' / case['id']
        consume(case['id'], (folder / 'old.bin').read_bytes(), (folder / 'new.bin').read_bytes(), case['block_len'], case['strong_sum_len'], (folder / 'old.sig').read_bytes())
    old = bytes(0x10 + i // 64 for i in range(512))
    consume('reuse-eight-blocks', old, old[:256] + bytes.fromhex('0080ff') + old[256:], 64, 32, reuse=True)
    count = 1
    for block in (1, 2, 64, 2048):
        size = 2 * block + max(1, block // 2)
        old = bytes((i * 73 + 19 + i // block) % 256 for i in range(size))
        for label, new in [
            ('tail-at-eof', bytes.fromhex('ff0080') + old),
            ('tail-in-middle', old[2 * block:] + old[:2 * block] + b'!'),
            ('changed-short', old[:-1] + b'\x55'),
        ]:
            consume(f'block-{block}-{label}', old, new, block, 32)
            count += 1
    print(f'Public delta: 16 fixed upstream signatures + {count} temporary reuse/short-tail cases; upstream patch/cmp passed.', flush=True)
