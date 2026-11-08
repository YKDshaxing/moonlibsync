"""Required Linux Native cross-implementation matrix, deterministic plan, fail closed."""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from interop_cases import CONFIG, ROOT, make_cases, fingerprint
from interop_wire import inspect_delta, check_contents

UPSTREAM_SHA = 'e364852674780e43d578e4239128ff7014190ed3'
COMBINATIONS = ['/'.join((s, d, p)) for s in ('upstream', 'moonbit') for d in ('upstream', 'moonbit') for p in ('upstream', 'moonbit')]
A, B = 'upstream/moonbit/upstream', 'moonbit/upstream/moonbit'


class ComparisonMismatch(Exception):
    pass


def compare_bytes(expected, actual):
    # Full bytes, not length/hash or agreement between recovery implementations.
    if expected.read_bytes() != actual.read_bytes():
        raise ComparisonMismatch('INTEROP_COMPARE_MISMATCH: ' + str(actual))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def archive_failure(output, current, context, report, error):
    destination = output / 'failures' / (context.get('case', 'preflight') + '-' + uuid.uuid4().hex[:8])
    destination.mkdir(parents=True)
    if current is not None and current.is_dir():
        shutil.copytree(current, destination, dirs_exist_ok=True)
    if (output / 'commands.log').exists():
        shutil.copy2(output / 'commands.log', destination / 'commands.log')
    details = dict(context=context, error=repr(error), versions=report.get('versions'), source=report.get('source'))
    (destination / 'failure.json').write_text(json.dumps(details, indent=2), encoding='utf-8')
    manifest = {p.name: digest(p) for p in destination.iterdir() if p.is_file()}
    (destination / 'artifacts.sha256.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    report['failure_archive'] = str(destination)


@contextmanager
def scratch_directory(output, on_failure):
    with tempfile.TemporaryDirectory(prefix='run-', dir=output) as scratch:
        try:
            yield Path(scratch)
        except BaseException as error:
            # Archive while all case inputs and intermediate outputs still exist.
            on_failure(error)
            raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rdiff', type=Path, default=ROOT / '.toolchain/reference/build/rdiff')
    parser.add_argument('--output', type=Path, default=ROOT / '_build/interop')
    parser.add_argument('--compare', nargs=2, type=Path)
    args = parser.parse_args()
    if args.compare:
        try:
            compare_bytes(*args.compare)
            return 0
        except Exception as error:
            print(str(error), file=sys.stderr)
            return 1
    os.chdir(ROOT)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    log = (output / 'commands.log').open('w', encoding='utf-8')
    report = dict(format=1, status='running', target='Linux Native', groups=CONFIG['groups'],
                  planned_cases=CONFIG['expected_cases'], combinations={c: dict(expected=CONFIG['expected_cases'], success=0, failed=0) for c in COMBINATIONS},
                  signature_comparisons=0, byte_comparisons=0, copy_gates=[], failure_gates={},
                  random=CONFIG['random'], exhaustive=dict(**CONFIG['exhaustive'], words=13, ordered_pairs=169, parameter_cases=338), cases=[])
    current, context = None, {}

    def record(value):
        log.write(json.dumps(value, ensure_ascii=True) + '\n')
        log.flush()

    def run(argv, cwd=ROOT, allow_failure=False, timeout=20):
        argv = list(map(str, argv))
        started = time.monotonic()
        try:
            result = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=timeout)
            record(dict(kind='command', argv=argv, cwd=str(cwd), exit_code=result.returncode,
                        stdout=result.stdout, stderr=result.stderr, elapsed=time.monotonic()-started))
        except BaseException as error:
            partial = {}
            if isinstance(error, subprocess.TimeoutExpired):
                for stream in ('stdout', 'stderr'):
                    value = getattr(error, stream, None)
                    partial[stream] = value.decode('utf-8', errors='replace') if isinstance(value, bytes) else value
            record(dict(kind='command', argv=argv, cwd=str(cwd), error=repr(error), **partial))
            raise
        if result.returncode and not allow_failure:
            raise RuntimeError(f'Command exit={result.returncode}: {argv}; {result.stderr[-2000:]}')
        return result

    def compare(expected, actual):
        try:
            compare_bytes(expected, actual)
            record(dict(kind='full-byte-comparison', expected=str(expected), actual=str(actual), exit_code=0))
        except BaseException:
            record(dict(kind='full-byte-comparison', expected=str(expected), actual=str(actual), exit_code=1))
            raise

    def git(*argv, cwd=ROOT):
        return run(['git', '-c', f'safe.directory={cwd.as_posix()}', *argv], cwd=cwd).stdout.strip()

    try:
        rdiff = args.rdiff.resolve()
        if not rdiff.is_file():
            raise FileNotFoundError('INTEROP_REFERENCE_MISSING: ' + str(rdiff))
        if rdiff != (ROOT / '.toolchain/reference/build/rdiff').resolve():
            raise ValueError('INTEROP_REFERENCE_IDENTITY: unregistered reference path')
        source = ROOT / '.toolchain/reference/source'
        assert git('rev-parse', 'HEAD', cwd=source) == UPSTREAM_SHA
        git('diff', '--exit-code', 'HEAD', '--', cwd=source)
        assert not git('ls-files', '--others', '--exclude-standard', cwd=source)
        assert 'src/blake2/blake2b-ref.c' in (ROOT / '.toolchain/reference/build/compile_commands.json').read_text()
        version = run([rdiff, '--version']).stdout.strip()
        assert version.startswith('rdiff (librsync 2.3.4)')
        lock = json.loads((ROOT / 'toolchain.lock.json').read_text(encoding='utf-8'))
        moonc = run(['moonc', '-v']).stdout.strip()
        assert moonc == lock['moonc']
        report['versions'] = dict(moonc=moonc, moon=run(['moon', 'version', '--all']).stdout,
                                  python=sys.version, environment=platform.platform(), upstream=version,
                                  upstream_sha=UPSTREAM_SHA, reference_binary_sha256=digest(rdiff))
        dirty = git('status', '--porcelain', '--untracked-files=all')
        files = git('ls-files', '-co', '--exclude-standard').splitlines()
        tree = hashlib.sha256()
        for name in sorted(set(files)):
            path = ROOT / name
            if path.is_file():
                tree.update(name.encode() + b'\0' + path.read_bytes())
        report['source'] = dict(head=git('rev-parse', 'HEAD'), dirty=bool(dirty), status=dirty, content_sha256=tree.hexdigest())
        ci_sha = os.environ.get('GITHUB_SHA')
        if ci_sha:
            assert report['source']['head'] == ci_sha and not dirty, 'CI source must be clean and match GITHUB_SHA'
        print(f'Interop source: head={report["source"]["head"]} dirty={bool(dirty)}', flush=True)
        cases = make_cases()
        planned = fingerprint(cases)
        assert planned == (ROOT / 'tests/interop/plan.sha256').read_text().strip()
        report['plan_sha256'] = planned
        report['independent_input_pairs'] = len({(c['old'], c['new']) for c in cases})
        report['parameter_cases'] = len(cases)
        run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests/interop', '-p', 'test_*.py'])
        run([sys.executable, 'scripts/verify_fixtures.py'])
        if not os.environ.get('MOONLIBSYNC_OFFLINE_INDEX'):
            run(['moon', 'update'], timeout=120)
        build = os.environ.get('MOONLIBSYNC_BUILD_DIR', '_build')
        run(['moon', '--target-dir', build, 'build', 'probes/signature', '--target', 'native'], timeout=120)
        run([sys.executable, 'scripts/verify_dependencies.py'])
        exe = ROOT / build / 'native/debug/build/probes/signature/signature.exe'
        assert exe.is_file()
        report['versions']['adapter_sha256'] = digest(exe)
        with scratch_directory(output, lambda error: archive_failure(output, current, context, report, error)) as scratch:
            scratch = Path(scratch)
            for ordinal, c in enumerate(cases):
                current = scratch / c['id']
                current.mkdir()
                (current / 'old.bin').write_bytes(c['old'])
                (current / 'new.bin').write_bytes(c['new'])
                metadata = {k: v for k, v in c.items() if k not in ('old', 'new')}
                metadata.update(old_bytes=len(c['old']), new_bytes=len(c['new']), old_sha256=digest(current/'old.bin'), new_sha256=digest(current/'new.bin'))
                (current / 'case.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
                context = dict(case=c['id'], phase='signature')
                run([rdiff, '-H', 'blake2', '-R', 'rabinkarp', '-b', c['block'], '-S', c['strong'], 'signature', 'old.bin', 'upstream.sig'], current)
                run([exe, current/'old.bin', current/'moonbit.sig', c['block'], c['strong']], current)
                compare(current/'upstream.sig', current/'moonbit.sig')
                report['signature_comparisons'] += 1
                stats = {}
                for s in ('upstream', 'moonbit'):
                    for d in ('upstream', 'moonbit'):
                        context = dict(case=c['id'], phase='delta', signature=s, delta=d)
                        delta = current / f'{s}-{d}.delta'
                        if d == 'upstream':
                            run([rdiff, 'delta', f'{s}.sig', 'new.bin', delta], current)
                        else:
                            # Generation gets only signature, new file and fresh output.
                            run([exe, 'delta', current/f'{s}.sig', current/'new.bin', delta], current)
                        commands = inspect_delta(delta.read_bytes())
                        copied = check_contents(commands, c['old'], c['new'])
                        stats[f'{s}/{d}'] = dict(bytes=delta.stat().st_size, copy_bytes=copied, commands=len(commands))
                        if d == 'moonbit' and c['group'] == 'reuse':
                            assert copied >= c['copy_floor']
                            if c['id'] == 'reuse-insert':
                                assert delta.stat().st_size < CONFIG['reuse']['maximum_delta_exclusive']
                                assert len(c['new']) == CONFIG['reuse']['new_bytes']
                            report['copy_gates'].append(dict(case=c['id'], signature=s, delta_bytes=delta.stat().st_size, new_bytes=len(c['new']), copy_bytes=copied, minimum=c['copy_floor'], passed=True))
                        for p in ('upstream', 'moonbit'):
                            combination = '/'.join((s, d, p))
                            context = dict(case=c['id'], phase='patch', combination=combination)
                            restored = current / f'{s}-{d}-{p}.restored'
                            try:
                                run([rdiff, 'patch', 'old.bin', delta, restored] if p == 'upstream' else [exe, 'patch', current/'old.bin', delta, restored], current)
                                compare(current/'new.bin', restored)
                            except BaseException:
                                report['combinations'][combination]['failed'] += 1
                                raise
                            report['combinations'][combination]['success'] += 1
                            report['byte_comparisons'] += 1
                report['cases'].append(dict(**metadata, deltas=stats))
                if (ordinal + 1) % 50 == 0:
                    print(f'Interop progress: {ordinal+1}/{len(cases)} parameter cases, eight combinations each', flush=True)
            context = dict(phase='failure-gates')
            missing = run([sys.executable, ROOT/'scripts/interop.py', '--rdiff', scratch/'does-not-exist-rdiff', '--output', scratch/'missing-tool-report'], allow_failure=True)
            assert missing.returncode == 1 and 'INTEROP_REFERENCE_MISSING' in missing.stderr
            report['failure_gates']['missing_reference'] = dict(passed=True, observed_exit=missing.returncode)
            bad = scratch/'corrupted.restored'
            value = (current/'upstream-upstream-upstream.restored').read_bytes()
            bad.write_bytes((bytes([value[0] ^ 1]) + value[1:]) if value else b'\xff')
            mismatch = run([sys.executable, ROOT/'scripts/interop.py', '--compare', current/'new.bin', bad], allow_failure=True)
            assert mismatch.returncode == 1 and 'INTEROP_COMPARE_MISMATCH' in mismatch.stderr
            report['failure_gates']['comparison_failure'] = dict(passed=True, observed_exit=mismatch.returncode)
            run([exe, 'patch', current/'old.bin', current/'upstream-upstream.delta', scratch/'normal-after-gates.bin'])
            compare(current/'new.bin', scratch/'normal-after-gates.bin')
            report['failure_gates']['normal_after_gates'] = dict(passed=True, additional_restore_count=1)
        current = None
        assert len(report['cases']) == CONFIG['expected_cases']
        assert all(v['success'] == v['expected'] and not v['failed'] for v in report['combinations'].values())
        assert report['signature_comparisons'] == len(cases)
        report['status'] = 'passed'
        report['algorithm_failure_samples'] = 0
        print(f'Interop passed: {report["independent_input_pairs"]} independent pairs; {len(cases)} parameter cases; {report["byte_comparisons"]} eight-combination restores; chains A/B each {len(cases)}.', flush=True)
        print('No algorithm failure samples found requiring archive.', flush=True)
        return_code = 0
    except BaseException as error:
        report['status'] = 'failed'
        report['error'] = repr(error)
        report['failure_context'] = context
        if "failure_archive" not in report:
            archive_failure(output, current, context, report, error)
        print(str(error), file=sys.stderr)
        return_code = 1
    finally:
        for value in report['combinations'].values():
            value['not_executed'] = value['expected'] - value['success'] - value['failed']
        report['chain_A'] = report['combinations'][A].copy()
        report['chain_B'] = report['combinations'][B].copy()
        report['completed_parameter_cases'] = len(report['cases'])
        report['completed_groups'] = {group: sum(c['group'] == group for c in report['cases']) for group in CONFIG['groups']}
        random_cases = [c for c in report['cases'] if c['group'] == 'random']
        report['completed_random_samples'] = len(random_cases)
        report['signature_byte_comparison'] = dict(expected=CONFIG['expected_cases'], success=report['signature_comparisons'], all_passed=report['status']=='passed')
        report['restoration_byte_comparison'] = dict(expected=CONFIG['expected_cases']*8, success=report['byte_comparisons'], all_passed=report['status']=='passed')
        log.close()
        payload = (json.dumps(report, indent=2, sort_keys=True) + '\n').encode()
        (output/'report.json').write_bytes(payload)
        (output/'report.sha256').write_text(hashlib.sha256(payload).hexdigest()+'\n', encoding='utf-8')
        print('Report:', output/'report.json', 'sha256='+hashlib.sha256(payload).hexdigest(), flush=True)
    return return_code


if __name__ == '__main__':
    sys.exit(main())
