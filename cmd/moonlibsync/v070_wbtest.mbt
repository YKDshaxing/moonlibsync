// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "cli v070 option parsing and usage gating for all 7 new commands and flags" {
  // range-plan (stdout & -o)
  let rp_stdout = parse_plan([
    "range-plan", "target.sig", "131072", "basis.bin", "--merge-gap", "1024", "--max-ranges",
    "16", "--json",
  ])
  assert_eq(rp_stdout.inputs, ["target.sig", "131072", "basis.bin"])
  assert_eq(rp_stdout.target_length, Some(131072L))
  assert_eq(rp_stdout.merge_gap_bytes, 1024L)
  assert_eq(rp_stdout.max_ranges, 16L)
  assert_true(rp_stdout.mode is Inspect(true) && rp_stdout.json)

  let rp_file = parse_plan([
    "range-plan", "target.sig", "0", "basis.bin", "-o", "plan.json",
  ])
  assert_true(rp_file.mode is WriteFile("plan.json") && !rp_file.json)
  assert_eq(rp_file.target_length, Some(0L))

  // fetch-sync (--sig & --sig-url, --verify-sig & --verify-bundle)
  let fs1 = parse_plan([
    "fetch-sync", "http://127.0.0.1:8080/new.bin", "--basis", "old.bin", "--sig-url",
    "http://127.0.0.1:8080/new.sig", "-o", "out.bin", "--target-length", "65536",
    "--merge-gap", "0", "--max-ranges", "32", "--verify-sig", "new.sig.json", "--verify-key",
    "pub.key", "--json", "--progress",
  ])
  assert_eq(fs1.inputs, ["http://127.0.0.1:8080/new.bin"])
  assert_eq(fs1.basis_path, Some("old.bin"))
  assert_eq(fs1.sig_url, Some("http://127.0.0.1:8080/new.sig"))
  assert_eq(fs1.sig_file, None)
  assert_eq(fs1.target_length, Some(65536L))
  assert_eq(fs1.merge_gap_bytes, 0L)
  assert_eq(fs1.max_ranges, 32L)
  assert_eq(fs1.verify_sig, Some("new.sig.json"))
  assert_eq(fs1.verify_keys, ["pub.key"])
  assert_true(fs1.mode is WriteFile("out.bin") && fs1.json && fs1.progress)

  let fs2 = parse_plan([
    "fetch-sync", "https://example.com/a", "--basis", "old.bin", "--sig", "a.sig",
    "-o", "out.bin", "--verify-bundle", "b.json", "--keyring", "kr.json",
  ])
  assert_eq(fs2.sig_file, Some("a.sig"))
  assert_eq(fs2.verify_bundle, Some("b.json"))
  assert_eq(fs2.keyring_file, Some("kr.json"))

  // compose-delta
  let cd = parse_plan([
    "compose-delta", "d1.delta", "d2.delta", "d3.delta", "-o", "d13.delta", "--json",
    "--max-delta-bytes", "65536",
  ])
  assert_eq(cd.inputs, ["d1.delta", "d2.delta", "d3.delta"])
  assert_true(cd.mode is WriteFile("d13.delta") && cd.json)
  assert_eq(cd.limits.max_delta_bytes, 65536L)

  // x25519-keygen
  let xk = parse_plan([
    "x25519-keygen", "-o", "sec.key", "--pub-out", "pub.key", "--json",
  ])
  assert_eq(xk.inputs, [])
  assert_true(xk.mode is WriteFile("sec.key") && xk.json)
  assert_eq(xk.pub_out, Some("pub.key"))

  // keyring-init
  let ki = parse_plan([
    "keyring-init", "--trust", "k1.pub", "--trust", "k2.pub", "--revoke", "0123456789abcdef",
    "--quorum", "2", "-o", "kr.json", "--json",
  ])
  assert_eq(ki.inputs, [])
  assert_eq(ki.trust_keys, ["k1.pub", "k2.pub"])
  assert_eq(ki.revoked_key_ids, ["0123456789abcdef"])
  assert_eq(ki.quorum, 2)
  assert_true(ki.mode is WriteFile("kr.json") && ki.json)

  // sign-combine & verify-quorum
  let sc = parse_plan([
    "sign-combine", "s1.json", "s2.json", "-o", "bundle.json", "--json",
  ])
  assert_eq(sc.inputs, ["s1.json", "s2.json"])
  assert_true(sc.mode is WriteFile("bundle.json") && sc.json)

  let vq = parse_plan([
    "verify-quorum", "payload.bin", "bundle.json", "--keyring", "kr.json", "--json",
    "--streaming", "--progress",
  ])
  assert_eq(vq.inputs, ["payload.bin", "bundle.json"])
  assert_eq(vq.keyring_file, Some("kr.json"))
  assert_true(vq.mode is Inspect(true) && vq.streaming && vq.progress)

  // multi-recipient seal & unseal
  let sl_r = parse_plan([
    "seal", "in.bin", "out.menc", "--recipient", "r1.pub", "--recipient", "r2.pub",
    "--chunk-size", "4096",
  ])
  assert_eq(sl_r.recipients, ["r1.pub", "r2.pub"])
  assert_eq(sl_r.seal_options.chunk_size, 4096)

  let usl_r = parse_plan([
    "unseal", "in.menc", "out.bin", "--recipient-key", "r1.sec",
  ])
  assert_eq(usl_r.recipient_key, Some("r1.sec"))

  // --format on compress/decompress
  let cz = parse_plan(["compress", "a", "b", "--format", "zlib", "--streaming"])
  assert_true(cz.compress_format is Zlib && cz.streaming)
  let dd = parse_plan(["decompress", "a", "b", "--format", "deflate"])
  assert_true(dd.compress_format is Deflate)

  // --jobs & --meta-out & --meta & --verify-bundle on dir-*
  let ds = parse_plan([
    "dir-snapshot", "d", "s.json", "--jobs", "4", "--meta-out", "m.json",
  ])
  assert_eq(ds.jobs, 4)
  assert_eq(ds.meta_out, Some("m.json"))
  let dsig = parse_plan(["dir-signatures", "d", "s.json", "sigs", "--jobs", "8"])
  assert_eq(dsig.jobs, 8)
  let dp = parse_plan([
    "dir-pack", "b.json", "sigs", "t", "out.mbundle", "--archive", "--jobs", "4",
  ])
  assert_eq(dp.jobs, 4)
  let dv = parse_plan(["dir-verify", "d", "s.json", "--jobs", "4", "--json"])
  assert_eq(dv.jobs, 4)
  let da = parse_plan([
    "dir-apply", "b", "a.mbundle.gz", "out", "--archive", "--gzip", "--verify-bundle",
    "sigb.json", "--keyring", "kr.json", "--meta", "m.json",
  ])
  assert_eq(da.verify_bundle, Some("sigb.json"))
  assert_eq(da.keyring_file, Some("kr.json"))
  assert_eq(da.meta_file, Some("m.json"))

  // Usage rejections
  for
    bad in [
      ["range-plan", "sig", "not-a-num", "basis"],
      ["range-plan", "sig", "10"],
      ["range-plan", "sig", "10", "basis", "--max-ranges", "0"],
      ["range-plan", "sig", "10", "basis", "--max-ranges", "65537"],
      ["range-plan", "sig", "10", "basis", "--merge-gap", "-1"],
      ["range-plan", "sig", "10", "basis", "--streaming"],
      ["fetch-sync", "http://127.0.0.1/a", "--sig", "s", "-o", "o"],
      ["fetch-sync", "http://127.0.0.1/a", "--basis", "b", "-o", "o"],
      [
        "fetch-sync", "http://127.0.0.1/a", "--basis", "b", "--sig", "s", "--sig-url",
        "http://127.0.0.1/s", "-o", "o",
      ],
      ["fetch-sync", "http://127.0.0.1/a", "--basis", "b", "--sig", "s"],
      [
        "fetch-sync", "ftp://127.0.0.1/a", "--basis", "b", "--sig", "s", "-o", "o",
      ],
      [
        "fetch-sync", "http://127.0.0.1/a", "--basis", "b", "--sig-url", "ftp://127.0.0.1/s",
        "-o", "o",
      ],
      [
        "fetch-sync", "http://127.0.0.1/a", "--basis", "b", "--sig", "s", "-o", "o",
        "--verify-sig", "sg", "--verify-key", "k", "--verify-bundle", "bd", "--keyring",
        "kr",
      ],
      [
        "fetch-sync", "http://127.0.0.1/a", "--basis", "b", "--sig", "s", "-o", "o",
        "--verify-bundle", "bd",
      ],
      ["compose-delta", "only-one.delta", "-o", "out.delta"],
      ["compose-delta", "d1.delta", "d2.delta"],
      [
        "compose-delta", "d1.delta", "d2.delta", "-o", "out.delta", "--streaming",
      ],
      ["x25519-keygen"],
      ["x25519-keygen", "extra", "-o", "sec.key"],
      ["x25519-keygen", "-o", "sec.key", "--progress"],
      ["keyring-init", "--quorum", "1", "-o", "kr.json"],
      ["keyring-init", "--trust", "k.pub", "-o", "kr.json"],
      ["keyring-init", "--trust", "k.pub", "--quorum", "0", "-o", "kr.json"],
      ["keyring-init", "--trust", "k.pub", "--quorum", "65", "-o", "kr.json"],
      ["keyring-init", "--trust", "k.pub", "--quorum", "1"],
      ["sign-combine", "-o", "b.json"],
      ["sign-combine", "s1.json"],
      ["verify-quorum", "p.bin", "b.json"],
      ["verify-quorum", "p.bin", "--keyring", "kr.json"],
      ["seal", "i", "o", "--recipient", "r.pub", "--key-file", "k"],
      ["seal", "i", "o", "--recipient", "r.pub", "--passphrase-file", "p"],
      ["seal", "i", "o", "--recipient", "r.pub", "--argon2-memory", "64"],
      ["seal", "i", "o", "--recipient", "r.pub", "--streaming"],
      ["unseal", "i", "o", "--recipient-key", "r.sec", "--key-file", "k"],
      ["unseal", "i", "o", "--recipient-key", "r.sec", "--streaming"],
      ["compress", "i", "o", "--format", "brotli"],
      ["compress", "i", "o", "--format", "gzip", "--format", "zlib"],
      ["signature", "o", "s", "--format", "gzip"],
      ["dir-snapshot", "d", "s", "--jobs", "0"],
      ["dir-snapshot", "d", "s", "--jobs", "65"],
      ["dir-apply", "b", "bd", "o", "--jobs", "2"],
      ["dir-apply", "b", "bd", "o", "--verify-bundle", "sb", "--keyring", "kr"],
      [
        "dir-apply", "b", "bd", "o", "--archive", "--verify-sig", "s", "--verify-key",
        "k", "--verify-bundle", "sb", "--keyring", "kr",
      ],
      ["dir-snapshot", "d", "s", "--meta", "m.json"],
      ["dir-apply", "b", "bd", "o", "--meta-out", "m.json"],
    ] {
    let rejected = try {
      let _ = parse_plan(bad)
      false
    } catch {
      Usage(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
async test "cli v070 range-plan stdout file output merge-gap and max-ranges" {
  cli_test_scope(dir => {
    let old = Bytes::makei(40960, i => {
      ((i * 37 + 13 + i / 1024 * 17) % 256).to_byte()
    })
    let edited = old[0:4096].to_owned() +
      b"EDIT-ONE-V070-RANGE!" +
      old[4116:28672].to_owned() +
      b"EDIT-TWO-V070-RANGE!" +
      old[28692:].to_owned()
    let old_p = dir + "/old.bin"
    let new_p = dir + "/new.bin"
    let sig_p = dir + "/new.sig"
    let plan_p = dir + "/plan.json"
    @fs.write_binary(old_p, old, create_mode=CreateNew)
    @fs.write_binary(new_p, edited, create_mode=CreateNew)
    execute(parse_plan(["signature", new_p, sig_p, "--block-size", "1024"]))

    let stdout_buf = StringBuilder()
    execute_range_plan(
      parse_plan([
        "range-plan",
        sig_p,
        edited.length().to_string(),
        old_p,
        "--merge-gap",
        "0",
        "--json",
      ]),
      None,
      writer=b => stdout_buf.write_string(@utf8.decode(b)),
    )
    execute_range_plan(
      parse_plan([
        "range-plan",
        sig_p,
        edited.length().to_string(),
        old_p,
        "--merge-gap",
        "0",
        "-o",
        plan_p,
      ]),
      Some(plan_p),
    )
    let file_str = @utf8.decode(bounded_read(plan_p, 65536L))
    assert_eq(stdout_buf.to_string(), file_str)
    assert_true(file_str.contains("\"kind\":\"moonlibsync-range-plan\""))
    assert_true(file_str.contains("\"reused_bytes\":38912"))
    assert_true(file_str.contains("\"fetch_bytes\":2048"))

    // --max-ranges 1 rejects 2 disjoint ranges when --merge-gap 0
    expect_file_failure(
      () => {
        execute_range_plan(
          parse_plan([
            "range-plan",
            sig_p,
            edited.length().to_string(),
            old_p,
            "--merge-gap",
            "0",
            "--max-ranges",
            "1",
          ]),
          None,
        )
      },
      "LimitExceeded",
    )

    // Large --merge-gap merges both ranges into 1 range so --max-ranges 1 passes
    let merged_buf = StringBuilder()
    execute_range_plan(
      parse_plan([
        "range-plan",
        sig_p,
        edited.length().to_string(),
        old_p,
        "--merge-gap",
        "32768",
        "--max-ranges",
        "1",
      ]),
      None,
      writer=b => merged_buf.write_string(@utf8.decode(b)),
    )
    assert_true(merged_buf.to_string().contains("\"request_bytes\":25600"))

    // No-overwrite on -o
    expect_file_failure(
      () => {
        execute_range_plan(
          parse_plan([
            "range-plan",
            sig_p,
            edited.length().to_string(),
            old_p,
            "-o",
            plan_p,
          ]),
          Some(plan_p),
        )
      },
      "already exists",
    )
  })
}

///|
async test "cli v070 compose-delta chain v1->v2->v3->v4 and patch parity" {
  cli_test_scope(dir => {
    let v1 = Bytes::makei(32768, i => {
      ((i * 53 + 7 + i / 512 * 11) % 256).to_byte()
    })
    let v2 = v1[0:4000].to_owned() + b"PATCH-STEP-TWO" + v1[4014:].to_owned()
    let v3 = v2[0:16000].to_owned() +
      b"PATCH-STEP-THREE-INSERT" +
      v2[16000:].to_owned()
    let v4 = v3[0:24000].to_owned() + b"STEP-FOUR" + v3[25000:].to_owned()

    let p1 = dir + "/v1.bin"
    let p2 = dir + "/v2.bin"
    let p3 = dir + "/v3.bin"
    let p4 = dir + "/v4.bin"
    @fs.write_binary(p1, v1, create_mode=CreateNew)
    @fs.write_binary(p2, v2, create_mode=CreateNew)
    @fs.write_binary(p3, v3, create_mode=CreateNew)
    @fs.write_binary(p4, v4, create_mode=CreateNew)

    let s1 = dir + "/v1.sig"
    let s2 = dir + "/v2.sig"
    let s3 = dir + "/v3.sig"
    let d12 = dir + "/d12.delta"
    let d23 = dir + "/d23.delta"
    let d34 = dir + "/d34.delta"
    let d14 = dir + "/d14.delta"
    let out4 = dir + "/out4.bin"

    execute(parse_plan(["signature", p1, s1, "--block-size", "512"]))
    execute(parse_plan(["delta", s1, p2, d12]))
    execute(parse_plan(["signature", p2, s2, "--block-size", "512"]))
    execute(parse_plan(["delta", s2, p3, d23]))
    execute(parse_plan(["signature", p3, s3, "--block-size", "512"]))
    execute(parse_plan(["delta", s3, p4, d34]))

    let json_out = StringBuilder()
    execute_compose_delta(
      parse_plan(["compose-delta", d12, d23, d34, "-o", d14, "--json"]),
      d14,
      writer=b => json_out.write_string(@utf8.decode(b)),
    )
    let j = json_out.to_string()
    assert_true(j.contains("\"command\":\"compose-delta\""))
    assert_true(j.contains("\"input_count\":3"))
    assert_true(j.contains("\"output_bytes\":\{v4.length()}"))

    execute(parse_plan(["patch", p1, d14, out4]))
    assert_eq(bounded_read(out4, 65536L), v4)

    // No-overwrite refused
    expect_file_failure(
      () => execute(parse_plan(["compose-delta", d12, d23, "-o", d14])),
      "already exists",
    )
  })
}

///|
async test "cli v070 x25519-keygen and multi-recipient MLSENC02 seal unseal" {
  cli_test_scope(dir => {
    let sec_a = dir + "/a.sec"
    let pub_a = dir + "/a.pub"
    let sec_b = dir + "/b.sec"
    let sec_c = dir + "/c.sec"
    let pub_c = dir + "/c.pub"

    let out_a = StringBuilder()
    execute_x25519_keygen(
      parse_plan(["x25519-keygen", "-o", sec_a, "--pub-out", pub_a, "--json"]),
      sec_a,
      writer=b => out_a.write_string(@utf8.decode(b)),
    )
    assert_true(out_a.to_string().contains("\"command\":\"x25519-keygen\""))
    assert_eq(bounded_read(sec_a, 128L).length(), 65)
    assert_eq(bounded_read(pub_a, 128L).length(), 65)

    // Generate B without --pub-out; derive raw hex pubkey from secret file
    let out_b = StringBuilder()
    execute_x25519_keygen(parse_plan(["x25519-keygen", "-o", sec_b]), sec_b, writer=b => {
      out_b.write_string(@utf8.decode(b))
    })
    let b_secret = read_hex_key_file(sec_b, "x25519_secret")
    let b_pub_hex = @crypto.encode_key_hex(
      @crypto.x25519_public_from_secret(b_secret),
    )
    assert_true(out_b.to_string().contains("public_key_hex: " + b_pub_hex))

    execute_x25519_keygen(
      parse_plan(["x25519-keygen", "-o", sec_c, "--pub-out", pub_c]),
      sec_c,
      writer=_ => (),
    )

    // Refuses overwrite & identical paths
    expect_file_failure(
      () => {
        execute(
          parse_plan(["x25519-keygen", "-o", sec_a, "--pub-out", dir + "/u.pub"]),
        )
      },
      "already exists",
    )
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "x25519-keygen",
            "-o",
            dir + "/same.k",
            "--pub-out",
            dir + "/same.k",
          ]),
        )
      },
      "distinct",
    )

    // Multi-recipient seal using file path for A and raw hex for B
    let plain = Bytes::makei(20000, i => ((i * 43 + 5) % 256).to_byte())
    let plain_p = dir + "/plain.bin"
    let env_p = dir + "/multi.menc"
    let dec_a = dir + "/dec-a.bin"
    let dec_b = dir + "/dec-b.bin"
    @fs.write_binary(plain_p, plain, create_mode=CreateNew)

    execute(
      parse_plan([
        "seal", plain_p, env_p, "--recipient", pub_a, "--recipient", b_pub_hex, "--chunk-size",
        "4096",
      ]),
    )
    let env_bytes = bounded_read(env_p, 65536L)
    assert_eq(env_bytes[0:8].to_owned(), b"MLSENC02")

    // Both A and B decrypt identically
    execute(parse_plan(["unseal", env_p, dec_a, "--recipient-key", sec_a]))
    execute(parse_plan(["unseal", env_p, dec_b, "--recipient-key", sec_b]))
    assert_eq(bounded_read(dec_a, 65536L), plain)
    assert_eq(bounded_read(dec_b, 65536L), plain)

    // Unauthorized C fails with AuthenticationFailed and zero output
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "unseal",
            env_p,
            dir + "/dec-c.bin",
            "--recipient-key",
            sec_c,
          ]),
        )
      },
      "AuthenticationFailed",
    )
    assert_true(!entry_exists(dir + "/dec-c.bin"))

    // 1-byte tamper rejected
    let last_i = env_bytes.length() - 1
    let tampered = env_bytes[0:last_i].to_owned() +
      Bytes::from_array([(env_bytes[last_i].to_int() ^ 0x01).to_byte()])
    let tampered_p = dir + "/tampered.menc"
    @fs.write_binary(tampered_p, tampered[:], create_mode=CreateNew)
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "unseal",
            tampered_p,
            dir + "/dec-tampered.bin",
            "--recipient-key",
            sec_a,
          ]),
        )
      },
      "AuthenticationFailed",
    )
    assert_true(!entry_exists(dir + "/dec-tampered.bin"))
  })
}

///|
async test "cli v070 keyring-init sign-combine verify-quorum and dir-apply verify-bundle" {
  cli_test_scope(dir => {
    let priv1 = dir + "/k1.priv"
    let pub1 = dir + "/k1.pub"
    let priv2 = dir + "/k2.priv"
    let pub2 = dir + "/k2.pub"
    let priv3 = dir + "/k3.priv"
    let pub3 = dir + "/k3.pub"
    execute(parse_plan(["keygen", priv1, pub1]))
    execute(parse_plan(["keygen", priv2, pub2]))
    execute(parse_plan(["keygen", priv3, pub3]))

    let pub2_bytes = read_public_key_file(pub2)
    let pub2_hex = @crypto.encode_key_hex(pub2_bytes)
    let k2_id = @crypto.key_id_from_public_key(pub2_bytes)

    let kr_p = dir + "/kr.json"
    let kr_rev_p = dir + "/kr-revoked.json"
    let ki_out = StringBuilder()
    execute_keyring_init(
      parse_plan([
        "keyring-init", "--trust", pub1, "--trust", pub2_hex, "--trust", pub3, "--quorum",
        "2", "-o", kr_p, "--json",
      ]),
      kr_p,
      writer=b => ki_out.write_string(@utf8.decode(b)),
    )
    assert_true(ki_out.to_string().contains("\"min_quorum\":2"))
    assert_true(ki_out.to_string().contains("\"trusted_count\":3"))

    execute(
      parse_plan([
        "keyring-init", "--trust", pub1, "--trust", pub2, "--trust", pub3, "--revoke",
        k2_id, "--quorum", "2", "-o", kr_rev_p,
      ]),
    )

    // Sign a directory archive with all 3 keys
    let bdir = dir + "/basis"
    let tdir = dir + "/target"
    @fs.mkdir(bdir)
    @fs.mkdir(tdir)
    @fs.write_binary(bdir + "/f.bin", b"v1-data", create_mode=CreateNew)
    @fs.write_binary(tdir + "/f.bin", b"v2-data-updated", create_mode=CreateNew)
    let bsnap = dir + "/b.snap.json"
    let sigs = dir + "/sigs"
    let arch = dir + "/upd.mbundle.gz"
    execute(parse_plan(["dir-snapshot", bdir, bsnap]))
    execute(parse_plan(["dir-signatures", bdir, bsnap, sigs]))
    execute(
      parse_plan(["dir-pack", bsnap, sigs, tdir, arch, "--archive", "--gzip"]),
    )

    let s1 = dir + "/s1.json"
    let s2 = dir + "/s2.json"
    let s3 = dir + "/s3.json"
    execute(parse_plan(["sign", arch, priv1, s1]))
    execute(parse_plan(["sign", arch, priv2, s2]))
    execute(parse_plan(["sign", arch, priv3, s3]))

    let b12 = dir + "/b12.json"
    let b13 = dir + "/b13.json"
    let b1_only = dir + "/b1.json"
    let sc_out = StringBuilder()
    execute_sign_combine(
      parse_plan(["sign-combine", s1, s2, "-o", b12, "--json"]),
      b12,
      writer=b => sc_out.write_string(@utf8.decode(b)),
    )
    assert_true(sc_out.to_string().contains("\"signature_count\":2"))
    execute(parse_plan(["sign-combine", s1, s3, "-o", b13]))
    execute(parse_plan(["sign-combine", s1, "-o", b1_only]))

    // 2-of-3 verify-quorum passes (JSON & human)
    let vq_json = StringBuilder()
    execute_verify_quorum(
      parse_plan(["verify-quorum", arch, b12, "--keyring", kr_p, "--json"]),
      true,
      writer=b => vq_json.write_string(@utf8.decode(b)),
    )
    assert_true(vq_json.to_string().contains("\"verified\":true"))
    assert_true(vq_json.to_string().contains("\"verified_count\":2"))

    let vq_human = StringBuilder()
    execute_verify_quorum(
      parse_plan(["verify-quorum", arch, b12, "--keyring", kr_p]),
      false,
      writer=b => vq_human.write_string(@utf8.decode(b)),
    )
    assert_true(vq_human.to_string().contains("verified: true\n"))

    // 1-of-3 fails quorum with empty stdout
    let bad_out = StringBuilder()
    expect_file_failure(
      () => {
        execute_verify_quorum(
          parse_plan([
            "verify-quorum", arch, b1_only, "--keyring", kr_p, "--json",
          ]),
          true,
          writer=b => bad_out.write_string(@utf8.decode(b)),
        )
      },
      "quorum_not_met",
    )
    assert_eq(bad_out.to_string(), "")

    // Revoked k2 causes b12 to fail quorum, while b13 still passes
    expect_file_failure(
      () => {
        execute_verify_quorum(
          parse_plan(["verify-quorum", arch, b12, "--keyring", kr_rev_p]),
          false,
        )
      },
      "quorum_not_met",
    )
    execute_verify_quorum(
      parse_plan(["verify-quorum", arch, b13, "--keyring", kr_rev_p]),
      false,
      writer=_ => (),
    )

    // dir-apply --archive --gzip --verify-bundle --keyring
    let out_ok = dir + "/applied-ok"
    execute(
      parse_plan([
        "dir-apply", bdir, arch, out_ok, "--archive", "--gzip", "--verify-bundle",
        b13, "--keyring", kr_rev_p,
      ]),
    )
    assert_eq(bounded_read(out_ok + "/f.bin", 64L), b"v2-data-updated")

    let out_fail = dir + "/applied-fail"
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-apply", bdir, arch, out_fail, "--archive", "--gzip", "--verify-bundle",
            b12, "--keyring", kr_rev_p,
          ]),
        )
      },
      "quorum_not_met",
    )
    assert_true(!entry_exists(out_fail))
  })
}

///|
async test "cli v070 compress and decompress zlib and deflate buffered streaming and zip-bomb" {
  cli_test_scope(dir => {
    let payload = Bytes::makei(90000, i => {
      ((i / 16 * 13 + i % 7) % 256).to_byte()
    })
    let in_p = dir + "/in.bin"
    @fs.write_binary(in_p, payload, create_mode=CreateNew)

    for fmt in ["zlib", "deflate"] {
      let c_buf = dir + "/out-\{fmt}-buf.bin"
      let c_str = dir + "/out-\{fmt}-str.bin"
      let d_a = dir + "/dec-\{fmt}-a.bin"
      let d_b = dir + "/dec-\{fmt}-b.bin"
      execute(parse_plan(["compress", in_p, c_buf, "--format", fmt]))
      execute(
        parse_plan(["compress", in_p, c_str, "--format", fmt, "--streaming"]),
      )
      let cb = bounded_read(c_buf, 200000L)
      let cs = bounded_read(c_str, 200000L)
      assert_true(cb.length() < payload.length())
      assert_true(cs.length() < payload.length())
      if fmt == "zlib" {
        assert_eq(cb[0], b'\x78')
      }
      // Cross-mode decode parity
      execute(
        parse_plan(["decompress", c_buf, d_a, "--format", fmt, "--streaming"]),
      )
      execute(parse_plan(["decompress", c_str, d_b, "--format", fmt]))
      assert_eq(bounded_read(d_a, 200000L), payload)
      assert_eq(bounded_read(d_b, 200000L), payload)

      // Zip-bomb / output limit rejection (buffered & streaming)
      expect_file_failure(
        () => {
          execute(
            parse_plan([
              "decompress",
              c_buf,
              dir + "/bomb-\{fmt}-buf.out",
              "--format",
              fmt,
              "--max-output-bytes",
              "1024",
            ]),
          )
        },
        "LimitExceeded",
      )
      assert_true(!entry_exists(dir + "/bomb-\{fmt}-buf.out"))
      expect_file_failure(
        () => {
          execute(
            parse_plan([
              "decompress",
              c_str,
              dir + "/bomb-\{fmt}-str.out",
              "--format",
              fmt,
              "--streaming",
              "--max-output-bytes",
              "1024",
            ]),
          )
        },
        "LimitExceeded",
      )
      assert_true(!entry_exists(dir + "/bomb-\{fmt}-str.out"))
    }
  })
}

///|
async test "cli v070 deterministic concurrency --jobs 4 parity across dir commands" {
  cli_test_scope(dir => {
    let basis = dir + "/basis"
    let target = dir + "/target"
    @fs.mkdir(basis + "/subA", recursive=true)
    @fs.mkdir(basis + "/subB", recursive=true)
    @fs.mkdir(target + "/subA", recursive=true)
    @fs.mkdir(target + "/subB", recursive=true)
    for k in 0..<12 {
      let data = Bytes::makei(4096 + k * 512, i => {
        ((i * (k + 7) + k * 19) % 256).to_byte()
      })
      let sub = if k % 2 == 0 { "subA" } else { "subB" }
      @fs.write_binary(
        basis + "/\{sub}/file-\{k}.bin",
        data,
        create_mode=CreateNew,
      )
      if k < 4 {
        @fs.write_binary(
          target + "/\{sub}/file-\{k}.bin",
          data,
          create_mode=CreateNew,
        )
      } else if k < 10 {
        let edited = data[0:2048].to_owned() +
          b"MODIFIED-JOBS-V070" +
          data[2066:].to_owned()
        @fs.write_binary(
          target + "/\{sub}/file-\{k}.bin",
          edited,
          create_mode=CreateNew,
        )
      }
    }
    @fs.write_binary(
      target + "/subA/brand-new.bin",
      b"fresh-file-jobs-4",
      create_mode=CreateNew,
    )

    let snap1 = dir + "/b-j1.snap.json"
    let snap4 = dir + "/b-j4.snap.json"
    execute(parse_plan(["dir-snapshot", basis, snap1, "--jobs", "1"]))
    execute(parse_plan(["dir-snapshot", basis, snap4, "--jobs", "4"]))
    assert_eq(bounded_read(snap1, 65536L), bounded_read(snap4, 65536L))

    let sigs1 = dir + "/sigs-j1"
    let sigs4 = dir + "/sigs-j4"
    execute(
      parse_plan([
        "dir-signatures", basis, snap1, sigs1, "--block-size", "512", "--streaming",
        "--jobs", "1",
      ]),
    )
    execute(
      parse_plan([
        "dir-signatures", basis, snap1, sigs4, "--block-size", "512", "--streaming",
        "--jobs", "4",
      ]),
    )
    assert_eq(
      bounded_read(sigs1 + "/signatures.json", 65536L),
      bounded_read(sigs4 + "/signatures.json", 65536L),
    )

    let arch1 = dir + "/arch-j1.mbundle"
    let arch4 = dir + "/arch-j4.mbundle"
    execute(
      parse_plan([
        "dir-pack", snap1, sigs1, target, arch1, "--archive", "--streaming", "--jobs",
        "1",
      ]),
    )
    execute(
      parse_plan([
        "dir-pack", snap1, sigs4, target, arch4, "--archive", "--streaming", "--jobs",
        "4",
      ]),
    )
    assert_eq(bounded_read(arch1, 1048576L), bounded_read(arch4, 1048576L))

    let out = dir + "/out"
    let tsnap = dir + "/t.snap.json"
    execute(parse_plan(["dir-snapshot", target, tsnap, "--jobs", "4"]))
    execute(parse_plan(["dir-apply", basis, arch4, out, "--archive"]))
    let dv1 = StringBuilder()
    let dv4 = StringBuilder()
    execute_dir_verify(
      parse_plan(["dir-verify", out, tsnap, "--json", "--jobs", "1"]),
      true,
      writer=b => dv1.write_string(@utf8.decode(b)),
    )
    execute_dir_verify(
      parse_plan(["dir-verify", out, tsnap, "--json", "--jobs", "4"]),
      true,
      writer=b => dv4.write_string(@utf8.decode(b)),
    )
    assert_eq(dv1.to_string(), dv4.to_string())
    assert_true(dv4.to_string().contains("\"ok\":true"))
  })
}

///|
async test "cli v070 dir-snapshot --meta-out and dir-apply --meta empty dirs" {
  cli_test_scope(dir => {
    let basis = dir + "/basis"
    let target = dir + "/target"
    @fs.mkdir(basis)
    @fs.mkdir(target + "/empty-top", recursive=true)
    @fs.mkdir(target + "/nested/empty-leaf", recursive=true)
    @fs.mkdir(target + "/bin", recursive=true)
    @fs.write_binary(basis + "/keep.txt", b"hello", create_mode=CreateNew)
    @fs.write_binary(target + "/keep.txt", b"hello", create_mode=CreateNew)
    @fs.write_binary(
      target + "/bin/run.sh",
      b"#!/bin/sh\necho hi\n",
      create_mode=CreateNew,
    )
    if @path.sep == '/' {
      @fs.chmod(target + "/bin/run.sh", 0o755)
    }

    let bsnap = dir + "/b.snap.json"
    let tsnap = dir + "/t.snap.json"
    let tmeta = dir + "/t.meta.json"
    let sigs = dir + "/sigs"
    let arch = dir + "/upd.mbundle"
    let out = dir + "/out"

    execute(parse_plan(["dir-snapshot", basis, bsnap]))
    execute(
      parse_plan([
        "dir-snapshot", target, tsnap, "--meta-out", tmeta, "--jobs", "2",
      ]),
    )
    let dl = @lib.DirLimits::default()
    let parsed_meta = @lib.parse_dir_metadata(
      bounded_read(tmeta, dl.max_snapshot_bytes),
      dl,
    )
    assert_eq(parsed_meta.empty_dirs, ["empty-top", "nested/empty-leaf"])
    if @path.sep == '/' {
      assert_eq(parsed_meta.executable_paths, ["bin/run.sh"])
    } else {
      assert_eq(parsed_meta.executable_paths, [])
    }

    execute(parse_plan(["dir-signatures", basis, bsnap, sigs]))
    execute(parse_plan(["dir-pack", bsnap, sigs, target, arch, "--archive"]))
    execute(
      parse_plan(["dir-apply", basis, arch, out, "--archive", "--meta", tmeta]),
    )
    assert_true(@fs.kind(out + "/empty-top", follow_symlink=false) is Directory)
    assert_true(
      @fs.kind(out + "/nested/empty-leaf", follow_symlink=false) is Directory,
    )
    if @path.sep == '/' {
      assert_true(@fs.can_execute(out + "/bin/run.sh"))
    }

    // --meta-out collision with snapshot path refused without leaving files
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-snapshot",
            target,
            dir + "/same.json",
            "--meta-out",
            dir + "/same.json",
          ]),
        )
      },
      "collides",
    )
    assert_true(!entry_exists(dir + "/same.json"))

    // Malicious --meta with empty_dir colliding with existing file fails cleanly
    let bad_meta_p = dir + "/bad.meta.json"
    let bad_meta = @lib.create_dir_metadata([], ["keep.txt"], dl)
    @fs.write_binary(
      bad_meta_p,
      @lib.encode_dir_metadata(bad_meta, dl)[:],
      create_mode=CreateNew,
    )
    let out_bad = dir + "/out-bad"
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-apply", basis, arch, out_bad, "--archive", "--meta", bad_meta_p,
          ]),
        )
      },
      "keep.txt",
    )
    assert_true(!entry_exists(out_bad))
  })
}

///|
test "cli v070 http helper validation and strict hex helpers" {
  // Valid Content-Range
  validate_content_range("bytes 100-199/1000", 100L, 100L, 1000L)
  validate_content_range("  bytes 0-0/*  ", 0L, 1L, 500L)
  // Invalid Content-Range
  for
    bad in [
      "bytes 100-198/1000", "bytes 101-199/1000", "bytes 100-199/999", "items 100-199/1000",
      "bytes 100-199/abc",
    ] {
    let failed = try {
      validate_content_range(bad, 100L, 100L, 1000L)
      false
    } catch {
      FileFailure(_) => true
      _ => false
    }
    assert_true(failed)
  }
  assert_eq(parse_http_nonneg_decimal(" 42 ", "test"), 42L)
  assert_true(
    is_strict_64_lower_hex(
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    ),
  )
  assert_true(
    !is_strict_64_lower_hex(
      "0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef",
    ),
  )
  assert_true(!is_strict_64_lower_hex("short"))
}

///|
async test "cli v070 completions emit all 35 commands and v070 flags for bash zsh powershell" {
  let all_35 = [
    "signature", "delta", "patch", "reverse-delta", "compose-delta", "range-plan",
    "fetch-sync", "basis-info", "make-manifest", "patch-verified", "inspect-signature",
    "inspect-delta", "check-patch", "inspect-manifest", "inspect-bundle", "make-transfer-manifest",
    "apply-update", "compress", "decompress", "keygen", "x25519-keygen", "sign",
    "verify", "keyring-init", "sign-combine", "verify-quorum", "seal", "unseal",
    "dir-snapshot", "dir-plan", "dir-verify", "dir-signatures", "dir-pack", "dir-apply",
    "completions",
  ]
  let new_flags = [
    "--jobs", "--format", "--recipient", "--recipient-key", "--keyring", "--quorum",
    "--trust", "--revoke", "--meta-out", "--meta", "--sig-url", "--merge-gap", "--max-ranges",
    "--verify-bundle", "--pub-out",
  ]
  for shell in ["bash", "zsh", "powershell"] {
    let out = StringBuilder()
    execute_completions(parse_plan(["completions", shell]), writer=b => {
      out.write_string(@utf8.decode(b))
    })
    let text = out.to_string()
    assert_true(text.contains("0.7.1"))
    for cmd in all_35 {
      assert_true(text.contains(cmd))
    }
    for flag in new_flags {
      assert_true(text.contains(flag))
    }
  }
}

///|
async test "cli v070 red-team hardening: http parsing excluded-only meta and manifest cross-validation" {
  // validate_http_url rejects empty host
  for bad_url in ["http://", "https://", "http:///a/b", "http://?q=1"] {
    let bad = try {
      validate_http_url(bad_url, "URL")
      false
    } catch {
      Usage(_) => true
      _ => false
    }
    assert_true(bad)
  }
  validate_http_url("http://127.0.0.1:8080/a", "URL")

  // Strict canonical Content-Range total rejects leading zero
  let cr_bad = try {
    validate_content_range("bytes 0-9/0100", 0L, 10L, 100L)
    false
  } catch {
    FileFailure(_) => true
    _ => false
  }
  assert_true(cr_bad)

  cli_test_scope(dir => {
    let target = dir + "/target"
    let basis = dir + "/basis"
    @fs.mkdir(basis)
    @fs.mkdir(target + "/excluded-only", recursive=true)
    @fs.mkdir(target + "/genuinely-empty", recursive=true)
    @fs.mkdir(target + "/alpha", recursive=true)
    @fs.write_binary(
      target + "/excluded-only/secret.key",
      b"top-secret",
      create_mode=CreateNew,
    )
    @fs.write_binary(target + "/alpha/keep.txt", b"ok", create_mode=CreateNew)
    @fs.write_binary(basis + "/keep.txt", b"ok", create_mode=CreateNew)

    let tsnap = dir + "/t.snap.json"
    let tmeta = dir + "/t.meta.json"
    execute(
      parse_plan([
        "dir-snapshot", target, tsnap, "--exclude", "*.key", "--meta-out", tmeta,
      ]),
    )
    let dl = @lib.DirLimits::default()
    let meta = @lib.parse_dir_metadata(
      bounded_read(tmeta, dl.max_snapshot_bytes),
      dl,
    )
    // excluded-only MUST NOT appear in empty_dirs; genuinely-empty DOES appear
    assert_eq(meta.empty_dirs, ["genuinely-empty"])

    let bsnap = dir + "/b.snap.json"
    let sigs = dir + "/sigs"
    let arch = dir + "/upd.mbundle"
    execute(parse_plan(["dir-snapshot", basis, bsnap]))
    execute(parse_plan(["dir-signatures", basis, bsnap, sigs]))
    execute(
      parse_plan([
        "dir-pack", bsnap, sigs, target, arch, "--archive", "--exclude", "*.key",
      ]),
    )

    // Cross-validation rejects non-empty ancestor empty_dir, case-mismatched parent, and absent executable_path
    let mut bad_idx = 0
    for
      bad_pair in [
        ([], ["alpha"]),
        ([], ["Alpha/newempty"]),
        (["absent.sh"], []),
      ] {
      let bm_path = dir + "/bad-\{bad_idx}.meta.json"
      let bm = @lib.create_dir_metadata(bad_pair.0, bad_pair.1, dl)
      @fs.write_binary(
        bm_path,
        @lib.encode_dir_metadata(bm, dl)[:],
        create_mode=CreateNew,
      )
      let bad_out = dir + "/out-\{bad_idx}"
      bad_idx = bad_idx + 1
      let rejected = try {
        execute(
          parse_plan([
            "dir-apply", basis, arch, bad_out, "--archive", "--meta", bm_path,
          ]),
        )
        false
      } catch {
        FileFailure(_) => true
        _ => false
      }
      assert_true(rejected)
      assert_true(!entry_exists(bad_out))
    }
  })
}

///|
test "cli v071 resolve_redirect_url validates schemes downgrades and relative paths" {
  assert_eq(
    resolve_redirect_url("http://127.0.0.1:8080/a/b.bin", "/v2/c.bin"),
    "http://127.0.0.1:8080/v2/c.bin",
  )
  assert_eq(
    resolve_redirect_url("https://cdn.example.com/a", "//edge.example.com/b"),
    "https://edge.example.com/b",
  )
  assert_eq(
    resolve_redirect_url("http://a.test/x", "https://b.test/y"),
    "https://b.test/y",
  )
  assert_eq(
    resolve_redirect_url("http://a.test/x", "HTTPS://CDN.TEST/v2.bin"),
    "https://CDN.TEST/v2.bin",
  )
  assert_eq(
    resolve_redirect_url("http://127.0.0.1:8080/a/b.bin", "/v2/c.bin#frag"),
    "http://127.0.0.1:8080/v2/c.bin",
  )
  assert_eq(
    resolve_redirect_url("http://a.test/x", "https://b.test?token=1"),
    "https://b.test/?token=1",
  )
  for
    pair in [
      ("https://secure.test/a", "http://plain.test/a"),
      ("https://secure.test/a", "HTTP://plain.test/a"),
      ("HTTPS://secure.test/a", "http://plain.test/a"),
      ("http://a.test/x", "https://user:pass@b.test/y"),
      ("http://a.test/x", "#only-frag"),
      ("http://a.test/x", "file:///etc/passwd"),
      ("http://a.test/x", "ftp://a.test/x"),
      ("http://a.test/x", "https:///empty-host"),
      ("http://a.test/x", "https://bad.test/has space"),
      ("http://a.test/x", "relative-no-slash"),
    ] {
    let rejected = try {
      ignore(resolve_redirect_url(pair.0, pair.1))
      false
    } catch {
      FileFailure(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}
