"""0.6.0 CLI integration cases: rollsum-blake2 profile, reverse-delta, --exclude-from, --detect-moves, inspect-bundle, --save-rollback, Ed25519 keygen/sign/verify/--verify-sig, MLSENC01 seal/unseal, and shell completions."""
import hashlib
import json
import os
from pathlib import Path
import struct
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
        result = case('v060/' + name, args, expected, **kw)
        report['cases'][-1]['v060_added'] = True
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
            name='v060/' + name,
            expected_exit=expected,
            actual_exit=p.returncode,
            passed=True,
            inputs_preserved=True,
            owned_temporary_clean=True,
            v060_added=True,
        ))
        return p

    # 0. Version & help listing all 35 commands.
    ver = inspect_run('version', ['--version'])
    assert ver.stdout.decode('utf-8') == 'MoonLibSync 0.7.0\n'
    hlp = inspect_run('help', ['--help']).stdout.decode('utf-8')
    all_28 = [
        'signature', 'delta', 'patch', 'reverse-delta', 'basis-info',
        'make-manifest', 'patch-verified', 'inspect-signature', 'inspect-delta',
        'check-patch', 'inspect-manifest', 'inspect-bundle',
        'make-transfer-manifest', 'apply-update', 'compress', 'decompress',
        'keygen', 'sign', 'verify', 'seal', 'unseal', 'dir-snapshot',
        'dir-plan', 'dir-verify', 'dir-signatures', 'dir-pack', 'dir-apply',
        'completions',
    ]
    all_35 = all_28 + [
        'compose-delta', 'range-plan', 'fetch-sync', 'x25519-keygen',
        'keyring-init', 'sign-combine', 'verify-quorum',
    ]
    assert len(all_35) == 35
    for cmd_name in all_35:
        assert f'moonlibsync {cmd_name}' in hlp, ('missing command in --help', cmd_name)

    # 1. --profile rollsum-blake2 (0x72730137) + inspect-signature + delta/patch/basis-info.
    prof_old = root / 'v060-prof-old.bin'
    prof_new = root / 'v060-prof-new.bin'
    old_bytes = bytes(((i * 47 + 11 + (i // 1024) * 19) % 256) for i in range(98304))
    new_bytes = old_bytes[:49152] + b'V060-ROLLSUM-BLAKE2-EDIT' + old_bytes[49176:]
    prof_old.write_bytes(old_bytes)
    prof_new.write_bytes(new_bytes)

    sig_rs_buf = root / 'v060-rs-buf.sig'
    sig_rs_str = root / 'v060-rs-str.sig'
    sig_rk = root / 'v060-rk.sig'
    run('profile/rollsum-buffered', ['signature', prof_old, sig_rs_buf, '--profile', 'rollsum-blake2', '--block-size', 'auto'], watch=[prof_old], output=sig_rs_buf)
    run('profile/rollsum-streaming', ['signature', prof_old, sig_rs_str, '--profile', 'rollsum-blake2', '--block-size', 'auto', '--streaming'], watch=[prof_old], output=sig_rs_str)
    run('profile/rk-explicit', ['signature', prof_old, sig_rk, '--profile', 'rk-blake2', '--block-size', '2048'], watch=[prof_old], output=sig_rk)
    assert sig_rs_buf.read_bytes() == sig_rs_str.read_bytes()
    assert struct.unpack('>I', sig_rs_buf.read_bytes()[:4])[0] == 0x72730137
    assert struct.unpack('>I', sig_rk.read_bytes()[:4])[0] == 0x72730147

    insp_rs_json = inspect_run('profile/inspect-rs-json', ['inspect-signature', sig_rs_str, '--json'], watch=[sig_rs_str])
    rs_obj = json.loads(insp_rs_json.stdout.decode('utf-8'))
    assert rs_obj['summary']['magic'] == '0x72730137'
    assert rs_obj['summary']['profile'] == 'RS_BLAKE2_SIG_MAGIC'
    insp_rs_human = inspect_run('profile/inspect-rs-human', ['inspect-signature', sig_rs_str], watch=[sig_rs_str])
    assert 'magic: 0x72730137\nprofile: RS_BLAKE2_SIG_MAGIC\n' in insp_rs_human.stdout.decode('utf-8')

    rs_delta = root / 'v060-rs.delta'
    rs_out = root / 'v060-rs.out'
    rs_info = root / 'v060-rs.info.json'
    run('profile/rs-delta', ['delta', sig_rs_str, prof_new, rs_delta, '--streaming'], watch=[sig_rs_str, prof_new], output=rs_delta)
    run('profile/rs-patch', ['patch', prof_old, rs_delta, rs_out, '--streaming'], watch=[prof_old, rs_delta], output=rs_out)
    assert rs_out.read_bytes() == new_bytes
    run('profile/rs-basis-info-stream', ['basis-info', prof_old, sig_rs_str, rs_info, '--streaming'], watch=[prof_old, sig_rs_str], output=rs_info)

    # 2. reverse-delta (buffered & streaming + progress + no-overwrite).
    rev_buf = root / 'v060-rev-buf.delta'
    rev_str = root / 'v060-rev-str.delta'
    rev_restored = root / 'v060-rev-restored.bin'
    run('reverse-delta/buffered', ['reverse-delta', prof_old, prof_new, rev_buf, '--block-size', 'auto', '--sum-size', '16'], watch=[prof_old, prof_new], output=rev_buf)
    p_rev = raw_run('reverse-delta/streaming-progress', ['reverse-delta', prof_old, prof_new, rev_str, '--block-size', 'auto', '--sum-size', '16', '--streaming', '--progress'], expected=0, watch=[prof_old, prof_new], output=rev_str)
    assert p_rev.stdout == b'' and b'[moonlibsync] reverse-delta ' in p_rev.stderr and b'(100%)' in p_rev.stderr
    assert rev_buf.read_bytes() == rev_str.read_bytes()
    assert rev_str.stat().st_size < len(old_bytes) // 4
    run('reverse-delta/no-overwrite', ['reverse-delta', prof_old, prof_new, rev_buf], 1, watch=[prof_old, prof_new, rev_buf], output=rev_buf, contains='already exists')
    run('reverse-delta/patch-recover-old', ['patch', prof_new, rev_str, rev_restored, '--streaming'], watch=[prof_new, rev_str], output=rev_restored)
    assert rev_restored.read_bytes() == old_bytes

    # 3. --exclude-from + --detect-moves + inspect-bundle + --save-rollback.
    b_dir = root / 'v060-basis'
    t_dir = root / 'v060-target'
    (b_dir / 'legacy').mkdir(parents=True)
    (t_dir / 'moved').mkdir(parents=True)
    (t_dir / 'cache').mkdir(parents=True)

    pure_move_data = bytes(((i * 31 + 7) % 256) for i in range(40960))
    edit_move_old = bytes(((i * 53 + 3 + (i // 512) * 13) % 256) for i in range(81920))
    edit_move_new = edit_move_old[:40960] + b'V060-MOVE-DELTA-PATCH' + edit_move_old[40981:]

    (b_dir / 'keep.bin').write_bytes(b'unchanged-060')
    (b_dir / 'legacy' / 'asset.bin').write_bytes(pure_move_data)
    (b_dir / 'legacy' / 'doc.bin').write_bytes(edit_move_old)
    (b_dir / 'modify.bin').write_bytes(old_bytes)
    (b_dir / 'removed.bin').write_bytes(b'will-be-restored-by-rollback')

    (t_dir / 'keep.bin').write_bytes(b'unchanged-060')
    (t_dir / 'moved' / 'asset-renamed.bin').write_bytes(pure_move_data)
    (t_dir / 'moved' / 'doc.bin').write_bytes(edit_move_new)
    (t_dir / 'modify.bin').write_bytes(new_bytes)
    (t_dir / 'added.bin').write_bytes(b'fresh-in-target')
    # Excluded by --exclude-from and --exclude
    (t_dir / 'cache' / 'stale.dat').write_bytes(b'ignore-cache')
    (t_dir / 'moved' / 'trace.log').write_bytes(b'ignore-log')
    (t_dir / 'scratch.tmp').write_bytes(b'ignore-tmp')

    ign_file = root / 'v060.moonlibsyncignore'
    ign_file.write_bytes(b'# MoonLibSync ignore file\r\n\r\n  cache  \r\n*.log\n')
    bom_ign = root / 'v060-bom.ignore'
    bom_ign.write_bytes(b'\xef\xbb\xbf*.log\n')
    bad_ign = root / 'v060-bad.ignore'
    bad_ign.write_bytes(b'../escape\n')

    b_snap = root / 'v060-basis.snap.json'
    t_snap = root / 'v060-target.snap.json'
    sig_dir = root / 'v060-sigs'
    excl_args = ['--exclude-from', ign_file, '--exclude', '*.tmp']

    run('exclude-from/snap-basis', ['dir-snapshot', b_dir, b_snap], output=b_snap)
    run('exclude-from/snap-target', ['dir-snapshot', t_dir, t_snap, *excl_args], watch=[ign_file], output=t_snap)
    t_snap_paths = [e['path'] for e in json.loads(t_snap.read_bytes())['entries']]
    assert t_snap_paths == ['added.bin', 'keep.bin', 'modify.bin', 'moved/asset-renamed.bin', 'moved/doc.bin']

    run('exclude-from/reject-bom', ['dir-snapshot', t_dir, root / 'v060-bom.snap.json', '--exclude-from', bom_ign], 1, watch=[bom_ign], output=root / 'v060-bom.snap.json', contains='exclude_file_bom')
    run('exclude-from/reject-bad-pat', ['dir-snapshot', t_dir, root / 'v060-bad.snap.json', '--exclude-from', bad_ign], 1, watch=[bad_ign], output=root / 'v060-bad.snap.json', contains='InvalidOptions:exclude')
    run('exclude-from/reject-missing', ['dir-snapshot', t_dir, root / 'v060-miss.snap.json', '--exclude-from', root / 'missing.ign'], 1, output=root / 'v060-miss.snap.json', contains='read')
    if links:
        ign_link = root / 'v060-ign-link'
        ign_link.symlink_to(ign_file)
        run('exclude-from/reject-symlink', ['dir-snapshot', t_dir, root / 'v060-sym.snap.json', '--exclude-from', ign_link], 1, watch=[ign_file, ign_link], output=root / 'v060-sym.snap.json', contains='leaf symlink')

    # dir-plan --detect-moves (human & JSON)
    plan_json = inspect_run('detect-moves/plan-json', ['dir-plan', b_snap, t_snap, '--detect-moves', '--json'], watch=[b_snap, t_snap])
    plan_obj = json.loads(plan_json.stdout.decode('utf-8'))
    assert plan_obj['summary']['copy_from_basis'] == '1'
    cfb_actions = [a for a in plan_obj['actions'] if a['kind'] == 'copy-from-basis']
    assert len(cfb_actions) == 1 and cfb_actions[0]['path'] == 'moved/asset-renamed.bin' and cfb_actions[0]['source_path'] == 'legacy/asset.bin'
    plan_human = inspect_run('detect-moves/plan-human', ['dir-plan', b_snap, t_snap, '--detect-moves'], watch=[b_snap, t_snap]).stdout.decode('utf-8')
    assert 'copy_from_basis: 1\n' in plan_human
    assert 'copy-from-basis: moved/asset-renamed.bin <- legacy/asset.bin\n' in plan_human

    # dir-signatures with --profile rollsum-blake2
    run('detect-moves/dir-signatures', ['dir-signatures', b_dir, b_snap, sig_dir, '--profile', 'rollsum-blake2', '--block-size', 'auto', '--streaming'], watch=[b_snap], output=sig_dir)
    first_sig = sorted((sig_dir / 'sigs').iterdir())[0]
    assert struct.unpack('>I', first_sig.read_bytes()[:4])[0] == 0x72730137

    # dir-pack --detect-moves (plain archive & gzip archive & directory bundle)
    arch_plain = root / 'v060-move.mbundle'
    arch_gz = root / 'v060-move.mbundle.gz'
    bundle_dir = root / 'v060-move-dir'
    run('detect-moves/pack-plain', ['dir-pack', b_snap, sig_dir, t_dir, arch_plain, '--detect-moves', '--archive', '--streaming', *excl_args], watch=[b_snap, ign_file], output=arch_plain)
    run('detect-moves/pack-gzip', ['dir-pack', b_snap, sig_dir, t_dir, arch_gz, '--detect-moves', '--archive', '--gzip', '--streaming', *excl_args], watch=[b_snap, ign_file], output=arch_gz)
    run('detect-moves/pack-dir-buffered', ['dir-pack', b_snap, sig_dir, t_dir, bundle_dir, '--detect-moves', *excl_args], watch=[b_snap, ign_file], output=bundle_dir)

    # inspect-bundle (plain & gzip, JSON & human, read-only)
    ib_plain_j = inspect_run('inspect-bundle/plain-json', ['inspect-bundle', arch_plain, '--json'], watch=[arch_plain])
    ib_plain_obj = json.loads(ib_plain_j.stdout.decode('utf-8'))
    assert ib_plain_obj['schema_version'] == 1
    assert ib_plain_obj['command'] == 'inspect-bundle'
    assert ib_plain_obj['gzip'] is False
    assert ib_plain_obj['archive_bytes'] == str(arch_plain.stat().st_size)
    manifest_obj = ib_plain_obj['manifest']
    assert manifest_obj['summary']['copy_from_basis'] == '1'
    entry_map = {e['path']: e for e in manifest_obj['entries']}
    assert entry_map['moved/asset-renamed.bin']['kind'] == 'copy-from-basis'
    assert entry_map['moved/asset-renamed.bin']['source_path'] == 'legacy/asset.bin'
    assert entry_map['moved/doc.bin']['kind'] == 'update-delta-from'
    assert entry_map['moved/doc.bin']['source_path'] == 'legacy/doc.bin'
    assert int(manifest_obj['summary']['total_payload_bytes']) < 15000  # vs >220 KiB without moves/deltas!

    ib_gz_j = inspect_run('inspect-bundle/gzip-json', ['inspect-bundle', arch_gz, '--gzip', '--json'], watch=[arch_gz])
    ib_gz_obj = json.loads(ib_gz_j.stdout.decode('utf-8'))
    assert ib_gz_obj['gzip'] is True and ib_gz_obj['manifest'] == manifest_obj
    ib_gz_h = inspect_run('inspect-bundle/gzip-human', ['inspect-bundle', arch_gz, '--gzip'], watch=[arch_gz]).stdout.decode('utf-8')
    assert 'inspect-bundle\n' in ib_gz_h and 'copy_from_basis: 1\n' in ib_gz_h
    assert 'copy-from-basis: moved/asset-renamed.bin <- legacy/asset.bin\n' in ib_gz_h
    assert 'update-delta-from: moved/doc.bin <- legacy/doc.bin\n' in ib_gz_h

    # Single deleted file renamed to a different basename + edited -> update-delta-from
    ren_b = root / 'v060-ren-basis'
    ren_t = root / 'v060-ren-target'
    ren_b.mkdir(); ren_t.mkdir()
    (ren_b / 'old-report.bin').write_bytes(edit_move_old)
    (ren_t / 'new-report-v2.bin').write_bytes(edit_move_new)
    ren_bs = root / 'v060-ren-b.snap.json'
    ren_ts = root / 'v060-ren-t.snap.json'
    ren_sigs = root / 'v060-ren-sigs'
    ren_arch = root / 'v060-ren.mbundle.gz'
    ren_out = root / 'v060-ren-out'
    run('detect-moves/rename-snap-b', ['dir-snapshot', ren_b, ren_bs], output=ren_bs)
    run('detect-moves/rename-snap-t', ['dir-snapshot', ren_t, ren_ts], output=ren_ts)
    run('detect-moves/rename-sigs', ['dir-signatures', ren_b, ren_bs, ren_sigs, '--block-size', 'auto'], watch=[ren_bs], output=ren_sigs)
    run('detect-moves/rename-pack', ['dir-pack', ren_bs, ren_sigs, ren_t, ren_arch, '--detect-moves', '--archive', '--gzip'], watch=[ren_bs], output=ren_arch)
    ren_ib = json.loads(inspect_run('detect-moves/rename-inspect', ['inspect-bundle', ren_arch, '--gzip', '--json'], watch=[ren_arch]).stdout.decode('utf-8'))
    ren_entries = {e['path']: e for e in ren_ib['manifest']['entries']}
    assert ren_entries['new-report-v2.bin']['kind'] == 'update-delta-from'
    assert ren_entries['new-report-v2.bin']['source_path'] == 'old-report.bin'
    run('detect-moves/rename-apply', ['dir-apply', ren_b, ren_arch, ren_out, '--archive', '--gzip'], watch=[ren_arch], output=ren_out)
    assert json.loads(inspect_run('detect-moves/rename-verify', ['dir-verify', ren_out, ren_ts, '--json'], watch=[ren_ts]).stdout.decode('utf-8'))['ok'] is True

    # inspect-bundle negative cases (tamper, trailing, truncation, wrong gzip flag)
    raw_plain = arch_plain.read_bytes()
    bad_ib_tamper = root / 'v060-ib-tamper.mbundle'
    bad_ib_tamper.write_bytes(raw_plain[:-1] + bytes([raw_plain[-1] ^ 0xff]))
    inspect_run('inspect-bundle/reject-tamper', ['inspect-bundle', bad_ib_tamper, '--json'], 1, watch=[bad_ib_tamper], contains='BindingMismatch')
    bad_ib_trail = root / 'v060-ib-trail.mbundle'
    bad_ib_trail.write_bytes(raw_plain + b'Z')
    inspect_run('inspect-bundle/reject-trailing', ['inspect-bundle', bad_ib_trail], 1, watch=[bad_ib_trail], contains='TrailingData')
    bad_ib_trunc = root / 'v060-ib-trunc.mbundle'
    bad_ib_trunc.write_bytes(raw_plain[:-3])
    inspect_run('inspect-bundle/reject-trunc', ['inspect-bundle', bad_ib_trunc], 1, watch=[bad_ib_trunc], contains='TruncatedInput')
    inspect_run('inspect-bundle/reject-wrong-gz', ['inspect-bundle', arch_gz], 1, watch=[arch_gz], contains='InvalidSchema')
    inspect_run('inspect-bundle/reject-wrong-plain', ['inspect-bundle', arch_plain, '--gzip'], 1, watch=[arch_plain], contains='InvalidDelta')

    # 4. Ed25519 keygen, sign, verify, and attached --verify-sig + --save-rollback.
    priv1 = root / 'v060-k1.priv'
    pub1 = root / 'v060-k1.pub'
    priv2 = root / 'v060-k2.priv'
    pub2 = root / 'v060-k2.pub'
    run('ed25519/keygen-1', ['keygen', priv1, pub1], output=pub1)
    run('ed25519/keygen-2', ['keygen', priv2, pub2], output=pub2)
    assert len(priv1.read_bytes()) == 65 and priv1.read_bytes().endswith(b'\n')
    assert len(pub1.read_bytes()) == 65 and pub1.read_bytes().endswith(b'\n')
    run('ed25519/keygen-no-overwrite-priv', ['keygen', priv1, root / 'v060-unused.pub'], 1, watch=[priv1], output=root / 'v060-unused.pub', contains='already exists')
    run('ed25519/keygen-no-overwrite-pub', ['keygen', root / 'v060-unused.priv', pub1], 1, watch=[pub1], output=root / 'v060-unused.priv', contains='already exists')
    run('ed25519/keygen-same-path', ['keygen', root / 'v060-same.key', root / 'v060-same.key'], 1, output=root / 'v060-same.key', contains='distinct')

    arch_sig = root / 'v060-move.mbundle.gz.sig.json'
    p_sign = raw_run('ed25519/sign-archive', ['sign', arch_gz, priv1, arch_sig, '--streaming', '--progress'], expected=0, watch=[arch_gz, priv1], output=arch_sig)
    assert p_sign.stdout == b'' and b'[moonlibsync] sign ' in p_sign.stderr and b'(100%)' in p_sign.stderr
    sig_doc = json.loads(arch_sig.read_bytes())
    assert sig_doc['schema_version'] == 1 and sig_doc['kind'] == 'moonlibsync-signature' and sig_doc['algorithm'] == 'ed25519'

    # verify (human, JSON, multi-key --pub-key, --progress stdout purity, read-only)
    v_j = inspect_run('ed25519/verify-json', ['verify', arch_gz, arch_sig, pub1, '--json', '--streaming'], watch=[arch_gz, arch_sig, pub1])
    v_obj = json.loads(v_j.stdout.decode('utf-8'))
    assert v_obj == {
        'schema_version': 1,
        'command': 'verify',
        'verified': True,
        'algorithm': 'ed25519',
        'key_id': sig_doc['key_id'],
        'public_key': sig_doc['public_key'],
        'payload_length': sig_doc['payload_length'],
        'payload_sha256': sig_doc['payload_sha256'],
    }
    v_multi = raw_run('ed25519/verify-multikey-progress', ['verify', arch_gz, arch_sig, pub2, '--pub-key', pub1, '--json', '--progress'], expected=0, watch=[arch_gz, arch_sig, pub1, pub2], read_only=True)
    assert b'[moonlibsync]' not in v_multi.stdout and json.loads(v_multi.stdout.decode('utf-8'))['verified'] is True
    assert b'[moonlibsync] verify ' in v_multi.stderr
    v_h = inspect_run('ed25519/verify-human', ['verify', arch_gz, arch_sig, pub1], watch=[arch_gz, arch_sig, pub1]).stdout.decode('utf-8')
    assert 'verify\nverified: true\nalgorithm: ed25519\n' in v_h

    # verify negative cases: untrusted key, tampered payload, tampered sig, bad key file -> exit 1 & empty stdout
    inspect_run('ed25519/verify-untrusted', ['verify', arch_gz, arch_sig, pub2, '--json'], 1, watch=[arch_gz, arch_sig, pub2], contains='UntrustedKey')
    tampered_arch_gz = root / 'v060-tampered-arch.mbundle.gz'
    gz_raw = arch_gz.read_bytes()
    tampered_arch_gz.write_bytes(gz_raw[:-1] + bytes([gz_raw[-1] ^ 0x01]))
    inspect_run('ed25519/verify-tampered-payload', ['verify', tampered_arch_gz, arch_sig, pub1, '--json'], 1, watch=[tampered_arch_gz, arch_sig, pub1], contains='DigestMismatch')
    bad_sig_doc = dict(sig_doc)
    flip_char = '0' if sig_doc['signature'][0] != '0' else '1'
    bad_sig_doc['signature'] = flip_char + sig_doc['signature'][1:]
    bad_sig_file = root / 'v060-bad.sig.json'
    bad_sig_file.write_text(json.dumps(bad_sig_doc) + '\n', encoding='utf-8')
    inspect_run('ed25519/verify-tampered-sig', ['verify', arch_gz, bad_sig_file, pub1], 1, watch=[arch_gz, bad_sig_file, pub1], contains='InvalidSignature')
    bad_key_file = root / 'v060-bad.pub'
    bad_key_file.write_bytes(b'NOT-HEX\n')
    inspect_run('ed25519/verify-bad-key', ['verify', arch_gz, arch_sig, bad_key_file], 1, watch=[arch_gz, arch_sig, bad_key_file], contains='InvalidFormat')

    # dir-apply with --verify-sig + multi-key --verify-key + --save-rollback
    out_applied = root / 'v060-out-applied'
    rb_archive = root / 'v060-rollback.mbundle.gz'
    restored_basis = root / 'v060-restored-basis'
    run('dir-apply/verified-with-rollback', [
        'dir-apply', b_dir, arch_gz, out_applied, '--archive', '--gzip', '--streaming',
        '--verify-sig', arch_sig, '--verify-key', pub2, '--verify-key', pub1,
        '--save-rollback', rb_archive,
    ], watch=[arch_gz, arch_sig, pub1, pub2], output=out_applied)
    assert rb_archive.is_file() and rb_archive.read_bytes()[:2] == b'\x1f\x8b'
    # Verify applied directory matches target snapshot bit-for-bit
    v_applied = inspect_run('dir-apply/verify-applied', ['dir-verify', out_applied, t_snap, '--json'], watch=[t_snap])
    assert json.loads(v_applied.stdout.decode('utf-8'))['ok'] is True
    # Verify BASIS_DIR untouched
    assert (b_dir / 'removed.bin').read_bytes() == b'will-be-restored-by-rollback'

    # Apply rollback archive to out_applied -> recovers BASIS_DIR bit-for-bit!
    run('rollback/apply-rollback', ['dir-apply', out_applied, rb_archive, restored_basis, '--archive', '--gzip', '--streaming'], watch=[rb_archive], output=restored_basis)
    v_rb = inspect_run('rollback/verify-restored-basis', ['dir-verify', restored_basis, b_snap, '--json'], watch=[b_snap])
    assert json.loads(v_rb.stdout.decode('utf-8'))['ok'] is True
    ib_rb = inspect_run('rollback/inspect-rollback', ['inspect-bundle', rb_archive, '--gzip', '--json'], watch=[rb_archive])
    assert json.loads(ib_rb.stdout.decode('utf-8'))['gzip'] is True

    # dir-apply directory-bundle mode with --save-rollback
    out_dir_mode = root / 'v060-out-dirmode'
    rb_dir_mode = root / 'v060-rollback-dirmode.mbundle.gz'
    restored_basis_2 = root / 'v060-restored-basis-2'
    run('dir-apply/dirmode-with-rollback', ['dir-apply', b_dir, bundle_dir, out_dir_mode, '--save-rollback', rb_dir_mode], output=out_dir_mode)
    run('rollback/apply-dirmode-rollback', ['dir-apply', out_dir_mode, rb_dir_mode, restored_basis_2, '--archive', '--gzip'], watch=[rb_dir_mode], output=restored_basis_2)
    assert json.loads(inspect_run('rollback/verify-dirmode-basis', ['dir-verify', restored_basis_2, b_snap, '--json'], watch=[b_snap]).stdout.decode('utf-8'))['ok'] is True

    # dir-apply negative cases: existing rollback refuses early without touching OUT_DIR; untrusted sig refuses without creating OUT_DIR or rollback
    run('dir-apply/rollback-no-overwrite', ['dir-apply', b_dir, arch_gz, root / 'v060-no-out', '--archive', '--gzip', '--save-rollback', rb_archive], 1, watch=[arch_gz, rb_archive], output=root / 'v060-no-out', contains='already exists')
    run('dir-apply/reject-untrusted-sig', ['dir-apply', b_dir, arch_gz, root / 'v060-untrusted-out', '--archive', '--gzip', '--verify-sig', arch_sig, '--verify-key', pub2, '--save-rollback', root / 'v060-untrusted-rb.gz'], 1, watch=[arch_gz, arch_sig, pub2], output=root / 'v060-untrusted-out', contains='UntrustedKey')
    assert not (root / 'v060-untrusted-rb.gz').exists()
    run('dir-apply/reject-tampered-signed-arch', ['dir-apply', b_dir, tampered_arch_gz, root / 'v060-tampered-out', '--archive', '--gzip', '--verify-sig', arch_sig, '--verify-key', pub1], 1, watch=[tampered_arch_gz, arch_sig, pub1], output=root / 'v060-tampered-out', contains='DigestMismatch')

    # Attached --verify-sig on patch-verified and apply-update (buffered & streaming)
    um_file = root / 'v060-um.json'
    um_sig = root / 'v060-um.sig.json'
    tm_file = root / 'v060-tm.json'
    tm_sig = root / 'v060-tm.sig.json'
    run('attached-sig/make-manifest', ['make-manifest', rs_info, sig_rs_str, prof_new, rs_delta, um_file], watch=[rs_info, sig_rs_str, prof_new, rs_delta], output=um_file)
    run('attached-sig/make-transfer', ['make-transfer-manifest', rs_info, sig_rs_str, prof_new, rs_delta, tm_file], watch=[rs_info, sig_rs_str, prof_new, rs_delta], output=tm_file)
    run('attached-sig/sign-um', ['sign', um_file, priv1, um_sig], watch=[um_file, priv1], output=um_sig)
    run('attached-sig/sign-tm', ['sign', tm_file, priv1, tm_sig], watch=[tm_file, priv1], output=tm_sig)

    pv_ok_buf = root / 'v060-pv-buf.out'
    pv_ok_str = root / 'v060-pv-str.out'
    au_ok_buf = root / 'v060-au-buf.out'
    au_ok_str = root / 'v060-au-str.out'
    run('attached-sig/patch-verified-buf', ['patch-verified', prof_old, rs_delta, um_file, pv_ok_buf, '--verify-sig', um_sig, '--verify-key', pub1], watch=[prof_old, rs_delta, um_file, um_sig, pub1], output=pv_ok_buf)
    run('attached-sig/patch-verified-str', ['patch-verified', prof_old, rs_delta, um_file, pv_ok_str, '--streaming', '--verify-sig', um_sig, '--verify-key', pub2, '--verify-key', pub1], watch=[prof_old, rs_delta, um_file, um_sig, pub1, pub2], output=pv_ok_str)
    run('attached-sig/apply-update-buf', ['apply-update', rs_delta, tm_file, au_ok_buf, '--basis', prof_old, '--verify-sig', tm_sig, '--verify-key', pub1], watch=[prof_old, rs_delta, tm_file, tm_sig, pub1], output=au_ok_buf)
    run('attached-sig/apply-update-str', ['apply-update', rs_delta, tm_file, au_ok_str, '--basis', prof_old, '--streaming', '--verify-sig', tm_sig, '--verify-key', pub1], watch=[prof_old, rs_delta, tm_file, tm_sig, pub1], output=au_ok_str)
    for restored in (pv_ok_buf, pv_ok_str, au_ok_buf, au_ok_str):
        assert restored.read_bytes() == new_bytes
    run('attached-sig/patch-verified-reject-untrusted', ['patch-verified', prof_old, rs_delta, um_file, root / 'v060-pv-bad', '--verify-sig', um_sig, '--verify-key', pub2], 1, watch=[um_file, um_sig, pub2], output=root / 'v060-pv-bad', contains='UntrustedKey')
    run('attached-sig/apply-update-reject-untrusted', ['apply-update', rs_delta, tm_file, root / 'v060-au-bad', '--basis', prof_old, '--streaming', '--verify-sig', tm_sig, '--verify-key', pub2], 1, watch=[tm_file, tm_sig, pub2], output=root / 'v060-au-bad', contains='UntrustedKey')

    # 5. MLSENC01 AEAD seal & unseal (raw key + Argon2id passphrase, buffered & streaming, tamper/trailing/truncation/wrong-key).
    sym_key = root / 'v060-sym.key'
    wrong_key = root / 'v060-wrong.key'
    pw_file = root / 'v060-pass.txt'
    wrong_pw = root / 'v060-wrong-pass.txt'
    sym_key.write_bytes(b'0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n')
    wrong_key.write_bytes(b'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210\n')
    pw_file.write_bytes(b'my-secret-passphrase-060\r\n')
    wrong_pw.write_bytes(b'not-the-right-passphrase\n')

    big_plain = root / 'v060-big-plain.bin'
    big_plain_bytes = bytes(((i * 67 + 23) % 256) for i in range(140000))
    big_plain.write_bytes(big_plain_bytes)
    empty_plain = root / 'v060-empty-plain.bin'
    empty_plain.write_bytes(b'')

    enc_k_buf = root / 'v060-k-buf.menc'
    enc_k_str = root / 'v060-k-str.menc'
    dec_k_a = root / 'v060-k-dec-a.bin'
    dec_k_b = root / 'v060-k-dec-b.bin'
    run('seal/key-buffered', ['seal', big_plain, enc_k_buf, '--key-file', sym_key, '--chunk-size', '16384'], watch=[big_plain, sym_key], output=enc_k_buf)
    p_seal = raw_run('seal/key-streaming-progress', ['seal', big_plain, enc_k_str, '--key-file', sym_key, '--chunk-size', '16384', '--streaming', '--progress'], expected=0, watch=[big_plain, sym_key], output=enc_k_str)
    assert p_seal.stdout == b'' and b'[moonlibsync] seal ' in p_seal.stderr and b'(100%)' in p_seal.stderr
    assert enc_k_buf.read_bytes()[:8] == b'MLSENC01'
    assert enc_k_str.read_bytes()[:8] == b'MLSENC01'
    # Random salt + nonce prefix => distinct ciphertexts
    assert enc_k_buf.read_bytes() != enc_k_str.read_bytes()

    p_unseal = raw_run('unseal/key-streaming-progress', ['unseal', enc_k_buf, dec_k_a, '--key-file', sym_key, '--streaming', '--progress'], expected=0, watch=[enc_k_buf, sym_key], output=dec_k_a)
    assert p_unseal.stdout == b'' and b'[moonlibsync] unseal ' in p_unseal.stderr and b'(100%)' in p_unseal.stderr
    run('unseal/key-buffered', ['unseal', enc_k_str, dec_k_b, '--key-file', sym_key], watch=[enc_k_str, sym_key], output=dec_k_b)
    assert dec_k_a.read_bytes() == big_plain_bytes
    assert dec_k_b.read_bytes() == big_plain_bytes

    # Empty file seal/unseal
    enc_empty = root / 'v060-empty.menc'
    dec_empty = root / 'v060-empty.out'
    run('seal/empty', ['seal', empty_plain, enc_empty, '--key-file', sym_key, '--streaming'], watch=[empty_plain, sym_key], output=enc_empty)
    run('unseal/empty', ['unseal', enc_empty, dec_empty, '--key-file', sym_key, '--streaming'], watch=[enc_empty, sym_key], output=dec_empty)
    assert dec_empty.read_bytes() == b''

    # Argon2id passphrase roundtrip (buffered & streaming)
    enc_pw = root / 'v060-pw.menc'
    dec_pw = root / 'v060-pw.out'
    run('seal/passphrase-streaming', ['seal', prof_old, enc_pw, '--passphrase-file', pw_file, '--argon2-memory', '64', '--argon2-passes', '1', '--chunk-size', '16384', '--streaming'], watch=[prof_old, pw_file], output=enc_pw)
    run('unseal/passphrase-streaming', ['unseal', enc_pw, dec_pw, '--passphrase-file', pw_file, '--streaming'], watch=[enc_pw, pw_file], output=dec_pw)
    assert dec_pw.read_bytes() == old_bytes

    # Negative AEAD tests
    ct_raw = enc_k_str.read_bytes()
    ct_tampered = root / 'v060-ct-tampered.menc'
    ct_tampered.write_bytes(ct_raw[:-1] + bytes([ct_raw[-1] ^ 0x80]))
    ct_trail = root / 'v060-ct-trail.menc'
    ct_trail.write_bytes(ct_raw + b'X')
    ct_trunc = root / 'v060-ct-trunc.menc'
    ct_trunc.write_bytes(ct_raw[:-4])
    run('unseal/reject-tamper-streaming', ['unseal', ct_tampered, root / 'v060-u-bad1', '--key-file', sym_key, '--streaming'], 1, watch=[ct_tampered, sym_key], output=root / 'v060-u-bad1', contains='AuthenticationFailed')
    run('unseal/reject-wrong-key', ['unseal', enc_k_str, root / 'v060-u-bad2', '--key-file', wrong_key], 1, watch=[enc_k_str, wrong_key], output=root / 'v060-u-bad2', contains='AuthenticationFailed')
    run('unseal/reject-wrong-passphrase', ['unseal', enc_pw, root / 'v060-u-bad3', '--passphrase-file', wrong_pw], 1, watch=[enc_pw, wrong_pw], output=root / 'v060-u-bad3', contains='AuthenticationFailed')
    run('unseal/reject-trailing', ['unseal', ct_trail, root / 'v060-u-bad4', '--key-file', sym_key, '--streaming'], 1, watch=[ct_trail, sym_key], output=root / 'v060-u-bad4', contains='TrailingData')
    run('unseal/reject-truncated', ['unseal', ct_trunc, root / 'v060-u-bad5', '--key-file', sym_key, '--streaming'], 1, watch=[ct_trunc, sym_key], output=root / 'v060-u-bad5', contains='TruncatedInput')
    run('unseal/reject-kdf-mismatch', ['unseal', enc_pw, root / 'v060-u-bad6', '--key-file', sym_key], 1, watch=[enc_pw, sym_key], output=root / 'v060-u-bad6', contains='kdf_mode_mismatch')
    run('seal/no-overwrite', ['seal', big_plain, enc_k_buf, '--key-file', sym_key], 1, watch=[big_plain, enc_k_buf], output=enc_k_buf, contains='already exists')

    # 6. Shell completions (bash, zsh, powershell) - read-only & complete.
    for shell in ('bash', 'zsh', 'powershell'):
        cp = inspect_run(f'completions/{shell}', ['completions', shell])
        text = cp.stdout.decode('utf-8')
        for cmd_name in all_28:
            assert cmd_name in text, (shell, cmd_name)
        assert '--detect-moves' in text and '--save-rollback' in text and '--verify-sig' in text
        if shell == 'zsh':
            assert 'delta|patch|basis-info|make-manifest|sign)' in text
            assert 'compress|decompress)' in text
            assert 'inspect-signature|inspect-manifest)' in text
            assert 'inspect-delta|check-patch)' in text

    # 7. Red-Team Audit #2 adversarial regression cases.
    def _craft_mbundle(manifest_obj, payloads=()):
        m_bytes = (json.dumps(manifest_obj, separators=(',', ':')) + '\n').encode('utf-8')
        buf = bytearray(b'MLSBDL01')
        buf += struct.pack('>I', len(m_bytes))
        buf += m_bytes
        buf += struct.pack('>I', len(payloads))
        for rel_path, data in payloads:
            p_bytes = rel_path.encode('utf-8')
            buf += struct.pack('>I', len(p_bytes))
            buf += p_bytes
            buf += struct.pack('>Q', len(data))
            buf += data
        return bytes(buf)

    # 7a. Crafted .mbundle with DOS reserved path "NUL", intermediate dir case collision, and file/dir prefix collision.
    rt_basis = root / 'v060-rt-empty-basis'
    rt_basis.mkdir()
    p_one = b'one'
    p_two = b'two'
    d_one = dict(byte_length=str(len(p_one)), sha256=hashlib.sha256(p_one).hexdigest())
    d_two = dict(byte_length=str(len(p_two)), sha256=hashlib.sha256(p_two).hexdigest())

    crafted_nul = root / 'v060-rt-nul.mbundle'
    crafted_nul.write_bytes(_craft_mbundle(
        dict(
            schema_version=3,
            kind='moonlibsync-dir-bundle',
            summary=dict(unchanged='0', add_full='1', update_delta='0', update_full='0', delete='0', total_payload_bytes=str(len(p_one))),
            entries=[dict(path='NUL', kind='add-full', payload_path='payloads/000000.full', target=d_one)],
        ),
        [('payloads/000000.full', p_one)],
    ))
    inspect_run('redteam2/inspect-crafted-nul', ['inspect-bundle', crafted_nul], 1, watch=[crafted_nul], contains='InvalidField:path')
    rt_nul_out = root / 'v060-rt-nul-out'
    run('redteam2/apply-crafted-nul', ['dir-apply', rt_basis, crafted_nul, rt_nul_out, '--archive'], 1, watch=[crafted_nul], output=rt_nul_out, contains='InvalidField:path')
    assert not rt_nul_out.exists()

    crafted_dircase = root / 'v060-rt-dircase.mbundle'
    crafted_dircase.write_bytes(_craft_mbundle(
        dict(
            schema_version=3,
            kind='moonlibsync-dir-bundle',
            summary=dict(unchanged='0', add_full='2', update_delta='0', update_full='0', delete='0', total_payload_bytes='6'),
            entries=[
                dict(path='DIR/b.txt', kind='add-full', payload_path='payloads/000000.full', target=d_one),
                dict(path='dir/a.txt', kind='add-full', payload_path='payloads/000001.full', target=d_two),
            ],
        ),
        [('payloads/000000.full', p_one), ('payloads/000001.full', p_two)],
    ))
    inspect_run('redteam2/inspect-crafted-dircase', ['inspect-bundle', crafted_dircase], 1, watch=[crafted_dircase], contains='InvalidField:path_collision')
    rt_dircase_out = root / 'v060-rt-dircase-out'
    run('redteam2/apply-crafted-dircase', ['dir-apply', rt_basis, crafted_dircase, rt_dircase_out, '--archive'], 1, watch=[crafted_dircase], output=rt_dircase_out, contains='InvalidField:path_collision')
    assert not rt_dircase_out.exists()

    crafted_prefix = root / 'v060-rt-prefix.mbundle'
    crafted_prefix.write_bytes(_craft_mbundle(
        dict(
            schema_version=3,
            kind='moonlibsync-dir-bundle',
            summary=dict(unchanged='0', add_full='2', update_delta='0', update_full='0', delete='0', total_payload_bytes='6'),
            entries=[
                dict(path='foo', kind='add-full', payload_path='payloads/000000.full', target=d_one),
                dict(path='foo/bar.txt', kind='add-full', payload_path='payloads/000001.full', target=d_two),
            ],
        ),
        [('payloads/000000.full', p_one), ('payloads/000001.full', p_two)],
    ))
    inspect_run('redteam2/inspect-crafted-prefix', ['inspect-bundle', crafted_prefix], 1, watch=[crafted_prefix], contains='InvalidField:path_collision')
    rt_prefix_out = root / 'v060-rt-prefix-out'
    run('redteam2/apply-crafted-prefix', ['dir-apply', rt_basis, crafted_prefix, rt_prefix_out, '--archive'], 1, watch=[crafted_prefix], output=rt_prefix_out, contains='InvalidField:path_collision')
    assert not rt_prefix_out.exists()

    if os.name == 'nt':
        run('redteam2/win-reserved-nul', ['signature', prof_old, root / 'NUL'], 1, watch=[prof_old], contains='reserved Windows device output path')
        run('redteam2/win-reserved-con-ext', ['signature', prof_old, root / 'con.txt'], 1, watch=[prof_old], contains='reserved Windows device output path')

    # 7b. dir-apply --save-rollback exclude boundary isolation (excluded secret + excluded oversized file + optional excluded symlink).
    rb_ex_b = root / 'v060-rt-rb-basis'
    rb_ex_t = root / 'v060-rt-rb-target'
    rb_ex_b.mkdir()
    rb_ex_t.mkdir()
    rb_edit_v1 = bytes(((i * 19 + 5) % 256) for i in range(3000))
    rb_edit_v2 = rb_edit_v1[:1400] + b'RT2-SYNCED-DELTA' + rb_edit_v1[1416:]
    (rb_ex_b / 'keep.bin').write_bytes(b'tracked-keep')
    (rb_ex_b / 'edit.bin').write_bytes(rb_edit_v1)
    (rb_ex_b / 'drop.bin').write_bytes(b'tracked-drop')
    (rb_ex_b / 'secret.log').write_bytes(b'DO-NOT-LEAK-INTO-ROLLBACK')
    (rb_ex_b / 'huge.log').write_bytes(b'H' * 16384)
    if links:
        (rb_ex_b / 'ignored.link').symlink_to(rb_ex_b / 'secret.log')
    if os.name == 'nt':
        junc_target = root / 'v060-rt-junc-target'
        junc_target.mkdir()
        (junc_target / 'outside.bin').write_bytes(b'OUTSIDE-JUNCTION')
        mkj = subprocess.run(['cmd', '/c', 'mklink', '/J', str(rb_ex_b / 'ignored_junc'), str(junc_target)], capture_output=True)
        assert mkj.returncode == 0, mkj.stderr
    (rb_ex_t / 'keep.bin').write_bytes(b'tracked-keep')
    (rb_ex_t / 'edit.bin').write_bytes(rb_edit_v2)
    (rb_ex_t / 'add.bin').write_bytes(b'tracked-add')

    rb_ex_bs = root / 'v060-rt-rb-b.snap.json'
    rb_ex_ts = root / 'v060-rt-rb-t.snap.json'
    rb_ex_sigs = root / 'v060-rt-rb-sigs'
    rb_ex_arch = root / 'v060-rt-rb.mbundle.gz'
    rb_ex_out = root / 'v060-rt-rb-out'
    rb_ex_rollback = root / 'v060-rt-rb-save.mbundle.gz'
    rb_ex_restored = root / 'v060-rt-rb-restored'
    rb_excl = ['--exclude', '*.log', '--exclude', '*.link', '--exclude', 'ignored_junc', '--max-file-bytes', '4096']
    run('redteam2/rb-snap-b', ['dir-snapshot', rb_ex_b, rb_ex_bs, *rb_excl], output=rb_ex_bs)
    run('redteam2/rb-snap-t', ['dir-snapshot', rb_ex_t, rb_ex_ts, *rb_excl], output=rb_ex_ts)
    run('redteam2/rb-sigs', ['dir-signatures', rb_ex_b, rb_ex_bs, rb_ex_sigs, '--block-size', '256', '--max-file-bytes', '4096'], watch=[rb_ex_bs], output=rb_ex_sigs)
    run('redteam2/rb-pack', ['dir-pack', rb_ex_bs, rb_ex_sigs, rb_ex_t, rb_ex_arch, '--archive', '--gzip', *rb_excl], watch=[rb_ex_bs], output=rb_ex_arch)
    run('redteam2/rb-apply-save', ['dir-apply', rb_ex_b, rb_ex_arch, rb_ex_out, '--archive', '--gzip', '--max-file-bytes', '4096', '--save-rollback', rb_ex_rollback], watch=[rb_ex_arch], output=rb_ex_out)
    rb_ex_insp = json.loads(inspect_run('redteam2/rb-inspect', ['inspect-bundle', rb_ex_rollback, '--gzip', '--json', '--max-file-bytes', '4096'], watch=[rb_ex_rollback]).stdout.decode('utf-8'))
    rb_ex_paths = [e['path'] for e in rb_ex_insp['manifest']['entries']]
    assert 'secret.log' not in rb_ex_paths and 'huge.log' not in rb_ex_paths and 'ignored.link' not in rb_ex_paths and not any('ignored_junc' in p or 'outside.bin' in p for p in rb_ex_paths)
    run('redteam2/rb-apply-rollback', ['dir-apply', rb_ex_out, rb_ex_rollback, rb_ex_restored, '--archive', '--gzip', '--max-file-bytes', '4096'], watch=[rb_ex_rollback], output=rb_ex_restored)
    rb_ex_ver = json.loads(inspect_run('redteam2/rb-verify-restored', ['dir-verify', rb_ex_restored, rb_ex_bs, '--json', '--max-file-bytes', '4096'], watch=[rb_ex_bs]).stdout.decode('utf-8'))
    assert rb_ex_ver['ok'] is True and rb_ex_ver['summary']['extra'] == '0' and rb_ex_ver['summary']['matched'] == '3'

    # 7c. Cyclic swap (a.bin <-> b.bin) with --detect-moves, 0 payload bytes, apply, verify, and rollback.
    sw_b = root / 'v060-rt-swap-basis'
    sw_t = root / 'v060-rt-swap-target'
    sw_b.mkdir()
    sw_t.mkdir()
    sw_data_a = bytes(((i * 17 + 1) % 256) for i in range(4096))
    sw_data_b = bytes(((i * 43 + 9) % 256) for i in range(5120))
    (sw_b / 'a.bin').write_bytes(sw_data_a)
    (sw_b / 'b.bin').write_bytes(sw_data_b)
    (sw_t / 'a.bin').write_bytes(sw_data_b)
    (sw_t / 'b.bin').write_bytes(sw_data_a)
    sw_bs = root / 'v060-rt-swap-b.snap.json'
    sw_ts = root / 'v060-rt-swap-t.snap.json'
    sw_sigs = root / 'v060-rt-swap-sigs'
    sw_arch = root / 'v060-rt-swap.mbundle.gz'
    sw_out = root / 'v060-rt-swap-out'
    sw_rb = root / 'v060-rt-swap-rb.mbundle.gz'
    sw_restored = root / 'v060-rt-swap-restored'
    run('redteam2/swap-snap-b', ['dir-snapshot', sw_b, sw_bs], output=sw_bs)
    run('redteam2/swap-snap-t', ['dir-snapshot', sw_t, sw_ts], output=sw_ts)
    sw_plan = json.loads(inspect_run('redteam2/swap-plan', ['dir-plan', sw_bs, sw_ts, '--detect-moves', '--json'], watch=[sw_bs, sw_ts]).stdout.decode('utf-8'))
    assert sw_plan['summary']['copy_from_basis'] == '2' and sw_plan['summary']['transfer_upper_bound_bytes'] == '0'
    run('redteam2/swap-sigs', ['dir-signatures', sw_b, sw_bs, sw_sigs], watch=[sw_bs], output=sw_sigs)
    run('redteam2/swap-pack', ['dir-pack', sw_bs, sw_sigs, sw_t, sw_arch, '--detect-moves', '--archive', '--gzip'], watch=[sw_bs], output=sw_arch)
    sw_ib = json.loads(inspect_run('redteam2/swap-inspect', ['inspect-bundle', sw_arch, '--gzip', '--json'], watch=[sw_arch]).stdout.decode('utf-8'))
    assert sw_ib['manifest']['summary']['copy_from_basis'] == '2' and sw_ib['manifest']['summary']['total_payload_bytes'] == '0'
    run('redteam2/swap-apply', ['dir-apply', sw_b, sw_arch, sw_out, '--archive', '--gzip', '--save-rollback', sw_rb], watch=[sw_arch], output=sw_out)
    assert json.loads(inspect_run('redteam2/swap-verify-target', ['dir-verify', sw_out, sw_ts, '--json'], watch=[sw_ts]).stdout.decode('utf-8'))['ok'] is True
    sw_rb_ib = json.loads(inspect_run('redteam2/swap-inspect-rb', ['inspect-bundle', sw_rb, '--gzip', '--json'], watch=[sw_rb]).stdout.decode('utf-8'))
    assert sw_rb_ib['manifest']['summary']['copy_from_basis'] == '2' and sw_rb_ib['manifest']['summary']['total_payload_bytes'] == '0'
    run('redteam2/swap-apply-rb', ['dir-apply', sw_out, sw_rb, sw_restored, '--archive', '--gzip'], watch=[sw_rb], output=sw_restored)
    assert json.loads(inspect_run('redteam2/swap-verify-basis', ['dir-verify', sw_restored, sw_bs, '--json'], watch=[sw_bs]).stdout.decode('utf-8'))['ok'] is True

    # 7d. reverse-delta asymmetric --max-old-bytes / --max-new-bytes (buffered & streaming).
    rev_small = root / 'v060-rt-rev-small.bin'
    rev_big = root / 'v060-rt-rev-big.bin'
    rev_small_bytes = bytes(((i * 11 + 3) % 256) for i in range(256))
    rev_big_bytes = bytes(((i * 29 + 7) % 256) for i in range(6000))
    rev_small.write_bytes(rev_small_bytes)
    rev_big.write_bytes(rev_big_bytes)

    rev_asym1_buf = root / 'v060-rt-rev1-buf.delta'
    rev_asym1_str = root / 'v060-rt-rev1-str.delta'
    rev_asym1_out = root / 'v060-rt-rev1.out'
    run('redteam2/rev-asym1-buf', ['reverse-delta', rev_small, rev_big, rev_asym1_buf, '--block-size', 'auto', '--max-old-bytes', '512', '--max-new-bytes', '8192'], watch=[rev_small, rev_big], output=rev_asym1_buf)
    run('redteam2/rev-asym1-str', ['reverse-delta', rev_small, rev_big, rev_asym1_str, '--block-size', 'auto', '--streaming', '--max-old-bytes', '512', '--max-new-bytes', '8192'], watch=[rev_small, rev_big], output=rev_asym1_str)
    assert rev_asym1_buf.read_bytes() == rev_asym1_str.read_bytes()
    run('redteam2/rev-asym1-patch', ['patch', rev_big, rev_asym1_str, rev_asym1_out], watch=[rev_big, rev_asym1_str], output=rev_asym1_out)
    assert rev_asym1_out.read_bytes() == rev_small_bytes

    run('redteam2/rev-asym1-reject-old-buf', ['reverse-delta', rev_small, rev_big, root / 'v060-rt-rf1', '--max-old-bytes', '128', '--max-new-bytes', '8192'], 1, watch=[rev_small, rev_big], output=root / 'v060-rt-rf1', contains='ReadLimitExceeded')
    run('redteam2/rev-asym1-reject-old-str', ['reverse-delta', rev_small, rev_big, root / 'v060-rt-rf2', '--streaming', '--max-old-bytes', '128', '--max-new-bytes', '8192'], 1, watch=[rev_small, rev_big], output=root / 'v060-rt-rf2', contains='ReadLimitExceeded')
    run('redteam2/rev-asym1-reject-new-buf', ['reverse-delta', rev_small, rev_big, root / 'v060-rt-rf3', '--max-old-bytes', '512', '--max-new-bytes', '2048'], 1, watch=[rev_small, rev_big], output=root / 'v060-rt-rf3', contains='ReadLimitExceeded')
    run('redteam2/rev-asym1-reject-new-str', ['reverse-delta', rev_small, rev_big, root / 'v060-rt-rf4', '--streaming', '--max-old-bytes', '512', '--max-new-bytes', '2048'], 1, watch=[rev_small, rev_big], output=root / 'v060-rt-rf4', contains='ReadLimitExceeded')

    rev_asym2_buf = root / 'v060-rt-rev2-buf.delta'
    rev_asym2_str = root / 'v060-rt-rev2-str.delta'
    rev_asym2_out = root / 'v060-rt-rev2.out'
    run('redteam2/rev-asym2-buf', ['reverse-delta', rev_big, rev_small, rev_asym2_buf, '--block-size', 'auto', '--max-old-bytes', '8192', '--max-new-bytes', '512'], watch=[rev_big, rev_small], output=rev_asym2_buf)
    run('redteam2/rev-asym2-str', ['reverse-delta', rev_big, rev_small, rev_asym2_str, '--block-size', 'auto', '--streaming', '--max-old-bytes', '8192', '--max-new-bytes', '512'], watch=[rev_big, rev_small], output=rev_asym2_str)
    assert rev_asym2_buf.read_bytes() == rev_asym2_str.read_bytes()
    run('redteam2/rev-asym2-patch', ['patch', rev_small, rev_asym2_str, rev_asym2_out], watch=[rev_small, rev_asym2_str], output=rev_asym2_out)
    assert rev_asym2_out.read_bytes() == rev_big_bytes

    # 7e. seal with default limits on input > 64 KiB + explicit --max-output-bytes 100 rejection.
    seal_def_out = root / 'v060-rt-seal-def.menc'
    seal_def_dec = root / 'v060-rt-seal-def.out'
    run('redteam2/seal-default-limits', ['seal', big_plain, seal_def_out, '--key-file', sym_key, '--streaming'], watch=[big_plain, sym_key], output=seal_def_out)
    run('redteam2/unseal-default-limits', ['unseal', seal_def_out, seal_def_dec, '--key-file', sym_key, '--streaming'], watch=[seal_def_out, sym_key], output=seal_def_dec)
    assert seal_def_dec.read_bytes() == big_plain_bytes
    run('redteam2/seal-explicit-max-output-buf', ['seal', big_plain, root / 'v060-rt-seal-cap1.menc', '--key-file', sym_key, '--max-output-bytes', '100'], 1, watch=[big_plain, sym_key], output=root / 'v060-rt-seal-cap1.menc', contains='LimitExceeded')
    run('redteam2/seal-explicit-max-output-str', ['seal', big_plain, root / 'v060-rt-seal-cap2.menc', '--key-file', sym_key, '--streaming', '--max-output-bytes', '100'], 1, watch=[big_plain, sym_key], output=root / 'v060-rt-seal-cap2.menc', contains='LimitExceeded')

    # 8. Usage gating (exit code 2).
    for label, args, needle in [
        ('bad-profile', ['signature', prof_old, root / 'u1', '--profile', 'md4'], 'usage:'),
        ('dup-profile', ['signature', prof_old, root / 'u2', '--profile', 'rk-blake2', '--profile', 'rollsum-blake2'], 'usage:'),
        ('profile-on-delta', ['delta', sig_rk, prof_new, root / 'u3', '--profile', 'rk-blake2'], 'usage:'),
        ('exclude-from-empty', ['dir-snapshot', b_dir, root / 'u4', '--exclude-from', ''], 'usage:'),
        ('exclude-from-apply', ['dir-apply', b_dir, arch_gz, root / 'u5', '--archive', '--exclude-from', ign_file], 'usage:'),
        ('detect-moves-snap', ['dir-snapshot', b_dir, root / 'u6', '--detect-moves'], 'usage:'),
        ('verify-sig-no-key', ['dir-apply', b_dir, arch_gz, root / 'u7', '--archive', '--verify-sig', arch_sig], 'usage:'),
        ('verify-key-no-sig', ['dir-apply', b_dir, arch_gz, root / 'u8', '--archive', '--verify-key', pub1], 'usage:'),
        ('verify-sig-no-archive', ['dir-apply', b_dir, bundle_dir, root / 'u9', '--verify-sig', arch_sig, '--verify-key', pub1], 'usage:'),
        ('save-rollback-pack', ['dir-pack', b_snap, sig_dir, t_dir, root / 'u10', '--save-rollback', root / 'rb'], 'usage:'),
        ('seal-no-auth', ['seal', big_plain, root / 'u11'], 'usage:'),
        ('seal-both-auth', ['seal', big_plain, root / 'u12', '--key-file', sym_key, '--passphrase-file', pw_file], 'usage:'),
        ('seal-argon2-with-key', ['seal', big_plain, root / 'u13', '--key-file', sym_key, '--argon2-memory', '64'], 'usage:'),
        ('seal-bad-chunk', ['seal', big_plain, root / 'u14', '--key-file', sym_key, '--chunk-size', '512'], 'usage:'),
        ('unseal-no-auth', ['unseal', enc_k_buf, root / 'u15'], 'usage:'),
        ('unseal-chunk-flag', ['unseal', enc_k_buf, root / 'u16', '--key-file', sym_key, '--chunk-size', '4096'], 'usage:'),
        ('keygen-one-arg', ['keygen', root / 'u17'], 'usage:'),
        ('keygen-json', ['keygen', root / 'u18a', root / 'u18b', '--json'], 'usage:'),
        ('inspect-bundle-archive-flag', ['inspect-bundle', arch_plain, '--archive'], 'usage:'),
        ('inspect-bundle-streaming', ['inspect-bundle', arch_plain, '--streaming'], 'usage:'),
        ('completions-invalid-shell', ['completions', 'fish'], 'usage:'),
        ('completions-json', ['completions', 'bash', '--json'], 'usage:'),
        ('reverse-delta-missing-arg', ['reverse-delta', prof_old, prof_new], 'usage:'),
    ]:
        run('usage/' + label, args, 2, watch=[prof_old, arch_gz, enc_k_buf], contains=needle)

    report['v060_summary'] = dict(
        profile_rollsum_verified=True,
        reverse_delta_verified=True,
        exclude_from_verified=True,
        detect_moves_verified=True,
        inspect_bundle_verified=True,
        rollback_verified=True,
        ed25519_signing_verified=True,
        aead_seal_unseal_verified=True,
        completions_verified=True,
    )
