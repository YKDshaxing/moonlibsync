// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "cli v050 option parsing and gating for archive gzip exclude progress dir-verify" {
  let pack_dir = parse_plan(["dir-pack", "b.json", "sigs", "t", "out-dir"])
  assert_true(pack_dir.mode is WriteDir("out-dir"))
  assert_true(!pack_dir.archive)
  assert_true(!pack_dir.gzip)
  assert_true(!pack_dir.progress)
  assert_eq(pack_dir.excludes, [])

  let pack_arch = parse_plan([
    "dir-pack", "b.json", "sigs", "t", "out.mbundle", "--archive",
  ])
  assert_true(pack_arch.mode is WriteFile("out.mbundle"))
  assert_true(pack_arch.archive)
  assert_true(!pack_arch.gzip)

  let pack_gz_a = parse_plan([
    "dir-pack", "--archive", "--gzip", "b.json", "sigs", "t", "out.mbundle.gz",
  ])
  assert_true(pack_gz_a.mode is WriteFile("out.mbundle.gz"))
  assert_true(pack_gz_a.archive && pack_gz_a.gzip)

  let pack_gz_b = parse_plan([
    "dir-pack", "--gzip", "--archive", "b.json", "sigs", "t", "out.mbundle.gz",
  ])
  assert_true(pack_gz_b.mode is WriteFile("out.mbundle.gz"))
  assert_true(pack_gz_b.archive && pack_gz_b.gzip)

  let apply_arch = parse_plan([
    "dir-apply", "basis", "in.mbundle.gz", "out-dir", "--archive", "--gzip", "--progress",
  ])
  assert_true(apply_arch.mode is WriteDir("out-dir"))
  assert_true(apply_arch.archive && apply_arch.gzip && apply_arch.progress)

  let verify_plan = parse_plan([
    "dir-verify", "--json", "--exclude", ".git", "--exclude", "*.log", "--progress",
    "--max-entries", "50", "--", "--dir", "--snap",
  ])
  assert_eq(verify_plan.operation, "dir-verify")
  assert_eq(verify_plan.inputs, ["--dir", "--snap"])
  assert_true(verify_plan.mode is Inspect(true))
  assert_true(verify_plan.progress)
  assert_eq(verify_plan.excludes, [".git", "*.log"])
  assert_eq(verify_plan.dir_limits.max_entries, 50L)

  // Exactly 64 --exclude patterns are permitted
  let args64 : Array[String] = ["dir-snapshot", "src", "out.json"]
  for i in 0..<64 {
    args64.push("--exclude")
    args64.push("pat\{i}")
  }
  let p64 = parse_plan(args64)
  assert_eq(p64.excludes.length(), 64)

  // 65th --exclude pattern is rejected with Usage
  let args65 = args64.copy()
  args65.push("--exclude")
  args65.push("pat64")
  let rejected65 = try {
    let _ = parse_plan(args65)
    false
  } catch {
    Usage(_) => true
    _ => false
  }
  assert_true(rejected65)

  // --progress allowed on all standard commands
  for
    args in [
      ["signature", "old", "sig", "--progress"],
      ["delta", "sig", "new", "d", "--progress"],
      ["patch", "old", "d", "out", "--progress"],
      ["compress", "in", "out", "--progress"],
      ["decompress", "in", "out", "--progress"],
      ["inspect-signature", "sig", "--progress"],
      ["dir-snapshot", "d", "s", "--progress"],
      ["dir-plan", "a", "b", "--progress"],
      ["dir-verify", "d", "s", "--progress"],
      ["dir-signatures", "d", "s", "out", "--progress"],
    ] {
    assert_true(parse_plan(args).progress)
  }

  // --gzip without --archive must fail with exact message
  for
    gzip_only in [
      ["dir-pack", "b.json", "sigs", "t", "out", "--gzip"],
      ["dir-apply", "basis", "b", "out", "--gzip"],
    ] {
    let msg = try {
      let _ = parse_plan(gzip_only)
      ""
    } catch {
      Usage(m) => m
      _ => ""
    }
    assert_eq(msg, "--gzip requires --archive")
  }

  // Rejections for invalid flag combinations
  for
    bad in [
      ["dir-pack", "b", "s", "t", "o", "--archive", "--archive"],
      ["dir-pack", "b", "s", "t", "o", "--archive", "--gzip", "--gzip"],
      ["dir-apply", "b", "bd", "o", "--archive", "--archive"],
      ["dir-snapshot", "d", "o", "--archive"],
      ["dir-signatures", "d", "s", "o", "--archive"],
      ["dir-verify", "d", "s", "--archive"],
      ["compress", "a", "b", "--archive"],
      ["compress", "a", "b", "--gzip"],
      ["dir-apply", "b", "bd", "o", "--exclude", ".git"],
      ["dir-signatures", "d", "s", "o", "--exclude", ".git"],
      ["dir-plan", "a", "b", "--exclude", ".git"],
      ["signature", "old", "sig", "--exclude", ".git"],
      ["dir-snapshot", "d", "o", "--exclude"],
      ["dir-snapshot", "d", "o", "--exclude", ""],
      ["signature", "old", "sig", "--progress", "--progress"],
      ["dir-verify", "d"],
      ["dir-verify", "d", "s", "extra"],
      ["dir-verify", "d", "s", "--streaming"],
      ["dir-verify", "d", "s", "--max-old-bytes", "10"],
      ["dir-verify", "d", "s", "--json", "--json"],
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
async test "cli v050 dir-pack and dir-apply archive and gzip roundtrip plus atomic tamper and trailing rejections" {
  cli_test_scope(dir => {
    let basis = dir + "/basis"
    let target = dir + "/target"
    @fs.mkdir(basis + "/nested", recursive=true)
    @fs.mkdir(target + "/nested", recursive=true)
    @fs.mkdir(target + "/.git", recursive=true)

    let large_old = Bytes::makei(90000, i => {
      ((i * 37 + 5 + i / 512 * 11) % 256).to_byte()
    })
    let large_new = large_old[0:42000].to_owned() +
      b"V050-ARCHIVE-DELTA-EDIT" +
      large_old[42023:].to_owned()
    @fs.write_binary(
      basis + "/keep.bin",
      b"same-content",
      create_mode=CreateNew,
    )
    @fs.write_binary(
      basis + "/nested/large.bin",
      large_old,
      create_mode=CreateNew,
    )
    @fs.write_binary(basis + "/small.bin", b"v1", create_mode=CreateNew)
    @fs.write_binary(basis + "/drop.bin", b"gone", create_mode=CreateNew)

    @fs.write_binary(
      target + "/keep.bin",
      b"same-content",
      create_mode=CreateNew,
    )
    @fs.write_binary(
      target + "/nested/large.bin",
      large_new,
      create_mode=CreateNew,
    )
    @fs.write_binary(target + "/small.bin", b"v2-short", create_mode=CreateNew)
    @fs.write_binary(target + "/added.bin", b"new-bytes", create_mode=CreateNew)
    @fs.write_binary(target + "/empty.bin", b"", create_mode=CreateNew)
    // Excluded target entries
    @fs.write_binary(
      target + "/.git/HEAD",
      b"ref: refs/heads/main\n",
      create_mode=CreateNew,
    )
    @fs.write_binary(
      target + "/nested/debug.log",
      b"ignore-this-log",
      create_mode=CreateNew,
    )

    let basis_snap = dir + "/basis.snap.json"
    let target_snap = dir + "/target.snap.json"
    let sig_dir = dir + "/sigs"
    let arch_plain = dir + "/bundle.mbundle"
    let arch_gz = dir + "/bundle.mbundle.gz"
    let out_plain = dir + "/out-plain"
    let out_gz = dir + "/out-gz"

    execute(parse_plan(["dir-snapshot", basis, basis_snap]))
    execute(
      parse_plan([
        "dir-snapshot", target, target_snap, "--exclude", ".git", "--exclude", "*.log",
      ]),
    )
    execute(
      parse_plan([
        "dir-signatures", basis, basis_snap, sig_dir, "--block-size", "auto", "--streaming",
      ]),
    )
    execute(
      parse_plan([
        "dir-pack", basis_snap, sig_dir, target, arch_plain, "--archive", "--exclude",
        ".git", "--exclude", "*.log", "--streaming",
      ]),
    )
    execute(
      parse_plan([
        "dir-pack", basis_snap, sig_dir, target, arch_gz, "--archive", "--gzip",
        "--exclude", ".git", "--exclude", "*.log", "--streaming",
      ]),
    )

    let dl = @lib.DirLimits::default()
    let plain_bytes = bounded_read(arch_plain, 10000000L)
    let gz_bytes = bounded_read(arch_gz, 10000000L)
    assert_eq(plain_bytes[0:8].to_owned(), @lib.bundle_archive_magic())
    assert_eq(gz_bytes[0], b'\x1f')
    assert_eq(gz_bytes[1], b'\x8b')
    assert_true(gz_bytes.length() < plain_bytes.length())

    // No-overwrite refusal on existing archive file
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-pack", basis_snap, sig_dir, target, arch_plain, "--archive",
          ]),
        )
      },
      "already exists",
    )

    // Apply plain archive and gzip archive
    execute(
      parse_plan([
        "dir-apply", basis, arch_plain, out_plain, "--archive", "--streaming",
      ]),
    )
    execute(
      parse_plan([
        "dir-apply", basis, arch_gz, out_gz, "--archive", "--gzip", "--streaming",
      ]),
    )

    let out_plain_snap = dir + "/out-plain.snap.json"
    let out_gz_snap = dir + "/out-gz.snap.json"
    execute(parse_plan(["dir-snapshot", out_plain, out_plain_snap]))
    execute(parse_plan(["dir-snapshot", out_gz, out_gz_snap]))
    assert_eq(
      bounded_read(out_plain_snap, dl.max_snapshot_bytes),
      bounded_read(target_snap, dl.max_snapshot_bytes),
    )
    assert_eq(
      bounded_read(out_gz_snap, dl.max_snapshot_bytes),
      bounded_read(target_snap, dl.max_snapshot_bytes),
    )
    // Restored OUT_DIR must NEVER contain payloads/ or bundle.json or excluded entries
    assert_true(!entry_exists(out_plain + "/payloads"))
    assert_true(!entry_exists(out_plain + "/bundle.json"))
    assert_true(!entry_exists(out_plain + "/.git"))
    assert_true(!entry_exists(out_plain + "/nested/debug.log"))
    assert_true(!entry_exists(out_gz + "/payloads"))
    assert_true(!entry_exists(out_gz + "/bundle.json"))
    // BASIS_DIR is never mutated
    assert_true(entry_exists(basis + "/drop.bin"))

    // Refuses existing OUT_DIR in archive mode
    expect_file_failure(
      () => {
        execute(
          parse_plan(["dir-apply", basis, arch_plain, out_plain, "--archive"]),
        )
      },
      "already exists",
    )

    // Zero-payload (all unchanged) archive roundtrip (plain & gzip)
    let arch_noop = dir + "/noop.mbundle"
    let arch_noop_gz = dir + "/noop.mbundle.gz"
    let out_noop = dir + "/out-noop"
    let out_noop_gz = dir + "/out-noop-gz"
    execute(
      parse_plan([
        "dir-pack", basis_snap, sig_dir, basis, arch_noop, "--archive",
      ]),
    )
    execute(
      parse_plan([
        "dir-pack", basis_snap, sig_dir, basis, arch_noop_gz, "--archive", "--gzip",
      ]),
    )
    execute(parse_plan(["dir-apply", basis, arch_noop, out_noop, "--archive"]))
    execute(
      parse_plan([
        "dir-apply", basis, arch_noop_gz, out_noop_gz, "--archive", "--gzip",
      ]),
    )
    let noop_snap = dir + "/noop.snap.json"
    execute(parse_plan(["dir-snapshot", out_noop_gz, noop_snap]))
    assert_eq(
      bounded_read(noop_snap, dl.max_snapshot_bytes),
      bounded_read(basis_snap, dl.max_snapshot_bytes),
    )

    // Tampered payload byte in plain archive -> atomic failure, zero OUT_DIR, zero temps
    let last_i = plain_bytes.length() - 1
    let tampered = plain_bytes[0:last_i].to_owned() +
      Bytes::from_array([(plain_bytes[last_i].to_int() ^ 0xff).to_byte()])
    let tampered_path = dir + "/tampered.mbundle"
    @fs.write_binary(tampered_path, tampered[:], create_mode=CreateNew)
    let bad_tamper_out = dir + "/bad-tamper"
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-apply", basis, tampered_path, bad_tamper_out, "--archive", "--streaming",
          ]),
        )
      },
      "BindingMismatch",
    )
    assert_true(!entry_exists(bad_tamper_out))

    // Trailing byte on plain archive -> Core:TrailingData, zero OUT_DIR
    let trailing_plain = dir + "/trailing.mbundle"
    @fs.write_binary(
      trailing_plain,
      (plain_bytes + b"X")[:],
      create_mode=CreateNew,
    )
    let bad_trail_out = dir + "/bad-trail"
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-apply", basis, trailing_plain, bad_trail_out, "--archive",
          ]),
        )
      },
      "TrailingData",
    )
    assert_true(!entry_exists(bad_trail_out))

    // Truncated plain archive -> Core:TruncatedInput, zero OUT_DIR
    let trunc_plain = dir + "/trunc.mbundle"
    @fs.write_binary(
      trunc_plain,
      plain_bytes[0:plain_bytes.length() - 2],
      create_mode=CreateNew,
    )
    let bad_trunc_out = dir + "/bad-trunc"
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-apply", basis, trunc_plain, bad_trunc_out, "--archive",
          ]),
        )
      },
      "TruncatedInput",
    )
    assert_true(!entry_exists(bad_trunc_out))

    // Trailing byte on gzip archive -> TrailingData, zero OUT_DIR
    let trailing_gz = dir + "/trailing.mbundle.gz"
    @fs.write_binary(trailing_gz, (gz_bytes + b"X")[:], create_mode=CreateNew)
    let bad_gz_trail = dir + "/bad-gz-trail"
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-apply", basis, trailing_gz, bad_gz_trail, "--archive", "--gzip",
          ]),
        )
      },
      "TrailingData",
    )
    assert_true(!entry_exists(bad_gz_trail))

    // Gzip zip-bomb (compressed zeros) -> rejected immediately before expanding
    let bomb_gz = dir + "/bomb.mbundle.gz"
    let bomb_data = @compress.compress_gzip(
      Bytes::make(262144, b'\x00')[:],
      262144L,
      262144L,
    )
    @fs.write_binary(bomb_gz, bomb_data[:], create_mode=CreateNew)
    let bad_bomb_out = dir + "/bad-bomb"
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-apply", basis, bomb_gz, bad_bomb_out, "--archive", "--gzip",
          ]),
        )
      },
      "InvalidSchema",
    )
    assert_true(!entry_exists(bad_bomb_out))

    // Wrong-mode archive rejections (gzip without --gzip, plain with --gzip, dir with --archive)
    let bad_wrong1 = dir + "/bad-wrong1"
    expect_file_failure(
      () => {
        execute(
          parse_plan(["dir-apply", basis, arch_gz, bad_wrong1, "--archive"]),
        )
      },
      "InvalidSchema",
    )
    assert_true(!entry_exists(bad_wrong1))

    let bad_wrong2 = dir + "/bad-wrong2"
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-apply", basis, arch_plain, bad_wrong2, "--archive", "--gzip",
          ]),
        )
      },
      "InvalidDelta",
    )
    assert_true(!entry_exists(bad_wrong2))

    let bad_wrong3 = dir + "/bad-wrong3"
    expect_file_failure(
      () => {
        execute(
          parse_plan(["dir-apply", basis, basis, bad_wrong3, "--archive"]),
        )
      },
      "unsupported input kind",
    )
    assert_true(!entry_exists(bad_wrong3))

    // Buffered (non-streaming) archive pack/apply parity
    let arch_buf = dir + "/buf.mbundle.gz"
    let out_buf = dir + "/out-buf"
    execute(
      parse_plan([
        "dir-pack", basis_snap, sig_dir, target, arch_buf, "--archive", "--gzip",
        "--exclude", ".git", "--exclude", "*.log",
      ]),
    )
    execute(
      parse_plan(["dir-apply", basis, arch_buf, out_buf, "--archive", "--gzip"]),
    )
    let out_buf_snap = dir + "/out-buf.snap.json"
    execute(parse_plan(["dir-snapshot", out_buf, out_buf_snap]))
    assert_eq(
      bounded_read(out_buf_snap, dl.max_snapshot_bytes),
      bounded_read(target_snap, dl.max_snapshot_bytes),
    )

    // Invalid exclude pattern rejected by dir-pack before staging
    expect_file_failure(
      () => {
        execute(
          parse_plan([
            "dir-pack",
            basis_snap,
            sig_dir,
            target,
            dir + "/bad-ex.mbundle",
            "--archive",
            "--exclude",
            "../evil",
          ]),
        )
      },
      "InvalidOptions:exclude",
    )
    assert_true(!entry_exists(dir + "/bad-ex.mbundle"))

    // Zero leaked .moonlibsync-* temp files or directories
    for name in @fs.readdir(dir, include_hidden=true, include_special=false) {
      assert_true(!name.has_prefix(".moonlibsync-"))
    }
  })
}

///|
async test "cli v050 dir-snapshot exclude and dir-verify matching and drift reports" {
  cli_test_scope(dir => {
    let tree = dir + "/tree"
    @fs.mkdir(tree + "/sub", recursive=true)
    @fs.mkdir(tree + "/.git/objects", recursive=true)
    @fs.mkdir(tree + "/node_modules/pkg", recursive=true)
    @fs.mkdir(tree + "/dist", recursive=true)
    @fs.write_binary(tree + "/keep.txt", b"hello-v1", create_mode=CreateNew)
    @fs.write_binary(
      tree + "/sub/data.bin",
      b"payload-1",
      create_mode=CreateNew,
    )
    @fs.write_binary(tree + "/.git/HEAD", b"ref: main\n", create_mode=CreateNew)
    @fs.write_binary(
      tree + "/node_modules/pkg/index.js",
      b"module.exports={}",
      create_mode=CreateNew,
    )
    @fs.write_binary(tree + "/app.log", b"log-line", create_mode=CreateNew)
    @fs.write_binary(tree + "/dist/out.js", b"compiled", create_mode=CreateNew)

    let snap = dir + "/tree.snap.json"
    execute(
      parse_plan([
        "dir-snapshot", tree, snap, "--exclude", ".git", "--exclude", "node_modules",
        "--exclude", "*.log", "--exclude", "dist/*",
      ]),
    )
    let dl = @lib.DirLimits::default()
    let parsed_snap = @lib.parse_dir_snapshot(
      bounded_read(snap, dl.max_snapshot_bytes),
      dl,
    )
    assert_eq(parsed_snap.entries.length(), 2)
    assert_eq(parsed_snap.entries[0].path, "keep.txt")
    assert_eq(parsed_snap.entries[1].path, "sub/data.bin")

    // Matching dir-verify (--json and human)
    let ok_json_buf = StringBuilder()
    execute_dir_verify(
      parse_plan([
        "dir-verify", tree, snap, "--json", "--exclude", ".git", "--exclude", "node_modules",
        "--exclude", "*.log", "--exclude", "dist/*",
      ]),
      true,
      writer=bytes => ok_json_buf.write_string(@utf8.decode(bytes)),
    )
    let ok_report = @lib.parse_dir_verify_report(
      @utf8.encode(ok_json_buf.to_string()),
      dl,
    )
    assert_true(ok_report.ok)
    assert_eq(ok_report.matched_count, 2L)
    assert_eq(ok_report.modified_count, 0L)
    assert_eq(ok_report.missing_count, 0L)
    assert_eq(ok_report.extra_count, 0L)
    assert_eq(ok_report.issues.length(), 0)

    let ok_human_buf = StringBuilder()
    execute_dir_verify(
      parse_plan([
        "dir-verify", tree, snap, "--exclude", ".git", "--exclude", "node_modules",
        "--exclude", "*.log", "--exclude", "dist/*",
      ]),
      false,
      writer=bytes => ok_human_buf.write_string(@utf8.decode(bytes)),
    )
    assert_true(ok_human_buf.to_string().contains("dir-verify\nok: true\n"))
    assert_true(ok_human_buf.to_string().contains("matched: 2\n"))

    // Introduce drift: modify keep.txt, delete sub/data.bin, add extra.txt
    @fs.write_binary(
      tree + "/keep.txt",
      b"hello-v2-modified",
      create_mode=TruncateExisting,
    )
    @fs.remove(tree + "/sub/data.bin")
    @fs.write_binary(tree + "/extra.txt", b"unexpected", create_mode=CreateNew)

    let drift_json_buf = StringBuilder()
    expect_file_failure(
      () => {
        execute_dir_verify(
          parse_plan([
            "dir-verify", tree, snap, "--json", "--exclude", ".git", "--exclude",
            "node_modules", "--exclude", "*.log", "--exclude", "dist/*",
          ]),
          true,
          writer=bytes => drift_json_buf.write_string(@utf8.decode(bytes)),
        )
      },
      "dir-verify mismatch",
    )
    // Report MUST be written to stdout BEFORE raising mismatch failure!
    let drift_report = @lib.parse_dir_verify_report(
      @utf8.encode(drift_json_buf.to_string()),
      dl,
    )
    assert_true(!drift_report.ok)
    assert_eq(drift_report.matched_count, 0L)
    assert_eq(drift_report.modified_count, 1L)
    assert_eq(drift_report.missing_count, 1L)
    assert_eq(drift_report.extra_count, 1L)
    assert_eq(drift_report.issues.length(), 3)

    let drift_human_buf = StringBuilder()
    expect_file_failure(
      () => {
        execute_dir_verify(
          parse_plan([
            "dir-verify", tree, snap, "--exclude", ".git", "--exclude", "node_modules",
            "--exclude", "*.log", "--exclude", "dist/*",
          ]),
          false,
          writer=bytes => drift_human_buf.write_string(@utf8.decode(bytes)),
        )
      },
      "dir-verify mismatch",
    )
    let htext = drift_human_buf.to_string()
    assert_true(htext.contains("ok: false\n"))
    assert_true(htext.contains("  extra: extra.txt\n"))
    assert_true(htext.contains("  modified: keep.txt\n"))
    assert_true(htext.contains("  missing: sub/data.bin\n"))

    // Invalid exclude pattern rejected even on empty directory
    let empty_dir = dir + "/empty"
    @fs.mkdir(empty_dir)
    let empty_snap = dir + "/empty.snap.json"
    execute(parse_plan(["dir-snapshot", empty_dir, empty_snap]))
    for bad_pat in ["../escape", "a\\b", "/leading"] {
      expect_file_failure(
        () => {
          execute(
            parse_plan([
              "dir-snapshot",
              empty_dir,
              dir + "/bad-ex.json",
              "--exclude",
              bad_pat,
            ]),
          )
        },
        "InvalidOptions:exclude",
      )
      expect_file_failure(
        () => {
          execute_dir_verify(
            parse_plan([
              "dir-verify", empty_dir, empty_snap, "--exclude", bad_pat,
            ]),
            true,
            writer=_ => (),
          )
        },
        "InvalidOptions:exclude",
      )
    }
  })
}

///|
async test "cli v050 ProgressReporter enabled disabled formatting throttling and stdout purity" {
  // Pure formatter edge cases
  let line_half = format_progress_line("delta", 524288L, 1048576L, 1000L)
  assert_eq(
    line_half, "[moonlibsync] delta 524288/1048576 B (50%) | 0.50 MiB/s | ETA 1s\n",
  )
  let line_zero = format_progress_line("signature", 0L, 0L, 0L)
  assert_eq(
    line_zero, "[moonlibsync] signature 0/0 B (100%) | 0.00 MiB/s | ETA 0s\n",
  )
  let line_unknown = format_progress_line("dir-snapshot", 1048576L, -1L, 500L)
  assert_eq(line_unknown, "[moonlibsync] dir-snapshot 1048576 B | 2.00 MiB/s\n")

  // Disabled reporter is a strict no-op
  let disabled_lines : Array[String] = []
  let off = ProgressReporter::new("patch", 1000L, false, interval_ms=0L)
  off.advance(500L, writer=b => disabled_lines.push(@utf8.decode(b)))
  off.finish(writer=b => disabled_lines.push(@utf8.decode(b)))
  assert_eq(disabled_lines.length(), 0)

  // Enabled reporter emits throttled updates and final 100% line once
  let enabled_lines : Array[String] = []
  let on = ProgressReporter::new("patch", 1000L, true, interval_ms=0L)
  on.advance(400L, writer=b => enabled_lines.push(@utf8.decode(b)))
  on.advance(600L, writer=b => enabled_lines.push(@utf8.decode(b)))
  on.finish(writer=b => enabled_lines.push(@utf8.decode(b)))
  on.finish(writer=b => enabled_lines.push(@utf8.decode(b)))
  assert_eq(enabled_lines.length(), 3)
  assert_true(enabled_lines[0].contains("[moonlibsync] patch 400/1000 B (40%)"))
  assert_true(
    enabled_lines[1].contains("[moonlibsync] patch 1000/1000 B (100%)"),
  )
  assert_true(
    enabled_lines[2].contains("[moonlibsync] patch 1000/1000 B (100%)") &&
    enabled_lines[2].contains("ETA 0s\n"),
  )

  // Throttling suppresses rapid intermediate advances when interval has not elapsed
  let throttled_lines : Array[String] = []
  let throttled = ProgressReporter::new(
    "compress",
    1000L,
    true,
    interval_ms=60000L,
  )
  throttled.advance(300L, writer=b => throttled_lines.push(@utf8.decode(b)))
  throttled.advance(700L, writer=b => throttled_lines.push(@utf8.decode(b)))
  assert_eq(throttled_lines.length(), 0)
  throttled.finish(writer=b => throttled_lines.push(@utf8.decode(b)))
  assert_eq(throttled_lines.length(), 1)
  assert_true(
    throttled_lines[0].contains("[moonlibsync] compress 1000/1000 B (100%)"),
  )

  // Unknown-total reporter transitions to done/done (100%) on finish
  let scan_lines : Array[String] = []
  let scan = ProgressReporter::new("dir-verify", -1L, true, interval_ms=0L)
  scan.advance(256L, writer=b => scan_lines.push(@utf8.decode(b)))
  scan.finish(writer=b => scan_lines.push(@utf8.decode(b)))
  assert_eq(scan_lines.length(), 2)
  assert_true(scan_lines[0].contains("[moonlibsync] dir-verify 256 B"))
  assert_true(
    scan_lines[1].contains("[moonlibsync] dir-verify 256/256 B (100%)"),
  )

  // Stdout purity: dir-verify --json --progress writes only valid JSON to stdout
  cli_test_scope(dir => {
    let d = dir + "/d"
    @fs.mkdir(d)
    @fs.write_binary(d + "/f.bin", b"abc", create_mode=CreateNew)
    let snap = dir + "/s.json"
    execute(parse_plan(["dir-snapshot", d, snap]))
    let stdout_buf = StringBuilder()
    execute_dir_verify(
      parse_plan(["dir-verify", d, snap, "--json", "--progress"]),
      true,
      writer=b => stdout_buf.write_string(@utf8.decode(b)),
    )
    let out = stdout_buf.to_string()
    assert_true(!out.contains("[moonlibsync]"))
    let report = @lib.parse_dir_verify_report(
      @utf8.encode(out),
      @lib.DirLimits::default(),
    )
    assert_true(report.ok && report.matched_count == 1L)
  })
}
