// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "verified independent manifests and all sixteen upstream reference pairs" {
  let d = Limits::default()
  for v in manifest_reference_vectors() {
    assert_eq(verified_patch(v.0, v.3, parse_update_manifest(v.5, d), d), v.2)
  }
  let old = reference_bases()
  let sig = reference_signatures()
  let new = reference_news()
  let delta = reference_deltas()
  assert_eq(old.length(), 16)
  for i in 0..<old.length() {
    let info = create_basis_info(old[i].1, sig[i].1, d)
    let manifest = create_update_manifest(
      info,
      sig[i].1,
      new[i].1,
      delta[i].1,
      d,
    )
    assert_eq(verified_patch(old[i].1, delta[i].1, manifest, d), new[i].1)
  }
}

///|
test "verified authenticated malformed deltas still undergo complete parse and COPY preflight" {
  let d = Limits::default()
  let v = manifest_reference_vectors()[1]
  let m = parse_update_manifest(v.5, d)
  for
    (bytes, expected) in [
      (b"\x72\x73\x02\x36\x55\x00", "InvalidOpcode"),
      (b"\x72\x73\x02\x36\x45\xff\x01", "TruncatedInput"),
      (b"\x72\x73\x02\x36\x00\xff", "TrailingData"),
      (b"\x72\x73\x02\x36\x45\x02\x03\x00", "CopyOutOfBounds"),
    ] {
    let bound = {
      ..m,
      delta: {
        byte_length: bytes.length().to_int64(),
        sha256: manifest_sha256(bytes, d.max_delta_bytes),
      },
    }
    let actual = try {
      let _ = verified_patch(b"abc", bytes, bound, d)
      "success"
    } catch {
      ManifestError::Core(InvalidOpcode) => "InvalidOpcode"
      ManifestError::Core(TruncatedInput) => "TruncatedInput"
      ManifestError::Core(TrailingData) => "TrailingData"
      ManifestError::Core(CopyOutOfBounds) => "CopyOutOfBounds"
      _ => "other"
    }
    assert_eq(actual, expected)
  }
}
