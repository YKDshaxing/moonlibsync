// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn digest_of(data : Bytes) -> @moonlibsync.FileDigest raise {
  let h = @moonlibsync.Sha256Hasher::new(data.length().to_int64())
  h.update(data[:])
  h.finish()
}

///|
test "dir snapshot deterministic sorting roundtrip and plan_dir_sync" {
  let d = @moonlibsync.DirLimits::default()
  let d_a = digest_of(b"alpha")
  let d_b1 = digest_of(b"beta-v1")
  let d_b2 = digest_of(b"beta-v2-longer")
  let d_c = digest_of(b"gamma")
  let d_d = digest_of(b"delta")

  // Unsorted input becomes deterministically sorted.
  let basis = @moonlibsync.create_dir_snapshot(
    [
      { path: "z/last.bin", digest: d_c, },
      { path: "a.bin", digest: d_a, },
      { path: "b/item.bin", digest: d_b1, },
    ],
    d,
  )
  assert_eq(basis.entries.map(e => e.path), [
    "a.bin", "b/item.bin", "z/last.bin",
  ])
  let snap_bytes = @moonlibsync.encode_dir_snapshot(basis, d)
  let parsed_basis = @moonlibsync.parse_dir_snapshot(snap_bytes, d)
  assert_eq(parsed_basis.entries.length(), 3)
  assert_eq(parsed_basis.entries[1].digest.sha256, d_b1.sha256)

  let target = @moonlibsync.create_dir_snapshot(
    [
      { path: "n/new.bin", digest: d_d, },
      { path: "b/item.bin", digest: d_b2, },
      { path: "a.bin", digest: d_a, },
    ],
    d,
  )
  let plan = @moonlibsync.plan_dir_sync(basis, target, d)
  assert_eq(plan.unchanged_count, 1L)
  assert_eq(plan.add_count, 1L)
  assert_eq(plan.update_count, 1L)
  assert_eq(plan.delete_count, 1L)
  assert_eq(plan.transfer_upper_bound_bytes, d_b2.byte_length + d_d.byte_length)
  assert_eq(plan.actions.map(a => a.path), [
    "a.bin", "b/item.bin", "n/new.bin", "z/last.bin",
  ])
  assert_true(plan.actions[0].kind is Unchanged)
  assert_true(plan.actions[1].kind is UpdateCandidate)
  assert_true(plan.actions[2].kind is AddFull)
  assert_true(plan.actions[3].kind is Delete)

  let encoded_plan = @moonlibsync.encode_dir_plan(plan, d)
  let parsed_plan = @moonlibsync.parse_dir_plan(encoded_plan, d)
  assert_eq(parsed_plan.unchanged_count, 1L)
  assert_eq(parsed_plan.add_count, 1L)
  assert_eq(parsed_plan.update_count, 1L)
  assert_eq(parsed_plan.delete_count, 1L)
  assert_eq(
    parsed_plan.transfer_upper_bound_bytes,
    d_b2.byte_length + d_d.byte_length,
  )
}

///|
test "dir snapshot rejects unsafe paths duplicates case collisions and cross-snapshot case collisions" {
  let d = @moonlibsync.DirLimits::default()
  let dig = digest_of(b"x")
  for
    bad_path in [
      "", "/abs", "dir/", "dir//file", ".", "..", "a/../b", "a/./b", "a\\b", "C:file",
      "bad\u0000name", "line\nbreak", "dot.", "space ", "sub/dot.",
    ] {
    let rej = try {
      let _ = @moonlibsync.create_dir_snapshot(
        [{ path: bad_path, digest: dig, }],
        d,
      )
      false
    } catch {
      @moonlibsync.ManifestError::InvalidField("path") => true
      _ => false
    }
    assert_true(rej)
  }

  // Exact duplicate and ASCII case collision inside one snapshot.
  for
    pair in [
      ("a/File.txt", "a/File.txt"),
      ("README.md", "readme.md"),
      ("Sub/A.bin", "sub/a.bin"),
    ] {
    let col = try {
      let _ = @moonlibsync.create_dir_snapshot(
        [{ path: pair.0, digest: dig, }, { path: pair.1, digest: dig, }],
        d,
      )
      false
    } catch {
      @moonlibsync.ManifestError::InvalidField("path_collision") => true
      _ => false
    }
    assert_true(col)
  }

  // Cross-snapshot case collision.
  let s1 = @moonlibsync.create_dir_snapshot(
    [{ path: "Docs/Guide.md", digest: dig, }],
    d,
  )
  let s2 = @moonlibsync.create_dir_snapshot(
    [{ path: "docs/guide.md", digest: dig, }],
    d,
  )
  let cross = try {
    let _ = @moonlibsync.plan_dir_sync(s1, s2, d)
    false
  } catch {
    @moonlibsync.ManifestError::InvalidField("path_collision") => true
    _ => false
  }
  assert_true(cross)
}

///|
test "dir strict JSON parser and DirLimits boundaries reject malformed or oversized inputs" {
  let d = @moonlibsync.DirLimits::default()
  let dig = digest_of(b"hello")
  // Resource limits: entries, depth, path_bytes, file_bytes, snapshot_bytes.
  let over_entries = try {
    let _ = @moonlibsync.create_dir_snapshot([{ path: "a", digest: dig, }], {
      ..d,
      max_entries: 0L,
    })
    false
  } catch {
    @moonlibsync.ManifestError::ResourceLimit("dir_entries") => true
    _ => false
  }
  assert_true(over_entries)

  let over_depth = try {
    let _ = @moonlibsync.create_dir_snapshot(
      [{ path: "a/b/c", digest: dig, }],
      { ..d, max_depth: 2L, },
    )
    false
  } catch {
    @moonlibsync.ManifestError::ResourceLimit("path_depth") => true
    _ => false
  }
  assert_true(over_depth)

  let over_path = try {
    let _ = @moonlibsync.create_dir_snapshot([{ path: "abcd", digest: dig, }], {
      ..d,
      max_path_bytes: 3L,
    })
    false
  } catch {
    @moonlibsync.ManifestError::ResourceLimit("path_bytes") => true
    _ => false
  }
  assert_true(over_path)

  // Strict JSON rejections on parse_dir_snapshot / parse_dir_plan:
  // BOM, duplicate keys, unsorted entries, invalid schema, bad digest, forged summary.
  let bom = try {
    let _ = @moonlibsync.parse_dir_snapshot(
      b"\xef\xbb\xbf{\"schema_version\":3,\"kind\":\"moonlibsync-dir-snapshot\",\"entries\":[]}",
      d,
    )
    false
  } catch {
    @moonlibsync.ManifestError::InvalidJson => true
    _ => false
  }
  assert_true(bom)

  let dup = try {
    let _ = @moonlibsync.parse_dir_snapshot(
      b"{\"schema_version\":3,\"schema_version\":3,\"kind\":\"moonlibsync-dir-snapshot\",\"entries\":[]}",
      d,
    )
    false
  } catch {
    @moonlibsync.ManifestError::InvalidJson => true
    _ => false
  }
  assert_true(dup)

  let unsorted_json = b"{\"schema_version\":3,\"kind\":\"moonlibsync-dir-snapshot\",\"entries\":[{\"path\":\"b\",\"byte_length\":\"5\",\"sha256\":\"" +
    @utf8.encode(dig.sha256) +
    b"\"},{\"path\":\"a\",\"byte_length\":\"5\",\"sha256\":\"" +
    @utf8.encode(dig.sha256) +
    b"\"}]}"
  let ord = try {
    let _ = @moonlibsync.parse_dir_snapshot(unsorted_json, d)
    false
  } catch {
    @moonlibsync.ManifestError::InvalidField("path_order") => true
    _ => false
  }
  assert_true(ord)

  let forged_plan = @utf8.encode(
    "{\"schema_version\":3,\"kind\":\"moonlibsync-dir-plan\",\"summary\":{\"unchanged\":\"99\",\"add\":\"0\",\"update\":\"0\",\"delete\":\"0\",\"transfer_upper_bound_bytes\":\"0\"},\"actions\":[]}\n",
  )
  let bad_sum = try {
    let _ = @moonlibsync.parse_dir_plan(forged_plan, d)
    false
  } catch {
    @moonlibsync.ManifestError::BindingMismatch("plan_summary") => true
    _ => false
  }
  assert_true(bad_sum)

  // Invalid DirLimits config -> InvalidOptions
  let bad_lim = try {
    { ..d, max_snapshot_bytes: 63L, }.validate()
    false
  } catch {
    @moonlibsync.ManifestError::Core(
      @moonlibsync.SyncError::InvalidOptions("max_snapshot_bytes")
    ) => true
    _ => false
  }
  assert_true(bad_lim)
}

///|
test "schema 3 DirSignatureIndex and DirBundleManifest roundtrip and strict validation" {
  let dl = @moonlibsync.DirLimits::default()
  let fl = @moonlibsync.Limits::default()
  let old_a = b"unchanged-bytes"
  let old_b = Bytes::makei(4096, i => ((i * 41 + 3) % 256).to_byte())
  let new_b = old_b[0:2048].to_owned() + b"DIFF!" + old_b[2053:].to_owned()
  let sig_b = @moonlibsync.signature(
    old_b,
    { block_len: 512L, strong_sum_len: 32L, },
    fl,
  )
  let info_b = @moonlibsync.create_basis_info(old_b, sig_b, fl)
  let delta_b = @moonlibsync.delta(sig_b, new_b, fl)
  let um_b = @moonlibsync.create_update_manifest(
    info_b, sig_b, new_b, delta_b, fl,
  )

  let sha = (data : Bytes) => {
    let h = @moonlibsync.Sha256Hasher::new(fl.max_old_bytes)
    h.update(data[:])
    h.finish()
  }
  let d_old_a = sha(old_a)
  let d_add = sha(b"brand-new")
  let d_uf_old = sha(b"tiny1")
  let d_uf_new = sha(b"tiny22")
  let d_del = sha(b"deleted")

  // DirSignatureIndex unsorted -> sorted canonical encode/parse roundtrip
  let sig_idx = @moonlibsync.create_dir_signature_index(
    [
      {
        path: "sub/b.bin",
        basis: info_b.basis,
        signature_path: "sigs/000001.sig",
        signature: info_b.signature,
      },
      {
        path: "a.bin",
        basis: d_old_a,
        signature_path: "sigs/000000.sig",
        signature: info_b.signature,
      },
    ],
    dl,
    fl,
  )
  assert_eq(sig_idx.entries[0].path, "a.bin")
  assert_eq(sig_idx.entries[1].path, "sub/b.bin")
  let sig_json = @moonlibsync.encode_dir_signature_index(sig_idx, dl, fl)
  let sig_parsed = @moonlibsync.parse_dir_signature_index(sig_json, dl, fl)
  assert_eq(
    @moonlibsync.encode_dir_signature_index(sig_parsed, dl, fl),
    sig_json,
  )

  // Reject signature_path escaping sigs/ or case-folding collision
  let bad_sig_prefix = try {
    let _ = @moonlibsync.create_dir_signature_index(
      [
        {
          path: "a.bin",
          basis: d_old_a,
          signature_path: "other/0.sig",
          signature: info_b.signature,
        },
      ],
      dl,
      fl,
    )
    false
  } catch {
    @moonlibsync.ManifestError::InvalidField("signature_path") => true
    _ => false
  }
  assert_true(bad_sig_prefix)

  let bad_sig_coll = try {
    let _ = @moonlibsync.create_dir_signature_index(
      [
        {
          path: "a.bin",
          basis: d_old_a,
          signature_path: "sigs/A.sig",
          signature: info_b.signature,
        },
        {
          path: "b.bin",
          basis: d_old_a,
          signature_path: "sigs/a.sig",
          signature: info_b.signature,
        },
      ],
      dl,
      fl,
    )
    false
  } catch {
    @moonlibsync.ManifestError::InvalidField("signature_path_collision") => true
    _ => false
  }
  assert_true(bad_sig_coll)

  // DirBundleManifest all 5 action kinds + exact payload byte sum
  let bundle = @moonlibsync.create_dir_bundle_manifest(
    [
      { path: "z/del.bin", action: Delete(d_del), },
      { path: "sub/b.bin", action: UpdateDelta("payloads/000001.delta", um_b), },
      { path: "a.bin", action: Unchanged(d_old_a), },
      {
        path: "c.bin",
        action: UpdateFull("payloads/000002.full", d_uf_old, d_uf_new),
      },
      { path: "add.bin", action: AddFull("payloads/000000.full", d_add), },
    ],
    dl,
    fl,
  )
  assert_eq(bundle.unchanged_count, 1L)
  assert_eq(bundle.add_full_count, 1L)
  assert_eq(bundle.update_delta_count, 1L)
  assert_eq(bundle.update_full_count, 1L)
  assert_eq(bundle.delete_count, 1L)
  assert_eq(
    bundle.total_payload_bytes,
    d_add.byte_length + um_b.delta.byte_length + d_uf_new.byte_length,
  )
  assert_eq(bundle.entries[0].path, "a.bin")
  assert_eq(bundle.entries[4].path, "z/del.bin")

  let bundle_json = @moonlibsync.encode_dir_bundle_manifest(bundle, dl, fl)
  let parsed = @moonlibsync.parse_dir_bundle_manifest(bundle_json, dl, fl)
  assert_eq(
    @moonlibsync.encode_dir_bundle_manifest(parsed, dl, fl),
    bundle_json,
  )

  // Reject payload_path outside payloads/, payload collision, and forged summary
  let bad_pp = try {
    let _ = @moonlibsync.create_dir_bundle_manifest(
      [{ path: "x", action: AddFull("evil.bin", d_add), }],
      dl,
      fl,
    )
    false
  } catch {
    @moonlibsync.ManifestError::InvalidField("payload_path") => true
    _ => false
  }
  assert_true(bad_pp)

  let bad_pcoll = try {
    let _ = @moonlibsync.create_dir_bundle_manifest(
      [
        { path: "x", action: AddFull("payloads/P.bin", d_add), },
        { path: "y", action: AddFull("payloads/p.bin", d_add), },
      ],
      dl,
      fl,
    )
    false
  } catch {
    @moonlibsync.ManifestError::InvalidField("payload_path_collision") => true
    _ => false
  }
  assert_true(bad_pcoll)

  let forged = @utf8.encode(
    "{\"schema_version\":3,\"kind\":\"moonlibsync-dir-bundle\",\"summary\":{\"unchanged\":\"1\",\"add_full\":\"0\",\"update_delta\":\"0\",\"update_full\":\"0\",\"delete\":\"0\",\"total_payload_bytes\":\"0\"},\"entries\":[]}\n",
  )
  let bad_sum = try {
    let _ = @moonlibsync.parse_dir_bundle_manifest(forged, dl, fl)
    false
  } catch {
    @moonlibsync.ManifestError::BindingMismatch("bundle_summary") => true
    _ => false
  }
  assert_true(bad_sum)
}

///|
test "match_dir_exclude handles segment globs path prefixes and rejects invalid patterns" {
  // Single-segment exact & wildcard matches at root and nested paths
  assert_true(@moonlibsync.match_dir_exclude(".git/config", ".git"))
  assert_true(
    @moonlibsync.match_dir_exclude("sub/node_modules/a.js", "node_modules"),
  )
  assert_true(!@moonlibsync.match_dir_exclude("src/git-helper.mbt", ".git"))
  assert_true(@moonlibsync.match_dir_exclude("logs/app.log", "*.log"))
  assert_true(@moonlibsync.match_dir_exclude("a/b/temp-1.bin", "temp-?.bin"))
  assert_true(!@moonlibsync.match_dir_exclude("a/b/temp-12.bin", "temp-?.bin"))

  // Multi-segment prefix globs
  assert_true(@moonlibsync.match_dir_exclude("dist/app.js", "dist/*"))
  assert_true(@moonlibsync.match_dir_exclude("dist/sub/app.js", "dist/*"))
  assert_true(!@moonlibsync.match_dir_exclude("src/dist/app.js", "dist/*"))
  assert_true(@moonlibsync.match_dir_exclude("docs/spec.draft", "docs/*.draft"))
  assert_true(!@moonlibsync.match_dir_exclude("docs/spec.md", "docs/*.draft"))

  // Reject invalid exclude patterns
  for bad in ["", "/abs", "trail/", "a//b", "a\\b", "../x", "a/./b", "c:d"] {
    let rejected = try {
      let _ = @moonlibsync.match_dir_exclude("a/b", bad)
      false
    } catch {
      @moonlibsync.ManifestError::Core(
        @moonlibsync.SyncError::InvalidOptions("exclude")
      ) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "verify_dir_snapshot and schema 3 DirVerifyReport roundtrip and mismatch detection" {
  let dl = @moonlibsync.DirLimits::default()
  let fl = @moonlibsync.Limits::default()
  let sha = (data : Bytes) => {
    let h = @moonlibsync.Sha256Hasher::new(fl.max_old_bytes)
    h.update(data[:])
    h.finish()
  }
  let exp = @moonlibsync.create_dir_snapshot(
    [
      { path: "keep.txt", digest: sha(b"same"), },
      { path: "mod.txt", digest: sha(b"v1"), },
      { path: "gone.txt", digest: sha(b"missing"), },
    ],
    dl,
  )
  // Exact match -> ok=true, zero issues
  let ok_rep = @moonlibsync.verify_dir_snapshot(exp, exp, dl)
  assert_true(ok_rep.ok)
  assert_eq(ok_rep.matched_count, 3L)
  assert_eq(ok_rep.issues.length(), 0)
  let ok_json = @moonlibsync.encode_dir_verify_report(ok_rep, dl)
  let ok_parsed = @moonlibsync.parse_dir_verify_report(ok_json, dl)
  assert_true(ok_parsed.ok)
  assert_eq(ok_parsed.matched_count, 3L)

  // Drift: 1 matched, 1 modified, 1 missing, 1 extra
  let act = @moonlibsync.create_dir_snapshot(
    [
      { path: "keep.txt", digest: sha(b"same"), },
      { path: "mod.txt", digest: sha(b"v2-tampered"), },
      { path: "extra.txt", digest: sha(b"unexpected"), },
    ],
    dl,
  )
  let rep = @moonlibsync.verify_dir_snapshot(exp, act, dl)
  assert_true(!rep.ok)
  assert_eq(rep.matched_count, 1L)
  assert_eq(rep.modified_count, 1L)
  assert_eq(rep.missing_count, 1L)
  assert_eq(rep.extra_count, 1L)
  assert_eq(rep.issues.length(), 3)
  let rep_json = @moonlibsync.encode_dir_verify_report(rep, dl)
  let rep_parsed = @moonlibsync.parse_dir_verify_report(rep_json, dl)
  assert_eq(@moonlibsync.encode_dir_verify_report(rep_parsed, dl), rep_json)

  // Forged ok=true with non-zero issues -> BindingMismatch("verify_summary")
  let forged = @utf8.encode(
    "{\"schema_version\":3,\"kind\":\"moonlibsync-dir-verify\",\"ok\":true,\"summary\":{\"matched\":\"0\",\"modified\":\"1\",\"missing\":\"0\",\"extra\":\"0\"},\"issues\":[]}\n",
  )
  let bad = try {
    let _ = @moonlibsync.parse_dir_verify_report(forged, dl)
    false
  } catch {
    @moonlibsync.ManifestError::BindingMismatch("verify_summary") => true
    _ => false
  }
  assert_true(bad)
}

///|
test "plan_dir_sync_with_options detect_moves emits CopyFromBasis with zero transfer bytes" {
  let d = @moonlibsync.DirLimits::default()
  let d_big = digest_of(Bytes::make(1024, b'\x42'))
  let d_same = digest_of(b"unchanged-doc")
  let d_new = digest_of(b"brand-new")

  let basis = @moonlibsync.create_dir_snapshot(
    [
      { path: "a/stay.txt", digest: d_same, },
      { path: "legacy/asset.bin", digest: d_big, },
    ],
    d,
  )
  let target = @moonlibsync.create_dir_snapshot(
    [
      { path: "a/stay.txt", digest: d_same, },
      { path: "media/moved-asset.bin", digest: d_big, },
      { path: "media/copy-asset.bin", digest: d_big, },
      { path: "new.txt", digest: d_new, },
    ],
    d,
  )

  // Default plan_dir_sync stays 100% backward-compatible (detect_moves = false)
  let legacy_plan = @moonlibsync.plan_dir_sync(basis, target, d)
  assert_eq(legacy_plan.copy_from_basis_count, 0L)
  assert_eq(legacy_plan.add_count, 3L)
  assert_eq(
    legacy_plan.transfer_upper_bound_bytes,
    d_big.byte_length * 2L + d_new.byte_length,
  )

  // With detect_moves = true, both moved and copied paths become 0-byte CopyFromBasis!
  let move_plan = @moonlibsync.plan_dir_sync_with_options(
    basis,
    target,
    { detect_moves: true, },
    d,
  )
  assert_eq(move_plan.unchanged_count, 1L)
  assert_eq(move_plan.copy_from_basis_count, 2L)
  assert_eq(move_plan.add_count, 1L)
  assert_eq(move_plan.delete_count, 1L)
  assert_eq(move_plan.transfer_upper_bound_bytes, d_new.byte_length)

  // Schema 3 JSON roundtrip preserves CopyFromBasis & source_path
  let encoded = @moonlibsync.encode_dir_plan(move_plan, d)
  let parsed = @moonlibsync.parse_dir_plan(encoded, d)
  assert_eq(parsed.copy_from_basis_count, 2L)
  assert_eq(parsed.transfer_upper_bound_bytes, d_new.byte_length)
  let mut found_moved = false
  for act in parsed.actions {
    if act.path == "media/moved-asset.bin" {
      assert_true(act.kind is CopyFromBasis("legacy/asset.bin"))
      found_moved = true
    }
  }
  assert_true(found_moved)
}

///|
test "dir bundle manifest CopyFromBasis and UpdateDeltaFrom roundtrip and exclude file parser" {
  let dl = @moonlibsync.DirLimits::default()
  let lim = @moonlibsync.Limits::default()
  let old_bytes = Bytes::makei(512, i => (i & 0xff).to_byte())
  let new_bytes = old_bytes[0:256].to_owned() +
    b"MOVED-EDIT" +
    old_bytes[266:].to_owned()
  let sig = @moonlibsync.signature(
    old_bytes,
    { block_len: 64L, strong_sum_len: 16L, },
    lim,
  )
  let delta = @moonlibsync.delta(sig, new_bytes, lim)
  let info = @moonlibsync.create_basis_info(old_bytes, sig, lim)
  let um = @moonlibsync.create_update_manifest(info, sig, new_bytes, delta, lim)
  let d_move = digest_of(b"exact-moved-file")

  let bundle = @moonlibsync.create_dir_bundle_manifest(
    [
      {
        path: "new/moved.bin",
        action: @moonlibsync.DirBundleAction::CopyFromBasis(
          "old/moved.bin", d_move,
        ),
      },
      {
        path: "new/edited.bin",
        action: @moonlibsync.DirBundleAction::UpdateDeltaFrom(
          "old/edited.bin", "payloads/0.delta", um,
        ),
      },
      {
        path: "old/moved.bin",
        action: @moonlibsync.DirBundleAction::Delete(d_move),
      },
    ],
    dl,
    lim,
  )
  assert_eq(bundle.copy_from_basis_count, 1L)
  assert_eq(bundle.update_delta_count, 1L)
  assert_eq(bundle.delete_count, 1L)
  assert_eq(bundle.total_payload_bytes, um.delta.byte_length)

  let encoded = @moonlibsync.encode_dir_bundle_manifest(bundle, dl, lim)
  let parsed = @moonlibsync.parse_dir_bundle_manifest(encoded, dl, lim)
  assert_eq(parsed.copy_from_basis_count, 1L)
  assert_eq(parsed.update_delta_count, 1L)
  assert_eq(parsed.total_payload_bytes, um.delta.byte_length)

  // Archive expected payloads skips CopyFromBasis (0 bytes) and includes UpdateDeltaFrom!
  let expected_payloads = @moonlibsync.bundle_expected_payloads(parsed)
  assert_eq(expected_payloads.length(), 1)
  assert_eq(expected_payloads[0].0, "payloads/0.delta")
  let arch = @moonlibsync.encode_bundle_archive(
    parsed,
    Map([("payloads/0.delta", delta)]),
    dl,
    lim,
  )
  let decoded = @moonlibsync.parse_bundle_archive(arch, dl, lim)
  assert_eq(decoded.manifest.copy_from_basis_count, 1L)
  assert_eq(decoded.payloads["payloads/0.delta"], delta)

  // parse_dir_exclude_file parses comments, blanks, CRLF, and rejects BOM / invalid rules
  let ignore_bytes = b"# MoonLibSync ignore file\r\n\r\n  .git  \nnode_modules\r\n# temp files\n*.tmp\nbuild/*\n"
  let patterns = @moonlibsync.parse_dir_exclude_file(ignore_bytes, dl)
  assert_eq(patterns, [".git", "node_modules", "*.tmp", "build/*"])
  let bom_rej = try {
    let _ = @moonlibsync.parse_dir_exclude_file(b"\xef\xbb\xbf.git\n", dl)
    false
  } catch {
    @moonlibsync.ManifestError::InvalidField("exclude_file_bom") => true
    _ => false
  }
  assert_true(bom_rej)
}

///|
test "dir sync rejects reserved DOS names, file-vs-dir prefix and dir-case collisions, self-ref, and handles cyclic swaps" {
  let d = @moonlibsync.DirLimits::default()
  let fl = @moonlibsync.Limits::default()
  let d1 = digest_of(b"content-one")
  let d2 = digest_of(b"content-two")

  // 1. Windows DOS reserved device names rejected in any segment
  for
    bad in [
      "NUL", "nul.txt", "sub/CON", "PRN", "AUX", "COM1", "com9.bin", "LPT1", "dir/lpt9.dat",
    ] {
    let rej = try {
      let _ = @moonlibsync.create_dir_snapshot([{ path: bad, digest: d1, }], d)
      false
    } catch {
      @moonlibsync.ManifestError::InvalidField("path") => true
      _ => false
    }
    assert_true(rej)
  }

  // 2. File-vs-directory ancestor prefix & intermediate dir case collisions rejected
  for
    pair in [
      ("foo", "foo/bar.txt"),
      ("Foo", "foo/bar.txt"),
      ("a/B", "a/b/c/d.txt"),
      ("DIR/b.txt", "dir/a.txt"),
    ] {
    let rej = try {
      let _ = @moonlibsync.create_dir_snapshot(
        [{ path: pair.0, digest: d1, }, { path: pair.1, digest: d2, }],
        d,
      )
      false
    } catch {
      @moonlibsync.ManifestError::InvalidField("path_collision") => true
      _ => false
    }
    assert_true(rej)
  }

  // 3. Non-prefix siblings are allowed
  let ok_sibs = @moonlibsync.create_dir_snapshot(
    [
      { path: "foo", digest: d1, },
      { path: "foo.txt", digest: d2, },
      { path: "foo-bar/baz", digest: d1, },
    ],
    d,
  )
  assert_eq(ok_sibs.entries.length(), 3)

  // 4. Legal file <-> directory replacement across snapshots is allowed, while cross-snapshot dir-case collision is rejected
  let snap_file = @moonlibsync.create_dir_snapshot(
    [{ path: "foo", digest: d1, }],
    d,
  )
  let snap_dir = @moonlibsync.create_dir_snapshot(
    [{ path: "foo/bar.txt", digest: d2, }],
    d,
  )
  let repl_plan = @moonlibsync.plan_dir_sync(snap_file, snap_dir, d)
  let _ = @moonlibsync.parse_dir_plan(
    @moonlibsync.encode_dir_plan(repl_plan, d),
    d,
  )

  let snap_upper = @moonlibsync.create_dir_snapshot(
    [{ path: "DIR/a.txt", digest: d1, }],
    d,
  )
  let snap_lower = @moonlibsync.create_dir_snapshot(
    [{ path: "dir/b.txt", digest: d2, }],
    d,
  )
  let cross_rej = try {
    let _ = @moonlibsync.plan_dir_sync(snap_upper, snap_lower, d)
    false
  } catch {
    @moonlibsync.ManifestError::InvalidField("path_collision") => true
    _ => false
  }
  assert_true(cross_rej)

  // 5. Cyclic swap a.bin <-> b.bin under detect_moves emits 2x CopyFromBasis (0 transfer bytes) & roundtrips
  let swap_v1 = @moonlibsync.create_dir_snapshot(
    [{ path: "a.bin", digest: d1, }, { path: "b.bin", digest: d2, }],
    d,
  )
  let swap_v2 = @moonlibsync.create_dir_snapshot(
    [{ path: "a.bin", digest: d2, }, { path: "b.bin", digest: d1, }],
    d,
  )
  let swap_plan = @moonlibsync.plan_dir_sync_with_options(
    swap_v1,
    swap_v2,
    { detect_moves: true, },
    d,
  )
  assert_eq(swap_plan.copy_from_basis_count, 2L)
  assert_eq(swap_plan.transfer_upper_bound_bytes, 0L)
  let parsed_swap = @moonlibsync.parse_dir_plan(
    @moonlibsync.encode_dir_plan(swap_plan, d),
    d,
  )
  assert_eq(parsed_swap.copy_from_basis_count, 2L)
  assert_true(parsed_swap.actions[0].kind is CopyFromBasis("b.bin"))
  assert_true(parsed_swap.actions[1].kind is CopyFromBasis("a.bin"))

  // 6. Case-folded self-reference in CopyFromBasis rejected
  let self_ref_rej = try {
    let _ = @moonlibsync.create_dir_bundle_manifest(
      [{ path: "foo.txt", action: CopyFromBasis("FOO.TXT", d1), }],
      d,
      fl,
    )
    false
  } catch {
    @moonlibsync.ManifestError::InvalidField("source_path") => true
    _ => false
  }
  assert_true(self_ref_rej)

  // 7. DirVerifyReport aggregate count > max_entries rejected
  let tight : @moonlibsync.DirLimits = { ..d, max_entries: 2L, }
  let agg_rej = try {
    let _ = @moonlibsync.encode_dir_verify_report(
      {
        ok: false,
        matched_count: 2L,
        modified_count: 0L,
        missing_count: 1L,
        extra_count: 0L,
        issues: [
          { path: "z.bin", kind: Missing, expected: Some(d1), actual: None, },
        ],
      },
      tight,
    )
    false
  } catch {
    @moonlibsync.ManifestError::ResourceLimit("dir_entries") => true
    _ => false
  }
  assert_true(agg_rej)
}
