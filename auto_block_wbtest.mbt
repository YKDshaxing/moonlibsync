// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "auto whitebox last power exceeds Int32 before legal nonpower cap" {
  let d = {
    ..Limits::default(),
    max_old_bytes: 2147483647L,
    max_block_bytes: 2147483647L,
    max_signature_records: 1L,
    max_signature_bytes: 48L,
  }
  for
    (n, expected) in [
      (1073741824L, 1073741824L),
      (1073741825L, 2147483647L),
      (2147483647L, 2147483647L),
    ] {
    let block = recommend_block_len(n, 32L, d)
    assert_eq(block, expected)
    let plan = signature_plan(
      n.reinterpret_as_uint64(),
      { block_len: block, strong_sum_len: 32L, },
      d,
    )
    assert_eq(plan.2, 1)
    assert_eq(plan.3, 48)
  }
  expect_sync_error(
    () => {
      let _ = recommend_block_len(2147483647L, 32L, {
        ..d,
        max_block_bytes: 2147483646L,
      })
    },
    "LimitExceeded",
  )
}

///|
test "auto whitebox independent maximal block feasibility grid matches preflight" {
  let base = { ..Limits::default(), max_old_bytes: 2147483647L, }
  for n in [0L, 1L, 17L, 34L, 35L, 63L, 64L, 65L, 32768L, 32769L, 2147483647L] {
    for cap in [1L, 17L, 63L, 64L, 65L, 2048L, 2147483647L] {
      for records in [0L, 1L, 2L, 512L] {
        for bytes in [12L, 17L, 32L, 48L, 84L, 16777216L] {
          for strong in [1L, 16L, 32L] {
            let limits = {
              ..base,
              max_block_bytes: cap,
              max_signature_records: records,
              max_signature_bytes: bytes,
            }
            let count = n / cap + (if n % cap == 0L { 0L } else { 1L })
            // The largest legal block has the fewest records. If it cannot fit,
            // no other block can. This oracle does not reproduce policy rounding.
            let feasible = count <= records &&
              12L + count * (4L + strong) <= bytes
            let actual = try {
              let block = recommend_block_len(n, strong, limits)
              assert_true(block >= 1L && block <= cap)
              let _ = signature_plan(
                n.reinterpret_as_uint64(),
                { block_len: block, strong_sum_len: strong, },
                limits,
              )
              true
            } catch {
              LimitExceeded => false
              _ => fail("unexpected auto failure")
            }
            assert_eq(actual, feasible)
          }
        }
      }
    }
  }
}

///|
test "auto whitebox exact independent policy plans without content allocation" {
  let d = Limits::default()
  for
    (n, expected, count, size) in [
      (0L, 2048L, 0, 12),
      (65536L, 128L, 512, 18444),
      (1048576L, 2048L, 512, 18444),
      (67108864L, 131072L, 512, 18444),
    ] {
    let block = recommend_block_len(n, 32L, d)
    assert_eq(block, expected)
    let p = signature_plan(
      n.reinterpret_as_uint64(),
      { block_len: block, strong_sum_len: 32L, },
      d,
    )
    assert_eq(p.2, count)
    assert_eq(p.3, size)
  }
}
