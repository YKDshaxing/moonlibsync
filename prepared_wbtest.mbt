// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn prepared_test_wire(
  block : Int32,
  records : Array[(UInt32, Bytes)],
) -> Bytes raise SyncError {
  encode_signature(crafted_index_signature(block, 1, records), {
    ..Limits::default(),
    max_block_bytes: block.to_int64(),
  })
}

///|
test "prepared metadata unsigned stable order and duplicate retention" {
  let bytes = b"\x72\x73\x01\x47\x00\x00\x00\x07\x00\x00\x00\x01\xff\xff\xff\xff\xff\x00\x00\x00\x00\x00\x80\x00\x00\x00\x80\x00\x00\x00\x00\x00"
  let p = prepare_signature(bytes, Limits::default())
  assert_eq(p.signature_bytes, 32L)
  assert_eq(p.index.signature.magic, 0x72730147U)
  assert_eq(p.index.signature.block_len, 7)
  assert_eq(p.index.signature.strong_sum_len, 1)
  assert_eq(p.index.signature.records.length(), 4)
  assert_eq(p.index.order, [1, 3, 2, 0])
  assert_eq(p.index.signature.records[0].weak_sum, 0xffffffffU)
  assert_eq(p.index.signature.records[2].weak_sum, 0x80000000U)
  // Ordinals 1 and 3 are exact duplicates and are both retained, in order.
  assert_eq(p.index.signature.records[1].strong_sum, b"\x00")
  assert_eq(p.index.signature.records[3].strong_sum, b"\x00")
  assert_eq(p.index.signature.records[3].nominal_offset, 21UL)
  let empty = prepare_signature(
    b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x20",
    { ..Limits::default(), max_match_work: 0L, },
  )
  assert_eq(empty.signature_bytes, 12L)
  assert_eq(empty.index.signature.records.length(), 0)
  assert_eq(empty.index.order.length(), 0)
}

///|
test "prepared work boundaries use independently derived merge costs" {
  // Equal sorted keys: init=3n, writes=n per pass, comparisons=n/2 per
  // pass for powers of two. n=1:3; n=2:9; n=8:60; n=128:1728.
  // Four unsigned keys [MAX,0,0x80000000,0]: init12+writes8+comparisons5=25.
  let cases : Array[(Array[(UInt32, Bytes)], Int64)] = [
    ([], 0L),
    ([(0U, b"\x00")], 3L),
    (Array::make(2, (0U, b"\x00")), 9L),
    (
      [
        (0xffffffffU, b"\xff"),
        (0U, b"\x00"),
        (0x80000000U, b"\x80"),
        (0U, b"\x00"),
      ],
      25L,
    ),
    (Array::make(8, (0U, b"\x00")), 60L),
    (Array::make(128, (0U, b"\x00")), 1728L),
  ]
  for (records, need) in cases {
    let bytes = prepared_test_wire(7, records)
    let d = Limits::default()
    if need > 0L {
      expect_sync_error(
        () => {
          let _ = prepare_signature(bytes, { ..d, max_match_work: need - 1L, })
        },
        "LimitExceeded",
      )
    }
    for cap in [need, need + 1L] {
      let p = prepare_signature(bytes, { ..d, max_match_work: cap, })
      assert_eq(p.index.order.length(), records.length())
      assert_eq(p.signature_bytes, 12L + 5L * records.length().to_int64())
    }
  }
}

///|
test "prepared index precharges both arrays before allocation work" {
  let bytes = prepared_test_wire(1, Array::make(128, (0U, b"\x00")))
  let d = { ..Limits::default(), max_match_work: 383L, }
  let parsed = parse_signature(bytes, d)
  let work = MatchWork::new(d)
  expect_sync_error(
    () => {
      let _ = build_signature_index(parsed, work)
    },
    "LimitExceeded",
  )
  assert_eq(work.remaining, 383L) // 3*128=384 is checked as one precharge.
  assert_eq(parsed.records.length(), 128)
  expect_sync_error(
    () => {
      let _ = prepare_signature(bytes, d)
    },
    "LimitExceeded",
  )
  assert_eq(
    prepare_signature(bytes, { ..d, max_match_work: 1728L, }).index.order,
    Array::makei(128, i => i),
  )
}

///|
test "prepared nominal offsets above UInt32 remain wide through matching" {
  let window = b"a"
  let weak = window_weak(window)
  let digest = strong_sum(window, 1)
  let wrong = if digest == b"\x00" { b"\xff" } else { b"\x00" }
  let bytes = prepared_test_wire(2147483647, [
    (weak, wrong),
    (weak, wrong),
    (weak, wrong),
    (weak, digest),
  ])
  let p = prepare_signature(bytes, {
    ..Limits::default(),
    max_block_bytes: 2147483647L,
  })
  assert_eq(p.signature_bytes, 32L)
  assert_eq(p.index.signature.block_len, 2147483647)
  assert_eq(p.index.signature.records[2].nominal_offset, 4294967294UL)
  assert_eq(p.index.signature.records[3].nominal_offset, 6442450941UL)
  assert_eq(p.index.order, [0, 1, 2, 3])
  assert_block_match(
    match_signature_window(p.index, window, weak, index_work(100L)),
    3,
    6442450941UL,
    1,
  )
}

///|
fn scoped_prepared(data : Bytes) -> PreparedSignature raise SyncError {
  let encoded = signature(
    data,
    { block_len: 2L, strong_sum_len: 32L, },
    Limits::default(),
  )
  prepare_signature(encoded, Limits::default())
}

///|
test "prepared owned lifetime multiple objects and failed queries stay independent" {
  let a = scoped_prepared(b"abc")
  let b = scoped_prepared(b"xyz")
  let order_a = a.index.order[:].to_owned()
  let order_b = b.index.order[:].to_owned()
  for _ in 0..<3 {
    expect_sync_error(
      () => {
        let _ = match_signature_window(
          a.index,
          b"ab",
          window_weak(b"ab"),
          index_work(0L),
        )
      },
      "LimitExceeded",
    )
    expect_sync_error(
      () => {
        let _ = prepare_signature(b"", Limits::default())
      },
      "TruncatedInput",
    )
    assert_block_match(
      match_signature_window(
        a.index,
        b"ab",
        window_weak(b"ab"),
        index_work(100L),
      ),
      0,
      0UL,
      2,
    )
    assert_block_match(
      match_signature_window(b.index, b"z", window_weak(b"z"), index_work(100L)),
      1,
      2UL,
      1,
    )
    assert_block_match(
      match_signature_window(a.index, b"c", window_weak(b"c"), index_work(100L)),
      1,
      2UL,
      1,
    )
    assert_true(
      match_signature_window(
        b.index,
        b"ab",
        window_weak(b"ab"),
        index_work(100L),
      )
      is None,
    )
  }
  assert_eq(a.index.order, order_a)
  assert_eq(b.index.order, order_b)
  assert_eq(a.index.signature.records[0].strong_sum, strong_sum(b"ab", 32))
  assert_eq(b.index.signature.records[0].strong_sum, strong_sum(b"xy", 32))
}

///|
test "prepared sixteen upstream fixtures full blocks short tails and stable earliest choices" {
  let bases = reference_bases()
  let signatures = reference_signatures()
  assert_eq(bases.length(), 16)
  assert_eq(signatures.length(), 16)
  for i in 0..<16 {
    let (id, basis) = bases[i]
    let (sig_id, bytes) = signatures[i]
    assert_eq(id, sig_id)
    let block = match id {
      "empty" | "default-edit" => 2048
      "before-block" | "exact-block" | "after-block" | "repeat" => 16
      _ => 7
    }
    let strong = match id {
      "empty-new" | "one" | "after-block" | "insert-head" | "delete-tail" => 1
      "to-empty"
      | "before-block"
      | "repeat"
      | "insert-middle"
      | "delete-head" => 16
      _ => 32
    }
    let count = (basis.length() + block - 1) / block // Actual old bytes, test-only.
    let p = prepare_signature(bytes, Limits::default())
    assert_eq(p.signature_bytes, bytes.length().to_int64())
    assert_eq(p.index.signature.magic, 0x72730147U)
    assert_eq(p.index.signature.block_len, block)
    assert_eq(p.index.signature.strong_sum_len, strong)
    assert_eq(p.index.signature.records.length(), count)
    for n in 0..<count {
      let start = n * block
      let end = if basis.length() - start < block {
        basis.length()
      } else {
        start + block
      }
      let window = basis[start:end]
      // Independent earliest identical basis block, not a query/encoder oracle.
      let first = if id == "repeat" || (id == "default-edit" && n < 2) {
        0
      } else {
        n
      }
      assert_block_match(
        match_signature_window(
          p.index,
          window,
          window_weak(window),
          index_work(100000L),
        ),
        first,
        first.to_uint64() * block.to_uint64(),
        end - start,
      )
      let record = p.index.signature.records[n]
      let digest_start = 12 + n * (4 + strong) + 4
      assert_eq(
        record.strong_sum,
        bytes[digest_start:digest_start + strong].to_owned(),
      )
      assert_eq(record.nominal_offset, n.to_uint64() * block.to_uint64())
    }
  }
}

///|
test "prepared validates all limit fields even when preparation does not use them" {
  let d = Limits::default()
  let header = b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x01"
  for
    (limits, field) in [
      ({ ..d, max_old_bytes: -1L, }, "max_old_bytes"),
      ({ ..d, max_new_bytes: -1L, }, "max_new_bytes"),
      ({ ..d, max_signature_bytes: -1L, }, "max_signature_bytes"),
      ({ ..d, max_signature_records: -1L, }, "max_signature_records"),
      ({ ..d, max_block_bytes: 0L, }, "max_block_bytes"),
      ({ ..d, max_delta_bytes: -1L, }, "max_delta_bytes"),
      ({ ..d, max_output_bytes: -1L, }, "max_output_bytes"),
      ({ ..d, max_instructions: -1L, }, "max_instructions"),
      ({ ..d, max_match_work: -1L, }, "max_match_work"),
    ] {
    expect_sync_error(
      () => {
        let _ = prepare_signature(header, limits)
      },
      "InvalidOptions:" + field,
    )
  }
}
