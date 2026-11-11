// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "update selection hand calculated strict tie and threshold neighbors" {
  for
    (n, d, m, kind, reason, saved) in [
      (10L, 7L, 0L, "librsync-delta", "minimum-savings-met", 3L),
      (10L, 7L, 2L, "librsync-delta", "minimum-savings-met", 3L),
      (10L, 7L, 3L, "librsync-delta", "minimum-savings-met", 3L),
      (10L, 7L, 4L, "full-file", "below-minimum-savings", 0L),
      (10L, 10L, 0L, "full-file", "delta-not-smaller", 0L),
      (10L, 11L, 0L, "full-file", "delta-not-smaller", 0L),
      (0L, 5L, 0L, "full-file", "delta-not-smaller", 0L),
      (10L, 7L, 9223372036854775807L, "full-file", "below-minimum-savings", 0L),
    ] {
    let value = update_decision(n, d, { min_savings_bytes: m, })
    assert_eq(value.kind, kind)
    assert_eq(value.reason, reason)
    assert_eq(value.savings_bytes, saved)
    assert_eq(value.new_bytes, n)
    assert_eq(value.delta_bytes, d)
    assert_eq(value.payload_bytes, n - saved)
    assert_eq(value.min_savings_bytes, m)
  }
}

///|
test "update independent tie uses a real eight byte COPY and eight byte NEW" {
  let limits = Limits::default()
  let old = b"abcdefgh"
  let sig = signature(old, { block_len: 8L, strong_sum_len: 32L, }, limits)
  let plan = plan_update(sig, old, UpdateOptions::default(), limits)
  assert_eq(plan.decision.delta_bytes, 8L)
  assert_eq(plan.decision.kind, "full-file")
  assert_true(plan.payload is Full(_))
  assert_eq(delta(sig, old, limits), b"\x72\x73\x02\x36\x45\x00\x08\x00")
}
