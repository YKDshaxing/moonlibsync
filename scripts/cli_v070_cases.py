"""0.7.0 CLI integration cases: real HTTP Range fetch-sync, range-plan, compose-delta, X25519 multi-recipient MLSENC02 seal/unseal, Ed25519 trust keyring & M-of-N quorum, zlib/deflate compression, --jobs deterministic concurrency, --meta-out/--meta directory metadata, and 35-command completions."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import threading


def exercise(root, case, report, _links):
    def run(name, args, expected=0, **kw):
        result = case('v070/' + name, args, expected, **kw)
        report['cases'][-1]['v070_added'] = True
        return result

    def inspect_run(name, args, expected=0, **kw):
        before_entries = {str(p.relative_to(root)) for p in root.rglob('*')}
        result = run(name, args, expected, text=(expected == 0), **kw)
        after_entries = {str(p.relative_to(root)) for p in root.rglob('*')}
        assert after_entries == before_entries, name
        return result

    # 1. Real local HTTP Range server + fetch-sync + range-plan!
    old_data = bytes(((i * 59 + 17 + (i // 2048) * 23) % 256) for i in range(131072))
    edit_chunk = bytes(((i * 97 + 5) % 256) for i in range(1024))
    new_data = old_data[:65536] + edit_chunk + old_data[66560:]
    assert len(new_data) == 131072

    old_file = root / 'v070-range-old.bin'
    new_file = root / 'v070-range-new.bin'
    new_sig = root / 'v070-range-new.sig'
    old_file.write_bytes(old_data)
    new_file.write_bytes(new_data)
    run('range/make-target-sig', ['signature', new_file, new_sig, '--block-size', '2048'], watch=[new_file], output=new_sig)

    # Ed25519 keys for signing new.bin (and later quorum tests)
    priv1, pub1 = root / 'v070-ed1.priv', root / 'v070-ed1.pub'
    priv2, pub2 = root / 'v070-ed2.priv', root / 'v070-ed2.pub'
    priv3, pub3 = root / 'v070-ed3.priv', root / 'v070-ed3.pub'
    run('quorum/keygen-1', ['keygen', priv1, pub1], output=pub1)
    run('quorum/keygen-2', ['keygen', priv2, pub2], output=pub2)
    run('quorum/keygen-3', ['keygen', priv3, pub3], output=pub3)
    pub1_hex = pub1.read_text(encoding='utf-8').strip()
    pub2_hex = pub2.read_text(encoding='utf-8').strip()
    k2_id = hashlib.sha256(bytes.fromhex(pub2_hex)).hexdigest()[:16]

    new_ed_sig1 = root / 'v070-new-s1.sig.json'
    new_ed_sig2 = root / 'v070-new-s2.sig.json'
    new_ed_sig3 = root / 'v070-new-s3.sig.json'
    run('range/sign-new-1', ['sign', new_file, priv1, new_ed_sig1], watch=[new_file, priv1], output=new_ed_sig1)
    run('range/sign-new-2', ['sign', new_file, priv2, new_ed_sig2], watch=[new_file, priv2], output=new_ed_sig2)
    run('range/sign-new-3', ['sign', new_file, priv3, new_ed_sig3], watch=[new_file, priv3], output=new_ed_sig3)

    # 1a. range-plan offline JSON + -o + --merge-gap / --max-ranges checks
    rp_stdout = inspect_run(
        'range-plan/stdout-json',
        ['range-plan', new_sig, str(len(new_data)), old_file, '--json'],
        watch=[new_sig, old_file],
    )
    rp_obj = json.loads(rp_stdout.stdout.decode('utf-8'))
    assert rp_obj['schema'] == 3 and rp_obj['kind'] == 'moonlibsync-range-plan'
    assert rp_obj['target_length'] == 131072
    assert rp_obj['reused_bytes'] >= 129024
    assert rp_obj['request_bytes'] <= 2048
    assert len(rp_obj['ranges']) == 1

    rp_file = root / 'v070-plan.json'
    run('range-plan/write-file', ['range-plan', new_sig, str(len(new_data)), old_file, '-o', rp_file], watch=[new_sig, old_file], output=rp_file)
    assert rp_file.read_bytes() == rp_stdout.stdout
    run('range-plan/no-overwrite', ['range-plan', new_sig, str(len(new_data)), old_file, '-o', rp_file], 1, watch=[rp_file], output=rp_file, contains='already exists')

    # Two disjoint edits to test --merge-gap and --max-ranges limit
    two_edit = old_data[:4096] + b'A' * 64 + old_data[4160:100000] + b'B' * 64 + old_data[100064:]
    two_edit_file = root / 'v070-two-edit.bin'
    two_edit_sig = root / 'v070-two-edit.sig'
    two_edit_file.write_bytes(two_edit)
    run('range-plan/two-edit-sig', ['signature', two_edit_file, two_edit_sig, '--block-size', '2048'], watch=[two_edit_file], output=two_edit_sig)
    inspect_run(
        'range-plan/reject-max-ranges-1',
        ['range-plan', two_edit_sig, str(len(two_edit)), old_file, '--merge-gap', '0', '--max-ranges', '1'],
        1,
        watch=[two_edit_sig, old_file],
        contains='LimitExceeded',
    )
    rp_merged = json.loads(inspect_run(
        'range-plan/merge-gap-coalesce',
        ['range-plan', two_edit_sig, str(len(two_edit)), old_file, '--merge-gap', '131072', '--max-ranges', '1'],
        watch=[two_edit_sig, old_file],
    ).stdout.decode('utf-8'))
    assert len(rp_merged['ranges']) == 1

    # Build a 2-of-3 quorum keyring + signature bundles for new.bin
    kr_ok = root / 'v070-kr.json'
    kr_rev = root / 'v070-kr-rev.json'
    ki_p = run(
        'quorum/keyring-init',
        ['keyring-init', '--trust', pub1, '--trust', pub2_hex, '--trust', pub3, '--quorum', '2', '-o', kr_ok, '--json'],
        watch=[pub1, pub3],
        output=kr_ok,
        text=True,
    )
    ki_obj = json.loads(ki_p.stdout.decode('utf-8'))
    assert ki_obj['min_quorum'] == 2 and ki_obj['trusted_count'] == 3 and ki_obj['revoked_count'] == 0
    run(
        'quorum/keyring-init-revoked',
        ['keyring-init', '--trust', pub1, '--trust', pub2, '--trust', pub3, '--revoke', k2_id, '--quorum', '2', '-o', kr_rev],
        watch=[pub1, pub2, pub3],
        output=kr_rev,
    )

    new_bundle_12 = root / 'v070-new-b12.json'
    new_bundle_13 = root / 'v070-new-b13.json'
    sc_p = run('quorum/sign-combine-12', ['sign-combine', new_ed_sig1, new_ed_sig2, '-o', new_bundle_12, '--json'], watch=[new_ed_sig1, new_ed_sig2], output=new_bundle_12, text=True)
    assert json.loads(sc_p.stdout.decode('utf-8'))['signature_count'] == 2
    run('quorum/sign-combine-13', ['sign-combine', new_ed_sig1, new_ed_sig3, '-o', new_bundle_13], watch=[new_ed_sig1, new_ed_sig3], output=new_bundle_13)

    # 1b. Real ThreadingHTTPServer implementing RFC 7233 HEAD + Range 206 + byte counter!
    sig_bytes = new_sig.read_bytes()
    stats_lock = threading.Lock()
    stats = dict(bytes_by_path={}, requests_by_path={})

    def record_stat(path, nbytes):
        with stats_lock:
            stats['bytes_by_path'][path] = stats['bytes_by_path'].get(path, 0) + nbytes
            stats['requests_by_path'][path] = stats['requests_by_path'].get(path, 0) + 1

    class RangeHandler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, _fmt, *_args):
            pass

        def do_HEAD(self):
            if self.path in ('/new.bin', '/new-full200.bin', '/bad-range.bin', '/missing-cr.bin', '/gzip-ce.bin', '/tampered.bin', '/status500.bin'):
                record_stat(self.path, 0)
                self.send_response(200)
                self.send_header('Content-Length', str(len(new_data)))
                self.send_header('Accept-Ranges', 'bytes')
                self.send_header('Connection', 'close')
                self.end_headers()
            elif self.path == '/new.sig':
                record_stat(self.path, 0)
                self.send_response(200)
                self.send_header('Content-Length', str(len(sig_bytes)))
                self.send_header('Connection', 'close')
                self.end_headers()
            else:
                self.send_response(404)
                self.send_header('Content-Length', '0')
                self.send_header('Connection', 'close')
                self.end_headers()

        def do_GET(self):
            if self.path == '/new.sig':
                record_stat(self.path, len(sig_bytes))
                self.send_response(200)
                self.send_header('Content-Length', str(len(sig_bytes)))
                self.send_header('Connection', 'close')
                self.end_headers()
                self.wfile.write(sig_bytes)
                return
            if self.path == '/status500.bin':
                record_stat(self.path, 0)
                self.send_response(500)
                self.send_header('Content-Length', '0')
                self.send_header('Connection', 'close')
                self.end_headers()
                return
            if self.path == '/new-full200.bin':
                record_stat(self.path, len(new_data))
                self.send_response(200)
                self.send_header('Content-Length', str(len(new_data)))
                self.send_header('Connection', 'close')
                self.end_headers()
                self.wfile.write(new_data)
                return
            if self.path in ('/new.bin', '/bad-range.bin', '/missing-cr.bin', '/gzip-ce.bin', '/tampered.bin'):
                rng = self.headers.get('Range')
                if rng:
                    m = re.fullmatch(r'bytes=(\d+)-(\d+)', rng.strip())
                    if not m:
                        self.send_response(416)
                        self.send_header('Content-Length', '0')
                        self.send_header('Connection', 'close')
                        self.end_headers()
                        return
                    start, end = int(m.group(1)), int(m.group(2))
                    if start > end or end >= len(new_data):
                        self.send_response(416)
                        self.send_header('Content-Length', '0')
                        self.send_header('Connection', 'close')
                        self.end_headers()
                        return
                    chunk = new_data[start:end + 1]
                    if self.path == '/tampered.bin':
                        chunk = bytes([chunk[0] ^ 0x01]) + chunk[1:]
                    record_stat(self.path, len(chunk))
                    self.send_response(206)
                    if self.path == '/bad-range.bin':
                        self.send_header('Content-Range', f'bytes 0-10/{len(new_data)}')
                    elif self.path != '/missing-cr.bin':
                        self.send_header('Content-Range', f'bytes {start}-{end}/{len(new_data)}')
                    if self.path == '/gzip-ce.bin':
                        self.send_header('Content-Encoding', 'gzip')
                    self.send_header('Content-Length', str(len(chunk)))
                    self.send_header('Accept-Ranges', 'bytes')
                    self.send_header('Connection', 'close')
                    self.end_headers()
                    self.wfile.write(chunk)
                    return
                record_stat(self.path, len(new_data))
                self.send_response(200)
                self.send_header('Content-Length', str(len(new_data)))
                self.send_header('Connection', 'close')
                self.end_headers()
                self.wfile.write(new_data)
                return
            self.send_response(404)
            self.send_header('Content-Length', '0')
            self.send_header('Connection', 'close')
            self.end_headers()

    server = ThreadingHTTPServer(('127.0.0.1', 0), RangeHandler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        base_url = f'http://127.0.0.1:{port}'
        fs_out = root / 'v070-fetched.bin'
        fs_res = run(
            'fetch-sync/range-206-verified',
            [
                'fetch-sync', f'{base_url}/new.bin',
                '--basis', old_file,
                '--sig-url', f'{base_url}/new.sig',
                '--verify-sig', new_ed_sig1,
                '--verify-key', pub1,
                '-o', fs_out,
                '--json',
            ],
            watch=[old_file, new_ed_sig1, pub1],
            output=fs_out,
            text=True,
        )
        assert fs_out.read_bytes() == new_data
        fs_obj = json.loads(fs_res.stdout.decode('utf-8'))
        assert fs_obj['command'] == 'fetch-sync'
        assert fs_obj['target_length'] == 131072
        assert fs_obj['reused_bytes'] >= 129024
        assert fs_obj['request_bytes'] <= 2048
        assert fs_obj['range_count'] == 1
        assert fs_obj['http_requests'] == 3  # 1 sig GET + 1 HEAD + 1 Range GET
        assert fs_obj['sha256'] == hashlib.sha256(new_data).hexdigest()

        wire_bytes_served = stats['bytes_by_path'].get('/new.bin', 0)
        assert 0 < wire_bytes_served < 20000, ('expected >80% bandwidth savings', wire_bytes_served)
        report['v070_http_range_savings'] = dict(
            target_bytes=len(new_data),
            wire_bytes_served=wire_bytes_served,
            savings_percent=round(100.0 * (1.0 - wire_bytes_served / len(new_data)), 2),
        )

        # fetch-sync with local --sig + raw 64-hex --verify-key + --target-length
        fs_out_hex = root / 'v070-fetched-hex.bin'
        run(
            'fetch-sync/local-sig-raw-hex-key',
            [
                'fetch-sync', f'{base_url}/new.bin',
                '--basis', old_file,
                '--sig', new_sig,
                '--target-length', str(len(new_data)),
                '--verify-sig', new_ed_sig1,
                '--verify-key', pub1_hex,
                '-o', fs_out_hex,
            ],
            watch=[old_file, new_sig, new_ed_sig1],
            output=fs_out_hex,
        )
        assert fs_out_hex.read_bytes() == new_data

        # fetch-sync with --verify-bundle + --keyring (pass & revoked rejection)
        fs_out_quorum = root / 'v070-fetched-quorum.bin'
        run(
            'fetch-sync/verify-bundle-quorum-ok',
            [
                'fetch-sync', f'{base_url}/new.bin',
                '--basis', old_file,
                '--sig', new_sig,
                '--verify-bundle', new_bundle_13,
                '--keyring', kr_rev,
                '-o', fs_out_quorum,
            ],
            watch=[old_file, new_sig, new_bundle_13, kr_rev],
            output=fs_out_quorum,
        )
        assert fs_out_quorum.read_bytes() == new_data
        run(
            'fetch-sync/verify-bundle-quorum-revoked-reject',
            [
                'fetch-sync', f'{base_url}/new.bin',
                '--basis', old_file,
                '--sig', new_sig,
                '--verify-bundle', new_bundle_12,
                '--keyring', kr_rev,
                '-o', root / 'v070-fetched-quorum-bad.bin',
            ],
            1,
            watch=[old_file, new_sig, new_bundle_12, kr_rev],
            output=root / 'v070-fetched-quorum-bad.bin',
            contains='quorum_not_met',
        )
        assert not (root / 'v070-fetched-quorum-bad.bin').exists()

        # fetch-sync 200 OK full-body fallback
        fs_out_200 = root / 'v070-fetched-200.bin'
        run(
            'fetch-sync/fallback-200-ok',
            [
                'fetch-sync', f'{base_url}/new-full200.bin',
                '--basis', old_file,
                '--sig', new_sig,
                '-o', fs_out_200,
            ],
            watch=[old_file, new_sig],
            output=fs_out_200,
        )
        assert fs_out_200.read_bytes() == new_data

        # fetch-sync identical basis -> 0 range requests!
        bytes_before_noop = stats['bytes_by_path'].get('/new.bin', 0)
        fs_out_noop = root / 'v070-fetched-noop.bin'
        fs_noop_res = run(
            'fetch-sync/zero-range-identical-basis',
            [
                'fetch-sync', f'{base_url}/new.bin',
                '--basis', new_file,
                '--sig', new_sig,
                '-o', fs_out_noop,
                '--json',
            ],
            watch=[new_file, new_sig],
            output=fs_out_noop,
            text=True,
        )
        assert fs_out_noop.read_bytes() == new_data
        assert stats['bytes_by_path'].get('/new.bin', 0) == bytes_before_noop
        noop_obj = json.loads(fs_noop_res.stdout.decode('utf-8'))
        assert noop_obj['range_count'] == 0 and noop_obj['request_bytes'] == 0

        # Negative fetch-sync tests: 1-byte tamper, bad Content-Range, 500 error, no-overwrite
        run(
            'fetch-sync/reject-tampered-1-byte',
            [
                'fetch-sync', f'{base_url}/tampered.bin',
                '--basis', old_file,
                '--sig', new_sig,
                '--verify-sig', new_ed_sig1,
                '--verify-key', pub1,
                '-o', root / 'v070-bad-tamper.bin',
            ],
            1,
            watch=[old_file, new_sig, new_ed_sig1, pub1],
            output=root / 'v070-bad-tamper.bin',
            contains='DigestMismatch',
        )
        assert not (root / 'v070-bad-tamper.bin').exists()

        run(
            'fetch-sync/reject-bad-content-range',
            [
                'fetch-sync', f'{base_url}/bad-range.bin',
                '--basis', old_file,
                '--sig', new_sig,
                '-o', root / 'v070-bad-cr.bin',
            ],
            1,
            watch=[old_file, new_sig],
            output=root / 'v070-bad-cr.bin',
            contains='Content-Range mismatch',
        )
        assert not (root / 'v070-bad-cr.bin').exists()

        run(
            'fetch-sync/reject-http-500',
            [
                'fetch-sync', f'{base_url}/status500.bin',
                '--basis', old_file,
                '--sig', new_sig,
                '-o', root / 'v070-bad-500.bin',
            ],
            1,
            watch=[old_file, new_sig],
            output=root / 'v070-bad-500.bin',
            contains='HTTP status 500',
        )
        assert not (root / 'v070-bad-500.bin').exists()

        run(
            'fetch-sync/no-overwrite',
            ['fetch-sync', f'{base_url}/new.bin', '--basis', old_file, '--sig', new_sig, '-o', fs_out],
            1,
            watch=[fs_out],
            output=fs_out,
            contains='already exists',
        )

        # Red-team hardening: reject 206 missing Content-Range, reject Content-Encoding: gzip, reject target > max-output-bytes before GETs, prevent CWD 64-hex key shadowing
        run(
            'fetch-sync/reject-missing-content-range',
            ['fetch-sync', f'{base_url}/missing-cr.bin', '--basis', old_file, '--sig', new_sig, '-o', root / 'v070-missing-cr.bin'],
            1,
            watch=[old_file, new_sig],
            output=root / 'v070-missing-cr.bin',
            contains='missing Content-Range',
        )
        run(
            'fetch-sync/reject-content-encoding-gzip',
            ['fetch-sync', f'{base_url}/gzip-ce.bin', '--basis', old_file, '--sig', new_sig, '-o', root / 'v070-gzip-ce.bin'],
            1,
            watch=[old_file, new_sig],
            output=root / 'v070-gzip-ce.bin',
            contains='unsupported Content-Encoding',
        )
        reqs_before_cap = stats['requests_by_path'].get('/new.bin', 0)
        run(
            'fetch-sync/reject-max-output-before-download',
            ['fetch-sync', f'{base_url}/new.bin', '--basis', old_file, '--sig', new_sig, '--max-output-bytes', '1024', '-o', root / 'v070-over-output.bin'],
            1,
            watch=[old_file, new_sig],
            output=root / 'v070-over-output.bin',
            contains='ReadLimitExceeded',
        )
        assert stats['requests_by_path'].get('/new.bin', 0) == reqs_before_cap + 1  # only HEAD, zero Range GETs

        # CWD 64-hex shadowing attack: planted attacker key file named <pub1_hex> must NEVER override inline pub1_hex
        shadow_ed_file = root / pub1_hex
        shadow_ed_file.write_text(pub3.read_text(encoding='utf-8'), encoding='utf-8')
        try:
            shadow_out = root / 'v070-shadow-ed.bin'
            run(
                'fetch-sync/no-cwd-hex-shadow-verify-key',
                ['fetch-sync', f'{base_url}/new.bin', '--basis', old_file, '--sig', new_sig, '--verify-sig', new_ed_sig1, '--verify-key', pub1_hex, '-o', shadow_out],
                watch=[old_file, new_sig, new_ed_sig1, shadow_ed_file],
                output=shadow_out,
            )
            assert shadow_out.read_bytes() == new_data
            kr_shadow = root / 'v070-kr-shadow.json'
            run(
                'quorum/no-cwd-hex-shadow-trust',
                ['keyring-init', '--trust', pub1_hex, '--quorum', '1', '-o', kr_shadow],
                watch=[shadow_ed_file],
                output=kr_shadow,
            )
            assert pub1_hex in kr_shadow.read_text(encoding='utf-8')
            assert pub3.read_text(encoding='utf-8').strip() not in kr_shadow.read_text(encoding='utf-8')
        finally:
            shadow_ed_file.unlink(missing_ok=True)
    finally:
        server.shutdown()
        server.server_close()

    # 2. compose-delta (v1 -> v2 -> v3 -> v4 composed into d14.delta patched directly onto v1)
    v1_bytes = bytes(((i * 31 + 7 + (i // 512) * 13) % 256) for i in range(40960))
    v2_bytes = v1_bytes[:4096] + b'V2-EDIT-BLOCK!' + v1_bytes[4110:]
    v3_bytes = v2_bytes[:20480] + b'V3-INSERT-MIDDLE-BYTES' + v2_bytes[20480:]
    v4_bytes = v3_bytes[:30000] + b'V4-TAIL' + v3_bytes[31500:]
    v1_f, v2_f, v3_f, v4_f = [root / f'v070-comp-v{k}.bin' for k in (1, 2, 3, 4)]
    for path, content in [(v1_f, v1_bytes), (v2_f, v2_bytes), (v3_f, v3_bytes), (v4_f, v4_bytes)]:
        path.write_bytes(content)
    s1_f, s2_f, s3_f = [root / f'v070-comp-v{k}.sig' for k in (1, 2, 3)]
    d12_f, d23_f, d34_f = root / 'v070-d12.delta', root / 'v070-d23.delta', root / 'v070-d34.delta'
    run('compose/sig1', ['signature', v1_f, s1_f, '--block-size', '512'], watch=[v1_f], output=s1_f)
    run('compose/d12', ['delta', s1_f, v2_f, d12_f], watch=[s1_f, v2_f], output=d12_f)
    run('compose/sig2', ['signature', v2_f, s2_f, '--block-size', '512'], watch=[v2_f], output=s2_f)
    run('compose/d23', ['delta', s2_f, v3_f, d23_f], watch=[s2_f, v3_f], output=d23_f)
    run('compose/sig3', ['signature', v3_f, s3_f, '--block-size', '512'], watch=[v3_f], output=s3_f)
    run('compose/d34', ['delta', s3_f, v4_f, d34_f], watch=[s3_f, v4_f], output=d34_f)

    d14_f = root / 'v070-d14.delta'
    comp_res = run('compose/chain-1-to-4', ['compose-delta', d12_f, d23_f, d34_f, '-o', d14_f, '--json'], watch=[d12_f, d23_f, d34_f], output=d14_f, text=True)
    comp_obj = json.loads(comp_res.stdout.decode('utf-8'))
    assert comp_obj['command'] == 'compose-delta'
    assert comp_obj['input_count'] == 3
    assert comp_obj['output_bytes'] == len(v4_bytes)
    assert comp_obj['sha256'] == hashlib.sha256(d14_f.read_bytes()).hexdigest()

    v4_patched = root / 'v070-comp-patched.bin'
    run('compose/patch-v1-to-v4', ['patch', v1_f, d14_f, v4_patched], watch=[v1_f, d14_f], output=v4_patched)
    assert v4_patched.read_bytes() == v4_bytes
    run('compose/no-overwrite', ['compose-delta', d12_f, d23_f, '-o', d14_f], 1, watch=[d14_f], output=d14_f, contains='already exists')

    # 3. x25519-keygen + multi-recipient MLSENC02 seal & unseal
    x_sec_a, x_pub_a = root / 'v070-xa.sec', root / 'v070-xa.pub'
    x_sec_b = root / 'v070-xb.sec'
    x_sec_c, x_pub_c = root / 'v070-xc.sec', root / 'v070-xc.pub'
    xa_res = run('x25519/keygen-a', ['x25519-keygen', '-o', x_sec_a, '--pub-out', x_pub_a, '--json'], output=x_sec_a, text=True)
    xa_obj = json.loads(xa_res.stdout.decode('utf-8'))
    assert len(xa_obj['key_id']) == 16 and len(xa_obj['public_key_hex']) == 64
    assert x_pub_a.read_text(encoding='utf-8').strip() == xa_obj['public_key_hex']

    xb_res = run('x25519/keygen-b', ['x25519-keygen', '-o', x_sec_b, '--json'], output=x_sec_b, text=True)
    xb_pub_hex = json.loads(xb_res.stdout.decode('utf-8'))['public_key_hex']
    run('x25519/keygen-c', ['x25519-keygen', '-o', x_sec_c, '--pub-out', x_pub_c], output=x_sec_c, text=True)

    env_plain = root / 'v070-env-plain.bin'
    env_plain_bytes = bytes(((i * 79 + 11) % 256) for i in range(45000))
    env_plain.write_bytes(env_plain_bytes)
    env_cipher = root / 'v070-multi.menc'
    run('x25519/seal-ab', ['seal', env_plain, env_cipher, '--recipient', x_pub_a, '--recipient', xb_pub_hex, '--chunk-size', '8192'], watch=[env_plain, x_pub_a], output=env_cipher)
    env_raw = env_cipher.read_bytes()
    assert env_raw[:8] == b'MLSENC02'

    dec_a, dec_b = root / 'v070-dec-a.bin', root / 'v070-dec-b.bin'
    run('x25519/unseal-a', ['unseal', env_cipher, dec_a, '--recipient-key', x_sec_a], watch=[env_cipher, x_sec_a], output=dec_a)
    run('x25519/unseal-b', ['unseal', env_cipher, dec_b, '--recipient-key', x_sec_b], watch=[env_cipher, x_sec_b], output=dec_b)
    assert dec_a.read_bytes() == env_plain_bytes
    assert dec_b.read_bytes() == env_plain_bytes

    run('x25519/unseal-reject-c', ['unseal', env_cipher, root / 'v070-dec-c.bin', '--recipient-key', x_sec_c], 1, watch=[env_cipher, x_sec_c], output=root / 'v070-dec-c.bin', contains='AuthenticationFailed')
    env_tampered = root / 'v070-multi-tampered.menc'
    env_tampered.write_bytes(env_raw[:-1] + bytes([env_raw[-1] ^ 0x01]))
    run('x25519/unseal-reject-tamper', ['unseal', env_tampered, root / 'v070-dec-t.bin', '--recipient-key', x_sec_a], 1, watch=[env_tampered, x_sec_a], output=root / 'v070-dec-t.bin', contains='AuthenticationFailed')

    # CWD 64-hex shadowing attack on X25519 seal --recipient <xb_pub_hex>
    shadow_x_file = root / xb_pub_hex
    shadow_x_file.write_text(x_pub_c.read_text(encoding='utf-8'), encoding='utf-8')
    try:
        shadow_env = root / 'v070-shadow.menc'
        shadow_dec_b = root / 'v070-shadow-b.bin'
        run('x25519/no-cwd-hex-shadow-seal', ['seal', env_plain, shadow_env, '--recipient', xb_pub_hex], watch=[env_plain, shadow_x_file], output=shadow_env)
        run('x25519/no-cwd-hex-shadow-unseal-b', ['unseal', shadow_env, shadow_dec_b, '--recipient-key', x_sec_b], watch=[shadow_env, x_sec_b], output=shadow_dec_b)
        assert shadow_dec_b.read_bytes() == env_plain_bytes
        run('x25519/no-cwd-hex-shadow-reject-c', ['unseal', shadow_env, root / 'v070-shadow-c.bin', '--recipient-key', x_sec_c], 1, watch=[shadow_env, x_sec_c], output=root / 'v070-shadow-c.bin', contains='AuthenticationFailed')
    finally:
        shadow_x_file.unlink(missing_ok=True)

    # 4. verify-quorum + dir-apply --archive --verify-bundle --keyring
    vq_ok = inspect_run('quorum/verify-2-of-3-json', ['verify-quorum', new_file, new_bundle_12, '--keyring', kr_ok, '--json', '--streaming'], watch=[new_file, new_bundle_12, kr_ok])
    vq_obj = json.loads(vq_ok.stdout.decode('utf-8'))
    assert vq_obj['verified'] is True and vq_obj['required_quorum'] == 2 and vq_obj['verified_count'] == 2
    vq_h = inspect_run('quorum/verify-2-of-3-human', ['verify-quorum', new_file, new_bundle_12, '--keyring', kr_ok], watch=[new_file, new_bundle_12, kr_ok]).stdout.decode('utf-8')
    assert 'verify-quorum\nverified: true\nrequired_quorum: 2\n' in vq_h

    inspect_run('quorum/reject-revoked-signer', ['verify-quorum', new_file, new_bundle_12, '--keyring', kr_rev, '--json'], 1, watch=[new_file, new_bundle_12, kr_rev], contains='quorum_not_met')
    inspect_run('quorum/verify-after-revocation-13', ['verify-quorum', new_file, new_bundle_13, '--keyring', kr_rev, '--json'], watch=[new_file, new_bundle_13, kr_rev])
    tampered_payload = root / 'v070-tampered-payload.bin'
    tampered_payload.write_bytes(new_data[:-1] + bytes([new_data[-1] ^ 0xff]))
    inspect_run('quorum/reject-tampered-payload', ['verify-quorum', tampered_payload, new_bundle_12, '--keyring', kr_ok], 1, watch=[tampered_payload, new_bundle_12, kr_ok], contains='DigestMismatch')

    # 5. compress & decompress --format zlib and deflate (buffered + streaming + zip-bomb)
    comp_in = root / 'v070-comp-in.bin'
    comp_in_bytes = (b'MoonLibSync-0.7.0-Compress-Block-' * 3000)
    comp_in.write_bytes(comp_in_bytes)
    for fmt in ('zlib', 'deflate'):
        c_buf = root / f'v070-{fmt}-buf.bin'
        c_str = root / f'v070-{fmt}-str.bin'
        d_a = root / f'v070-{fmt}-dec-a.bin'
        d_b = root / f'v070-{fmt}-dec-b.bin'
        run(f'compress/{fmt}-buf', ['compress', comp_in, c_buf, '--format', fmt], watch=[comp_in], output=c_buf)
        run(f'compress/{fmt}-str', ['compress', comp_in, c_str, '--format', fmt, '--streaming'], watch=[comp_in], output=c_str)
        assert c_buf.stat().st_size < len(comp_in_bytes) // 10
        if fmt == 'zlib':
            assert c_buf.read_bytes()[0] == 0x78
        run(f'decompress/{fmt}-cross-str', ['decompress', c_buf, d_a, '--format', fmt, '--streaming'], watch=[c_buf], output=d_a)
        run(f'decompress/{fmt}-cross-buf', ['decompress', c_str, d_b, '--format', fmt], watch=[c_str], output=d_b)
        assert d_a.read_bytes() == comp_in_bytes
        assert d_b.read_bytes() == comp_in_bytes
        run(
            f'decompress/{fmt}-zipbomb',
            ['decompress', c_buf, root / f'v070-{fmt}-bomb.out', '--format', fmt, '--streaming', '--max-output-bytes', '1024'],
            1,
            watch=[c_buf],
            output=root / f'v070-{fmt}-bomb.out',
            contains='LimitExceeded',
        )

    # 6. --jobs 4 deterministic parity + --meta-out/--meta + dir-apply --archive --verify-bundle --keyring
    d_basis = root / 'v070-dir-basis'
    d_target = root / 'v070-dir-target'
    (d_basis / 'alpha').mkdir(parents=True)
    (d_basis / 'beta').mkdir(parents=True)
    (d_target / 'alpha').mkdir(parents=True)
    (d_target / 'beta').mkdir(parents=True)
    (d_target / 'empty-dir-1').mkdir(parents=True)
    (d_target / 'nested' / 'empty-dir-2').mkdir(parents=True)
    (d_target / 'excluded-only').mkdir(parents=True)
    (d_target / 'excluded-only' / 'secret.key').write_bytes(b'ignore-me')

    for idx in range(10):
        sub = 'alpha' if idx % 2 == 0 else 'beta'
        blob = bytes(((i * (idx + 11) + idx * 7) % 256) for i in range(4096 + idx * 512))
        (d_basis / sub / f'item-{idx:02d}.bin').write_bytes(blob)
        if idx < 4:
            (d_target / sub / f'item-{idx:02d}.bin').write_bytes(blob)
        elif idx < 8:
            (d_target / sub / f'item-{idx:02d}.bin').write_bytes(blob[:1024] + b'V070-JOBS-EDIT' + blob[1038:])
    (d_target / 'alpha' / 'new-file.bin').write_bytes(b'added-in-v070')
    if os.name != 'nt':
        (d_target / 'bin').mkdir(parents=True)
        tool_sh = d_target / 'bin' / 'tool.sh'
        tool_sh.write_bytes(b'#!/bin/sh\necho v070\n')
        os.chmod(tool_sh, 0o755)

    snap_b1 = root / 'v070-b-j1.snap.json'
    snap_b4 = root / 'v070-b-j4.snap.json'
    snap_t1 = root / 'v070-t-j1.snap.json'
    snap_t4 = root / 'v070-t-j4.snap.json'
    meta_t = root / 'v070-t.meta.json'
    run('jobs/snap-basis-j1', ['dir-snapshot', d_basis, snap_b1, '--jobs', '1'], output=snap_b1)
    run('jobs/snap-basis-j4', ['dir-snapshot', d_basis, snap_b4, '--jobs', '4'], output=snap_b4)
    assert snap_b1.read_bytes() == snap_b4.read_bytes()

    run('jobs/snap-target-j1', ['dir-snapshot', d_target, snap_t1, '--exclude', '*.key', '--jobs', '1'], output=snap_t1)
    run('jobs/snap-target-j4-meta', ['dir-snapshot', d_target, snap_t4, '--exclude', '*.key', '--jobs', '4', '--meta-out', meta_t], output=snap_t4)
    assert snap_t1.read_bytes() == snap_t4.read_bytes()
    meta_doc = json.loads(meta_t.read_bytes())
    assert meta_doc['schema'] == 3 and meta_doc['kind'] == 'moonlibsync-dir-metadata'
    assert meta_doc['empty_dirs'] == ['empty-dir-1', 'nested/empty-dir-2']
    assert 'excluded-only' not in meta_doc['empty_dirs']
    if os.name != 'nt':
        assert meta_doc['executable_paths'] == ['bin/tool.sh']

    sigs_j1 = root / 'v070-sigs-j1'
    sigs_j4 = root / 'v070-sigs-j4'
    run('jobs/dir-sigs-j1', ['dir-signatures', d_basis, snap_b1, sigs_j1, '--block-size', '512', '--streaming', '--jobs', '1'], watch=[snap_b1], output=sigs_j1)
    run('jobs/dir-sigs-j4', ['dir-signatures', d_basis, snap_b4, sigs_j4, '--block-size', '512', '--streaming', '--jobs', '4'], watch=[snap_b4], output=sigs_j4)
    assert (sigs_j1 / 'signatures.json').read_bytes() == (sigs_j4 / 'signatures.json').read_bytes()

    arch_j1 = root / 'v070-pack-j1.mbundle'
    arch_j4 = root / 'v070-pack-j4.mbundle'
    arch_gz = root / 'v070-pack-j4.mbundle.gz'
    run('jobs/dir-pack-j1', ['dir-pack', snap_b1, sigs_j1, d_target, arch_j1, '--exclude', '*.key', '--archive', '--streaming', '--jobs', '1'], watch=[snap_b1], output=arch_j1)
    run('jobs/dir-pack-j4', ['dir-pack', snap_b4, sigs_j4, d_target, arch_j4, '--exclude', '*.key', '--archive', '--streaming', '--jobs', '4'], watch=[snap_b4], output=arch_j4)
    assert arch_j1.read_bytes() == arch_j4.read_bytes()
    run('jobs/dir-pack-j4-gz', ['dir-pack', snap_b4, sigs_j4, d_target, arch_gz, '--exclude', '*.key', '--archive', '--gzip', '--streaming', '--jobs', '4'], watch=[snap_b4], output=arch_gz)

    # Quorum-sign the archive & apply with --verify-bundle --keyring --meta
    as1, as2, as3 = root / 'v070-as1.json', root / 'v070-as2.json', root / 'v070-as3.json'
    ab12, ab13 = root / 'v070-ab12.json', root / 'v070-ab13.json'
    run('quorum/sign-arch-1', ['sign', arch_gz, priv1, as1], watch=[arch_gz, priv1], output=as1)
    run('quorum/sign-arch-2', ['sign', arch_gz, priv2, as2], watch=[arch_gz, priv2], output=as2)
    run('quorum/sign-arch-3', ['sign', arch_gz, priv3, as3], watch=[arch_gz, priv3], output=as3)
    run('quorum/combine-arch-12', ['sign-combine', as1, as2, '-o', ab12], watch=[as1, as2], output=ab12)
    run('quorum/combine-arch-13', ['sign-combine', as1, as3, '-o', ab13], watch=[as1, as3], output=ab13)

    d_out = root / 'v070-dir-out'
    run(
        'dir-apply/quorum-and-meta',
        [
            'dir-apply', d_basis, arch_gz, d_out,
            '--archive', '--gzip', '--streaming',
            '--verify-bundle', ab13, '--keyring', kr_rev,
            '--meta', meta_t,
        ],
        watch=[arch_gz, ab13, kr_rev, meta_t],
        output=d_out,
    )
    assert (d_out / 'empty-dir-1').is_dir()
    assert (d_out / 'nested' / 'empty-dir-2').is_dir()
    if os.name != 'nt':
        assert ((d_out / 'bin' / 'tool.sh').stat().st_mode & 0o777) == 0o700

    # dir-verify --jobs 4 matches --jobs 1
    dv1 = inspect_run('jobs/dir-verify-j1', ['dir-verify', d_out, snap_t4, '--json', '--jobs', '1'], watch=[snap_t4])
    dv4 = inspect_run('jobs/dir-verify-j4', ['dir-verify', d_out, snap_t4, '--json', '--jobs', '4'], watch=[snap_t4])
    assert dv1.stdout == dv4.stdout and json.loads(dv4.stdout.decode('utf-8'))['ok'] is True

    # dir-apply rejects revoked quorum bundle leaving zero OUT_DIR
    d_out_fail = root / 'v070-dir-out-fail'
    run(
        'dir-apply/reject-revoked-quorum',
        [
            'dir-apply', d_basis, arch_gz, d_out_fail,
            '--archive', '--gzip',
            '--verify-bundle', ab12, '--keyring', kr_rev,
        ],
        1,
        watch=[arch_gz, ab12, kr_rev],
        output=d_out_fail,
        contains='quorum_not_met',
    )
    assert not d_out_fail.exists()

    # 7. Shell completions include all 7 new commands and new flags
    new_cmds = ['compose-delta', 'range-plan', 'fetch-sync', 'x25519-keygen', 'keyring-init', 'sign-combine', 'verify-quorum']
    new_flags = ['--jobs', '--format', '--recipient', '--recipient-key', '--keyring', '--quorum', '--trust', '--revoke', '--meta-out', '--meta', '--sig-url', '--merge-gap', '--max-ranges', '--verify-bundle']
    for shell in ('bash', 'zsh', 'powershell'):
        cp = inspect_run(f'completions/{shell}', ['completions', shell])
        text = cp.stdout.decode('utf-8')
        assert '0.7.0' in text
        for cmd_name in new_cmds:
            assert cmd_name in text, (shell, cmd_name)
        for flag in new_flags:
            assert flag in text, (shell, flag)

    # 8. Usage rejections (exit 2)
    for label, args in [
        ('compose-one-delta', ['compose-delta', d12_f, '-o', root / 'u1']),
        ('fetch-sync-no-basis', ['fetch-sync', 'http://127.0.0.1:9/a', '--sig', new_sig, '-o', root / 'u2']),
        ('fetch-sync-bad-scheme', ['fetch-sync', 'ftp://127.0.0.1/a', '--basis', old_file, '--sig', new_sig, '-o', root / 'u3']),
        ('fetch-sync-empty-host', ['fetch-sync', 'http:///path', '--basis', old_file, '--sig', new_sig, '-o', root / 'u10']),
        ('seal-recipient-plus-key', ['seal', env_plain, root / 'u4', '--recipient', x_pub_a, '--key-file', x_sec_a]),
        ('unseal-recipient-streaming', ['unseal', env_cipher, root / 'u5', '--recipient-key', x_sec_a, '--streaming']),
        ('compress-bad-format', ['compress', comp_in, root / 'u6', '--format', 'lz4']),
        ('jobs-zero', ['dir-snapshot', d_basis, root / 'u7', '--jobs', '0']),
        ('jobs-65', ['dir-snapshot', d_basis, root / 'u8', '--jobs', '65']),
        ('dir-apply-bundle-no-archive', ['dir-apply', d_basis, arch_gz, root / 'u9', '--verify-bundle', ab12, '--keyring', kr_ok]),
        ('verify-quorum-no-keyring', ['verify-quorum', new_file, new_bundle_12]),
    ]:
        run('usage/' + label, args, 2, contains='usage:')

    report['v070_summary'] = dict(
        range_plan_and_fetch_sync_verified=True,
        compose_delta_verified=True,
        x25519_multi_recipient_verified=True,
        quorum_keyring_verified=True,
        zlib_deflate_verified=True,
        jobs_concurrency_parity_verified=True,
        dir_metadata_verified=True,
        completions_35_verified=True,
    )
