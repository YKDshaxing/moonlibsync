// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn auto_reject(
  action : () -> Unit raise @moonlibsync.SyncError,
  expected : String,
) -> Unit raise {
  let actual = try {
    action()
    "success"
  } catch {
    @moonlibsync.SyncError::InvalidOptions(field) => "InvalidOptions:" + field
    @moonlibsync.SyncError::LimitExceeded => "LimitExceeded"
    _ => "other"
  }
  assert_eq(actual, expected)
}

///|
fn auto_sample(
  length : Int32,
  strong : Int64,
  limits : @moonlibsync.Limits,
  block : Int64,
  records : Int64,
  size : Int64,
) -> Unit raise {
  assert_eq(
    @moonlibsync.recommend_block_len(length.to_int64(), strong, limits),
    block,
  )
  let data = Bytes::makei(length, i => (i % 251).to_byte())
  let sig = @moonlibsync.signature(
    data,
    { block_len: block, strong_sum_len: strong, },
    limits,
  )
  let summary = @moonlibsync.inspect_signature(sig, limits)
  assert_eq(summary.block_len, block)
  assert_eq(summary.record_count, records)
  assert_eq(summary.signature_bytes, size)
  assert_eq(sig.length().to_int64(), size)
}

///|
test "auto public policy v1 explicit thresholds with independent records and lengths" {
  let d = @moonlibsync.Limits::default()
  for
    (n, block, count, size) in [
      (1, 64L, 1L, 48L),
      (63, 64L, 1L, 48L),
      (64, 64L, 1L, 48L),
      (65, 64L, 2L, 84L),
      (32767, 64L, 512L, 18444L),
      (32768, 64L, 512L, 18444L),
      (32769, 128L, 257L, 9264L),
      (65535, 128L, 512L, 18444L),
      (65536, 128L, 512L, 18444L),
      (65537, 256L, 257L, 9264L),
      (131071, 256L, 512L, 18444L),
      (131072, 256L, 512L, 18444L),
      (131073, 512L, 257L, 9264L),
    ] {
    auto_sample(n, 32L, d, block, count, size)
  }
  assert_eq(@moonlibsync.recommend_block_len(1048575L, 32L, d), 2048L)
  assert_eq(@moonlibsync.recommend_block_len(1048577L, 32L, d), 4096L)
  assert_eq(@moonlibsync.recommend_block_len(1048576L, 32L, d), 2048L)
  assert_eq(@moonlibsync.recommend_block_len(67108864L, 32L, d), 131072L)
  assert_eq(@moonlibsync.recommend_block_len(67108863L, 32L, d), 131072L)
  auto_reject(
    () => {
      let _ = @moonlibsync.recommend_block_len(67108865L, 32L, d)
    },
    "LimitExceeded",
  )
}

///|
test "auto public empty basis zero records and exact header budget" {
  let d = @moonlibsync.Limits::default()
  for cap in [1L, 17L, 2047L, 2048L, 2049L] {
    let limits = {
      ..d,
      max_old_bytes: 0L,
      max_signature_records: 0L,
      max_signature_bytes: 12L,
      max_block_bytes: cap,
    }
    let expected = if cap < 2048L { cap } else { 2048L }
    auto_sample(0, 32L, limits, expected, 0L, 12L)
  }
  auto_reject(
    () => {
      let _ = @moonlibsync.recommend_block_len(0L, 32L, {
        ..d,
        max_signature_bytes: 11L,
      })
    },
    "LimitExceeded",
  )
}

///|
test "auto public record caps change required size without changing defaults" {
  let d = @moonlibsync.Limits::default()
  auto_sample(129, 32L, { ..d, max_signature_records: 1L, }, 256L, 1L, 48L)
  auto_sample(129, 32L, { ..d, max_signature_records: 2L, }, 128L, 2L, 84L)
  auto_sample(129, 32L, { ..d, max_signature_records: 3L, }, 64L, 3L, 120L)
  auto_reject(
    () => {
      let _ = @moonlibsync.recommend_block_len(1L, 32L, {
        ..d,
        max_signature_records: 0L,
      })
    },
    "LimitExceeded",
  )
}

///|
test "auto public byte cap threshold adapts to fewer records instead of rejecting feasible input" {
  let d = @moonlibsync.Limits::default()
  auto_sample(129, 32L, { ..d, max_signature_bytes: 83L, }, 256L, 1L, 48L)
  auto_sample(129, 32L, { ..d, max_signature_bytes: 84L, }, 128L, 2L, 84L)
  auto_sample(129, 32L, { ..d, max_signature_bytes: 85L, }, 128L, 2L, 84L)
}

///|
test "auto public strong widths one sixteen thirtytwo and single record exact budgets" {
  let d = @moonlibsync.Limits::default()
  for (sum, bytes) in [(1L, 17L), (16L, 32L), (32L, 48L)] {
    auto_reject(
      () => {
        let _ = @moonlibsync.recommend_block_len(65L, sum, {
          ..d,
          max_signature_bytes: bytes - 1L,
        })
      },
      "LimitExceeded",
    )
    auto_sample(65, sum, { ..d, max_signature_bytes: bytes, }, 128L, 1L, bytes)
    auto_sample(
      65,
      sum,
      { ..d, max_signature_bytes: bytes + 1L, },
      128L,
      1L,
      bytes,
    )
  }
  auto_sample(129, 1L, { ..d, max_signature_bytes: 48L, }, 64L, 3L, 27L)
  auto_sample(129, 16L, { ..d, max_signature_bytes: 48L, }, 256L, 1L, 32L)
  auto_sample(129, 32L, { ..d, max_signature_bytes: 48L, }, 256L, 1L, 48L)
}

///|
test "auto public nonpower block cap preserves feasible candidates at exact boundary" {
  let d = @moonlibsync.Limits::default()
  auto_reject(
    () => {
      let _ = @moonlibsync.recommend_block_len(34L, 32L, {
        ..d,
        max_block_bytes: 16L,
        max_signature_records: 2L,
      })
    },
    "LimitExceeded",
  )
  auto_sample(
    33,
    32L,
    { ..d, max_block_bytes: 17L, max_signature_records: 2L, },
    17L,
    2L,
    84L,
  )
  auto_sample(
    34,
    32L,
    { ..d, max_block_bytes: 17L, max_signature_records: 2L, },
    17L,
    2L,
    84L,
  )
  auto_sample(
    34,
    32L,
    { ..d, max_block_bytes: 18L, max_signature_records: 2L, },
    18L,
    2L,
    84L,
  )
  auto_reject(
    () => {
      let _ = @moonlibsync.recommend_block_len(35L, 32L, {
        ..d,
        max_block_bytes: 17L,
        max_signature_records: 2L,
      })
    },
    "LimitExceeded",
  )
  for (cap, expected) in [(63L, 63L), (64L, 64L), (65L, 64L)] {
    auto_sample(
      129,
      32L,
      { ..d, max_block_bytes: cap, max_signature_records: 3L, },
      expected,
      3L,
      120L,
    )
  }
}

///|
test "auto public validation order and Int64 extremes never overflow" {
  let d = @moonlibsync.Limits::default()
  for n in [-9223372036854775808L, -1L] {
    auto_reject(
      () => {
        let _ = @moonlibsync.recommend_block_len(n, 0L, {
          ..d,
          max_signature_bytes: 0L,
        })
      },
      "InvalidOptions:basis_len",
    )
  }
  for sum in [-9223372036854775808L, 0L, 33L, 9223372036854775807L] {
    auto_reject(
      () => {
        let _ = @moonlibsync.recommend_block_len(9223372036854775807L, sum, d)
      },
      "InvalidOptions:strong_sum_len",
    )
  }
  auto_reject(
    () => {
      let _ = @moonlibsync.recommend_block_len(9223372036854775807L, 32L, d)
    },
    "LimitExceeded",
  )
  for
    (limits, name) in [
      ({ ..d, max_old_bytes: -1L, }, "max_old_bytes"),
      ({ ..d, max_old_bytes: 9223372036854775807L, }, "max_old_bytes"),
      ({ ..d, max_new_bytes: -1L, }, "max_new_bytes"),
      ({ ..d, max_block_bytes: 0L, }, "max_block_bytes"),
      ({ ..d, max_signature_bytes: -1L, }, "max_signature_bytes"),
      ({ ..d, max_signature_records: -1L, }, "max_signature_records"),
      ({ ..d, max_delta_bytes: -1L, }, "max_delta_bytes"),
      ({ ..d, max_output_bytes: -1L, }, "max_output_bytes"),
      ({ ..d, max_instructions: -1L, }, "max_instructions"),
      ({ ..d, max_match_work: -1L, }, "max_match_work"),
    ] {
    auto_reject(
      () => {
        let _ = @moonlibsync.recommend_block_len(-1L, 0L, limits)
      },
      "InvalidOptions:" + name,
    )
  }
}

///|
test "auto public legal unrelated zero budgets and limits are unchanged" {
  let d = @moonlibsync.Limits::default()
  let limits = {
    ..d,
    max_new_bytes: 0L,
    max_delta_bytes: 0L,
    max_output_bytes: 0L,
    max_instructions: 0L,
    max_match_work: 0L,
  }
  auto_sample(65, 16L, limits, 64L, 2L, 52L)
  assert_eq(limits.max_match_work, 0L)
  assert_eq(limits.max_signature_bytes, d.max_signature_bytes)
}

///|
test "auto public recommendation never changes legacy default or zero option semantics" {
  let d = @moonlibsync.Limits::default()
  let old = b"abc"
  let before = @moonlibsync.signature(
    old,
    @moonlibsync.SignatureOptions::default(),
    d,
  )
  assert_eq(@moonlibsync.recommend_block_len(3L, 32L, d), 64L)
  assert_eq(@moonlibsync.SignatureOptions::default().block_len, 2048L)
  assert_eq(@moonlibsync.SignatureOptions::default().strong_sum_len, 32L)
  assert_eq(
    @moonlibsync.signature(old, @moonlibsync.SignatureOptions::default(), d),
    before,
  )
  auto_reject(
    () => {
      let _ = @moonlibsync.signature(
        old,
        { block_len: 0L, strong_sum_len: 32L, },
        d,
      )
    },
    "InvalidOptions:block_len",
  )
}

///|
test "auto public failure followed by success preserves old bytes and earlier result" {
  let d = @moonlibsync.Limits::default()
  let old = b"abc"
  let before = @moonlibsync.signature(
    old,
    { block_len: 64L, strong_sum_len: 32L, },
    d,
  )
  for _ in 0..<3 {
    auto_reject(
      () => {
        let _ = @moonlibsync.recommend_block_len(3L, 32L, {
          ..d,
          max_signature_bytes: 12L,
        })
      },
      "LimitExceeded",
    )
    assert_eq(@moonlibsync.recommend_block_len(3L, 32L, d), 64L)
    assert_eq(
      @moonlibsync.signature(old, { block_len: 64L, strong_sum_len: 32L, }, d),
      before,
    )
  }
  assert_eq(old, b"abc")
}
