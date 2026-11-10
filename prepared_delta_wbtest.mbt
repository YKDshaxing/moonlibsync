// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "prepared delta scan thirty excludes exactly three construction units" {
  let d = Limits::default()
  let sig = signature(b"abc", { block_len: 3L, strong_sum_len: 16L, }, d)
  let p = prepare_signature(sig, { ..d, max_match_work: 3L, })
  let index_before = p.index
  let order_before = p.index.order
  let records_before = p.index.signature.records
  for _ in 0..<3 {
    let result = p.delta(b"abc", { ..d, max_match_work: 30L, })
    assert_eq(result, b"\x72\x73\x02\x36\x45\x00\x03\x00")
    assert_true(physical_equal(p.index, index_before))
    assert_true(physical_equal(p.index.order, order_before))
    assert_true(physical_equal(p.index.signature.records, records_before))
    let work = index_work(30L)
    assert_eq(scan_signature_delta(p.index, b"abc", d, work), result)
    assert_eq(work.remaining, 0L)
  }
  expect_sync_error(
    () => {
      let _ = delta(sig, b"abc", { ..d, max_match_work: 30L, })
    },
    "LimitExceeded",
  )
  assert_eq(
    delta(sig, b"abc", { ..d, max_match_work: 33L, }),
    p.delta(b"abc", d),
  )
}

///|
test "prepared delta sixteen upstream signatures exact bytes recovery and COPY" {
  let bases = reference_bases()
  let signatures = reference_signatures()
  let news = reference_news()
  let d = Limits::default()
  for i in 0..<16 {
    let p = prepare_signature(signatures[i].1, d)
    let old = bases[i].1
    let new = news[i].1
    let result = p.delta(new, d)
    assert_eq(result, delta(signatures[i].1, new, d))
    assert_eq(patch(old, result, d), new)
    assert_eq(p.delta(new, d), result)
    assert_eq(p.signature_bytes, signatures[i].1.length().to_int64())
  }
}

///|
test "prepared delta index immutable through partial scan failure and capacity precharge" {
  let d = Limits::default()
  let p = scoped_prepared(b"abc")
  let order = p.index.order[:].to_owned()
  let digest = p.index.signature.records[0].strong_sum
  for cap in [0L, 1L, 5L, 10L] {
    expect_sync_error(
      () => {
        let _ = p.delta(b"!abc", { ..d, max_match_work: cap, })
      },
      "LimitExceeded",
    )
    assert_eq(p.index.order, order)
    assert_eq(p.index.signature.records[0].strong_sum, digest)
  }
  assert_eq(patch(b"abc", p.delta(b"!abc", d), d), b"!abc")
  let work = index_work(3L)
  let builder : DeltaBuilder = { commands: [], size: 5UL, }
  append_generated_span(builder, b"ab", 0, 1, None, d, work)
  expect_sync_error(
    () => {
      append_generated_span(
        builder,
        b"ab",
        1,
        2,
        Some({ record_index: 0, nominal_offset: 0UL, length: 1, }),
        d,
        work,
      )
    },
    "LimitExceeded",
  )
  assert_eq(builder.commands.length(), 1)
}

///|
test "prepared delta empty signature and zero work empty target retain one shot semantics" {
  let d = Limits::default()
  let sig = signature(b"", SignatureOptions::default(), d)
  let p = prepare_signature(sig, { ..d, max_match_work: 0L, })
  assert_eq(
    p.delta(b"", { ..d, max_match_work: 0L, }),
    delta(sig, b"", { ..d, max_match_work: 0L, }),
  )
  let result = p.delta(b"binary\x00\x80", d)
  assert_eq(result, delta(sig, b"binary\x00\x80", d))
  assert_eq(patch(b"", result, d), b"binary\x00\x80")
}
