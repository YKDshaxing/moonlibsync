// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn expect_manifest(
  action : () -> Unit raise ManifestError,
  expected : String,
) -> Unit raise {
  let actual = try {
    action()
    "success"
  } catch {
    ManifestError::ResourceLimit(field) => "Resource:" + field
    ManifestError::InvalidField(field) => "Field:" + field
    _ => "other"
  }
  assert_eq(actual, expected)
}

///|
test "manifest SHA256 independent hashlib vectors and prehash exact boundaries" {
  assert_eq(sha256_reference_vectors().length(), 9)
  for (input, expected) in sha256_reference_vectors() {
    assert_eq(manifest_sha256(input, input.length().to_int64()), expected)
    assert_eq(manifest_sha256(input, input.length().to_int64() + 1L), expected)
    assert_eq(expected.length(), 64)
    expect_manifest(
      () => {
        let _ = manifest_sha256(input, input.length().to_int64() - 1L)
      },
      "Resource:sha256_input",
    )
  }
}

///|
test "manifest independent Python exact encodings for default nondefault and empty cases" {
  let d = Limits::default()
  for
    (old, sig, new, delta, basis_wire, update_wire) in manifest_reference_vectors() {
    let info = create_basis_info(old, sig, d)
    let update = create_update_manifest(info, sig, new, delta, d)
    assert_eq(encode_basis_info(info, d), basis_wire)
    assert_eq(encode_update_manifest(update, d), update_wire)
    let a = parse_basis_info(basis_wire, d)
    let b = parse_update_manifest(update_wire, d)
    assert_eq(a.basis.byte_length, old.length().to_int64())
    assert_eq(a.signature.byte_length, sig.length().to_int64())
    assert_eq(b.delta.byte_length, delta.length().to_int64())
    assert_eq(b.result.byte_length, new.length().to_int64())
    assert_eq(b.basis.sha256, a.basis.sha256)
    assert_eq(b.signature.sha256, a.signature.sha256)
    assert_eq(encode_basis_info(a, d), basis_wire)
    assert_eq(encode_update_manifest(b, d), update_wire)
  }
}

///|
test "manifest exact container depth and total field count using fixed core parser" {
  let d = Limits::default()
  let two = manifest_tree(b"{\"a\":{\"b\":0}}", d)
  assert_eq(manifest_field_count(two), 2)
  expect_manifest(
    () => {
      let _ = manifest_tree(b"{\"a\":{\"b\":{}}}", d)
    },
    "Resource:manifest_depth",
  )
  let text = "{" + Array::makei(16, i => "\"k\{i}\":0").join(",") + "}"
  assert_eq(manifest_field_count(manifest_tree(@utf8.encode(text), d)), 16)
  let text = "{" + Array::makei(17, i => "\"k\{i}\":0").join(",") + "}"
  expect_manifest(
    () => {
      let _ = manifest_tree(@utf8.encode(text), d)
    },
    "Resource:manifest_fields",
  )
}

///|
test "manifest decimal Int64 parsing exact before resource checks" {
  assert_eq(manifest_decimal("0"), 0L)
  assert_eq(manifest_decimal("2147483648"), 2147483648L)
  assert_eq(manifest_decimal("9223372036854775807"), 9223372036854775807L)
  expect_manifest(
    () => {
      let _ = manifest_decimal("9223372036854775808")
    },
    "Field:byte_length",
  )
}

///|
test "manifest declared resource budgets exact plus one and minimum wire lengths" {
  let d = Limits::default()
  let v = manifest_reference_vectors()[1]
  for
    (field, need) in [
      ("basis", 3L),
      ("signature", 48L),
      ("delta", 8L),
      ("result", 3L),
    ] {
    for cap in [need - 1L, need, need + 1L] {
      let limits = match field {
        "basis" => { ..d, max_old_bytes: cap, }
        "signature" => { ..d, max_signature_bytes: cap, }
        "delta" => { ..d, max_delta_bytes: cap, }
        _ => { ..d, max_output_bytes: cap, }
      }
      if cap < need {
        expect_manifest(
          () => {
            let _ = parse_update_manifest(v.5, limits)
          },
          "Resource:" + field,
        )
      } else {
        assert_eq(parse_update_manifest(v.5, limits).result.byte_length, 3L)
      }
    }
  }
  assert_eq(
    parse_update_manifest(v.5, { ..d, max_new_bytes: 0L, }).result.byte_length,
    3L,
  )
  let value = parse_update_manifest(v.5, d)
  expect_manifest(
    () => {
      let _ = encode_update_manifest(
        { ..value, signature: { ..value.signature, byte_length: 11L, }, },
        d,
      )
    },
    "Field:signature.byte_length",
  )
  expect_manifest(
    () => {
      let _ = encode_update_manifest(
        { ..value, delta: { ..value.delta, byte_length: 4L, }, },
        d,
      )
    },
    "Field:delta.byte_length",
  )
}
