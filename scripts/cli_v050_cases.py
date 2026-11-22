"""0.5.0 CLI integration cases: single-file .mbundle/.mbundle.gz archives, --exclude, dir-verify, and --progress."""
import hashlib
import json
from pathlib import Path
import subprocess


def _snapshot(path):
    path = Path(path)
    if path.is_symlink():
        return ('symlink', str(path.readlink()))
    if not path.exists():
        return ('absent',)
    if path.is_dir():
        return ('directory', sorted(p.name for p in path.iterdir()))
    h = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    st = path.stat()
    return ('file', st.st_size, h.hexdigest(), st.st_ino, st.st_nlink)


def _temps(root):
    return {str(p.relative_to(root)) for p in root.rglob('.moonlibsync-*.tmp')}


def exercise(root, case, report, links):
    exe = report['executable']

    def run(name, args, expected=0, **kw):
        result = case('v050/' + name, args, expected, **kw)
        report['cases'][-1]['v050_added'] = True
        return result

    def inspect_run(name, args, expected=0, **kw):
        before_entries = {str(p.relative_to(root)) for p in root.rglob('*')}
        result = run(name, args, expected, text=(expected == 0), **kw)
        after_entries = {str(p.relative_to(root)) for p in root.rglob('*')}
        assert after_entries == before_entries, name
        return result

    def raw_run(name, args, expected=0, watch=(), output=None, read_only=False):
        protected = list(dict.fromkeys([Path(p) for p in watch] + ([Path(output)] if output else [])))
        before = {str(p): _snapshot(p) for p in protected}
        before_entries = {str(p.relative_to(root)) for p in root.rglob('*')} if read_only else None
        pending = _temps(root)
        p = subprocess.run([str(exe), *map(str, args)], cwd=root, capture_output=True, timeout=120)
        assert p.returncode == expected, (name, p.returncode, expected, p.stdout, p.stderr)
        assert b'backtrace' not in p.stderr.lower() and b'panic' not in p.stderr.lower(), (name, p.stderr)
        for path, value in before.items():
            if expected == 0 and output and path == str(output):
                continue
            assert _snapshot(path) == value, ('changed protected input/output', name, path)
        if read_only:
            after_entries = {str(p.relative_to(root)) for p in root.rglob('*')}
            assert after_entries == before_entries, ('read-only command modified filesystem', name)
        assert _temps(root) == pending, ('leaked or deleted temporary', name, _temps(root), pending)
        report['cases'].append(dict(
            name='v050/' + name,
            expected_exit=expected,
            actual_exit=p.returncode,
            passed=True,
            inputs_preserved=True,
            owned_temporary_clean=True,
            v050_added=True,
        ))
        return p

    # 1. Build realistic multi-file basis & target trees with excluded subtrees/patterns.
    b_dir = root / 'v050-basis'
    t_dir = root / 'v050-target'
    (b_dir / 'sub').mkdir(parents=True)
    (t_dir / 'sub').mkdir(parents=True)
    (t_dir / '.git' / 'objects').mkdir(parents=True)
    (t_dir / 'node_modules' / 'pkg').mkdir(parents=True)
    (t_dir / 'dist').mkdir(parents=True)

    big_old = bytes(((i * 59 + 13 + (i // 1024) * 17) % 256) for i in range(98304))
    big_new = big_old[:49152] + b'V050-ARCHIVE-STREAM-PATCH' + big_old[49177:]

    (b_dir / 'same.bin').write_bytes(b'identical-050')
    (b_dir / 'sub' / 'big.bin').write_bytes(big_old)
    (b_dir / 'tiny.bin').write_bytes(b'aa')
    (b_dir / 'removed.bin').write_bytes(b'stay-in-basis')

    (t_dir / 'same.bin').write_bytes(b'identical-050')
    (t_dir / 'sub' / 'big.bin').write_bytes(big_new)
    (t_dir / 'tiny.bin').write_bytes(b'bbbbbbbb')
    (t_dir / 'added.bin').write_bytes(b'brand-new-050')
    (t_dir / 'zero.bin').write_bytes(b'')
    # Excluded files & subtrees in target
    (t_dir / '.git' / 'HEAD').write_bytes(b'ref: refs/heads/main\n')
    (t_dir / 'node_modules' / 'pkg' / 'index.js').write_bytes(b'module.exports = 1;\n')
    (t_dir / 'sub' / 'trace.log').write_bytes(b'debug line\n')
    (t_dir / 'dist' / 'app.js').write_bytes(b'compiled\n')
    if links:
        # Symlink inside excluded directory must be pruned before symlink check!
        (t_dir / '.git' / 'sym-inside-excluded').symlink_to(b_dir / 'same.bin')

    excludes = [
        '--exclude', '.git',
        '--exclude', 'node_modules',
        '--exclude', '*.log',
        '--exclude', 'dist/*',
    ]

    b_snap = root / 'v050-basis.snap.json'
    t_snap = root / 'v050-target.snap.json'
    sig_dir = root / 'v050-sigs'
    arch_plain = root / 'v050-bundle.mbundle'
    arch_gz = root / 'v050-bundle.mbundle.gz'
    arch_buf = root / 'v050-bundle-buf.mbundle.gz'
    out_plain = root / 'v050-out-plain'
    out_gz = root / 'v050-out-gz'
    out_buf = root / 'v050-out-buf'

    run('snap/basis', ['dir-snapshot', b_dir, b_snap], output=b_snap)
    run('snap/target-exclude', ['dir-snapshot', t_dir, t_snap, *excludes], output=t_snap)
    t_snap_obj = json.loads(t_snap.read_bytes())
    assert [e['path'] for e in t_snap_obj['entries']] == [
        'added.bin', 'same.bin', 'sub/big.bin', 'tiny.bin', 'zero.bin',
    ]

    run('sigs/basis', ['dir-signatures', b_dir, b_snap, sig_dir, '--block-size', 'auto', '--streaming'], watch=[b_snap], output=sig_dir)

    # 2. Single-file --archive and --archive --gzip pack + apply roundtrips.
    run('archive/pack-plain', ['dir-pack', b_snap, sig_dir, t_dir, arch_plain, '--archive', '--streaming', *excludes], watch=[b_snap], output=arch_plain)
    assert arch_plain.read_bytes()[:8] == b'MLSBDL01'
    run('archive/pack-plain-no-overwrite', ['dir-pack', b_snap, sig_dir, t_dir, arch_plain, '--archive', *excludes], 1, watch=[b_snap, arch_plain], output=arch_plain, contains='exists')

    run('archive/pack-gzip', ['dir-pack', b_snap, sig_dir, t_dir, arch_gz, '--archive', '--gzip', '--streaming', *excludes], watch=[b_snap], output=arch_gz)
    assert arch_gz.read_bytes()[:2] == b'\x1f\x8b'
    assert arch_gz.stat().st_size < arch_plain.stat().st_size

    # Order independence of --gzip --archive & buffered mode parity
    run('archive/pack-gzip-buffered', ['dir-pack', b_snap, sig_dir, t_dir, arch_buf, '--gzip', '--archive', *excludes], watch=[b_snap], output=arch_buf)

    run('archive/apply-plain', ['dir-apply', b_dir, arch_plain, out_plain, '--archive', '--streaming'], watch=[arch_plain], output=out_plain)
    run('archive/apply-gzip', ['dir-apply', b_dir, arch_gz, out_gz, '--archive', '--gzip', '--streaming'], watch=[arch_gz], output=out_gz)
    run('archive/apply-gzip-buffered', ['dir-apply', b_dir, arch_buf, out_buf, '--archive', '--gzip'], watch=[arch_buf], output=out_buf)

    for restored in (out_plain, out_gz, out_buf):
        assert not (restored / 'payloads').exists()
        assert not (restored / 'bundle.json').exists()
        assert not (restored / '.git').exists()
        assert not (restored / 'node_modules').exists()
        assert not (restored / 'sub' / 'trace.log').exists()
        assert not (restored / 'dist').exists()
        assert (restored / 'zero.bin').read_bytes() == b''
        assert (restored / 'sub' / 'big.bin').read_bytes() == big_new
    # BASIS_DIR never modified
    assert (b_dir / 'removed.bin').read_bytes() == b'stay-in-basis'

    # No-overwrite on existing OUT_DIR in archive mode
    run('archive/apply-no-overwrite', ['dir-apply', b_dir, arch_plain, out_plain, '--archive'], 1, watch=[arch_plain, out_plain], output=out_plain, contains='exists')

    # Zero-payload archive (all unchanged) roundtrip
    arch_noop = root / 'v050-noop.mbundle.gz'
    out_noop = root / 'v050-out-noop'
    run('archive/pack-noop', ['dir-pack', b_snap, sig_dir, b_dir, arch_noop, '--archive', '--gzip'], watch=[b_snap], output=arch_noop)
    run('archive/apply-noop', ['dir-apply', b_dir, arch_noop, out_noop, '--archive', '--gzip'], watch=[arch_noop], output=out_noop)
    noop_v = inspect_run('verify/noop-ok', ['dir-verify', out_noop, b_snap, '--json'], watch=[b_snap])
    assert json.loads(noop_v.stdout.decode('utf-8'))['ok'] is True

    # 3. Atomic tamper / trailing / truncation / zip-bomb / wrong-mode rejections.
    plain_raw = arch_plain.read_bytes()
    tampered_arch = root / 'v050-tampered.mbundle'
    tampered_arch.write_bytes(plain_raw[:-1] + bytes([plain_raw[-1] ^ 0xff]))
    run('archive/reject-tampered', ['dir-apply', b_dir, tampered_arch, root / 'v050-bad-tamper', '--archive', '--streaming'], 1, watch=[tampered_arch], output=root / 'v050-bad-tamper', contains='BindingMismatch')

    trail_arch = root / 'v050-trail.mbundle'
    trail_arch.write_bytes(plain_raw + b'X')
    run('archive/reject-trailing-plain', ['dir-apply', b_dir, trail_arch, root / 'v050-bad-trail', '--archive'], 1, watch=[trail_arch], output=root / 'v050-bad-trail', contains='TrailingData')

    trunc_arch = root / 'v050-trunc.mbundle'
    trunc_arch.write_bytes(plain_raw[:-2])
    run('archive/reject-trunc-plain', ['dir-apply', b_dir, trunc_arch, root / 'v050-bad-trunc', '--archive'], 1, watch=[trunc_arch], output=root / 'v050-bad-trunc', contains='TruncatedInput')

    gz_raw = arch_gz.read_bytes()
    trail_gz = root / 'v050-trail.mbundle.gz'
    trail_gz.write_bytes(gz_raw + b'Z')
    run('archive/reject-trailing-gzip', ['dir-apply', b_dir, trail_gz, root / 'v050-bad-gz-trail', '--archive', '--gzip'], 1, watch=[trail_gz], output=root / 'v050-bad-gz-trail', contains='TrailingData')

    trunc_gz = root / 'v050-trunc.mbundle.gz'
    trunc_gz.write_bytes(gz_raw[:-1])
    run('archive/reject-trunc-gzip', ['dir-apply', b_dir, trunc_gz, root / 'v050-bad-gz-trunc', '--archive', '--gzip'], 1, watch=[trunc_gz], output=root / 'v050-bad-gz-trunc', contains='TruncatedInput')

    # Gzip zip-bomb (256 KiB compressed zeros) rejected immediately without expanding
    bomb_raw = root / 'v050-bomb.bin'
    bomb_gz = root / 'v050-bomb.mbundle.gz'
    bomb_raw.write_bytes(b'\x00' * 262144)
    run('archive/make-bomb', ['compress', bomb_raw, bomb_gz, '--streaming'], watch=[bomb_raw], output=bomb_gz)
    run('archive/reject-bomb', ['dir-apply', b_dir, bomb_gz, root / 'v050-bad-bomb', '--archive', '--gzip'], 1, watch=[bomb_gz], output=root / 'v050-bad-bomb', contains='InvalidSchema')

    # Wrong mode combinations
    run('archive/reject-gz-without-flag', ['dir-apply', b_dir, arch_gz, root / 'v050-bad-w1', '--archive'], 1, watch=[arch_gz], output=root / 'v050-bad-w1', contains='InvalidSchema')
    run('archive/reject-plain-with-gz', ['dir-apply', b_dir, arch_plain, root / 'v050-bad-w2', '--archive', '--gzip'], 1, watch=[arch_plain], output=root / 'v050-bad-w2', contains='InvalidDelta')
    run('archive/reject-dir-as-archive', ['dir-apply', b_dir, b_dir, root / 'v050-bad-w3', '--archive'], 1, output=root / 'v050-bad-w3', contains='unsupported input')
    if links:
        arch_link = root / 'v050-arch-link.mbundle'
        arch_link.symlink_to(arch_plain)
        run('archive/reject-symlink', ['dir-apply', b_dir, arch_link, root / 'v050-bad-sym', '--archive'], 1, watch=[arch_plain, arch_link], output=root / 'v050-bad-sym', contains='leaf symlink')

    # 4. dir-verify matching (exit 0) and drift (exit 1 with full stdout report + stderr diagnostic).
    v_ok_json = inspect_run('verify/match-json', ['dir-verify', out_gz, t_snap, '--json'], watch=[t_snap])
    v_ok_obj = json.loads(v_ok_json.stdout.decode('utf-8'))
    assert v_ok_obj == {
        'schema_version': 3,
        'kind': 'moonlibsync-dir-verify',
        'ok': True,
        'summary': {'matched': '5', 'modified': '0', 'missing': '0', 'extra': '0'},
        'issues': [],
    }
    v_ok_human = inspect_run('verify/match-human', ['dir-verify', t_dir, t_snap, *excludes], watch=[t_snap])
    v_ok_htext = v_ok_human.stdout.decode('utf-8')
    assert v_ok_htext.startswith('dir-verify\nok: true\nmatched: 5\n')

    # Mutate out_plain to test Modified + Missing + Extra drift detection
    (out_plain / 'same.bin').write_bytes(b'drifted-bytes')
    (out_plain / 'tiny.bin').unlink()
    (out_plain / 'unexpected.bin').write_bytes(b'extra-file')

    drift_json = raw_run('verify/drift-json', ['dir-verify', out_plain, t_snap, '--json'], expected=1, watch=[t_snap], read_only=True)
    assert b'dir-verify mismatch' in drift_json.stderr
    drift_obj = json.loads(drift_json.stdout.decode('utf-8'))
    assert drift_obj['schema_version'] == 3 and drift_obj['kind'] == 'moonlibsync-dir-verify'
    assert drift_obj['ok'] is False
    assert drift_obj['summary'] == {'matched': '3', 'modified': '1', 'missing': '1', 'extra': '1'}
    assert [(i['kind'], i['path']) for i in drift_obj['issues']] == [
        ('modified', 'same.bin'),
        ('missing', 'tiny.bin'),
        ('extra', 'unexpected.bin'),
    ]

    drift_human = raw_run('verify/drift-human', ['dir-verify', out_plain, t_snap], expected=1, watch=[t_snap], read_only=True)
    assert b'dir-verify mismatch' in drift_human.stderr
    drift_htext = drift_human.stdout.decode('utf-8')
    assert 'ok: false\n' in drift_htext
    assert '  modified: same.bin\n' in drift_htext
    assert '  missing: tiny.bin\n' in drift_htext
    assert '  extra: unexpected.bin\n' in drift_htext

    # Invalid exclude patterns rejected even on empty dir
    empty_dir = root / 'v050-empty'
    empty_dir.mkdir()
    empty_snap = root / 'v050-empty.snap.json'
    run('exclude/snap-empty', ['dir-snapshot', empty_dir, empty_snap], output=empty_snap)
    for bad_pat in ('../escape', 'a\\b', '/abs'):
        run('exclude/bad-snap-' + bad_pat.replace('/', '_').replace('\\', '_'),
            ['dir-snapshot', empty_dir, root / 'v050-bad-ex.json', '--exclude', bad_pat],
            1, output=root / 'v050-bad-ex.json', contains='InvalidOptions:exclude')
        inspect_run('exclude/bad-verify-' + bad_pat.replace('/', '_').replace('\\', '_'),
            ['dir-verify', empty_dir, empty_snap, '--exclude', bad_pat],
            1, watch=[empty_snap], contains='InvalidOptions:exclude')
        run('exclude/bad-pack-' + bad_pat.replace('/', '_').replace('\\', '_'),
            ['dir-pack', b_snap, sig_dir, empty_dir, root / 'v050-bad-ex.mbundle', '--archive', '--exclude', bad_pat],
            1, watch=[b_snap], output=root / 'v050-bad-ex.mbundle', contains='InvalidOptions:exclude')

    # 5. --progress emits throttled stderr lines without polluting stdout.
    prog_src = root / 'v050-prog.bin'
    prog_sig = root / 'v050-prog.sig'
    prog_gz = root / 'v050-prog.gz'
    prog_out = root / 'v050-prog.out'
    prog_src.write_bytes(big_old)

    p_sig = raw_run('progress/signature', ['signature', prog_src, prog_sig, '--streaming', '--progress'], expected=0, watch=[prog_src], output=prog_sig)
    assert p_sig.stdout == b''
    assert b'[moonlibsync] signature ' in p_sig.stderr and b'(100%)' in p_sig.stderr and b'MiB/s' in p_sig.stderr

    p_cmp = raw_run('progress/compress', ['compress', prog_src, prog_gz, '--streaming', '--progress'], expected=0, watch=[prog_src], output=prog_gz)
    assert p_cmp.stdout == b'' and b'[moonlibsync] compress ' in p_cmp.stderr and b'(100%)' in p_cmp.stderr

    p_dec = raw_run('progress/decompress', ['decompress', prog_gz, prog_out, '--streaming', '--progress'], expected=0, watch=[prog_gz], output=prog_out)
    assert p_dec.stdout == b'' and b'[moonlibsync] decompress ' in p_dec.stderr and b'(100%)' in p_dec.stderr
    assert prog_out.read_bytes() == big_old

    prog_arch = root / 'v050-prog.mbundle.gz'
    prog_dir_out = root / 'v050-prog-out'
    p_pack = raw_run('progress/dir-pack', ['dir-pack', b_snap, sig_dir, t_dir, prog_arch, '--archive', '--gzip', '--streaming', '--progress', *excludes], expected=0, watch=[b_snap], output=prog_arch)
    assert p_pack.stdout == b'' and b'[moonlibsync] dir-pack ' in p_pack.stderr and b'(100%)' in p_pack.stderr

    p_apply = raw_run('progress/dir-apply', ['dir-apply', b_dir, prog_arch, prog_dir_out, '--archive', '--gzip', '--streaming', '--progress'], expected=0, watch=[prog_arch], output=prog_dir_out)
    assert p_apply.stdout == b'' and b'[moonlibsync] dir-apply ' in p_apply.stderr and b'(100%)' in p_apply.stderr

    # Stdout JSON purity with --progress
    p_vjson = raw_run('progress/dir-verify-json', ['dir-verify', prog_dir_out, t_snap, '--json', '--progress'], expected=0, watch=[t_snap], read_only=True)
    assert b'[moonlibsync]' not in p_vjson.stdout
    assert json.loads(p_vjson.stdout.decode('utf-8'))['ok'] is True
    assert b'[moonlibsync] dir-verify ' in p_vjson.stderr and b'(100%)' in p_vjson.stderr

    # 6. Usage gating (exit code 2).
    too_many_excludes = []
    for idx in range(65):
        too_many_excludes.extend(['--exclude', f'p{idx}'])
    for label, args, needle in [
        ('pack-gzip-no-archive', ['dir-pack', b_snap, sig_dir, t_dir, root / 'v050-u.mb', '--gzip'], '--gzip requires --archive'),
        ('apply-gzip-no-archive', ['dir-apply', b_dir, arch_gz, root / 'v050-u-dir', '--gzip'], '--gzip requires --archive'),
        ('snap-archive', ['dir-snapshot', b_dir, root / 'v050-u.json', '--archive'], 'usage:'),
        ('verify-archive', ['dir-verify', b_dir, b_snap, '--archive'], 'usage:'),
        ('apply-exclude', ['dir-apply', b_dir, arch_plain, root / 'v050-u-dir', '--archive', '--exclude', '.git'], 'usage:'),
        ('exclude-empty', ['dir-snapshot', b_dir, root / 'v050-u.json', '--exclude', ''], 'usage:'),
        ('exclude-65', ['dir-snapshot', b_dir, root / 'v050-u.json', *too_many_excludes], 'usage:'),
        ('dup-archive', ['dir-pack', b_snap, sig_dir, t_dir, root / 'v050-u.mb', '--archive', '--archive'], 'usage:'),
        ('dup-progress', ['signature', prog_src, root / 'v050-u.sig', '--progress', '--progress'], 'usage:'),
        ('verify-streaming', ['dir-verify', b_dir, b_snap, '--streaming'], 'usage:'),
        ('verify-file-limit', ['dir-verify', b_dir, b_snap, '--max-old-bytes', '10'], 'usage:'),
        ('verify-missing-arg', ['dir-verify', b_dir], 'usage:'),
    ]:
        run('usage/' + label, args, 2, watch=[b_snap, arch_plain, arch_gz], contains=needle)

    report['v050_summary'] = dict(
        archive_verified=True,
        archive_gzip_verified=True,
        exclude_verified=True,
        dir_verify_verified=True,
        progress_verified=True,
    )
