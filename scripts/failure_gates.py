"""Corrupt only a runnable isolated source copy; exercise the real CI entries."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
output = ROOT / os.environ.get('MOONLIBSYNC_BUILD_DIR', '_build') / 'gates'
output.mkdir(parents=True, exist_ok=True)
git = ['git', '-c', f'safe.directory={ROOT.as_posix()}']
report = {'source_sha': subprocess.check_output([*git, 'rev-parse', 'HEAD'], text=True).strip(),
          'source_dirty': bool(subprocess.check_output([*git, 'status', '--porcelain'], text=True).strip()),
          'status': 'incomplete', 'checks': []}
if os.environ.get('GITHUB_SHA'):
    assert report['source_sha'] == os.environ['GITHUB_SHA'] and not report['source_dirty'], 'CI source mismatch'



def run_copy(copy, name, entry, marker=None):
    env = dict(os.environ, MOONLIBSYNC_BUILD_DIR='_build', MOONLIBSYNC_OFFLINE_INDEX='1')
    env.pop('GITHUB_SHA', None)  # Intentional copy mutations, recorded separately from clean CI source.
    command = [sys.executable, *entry]
    result = subprocess.run(command, cwd=copy, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding='utf-8', errors='replace', timeout=180)
    (output / (name + '.log')).write_text(result.stdout, encoding='utf-8')
    # A timeout, tool error or unrelated compiler failure cannot satisfy this gate.
    if marker is None:
        assert result.returncode == 0, name + ': normal entry failed; see log'
    else:
        assert result.returncode > 0 and marker in result.stdout, name + ': expected diagnostic/nonzero missing'
        if name == 'example-broken':
            assert marker in result.stdout.splitlines() and 'RuntimeError: unreachable' in result.stdout, 'Expected runtime assertion was not executed'
            assert 'CalledProcessError' in result.stdout and 'returned non-zero exit status' in result.stdout, 'Wrapper did not propagate child failure'
    report['checks'].append({'name': name, 'command': command, 'exit_code': result.returncode,
                             'expected_diagnostic': marker, 'log': name + '.log'})
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f'Failure gate {name}: exit={result.returncode} expected={marker or "success"}', flush=True)


with tempfile.TemporaryDirectory(prefix='moonlibsync-gates-') as directory:
    copy = Path(directory) / 'source'
    subprocess.run(['git', '-c', f'safe.directory={ROOT.as_posix()}/.git', '-c', f'safe.directory={ROOT.as_posix()}', 'clone', '--quiet', '--no-hardlinks', '--local', str(ROOT), str(copy)], check=True)
    # Include current task edits for pre-commit verification. CI repeats on clean HEAD.
    files = subprocess.check_output([*git, 'ls-files', '-co', '--exclude-standard', '-z']).decode().split('\0')
    for name in set(files) - {''}:
        source = ROOT / name
        if source.is_file():
            destination = copy / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        elif (copy / name).is_file():
            (copy / name).unlink()
    shutil.copytree(ROOT / '.mooncakes', copy / '.mooncakes', ignore=shutil.ignore_patterns('_build', '__pycache__'))
    for name, relative, marker in (
        ('reference', 'tests/fixtures/empty/old.bin', 'empty/old.bin'),
        ('opcode', 'tests/fixtures/opcodes/vectors.json', 'Opcode fixture checksum: vectors.json'),
    ):
        file = copy / relative
        original = file.read_bytes()
        file.write_bytes(original + b' ')
        run_copy(copy, name + '-broken', ['scripts/check_fixtures.py'], marker)
        file.write_bytes(original)
        run_copy(copy, name + '-normal', ['scripts/check_fixtures.py'])
    file = copy / 'examples/basic/main.mbt'
    original = file.read_text(encoding='utf-8')
    assert original.count('let expected = new_bytes') == 1
    file.write_text(original.replace('let expected = new_bytes', 'let expected = new_bytes + b"\\x00"'), encoding='utf-8')
    run_copy(copy, 'example-broken', ['scripts/check_example.py', '--target', 'wasm-gc'], 'BASIC_RESTORE_MISMATCH')
    file.write_text(original, encoding='utf-8')
    run_copy(copy, 'example-normal', ['scripts/check_example.py', '--target', 'wasm-gc'])
    # Deleted tracked interfaces must fail before moon info can regenerate them.
    (copy / 'probes/digest/pkg.generated.mbti').unlink()
    run_copy(copy, 'interface-deleted', ['-c', 'from pathlib import Path; import sys; sys.path.insert(0,"scripts"); from interface_guard import snapshot; snapshot(Path.cwd())'], 'INTERFACE_BASELINE_MISMATCH: probes/digest/pkg.generated.mbti')
    shutil.copyfile(ROOT / 'probes/digest/pkg.generated.mbti', copy / 'probes/digest/pkg.generated.mbti')
    run_copy(copy, 'interface-normal', ['-c', 'from pathlib import Path; import sys; sys.path.insert(0,"scripts"); from interface_guard import snapshot; snapshot(Path.cwd())'])
    # Exercise the same real CLI wrapper with a corrupt result descriptor.
    file = copy / 'tests/integrity/update.json'
    original = file.read_bytes()
    data = json.loads(original)
    data['result']['sha256'] = '0' * 64
    file.write_text(json.dumps(data), encoding='utf-8')
    run_copy(copy, 'stage-a-manifest-broken', ['scripts/check_stage_a_gate.py'], 'BindingMismatch:result_sha256')
    file.write_bytes(original)
    run_copy(copy, 'stage-a-manifest-normal', ['scripts/check_stage_a_gate.py'])
report['status'] = 'passed'
(output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print('Isolated failure gates passed; broken and normal logs preserved separately.')
