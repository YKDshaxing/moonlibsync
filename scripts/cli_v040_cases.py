"""0.4.0 CLI integration cases: --streaming pipelines and dir-snapshot / dir-plan."""
import hashlib
import json


def _digest(data):
    return dict(byte_length=str(len(data)), sha256=hashlib.sha256(data).hexdigest())


def exercise(root, case, report, links):
    def run(name, args, expected=0, **kw):
        result = case('v040/' + name, args, expected, **kw)
        report['cases'][-1]['v040_added'] = True
        return result

    def inspect_run(name, args, expected=0, **kw):
        before_entries = {str(p.relative_to(root)) for p in root.rglob('*')}
        result = run(name, args, expected, text=(expected == 0), **kw)
        after_entries = {str(p.relative_to(root)) for p in root.rglob('*')}
        assert after_entries == before_entries, name
        return result

    # 1. Streaming > 64 KiB pipeline parity & verified recovery.
    old_bytes = bytes(((i * 73 + 19 + (i // 2048) * 11) % 256) for i in range(140000))
    new_bytes = old_bytes[:70000] + b'STREAMING-040-PATCH' + old_bytes[70019:]
    old_p = root / 'v040-old.bin'
    new_p = root / 'v040-new.bin'
    old_p.write_bytes(old_bytes)
    new_p.write_bytes(new_bytes)

    sig_stream = root / 'v040-stream.sig'
    sig_plain = root / 'v040-plain.sig'
    delta_stream = root / 'v040-stream.delta'
    delta_plain = root / 'v040-plain.delta'
    out_stream = root / 'v040-stream.out'
    info_p = root / 'v040-info.json'
    update_p = root / 'v040-update.json'
    transfer_p = root / 'v040-transfer.json'
    verified_out = root / 'v040-verified.out'
    transfer_out = root / 'v040-transfer.out'

    run('stream/sig-auto', ['signature', old_p, sig_stream, '--streaming', '--block-size', 'auto'], watch=[old_p], output=sig_stream)
    run('plain/sig-auto', ['signature', old_p, sig_plain, '--block-size', 'auto'], watch=[old_p], output=sig_plain)
    assert sig_stream.read_bytes() == sig_plain.read_bytes()

    run('stream/delta', ['delta', sig_stream, new_p, delta_stream, '--streaming'], watch=[sig_stream, new_p], output=delta_stream)
    run('plain/delta', ['delta', sig_plain, new_p, delta_plain], watch=[sig_plain, new_p], output=delta_plain)
    assert delta_stream.read_bytes() == delta_plain.read_bytes()

    run('stream/patch', ['patch', old_p, delta_stream, out_stream, '--streaming'], watch=[old_p, delta_stream], output=out_stream)
    assert out_stream.read_bytes() == new_bytes

    run('stream/info', ['basis-info', old_p, sig_stream, info_p], watch=[old_p, sig_stream], output=info_p)
    info_stream = root / 'v040-info-stream.json'
    run('stream/info-streaming', ['basis-info', old_p, sig_stream, info_stream, '--streaming'], watch=[old_p, sig_stream], output=info_stream)
    assert info_stream.read_bytes() == info_p.read_bytes()

    run('stream/manifest', ['make-manifest', info_p, sig_stream, new_p, delta_stream, update_p], watch=[info_p, sig_stream, new_p, delta_stream], output=update_p)
    update_stream = root / 'v040-update-stream.json'
    run('stream/manifest-streaming', ['make-manifest', info_stream, sig_stream, new_p, delta_stream, update_stream, '--streaming'], watch=[info_stream, sig_stream, new_p, delta_stream], output=update_stream)
    assert update_stream.read_bytes() == update_p.read_bytes()

    run('stream/patch-verified', ['patch-verified', old_p, delta_stream, update_p, verified_out, '--streaming'], watch=[old_p, delta_stream, update_p], output=verified_out)
    assert verified_out.read_bytes() == new_bytes

    run('stream/transfer-manifest', ['make-transfer-manifest', info_p, sig_stream, new_p, delta_stream, transfer_p], watch=[info_p, sig_stream, new_p, delta_stream], output=transfer_p)
    transfer_stream = root / 'v040-transfer-stream.json'
    run('stream/transfer-manifest-streaming', ['make-transfer-manifest', info_stream, sig_stream, new_p, delta_stream, transfer_stream, '--streaming'], watch=[info_stream, sig_stream, new_p, delta_stream], output=transfer_stream)
    assert transfer_stream.read_bytes() == transfer_p.read_bytes()

    run('stream/apply-delta', ['apply-update', delta_stream, transfer_p, transfer_out, '--basis', old_p, '--streaming'], watch=[old_p, delta_stream, transfer_p], output=transfer_out)
    assert transfer_out.read_bytes() == new_bytes

    # Streaming inspect-delta & check-patch parity (text & --json) + high UInt64 offset + OOB rejection.
    id_plain = inspect_run('stream/inspect-delta-plain', ['inspect-delta', delta_stream, '--json'], watch=[delta_stream])
    id_stream = inspect_run('stream/inspect-delta-streaming', ['inspect-delta', delta_stream, '--json', '--streaming'], watch=[delta_stream])
    assert id_stream.stdout == id_plain.stdout
    cp_plain = inspect_run('stream/check-patch-plain', ['check-patch', old_p, delta_stream, '--json'], watch=[old_p, delta_stream])
    cp_stream = inspect_run('stream/check-patch-streaming', ['check-patch', old_p, delta_stream, '--json', '--streaming'], watch=[old_p, delta_stream])
    assert cp_stream.stdout == cp_plain.stdout

    high_delta = root / 'v040-high-off.delta'
    high_delta.write_bytes(bytes.fromhex('7273023651ffffffff000000000c00'))
    id_high = inspect_run('stream/inspect-delta-high-offset', ['inspect-delta', high_delta, '--json', '--streaming'], watch=[high_delta])
    assert json.loads(id_high.stdout.decode('utf-8'))['summary']['copy_bytes'] == '12'
    inspect_run('stream/check-patch-oob', ['check-patch', old_p, high_delta, '--streaming'], 1, watch=[old_p, high_delta], contains='CopyOutOfBounds')

    # Streaming basis-info mismatch rejection
    bad_sig_p = root / 'v040-bad.sig'
    sb = sig_stream.read_bytes()
    bad_sig_p.write_bytes(sb[:-1] + bytes([sb[-1] ^ 0xff]))
    run('stream/basis-info-mismatch', ['basis-info', old_p, bad_sig_p, root / 'v040-bi-bad.json', '--streaming'], 1, watch=[old_p, bad_sig_p], output=root / 'v040-bi-bad.json', contains='basis_signature')

    # Bounded gzip compress / decompress (buffered + --streaming, zip-bomb, trailing data).
    gz_plain = root / 'v040-delta.gz'
    gz_stream = root / 'v040-delta-stream.gz'
    ungz_plain = root / 'v040-delta.ungz'
    ungz_stream = root / 'v040-delta-stream.ungz'
    run('gzip/compress-plain', ['compress', delta_stream, gz_plain], watch=[delta_stream], output=gz_plain)
    run('gzip/compress-stream', ['compress', delta_stream, gz_stream, '--streaming'], watch=[delta_stream], output=gz_stream)
    run('gzip/decompress-plain', ['decompress', gz_plain, ungz_plain], watch=[gz_plain], output=ungz_plain)
    run('gzip/decompress-stream', ['decompress', gz_stream, ungz_stream, '--streaming'], watch=[gz_stream], output=ungz_stream)
    assert ungz_plain.read_bytes() == delta_stream.read_bytes()
    assert ungz_stream.read_bytes() == delta_stream.read_bytes()
    run('gzip/no-overwrite', ['compress', delta_stream, gz_plain], 1, watch=[delta_stream, gz_plain], output=gz_plain, contains='exists')

    bomb_raw = root / 'v040-bomb.bin'
    bomb_gz = root / 'v040-bomb.gz'
    bomb_raw.write_bytes(b'\x00' * 262144)
    run('gzip/make-bomb', ['compress', bomb_raw, bomb_gz, '--streaming'], watch=[bomb_raw], output=bomb_gz)
    assert bomb_gz.stat().st_size < 4096
    run('gzip/reject-bomb-stream', ['decompress', bomb_gz, root / 'v040-bomb.out', '--streaming', '--max-output-bytes', '4096'], 1, watch=[bomb_gz], output=root / 'v040-bomb.out', contains='LimitExceeded')

    trail_gz = root / 'v040-trail.gz'
    trail_gz.write_bytes(gz_stream.read_bytes() + b'X')
    run('gzip/reject-trailing', ['decompress', trail_gz, root / 'v040-trail.out', '--streaming'], 1, watch=[trail_gz], output=root / 'v040-trail.out', contains='TrailingData')
    trunc_gz = root / 'v040-trunc.gz'
    trunc_gz.write_bytes(gz_stream.read_bytes()[:-1])
    run('gzip/reject-truncated', ['decompress', trunc_gz, root / 'v040-trunc.out', '--streaming'], 1, watch=[trunc_gz], output=root / 'v040-trunc.out', contains='TruncatedInput')

    # Streaming Full-file apply-update + tampered manifest atomic rejection.
    full_new = root / 'v040-full.bin'
    full_cand = root / 'v040-full.delta'
    full_manifest = root / 'v040-full.json'
    full_out = root / 'v040-full.out'
    full_new.write_bytes(b'full-stream-payload-040')
    run('stream/full-cand', ['delta', sig_stream, full_new, full_cand], watch=[sig_stream, full_new], output=full_cand)
    run('stream/full-manifest', ['make-transfer-manifest', info_p, sig_stream, full_new, full_cand, full_manifest], watch=[info_p, sig_stream, full_new, full_cand], output=full_manifest)
    run('stream/apply-full', ['apply-update', full_new, full_manifest, full_out, '--streaming'], watch=[full_new, full_manifest], output=full_out)
    assert full_out.read_bytes() == b'full-stream-payload-040'

    bad_um = json.loads(update_p.read_bytes())
    bad_um['result']['sha256'] = '0' * 64
    bad_um_p = root / 'v040-bad-update.json'
    bad_um_p.write_text(json.dumps(bad_um), encoding='utf-8')
    run('stream/bad-result-sha', ['patch-verified', old_p, delta_stream, bad_um_p, root / 'v040-bad.out', '--streaming'], 1, watch=[old_p, delta_stream, bad_um_p], output=root / 'v040-bad.out', contains='result_sha256')
    run('stream/tight-old-limit', ['signature', old_p, root / 'v040-tight.sig', '--streaming', '--max-old-bytes', '100'], 1, watch=[old_p], output=root / 'v040-tight.sig', contains='ReadLimitExceeded')
    run('stream/usage-unsupported', ['inspect-manifest', update_p, '--streaming'], 2, watch=[update_p], contains='usage:')
    run('stream/usage-duplicate', ['patch', old_p, delta_stream, root / 'v040-u.out', '--streaming', '--streaming'], 2, watch=[old_p, delta_stream], output=root / 'v040-u.out', contains='usage:')

    # 2. dir-snapshot & dir-plan integration suite.
    d1 = root / 'v040-dir1'
    d2 = root / 'v040-dir2'
    d_empty = root / 'v040-dir-empty'
    (d1 / 'nested').mkdir(parents=True)
    (d2 / 'nested').mkdir(parents=True)
    d_empty.mkdir()
    (d1 / 'keep.bin').write_bytes(b'same')
    (d1 / '.hidden').write_bytes(b'dot-v1')
    (d1 / 'nested' / 'mod.bin').write_bytes(b'v1')
    (d1 / 'gone.bin').write_bytes(b'drop')
    (d2 / 'keep.bin').write_bytes(b'same')
    (d2 / '.hidden').write_bytes(b'dot-v1')
    (d2 / 'nested' / 'mod.bin').write_bytes(b'v2-updated')
    (d2 / 'added.bin').write_bytes(b'brand-new')

    snap1 = root / 'v040-snap1.json'
    snap2 = root / 'v040-snap2.json'
    snap_empty = root / 'v040-snap-empty.json'
    run('dir/snap1', ['dir-snapshot', d1, snap1], output=snap1)
    run('dir/snap2', ['dir-snapshot', d2, snap2], output=snap2)
    run('dir/snap-empty', ['dir-snapshot', d_empty, snap_empty, '--max-entries', '0'], output=snap_empty)
    s1 = json.loads(snap1.read_bytes())
    assert s1['schema_version'] == 3 and s1['kind'] == 'moonlibsync-dir-snapshot'
    assert [e['path'] for e in s1['entries']] == ['.hidden', 'gone.bin', 'keep.bin', 'nested/mod.bin']
    assert json.loads(snap_empty.read_bytes())['entries'] == []

    # No-overwrite check on dir-snapshot
    run('dir/snap-existing', ['dir-snapshot', d1, snap1], 1, watch=[snap1], output=snap1, contains='exists')

    # Read-only dir-plan JSON + human
    jp = inspect_run('dir/plan-json', ['dir-plan', snap1, snap2, '--json'], watch=[snap1, snap2])
    plan_obj = json.loads(jp.stdout.decode('utf-8'))
    assert plan_obj['schema_version'] == 3 and plan_obj['kind'] == 'moonlibsync-dir-plan'
    assert plan_obj['summary'] == {
        'unchanged': '2',
        'add': '1',
        'update': '1',
        'delete': '1',
        'transfer_upper_bound_bytes': str(len(b'v2-updated') + len(b'brand-new')),
    }
    hp = inspect_run('dir/plan-human', ['dir-plan', snap1, snap2], watch=[snap1, snap2])
    htext = hp.stdout.decode('utf-8')
    assert htext.startswith('dir-plan\n') and 'update-candidate: nested/mod.bin' in htext

    # DIR_LIMITS failures & usage rejections
    run('dir/limit-depth', ['dir-snapshot', d1, root / 'v040-d.json', '--max-depth', '1'], 1, output=root / 'v040-d.json', contains='ResourceLimit:path_depth')
    run('dir/limit-entries', ['dir-snapshot', d1, root / 'v040-e.json', '--max-entries', '2'], 1, output=root / 'v040-e.json', contains='ResourceLimit:dir_entries')
    run('dir/limit-file', ['dir-snapshot', d1, root / 'v040-f.json', '--max-file-bytes', '2'], 1, output=root / 'v040-f.json', contains='ReadLimitExceeded')
    run('dir/not-dir', ['dir-snapshot', old_p, root / 'v040-nd.json'], 1, watch=[old_p], output=root / 'v040-nd.json', contains='unsupported input kind')

    if links:
        sym_dir = root / 'v040-dir-sym'
        (sym_dir).mkdir()
        (sym_dir / 'link').symlink_to(old_p)
        run('dir/child-symlink', ['dir-snapshot', sym_dir, root / 'v040-sl.json'], 1, watch=[old_p], output=root / 'v040-sl.json', contains='symlink')
        top_sym = root / 'v040-top-sym'
        top_sym.symlink_to(d_empty, target_is_directory=True)
        run('dir/root-symlink', ['dir-snapshot', top_sym, root / 'v040-tl.json'], 1, output=root / 'v040-tl.json', contains='symlink')

    # 3. End-to-end directory incremental bundle: dir-signatures -> dir-pack -> dir-apply.
    b_dir = root / 'v040-bundle-basis'
    t_dir = root / 'v040-bundle-target'
    (b_dir / 'sub').mkdir(parents=True)
    (t_dir / 'sub').mkdir(parents=True)
    big_old = bytes(((i * 47 + 9 + (i // 1024) * 13) % 256) for i in range(96000))
    big_new = big_old[:48000] + b'DIR-BUNDLE-PATCH-040' + big_old[48020:]
    (b_dir / 'same.bin').write_bytes(b'identical-v1')
    (b_dir / 'sub' / 'big.bin').write_bytes(big_old)
    (b_dir / 'tiny.bin').write_bytes(b'aa')
    (b_dir / 'removed.bin').write_bytes(b'goodbye')
    (t_dir / 'same.bin').write_bytes(b'identical-v1')
    (t_dir / 'sub' / 'big.bin').write_bytes(big_new)
    (t_dir / 'tiny.bin').write_bytes(b'bbbbbb')
    (t_dir / 'added.bin').write_bytes(b'welcome-new')

    b_snap = root / 'v040-b-snap.json'
    t_snap = root / 'v040-t-snap.json'
    sig_dir = root / 'v040-sig-dir'
    bundle_dir = root / 'v040-bundle-dir'
    bundle_full_dir = root / 'v040-bundle-full'
    out_dir = root / 'v040-out-dir'
    out_snap = root / 'v040-out-snap.json'
    run('dir-bundle/snap-basis', ['dir-snapshot', b_dir, b_snap], output=b_snap)
    run('dir-bundle/snap-target', ['dir-snapshot', t_dir, t_snap], output=t_snap)
    run('dir-bundle/signatures', ['dir-signatures', b_dir, b_snap, sig_dir, '--block-size', 'auto', '--streaming'], watch=[b_snap], output=sig_dir)
    run('dir-bundle/signatures-no-overwrite', ['dir-signatures', b_dir, b_snap, sig_dir], 1, watch=[b_snap, sig_dir], output=sig_dir, contains='exists')

    # Sender packs bundle using ONLY b_snap + sig_dir + t_dir (no b_dir passed!)
    run('dir-bundle/pack', ['dir-pack', b_snap, sig_dir, t_dir, bundle_dir, '--streaming'], watch=[b_snap], output=bundle_dir)
    bm = json.loads((bundle_dir / 'bundle.json').read_bytes())
    assert bm['schema_version'] == 3 and bm['kind'] == 'moonlibsync-dir-bundle'
    assert bm['summary']['unchanged'] == '1'
    assert bm['summary']['add_full'] == '1'
    assert bm['summary']['update_delta'] == '1'
    assert bm['summary']['update_full'] == '1'
    assert bm['summary']['delete'] == '1'
    assert int(bm['summary']['total_payload_bytes']) < len(big_new) // 4

    # High --min-savings forces Full instead of Delta
    run('dir-bundle/pack-min-savings', ['dir-pack', b_snap, sig_dir, t_dir, bundle_full_dir, '--min-savings', '1000000'], watch=[b_snap], output=bundle_full_dir)
    bm_full = json.loads((bundle_full_dir / 'bundle.json').read_bytes())
    assert bm_full['summary']['update_delta'] == '0' and bm_full['summary']['update_full'] == '2'

    # Apply bundle into fresh OUT_DIR, verify snapshot equality and untouched BASIS_DIR
    run('dir-bundle/apply', ['dir-apply', b_dir, bundle_dir, out_dir, '--streaming'], output=out_dir)
    run('dir-bundle/snap-out', ['dir-snapshot', out_dir, out_snap], output=out_snap)
    assert out_snap.read_bytes() == t_snap.read_bytes()
    assert (b_dir / 'removed.bin').read_bytes() == b'goodbye'
    run('dir-bundle/apply-no-overwrite', ['dir-apply', b_dir, bundle_dir, out_dir], 1, watch=[out_dir], output=out_dir, contains='exists')

    # Tampered payload fails atomically and leaves no OUT_DIR
    pfiles = sorted((bundle_dir / 'payloads').iterdir())
    assert pfiles
    victim = pfiles[0]
    raw_v = victim.read_bytes()
    victim.write_bytes(bytes([raw_v[0] ^ 0xff]) + raw_v[1:])
    bad_out_dir = root / 'v040-bad-out-dir'
    run('dir-bundle/apply-tampered', ['dir-apply', b_dir, bundle_dir, bad_out_dir, '--streaming'], 1, output=bad_out_dir, contains='BindingMismatch')
    assert not bad_out_dir.exists()

    for label, args in [
        ('bad-depth-0', ['dir-snapshot', d1, root / 'v040-u.json', '--max-depth', '0']),
        ('cross-file-opt', ['dir-snapshot', d1, root / 'v040-u.json', '--max-old-bytes', '10']),
        ('cross-dir-opt', ['signature', old_p, root / 'v040-u.out', '--max-entries', '10']),
        ('plan-missing', ['dir-plan', snap1]),
        ('compress-json', ['compress', old_p, root / 'v040-u.gz', '--json']),
        ('apply-min-savings', ['dir-apply', b_dir, bundle_dir, root / 'v040-u-dir', '--min-savings', '1']),
    ]:
        run('dir/usage-' + label, args, 2, watch=[snap1, old_p], contains='usage:')

    report['v040_summary'] = dict(
        streaming_verified=True,
        streaming_inspect_and_manifests_verified=True,
        gzip_verified=True,
        dir_commands_verified=True,
        dir_bundle_verified=True,
    )
