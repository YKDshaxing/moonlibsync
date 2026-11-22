"""0.3.2 CLI integration cases: inspect-manifest (schema 1/2) and --max-* budget overrides."""
import hashlib
import json
import struct


def _digest(data):
    return dict(byte_length=str(len(data)), sha256=hashlib.sha256(data).hexdigest())


def exercise(root, case, report, links):
    def run(name, args, expected=0, **kw):
        result = case('v032/' + name, args, expected, **kw)
        report['cases'][-1]['v032_added'] = True
        return result

    def inspect_run(name, args, expected=0, **kw):
        before_entries = {str(p.relative_to(root)) for p in root.rglob('*')}
        result = run(name, args, expected, text=(expected == 0), **kw)
        after_entries = {str(p.relative_to(root)) for p in root.rglob('*')}
        assert after_entries == before_entries, name
        return result

    # Prepare fixtures covering all 4 schema 1 / schema 2 manifest variants.
    old = root / 'v032-old.bin'
    sig = root / 'v032-sig.bin'
    info = root / 'v032-info.json'
    new_delta = root / 'v032-new-delta.bin'
    delta_bin = root / 'v032-delta.bin'
    update_manifest = root / 'v032-update.json'
    transfer_delta = root / 'v032-transfer-delta.json'
    new_full = root / 'v032-new-full.bin'
    cand_full = root / 'v032-cand-full.bin'
    transfer_full = root / 'v032-transfer-full.json'

    old_bytes = (b'ABCD1234' * 16) + (b'WXYZ5678' * 16)
    new_delta_bytes = (b'ABCD1234' * 16) + b'PATCH' + (b'WXYZ5678' * 15) + b'567'
    new_full_bytes = b'completely-unrelated-payload'
    old.write_bytes(old_bytes)
    new_delta.write_bytes(new_delta_bytes)
    new_full.write_bytes(new_full_bytes)

    run('prep/sig', ['signature', old, sig, '--block-size', '32'], watch=[old], output=sig)
    run('prep/info', ['basis-info', old, sig, info], watch=[old, sig], output=info)
    run('prep/delta', ['delta', sig, new_delta, delta_bin], watch=[sig, new_delta], output=delta_bin)
    run('prep/update', ['make-manifest', info, sig, new_delta, delta_bin, update_manifest], watch=[info, sig, new_delta, delta_bin], output=update_manifest)
    run('prep/transfer-delta', ['make-transfer-manifest', info, sig, new_delta, delta_bin, transfer_delta], watch=[info, sig, new_delta, delta_bin], output=transfer_delta)
    run('prep/cand-full', ['delta', sig, new_full, cand_full], watch=[sig, new_full], output=cand_full)
    run('prep/transfer-full', ['make-transfer-manifest', info, sig, new_full, cand_full, transfer_full], watch=[info, sig, new_full, cand_full], output=transfer_full)

    basis_d = _digest(old_bytes)
    sig_d = _digest(sig.read_bytes())
    delta_d = _digest(delta_bin.read_bytes())
    result_delta_d = _digest(new_delta_bytes)
    full_d = _digest(new_full_bytes)

    expected_manifests = [
        ('s1-info', info, dict(manifest_schema_version=1, kind='moonlibsync-basis-info', basis=basis_d, signature=sig_d),
         ['manifest_schema_version: 1', 'kind: moonlibsync-basis-info', 'basis.byte_length: 256 bytes', 'signature.sha256: ' + sig_d['sha256']]),
        ('s1-update', update_manifest, dict(manifest_schema_version=1, kind='librsync-delta', basis=basis_d, signature=sig_d, delta=delta_d, result=result_delta_d),
         ['manifest_schema_version: 1', 'kind: librsync-delta', 'delta.byte_length: ' + delta_d['byte_length'] + ' bytes', 'result.sha256: ' + result_delta_d['sha256']]),
        ('s2-delta', transfer_delta, dict(manifest_schema_version=2, kind='librsync-delta', basis=basis_d, signature=sig_d, payload=delta_d, result=result_delta_d),
         ['manifest_schema_version: 2', 'kind: librsync-delta', 'payload.byte_length: ' + delta_d['byte_length'] + ' bytes', 'result.sha256: ' + result_delta_d['sha256']]),
        ('s2-full', transfer_full, dict(manifest_schema_version=2, kind='full-file', payload=full_d, result=full_d),
         ['manifest_schema_version: 2', 'kind: full-file', 'payload.byte_length: ' + full_d['byte_length'] + ' bytes', 'result.sha256: ' + full_d['sha256']]),
    ]

    for label, path, wanted_manifest, human_needles in expected_manifests:
        jp = inspect_run('inspect-manifest/' + label + '-json', ['inspect-manifest', path, '--json'], watch=[path])
        text = jp.stdout.decode('utf-8', errors='strict')
        assert text.endswith('\n') and not text.startswith('\ufeff')
        obj = json.loads(text)
        assert obj == dict(schema_version=1, command='inspect-manifest', manifest=wanted_manifest), (label, obj)

        hp = inspect_run('inspect-manifest/' + label + '-human', ['inspect-manifest', path], watch=[path])
        htext = hp.stdout.decode('utf-8', errors='strict')
        assert htext.startswith('inspect-manifest\n')
        assert 'actual referenced files were not read or authenticated' in htext
        for needle in human_needles:
            assert needle in htext, (label, needle, htext)

    # Literal '-' and '--' separator for inspect-manifest (save & restore existing '-').
    dash = root / '-'
    saved_dash = dash.read_bytes() if dash.exists() else None
    try:
        dash.write_bytes(transfer_full.read_bytes())
        dp = inspect_run('inspect-manifest/dash', ['inspect-manifest', '--json', '--', '-'], watch=[dash])
        assert json.loads(dp.stdout)['manifest']['kind'] == 'full-file'
    finally:
        if saved_dash is not None:
            dash.write_bytes(saved_dash)
        elif dash.exists():
            dash.unlink()

    # inspect-manifest strict error and usage cases.
    bad_json = root / 'v032-bad-json.json'; bad_json.write_bytes(b'{')
    bad_schema = root / 'v032-bad-schema.json'; bad_schema.write_bytes(b'{"schema_version":9,"kind":"none"}')
    oversize_manifest = root / 'v032-oversize.json'; oversize_manifest.write_bytes(b' ' * 65537)
    for label, args, needle in [
        ('bad-json', ['inspect-manifest', bad_json, '--json'], 'InvalidJson'),
        ('bad-schema', ['inspect-manifest', bad_schema, '--json'], 'InvalidSchema'),
        ('oversize', ['inspect-manifest', oversize_manifest, '--json'], 'ReadLimitExceeded'),
        ('tight-limit', ['inspect-manifest', info, '--max-old-bytes', '10', '--json'], 'ResourceLimit:basis'),
        ('missing', ['inspect-manifest', root / 'v032-missing.json', '--json'], 'read'),
        ('directory', ['inspect-manifest', root, '--json'], 'unsupported input'),
    ]:
        inspect_run('inspect-manifest/fail-' + label, args, 1, watch=[info, bad_json, bad_schema, oversize_manifest], contains=needle)

    if links:
        link = root / 'v032-manifest-link'
        link.symlink_to(info)
        inspect_run('inspect-manifest/fail-symlink', ['inspect-manifest', link, '--json'], 1, watch=[info, link], contains='leaf symlink')

    for label, args in [
        ('missing-path', ['inspect-manifest']),
        ('extra-path', ['inspect-manifest', info, info]),
        ('dup-json', ['inspect-manifest', info, '--json', '--json']),
        ('unknown-opt', ['inspect-manifest', info, '--wat']),
    ]:
        inspect_run('inspect-manifest/usage-' + label, args, 2, watch=[info], contains='usage:')

    # --max-* limit overrides on signature, delta, patch and usage errors.
    tiny = root / 'v032-tiny.bin'; tiny.write_bytes(b'abc')
    tiny4 = root / 'v032-tiny4.bin'; tiny4.write_bytes(b'wxyz')
    tiny_sig = root / 'v032-tiny.sig'
    tiny_delta = root / 'v032-tiny.delta'
    tiny_out = root / 'v032-tiny.out'

    run('limits/sig-old-reject', ['signature', tiny, root / 'v032-fail-old.sig', '--max-old-bytes', '2'], 1, watch=[tiny], output=root / 'v032-fail-old.sig', contains='ReadLimitExceeded')
    run('limits/sig-old-exact', ['signature', tiny, tiny_sig, '--max-old-bytes', '3'], watch=[tiny], output=tiny_sig)

    big_block_sig_a = root / 'v032-bigblock-a.sig'
    big_block_sig_b = root / 'v032-bigblock-b.sig'
    run('limits/sig-block-before', ['signature', tiny, big_block_sig_a, '--block-size', '1048577', '--max-block-bytes', '2097152'], watch=[tiny], output=big_block_sig_a)
    run('limits/sig-block-after', ['signature', tiny, big_block_sig_b, '--max-block-bytes', '2097152', '--block-size', '1048577'], watch=[tiny], output=big_block_sig_b)
    assert big_block_sig_a.read_bytes() == big_block_sig_b.read_bytes()
    assert struct.unpack('>III', big_block_sig_a.read_bytes()[:12]) == (0x72730147, 1048577, 32)

    run('limits/delta-work-reject', ['delta', tiny_sig, tiny4, root / 'v032-fail-work.delta', '--max-match-work', '1'], 1, watch=[tiny_sig, tiny4], output=root / 'v032-fail-work.delta', contains='LimitExceeded')
    run('limits/delta-work-ok', ['delta', tiny_sig, tiny4, tiny_delta, '--max-match-work', '4096'], watch=[tiny_sig, tiny4], output=tiny_delta)

    run('limits/patch-out-reject', ['patch', tiny, tiny_delta, root / 'v032-fail-out.bin', '--max-output-bytes', '3'], 1, watch=[tiny, tiny_delta], output=root / 'v032-fail-out.bin', contains='LimitExceeded')
    run('limits/patch-out-ok', ['patch', tiny, tiny_delta, tiny_out, '--max-output-bytes', '4'], watch=[tiny, tiny_delta], output=tiny_out)
    assert tiny_out.read_bytes() == b'wxyz'

    for label, args in [
        ('max-block-zero', ['signature', tiny, root / 'v032-u.out', '--max-block-bytes', '0']),
        ('max-old-neg', ['signature', tiny, root / 'v032-u.out', '--max-old-bytes', '-1']),
        ('max-old-over', ['signature', tiny, root / 'v032-u.out', '--max-old-bytes', '2147483648']),
        ('max-dup', ['signature', tiny, root / 'v032-u.out', '--max-old-bytes', '10', '--max-old-bytes', '20']),
        ('max-missing-val', ['delta', tiny_sig, tiny4, root / 'v032-u.out', '--max-match-work']),
    ]:
        run('limits/usage-' + label, args, 2, watch=[tiny, tiny_sig, tiny4], output=root / 'v032-u.out', contains='usage:')

    report['v032_summary'] = dict(inspect_manifest_variants=4, limit_flags_tested=True)
