// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "cli v060 option parsing and gating for all 8 new commands and flags" {
  // --profile on signature and dir-signatures
  let sig_rk = parse_plan(["signature", "old", "sig", "--profile", "rk-blake2"])
  assert_true(sig_rk.sig_profile is RkBlake2)
  let sig_rs = parse_plan([
    "signature", "--profile", "rollsum-blake2", "old", "sig", "--streaming",
  ])
  assert_true(sig_rs.sig_profile is RollsumBlake2 && sig_rs.streaming)
  let dsig_rs = parse_plan([
    "dir-signatures", "d", "s", "out", "--profile", "rollsum-blake2",
  ])
  assert_true(dsig_rs.sig_profile is RollsumBlake2)

  // --exclude-from on dir-snapshot, dir-pack, dir-verify
  let snap_ef = parse_plan([
    "dir-snapshot", "d", "o.json", "--exclude", "*.tmp", "--exclude-from", ".ignore",
  ])
  assert_eq(snap_ef.excludes, ["*.tmp"])
  assert_eq(snap_ef.exclude_sources.length(), 2)
  let pack_ef = parse_plan([
    "dir-pack", "b.json", "sigs", "t", "out.mbundle", "--archive", "--detect-moves",
    "--exclude-from", "a.ign", "--exclude-from", "b.ign",
  ])
  assert_true(pack_ef.detect_moves && pack_ef.archive)
  assert_eq(pack_ef.exclude_sources.length(), 2)
  let verify_ef = parse_plan([
    "dir-verify", "d", "s.json", "--exclude-from", ".ignore", "--json",
  ])
  assert_true(verify_ef.mode is Inspect(true))
  assert_eq(verify_ef.exclude_sources.length(), 1)

  // --detect-moves on dir-plan
  let plan_dm = parse_plan(["dir-plan", "a.json", "b.json", "--detect-moves"])
  assert_true(plan_dm.detect_moves && plan_dm.mode is Inspect(false))

  // --verify-sig / --verify-key / --save-rollback
  let apply_v = parse_plan([
    "dir-apply", "basis", "b.mbundle.gz", "out", "--archive", "--gzip", "--verify-sig",
    "b.sig.json", "--verify-key", "k1.pub", "--verify-key", "k2.pub", "--save-rollback",
    "rb.mbundle.gz",
  ])
  assert_eq(apply_v.verify_sig, Some("b.sig.json"))
  assert_eq(apply_v.verify_keys, ["k1.pub", "k2.pub"])
  assert_eq(apply_v.save_rollback, Some("rb.mbundle.gz"))
  let pv_v = parse_plan([
    "patch-verified", "old", "d", "m.json", "out", "--verify-sig", "m.sig", "--verify-key",
    "k.pub",
  ])
  assert_eq(pv_v.verify_sig, Some("m.sig"))
  assert_eq(pv_v.verify_keys, ["k.pub"])
  let au_v = parse_plan([
    "apply-update", "p", "m.json", "out", "--verify-sig", "m.sig", "--verify-key",
    "k.pub",
  ])
  assert_eq(au_v.verify_sig, Some("m.sig"))
  assert_eq(au_v.verify_keys, ["k.pub"])

  // keygen, sign, verify
  let kg = parse_plan(["keygen", "priv.key", "pub.key"])
  assert_eq(kg.inputs, ["priv.key"])
  assert_true(kg.mode is WriteFile("pub.key"))
  let sg = parse_plan([
    "sign", "in.bin", "priv.key", "in.sig.json", "--streaming", "--progress",
  ])
  assert_eq(sg.inputs, ["in.bin", "priv.key"])
  assert_true(
    sg.mode is WriteFile("in.sig.json") && sg.streaming && sg.progress,
  )
  let vf = parse_plan([
    "verify", "in.bin", "in.sig.json", "k1.pub", "--pub-key", "k2.pub", "--json",
    "--streaming", "--progress",
  ])
  assert_eq(vf.inputs, ["in.bin", "in.sig.json", "k1.pub"])
  assert_eq(vf.verify_keys, ["k2.pub"])
  assert_true(vf.mode is Inspect(true) && vf.streaming && vf.progress)

  // seal, unseal
  let sl_k = parse_plan([
    "seal", "in.bin", "out.menc", "--key-file", "k.hex", "--chunk-size", "4096",
    "--streaming", "--progress",
  ])
  assert_eq(sl_k.key_file, Some("k.hex"))
  assert_eq(sl_k.seal_options.chunk_size, 4096)
  assert_true(sl_k.streaming && sl_k.progress)
  let sl_p = parse_plan([
    "seal", "in.bin", "out.menc", "--passphrase-file", "pw.txt", "--argon2-memory",
    "128", "--argon2-passes", "1",
  ])
  assert_eq(sl_p.passphrase_file, Some("pw.txt"))
  assert_eq(sl_p.seal_options.argon2_memory_kib, 128)
  assert_eq(sl_p.seal_options.argon2_passes, 1)
  let usl = parse_plan([
    "unseal", "in.menc", "out.bin", "--key-file", "k.hex", "--streaming",
  ])
  assert_eq(usl.key_file, Some("k.hex"))
  assert_true(usl.streaming)

  // reverse-delta
  let rd = parse_plan([
    "reverse-delta", "old.bin", "new.bin", "rev.delta", "--block-size", "auto", "--sum-size",
    "16", "--streaming", "--progress",
  ])
  assert_eq(rd.inputs, ["old.bin", "new.bin"])
  assert_true(rd.mode is WriteFile("rev.delta") && rd.block_choice is Auto)
  assert_eq(rd.options.strong_sum_len, 16L)

  // inspect-bundle
  let ib = parse_plan([
    "inspect-bundle", "b.mbundle.gz", "--gzip", "--json", "--max-entries", "32",
    "--max-old-bytes", "4096",
  ])
  assert_eq(ib.inputs, ["b.mbundle.gz"])
  assert_true(ib.gzip && !ib.archive && ib.mode is Inspect(true))
  assert_eq(ib.dir_limits.max_entries, 32L)
  assert_eq(ib.limits.max_old_bytes, 4096L)

  // completions
  for sh in ["bash", "zsh", "powershell"] {
    let cp = parse_plan(["completions", sh])
    assert_eq(cp.inputs, [sh])
    assert_true(cp.mode is Inspect(false))
  }

  // Usage rejections
  for
    bad in [
      ["signature", "o", "s", "--profile", "md4"],
      ["signature", "o", "s", "--profile"],
      [
        "signature", "o", "s", "--profile", "rk-blake2", "--profile", "rollsum-blake2",
      ],
      ["delta", "s", "n", "d", "--profile", "rk-blake2"],
      ["dir-snapshot", "d", "o", "--exclude-from"],
      ["dir-snapshot", "d", "o", "--exclude-from", ""],
      ["dir-apply", "b", "bd", "o", "--exclude-from", ".ign"],
      ["dir-plan", "a", "b", "--detect-moves", "--detect-moves"],
      ["dir-snapshot", "d", "o", "--detect-moves"],
      ["dir-apply", "b", "bd", "o", "--archive", "--verify-sig", "s"],
      ["dir-apply", "b", "bd", "o", "--archive", "--verify-key", "k"],
      ["dir-apply", "b", "bd", "o", "--verify-sig", "s", "--verify-key", "k"],
      ["patch-verified", "o", "d", "m", "out", "--verify-sig", "s"],
      ["apply-update", "p", "m", "out", "--verify-key", "k"],
      ["signature", "o", "s", "--verify-sig", "sg", "--verify-key", "k"],
      ["dir-pack", "b", "s", "t", "o", "--save-rollback", "rb"],
      ["dir-apply", "b", "bd", "o", "--save-rollback", ""],
      [
        "dir-apply", "b", "bd", "o", "--save-rollback", "a", "--save-rollback", "b",
      ],
      ["sign", "in", "priv", "out", "--pub-key", "k"],
      ["verify", "in", "sig"],
      ["verify", "in", "sig", "pub", "--pub-key", ""],
      ["seal", "in", "out"],
      ["seal", "in", "out", "--key-file", "k", "--passphrase-file", "p"],
      ["seal", "in", "out", "--key-file", "k", "--argon2-memory", "64"],
      ["seal", "in", "out", "--key-file", "k", "--argon2-passes", "1"],
      ["seal", "in", "out", "--key-file", "k", "--chunk-size", "1023"],
      ["seal", "in", "out", "--key-file", "k", "--chunk-size", "1048577"],
      ["seal", "in", "out", "--passphrase-file", "p", "--argon2-memory", "63"],
      [
        "seal", "in", "out", "--passphrase-file", "p", "--argon2-memory", "65537",
      ],
      ["seal", "in", "out", "--passphrase-file", "p", "--argon2-passes", "0"],
      ["seal", "in", "out", "--passphrase-file", "p", "--argon2-passes", "9"],
      ["unseal", "in", "out"],
      ["unseal", "in", "out", "--key-file", "k", "--passphrase-file", "p"],
      ["unseal", "in", "out", "--key-file", "k", "--chunk-size", "4096"],
      ["keygen", "only-one"],
      ["keygen", "a", "b", "c"],
      ["keygen", "a", "b", "--json"],
      ["keygen", "a", "b", "--streaming"],
      ["keygen", "a", "b", "--progress"],
      ["keygen", "a", "b", "--max-old-bytes", "10"],
      ["reverse-delta", "old", "new"],
      ["reverse-delta", "old", "new", "out", "--profile", "rk-blake2"],
      ["inspect-bundle"],
      ["inspect-bundle", "a", "--archive"],
      ["inspect-bundle", "a", "--streaming"],
      ["inspect-bundle", "a", "--gzip", "--gzip"],
      ["completions"],
      ["completions", "fish"],
      ["completions", "bash", "--json"],
      ["completions", "bash", "--progress"],
      ["completions", "bash", "extra"],
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
async test "cli v060 signature profile rollsum-blake2 buffered streaming inspect and basis-info" {
  cli_test_scope(dir => {
    let d = @lib.Limits::default()
    let old = Bytes::makei(70000, i => {
      ((i * 41 + 9 + i / 512 * 7) % 256).to_byte()
    })
    let new_bytes = old[0:32000].to_owned() +
      b"ROLLSUM-PROFILE-EDIT" +
      old[32020:].to_owned()
    let old_p = dir + "/old.bin"
    let new_p = dir + "/new.bin"
    let sig_buf = dir + "/rs-buf.sig"
    let sig_str = dir + "/rs-str.sig"
    let delta_p = dir + "/rs.delta"
    let out_p = dir + "/rs.out"
    let info_buf = dir + "/info-buf.json"
    let info_str = dir + "/info-str.json"
    @fs.write_binary(old_p, old, create_mode=CreateNew)
    @fs.write_binary(new_p, new_bytes, create_mode=CreateNew)

    execute(
      parse_plan([
        "signature", old_p, sig_buf, "--profile", "rollsum-blake2", "--block-size",
        "auto",
      ]),
    )
    execute(
      parse_plan([
        "signature", old_p, sig_str, "--profile", "rollsum-blake2", "--block-size",
        "auto", "--streaming",
      ]),
    )
    let raw_buf = bounded_read(sig_buf, d.max_signature_bytes)
    let raw_str = bounded_read(sig_str, d.max_signature_bytes)
    assert_eq(raw_buf, raw_str)
    let summary = @lib.inspect_signature(raw_buf, d)
    assert_eq(summary.magic, 0x72730137U)
    let j = format_signature(summary, true)
    assert_true(j.contains("\"magic\":\"0x72730137\""))
    assert_true(j.contains("\"profile\":\"RS_BLAKE2_SIG_MAGIC\""))
    let h = format_signature(summary, false)
    assert_true(h.contains("magic: 0x72730137\nprofile: RS_BLAKE2_SIG_MAGIC\n"))

    execute(parse_plan(["delta", sig_str, new_p, delta_p, "--streaming"]))
    execute(parse_plan(["patch", old_p, delta_p, out_p, "--streaming"]))
    assert_eq(bounded_read(out_p, d.max_output_bytes), new_bytes)

    execute(parse_plan(["basis-info", old_p, sig_str, info_buf]))
    execute(parse_plan(["basis-info", old_p, sig_str, info_str, "--streaming"]))
    assert_eq(bounded_read(info_buf, 65536L), bounded_read(info_str, 65536L))
  })
}

///|
async test "cli v060 reverse-delta buffered and streaming roundtrip" {
  cli_test_scope(dir => {
    let d = @lib.Limits::default()
    let old = Bytes::makei(140000, i => {
      ((i * 29 + 3 + i / 1024 * 13) % 256).to_byte()
    })
    let new_bytes = old[0:68000].to_owned() +
      b"FORWARD-CHANGE-V060" +
      old[68019:].to_owned()
    let old_p = dir + "/old.bin"
    let new_p = dir + "/new.bin"
    let rev_buf = dir + "/rev-buf.delta"
    let rev_str = dir + "/rev-str.delta"
    let restored_buf = dir + "/restored-buf.bin"
    let restored_str = dir + "/restored-str.bin"
    @fs.write_binary(old_p, old, create_mode=CreateNew)
    @fs.write_binary(new_p, new_bytes, create_mode=CreateNew)

    execute(
      parse_plan([
        "reverse-delta", old_p, new_p, rev_buf, "--block-size", "auto", "--sum-size",
        "16",
      ]),
    )
    execute(
      parse_plan([
        "reverse-delta", old_p, new_p, rev_str, "--block-size", "auto", "--sum-size",
        "16", "--streaming",
      ]),
    )
    let rb = bounded_read(rev_buf, d.max_delta_bytes)
    let rs = bounded_read(rev_str, d.max_delta_bytes)
    assert_eq(rb, rs)
    assert_true(rb.length() < old.length() / 4)

    execute(parse_plan(["patch", new_p, rev_buf, restored_buf]))
    execute(parse_plan(["patch", new_p, rev_str, restored_str, "--streaming"]))
    assert_eq(bounded_read(restored_buf, d.max_output_bytes), old)
    assert_eq(bounded_read(restored_str, d.max_output_bytes), old)
  })
}

///|
async test "cli v060 exclude-from comments CRLF merge and BOM rejection" {
  cli_test_scope(dir => {
    let tree = dir + "/tree"
    @fs.mkdir(tree + "/sub", recursive=true)
    @fs.mkdir(tree + "/build", recursive=true)
    @fs.write_binary(tree + "/keep.bin", b"ok", create_mode=CreateNew)
    @fs.write_binary(tree + "/sub/debug.log", b"log", create_mode=CreateNew)
    @fs.write_binary(tree + "/build/out.o", b"obj", create_mode=CreateNew)
    @fs.write_binary(tree + "/temp.tmp", b"tmp", create_mode=CreateNew)

    let ign = dir + "/.moonlibsyncignore"
    @fs.write_binary(
      ign,
      b"# comment line\r\n\r\n  *.log  \r\nbuild\n",
      create_mode=CreateNew,
    )
    let snap = dir + "/tree.snap.json"
    execute(
      parse_plan([
        "dir-snapshot", tree, snap, "--exclude-from", ign, "--exclude", "*.tmp",
      ]),
    )
    let dl = @lib.DirLimits::default()
    let parsed = @lib.parse_dir_snapshot(
      bounded_read(snap, dl.max_snapshot_bytes),
      dl,
    )
    assert_eq(parsed.entries.length(), 1)
    assert_eq(parsed.entries[0].path, "keep.bin")

    // dir-verify with --exclude-from
    let out_buf = StringBuilder()
    execute_dir_verify(
      parse_plan([
        "dir-verify", tree, snap, "--exclude-from", ign, "--exclude", "*.tmp", "--json",
      ]),
      true,
      writer=b => out_buf.write_string(@utf8.decode(b)),
    )
    let report = @lib.parse_dir_verify_report(
      @utf8.encode(out_buf.to_string()),
      dl,
    )
    assert_true(report.ok && report.matched_count == 1L)

    // UTF-8 BOM exclude file rejected
    let bom_ign = dir + "/bom.ignore"
    @fs.write_binary(bom_ign, b"\xef\xbb\xbf*.log\n", create_mode=CreateNew)
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-snapshot",
            tree,
            dir + "/bom.snap.json",
            "--exclude-from",
            bom_ign,
          ]),
        )
      },
      "exclude_file_bom",
    )
    assert_true(!entry_exists(dir + "/bom.snap.json"))
  })
}

///|
async test "cli v060 detect-moves CopyFromBasis UpdateDeltaFrom inspect-bundle and save-rollback" {
  cli_test_scope(dir => {
    let basis = dir + "/basis"
    let target = dir + "/target"
    @fs.mkdir(basis + "/old-dir", recursive=true)
    @fs.mkdir(target + "/new-dir", recursive=true)

    let exact_moved = Bytes::makei(40000, i => ((i * 19 + 5) % 256).to_byte())
    let moved_edit_old = Bytes::makei(80000, i => {
      ((i * 61 + 11 + i / 512 * 9) % 256).to_byte()
    })
    let moved_edit_new = moved_edit_old[0:40000].to_owned() +
      b"MOVED-AND-EDITED-V060" +
      moved_edit_old[40021:].to_owned()

    @fs.write_binary(basis + "/stay.bin", b"unchanged", create_mode=CreateNew)
    @fs.write_binary(
      basis + "/old-dir/pure.bin",
      exact_moved,
      create_mode=CreateNew,
    )
    @fs.write_binary(
      basis + "/old-dir/edit.bin",
      moved_edit_old,
      create_mode=CreateNew,
    )
    @fs.write_binary(
      basis + "/drop.bin",
      b"deleted-in-target",
      create_mode=CreateNew,
    )

    @fs.write_binary(target + "/stay.bin", b"unchanged", create_mode=CreateNew)
    @fs.write_binary(
      target + "/new-dir/pure.bin",
      exact_moved,
      create_mode=CreateNew,
    )
    @fs.write_binary(
      target + "/new-dir/edit.bin",
      moved_edit_new,
      create_mode=CreateNew,
    )
    @fs.write_binary(
      target + "/brand-new.bin",
      b"added-in-target",
      create_mode=CreateNew,
    )

    let b_snap = dir + "/b.snap.json"
    let t_snap = dir + "/t.snap.json"
    let sig_dir = dir + "/sigs"
    let arch = dir + "/move.mbundle.gz"
    let out_dir = dir + "/out"
    let rb_arch = dir + "/rollback.mbundle.gz"
    let restored_basis = dir + "/restored-basis"

    execute(parse_plan(["dir-snapshot", basis, b_snap]))
    execute(parse_plan(["dir-snapshot", target, t_snap]))
    let dl = @lib.DirLimits::default()
    let fl = @lib.Limits::default()
    let bs = @lib.parse_dir_snapshot(
      bounded_read(b_snap, dl.max_snapshot_bytes),
      dl,
    )
    let ts = @lib.parse_dir_snapshot(
      bounded_read(t_snap, dl.max_snapshot_bytes),
      dl,
    )
    let dp = @lib.plan_dir_sync_with_options(
      bs,
      ts,
      { detect_moves: true, },
      dl,
    )
    assert_eq(dp.copy_from_basis_count, 1L)
    let plan_human = format_dir_plan(dp, dl, false, show_copy_from_basis=true)
    assert_true(plan_human.contains("copy_from_basis: 1\n"))
    assert_true(
      plan_human.contains(
        "copy-from-basis: new-dir/pure.bin <- old-dir/pure.bin",
      ),
    )

    execute(
      parse_plan([
        "dir-signatures", basis, b_snap, sig_dir, "--block-size", "auto", "--streaming",
      ]),
    )
    execute(
      parse_plan([
        "dir-pack", b_snap, sig_dir, target, arch, "--detect-moves", "--archive",
        "--gzip", "--streaming",
      ]),
    )

    // inspect-bundle --gzip --json and human
    let ib_json = StringBuilder()
    execute_inspect_bundle(
      parse_plan(["inspect-bundle", arch, "--gzip", "--json"]),
      true,
      writer=b => ib_json.write_string(@utf8.decode(b)),
    )
    let ib_jstr = ib_json.to_string()
    assert_true(ib_jstr.contains("\"command\":\"inspect-bundle\""))
    assert_true(ib_jstr.contains("\"gzip\":true"))
    assert_true(ib_jstr.contains("\"copy-from-basis\""))
    assert_true(ib_jstr.contains("\"update-delta-from\""))
    assert_true(ib_jstr.contains("\"copy_from_basis\":\"1\""))

    let ib_human = StringBuilder()
    execute_inspect_bundle(
      parse_plan(["inspect-bundle", arch, "--gzip"]),
      false,
      writer=b => ib_human.write_string(@utf8.decode(b)),
    )
    let ib_hstr = ib_human.to_string()
    assert_true(ib_hstr.contains("copy_from_basis: 1\n"))
    assert_true(
      ib_hstr.contains("copy-from-basis: new-dir/pure.bin <- old-dir/pure.bin"),
    )
    assert_true(
      ib_hstr.contains(
        "update-delta-from: new-dir/edit.bin <- old-dir/edit.bin",
      ),
    )

    // dir-apply with --save-rollback
    execute(
      parse_plan([
        "dir-apply", basis, arch, out_dir, "--archive", "--gzip", "--streaming",
        "--save-rollback", rb_arch,
      ]),
    )
    let out_snap = dir + "/out.snap.json"
    execute(parse_plan(["dir-snapshot", out_dir, out_snap]))
    assert_eq(
      bounded_read(out_snap, dl.max_snapshot_bytes),
      bounded_read(t_snap, dl.max_snapshot_bytes),
    )

    // Rollback path no-overwrite fails early without creating OUT_DIR
    let out_fail = dir + "/out-should-not-exist"
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-apply", basis, arch, out_fail, "--archive", "--gzip", "--save-rollback",
            rb_arch,
          ]),
        )
      },
      "already exists",
    )
    assert_true(!entry_exists(out_fail))

    // Apply rollback archive to out_dir -> recovers basis bit-for-bit!
    execute(
      parse_plan([
        "dir-apply", out_dir, rb_arch, restored_basis, "--archive", "--gzip", "--streaming",
      ]),
    )
    let rb_snap = dir + "/rb.snap.json"
    execute(parse_plan(["dir-snapshot", restored_basis, rb_snap]))
    assert_eq(
      bounded_read(rb_snap, dl.max_snapshot_bytes),
      bounded_read(b_snap, dl.max_snapshot_bytes),
    )
    // Inspect rollback archive too
    let rb_ib = StringBuilder()
    execute_inspect_bundle(
      parse_plan(["inspect-bundle", rb_arch, "--gzip", "--json"]),
      true,
      writer=b => rb_ib.write_string(@utf8.decode(b)),
    )
    assert_true(rb_ib.to_string().contains("\"gzip\":true"))
    let _ = fl
  })
}

///|
async test "cli v060 keygen sign verify and attached verify-sig on patch-verified apply-update dir-apply" {
  cli_test_scope(dir => {
    let d = @lib.Limits::default()
    let priv1 = dir + "/k1.priv"
    let pub1 = dir + "/k1.pub"
    let priv2 = dir + "/k2.priv"
    let pub2 = dir + "/k2.pub"

    execute(parse_plan(["keygen", priv1, pub1]))
    execute(parse_plan(["keygen", priv2, pub2]))
    assert_eq(bounded_read(priv1, 128L).length(), 65)
    assert_eq(bounded_read(pub1, 128L).length(), 65)

    // Refuses overwrite and identical paths
    expect_file_failure(
      () => execute(parse_plan(["keygen", priv1, dir + "/fresh.pub"])),
      "already exists",
    )
    assert_true(!entry_exists(dir + "/fresh.pub"))
    expect_file_failure(
      () => {
        execute(parse_plan(["keygen", dir + "/same.key", dir + "/same.key"]))
      },
      "distinct",
    )
    assert_true(!entry_exists(dir + "/same.key"))

    // Sign & verify a payload
    let payload = dir + "/payload.bin"
    let sig_file = dir + "/payload.sig.json"
    @fs.write_binary(payload, b"hello-ed25519-v060", create_mode=CreateNew)
    execute(parse_plan(["sign", payload, priv1, sig_file, "--streaming"]))

    let vj = StringBuilder()
    execute_verify(
      parse_plan([
        "verify", payload, sig_file, pub2, "--pub-key", pub1, "--json", "--streaming",
      ]),
      true,
      writer=b => vj.write_string(@utf8.decode(b)),
    )
    let vj_str = vj.to_string()
    assert_true(vj_str.contains("\"command\":\"verify\""))
    assert_true(vj_str.contains("\"verified\":true"))
    assert_true(vj_str.contains("\"algorithm\":\"ed25519\""))

    // Untrusted key fails with empty stdout
    let bad_out = StringBuilder()
    expect_file_failure(
      () => {
        execute_verify(
          parse_plan(["verify", payload, sig_file, pub2, "--json"]),
          true,
          writer=b => bad_out.write_string(@utf8.decode(b)),
        )
      },
      "UntrustedKey",
    )
    assert_eq(bad_out.to_string(), "")

    // Attached --verify-sig on patch-verified & apply-update (buffered & streaming)
    let old_p = dir + "/old.bin"
    let new_p = dir + "/new.bin"
    let rsig_p = dir + "/old.sig"
    let delta_p = dir + "/upd.delta"
    let info_p = dir + "/info.json"
    let um_p = dir + "/um.json"
    let um_sig = dir + "/um.sig.json"
    let tm_p = dir + "/tm.json"
    let tm_sig = dir + "/tm.sig.json"
    @fs.write_binary(
      old_p,
      b"0123456789abcdef0123456789abcdef",
      create_mode=CreateNew,
    )
    @fs.write_binary(
      new_p,
      b"0123456789abcdefXXXX456789abcdef",
      create_mode=CreateNew,
    )
    execute(parse_plan(["signature", old_p, rsig_p, "--block-size", "8"]))
    execute(parse_plan(["delta", rsig_p, new_p, delta_p]))
    execute(parse_plan(["basis-info", old_p, rsig_p, info_p]))
    execute(parse_plan(["make-manifest", info_p, rsig_p, new_p, delta_p, um_p]))
    execute(
      parse_plan([
        "make-transfer-manifest", info_p, rsig_p, new_p, delta_p, tm_p,
      ]),
    )
    execute(parse_plan(["sign", um_p, priv1, um_sig]))
    execute(parse_plan(["sign", tm_p, priv1, tm_sig]))

    let pv_out = dir + "/pv.out"
    let au_out = dir + "/au.out"
    execute(
      parse_plan([
        "patch-verified", old_p, delta_p, um_p, pv_out, "--verify-sig", um_sig, "--verify-key",
        pub1, "--streaming",
      ]),
    )
    assert_eq(
      bounded_read(pv_out, d.max_output_bytes),
      b"0123456789abcdefXXXX456789abcdef",
    )

    execute(
      parse_plan([
        "apply-update", delta_p, tm_p, au_out, "--basis", old_p, "--verify-sig",
        tm_sig, "--verify-key", pub2, "--verify-key", pub1,
      ]),
    )
    assert_eq(
      bounded_read(au_out, d.max_output_bytes),
      b"0123456789abcdefXXXX456789abcdef",
    )

    // Wrong key on patch-verified & apply-update fails without writing output
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "patch-verified",
            old_p,
            delta_p,
            um_p,
            dir + "/pv-bad.out",
            "--verify-sig",
            um_sig,
            "--verify-key",
            pub2,
          ]),
        )
      },
      "UntrustedKey",
    )
    assert_true(!entry_exists(dir + "/pv-bad.out"))

    // dir-apply --archive --verify-sig
    let bdir = dir + "/bdir"
    let tdir = dir + "/tdir"
    @fs.mkdir(bdir)
    @fs.mkdir(tdir)
    @fs.write_binary(bdir + "/a.bin", b"v1", create_mode=CreateNew)
    @fs.write_binary(tdir + "/a.bin", b"v2", create_mode=CreateNew)
    let bsnap = dir + "/bd.snap.json"
    let sdir = dir + "/bdsigs"
    let arch = dir + "/bd.mbundle.gz"
    let arch_sig = dir + "/bd.mbundle.gz.sig.json"
    execute(parse_plan(["dir-snapshot", bdir, bsnap]))
    execute(parse_plan(["dir-signatures", bdir, bsnap, sdir]))
    execute(
      parse_plan(["dir-pack", bsnap, sdir, tdir, arch, "--archive", "--gzip"]),
    )
    execute(parse_plan(["sign", arch, priv1, arch_sig]))

    execute(
      parse_plan([
        "dir-apply",
        bdir,
        arch,
        dir + "/bd-ok",
        "--archive",
        "--gzip",
        "--verify-sig",
        arch_sig,
        "--verify-key",
        pub1,
      ]),
    )
    assert_eq(bounded_read(dir + "/bd-ok/a.bin", 16L), b"v2")

    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-apply",
            bdir,
            arch,
            dir + "/bd-bad",
            "--archive",
            "--gzip",
            "--verify-sig",
            arch_sig,
            "--verify-key",
            pub2,
            "--save-rollback",
            dir + "/bd-bad-rb.mbundle.gz",
          ]),
        )
      },
      "UntrustedKey",
    )
    assert_true(!entry_exists(dir + "/bd-bad"))
    assert_true(!entry_exists(dir + "/bd-bad-rb.mbundle.gz"))
  })
}

///|
async test "cli v060 seal and unseal key and passphrase buffered streaming and tamper rejection" {
  cli_test_scope(dir => {
    let key_p = dir + "/sym.key"
    let wrong_key_p = dir + "/wrong.key"
    let pw_p = dir + "/pass.txt"
    let wrong_pw_p = dir + "/wrong-pass.txt"
    @fs.write_binary(
      key_p,
      b"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\n",
      create_mode=CreateNew,
    )
    @fs.write_binary(
      wrong_key_p,
      b"ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100\n",
      create_mode=CreateNew,
    )
    @fs.write_binary(pw_p, b"correct-horse-battery\r\n", create_mode=CreateNew)
    @fs.write_binary(wrong_pw_p, b"wrong-passphrase\n", create_mode=CreateNew)

    // Multi-chunk >128 KiB payload
    let plain = Bytes::makei(140000, i => ((i * 71 + 17) % 256).to_byte())
    let plain_p = dir + "/plain.bin"
    @fs.write_binary(plain_p, plain, create_mode=CreateNew)

    let enc_buf = dir + "/enc-buf.menc"
    let enc_str = dir + "/enc-str.menc"
    let dec_a = dir + "/dec-a.bin"
    let dec_b = dir + "/dec-b.bin"
    execute(
      parse_plan([
        "seal", plain_p, enc_buf, "--key-file", key_p, "--chunk-size", "16384",
      ]),
    )
    execute(
      parse_plan([
        "seal", plain_p, enc_str, "--key-file", key_p, "--chunk-size", "16384", "--streaming",
      ]),
    )
    // Cross-mode unseal parity
    execute(
      parse_plan(["unseal", enc_buf, dec_a, "--key-file", key_p, "--streaming"]),
    )
    execute(parse_plan(["unseal", enc_str, dec_b, "--key-file", key_p]))
    assert_eq(bounded_read(dec_a, 200000L), plain)
    assert_eq(bounded_read(dec_b, 200000L), plain)

    // Tamper final chunk byte -> streaming unseal rejects atomically with zero output or temps
    let ct = bounded_read(enc_str, 300000L)
    let last_i = ct.length() - 1
    let tampered = ct[0:last_i].to_owned() +
      Bytes::from_array([(ct[last_i].to_int() ^ 0x01).to_byte()])
    let tampered_p = dir + "/tampered.menc"
    @fs.write_binary(tampered_p, tampered[:], create_mode=CreateNew)
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "unseal",
            tampered_p,
            dir + "/bad-dec.bin",
            "--key-file",
            key_p,
            "--streaming",
          ]),
        )
      },
      "AuthenticationFailed",
    )
    assert_true(!entry_exists(dir + "/bad-dec.bin"))

    // Wrong key rejected
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "unseal",
            enc_str,
            dir + "/bad-key.bin",
            "--key-file",
            wrong_key_p,
          ]),
        )
      },
      "AuthenticationFailed",
    )
    assert_true(!entry_exists(dir + "/bad-key.bin"))

    // Passphrase Argon2id roundtrip (buffered & streaming) + wrong passphrase rejection
    let small_p = dir + "/small.bin"
    @fs.write_binary(small_p, b"argon2id-secret-payload", create_mode=CreateNew)
    let pw_enc = dir + "/pw.menc"
    let pw_dec = dir + "/pw.out"
    execute(
      parse_plan([
        "seal", small_p, pw_enc, "--passphrase-file", pw_p, "--argon2-memory", "64",
        "--argon2-passes", "1", "--chunk-size", "4096", "--streaming",
      ]),
    )
    execute(
      parse_plan([
        "unseal", pw_enc, pw_dec, "--passphrase-file", pw_p, "--streaming",
      ]),
    )
    assert_eq(bounded_read(pw_dec, 1024L), b"argon2id-secret-payload")

    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "unseal",
            pw_enc,
            dir + "/pw-bad.out",
            "--passphrase-file",
            wrong_pw_p,
          ]),
        )
      },
      "AuthenticationFailed",
    )
    assert_true(!entry_exists(dir + "/pw-bad.out"))

    // Trailing data rejected
    let trail_p = dir + "/trail.menc"
    @fs.write_binary(trail_p, (ct + b"X")[:], create_mode=CreateNew)
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "unseal",
            trail_p,
            dir + "/trail-bad.out",
            "--key-file",
            key_p,
            "--streaming",
          ]),
        )
      },
      "TrailingData",
    )
    assert_true(!entry_exists(dir + "/trail-bad.out"))

    // Zero leaked temp files
    for name in @fs.readdir(dir, include_hidden=true, include_special=false) {
      assert_true(!name.has_prefix(".moonlibsync-"))
    }
  })
}

///|
async test "cli v060 completions emit all 28 commands for bash zsh and powershell" {
  let all_commands = [
    "signature", "delta", "patch", "reverse-delta", "basis-info", "make-manifest",
    "patch-verified", "inspect-signature", "inspect-delta", "check-patch", "inspect-manifest",
    "inspect-bundle", "make-transfer-manifest", "apply-update", "compress", "decompress",
    "keygen", "sign", "verify", "seal", "unseal", "dir-snapshot", "dir-plan", "dir-verify",
    "dir-signatures", "dir-pack", "dir-apply", "completions",
  ]
  for shell in ["bash", "zsh", "powershell"] {
    let out = StringBuilder()
    execute_completions(parse_plan(["completions", shell]), writer=b => {
      out.write_string(@utf8.decode(b))
    })
    let text = out.to_string()
    assert_true(text.length() > 200)
    for cmd in all_commands {
      assert_true(text.contains(cmd))
    }
    assert_true(text.contains("--profile"))
    assert_true(text.contains("--detect-moves"))
    assert_true(text.contains("--exclude-from"))
    assert_true(text.contains("--verify-sig"))
    assert_true(text.contains("--save-rollback"))
    assert_true(text.contains("--passphrase-file"))
  }
}

///|
async test "cli v060 redteam2 Windows device guard seal output ceiling and zsh completions" {
  // Windows DOS reserved device name detector (exact, case-insensitive, extension, trailing space)
  for
    bad_leaf in [
      "CON", "con", "Prn", "AUX", "nul", "NUL.txt", "con.tar.gz", "aux .log", "COM1",
      "com9.bin", "LPT1", "lpt9.json", "NUL:stream",
    ] {
    assert_true(is_windows_reserved_device_name(bad_leaf))
  }
  for
    ok_leaf in [
      "console.txt", "null.bin", "auxiliary", "com0", "com10", "lpt0", "lpt10", "my-nul.txt",
      "archive.mbundle.gz",
    ] {
    assert_true(!is_windows_reserved_device_name(ok_leaf))
  }

  // On Windows, prepare_output rejects reserved DOS device output paths cleanly
  if @path.sep != '/' {
    cli_test_scope(dir => {
      for bad_name in ["NUL", "con.txt", "Aux", "COM1.bin", "lpt9.log"] {
        expect_file_failure(
          () => {
            let _ = prepare_output(dir + "/" + bad_name)
          },
          "reserved Windows device output path",
        )
      }
    })
  }

  // seal default output ceiling stays 80 MiB unless --max-output-bytes is explicitly passed
  let seal_default_plan = parse_plan([
    "seal", "in.bin", "out.menc", "--key-file", "k.hex",
  ])
  assert_true(!seal_default_plan.explicit_max_output)
  let sl_def = seal_limits_for_plan(seal_default_plan)
  assert_eq(sl_def.max_input_bytes, 67108864L)
  assert_eq(sl_def.max_output_bytes, 83886080L)

  let seal_explicit_small = parse_plan([
    "seal", "in.bin", "out.menc", "--key-file", "k.hex", "--max-output-bytes", "100",
  ])
  assert_true(seal_explicit_small.explicit_max_output)
  assert_eq(seal_limits_for_plan(seal_explicit_small).max_output_bytes, 100L)

  let seal_explicit_large = parse_plan([
    "seal", "in.bin", "out.menc", "--key-file", "k.hex", "--max-output-bytes", "100000000",
  ])
  assert_true(seal_explicit_large.explicit_max_output)
  assert_eq(
    seal_limits_for_plan(seal_explicit_large).max_output_bytes,
    100000000L,
  )

  let unseal_default_plan = parse_plan([
    "unseal", "in.menc", "out.bin", "--key-file", "k.hex",
  ])
  let usl_def = seal_limits_for_plan(unseal_default_plan)
  assert_eq(usl_def.max_input_bytes, 83886080L)
  assert_eq(usl_def.max_output_bytes, 67108864L)

  // Verify explicit --max-output-bytes 100 actually rejects seal output > 100 bytes
  cli_test_scope(dir => {
    let key_p = dir + "/k.hex"
    let in_p = dir + "/in.bin"
    @fs.write_binary(
      key_p,
      b"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\n",
      create_mode=CreateNew,
    )
    @fs.write_binary(
      in_p,
      Bytes::makei(256, i => (i % 256).to_byte()),
      create_mode=CreateNew,
    )
    for streaming in [false, true] {
      let args = [
        "seal",
        in_p,
        dir + "/too-big-\{streaming}.menc",
        "--key-file",
        key_p,
        "--max-output-bytes",
        "100",
      ]
      if streaming {
        args.push("--streaming")
      }
      expect_file_failure(() => execute(parse_plan(args)), "LimitExceeded")
      assert_true(!entry_exists(dir + "/too-big-\{streaming}.menc"))
    }
  })

  // zsh completion splits write commands and non-streaming inspect commands cleanly
  let zsh = completion_script_for_shell("zsh")
  assert_true(
    zsh.contains(
      "delta|patch|basis-info|make-manifest|compress|decompress|sign)\n      _arguments '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;",
    ),
  )
  assert_true(
    zsh.contains(
      "inspect-signature|inspect-manifest)\n      _arguments '--json[Output JSON]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;",
    ),
  )
  assert_true(
    zsh.contains(
      "inspect-delta|check-patch)\n      _arguments '--json[Output JSON]' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;",
    ),
  )
  assert_true(zsh.contains("*)\n      _arguments '*:file:_files' ;;"))
}

///|
async test "cli v060 redteam2 rollback exclude isolation cyclic swap and reverse-delta limits" {
  cli_test_scope(dir => {
    let dl = @lib.DirLimits::default()

    // 1. Rollback exclude isolation (excluded secret + excluded oversized file > --max-file-bytes)
    let ex_basis = dir + "/ex-basis"
    let ex_target = dir + "/ex-target"
    @fs.mkdir(ex_basis)
    @fs.mkdir(ex_target)
    let edit_v1 = Bytes::makei(3000, i => ((i * 23 + 7) % 256).to_byte())
    let edit_v2 = edit_v1[0:1500].to_owned() +
      b"PATCHED-SYNCED" +
      edit_v1[1514:].to_owned()
    @fs.write_binary(ex_basis + "/keep.bin", b"keep-v1", create_mode=CreateNew)
    @fs.write_binary(ex_basis + "/edit.bin", edit_v1, create_mode=CreateNew)
    @fs.write_binary(ex_basis + "/drop.bin", b"drop-v1", create_mode=CreateNew)
    @fs.write_binary(
      ex_basis + "/secret.log",
      b"TOP-SECRET-EXCLUDED",
      create_mode=CreateNew,
    )
    @fs.write_binary(
      ex_basis + "/huge.log",
      Bytes::make(12000, b'\x41'),
      create_mode=CreateNew,
    )

    @fs.write_binary(ex_target + "/keep.bin", b"keep-v1", create_mode=CreateNew)
    @fs.write_binary(ex_target + "/edit.bin", edit_v2, create_mode=CreateNew)
    @fs.write_binary(ex_target + "/add.bin", b"added-v2", create_mode=CreateNew)

    let ex_bs = dir + "/ex-b.snap.json"
    let ex_ts = dir + "/ex-t.snap.json"
    let ex_sigs = dir + "/ex-sigs"
    let ex_arch = dir + "/ex.mbundle.gz"
    let ex_bdir = dir + "/ex-bundle-dir"
    let ex_out = dir + "/ex-out"
    let ex_out_buf = dir + "/ex-out-buf"
    let ex_rb = dir + "/ex-rb.mbundle.gz"
    let ex_restored = dir + "/ex-restored"

    execute(
      parse_plan([
        "dir-snapshot", ex_basis, ex_bs, "--exclude", "*.log", "--max-file-bytes",
        "4096",
      ]),
    )
    execute(
      parse_plan([
        "dir-snapshot", ex_target, ex_ts, "--exclude", "*.log", "--max-file-bytes",
        "4096",
      ]),
    )
    execute(
      parse_plan([
        "dir-signatures", ex_basis, ex_bs, ex_sigs, "--block-size", "256", "--max-file-bytes",
        "4096",
      ]),
    )
    execute(
      parse_plan([
        "dir-pack", ex_bs, ex_sigs, ex_target, ex_arch, "--archive", "--gzip", "--exclude",
        "*.log", "--max-file-bytes", "4096",
      ]),
    )
    // Also pack & apply directory bundle non-streaming (exercises synced delta output)
    execute(
      parse_plan([
        "dir-pack", ex_bs, ex_sigs, ex_target, ex_bdir, "--exclude", "*.log", "--max-file-bytes",
        "4096",
      ]),
    )
    execute(
      parse_plan([
        "dir-apply", ex_basis, ex_bdir, ex_out_buf, "--max-file-bytes", "4096",
      ]),
    )
    assert_eq(bounded_read(ex_out_buf + "/edit.bin", 4096L), edit_v2)

    // dir-apply --save-rollback MUST NOT touch secret.log or huge.log!
    execute(
      parse_plan([
        "dir-apply", ex_basis, ex_arch, ex_out, "--archive", "--gzip", "--max-file-bytes",
        "4096", "--save-rollback", ex_rb,
      ]),
    )
    let rb_ib = StringBuilder()
    execute_inspect_bundle(
      parse_plan([
        "inspect-bundle", ex_rb, "--gzip", "--json", "--max-file-bytes", "4096",
      ]),
      true,
      writer=b => rb_ib.write_string(@utf8.decode(b)),
    )
    let rb_ib_str = rb_ib.to_string()
    assert_true(!rb_ib_str.contains("secret.log"))
    assert_true(!rb_ib_str.contains("huge.log"))

    execute(
      parse_plan([
        "dir-apply", ex_out, ex_rb, ex_restored, "--archive", "--gzip", "--max-file-bytes",
        "4096",
      ]),
    )
    let ver_rb = StringBuilder()
    execute_dir_verify(
      parse_plan([
        "dir-verify", ex_restored, ex_bs, "--json", "--max-file-bytes", "4096",
      ]),
      true,
      writer=b => ver_rb.write_string(@utf8.decode(b)),
    )
    let ver_rb_rep = @lib.parse_dir_verify_report(
      @utf8.encode(ver_rb.to_string()),
      dl,
    )
    assert_true(
      ver_rb_rep.ok &&
      ver_rb_rep.matched_count == 3L &&
      ver_rb_rep.extra_count == 0L,
    )

    // 2. Cyclic swap (a.bin <-> b.bin) + overwrite-from-sibling (c.bin <- d.bin)
    let sw_basis = dir + "/sw-basis"
    let sw_target = dir + "/sw-target"
    @fs.mkdir(sw_basis)
    @fs.mkdir(sw_target)
    let data_a = Bytes::makei(4096, i => ((i * 13 + 1) % 256).to_byte())
    let data_b = Bytes::makei(5000, i => ((i * 37 + 9) % 256).to_byte())
    let data_c = Bytes::makei(2048, i => ((i * 59 + 3) % 256).to_byte())
    let data_d = Bytes::makei(3072, i => ((i * 71 + 17) % 256).to_byte())
    @fs.write_binary(sw_basis + "/a.bin", data_a, create_mode=CreateNew)
    @fs.write_binary(sw_basis + "/b.bin", data_b, create_mode=CreateNew)
    @fs.write_binary(sw_basis + "/c.bin", data_c, create_mode=CreateNew)
    @fs.write_binary(sw_basis + "/d.bin", data_d, create_mode=CreateNew)
    @fs.write_binary(sw_target + "/a.bin", data_b, create_mode=CreateNew)
    @fs.write_binary(sw_target + "/b.bin", data_a, create_mode=CreateNew)
    @fs.write_binary(sw_target + "/c.bin", data_d, create_mode=CreateNew)
    @fs.write_binary(sw_target + "/d.bin", data_d, create_mode=CreateNew)

    let sw_bs = dir + "/sw-b.snap.json"
    let sw_ts = dir + "/sw-t.snap.json"
    let sw_sigs = dir + "/sw-sigs"
    let sw_arch = dir + "/sw.mbundle.gz"
    let sw_out = dir + "/sw-out"
    let sw_rb = dir + "/sw-rb.mbundle.gz"
    let sw_restored = dir + "/sw-restored"
    execute(parse_plan(["dir-snapshot", sw_basis, sw_bs]))
    execute(parse_plan(["dir-snapshot", sw_target, sw_ts]))
    execute(parse_plan(["dir-signatures", sw_basis, sw_bs, sw_sigs]))
    execute(
      parse_plan([
        "dir-pack", sw_bs, sw_sigs, sw_target, sw_arch, "--detect-moves", "--archive",
        "--gzip",
      ]),
    )
    let sw_ib = StringBuilder()
    execute_inspect_bundle(
      parse_plan(["inspect-bundle", sw_arch, "--gzip", "--json"]),
      true,
      writer=b => sw_ib.write_string(@utf8.decode(b)),
    )
    let sw_ib_str = sw_ib.to_string()
    assert_true(sw_ib_str.contains("\"copy_from_basis\":\"3\""))
    assert_true(sw_ib_str.contains("\"total_payload_bytes\":\"0\""))

    execute(
      parse_plan([
        "dir-apply", sw_basis, sw_arch, sw_out, "--archive", "--gzip", "--save-rollback",
        sw_rb,
      ]),
    )
    assert_eq(bounded_read(sw_out + "/a.bin", 8192L), data_b)
    assert_eq(bounded_read(sw_out + "/b.bin", 8192L), data_a)
    assert_eq(bounded_read(sw_out + "/c.bin", 8192L), data_d)
    assert_eq(bounded_read(sw_out + "/d.bin", 8192L), data_d)

    execute(
      parse_plan([
        "dir-apply", sw_out, sw_rb, sw_restored, "--archive", "--gzip",
      ]),
    )
    assert_eq(bounded_read(sw_restored + "/a.bin", 8192L), data_a)
    assert_eq(bounded_read(sw_restored + "/b.bin", 8192L), data_b)
    assert_eq(bounded_read(sw_restored + "/c.bin", 8192L), data_c)
    assert_eq(bounded_read(sw_restored + "/d.bin", 8192L), data_d)

    // 3. reverse-delta asymmetric --max-old-bytes / --max-new-bytes (buffered & streaming)
    let small_p = dir + "/rev-small.bin"
    let big_p = dir + "/rev-big.bin"
    let small_bytes = Bytes::makei(200, i => ((i * 11 + 3) % 256).to_byte())
    let big_bytes = Bytes::makei(5000, i => ((i * 31 + 5) % 256).to_byte())
    @fs.write_binary(small_p, small_bytes, create_mode=CreateNew)
    @fs.write_binary(big_p, big_bytes, create_mode=CreateNew)

    // Small OLD (200) -> Big NEW (5000) with --max-old-bytes 500 --max-new-bytes 6000
    let r1_buf = dir + "/r1-buf.delta"
    let r1_str = dir + "/r1-str.delta"
    execute(
      parse_plan([
        "reverse-delta", small_p, big_p, r1_buf, "--block-size", "auto", "--max-old-bytes",
        "500", "--max-new-bytes", "6000",
      ]),
    )
    execute(
      parse_plan([
        "reverse-delta", small_p, big_p, r1_str, "--block-size", "auto", "--streaming",
        "--max-old-bytes", "500", "--max-new-bytes", "6000",
      ]),
    )
    assert_eq(bounded_read(r1_buf, 65536L), bounded_read(r1_str, 65536L))
    execute(parse_plan(["patch", big_p, r1_str, dir + "/r1-restored.bin"]))
    assert_eq(bounded_read(dir + "/r1-restored.bin", 1024L), small_bytes)

    // Tighter --max-old-bytes rejects OLD; tighter --max-new-bytes rejects NEW
    for streaming in [false, true] {
      let args_old = [
        "reverse-delta",
        small_p,
        big_p,
        dir + "/r1-fail-old-\{streaming}.delta",
        "--max-old-bytes",
        "100",
        "--max-new-bytes",
        "6000",
      ]
      if streaming {
        args_old.push("--streaming")
      }
      expect_file_failure(
        () => execute(parse_plan(args_old)),
        "ReadLimitExceeded",
      )
      let args_new = [
        "reverse-delta",
        small_p,
        big_p,
        dir + "/r1-fail-new-\{streaming}.delta",
        "--max-old-bytes",
        "500",
        "--max-new-bytes",
        "4000",
      ]
      if streaming {
        args_new.push("--streaming")
      }
      expect_file_failure(
        () => execute(parse_plan(args_new)),
        "ReadLimitExceeded",
      )
    }

    // Big OLD (5000) -> Small NEW (200) with --max-old-bytes 6000 --max-new-bytes 500
    let r2_buf = dir + "/r2-buf.delta"
    let r2_str = dir + "/r2-str.delta"
    execute(
      parse_plan([
        "reverse-delta", big_p, small_p, r2_buf, "--block-size", "auto", "--max-old-bytes",
        "6000", "--max-new-bytes", "500",
      ]),
    )
    execute(
      parse_plan([
        "reverse-delta", big_p, small_p, r2_str, "--block-size", "auto", "--streaming",
        "--max-old-bytes", "6000", "--max-new-bytes", "500",
      ]),
    )
    assert_eq(bounded_read(r2_buf, 65536L), bounded_read(r2_str, 65536L))
    execute(parse_plan(["patch", small_p, r2_str, dir + "/r2-restored.bin"]))
    assert_eq(bounded_read(dir + "/r2-restored.bin", 8192L), big_bytes)
  })
}
