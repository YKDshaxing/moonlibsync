// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "strongsum complete independent vectors and every legal prefix" {
  for (input, expected) in strong_reference_vectors() {
    assert_eq(strong_sum(input, 32), expected)
    for len in 1..<=32 {
      let actual = strong_sum(input, len)
      assert_eq(actual.length(), len)
      assert_eq(actual, expected[0:len].to_owned())
    }
  }
}

///|
test "strongsum rejects invalid lengths before slicing and permits later valid calls" {
  for len in [-2147483648, -1, 0, 33, 2147483647] {
    expect_sync_error(
      () => {
        let _ = strong_sum(b"\x00\xff", len)
      },
      "InvalidOptions:strong_sum_len",
    )
    let (input, expected) = strong_reference_vectors()[0]
    assert_eq(strong_sum(input, 32), expected)
  }
}

///|
test "strongsum respects view boundaries and returns stable independent results" {
  for (input, expected) in strong_reference_vectors() {
    let padded = b"\xaa\xbb" + input + b"\xcc\xdd"
    let saved = strong_sum(padded[2:padded.length() - 2], 16)
    assert_eq(saved, expected[0:16].to_owned())
    let before = b"\xaa\xbb" + input + b"\xcc\xdd"
    let _ = strong_sum(b"another input\x00\x80\xff", 1)
    let _ = strong_sum(input, 32)
    assert_eq(saved, expected[0:16].to_owned())
    assert_eq(padded, before)
    assert_eq(strong_sum(input, 16), saved)
  }
}

///|
test "strongsum distinguishes wrong algorithms and wrong digest length parameters" {
  // All vectors include empty, short and 128-byte compression block boundaries.
  for (input, expected) in strong_reference_vectors() {
    assert_eq(strong_sum(input, 32), expected)
    assert_true(
      @blake2.hash(input, kind=Blake2b, len=64)[0:32].to_owned() != expected,
    )
    assert_true(@blake2.hash(input, kind=Blake2s, len=32) != expected)
    for len in [1, 16] {
      assert_true(
        @blake2.hash(input, kind=Blake2b, len~) != expected[0:len].to_owned(),
      )
    }
  }
}

///|
test "strongsum matches all actual rdiff records without padding tail blocks" {
  let bases = reference_bases()
  let signatures = reference_signatures()
  assert_eq(bases.length(), signatures.length())
  for i in 0..<bases.length() {
    let (id, basis) = bases[i]
    let (sig_id, input) = signatures[i]
    assert_eq(id, sig_id)
    let sig = parse_signature(input, Limits::default())
    let mut pos = 0
    for record in sig.records {
      let remaining = basis.length() - pos
      let size = if remaining < sig.block_len {
        remaining
      } else {
        sig.block_len
      }
      assert_eq(
        strong_sum(basis[pos:pos + size], sig.strong_sum_len),
        record.strong_sum,
      )
      pos = pos + size
    }
    assert_eq(pos, basis.length())
    if basis.length() == 0 {
      assert_eq(sig.records.length(), 0)
    }
  }
}
