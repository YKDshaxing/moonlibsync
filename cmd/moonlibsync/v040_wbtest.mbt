// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "cli streaming plan parsing and command gating" {
  for
    args in [
      ["signature", "--streaming", "old", "sig"],
      ["delta", "sig", "new", "--streaming", "delta"],
      ["patch", "old", "delta", "out", "--streaming"],
      ["basis-info", "old", "sig", "info", "--streaming"],
      ["make-manifest", "i", "s", "n", "d", "m", "--streaming"],
      ["make-transfer-manifest", "i", "s", "n", "d", "m", "--streaming"],
      ["patch-verified", "old", "delta", "manifest", "out", "--streaming"],
      [
        "apply-update", "payload", "manifest", "out", "--basis", "old", "--streaming",
      ],
      ["inspect-delta", "d", "--json", "--streaming"],
      ["check-patch", "old", "d", "--json", "--streaming"],
      ["compress", "in", "out", "--streaming"],
      ["decompress", "in", "out", "--streaming"],
      [
        "dir-signatures", "dir", "snap", "sigs", "--block-size", "auto", "--streaming",
      ],
      [
        "dir-pack", "snap", "sigs", "target", "bundle", "--min-savings", "16", "--streaming",
      ],
      ["dir-apply", "basis", "bundle", "out", "--streaming"],
    ] {
    let p = parse_plan(args)
    assert_true(p.streaming)
  }
  assert_true(!parse_plan(["signature", "old", "sig"]).streaming)
  assert_true(
    parse_plan(["dir-signatures", "d", "s", "out"]).mode is WriteDir("out"),
  )
  assert_true(
    parse_plan(["dir-pack", "s", "sg", "t", "b"]).mode is WriteDir("b"),
  )
  assert_true(parse_plan(["dir-apply", "b", "bd", "o"]).mode is WriteDir("o"))
  for
    bad in [
      ["signature", "--streaming", "--streaming", "old", "sig"],
      ["inspect-signature", "sig", "--streaming"],
      ["inspect-manifest", "m.json", "--streaming"],
      ["dir-snapshot", "d", "out", "--streaming"],
      ["dir-plan", "a", "b", "--streaming"],
      ["compress", "in", "out", "--json"],
      ["decompress", "in", "out", "--max-entries", "10"],
      ["dir-apply", "b", "bd", "o", "--min-savings", "1"],
      ["dir-pack", "s", "sg", "t", "b", "--block-size", "64"],
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
test "cli dir-snapshot and dir-plan option parsing and limit isolation" {
  let snap = parse_plan([
    "dir-snapshot", "--max-entries", "10", "--max-path-bytes", "256", "--max-depth",
    "4", "--max-snapshot-bytes", "65536", "--max-file-bytes", "1024", "src", "snap.json",
  ])
  assert_eq(snap.operation, "dir-snapshot")
  assert_eq(snap.inputs, ["src"])
  assert_true(snap.mode is WriteFile("snap.json"))
  assert_eq(snap.dir_limits.max_entries, 10L)
  assert_eq(snap.dir_limits.max_path_bytes, 256L)
  assert_eq(snap.dir_limits.max_depth, 4L)
  assert_eq(snap.dir_limits.max_snapshot_bytes, 65536L)
  assert_eq(snap.dir_limits.max_file_bytes, 1024L)

  let plan = parse_plan(["dir-plan", "--json", "--", "--a", "--b"])
  assert_eq(plan.operation, "dir-plan")
  assert_eq(plan.inputs, ["--a", "--b"])
  assert_true(plan.mode is Inspect(true))

  for
    bad in [
      ["dir-snapshot"],
      ["dir-snapshot", "only-dir"],
      ["dir-snapshot", "d", "o", "--json"],
      ["dir-snapshot", "d", "o", "--max-old-bytes", "10"],
      ["dir-plan", "a"],
      ["dir-plan", "a", "b", "c"],
      ["signature", "old", "sig", "--max-entries", "10"],
      ["dir-snapshot", "d", "o", "--max-depth", "0"],
      ["dir-snapshot", "d", "o", "--max-depth", "65"],
      ["dir-snapshot", "d", "o", "--max-snapshot-bytes", "63"],
      ["dir-snapshot", "d", "o", "--max-entries", "65537"],
      ["dir-snapshot", "d", "o", "--max-entries", "1", "--max-entries", "2"],
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
async test "cli streaming roundtrip beyond 64 KiB chunk boundary matches non-streaming" {
  cli_test_scope(dir => {
    let d = @lib.Limits::default()
    let old = Bytes::makei(140000, i => {
      ((i * 73 + 19 + i / 2048 * 11) % 256).to_byte()
    })
    let new_bytes = old[0:70000].to_owned() +
      b"STREAMED-MIDDLE" +
      old[70015:].to_owned()
    let old_path = dir + "/old.bin"
    let new_path = dir + "/new.bin"
    let sig_stream = dir + "/stream.sig"
    let delta_stream = dir + "/stream.delta"
    let out_stream = dir + "/stream.out"
    let info_path = dir + "/info.json"
    let manifest_path = dir + "/update.json"
    let transfer_path = dir + "/transfer.json"
    let out_verified = dir + "/verified.out"
    let out_transfer = dir + "/transfer.out"

    @fs.write_binary(old_path, old, create_mode=CreateNew)
    @fs.write_binary(new_path, new_bytes, create_mode=CreateNew)

    execute(
      parse_plan([
        "signature", old_path, sig_stream, "--streaming", "--block-size", "auto",
      ]),
    )
    let sig_bytes = bounded_read(sig_stream, d.max_signature_bytes)
    let expected_block = @lib.recommend_block_len(
      old.length().to_int64(),
      32L,
      d,
    )
    assert_eq(
      sig_bytes,
      @lib.signature(
        old,
        { block_len: expected_block, strong_sum_len: 32L, },
        d,
      ),
    )

    execute(
      parse_plan(["delta", sig_stream, new_path, delta_stream, "--streaming"]),
    )
    let delta_bytes = bounded_read(delta_stream, d.max_delta_bytes)
    assert_eq(delta_bytes, @lib.delta(sig_bytes, new_bytes, d))

    execute(
      parse_plan(["patch", old_path, delta_stream, out_stream, "--streaming"]),
    )
    assert_eq(bounded_read(out_stream, d.max_output_bytes), new_bytes)

    execute(parse_plan(["basis-info", old_path, sig_stream, info_path]))
    execute(
      parse_plan([
        "make-manifest", info_path, sig_stream, new_path, delta_stream, manifest_path,
      ]),
    )
    execute(
      parse_plan([
        "patch-verified", old_path, delta_stream, manifest_path, out_verified, "--streaming",
      ]),
    )
    assert_eq(bounded_read(out_verified, d.max_output_bytes), new_bytes)

    execute(
      parse_plan([
        "make-transfer-manifest", info_path, sig_stream, new_path, delta_stream,
        transfer_path,
      ]),
    )
    execute(
      parse_plan([
        "apply-update", delta_stream, transfer_path, out_transfer, "--basis", old_path,
        "--streaming",
      ]),
    )
    assert_eq(bounded_read(out_transfer, d.max_output_bytes), new_bytes)
  })
}

///|
async test "cli verified streaming leaves no output or temp on mismatch and full apply-update works" {
  cli_test_scope(dir => {
    let d = @lib.Limits::default()
    let old = b"abcdefghijklmnop"
    let sig = @lib.signature(old, { block_len: 8L, strong_sum_len: 32L, }, d)
    let info = @lib.create_basis_info(old, sig, d)
    let bad_new = b"xyz"
    let delta_bytes = @lib.delta(sig, b"abcdefghXYijklmn", d)
    let um = @lib.create_update_manifest(
      info, sig, b"abcdefghXYijklmn", delta_bytes, d,
    )
    let bad_um : @lib.UpdateManifest = {
      ..um,
      result: {
        ..um.result,
        sha256: "0000000000000000000000000000000000000000000000000000000000000000",
      },
    }
    let old_path = dir + "/old"
    let delta_path = dir + "/delta"
    let manifest_path = dir + "/bad.json"
    let failed_out = dir + "/failed.out"
    @fs.write_binary(old_path, old, create_mode=CreateNew)
    @fs.write_binary(delta_path, delta_bytes, create_mode=CreateNew)
    @fs.write_binary(
      manifest_path,
      @lib.encode_update_manifest(bad_um, d),
      create_mode=CreateNew,
    )
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "patch-verified", old_path, delta_path, manifest_path, failed_out, "--streaming",
          ]),
        )
      },
      "result_sha256",
    )
    assert_true(!entry_exists(failed_out))
    for name in @fs.readdir(dir, include_hidden=true, include_special=false) {
      assert_true(!name.has_prefix(".moonlibsync-"))
    }

    // Full-file apply-update --streaming path
    let cand = @lib.delta(sig, bad_new, d)
    let tm = @lib.create_transfer_manifest(
      info,
      sig,
      bad_new,
      cand,
      @lib.UpdateOptions::default(),
      d,
    )
    let full_payload = dir + "/full.bin"
    let full_manifest = dir + "/full.json"
    let full_out = dir + "/full.out"
    @fs.write_binary(full_payload, bad_new, create_mode=CreateNew)
    @fs.write_binary(
      full_manifest,
      @lib.encode_transfer_manifest(tm, d),
      create_mode=CreateNew,
    )
    execute(
      parse_plan([
        "apply-update", full_payload, full_manifest, full_out, "--streaming",
      ]),
    )
    assert_eq(bounded_read(full_out, 16L), bad_new)
  })
}

///|
async test "cli stream_open_chunks rejects concurrent growth before publish" {
  cli_test_scope(dir => {
    let path = dir + "/growing"
    @fs.write_binary(path, b"abc", create_mode=CreateNew)
    let file = open_regular_input(path)
    defer file.close()
    let hasher = @lib.Sha256Hasher::new(10L)
    expect_file_failure(
      () => {
        stream_open_chunks(
          file,
          path,
          3L,
          after_start=() => {
            @fs.write_binary(path, b"abcd", create_mode=TruncateExisting)
          },
          chunk => hasher.update(chunk),
        )
      },
      "InputChanged",
    )
  })
}

///|
async test "cli dir-snapshot and dir-plan handle nested trees limits and json format" {
  cli_test_scope(dir => {
    let v1 = dir + "/v1"
    let v2 = dir + "/v2"
    @fs.mkdir(v1 + "/sub", recursive=true)
    @fs.mkdir(v2 + "/sub", recursive=true)
    @fs.write_binary(v1 + "/a.bin", b"alpha", create_mode=CreateNew)
    @fs.write_binary(v1 + "/sub/b.bin", b"beta1", create_mode=CreateNew)
    @fs.write_binary(v1 + "/old.bin", b"drop", create_mode=CreateNew)
    @fs.write_binary(v2 + "/a.bin", b"alpha", create_mode=CreateNew)
    @fs.write_binary(v2 + "/sub/b.bin", b"beta22", create_mode=CreateNew)
    @fs.write_binary(v2 + "/new.bin", b"added", create_mode=CreateNew)

    let snap1 = dir + "/v1.snap.json"
    let snap2 = dir + "/v2.snap.json"
    execute(parse_plan(["dir-snapshot", v1, snap1]))
    execute(parse_plan(["dir-snapshot", v2, snap2]))

    let lim = @lib.DirLimits::default()
    let s1 = @lib.parse_dir_snapshot(
      bounded_read(snap1, lim.max_snapshot_bytes),
      lim,
    )
    let s2 = @lib.parse_dir_snapshot(
      bounded_read(snap2, lim.max_snapshot_bytes),
      lim,
    )
    let plan = @lib.plan_dir_sync(s1, s2, lim)
    assert_eq(plan.unchanged_count, 1L)
    assert_eq(plan.add_count, 1L)
    assert_eq(plan.update_count, 1L)
    assert_eq(plan.delete_count, 1L)
    let json_text = format_dir_plan(plan, lim, true)
    assert_true(json_text.contains("\"schema_version\":3"))
    assert_true(json_text.contains("\"kind\":\"moonlibsync-dir-plan\""))
    let human_text = format_dir_plan(plan, lim, false)
    assert_true(human_text.contains("update-candidate: sub/b.bin"))

    // Tight depth limit rejects nested sub/b.bin
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-snapshot",
            v1,
            dir + "/shallow.json",
            "--max-depth",
            "1",
          ]),
        )
      },
      "ResourceLimit:path_depth",
    )
    assert_true(!entry_exists(dir + "/shallow.json"))
  })
}

///|
async test "cli streaming manifests inspect-delta check-patch and gzip commands match buffered" {
  cli_test_scope(dir => {
    let d = @lib.Limits::default()
    let old = Bytes::makei(140000, i => {
      ((i * 53 + 17 + i / 1024 * 7) % 256).to_byte()
    })
    let new_bytes = old[0:66000].to_owned() +
      b"STREAM-ALL-COMMANDS-040" +
      old[66023:].to_owned()
    let old_p = dir + "/old.bin"
    let new_p = dir + "/new.bin"
    let sig_p = dir + "/old.sig"
    let delta_p = dir + "/upd.delta"
    let info_plain = dir + "/info-plain.json"
    let info_stream = dir + "/info-stream.json"
    let um_plain = dir + "/um-plain.json"
    let um_stream = dir + "/um-stream.json"
    let tm_plain = dir + "/tm-plain.json"
    let tm_stream = dir + "/tm-stream.json"
    let gz_p = dir + "/upd.delta.gz"
    let raw_out = dir + "/upd.delta.restored"
    @fs.write_binary(old_p, old, create_mode=CreateNew)
    @fs.write_binary(new_p, new_bytes, create_mode=CreateNew)
    execute(
      parse_plan([
        "signature", old_p, sig_p, "--streaming", "--block-size", "auto",
      ]),
    )
    execute(parse_plan(["delta", sig_p, new_p, delta_p, "--streaming"]))

    // basis-info / make-manifest / make-transfer-manifest --streaming byte-for-byte parity
    execute(parse_plan(["basis-info", old_p, sig_p, info_plain]))
    execute(
      parse_plan(["basis-info", old_p, sig_p, info_stream, "--streaming"]),
    )
    assert_eq(
      bounded_read(info_stream, 65536L),
      bounded_read(info_plain, 65536L),
    )

    execute(
      parse_plan(["make-manifest", info_plain, sig_p, new_p, delta_p, um_plain]),
    )
    execute(
      parse_plan([
        "make-manifest", info_stream, sig_p, new_p, delta_p, um_stream, "--streaming",
      ]),
    )
    assert_eq(bounded_read(um_stream, 65536L), bounded_read(um_plain, 65536L))

    execute(
      parse_plan([
        "make-transfer-manifest", info_plain, sig_p, new_p, delta_p, tm_plain,
      ]),
    )
    execute(
      parse_plan([
        "make-transfer-manifest", info_stream, sig_p, new_p, delta_p, tm_stream,
        "--streaming",
      ]),
    )
    assert_eq(bounded_read(tm_stream, 65536L), bounded_read(tm_plain, 65536L))

    // Streaming inspect-delta and check-patch match buffered results exactly
    let s_delta = stream_inspect_delta_file(delta_p, d)
    let p_delta = @lib.inspect_delta(
      bounded_read(delta_p, d.max_delta_bytes),
      d,
    )
    assert_eq(format_delta(s_delta, true), format_delta(p_delta, true))
    let s_check = stream_check_patch_file(old_p, delta_p, d)
    let p_check = check_patch_file(old_p, delta_p, d)
    assert_eq(format_patch(s_check, true), format_patch(p_check, true))

    // compress / decompress --streaming roundtrip + zip-bomb rejection
    execute(parse_plan(["compress", delta_p, gz_p, "--streaming"]))
    execute(parse_plan(["decompress", gz_p, raw_out, "--streaming"]))
    assert_eq(
      bounded_read(raw_out, d.max_delta_bytes),
      bounded_read(delta_p, d.max_delta_bytes),
    )

    let bomb_src = dir + "/zeros.bin"
    let bomb_gz = dir + "/zeros.gz"
    let bomb_out = dir + "/zeros.out"
    @fs.write_binary(
      bomb_src,
      Bytes::make(262144, b'\x00'),
      create_mode=CreateNew,
    )
    execute(parse_plan(["compress", bomb_src, bomb_gz, "--streaming"]))
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "decompress", bomb_gz, bomb_out, "--streaming", "--max-output-bytes",
            "4096",
          ]),
        )
      },
      "LimitExceeded",
    )
    assert_true(!entry_exists(bomb_out))
  })
}

///|
async test "cli dir-signatures dir-pack dir-apply end-to-end bundle roundtrip and tamper rejection" {
  cli_test_scope(dir => {
    let basis = dir + "/basis"
    let target = dir + "/target"
    @fs.mkdir(basis + "/nested", recursive=true)
    @fs.mkdir(target + "/nested", recursive=true)

    let large_old = Bytes::makei(90000, i => {
      ((i * 31 + i / 512 * 13) % 256).to_byte()
    })
    let large_new = large_old[0:45000].to_owned() +
      b"DIR-BUNDLE-DELTA-EDIT" +
      large_old[45021:].to_owned()
    @fs.write_binary(
      basis + "/keep.bin",
      b"identical-file",
      create_mode=CreateNew,
    )
    @fs.write_binary(
      basis + "/nested/large.bin",
      large_old,
      create_mode=CreateNew,
    )
    @fs.write_binary(basis + "/small.bin", b"v1", create_mode=CreateNew)
    @fs.write_binary(basis + "/drop.bin", b"remove-me", create_mode=CreateNew)

    @fs.write_binary(
      target + "/keep.bin",
      b"identical-file",
      create_mode=CreateNew,
    )
    @fs.write_binary(
      target + "/nested/large.bin",
      large_new,
      create_mode=CreateNew,
    )
    @fs.write_binary(target + "/small.bin", b"v2-short", create_mode=CreateNew)
    @fs.write_binary(
      target + "/added.bin",
      b"brand-new-file",
      create_mode=CreateNew,
    )

    let basis_snap = dir + "/basis.snap.json"
    let sig_dir = dir + "/sigs"
    let bundle_dir = dir + "/bundle"
    let out_dir = dir + "/restored"
    execute(parse_plan(["dir-snapshot", basis, basis_snap]))
    execute(
      parse_plan([
        "dir-signatures", basis, basis_snap, sig_dir, "--block-size", "auto", "--streaming",
      ]),
    )
    execute(
      parse_plan([
        "dir-pack", basis_snap, sig_dir, target, bundle_dir, "--streaming",
      ]),
    )
    let dl = @lib.DirLimits::default()
    let fl = @lib.Limits::default()
    let bm = @lib.parse_dir_bundle_manifest(
      bounded_read(bundle_dir + "/bundle.json", dl.max_snapshot_bytes * 8L),
      dl,
      fl,
    )
    assert_eq(bm.unchanged_count, 1L)
    assert_eq(bm.add_full_count, 1L)
    assert_eq(bm.update_delta_count, 1L)
    assert_eq(bm.update_full_count, 1L)
    assert_eq(bm.delete_count, 1L)
    assert_true(bm.total_payload_bytes < large_new.length().to_int64() / 4L)

    execute(
      parse_plan(["dir-apply", basis, bundle_dir, out_dir, "--streaming"]),
    )
    // Restored directory matches target snapshot byte-for-byte
    let target_snap = dir + "/target.snap.json"
    let restored_snap = dir + "/restored.snap.json"
    execute(parse_plan(["dir-snapshot", target, target_snap]))
    execute(parse_plan(["dir-snapshot", out_dir, restored_snap]))
    assert_eq(
      bounded_read(restored_snap, dl.max_snapshot_bytes),
      bounded_read(target_snap, dl.max_snapshot_bytes),
    )
    // BASIS_DIR was never modified (drop.bin still present!)
    assert_true(entry_exists(basis + "/drop.bin"))

    // Refuses existing output directory
    expect_file_failure(
      () => execute(parse_plan(["dir-apply", basis, bundle_dir, out_dir])),
      "already exists",
    )

    // Tamper a bundle payload -> dir-apply fails atomically with no partial OUT_DIR
    let payload_files = @fs.readdir(bundle_dir + "/payloads", sort=true)
    assert_true(payload_files.length() > 0)
    let victim = bundle_dir + "/payloads/" + payload_files[0]
    let orig = bounded_read(victim, 1000000L)
    let tampered = if orig.length() > 0 {
      Bytes::from_array([(orig[0].to_int() ^ 0xff).to_byte()]) +
      orig[1:].to_owned()
    } else {
      b"x"
    }
    @fs.write_binary(victim, tampered[:], create_mode=TruncateExisting)
    let bad_out = dir + "/bad-restored"
    expect_file_failure(
      () => {
        execute(
          parse_plan(["dir-apply", basis, bundle_dir, bad_out, "--streaming"]),
        )
      },
      "BindingMismatch",
    )
    assert_true(!entry_exists(bad_out))
    for name in @fs.readdir(dir, include_hidden=true, include_special=false) {
      assert_true(!name.has_prefix(".moonlibsync-"))
    }
  })
}
