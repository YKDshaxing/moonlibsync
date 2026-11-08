"""Two real product-CLI / pinned-rdiff file exchanges, Linux Native only."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
from interop_wire import inspect_delta, check_contents

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
assert os.name == 'posix', 'Linux Native demonstration requires Linux'
build = os.environ.get('MOONLIBSYNC_BUILD_DIR', '_build')
output = ROOT / build / 'exchange'
output.mkdir(parents=True, exist_ok=True)
report = {'status': 'incomplete', 'target': 'Linux Native', 'commands': [], 'chains': []}


def run(command, cwd=ROOT):
    command = list(map(str, command))
    result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace', timeout=120)
    with (output / 'commands.log').open('a', encoding='utf-8') as log:
        log.write(f'$ (cd {shlex.quote(str(cwd))} && {shlex.join(command)})\n{result.stdout}\nexit={result.returncode}\n')
    report['commands'].append({'cwd': str(cwd), 'args': command, 'exit_code': result.returncode})
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    result.check_returncode()
    return result.stdout.strip()


(output / 'commands.log').write_text('', encoding='utf-8')
report['source_sha'] = run(['git', '-c', f'safe.directory={ROOT.as_posix()}', 'rev-parse', 'HEAD'])
report['source_dirty'] = bool(run(['git', '-c', f'safe.directory={ROOT.as_posix()}', 'status', '--porcelain']))
if os.environ.get('GITHUB_SHA'):
    assert report['source_sha'] == os.environ['GITHUB_SHA'] and not report['source_dirty'], 'CI source mismatch'
lock = json.loads((ROOT / 'toolchain.lock.json').read_text())
assert run(['moonc', '-v']) == lock['moonc']
rdiff = ROOT / '.toolchain/reference/build/rdiff'
upstream = ROOT / '.toolchain/reference/source'
assert run(['git', '-c', f'safe.directory={upstream}', '-C', upstream, 'rev-parse', 'HEAD']) == 'e364852674780e43d578e4239128ff7014190ed3'
# Match build-reference.sh: compare actual tracked content, then reject untracked files.
run(['git', '-c', f'safe.directory={upstream}', '-C', upstream, 'diff', '--exit-code', 'HEAD', '--'])
assert not run(['git', '-c', f'safe.directory={upstream}', '-C', upstream, 'ls-files', '--others', '--exclude-standard'])
report['reference_version'] = run([rdiff, '--version'])
assert '2.3.4' in report['reference_version']
run(['moon', '--target-dir', build, 'build', 'cmd/moonlibsync', '--target', 'native'])
cli = ROOT / build / 'native/debug/build/cmd/moonlibsync/moonlibsync.exe'
assert cli.read_bytes()[:4] == b'\x7fELF'
parent = os.environ.get('MOONLIBSYNC_CLI_TMP_PARENT')
with tempfile.TemporaryDirectory(prefix='moonlibsync-exchange-', dir=parent) as temporary:
    folder = Path(temporary).resolve()
    report['filesystem'] = run(['stat', '-f', '-c', '%T', folder])
    report['temporary_directory'] = str(folder)
    old = bytes(0x10 + i // 64 for i in range(512))
    new = old[:256] + bytes.fromhex('0080ff') + old[256:]
    (folder / 'old.bin').write_bytes(old)
    (folder / 'new.bin').write_bytes(new)
    run([rdiff, '-H', 'blake2', '-R', 'rabinkarp', '-b', '64', '-S', '32', 'signature', 'old.bin', 'upstream.sig'], folder)
    run([cli, 'delta', 'upstream.sig', 'new.bin', 'moon.delta'], folder)
    run([rdiff, 'patch', 'old.bin', 'moon.delta', 'upstream-restored.bin'], folder)
    assert (folder / 'upstream-restored.bin').read_bytes() == new
    delta = (folder / 'moon.delta').read_bytes()
    copied = check_contents(inspect_delta(delta), old, new)
    assert copied >= 512 and len(delta) < len(new)
    report['chains'].append({'name': 'upstream signature -> CLI delta -> upstream patch', 'restored_equal': True, 'delta_bytes': len(delta), 'copy_bytes': copied})
    run([cli, 'signature', 'old.bin', 'moon.sig', '--block-size', '64', '--sum-size', '32'], folder)
    assert (folder / 'moon.sig').read_bytes() == (folder / 'upstream.sig').read_bytes()
    run([rdiff, 'delta', 'moon.sig', 'new.bin', 'upstream.delta'], folder)
    run([cli, 'patch', 'old.bin', 'upstream.delta', 'moon-restored.bin'], folder)
    assert (folder / 'moon-restored.bin').read_bytes() == new
    report['chains'].append({'name': 'CLI signature -> upstream delta -> CLI patch', 'restored_equal': True})
    # Retain the exact exchanged files after the owned temporary directory closes.
    saved = Path(tempfile.mkdtemp(prefix='files-', dir=output))
    for file in folder.iterdir():
        shutil.copyfile(file, saved / file.name)
    report['saved_files'] = str(saved.relative_to(ROOT))
report['status'] = 'passed'
(output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(f'Linux Native file exchange passed: both restored outputs equal independent new bytes; delta={len(delta)} COPY={copied}.')
