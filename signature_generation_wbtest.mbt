// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "generated complete signatures equal all fixed rdiff fixtures and reencode" {
  let bases = reference_bases()
  let refs = reference_signatures()
  for i in 0..<bases.length() {
    let (id, basis) = bases[i]
    let (ref_id, expected) = refs[i]
    assert_eq(id, ref_id)
    let parsed = parse_signature(expected, Limits::default())
    let options = {
      block_len: parsed.block_len.to_int64(),
      strong_sum_len: parsed.strong_sum_len.to_int64(),
    }
    let actual = signature(basis, options, Limits::default())
    assert_eq(actual, expected)
    let result = parse_signature(actual, Limits::default())
    assert_eq(result.records.length(), parsed.records.length())
    for n in 0..<result.records.length() {
      assert_eq(result.records[n].weak_sum, parsed.records[n].weak_sum)
      assert_eq(result.records[n].strong_sum, parsed.records[n].strong_sum)
      assert_eq(result.records[n].block_index, n)
    }
    assert_eq(encode_signature(result, Limits::default()), actual)
  }
}

///|
test "generation options budgets error precedence and recovery" {
  let d = Limits::default()
  let o = SignatureOptions::default()
  for block in [-1L, 0L] {
    expect_sync_error(
      () => {
        let _ = signature(b"", { ..o, block_len: block, }, d)
      },
      "InvalidOptions:block_len",
    )
  }
  for strong in [-1L, 0L, 33L, 9223372036854775807L] {
    expect_sync_error(
      () => {
        let _ = signature(b"", { ..o, strong_sum_len: strong, }, d)
      },
      "InvalidOptions:strong_sum_len",
    )
  }
  expect_sync_error(
    () => {
      let _ = signature(b"", { ..o, block_len: 2147483648L, }, d)
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = signature(b"", { block_len: 0L, strong_sum_len: 0L, }, {
        ..d,
        max_old_bytes: -1L,
      })
    },
    "InvalidOptions:max_old_bytes",
  )
  let options : SignatureOptions = { block_len: 2L, strong_sum_len: 1L, }
  let basis = b"\x00\x80\xff"
  let exact = {
    ..d,
    max_old_bytes: 3L,
    max_block_bytes: 2L,
    max_signature_records: 2L,
    max_signature_bytes: 22L,
  }
  assert_eq(signature(basis, options, exact).length(), 22)
  for
    limits in [
      { ..exact, max_old_bytes: 2L, },
      { ..exact, max_block_bytes: 1L, },
      { ..exact, max_signature_records: 1L, },
      { ..exact, max_signature_bytes: 21L, },
    ] {
    expect_sync_error(
      () => {
        let _ = signature(basis, options, limits)
      },
      "LimitExceeded",
    )
    assert_eq(signature(basis, options, exact).length(), 22)
    assert_eq(basis, b"\x00\x80\xff")
  }
  assert_eq(
    signature(b"", options, {
      ..d,
      max_signature_records: 0L,
      max_signature_bytes: 12L,
    }).length(),
    12,
  )
  expect_sync_error(
    () => {
      let _ = signature(b"", options, { ..d, max_signature_bytes: 11L, })
    },
    "LimitExceeded",
  )
  expect_sync_error(
    () => {
      let _ = signature(basis, options, { ..d, max_signature_records: 0L, })
    },
    "LimitExceeded",
  )
}

///|
test "generation output arithmetic rejects extremes before allocation" {
  assert_eq(signature_size(0UL, 32UL), 12)
  assert_eq(signature_size(429496727UL, 1UL), 2147483647)
  expect_sync_error(
    () => {
      let _ = signature_size(429496728UL, 1UL)
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = signature_size(0xffffffffffffffffUL, 32UL)
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = signature_size(0x3333333333333333UL, 1UL)
    },
    "IntegerOutOfRange",
  )
}
