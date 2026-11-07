// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// All wire fixtures below are handwritten. No signature encoder is used.
fn expect_signature_error(
  input : BytesView,
  limits : Limits,
  expected : String,
) -> Unit raise {
  expect_sync_error(
    () => {
      let _ = parse_signature(input, limits)
    },
    expected,
  )
}

///|
test "signature accepts header-only input without inferring a basis length" {
  let input = b"\x72\x73\x01\x47\x00\x00\x08\x00\x00\x00\x00\x10"
  let sig = parse_signature(input, Limits::default())
  assert_eq(sig.magic, 0x72730147U)
  assert_eq(sig.block_len, 2048)
  assert_eq(sig.strong_sum_len, 16)
  assert_eq(sig.records.length(), 0)
}

///|
test "signature reads one record with a 16-byte strong sum and unsigned weak sum" {
  let input = b"\x72\x73\x01\x47\x00\x00\x08\x00\x00\x00\x00\x10\x80\x00\x00\x00\x00\x80\xff\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d"
  let sig = parse_signature(input, Limits::default())
  assert_eq(sig.block_len, 2048)
  assert_eq(sig.strong_sum_len, 16)
  assert_eq(sig.records.length(), 1)
  let record = sig.records[0]
  assert_eq(record.block_index, 0)
  assert_eq(record.nominal_offset, 0UL)
  assert_eq(record.weak_sum, 0x80000000U)
  assert_eq(
    record.strong_sum,
    b"\x00\x80\xff\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d",
  )
}

///|
test "signature retains record order duplicates and all unsigned weak bits" {
  // block_len=7, strong_sum_len=1; weak values 0, 0x80000000, max, max.
  let input = b"\x72\x73\x01\x47\x00\x00\x00\x07\x00\x00\x00\x01\x00\x00\x00\x00\x00\x80\x00\x00\x00\x80\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"
  let sig = parse_signature(input, Limits::default())
  assert_eq(sig.block_len, 7)
  assert_eq(sig.strong_sum_len, 1)
  assert_eq(sig.records.length(), 4)
  let expected_weak = [0U, 0x80000000U, 0xffffffffU, 0xffffffffU]
  let expected_strong = [b"\x00", b"\x80", b"\xff", b"\xff"]
  let expected_offsets = [0UL, 7UL, 14UL, 21UL]
  for i in 0..<4 {
    assert_eq(sig.records[i].block_index, i)
    assert_eq(sig.records[i].nominal_offset, expected_offsets[i])
    assert_eq(sig.records[i].weak_sum, expected_weak[i])
    assert_eq(sig.records[i].strong_sum, expected_strong[i])
  }
}

///|
test "signature parses maximum strong length from a nonzero input view" {
  let input = b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x20\xff\xff\xff\xff\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\xfe\xff"
  let padded = b"\xaa\xbb" + input + b"\xcc"
  let sig = parse_signature(padded[2:padded.length() - 1], Limits::default())
  assert_eq(sig.strong_sum_len, 32)
  assert_eq(sig.records.length(), 1)
  assert_eq(sig.records[0].weak_sum, 0xffffffffU)
  assert_eq(
    sig.records[0].strong_sum,
    b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\xfe\xff",
  )
}

///|
test "signature requires a full header before classifying any magic" {
  let supported = b"\x72\x73\x01\x47\x00\x00\x00\x07\x00\x00\x00\x01"
  let known = b"\x72\x73\x01\x36\x00\x00\x00\x00\x00\x00\x00\x00"
  let unknown = b"\xde\xad\xbe\xef\x00\x00\x00\x00\x00\x00\x00\x00"
  for len in 0..<12 {
    expect_signature_error(
      supported[0:len],
      Limits::default(),
      "TruncatedInput",
    )
    expect_signature_error(known[0:len], Limits::default(), "TruncatedInput")
    expect_signature_error(unknown[0:len], Limits::default(), "TruncatedInput")
  }
}

///|
test "signature classifies known profiles unknown magic and delta magic" {
  let rest = b"\x00\x00\x00\x01\x00\x00\x00\x01"
  for magic in [b"\x72\x73\x01\x36", b"\x72\x73\x01\x37", b"\x72\x73\x01\x46"] {
    expect_signature_error(
      magic + rest,
      Limits::default(),
      "UnsupportedSignatureProfile",
    )
  }
  for
    magic in [
      b"\xde\xad\xbe\xef", b"\x72\x73\x02\x36", b"\x72\x73\x01\x48", b"\x00\x00\x00\x00",
    ] {
    expect_signature_error(magic + rest, Limits::default(), "InvalidSignature")
  }
}

///|
test "signature rejects zero block length and invalid strong lengths as format errors" {
  let magic = b"\x72\x73\x01\x47"
  expect_signature_error(
    magic + b"\x00\x00\x00\x00\x00\x00\x00\x01",
    Limits::default(),
    "InvalidSignature",
  )
  for strong in [b"\x00\x00\x00\x00", b"\x00\x00\x00\x21", b"\xff\xff\xff\xff"] {
    expect_signature_error(
      magic + b"\x00\x00\x00\x01" + strong,
      Limits::default(),
      "InvalidSignature",
    )
  }
}

///|
test "signature rejects every partial weak and strong record without dropping tail bytes" {
  let header = b"\x72\x73\x01\x47\x00\x00\x00\x07\x00\x00\x00\x10"
  let record = b"\x80\x00\x00\x00\x00\x80\xff\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d"
  for tail_len in 1..<20 {
    let tail = record[0:tail_len].to_owned()
    expect_signature_error(header + tail, Limits::default(), "TruncatedInput")
    expect_signature_error(
      header + record + tail,
      Limits::default(),
      "TruncatedInput",
    )
  }
}

///|
test "signature enforces byte budget below at and above the input length" {
  // Exactly 17 bytes, one strong-byte record.
  let input = b"\x72\x73\x01\x47\x00\x00\x00\x07\x00\x00\x00\x01\xff\xff\xff\xff\x80"
  let d = Limits::default()
  expect_signature_error(
    input,
    { ..d, max_signature_bytes: 16L, },
    "LimitExceeded",
  )
  for budget in [17L, 18L] {
    let sig = parse_signature(input, { ..d, max_signature_bytes: budget, })
    assert_eq(sig.records.length(), 1)
  }
  expect_signature_error(
    input,
    { ..d, max_signature_bytes: 0L, },
    "LimitExceeded",
  )
}

///|
test "signature enforces record budget and accepts a zero-record budget" {
  let input = b"\x72\x73\x01\x47\x00\x00\x00\x07\x00\x00\x00\x01\x00\x00\x00\x00\x00\xff\xff\xff\xff\xff"
  let d = Limits::default()
  expect_signature_error(
    input,
    { ..d, max_signature_records: 1L, },
    "LimitExceeded",
  )
  for budget in [2L, 3L] {
    let sig = parse_signature(input, { ..d, max_signature_records: budget, })
    assert_eq(sig.records.length(), 2)
  }
  let header = input[0:12]
  let sig = parse_signature(header, { ..d, max_signature_records: 0L, })
  assert_eq(sig.records.length(), 0)
  expect_signature_error(
    input[0:17],
    { ..d, max_signature_records: 0L, },
    "LimitExceeded",
  )
}

///|
test "signature checks block representability then the block budget" {
  let header = b"\x72\x73\x01\x47\x00\x00\x00\x07\x00\x00\x00\x01"
  let d = Limits::default()
  expect_signature_error(header, { ..d, max_block_bytes: 6L, }, "LimitExceeded")
  for budget in [7L, 8L] {
    assert_eq(
      parse_signature(header, { ..d, max_block_bytes: budget, }).block_len,
      7,
    )
  }
  let max_header = b"\x72\x73\x01\x47\x7f\xff\xff\xff\x00\x00\x00\x01"
  let large = { ..d, max_block_bytes: 2147483647L, }
  assert_eq(parse_signature(max_header, large).block_len, 2147483647)
  for block in [b"\x80\x00\x00\x00", b"\xff\xff\xff\xff"] {
    let input = b"\x72\x73\x01\x47" + block + b"\x00\x00\x00\x01"
    expect_signature_error(input, large, "IntegerOutOfRange")
    expect_signature_error(input, d, "IntegerOutOfRange")
  }
}

///|
test "signature preserves wide nominal offsets without applying unrelated limits" {
  let input = b"\x72\x73\x01\x47\x7f\xff\xff\xff\x00\x00\x00\x01\x00\x00\x00\x00\x00\x80\x00\x00\x00\x80\xff\xff\xff\xff\xff"
  let d = Limits::default()
  let sig = parse_signature(input, {
    ..d,
    max_block_bytes: 2147483647L,
    max_old_bytes: 0L,
    max_new_bytes: 0L,
    max_delta_bytes: 0L,
    max_output_bytes: 0L,
    max_instructions: 0L,
    max_match_work: 0L,
  })
  assert_eq(sig.records.length(), 3)
  assert_eq(sig.records[0].nominal_offset, 0UL)
  assert_eq(sig.records[1].nominal_offset, 2147483647UL)
  assert_eq(sig.records[2].nominal_offset, 4294967294UL)
}

///|
test "signature error precedence is fixed for competing invalid conditions" {
  let d = Limits::default()
  let bad_options = { ..d, max_old_bytes: -1L, max_signature_bytes: 0L, }
  expect_signature_error(b"\xff", bad_options, "InvalidOptions:max_old_bytes")
  expect_signature_error(
    b"\xff",
    { ..d, max_signature_bytes: 0L, },
    "LimitExceeded",
  )
  let unsupported_bad_fields = b"\x72\x73\x01\x36\x00\x00\x00\x00\xff\xff\xff\xff\x01"
  expect_signature_error(
    unsupported_bad_fields, d, "UnsupportedSignatureProfile",
  )
  let unknown_bad_fields = b"\xde\xad\xbe\xef\x00\x00\x00\x00\xff\xff\xff\xff\x01"
  expect_signature_error(unknown_bad_fields, d, "InvalidSignature")
  let bad_fields_tail = b"\x72\x73\x01\x47\x00\x00\x00\x00\x00\x00\x00\x21\x01"
  expect_signature_error(bad_fields_tail, d, "InvalidSignature")
  let range_tail = b"\x72\x73\x01\x47\xff\xff\xff\xff\x00\x00\x00\x01\x01"
  expect_signature_error(range_tail, d, "TruncatedInput")
  let limited_tail = b"\x72\x73\x01\x47\x00\x00\x00\x07\x00\x00\x00\x01\x01"
  expect_signature_error(
    limited_tail,
    { ..d, max_block_bytes: 6L, max_signature_records: 0L, },
    "TruncatedInput",
  )
}

///|
test "signature repeated failures do not leak state into the next valid parse" {
  let good = b"\x72\x73\x01\x47\x00\x00\x00\x07\x00\x00\x00\x01\xff\xff\xff\xff\x80"
  for _ in 0..<5 {
    expect_signature_error(good[0:11], Limits::default(), "TruncatedInput")
    expect_signature_error(good[0:16], Limits::default(), "TruncatedInput")
    let sig = parse_signature(good, Limits::default())
    assert_eq(sig.records.length(), 1)
    assert_eq(sig.records[0].block_index, 0)
    assert_eq(sig.records[0].nominal_offset, 0UL)
    assert_eq(sig.records[0].weak_sum, 0xffffffffU)
    assert_eq(sig.records[0].strong_sum, b"\x80")
  }
}
