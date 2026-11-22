// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "cli streaming plan parsing and command gating" {
  for
    args in [
      ["signature", "--streaming", "old", "sig"],
      ["delta", "sig", "new", "--streaming", "delta"],
      ["patch", "old", "delta", "out", "--streaming"],
      ["patch-verified", "old", "delta", "manifest", "out", "--streaming"],
      [
        "apply-update", "payload", "manifest", "out", "--basis", "old", "--streaming",
      ],
    ] {
    let p = parse_plan(args)
    assert_true(p.streaming)
  }
  assert_true(!parse_plan(["signature", "old", "sig"]).streaming)
  for
    bad in [
      ["signature", "--streaming", "--streaming", "old", "sig"],
      ["inspect-signature", "sig", "--streaming"],
      ["inspect-manifest", "m.json", "--streaming"],
      ["basis-info", "old", "sig", "info", "--streaming"],
      ["make-manifest", "i", "s", "n", "d", "m", "--streaming"],
      ["dir-snapshot", "d", "out", "--streaming"],
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
