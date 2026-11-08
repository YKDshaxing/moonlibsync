"""Linux reference consumption of public MoonBit signature output, never delta/patch implementations."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
lock = json.loads((ROOT / 'toolchain.lock.json').read_text())
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
manifest = json.loads((ROOT / 'tests/fixtures/manifest.json').read_text())
base = ROOT / '.toolchain/reference'
with tempfile.TemporaryDirectory(prefix='consume-', dir=base) as temp:
    root = Path(temp).resolve()
    assert root.is_relative_to(base.resolve())
    def compare(name, old, new, block, strong, expected=None):
        folder = root / name
        folder.mkdir()
        (folder / 'old.bin').write_bytes(old)
        (folder / 'new.bin').write_bytes(new)
        subprocess.run([str(exe), str(folder / 'old.bin'), str(folder / 'moonbit.sig'), str(block), str(strong)], check=True)
        subprocess.run([str(rdiff), '-H', 'blake2', '-R', 'rabinkarp', '-b', str(block), '-S', str(strong), 'signature', 'old.bin', 'upstream.sig'], cwd=folder, check=True)
        actual = (folder / 'moonbit.sig').read_bytes()
        assert actual == (folder / 'upstream.sig').read_bytes(), name
        if expected is not None:
            assert actual == expected, name
        subprocess.run([str(rdiff), 'delta', 'moonbit.sig', 'new.bin', 'update.delta'], cwd=folder, check=True)
        subprocess.run([str(rdiff), 'patch', 'old.bin', 'update.delta', 'restored.bin'], cwd=folder, check=True)
        subprocess.run(['cmp', 'new.bin', 'restored.bin'], cwd=folder, check=True)
    for case in manifest['cases']:
        folder = ROOT / 'tests/fixtures' / case['id']
        compare(case['id'], (folder / 'old.bin').read_bytes(), (folder / 'new.bin').read_bytes(), case['block_len'], case['strong_sum_len'], (folder / 'old.sig').read_bytes())
    count = 0
    for block in (1, 2, 64, 2048):
        for strong in (1, 16, 32):
            for size in sorted(set((0, 1, block - 1, block, block + 1, 2 * block - 1, 2 * block))):
                old = bytes((i * 73 + 19) % 256 for i in range(size))
                new = b'\x00\x80\xff' + old + b'\x7f'
                compare(f'matrix-{count}', old, new, block, strong)
                count += 1
    print(f'Public signature: 16 fixed fixtures + {count} temporary parameter cases byte-identical; upstream delta/patch/cmp passed.')
