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
