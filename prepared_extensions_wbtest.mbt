// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "signature header parser matches full parse on all fixtures and error precedence" {
  let d = Limits::default()
  for item in reference_signatures() {
    let sig = item.1
    let header = parse_signature_header(sig, d)
    let full = parse_signature(sig, d)
    assert_eq(header.magic, full.magic)
    assert_eq(header.block_len, full.block_len)
    assert_eq(header.strong_sum_len, full.strong_sum_len)
    assert_eq(header.record_count, full.records.length())
  }
  let invalid_cases : Array[(Bytes, Limits, String)] = [
    (b"short", { ..d, max_signature_bytes: 4L, }, "LimitExceeded"),
    (b"short", d, "TruncatedInput"),
    (
      b"\x72\x73\x01\x37\x00\x00\x08\x00\x00\x00\x00\x20", d, "UnsupportedSignatureProfile",
    ),
    (b"\x00\x00\x00\x00\x00\x00\x08\x00\x00\x00\x00\x20", d, "InvalidSignature"),
    (b"\x72\x73\x01\x47\x00\x00\x00\x00\x00\x00\x00\x20", d, "InvalidSignature"),
    (b"\x72\x73\x01\x47\x00\x00\x08\x00\x00\x00\x00\x21", d, "InvalidSignature"),
    (
      b"\x72\x73\x01\x47\x00\x00\x08\x00\x00\x00\x00\x01\x01\x02\x03", d, "TruncatedInput",
    ),
    (
      b"\x72\x73\x01\x47\x80\x00\x00\x00\x00\x00\x00\x01", d, "IntegerOutOfRange",
    ),
  ]
  for item in invalid_cases {
    let (bytes, lim, expected) = item
    expect_sync_error(
      () => {
        let _ = parse_signature_header(bytes, lim)
      },
      expected,
    )
    expect_sync_error(
      () => {
        let _ = parse_signature(bytes, lim)
      },
      expected,
    )
  }
}

///|
test "rabinkarp pow_mult and one-shot digest match iterative computation" {
  let lengths = [0, 1, 2, 3, 7, 8, 15, 16, 63, 64, 255, 256, 2048, 2049]
  for n in lengths {
    let mut expected_mult = 1U
    for _ in 0..<n {
      expected_mult = expected_mult * 0x08104225U
    }
    assert_eq(rk_pow_mult(n), expected_mult)
    let data = Bytes::makei(n, i => ((i * 73 + 19) % 256).to_byte())
    let state = RabinKarp::new()
    state.update(data)
    assert_eq(state.mult, expected_mult)
    assert_eq(rabinkarp_digest(data), state.digest())
  }
}

///|
test "sorted_weaks mirrors order and prepared plan_update reuses index arrays" {
  let d = Limits::default()
  for item in reference_signatures() {
    let sig = parse_signature(item.1, d)
    let index = build_signature_index(sig, MatchWork::new(d))
    assert_eq(index.sorted_weaks.length(), index.order.length())
    for i in 0..<index.order.length() {
      assert_eq(index.sorted_weaks[i], sig.records[index.order[i]].weak_sum)
      if i > 0 {
        assert_true(index.sorted_weaks[i - 1] <= index.sorted_weaks[i])
      }
    }
  }
  let sig = signature(
    b"abcdefghijklmnop",
    { block_len: 8L, strong_sum_len: 32L, },
    d,
  )
  let p = prepare_signature(sig, d)
  let order_before = p.index.order
  let weaks_before = p.index.sorted_weaks
  let records_before = p.index.signature.records
  let plan = p.plan_update(b"abcdefghijklmnop", UpdateOptions::default(), d)
  assert_eq(plan.decision.kind, "librsync-delta")
  assert_true(physical_equal(p.index.order, order_before))
  assert_true(physical_equal(p.index.sorted_weaks, weaks_before))
  assert_true(physical_equal(p.index.signature.records, records_before))
}
