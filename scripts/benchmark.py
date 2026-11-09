"""Finite Linux Native file-process benchmark; no performance pass threshold.

The immutable plan precedes measurement. All outputs are fresh; validation,
compilation and input preparation are outside each timed subprocess call.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone

from interop_wire import inspect_delta, check_contents

ROOT = Path(__file__).resolve().parents[1]
PLAN = ROOT / 'tests/benchmarks/config.json'
UPSTREAM_SHA = 'e364852674780e43d578e4239128ff7014190ed3'
ENGINES = ('moon', 'rdiff')
OPERATIONS = ('signature', 'delta', 'patch')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def runtime_files():
    # Exact runtime scope, not a cache/build-tree glob. Include additions too.
    paths = [p for p in ROOT.glob('*.mbt') if not p.name.endswith(('_test.mbt', '_wbtest.mbt'))]
    paths += list((ROOT / 'cmd/moonlibsync').glob('*.mbt'))
    paths += [ROOT / name for name in ('moon.mod', 'moon.pkg', 'pkg.generated.mbti',
              'cmd/moonlibsync/moon.pkg', 'dependencies.lock.json', 'toolchain.lock.json')]
    return {p.relative_to(ROOT).as_posix(): sha(p.read_bytes()) for p in sorted(paths)}


def inputs(size, scenario, config):
    domain = config['domain'].encode('ascii') + str(size).encode('ascii')
    old = bytes(value & 127 for value in hashlib.shake_256(domain + b'/old').digest(size))
    if scenario == 'identical':
        new = old
    elif scenario == 'small-replace':
        pos = size // 2 + 17
        new = old[:pos] + bytes(range(128, 192)) + old[pos + 64:]
    elif scenario == 'front-insert':
        new = bytes(range(128, 160)) + old
    elif scenario == 'all-different':
        new = bytes((value & 127) | 128 for value in hashlib.shake_256(domain + b'/different').digest(size))
        assert set(old).isdisjoint(new), 'Different alphabets must be disjoint'
    elif scenario == 'repeated':
        old = (bytes(range(128)) * ((size + 127) // 128))[:size]
        new = old[:size // 2] + bytes(range(128, 160)) + old[size // 2:]
    else:
        raise ValueError(scenario)
    return old, new


def delta_stats(encoded, old, new):
    commands = inspect_delta(encoded)
    copied = check_contents(commands, old, new)
    return {'delta_bytes': len(encoded), 'copy_bytes': copied,
            'copy_commands': sum(c[0] == 'copy' for c in commands),
            'literal_commands': sum(c[0] == 'literal' for c in commands),
            'literal_bytes': len(new) - copied, 'delta_sha256': sha(encoded)}


def stats(rows):
    if not rows or any(r['status'] != 'validated' or r['exit_code'] != 0 for r in rows):
        raise ValueError('Incomplete/failed measurement cannot enter success statistics')
    times = [r['elapsed_ns'] for r in rows if r['phase'] == 'formal']
    if not times:
        raise ValueError('No formal measurements')
    return {'samples': len(times), 'median_ns': statistics.median(times), 'min_ns': min(times), 'max_ns': max(times)}


def self_check(config):
    for size in config['sizes']:
        for scenario in config['scenarios']:
            old, new = inputs(size, scenario, config)
            assert len(old) == size and len(new) == size + (32 if scenario in ('front-insert', 'repeated') else 0)
            if scenario == 'small-replace':
                assert sum(a != b for a, b in zip(old, new)) == 64
            if scenario in ('front-insert', 'repeated'):
                pos = 0 if scenario == 'front-insert' else size // 2
                assert new[:pos] + new[pos + 32:] == old
    rows = [dict(status='validated', exit_code=0, phase='formal', elapsed_ns=n) for n in (5, 1, 9)]
    assert stats(rows + [dict(rows[0], phase='warmup', elapsed_ns=999)]) == dict(samples=3, median_ns=5, min_ns=1, max_ns=9)
    for bad in ([], [dict(rows[0], status='failed')], [dict(rows[0], exit_code=1)]):
        try:
            stats(bad)
        except ValueError:
            continue
        raise AssertionError('Failed measurement accepted')
    print('Benchmark tool checks passed: ten generator cases; summary/warmup policy; failed/incomplete sample rejection. No timed benchmark executed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-check', action='store_true')
    parser.add_argument('--verify-source', type=Path, metavar='RUN_DIRECTORY')
    args = parser.parse_args()
    config = json.loads(PLAN.read_text(encoding='utf-8'))
    if args.self_check:
        self_check(config)
        return
    if args.verify_source:
        folder = args.verify_source.resolve()
        manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
        assert manifest['runtime_files'] == runtime_files(), 'Measured runtime differs from current frozen runtime'
        assert manifest['plan_sha256'] == sha(PLAN.read_bytes()), 'Benchmark plan changed'
        assert manifest['tool_sha256'] == sha(Path(__file__).read_bytes()), 'Benchmark driver changed'
        git = ['git', '-c', f'safe.directory={ROOT.as_posix()}']
        linkage = {'measured_source': manifest['source'], 'current_sha': subprocess.check_output([*git, 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                   'current_dirty': bool(subprocess.check_output([*git, 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
                   'runtime_files_identical': True, 'plan_and_driver_identical': True, 'runtime_files': runtime_files()}
        save(folder / 'source-linkage.json', linkage)
        print(json.dumps({k: v for k, v in linkage.items() if k != 'runtime_files'}))
        return
    if sys.platform != 'linux':
        raise SystemExit('Full measurement requires Linux Native; no platform skip')
    os.chdir(ROOT)
    output = ROOT / '_build/benchmarks' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    output.mkdir(parents=True, exist_ok=False)
    print('Benchmark evidence:', output, flush=True)
    rows, summaries = [], []
    manifest = {'format': 1, 'status': 'preparing', 'plan': config,
                'plan_sha256': sha(PLAN.read_bytes()), 'tool_sha256': sha(Path(__file__).read_bytes()),
                'runtime_files': runtime_files(), 'cases': [],
                'timing_boundary': 'subprocess start + reads + computation + writes + process exit; Moon includes file sync and no-replace commit; validation excluded',
                'retention': 'timed outputs verified and hashed then deleted outside timing; representative inputs/signatures/deltas retained; any failure archives working files',
                'cache_policy': '2 warmups, OS caches uncontrolled; no cold-disk, CPU affinity, peak memory or cache-drop claim'}

    def run(command, cwd=ROOT, row=None):
        command = list(map(str, command))
        start = time.perf_counter_ns()
        try:
            result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    timeout=config['timeout_seconds'])
        except BaseException as error:
            with (output / 'commands.log').open('a', encoding='utf-8') as log:
                log.write(json.dumps({'argv': command, 'cwd': str(cwd), 'error': repr(error), 'timed': row is not None}) + '\n')
            raise
        end = time.perf_counter_ns()
        record = {'argv': command, 'cwd': str(cwd), 'exit_code': result.returncode,
                  'stdout': result.stdout.decode('utf-8', errors='replace'), 'stderr': result.stderr.decode('utf-8', errors='replace'), 'timed': row is not None}
        if row is not None:
            row.update(command=command, exit_code=result.returncode, elapsed_ns=end - start, status='unvalidated')
            rows.append(row)
            save(output / 'measurements.json', rows)
            record['measurement_index'] = len(rows) - 1
        with (output / 'commands.log').open('a', encoding='utf-8') as log:
            log.write(json.dumps(record) + '\n')
        result.check_returncode()
        return record['stdout'].strip()

    git = ['git', '-c', f'safe.directory={ROOT.as_posix()}']
    manifest['source'] = {'sha': run([*git, 'rev-parse', 'HEAD']), 'dirty': bool(run([*git, 'status', '--porcelain']))}
    save(output / 'manifest.json', manifest)
    try:
        lock = json.loads((ROOT / 'toolchain.lock.json').read_text())
        assert run(['moonc', '-v']) == lock['moonc']
        help_text = run(['moon', 'build', '--help'])
        assert '--release' in help_text and '--target-dir' in help_text
        build_dir = output / 'build'
        run(['moon', '--target-dir', build_dir, 'build', 'cmd/moonlibsync', '--target', 'native', '--release'])
        run([sys.executable, ROOT / 'scripts/verify_dependencies.py'])
        product = build_dir / 'native/release/build/cmd/moonlibsync/moonlibsync.exe'
        assert product.is_file() and product.read_bytes()[:4] == b'\x7fELF'
        upstream = ROOT / '.toolchain/reference/source'
        rdiff = ROOT / '.toolchain/reference/build/rdiff'
        reference_git = [*git, '-c', f'safe.directory={upstream.as_posix()}', '-C', upstream]
        assert run([*reference_git, 'rev-parse', 'HEAD']) == UPSTREAM_SHA
        run([*reference_git, 'diff', '--exit-code', 'HEAD', '--'])
        assert not run([*reference_git, 'ls-files', '--others', '--exclude-standard'])
        reference_cache = (rdiff.parent / 'CMakeCache.txt').read_text()
        for setting in ('CMAKE_BUILD_TYPE:STRING=Release', 'BUILD_RDIFF:BOOL=ON', 'BUILD_SHARED_LIBS:BOOL=OFF', 'USE_LIBB2:INTERNAL=OFF', 'ENABLE_COMPRESSION:BOOL=OFF', 'ENABLE_TRACE:BOOL=OFF'):
            assert setting in reference_cache, setting
        assert '--block-size' in run([rdiff, '--help'])
        manifest['environment'] = {'platform': platform.platform(), 'uname': run(['uname', '-a']),
            'os_release': Path('/etc/os-release').read_text(), 'cpu': run(['lscpu']), 'memory': run(['free', '-b']),
            'moon': run(['moon', 'version', '--all']), 'cc': run(['cc', '--version']), 'python': sys.version,
            'clock': str(time.get_clock_info('perf_counter')), 'rdiff': run([rdiff, '--version']),
            'reference_cmake_cache_sha256': sha(reference_cache.encode()), 'reference_cmake_cache': reference_cache,
            'reference_compile_commands': json.loads((rdiff.parent / 'compile_commands.json').read_text()),
            'product_path': str(product), 'product_sha256': sha(product.read_bytes()),
            'rdiff_path': str(rdiff), 'rdiff_sha256': sha(rdiff.read_bytes()), 'build_mode': 'release'}
        with tempfile.TemporaryDirectory(prefix='moonlibsync-benchmark-', dir=os.environ.get('MOONLIBSYNC_BENCH_TMP_PARENT', '/tmp')) as temporary:
            work = Path(temporary)
            try:
                # Put both executables and all timed inputs/outputs on this filesystem.
                executable = {}
                for engine, source in zip(ENGINES, (product, rdiff)):
                    executable[engine] = work / (engine + '.exe')
                    shutil.copy2(source, executable[engine])
                    assert sha(executable[engine].read_bytes()) == sha(source.read_bytes())
                manifest['environment'].update(work_directory=str(work), mount=run(['findmnt', '-T', work, '-o', 'TARGET,SOURCE,FSTYPE,OPTIONS', '--json']), filesystem=run(['stat', '-f', '-c', '%T', work]), executed_paths={k: str(v) for k, v in executable.items()})
                assert 'ext4' in manifest['environment']['mount'], 'Positive benchmark requires verified ext4 mount'
                manifest['status'] = 'measuring'
                save(output / 'manifest.json', manifest)
                for case_index, (size, scenario) in enumerate((s, c) for s in config['sizes'] for c in config['scenarios']):
                    case_id = f'{size}-{scenario}'
                    folder = work / case_id
                    folder.mkdir()
                    old, new = inputs(size, scenario, config)
                    (folder / 'old.bin').write_bytes(old)
                    (folder / 'new.bin').write_bytes(new)
                    sig = folder / 'shared.sig'
                    canonical = {e: folder / (e + '.delta') for e in ENGINES}

                    def command(engine, operation, destination):
                        exe = executable[engine]
                        if operation == 'signature':
                            if engine == 'moon':
                                return [exe, 'signature', folder / 'old.bin', destination, '--block-size', str(config['block_len']), '--sum-size', str(config['strong_sum_len'])]
                            return [exe, '-H', 'blake2', '-R', 'rabinkarp', '-b', str(config['block_len']), '-S', str(config['strong_sum_len']), 'signature', folder / 'old.bin', destination]
                        return [exe, operation, sig if operation == 'delta' else folder / 'old.bin', folder / 'new.bin' if operation == 'delta' else canonical['rdiff'], destination]

                    run(command('rdiff', 'signature', sig))
                    details = {'case': case_id, 'old_bytes': len(old), 'new_bytes': len(new),
                               'old_sha256': sha(old), 'new_sha256': sha(new), 'signature_bytes': sig.stat().st_size,
                               'signature_sha256': sha(sig.read_bytes()), 'engines': {}}
                    for engine in ENGINES:
                        run(command(engine, 'delta', canonical[engine]))
                        detail = delta_stats(canonical[engine].read_bytes(), old, new)
                        if scenario == 'all-different':
                            assert detail['copy_bytes'] == 0 and detail['literal_bytes'] == len(new)
                        detail.update(delta_over_new=detail['delta_bytes'] / len(new) if new else None,
                                      signature_plus_delta_over_new=(sig.stat().st_size + detail['delta_bytes']) / len(new) if new else None)
                        details['engines'][engine] = detail
                    manifest['cases'].append(details)
                    save(output / 'manifest.json', manifest)
                    retained = output / 'cases' / case_id
                    retained.mkdir(parents=True)
                    for path in folder.iterdir():
                        shutil.copyfile(path, retained / path.name)
                    for round_index in range(config['warmup_rounds'] + config['formal_rounds']):
                        phase = 'warmup' if round_index < config['warmup_rounds'] else 'formal'
                        for operation_index, operation in enumerate(OPERATIONS):
                            order = ENGINES if (case_index + round_index + operation_index) % 2 == 0 else ENGINES[::-1]
                            for order_index, engine in enumerate(order):
                                destination = folder / f'{round_index}-{operation}-{engine}.out'
                                assert not destination.exists()
                                row = {'case': case_id, 'phase': phase, 'round_index': round_index, 'operation': operation, 'engine': engine, 'order_index': order_index, 'status': 'pending'}
                                run(command(engine, operation, destination), row=row)
                                actual = destination.read_bytes()  # All validation is after the timer stops.
                                if operation == 'signature':
                                    assert actual == sig.read_bytes(), 'Signature bytes differ'
                                elif operation == 'delta':
                                    assert delta_stats(actual, old, new) == {k: details['engines'][engine][k] for k in ('delta_bytes', 'copy_bytes', 'copy_commands', 'literal_commands', 'literal_bytes', 'delta_sha256')}
                                    assert actual == canonical[engine].read_bytes(), 'Generator is not deterministic'
                                    restored = folder / 'validation.out'
                                    opposite = executable['rdiff' if engine == 'moon' else 'moon']
                                    run([opposite, 'patch', folder / 'old.bin', destination, restored])
                                    assert restored.read_bytes() == new, 'Cross recovery differs'
                                    restored.unlink()
                                else:
                                    assert actual == new, 'Shared-delta patch differs'
                                row.update(status='validated', output_bytes=len(actual), output_sha256=sha(actual),
                                           input_old_sha256=details['old_sha256'], input_new_sha256=details['new_sha256'],
                                           shared_signature_sha256=details['signature_sha256'], shared_patch_delta_sha256=details['engines']['rdiff']['delta_sha256'])
                                destination.unlink()
                                save(output / 'measurements.json', rows)
                    details['times'] = {engine: {op: stats([r for r in rows if r['case'] == case_id and r['engine'] == engine and r['operation'] == op]) for op in OPERATIONS} for engine in ENGINES}
                    summaries.append(details)
                    save(output / 'summary.json', {'status': 'incomplete', 'cases': summaries, 'units': 'ns'})
                    print('Measured and validated:', case_id, flush=True)
            except BaseException:
                shutil.copytree(work, output / 'failure-files')
                raise
        assert len(rows) == len(manifest['cases']) * 9 * 3 * 2 == 540
        assert all(r['status'] == 'validated' for r in rows)
        manifest['status'] = 'passed'
        save(output / 'summary.json', {'status': 'passed', 'cases': summaries, 'units': 'ns', 'warmup_measurements': 120, 'formal_measurements': 420})
        print('Benchmark passed: 10 cases, 120 warmup + 420 formal operation measurements; no timing threshold.', flush=True)
    except BaseException as error:
        manifest.update(status='failed', error=repr(error))
        save(output / 'summary.json', {'status': 'failed', 'error': repr(error), 'completed_cases': summaries})
        raise
    finally:
        save(output / 'manifest.json', manifest)
        save(output / 'measurements.json', rows)


if __name__ == '__main__':
    main()
