// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "transfer whitebox Delta applicable budgets at need minus equal plus one" {
  let d = Limits::default()
  let old = b"abcdefghijklmnop"
  let sig = signature(old, { block_len: 8L, strong_sum_len: 32L, }, d)
  let info = create_basis_info(old, sig, d)
  let payload = delta(sig, old, d)
  let m = create_transfer_manifest(
    info,
    sig,
    old,
    payload,
    UpdateOptions::default(),
    d,
  )
  assert_eq(payload.length(), 8)
  for offset in [-1L, 0L, 1L] {
    for
      (limits, field) in [
        ({ ..d, max_old_bytes: 16L + offset, }, "basis"),
        ({ ..d, max_signature_bytes: 84L + offset, }, "signature"),
        ({ ..d, max_delta_bytes: 8L + offset, }, "delta"),
        ({ ..d, max_output_bytes: 16L + offset, }, "result"),
      ] {
      if offset < 0L {
        let tag = try {
          let _ = apply_update(Some(old), payload, m, limits)
          "success"
        } catch {
          ManifestError::ResourceLimit(name) => name
          _ => "other"
        }
        assert_eq(tag, field)
      } else {
        assert_eq(apply_update(Some(old), payload, m, limits), old)
      }
    }
  }
}

///|
test "transfer whitebox authenticated malformed Delta still uses strict parser and COPY basis" {
  let d = Limits::default()
  let sig = signature(b"abc", SignatureOptions::default(), d)
  let info = create_basis_info(b"abc", sig, d)
  for
    (payload, expected) in [
      (b"\x72\x73\x02\x36\xff", "opcode"),
      (b"\x72\x73\x02\x36\x00\x00", "trailing"),
      (b"\x72\x73\x02\x36\x45\x03\x03\x00", "copy"),
    ] {
    let m = TransferManifest::Delta({
      basis: info.basis,
      signature: info.signature,
      delta: {
        byte_length: payload.length().to_int64(),
        sha256: manifest_sha256(payload, d.max_delta_bytes),
      },
      result: info.basis,
    })
    let tag = try {
      let _ = apply_update(Some(b"abc"), payload, m, d)
      "success"
    } catch {
      ManifestError::Core(InvalidOpcode) => "opcode"
      ManifestError::Core(TrailingData) => "trailing"
      ManifestError::Core(CopyOutOfBounds) => "copy"
      _ => "other"
    }
    assert_eq(tag, expected)
  }
}

///|
test "transfer whitebox schema2 independent encodings and old parser rejection" {
  let d = Limits::default()
  let legacy = parse_update_manifest(@utf8.encode(transfer_legacy_expected), d)
  let m = TransferManifest::Delta(legacy)
  assert_eq(
    encode_transfer_manifest(m, d),
    @utf8.encode(transfer_delta_expected),
  )
  let decoded = parse_transfer_manifest(
    @utf8.encode(transfer_delta_expected),
    d,
  )
  assert_eq(
    encode_transfer_manifest(decoded, d),
    @utf8.encode(transfer_delta_expected),
  )
  let tag = try {
    let _ = parse_update_manifest(@utf8.encode(transfer_delta_expected), d)
    "success"
  } catch {
    ManifestError::InvalidSchema => "schema"
    _ => "other"
  }
  assert_eq(tag, "schema")
  let tag = try {
    let _ = parse_transfer_manifest(@utf8.encode(transfer_legacy_expected), d)
    "success"
  } catch {
    ManifestError::InvalidSchema => "schema"
    _ => "other"
  }
  assert_eq(tag, "schema")
}

///|
test "transfer whitebox parser exact byte cap and public Full revalidation" {
  let d = Limits::default()
  let good = transfer_full_expected
  let padded = good + " ".repeat(65536 - good.length())
  let parsed = parse_transfer_manifest(@utf8.encode(padded), d)
  assert_eq(apply_update(None, b"abc", parsed, d), b"abc")
  let tag = try {
    let _ = parse_transfer_manifest(@utf8.encode(padded + " "), d)
    "success"
  } catch {
    ManifestError::ResourceLimit(name) => name
    _ => "other"
  }
  assert_eq(tag, "manifest_bytes")
}

///|
let transfer_legacy_expected : String = "{\"schema_version\":1,\"kind\":\"librsync-delta\",\"basis\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"},\"signature\":{\"byte_length\":\"48\",\"sha256\":\"59a030db700124f21acc20a3563329bb1d90b64c8e8de59f19cbc0ead26c9573\"},\"delta\":{\"byte_length\":\"8\",\"sha256\":\"22120222ab5b762c88d44e81d72884fcd4ff5f2d82b02a6ae5edb0f56b3b1b53\"},\"result\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"}}\n"

///|
let transfer_delta_expected : String = "{\"schema_version\":2,\"kind\":\"librsync-delta\",\"basis\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"},\"signature\":{\"byte_length\":\"48\",\"sha256\":\"59a030db700124f21acc20a3563329bb1d90b64c8e8de59f19cbc0ead26c9573\"},\"payload\":{\"byte_length\":\"8\",\"sha256\":\"22120222ab5b762c88d44e81d72884fcd4ff5f2d82b02a6ae5edb0f56b3b1b53\"},\"result\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"}}\n"

///|
let transfer_full_expected : String = "{\"schema_version\":2,\"kind\":\"full-file\",\"payload\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"},\"result\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"}}\n"
