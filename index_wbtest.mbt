// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// These adversarial records are structurally legal, not claimed real weak collisions.
fn crafted_index_signature(
  block : Int32,
  strong : Int32,
  records : Array[(UInt32, Bytes)],
) -> Signature raise SyncError {
  let out = signature_header(
    block,
    strong,
    signature_size(records.length().to_uint64(), strong.to_uint64()),
  )
  let mut cursor = 12L
  for (weak, digest) in records {
    write_signature_record(out, cursor, weak, digest)
    cursor = cursor + (4 + strong).to_int64()
  }
  let d = Limits::default()
  parse_signature(Bytes::from_array(out[:]), {
    ..d,
    max_block_bytes: block.to_int64(),
  })
}

///|
fn index_work(amount : Int64) -> MatchWork raise SyncError {
  let d = Limits::default()
  MatchWork::new({ ..d, max_match_work: amount, })
}

///|
fn window_weak(input : BytesView) -> UInt32 raise SyncError {
  let state = RabinKarp::new()
  state.update(input)
  state.digest()
}

///|
fn assert_block_match(
  result : BlockMatch?,
  id : Int32,
  offset : UInt64,
  length : Int32,
) -> Unit raise {
  guard result is Some(m) else { fail("expected confirmed match") }
  assert_eq(m.record_index, id)
  assert_eq(m.nominal_offset, offset)
  assert_eq(m.length, length)
}

///|
test "index empty absent weak and invalid windows avoid digest work" {
  let work = index_work(0L)
  let empty = crafted_index_signature(7, 16, [])
  let index = build_signature_index(empty, work)
  assert_true(
    match_signature_window(index, b"", window_weak(b""), work) is None,
  )
  assert_true(
    match_signature_window(index, b"abc", window_weak(b"abc"), work) is None,
  )
  assert_eq(work.remaining, 0L)
  expect_sync_error(
    () => {
      let _ = match_signature_window(
        index,
        b"12345678",
        window_weak(b"12345678"),
        work,
      )
    },
    "InvalidOptions:window_len",
  )
  let weak = window_weak(b"abc")
  let sig = crafted_index_signature(7, 16, [(weak, strong_sum(b"abc", 16))])
  let b = index_work(5L) // 3 build + 1 binary probe + 1 absent group check
  let one = build_signature_index(sig, b)
  assert_true(
    match_signature_window(one, b"aaa", window_weak(b"aaa"), b) is None,
  )
  assert_eq(b.remaining, 0L)
}

///|
test "index unsigned sorting is metered and equal weak keys preserve original ordinal" {
  let sig = crafted_index_signature(7, 1, [
    (0xffffffffU, b"\xff"),
    (0U, b"\x00"),
    (0x80000000U, b"\x80"),
    (0U, b"\x01"),
  ])
  let work = index_work(100L)
  let index = build_signature_index(sig, work)
  assert_eq(index.order, [1, 3, 2, 0])
  assert_eq(sig.records[0].weak_sum, 0xffffffffU)
  // Odd runs exercise every merge width and remainder-copy path beyond 4 items.
  let odd_records : Array[(UInt32, Bytes)] = Array::makei(17, i => {
    ((i % 3).reinterpret_as_uint(), b"\x00")
  })
  let odd_sig = crafted_index_signature(7, 1, odd_records)
  let odd_work = index_work(500L)
  assert_eq(build_signature_index(odd_sig, odd_work).order, [
    0, 3, 6, 9, 12, 15, 1, 4, 7, 10, 13, 16, 2, 5, 8, 11, 14,
  ])
  let cost = 100L - work.remaining
  let exact = index_work(cost)
  assert_eq(build_signature_index(sig, exact).order, [1, 3, 2, 0])
  assert_eq(exact.remaining, 0L)
  let short = index_work(cost - 1L)
  expect_sync_error(
    () => {
      let _ = build_signature_index(sig, short)
    },
    "LimitExceeded",
  )
  assert_true(short.remaining < cost - 1L) // charged work was not refunded
  let small = index_work(11L) // four records require 12 units before arrays
  expect_sync_error(
    () => {
      let _ = build_signature_index(sig, small)
    },
    "LimitExceeded",
  )
  assert_eq(small.remaining, 11L)
  let high_window = b"\x00\x01\x02\x03"
  let high_weak = window_weak(high_window)
  assert_true(high_weak > 0x7fffffffU)
  let high_sig = crafted_index_signature(7, 1, [
    (high_weak, strong_sum(high_window, 1)),
  ])
  let high_work = index_work(100L)
  let high_index = build_signature_index(high_sig, high_work)
  assert_block_match(
    match_signature_window(high_index, high_window, high_weak, high_work),
    0,
    0UL,
    4,
  )
}

///|
test "index genuine strong confirmation rejects crafted weak-only hits and distinguishes full prefix" {
  let window = b"abc"
  let weak = window_weak(window)
  let digest = strong_sum(window, 16)
  let altered = digest.to_array()
  altered[15] = altered[15] ^ b'\x01'
  let false_digest = Bytes::from_array(altered[:])
  assert_eq(false_digest[0:1].to_owned(), digest[0:1].to_owned())
  let sig = crafted_index_signature(7, 16, [
    (weak, false_digest),
    (weak, strong_sum(b"other", 16)),
    (weak, digest),
  ])
  let work = index_work(76L) // 18 build; query 2 probes+1 presence+4 hash+3 visits+48 compare
  let index = build_signature_index(sig, work)
  assert_eq(work.remaining, 58L)
  assert_block_match(
    match_signature_window(index, window, weak, work),
    2,
    14UL,
    3,
  )
  assert_eq(work.remaining, 0L) // one digest, not one per candidate
  let reject_sig = crafted_index_signature(7, 16, [
    (weak, false_digest),
    (weak, false_digest),
    (weak, false_digest),
  ])
  let reject_work = index_work(76L)
  let reject = build_signature_index(reject_sig, reject_work)
  assert_true(match_signature_window(reject, window, weak, reject_work) is None)
  assert_eq(reject_work.remaining, 0L)
}

///|
test "index repeated matches and one-byte signatures choose the first saved-prefix match" {
  let window = b"\x00\x80\xff"
  let weak = window_weak(window)
  let digest = strong_sum(window, 1)
  let sig = crafted_index_signature(7, 1, [
    (0U, b"\x00"),
    (weak, digest),
    (0xffffffffU, b"\xff"),
    (weak, digest),
  ])
  let work = index_work(200L)
  let index = build_signature_index(sig, work)
  for _ in 0..<3 {
    assert_block_match(
      match_signature_window(index, window, weak, work),
      1,
      7UL,
      3,
    )
  }
  // Only the saved byte is compared; no demand for the other 31 bytes.
  assert_eq(sig.records[1].strong_sum.length(), 1)
}

///|
test "index singleton exact charges and all query stage boundaries" {
  let window = b"abc"
  let weak = window_weak(window)
  let sig = crafted_index_signature(7, 16, [(weak, strong_sum(window, 16))])
  let exact = index_work(26L) // 3 build + 1 probe + 1 presence + 4 hash + 1 visit + 16 compare
  let index = build_signature_index(sig, exact)
  assert_block_match(
    match_signature_window(index, window, weak, exact),
    0,
    0UL,
    3,
  )
  assert_eq(exact.remaining, 0L)
  for available in [0L, 1L, 2L, 3L, 6L, 7L, 22L] {
    let work = index_work(3L + available)
    let fresh = build_signature_index(sig, work)
    expect_sync_error(
      () => {
        let _ = match_signature_window(fresh, window, weak, work)
      },
      "LimitExceeded",
    )
    assert_true(work.remaining <= available)
    let replacement = index_work(23L)
    assert_block_match(
      match_signature_window(fresh, window, weak, replacement),
      0,
      0UL,
      3,
    )
    assert_eq(sig.records[0].strong_sum, strong_sum(window, 16))
  }
}

///|
test "index collision traversal and repeated queries exhaust the same budget without reset" {
  let window = b"abc"
  let weak = window_weak(window)
  let digest = strong_sum(window, 16)
  let sig = crafted_index_signature(7, 16, [
    (weak, strong_sum(b"different", 16)),
    (weak, digest),
    (weak, digest),
  ])
  let work = index_work(75L)
  let index = build_signature_index(sig, work)
  assert_block_match(
    match_signature_window(index, window, weak, work),
    1,
    7UL,
    3,
  )
  let after = work.remaining
  expect_sync_error(
    () => {
      let _ = match_signature_window(index, window, weak, work)
    },
    "LimitExceeded",
  )
  assert_true(work.remaining < after)
  let last_sig = crafted_index_signature(7, 16, [
    (weak, strong_sum(b"x", 16)),
    (weak, strong_sum(b"y", 16)),
    (weak, digest),
  ])
  let short = index_work(75L)
  let last = build_signature_index(last_sig, short)
  expect_sync_error(
    () => {
      let _ = match_signature_window(last, window, weak, short)
    },
    "LimitExceeded",
  )
  assert_eq(short.remaining, 15L)
  let retry = index_work(58L)
  assert_block_match(
    match_signature_window(last, window, weak, retry),
    2,
    14UL,
    3,
  )
  assert_eq(retry.remaining, 0L)
}

///|
test "index wide nominal offsets and checked range addition never narrow to Int32" {
  let window = b"x"
  let weak = window_weak(window)
  let sig = crafted_index_signature(2147483647, 1, [
    (0U, b"\x00"),
    (0xffffffffU, b"\xff"),
    (weak, strong_sum(window, 1)),
  ])
  let work = index_work(100L)
  let index = build_signature_index(sig, work)
  assert_block_match(
    match_signature_window(index, window, weak, work),
    2,
    4294967294UL,
    1,
  )
  assert_eq(checked_match_end(0xfffffffffffffffeUL, 1UL), 0xffffffffffffffffUL)
  expect_sync_error(
    () => {
      let _ = checked_match_end(0xffffffffffffffffUL, 1UL)
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = checked_block_offset(0x8000000000000000UL, 2UL)
    },
    "IntegerOutOfRange",
  )
}

///|
test "index real fixture windows match including short tails and stable duplicate choices" {
  let bases = reference_bases()
  let signatures = reference_signatures()
  for i in 0..<bases.length() {
    let (id, basis) = bases[i]
    let (sig_id, bytes) = signatures[i]
    assert_eq(id, sig_id)
    let sig = parse_signature(bytes, Limits::default())
    let work = MatchWork::new(Limits::default())
    let index = build_signature_index(sig, work) // no basis argument
    let mut pos = 0
    for _ in sig.records {
      let take = if basis.length() - pos < sig.block_len {
        basis.length() - pos
      } else {
        sig.block_len
      }
      let window = basis[pos:pos + take]
      let weak = window_weak(window)
      let digest = strong_sum(window, sig.strong_sum_len)
      let mut first = -1
      for record in sig.records {
        if first == -1 && record.weak_sum == weak && record.strong_sum == digest {
          first = record.block_index
        }
      }
      assert_true(first >= 0)
      assert_block_match(
        match_signature_window(index, window, weak, work),
        first,
        checked_block_offset(first.to_uint64(), sig.block_len.to_uint64()),
        take,
      )
      pos = pos + take
    }
    assert_eq(pos, basis.length())
  }
}
