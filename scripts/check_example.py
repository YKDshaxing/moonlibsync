"""Run the public-only example and inspect its actual emitted delta."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from interop_wire import inspect_delta, check_contents

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
parser = argparse.ArgumentParser()
parser.add_argument('--target', required=True, choices=['native', 'js', 'wasm-gc'])
args = parser.parse_args()
build = os.environ.get('MOONLIBSYNC_BUILD_DIR', '_build')
output = ROOT / build / 'examples'
output.mkdir(parents=True, exist_ok=True)
command = ['moon', '--target-dir', build, 'run', 'examples/basic', '--target', args.target]
result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
(output / (args.target + '.log')).write_text(result.stdout, encoding='utf-8')
print(result.stdout, end='', flush=True)
report = {'target': args.target, 'command': command, 'exit_code': result.returncode,
          'source_sha': subprocess.check_output(['git', '-c', f'safe.directory={ROOT.as_posix()}', 'rev-parse', 'HEAD'], text=True).strip(),
          'source_dirty': bool(subprocess.check_output(['git', '-c', f'safe.directory={ROOT.as_posix()}', 'status', '--porcelain'], text=True).strip()),
          'status': 'failed'}
if os.environ.get('GITHUB_SHA'):
    assert report['source_sha'] == os.environ['GITHUB_SHA'] and not report['source_dirty'], 'CI source mismatch'

try:
    result.check_returncode()
    sizes = re.findall(r'^old_bytes=(\d+) new_bytes=(\d+) signature_bytes=(\d+) delta_bytes=(\d+)$', result.stdout, re.M)
    encoded = re.findall(r'^delta_hex=([0-9a-f]+)$', result.stdout, re.M)
    assert len(sizes) == len(encoded) == 1 and result.stdout.count('restored_equal=true') == 1, 'Example output protocol'
    old = bytes(0x10 + i // 64 for i in range(512))
    new = old[:256] + bytes.fromhex('0080ff') + old[256:]
    delta = bytes.fromhex(encoded[0])
    assert tuple(map(int, sizes[0])) == (len(old), len(new), 12 + 8 * 36, len(delta)), 'Example actual sizes'
    copied = check_contents(inspect_delta(delta), old, new)
    assert copied >= 512 and len(delta) < len(new), 'Example COPY/size threshold'
    (output / (args.target + '.delta')).write_bytes(delta)
    report.update(status='passed', old_bytes=len(old), new_bytes=len(new), signature_bytes=int(sizes[0][2]), delta_bytes=len(delta), copy_bytes=copied, restored_equal=True)
    print(f'Example {args.target} passed: old={len(old)} new={len(new)} signature={sizes[0][2]} delta={len(delta)} COPY={copied}', flush=True)
finally:
    (output / (args.target + '.json')).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
