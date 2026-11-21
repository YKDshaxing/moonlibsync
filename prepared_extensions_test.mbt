// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "prepared summary matches inspect_signature across empty single multi and short-tail inputs" {
  let d = @moonlibsync.Limits::default()
  let cases : Array[(Bytes, Int64, Int64)] = [
    (b"", 2048L, 32L),
    (b"a", 7L, 1L),
    (b"ABCDEFGHIJKLMN\x00\x80\xff", 7L, 16L),
    (Bytes::makei(5000, i => (i * 73 % 256).to_byte()), 2048L, 32L),
  ]
  for item in cases {
    let (old, block_len, strong_sum_len) = item
    let sig = @moonlibsync.signature(old, { block_len, strong_sum_len, }, d)
    let expected = @moonlibsync.inspect_signature(sig, d)
    let prepared = @moonlibsync.prepare_signature(sig, d)
    let actual = prepared.summary()
    assert_eq(actual.magic, expected.magic)
    assert_eq(actual.block_len, expected.block_len)
    assert_eq(actual.strong_sum_len, expected.strong_sum_len)
    assert_eq(actual.record_count, expected.record_count)
    assert_eq(actual.signature_bytes, expected.signature_bytes)
    // Summary remains stable before and after delta/plan calls.
    let _ = prepared.delta(old, d)
    let after = prepared.summary()
    assert_eq(after.magic, expected.magic)
    assert_eq(after.block_len, expected.block_len)
    assert_eq(after.strong_sum_len, expected.strong_sum_len)
    assert_eq(after.record_count, expected.record_count)
    assert_eq(after.signature_bytes, expected.signature_bytes)
  }
}

///|
test "prepared plan_update matches one-shot plan_update across delta full and threshold boundaries" {
  let d = @moonlibsync.Limits::default()
  let old = b"abcdefghijklmnop"
  let sig = @moonlibsync.signature(
    old,
    { block_len: 8L, strong_sum_len: 32L, },
    d,
  )
  let prepared = @moonlibsync.prepare_signature(sig, d)
  let targets : Array[(Bytes, Int64, String, String)] = [
    (old, 0L, "librsync-delta", "minimum-savings-met"),
    (old, 8L, "librsync-delta", "minimum-savings-met"),
    (old, 9L, "full-file", "below-minimum-savings"),
    (old, 9223372036854775807L, "full-file", "below-minimum-savings"),
    (b"abcdefgh", 0L, "full-file", "delta-not-smaller"),
    (b"xyz", 0L, "full-file", "delta-not-smaller"),
    (b"", 0L, "full-file", "delta-not-smaller"),
  ]
  for item in targets {
    let (new, min_savings_bytes, expected_kind, expected_reason) = item
    let options : @moonlibsync.UpdateOptions = { min_savings_bytes, }
    let oneshot = @moonlibsync.plan_update(sig, new, options, d)
    let reused = prepared.plan_update(new, options, d)
    assert_eq(reused.decision.kind, expected_kind)
    assert_eq(reused.decision.reason, expected_reason)
    assert_eq(reused.decision.kind, oneshot.decision.kind)
    assert_eq(reused.decision.reason, oneshot.decision.reason)
    assert_eq(reused.decision.new_bytes, oneshot.decision.new_bytes)
    assert_eq(reused.decision.delta_bytes, oneshot.decision.delta_bytes)
    assert_eq(reused.decision.payload_bytes, oneshot.decision.payload_bytes)
    assert_eq(reused.decision.savings_bytes, oneshot.decision.savings_bytes)
    assert_eq(
      reused.decision.min_savings_bytes,
      oneshot.decision.min_savings_bytes,
    )
    match (reused.payload, oneshot.payload) {
      (Delta(a), Delta(b)) => {
        assert_eq(a, b)
        assert_eq(@moonlibsync.patch(old, a, d), new)
      }
      (Full(a), Full(b)) => {
        assert_eq(a, b)
        assert_eq(a, new)
      }
      _ => fail("payload variant mismatch between prepared and one-shot")
    }
  }
}

///|
test "prepared plan_update revalidates limits options and preserves object after errors" {
  let d = @moonlibsync.Limits::default()
  let old = b"abcdefghijklmnop"
  let sig = @moonlibsync.signature(
    old,
    { block_len: 8L, strong_sum_len: 32L, },
    d,
  )
  let prepared = @moonlibsync.prepare_signature(sig, d)
  let neg_err = try {
    let _ = prepared.plan_update(old, { min_savings_bytes: -1L, }, d)
    false
  } catch {
    @moonlibsync.SyncError::InvalidOptions("min_savings_bytes") => true
    _ => false
  }
  assert_true(neg_err)
  let bad_limits = try {
    let _ = prepared.plan_update(old, { min_savings_bytes: -1L, }, {
      ..d,
      max_block_bytes: 0L,
    })
    false
  } catch {
    @moonlibsync.SyncError::InvalidOptions("max_block_bytes") => true
    _ => false
  }
  assert_true(bad_limits)
  let strict_limits : Array[@moonlibsync.Limits] = [
    { ..d, max_signature_bytes: sig.length().to_int64() - 1L, },
    { ..d, max_block_bytes: 7L, },
    { ..d, max_signature_records: 1L, },
    { ..d, max_new_bytes: 15L, },
    { ..d, max_output_bytes: 15L, },
    { ..d, max_delta_bytes: 4L, },
    { ..d, max_match_work: 1L, },
  ]
  for lim in strict_limits {
    let failed = try {
      let _ = prepared.plan_update(
        old,
        @moonlibsync.UpdateOptions::default(),
        lim,
      )
      false
    } catch {
      @moonlibsync.SyncError::LimitExceeded => true
      _ => false
    }
    assert_true(failed)
  }
  let ok = prepared.plan_update(old, @moonlibsync.UpdateOptions::default(), d)
  assert_eq(ok.decision.kind, "librsync-delta")
  match ok.payload {
    Delta(bytes) => assert_eq(@moonlibsync.patch(old, bytes, d), old)
    Full(_) => fail("expected Delta after recovery from errors")
  }
}
