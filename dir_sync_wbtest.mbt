// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "whitebox dir_sync JSON depth and quote escaping boundaries" {
  let d = DirLimits::default()
  let h = Sha256Hasher::new(3L)
  h.update(b"xyz"[:])
  let dig = h.finish()
  // Quotes inside a POSIX filename must escape cleanly and roundtrip.
  let snap = create_dir_snapshot(
    [{ path: "dir/\"quoted\".txt", digest: dig, }],
    d,
  )
  let raw = encode_dir_snapshot(snap, d)
  let parsed = parse_dir_snapshot(raw, d)
  assert_eq(parsed.entries[0].path, "dir/\"quoted\".txt")

  // Excess nesting depth (>3 for snapshot, >4 for plan) fails with manifest_depth.
  let deep_snap = b"{\"schema_version\":3,\"kind\":\"moonlibsync-dir-snapshot\",\"entries\":[{\"path\":\"a\",\"extra\":[{}]}]}"
  let depth_err = try {
    let _ = parse_dir_snapshot(deep_snap, d)
    false
  } catch {
    ManifestError::ResourceLimit("manifest_depth") => true
    _ => false
  }
  assert_true(depth_err)
}
