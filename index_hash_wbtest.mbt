// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "index open-addressed table enforces load factor <= 0.5 and precharges before table allocation" {
  let d = Limits::default()
  // 128 identical weak keys => distinct=1, M=2, sort=1728, table=2*2=4, insert=1.
  let bytes = prepared_test_wire(1, Array::make(128, (0U, b"\x00")))
  let parsed = parse_signature(bytes, d)
  let short_table = index_work(1731L)
  expect_sync_error(
    () => {
      let _ = build_signature_index(parsed, short_table)
    },
    "LimitExceeded",
  )
  // Failed 4-unit table precharge must leave all 3 remaining units untouched.
  assert_eq(short_table.remaining, 3L)
  let short_insert = index_work(1732L)
  expect_sync_error(
    () => {
      let _ = build_signature_index(parsed, short_insert)
    },
    "LimitExceeded",
  )
  assert_eq(short_insert.remaining, 0L)
  let index = build_signature_index(parsed, index_work(1733L))
  assert_eq(index.bucket_weak.length(), 2)
  assert_eq(index.bucket_start.length(), 2)

  // Distinct key counts check power-of-two sizing so load <= 0.50 always holds.
  for distinct_count in [1, 2, 3, 4, 5, 9] {
    let recs : Array[(UInt32, Bytes)] = Array::makei(distinct_count, i => {
      (i.reinterpret_as_uint() * 2654435761U, b"\x01")
    })
    let s = crafted_index_signature(4, 1, recs)
    let idx = build_signature_index(s, index_work(10000L))
    let m = idx.bucket_start.length()
    assert_true(m >= distinct_count * 2)
    assert_true((m & (m - 1)) == 0)
    let mut occupied = 0
    for start in idx.bucket_start {
      if start >= 0 {
        occupied = occupied + 1
      }
    }
    assert_eq(occupied, distinct_count)
  }
}

///|
test "index hash collision chain probes deterministically and preserves earliest ordinal" {
  let w0 = window_weak(b"AAAA")
  let w1 = window_weak(b"BBBB")
  // Find a 3rd key whose bucket collides mod 4 with w0, and a 4th absent key colliding too.
  let mut w2 = 0U
  for k in 100U..<2000U {
    if k != w0 && k != w1 && weak_slot(k, 3) == weak_slot(w0, 3) {
      w2 = k
      break
    }
  }
  let mut absent = 0U
  for k in 5000U..<9000U {
    if k != w0 && k != w1 && k != w2 && weak_slot(k, 3) == weak_slot(w0, 3) {
      absent = k
      break
    }
  }
  assert_true(w2 != 0U && absent != 0U)
  // Two distinct keys (w0 repeated twice + w2) -> distinct=2 -> M=4 -> mask=3.
  let d_a = strong_sum(b"AAAA", 16)
  let wrong_a = Bytes::make(16, b'\x00')
  let sig = crafted_index_signature(4, 16, [
    (w2, strong_sum(b"CCCC", 16)),
    (w0, wrong_a),
    (w0, d_a),
    (w0, d_a),
  ])
  let index = build_signature_index(sig, index_work(1000L))
  assert_eq(index.bucket_start.length(), 4)
  // Colliding miss probes occupied slots until hitting empty slot without strong hashing.
  let miss_work = index_work(10L)
  assert_true(
    match_signature_at(index, b"ZZZZ", 0, 4, absent, miss_work) is None,
  )
  let spent_miss = 10L - miss_work.remaining
  assert_true(spent_miss >= 2L && spent_miss <= 3L)
  // Hit on w0 traverses collision chain in bucket table and selects earliest matching ordinal (2).
  let hit = match_signature_at(index, b"XXAAAAYY", 2, 4, w0, index_work(200L))
  assert_block_match(hit, 2, 8UL, 4)
}

///|
test "delta pending literal run rejects zero instructions and width boundary overflow early" {
  let d = Limits::default()
  let empty_sig = signature(b"", { block_len: 16L, strong_sum_len: 32L, }, d)
  expect_sync_error(
    () => {
      let _ = delta(empty_sig, b"a", { ..d, max_instructions: 0L, })
    },
    "LimitExceeded",
  )
  // Length 64 uses 1-byte literal header (5+1+64 = 70); 65 jumps to 2-byte header (5+2+65 = 72).
  let b64 = Bytes::make(64, b'x')
  let b65 = Bytes::make(65, b'x')
  assert_eq(
    delta(empty_sig, b64, { ..d, max_delta_bytes: 70L, max_instructions: 1L, }).length(),
    70,
  )
  expect_sync_error(
    () => {
      let _ = delta(empty_sig, b65, {
        ..d,
        max_delta_bytes: 71L,
        max_instructions: 1L,
      })
    },
    "LimitExceeded",
  )
  // Pending literal flush with deferred Copy merge checks works with max_instructions=1.
  let sig = signature(b"ABCD", { block_len: 4L, strong_sum_len: 16L, }, d)
  let out = delta(sig, b"xxABCD", { ..d, max_instructions: 2L, })
  assert_eq(patch(b"ABCD", out, d), b"xxABCD")
}
