"""Audit a real moon package and consume it outside the repository.

Never uploads. --registry verifies a published version without workspace/path
replacement; --clean rebuilds a fresh source checkout with a fresh toolchain.
"""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
import zipfile

from interface_guard import snapshot, unchanged
from interop_wire import inspect_delta, check_contents

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / os.environ.get('MOONLIBSYNC_RELEASE_DIR', '_build/release-0.1.0')
MODULE = 'YKDshaxing/moonlibsync'
VERSION = '0.1.0'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8', newline='\n')


def git(*args):
    return ['git', '-c', f'safe.directory={ROOT.as_posix()}', *args]


def source():
    return {'sha': subprocess.check_output(git('rev-parse', 'HEAD'), cwd=ROOT, text=True).strip(),
            'dirty': bool(subprocess.check_output(git('status', '--porcelain'), cwd=ROOT, text=True).strip())}


def run(command, label, cwd=ROOT, env=None):
    result = subprocess.run(list(map(str, command)), cwd=cwd, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding='utf-8', errors='replace', timeout=600)
    (OUT / 'logs' / (label + '.log')).write_text(result.stdout, encoding='utf-8')
    with (OUT / 'logs/commands.jsonl').open('a', encoding='utf-8') as log:
        log.write(json.dumps({'time_utc': datetime.now(timezone.utc).isoformat(),
                             'command': list(map(str, command)), 'cwd': str(cwd),
                             'exit_code': result.returncode, 'log': label + '.log'}) + '\n')
    if result.returncode:
        print(result.stdout, flush=True)
    result.check_returncode()
    return result.stdout


def environment(folder):
    if os.name == 'nt':
        import ctypes
        fs = ctypes.create_unicode_buffer(128)
        ok = ctypes.windll.kernel32.GetVolumeInformationW(str(folder.anchor), None, 0, None, None, None, fs, len(fs))
        assert ok, 'Unable to identify output filesystem'
        filesystem = fs.value
    else:
        filesystem = subprocess.check_output(['findmnt', '-T', str(folder), '-o', 'FSTYPE', '-n'], text=True).strip()
    return {'platform': platform.platform(), 'python': sys.version, 'filesystem': filesystem, 'temporary_directory': str(folder)}


def no_parent_workspace(folder):
    for parent in (folder, *folder.parents):
        assert not (parent / 'moon.work').exists() and not (parent / 'moon.work.json').exists(), str(parent)


def members(archive):
    result = {}
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        seen = set()
        for item in z.infolist():
            name = item.filename
            assert item.orig_filename == name, 'ZIP filename normalization: ' + item.orig_filename
            path = PurePosixPath(name)
            assert name and '\\' not in name and not path.is_absolute() and '..' not in path.parts and ':' not in name
            assert name.casefold() not in seen, 'Duplicate/aliased member: ' + name
            seen.add(name.casefold())
            assert not stat.S_ISLNK(item.external_attr >> 16), 'Link member: ' + name
            if not item.is_dir():
                result[name] = z.read(name)
    return result


def expected_paths():
    files = subprocess.check_output(git('ls-files', '-co', '--exclude-standard', '-z'), cwd=ROOT).decode().split('\0')
    return {n for n in files if n and (ROOT / n).is_file() and
            (n == '.moonignore' or not any(p.startswith('.') for p in PurePosixPath(n).parts)) and
            not any(p in ('_build', 'target', '__pycache__') for p in PurePosixPath(n).parts) and
            not n.endswith(('.pyc', '.tmp', '.log'))}


def license_scope(name):
    if name.startswith('licenses/MoonBit-core-'):
        return 'MoonBit core original Apache-2.0 license/NOTICE; retained unchanged'
    if name == 'licenses/Apache-2.0.txt':
        return 'Complete Apache-2.0 license text for documented third-party sources'
    if name in ('COPYING', 'COPYING.LESSER'):
        return 'Complete GNU GPL/LGPL license text; verbatim terms retained'
    if name in ('LICENSE', 'SOURCES.md', 'THIRD_PARTY_NOTICES.md'):
        return 'Project notice and file-level original/ported/third-party attribution index'
    if name.startswith('tests/fixtures/'):
        return 'Project synthetic inputs, fixed-rdiff generated outputs or handwritten opcodes; retained with manifests and source notices'
    return 'Project LGPL-2.1-or-later source/tool/document or documented LGPL port; original upstream notices retained; see SOURCES.md'


def audit_package():
    before = snapshot(ROOT)
    run(['moon', 'package', '--list', '--frozen'], 'package-list')
    run(['moon', 'package', '--frozen'], 'package')
    unchanged(ROOT, before)
    archive = ROOT / '_build/publish/YKDshaxing-moonlibsync-0.1.0.zip'
    actual = members(archive)
    assert set(actual) == expected_paths(), {'unexpected': sorted(set(actual) - expected_paths()), 'missing': sorted(expected_paths() - set(actual))}
    for name, data in actual.items():
        assert data == (ROOT / name).read_bytes(), 'Source bytes differ: ' + name
        assert not any(part in ('.toolchain', '.mooncakes', '.git', '_build', '__pycache__') for part in PurePosixPath(name).parts)
    required = {'moon.mod', 'moon.pkg', 'pkg.generated.mbti', 'cmd/moonlibsync/main.mbt',
                'cmd/moonlibsync/moon.pkg', 'examples/basic/main.mbt', 'examples/basic/moon.pkg',
                'COPYING', 'COPYING.LESSER', 'LICENSE', 'SOURCES.md', 'THIRD_PARTY_NOTICES.md',
                'licenses/Apache-2.0.txt', 'licenses/MoonBit-core-LICENSE', 'licenses/MoonBit-core-NOTICE',
                'tests/fixtures/manifest.json', 'tests/fixtures/opcodes/vectors.json', 'scripts/verify_fixtures.py'}
    assert required <= actual.keys()
    metadata = actual['moon.mod'].decode()
    for text in ('name = "YKDshaxing/moonlibsync"', 'version = "0.1.0"', 'license = "LGPL-2.1-or-later"', 'moonbitstack/mooncrypt@0.4.5'):
        assert text in metadata
    for name in ('COPYING.LESSER', 'COPYING', 'licenses/Apache-2.0.txt'):
        assert len(actual[name]) > 10000, name
    current_source = source()
    git_blob_verified = False
    if not current_source['dirty']:
        names = sorted(actual)
        result = subprocess.run(git('cat-file', '--batch'), cwd=ROOT,
                                input=''.join('HEAD:' + name + '\n' for name in names).encode(),
                                stdout=subprocess.PIPE, check=True).stdout
        position = 0
        for name in names:
            end = result.index(b'\n', position)
            header = result[position:end].split()
            assert len(header) == 3 and header[1] == b'blob', name
            size = int(header[2]); position = end + 1
            assert result[position:position + size] == actual[name], 'Git blob bytes differ: ' + name
            position += size + 1
        assert position == len(result)
        git_blob_verified = True
    audit = {'status': 'passed', 'source': current_source, 'git_blob_byte_identity_verified': git_blob_verified, 'archive': archive.name,
             'bytes': archive.stat().st_size, 'sha256': digest(archive.read_bytes()),
             'member_count': len(actual), 'members': {n: {'bytes': len(d), 'sha256': digest(d), 'license_scope': license_scope(n)} for n, d in sorted(actual.items())},
             'license_audit': 'Project LGPL-2.1-or-later, upstream copyright/port notices, GPL/LGPL texts, Apache-2.0 and core LICENSE/NOTICE present and byte-identical to reviewed source; dependency licenses remain with their sources.',
             'development_policy': 'Complete tests, generated fixture constants and all required fixture/tool/source files retained together; no cached binaries or reports.'}
    shutil.copyfile(archive, OUT / archive.name)
    save(OUT / 'audit.json', audit)
    return actual, audit


def extract(actual, destination):
    destination.mkdir()
    for name, data in actual.items():
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def unchanged_bytes(actual, folder):
    assert all((folder / name).read_bytes() == data for name, data in actual.items()), 'Build modified audited package source'


def make_consumer(folder):
    folder.mkdir()
    (folder / 'moon.mod').write_text('name = "release/consumer"\nversion = "0.0.0"\nimport { "YKDshaxing/moonlibsync@0.1.0", }\n', encoding='utf-8', newline='\n')
    (folder / 'moon.pkg').write_text('import { "YKDshaxing/moonlibsync" @lib, }\npkgtype(kind: "executable")\n', encoding='utf-8', newline='\n')
    shutil.copyfile(ROOT / 'tests/release-consumer/main.mbt.txt', folder / 'main.mbt')


def consumer(folder, kind, env=None):
    results = []
    old = bytes(0x10 + i // 2048 for i in range(16384))
    new = old[:4113] + bytes(range(128, 192)) + old[4177:]
    for target in ('native', 'js', 'wasm-gc'):
        text = run(['moon', 'run', str(folder), '--target', target], kind + '-' + target, cwd=folder, env=env)
        assert text.count('consumer_defaults_and_error=passed') == 1
        lines = re.findall(r'^consumer_case=(same|small) signature_bytes=(\d+) delta_hex=([0-9a-f]+)$', text, re.M)
        assert len(lines) == 2 and {line[0] for line in lines} == {'same', 'small'}
        for name, signature_size, encoded in lines:
            delta = bytes.fromhex(encoded)
            expected = old if name == 'same' else new
            copied = check_contents(inspect_delta(delta), old, expected)
            assert int(signature_size) == 300 and copied >= (16384 if name == 'same' else 14336) and len(delta) < len(expected)
            results.append({'target': target, 'case': name, 'signature_bytes': int(signature_size), 'delta_bytes': len(delta), 'copy_bytes': copied, 'equal': True, 'public_defaults_and_error': True})
    return results


def cli_flow(folder, label, env=None):
    build_output = run(['moon', '--target-dir', str(folder / '_build'), 'build', 'cmd/moonlibsync', '--target', 'native'], label + '-build', cwd=folder, env=env)
    paths = re.findall(r'^\s*YKDshaxing/moonlibsync/cmd/moonlibsync\s+native\s+(.+\.exe)\s*$', build_output, re.M)
    assert len(paths) == 1, 'Missing actual product artifact path'
    exe = Path(paths[0].strip()).resolve()
    assert exe.is_file() and exe.is_relative_to((folder / '_build').resolve())
    work = folder.parent / (label + '-files')
    work.mkdir()
    old = bytes(0x10 + i // 2048 for i in range(16384))
    new = old[:4113] + bytes(range(128, 192)) + old[4177:]
    (work / 'old').write_bytes(old); (work / 'new').write_bytes(new)
    for op, args in [('signature', ['old', 'sig']), ('delta', ['sig', 'new', 'delta']), ('patch', ['old', 'delta', 'restored'])]:
        run([exe, op, *[work / arg for arg in args]], label + '-' + op, cwd=folder, env=env)
    assert (work / 'restored').read_bytes() == new
    copied = check_contents(inspect_delta((work / 'delta').read_bytes()), old, new)
    assert copied >= 14336
    version = run([exe, '--version'], label + '-version', cwd=folder, env=env).strip()
    assert version == 'MoonLibSync 0.1.0'
    return {'kind': label, 'path': str(exe), 'sha256': digest(exe.read_bytes()), 'source_build': True, 'version': version, 'restored_equal': True, 'copy_bytes': copied}


def candidate(actual):
    with tempfile.TemporaryDirectory(prefix='moonlibsync-package-') as directory:
        top = Path(directory).resolve()
        no_parent_workspace(top)
        assert not top.is_relative_to(ROOT)
        package = top / 'package'
        extract(actual, package)
        client = top / 'consumer'
        make_consumer(client)
        stage = top / 'stage-a-consumer'
        make_consumer(stage)
        (stage / 'moon.mod').write_text('name = "stage/a-consumer"\nversion = "0.0.0"\nimport { "YKDshaxing/moonlibsync@0.1.0", }\n', encoding='utf-8', newline='\n')
        shutil.copyfile(ROOT / 'tests/stage-a/consumer.mbt.txt', stage / 'main.mbt')
        (top / 'moon.work').write_text('members = ["./package", "./consumer", "./stage-a-consumer"]\n', encoding='utf-8', newline='\n')
        if not os.environ.get('MOONLIBSYNC_OFFLINE_INDEX'):
            run(['moon', 'update'], 'candidate-update', cwd=client)
        results = consumer(client, 'candidate')
        # Build the delivered example and product CLI from the extracted archive.
        for target in ('native', 'js', 'wasm-gc'):
            run(['moon', 'run', 'examples/basic', '--target', target], 'candidate-basic-' + target, cwd=package)
        cli = cli_flow(package, 'candidate-cli')
        from stage_a_candidate import validate
        stage_results = validate(stage, package, Path(cli['path']), run, OUT)
        unchanged_bytes(actual, package)
        return {'status': 'passed', 'kind': 'candidate-package-local-workspace-consumption', 'outside_repository': True, 'dependency_refresh': 'pinned cached index' if os.environ.get('MOONLIBSYNC_OFFLINE_INDEX') else 'moon update',
                'workspace_members': ['package', 'consumer', 'stage-a-consumer'], 'stage_a': stage_results, 'environment': environment(top), 'results': results, 'cli': cli, 'audited_source_unchanged': True}


def clean_source(actual):
    with tempfile.TemporaryDirectory(prefix='moonlibsync-clean-') as directory:
        top = Path(directory).resolve(); no_parent_workspace(top)
        fresh = top / 'source'
        run(['git', '-c', f'safe.directory={ROOT.as_posix()}/.git', '-c', f'safe.directory={ROOT.as_posix()}', 'clone', '--quiet', '--no-hardlinks', '--local', ROOT, fresh], 'clean-clone')
        # Pre-commit runs overlay the exact candidate files; final runs use clean HEAD.
        for name, data in actual.items():
            path = fresh / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        assert not (fresh / '_build').exists()
        run([sys.executable, fresh / 'scripts/install_toolchain.py'], 'clean-install', cwd=fresh)
        home = fresh / '.toolchain/selected'
        env = dict(os.environ, MOON_HOME=str(home), PATH=str(home / 'bin') + os.pathsep + os.environ['PATH'])
        env.pop('MOONLIBSYNC_BUILD_DIR', None)
        run(['moon', 'update'], 'clean-update', cwd=fresh, env=env)
        for target in ('native', 'js', 'wasm-gc'):
            run(['moon', 'run', 'examples/basic', '--target', target], 'clean-example-' + target, cwd=fresh, env=env)
        cli = cli_flow(fresh, 'clean-cli', env)
        unchanged_bytes(actual, fresh)
        return {'status': 'passed', 'fresh_toolchain_install': True, 'fresh_build_outputs': True, 'source_unchanged': True, 'environment': environment(top), 'cli': cli}


def registry(actual):
    with tempfile.TemporaryDirectory(prefix='moonlibsync-registry-') as directory:
        top = Path(directory).resolve(); no_parent_workspace(top)
        client = top / 'consumer'; make_consumer(client)
        # Fresh toolchain home also gives a genuinely empty public-registry cache.
        bootstrap = top / 'bootstrap'
        (bootstrap / 'scripts').mkdir(parents=True)
        shutil.copyfile(ROOT / 'scripts/install_toolchain.py', bootstrap / 'scripts/install_toolchain.py')
        shutil.copyfile(ROOT / 'toolchain.lock.json', bootstrap / 'toolchain.lock.json')
        run([sys.executable, bootstrap / 'scripts/install_toolchain.py'], 'registry-install-toolchain', cwd=bootstrap)
        home = bootstrap / '.toolchain/selected'
        env = {k: v for k, v in os.environ.items() if not k.startswith('MOON')}
        env.update(MOON_HOME=str(home), PATH=str(home / 'bin') + os.pathsep + os.environ['PATH'])
        cached = home / 'registry/cache/YKDshaxing/moonlibsync/0.1.0.zip'
        assert not cached.exists(), 'Registry cache must be empty before actual fetch'
        run(['moon', 'update'], 'registry-update', cwd=client, env=env)
        results = consumer(client, 'registry', env)
        run(['moon', 'view', 'YKDshaxing/moonlibsync@0.1.0', '--json'], 'registry-live-version', cwd=client, env=env)
        assert cached.is_file(), 'No registry archive fetched'
        fetched = members(cached)
        assert fetched == actual, 'Registry member/content difference'
        shutil.copyfile(cached, OUT / 'registry-download-original.zip')
        module = client / '.mooncakes/YKDshaxing/moonlibsync'
        assert module.is_dir()
        metadata = (module / 'moon.mod').read_text(encoding='utf-8')
        assert 'version = "0.1.0"' in metadata and 'name = "YKDshaxing/moonlibsync"' in metadata
        unchanged_bytes(actual, module)
        installed = {p.relative_to(module).as_posix() for p in module.rglob('*') if p.is_file()}
        assert installed == set(actual), {'extra': sorted(installed - actual.keys()), 'missing': sorted(actual.keys() - installed)}
        saved = OUT / 'registry-module'
        if saved.exists():
            raise SystemExit('Registry evidence already exists; do not overwrite')
        shutil.copytree(module, saved)
        # Source build from the registry-downloaded package, no precompiled binary claim.
        cli = cli_flow(module, 'registry-source-cli', env)
        unchanged_bytes(actual, module)
        closure = []
        for mod in (client / '.mooncakes').glob('*/*/moon.mod'):
            closure.append({'path': str(mod.parent), 'metadata_sha256': digest(mod.read_bytes()), 'metadata': mod.read_text(encoding='utf-8')})
        return {'status': 'passed', 'kind': 'public-registry-no-local-replacement', 'resolved_version': '0.1.0',
                'module_path': str(module), 'environment': environment(top), 'no_workspace': True, 'fresh_registry_home': str(home),
                'public_registry': 'https://mooncakes.io', 'downloaded_archive_sha256': digest(cached.read_bytes()),
                'downloaded_archive_bytes': cached.stat().st_size, 'results': results, 'closure': closure,
                'source_and_metadata_match_candidate': True, 'cli': cli}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clean', action='store_true')
    parser.add_argument('--registry', action='store_true')
    args = parser.parse_args()
    os.chdir(ROOT)
    (OUT / 'logs').mkdir(parents=True, exist_ok=True)
    report = {'publication_status': 'registry-verification-in-progress' if args.registry else 'unpublished-development-snapshot', 'source': source(), 'status': 'incomplete'}
    save(OUT / 'report.json', report)
    try:
        actual, audit = audit_package()
        report['audit'] = {'sha256': audit['sha256'], 'members': audit['member_count'], 'bytes': audit['bytes']}
        if args.registry:
            report['registry'] = registry(actual)
            report['publication_status'] = 'published-and-consumer-verified'
        else:
            report['candidate'] = candidate(actual)
            if args.clean:
                report['clean_source'] = clean_source(actual)
        report['status'] = 'passed'
    except BaseException as error:
        report.update(status='failed', error=repr(error))
        raise
    finally:
        save(OUT / 'report.json', report)
    print(f'Release checks passed: {report["publication_status"]}; real package audit and public API evidence saved to {OUT}')


if __name__ == '__main__':
    main()
