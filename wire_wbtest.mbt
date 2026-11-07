// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// All expected bytes are handwritten, not produced by the wire writers.
fn u32_vectors() -> Array[(UInt32, Bytes)] {
  [
    (0U, b"\x00\x00\x00\x00"),
    (1U, b"\x00\x00\x00\x01"),
    (0x7fffffffU, b"\x7f\xff\xff\xff"),
    (0x80000000U, b"\x80\x00\x00\x00"),
    (0xffffffffU, b"\xff\xff\xff\xff"),
    (0x01234567U, b"\x01\x23\x45\x67"),
  ]
}

///|
fn u64_vectors() -> Array[(UInt64, Bytes)] {
  [
    (0UL, b"\x00\x00\x00\x00\x00\x00\x00\x00"),
    (1UL, b"\x00\x00\x00\x00\x00\x00\x00\x01"),
    (0x00000000ffffffffUL, b"\x00\x00\x00\x00\xff\xff\xff\xff"),
    (0x0000000100000000UL, b"\x00\x00\x00\x01\x00\x00\x00\x00"),
    (0x7fffffffffffffffUL, b"\x7f\xff\xff\xff\xff\xff\xff\xff"),
    (0x8000000000000000UL, b"\x80\x00\x00\x00\x00\x00\x00\x00"),
    (0xffffffffffffffffUL, b"\xff\xff\xff\xff\xff\xff\xff\xff"),
    (0x0123456789abcdefUL, b"\x01\x23\x45\x67\x89\xab\xcd\xef"),
  ]
}

///|
/// Shared test assertion uses the actual error variant, not error text output.
fn sync_error_tag(error : SyncError) -> String {
  match error {
    InvalidOptions(field) => "InvalidOptions:" + field
    UnsupportedSignatureProfile => "UnsupportedSignatureProfile"
    TruncatedInput => "TruncatedInput"
    InvalidSignature => "InvalidSignature"
    InvalidDelta => "InvalidDelta"
    InvalidOpcode => "InvalidOpcode"
    IntegerOutOfRange => "IntegerOutOfRange"
    CopyOutOfBounds => "CopyOutOfBounds"
    TrailingData => "TrailingData"
    LimitExceeded => "LimitExceeded"
  }
}

///|
fn expect_sync_error(
  action : () -> Unit raise SyncError,
  expected : String,
) -> Unit raise {
  let actual = try {
    action()
    "success"
  } catch {
    error => sync_error_tag(error)
  }
  assert_eq(actual, expected)
}

///|
test "wire u32 reads match handwritten bytes at zero and nonzero view offsets" {
  for (expected, bytes) in u32_vectors() {
    assert_eq(read_u32_be(bytes, 0L), expected)
    let outer = b"\x55\xaa\xbb" + bytes + b"\xcc\x66"
    assert_eq(read_u32_be(outer[1:outer.length() - 1], 2L), expected)
  }
}

///|
test "wire u32 writes match handwritten bytes and preserve surrounding bytes" {
  for (value, expected) in u32_vectors() {
    let output = FixedArray::make(4, b'\xa5')
    write_u32_be(output, 0L, value)
    assert_eq(Bytes::from_array(output[:]), expected)
    let padded = FixedArray::make(8, b'\xa5')
    write_u32_be(padded, 2L, value)
    assert_eq(
      Bytes::from_array(padded[:]),
      b"\xa5\xa5" + expected + b"\xa5\xa5",
    )
  }
}

///|
test "wire u64 reads preserve all 64 bits from handwritten bytes" {
  for (expected, bytes) in u64_vectors() {
    assert_eq(read_u64_be(bytes, 0L), expected)
    let outer = b"\x55\xaa\xbb" + bytes + b"\xcc\x66"
    assert_eq(read_u64_be(outer[1:outer.length() - 1], 2L), expected)
  }
}

///|
test "wire u64 writes match handwritten bytes and preserve surrounding bytes" {
  for (value, expected) in u64_vectors() {
    let output = FixedArray::make(8, b'\xa5')
    write_u64_be(output, 0L, value)
    assert_eq(Bytes::from_array(output[:]), expected)
    let padded = FixedArray::make(12, b'\xa5')
    write_u64_be(padded, 2L, value)
    assert_eq(
      Bytes::from_array(padded[:]),
      b"\xa5\xa5" + expected + b"\xa5\xa5",
    )
  }
}

///|
test "wire reads reject truncation at every byte and invalid positions" {
  let full32 = b"\x12\x34\x56\x78"
  for remain in 0..<4 {
    expect_sync_error(
      () => {
        let _ = read_u32_be(full32[0:remain], 0L)
      },
      "TruncatedInput",
    )
    let padded = b"\xaa\xbb" + full32[0:remain].to_owned()
    expect_sync_error(
      () => {
        let _ = read_u32_be(padded, 2L)
      },
      "TruncatedInput",
    )
  }
  let full64 = b"\x01\x23\x45\x67\x89\xab\xcd\xef"
  for remain in 0..<8 {
    expect_sync_error(
      () => {
        let _ = read_u64_be(full64[0:remain], 0L)
      },
      "TruncatedInput",
    )
    let padded = b"\xaa\xbb" + full64[0:remain].to_owned()
    expect_sync_error(
      () => {
        let _ = read_u64_be(padded, 2L)
      },
      "TruncatedInput",
    )
  }
  for offset in [-1L, 9L, 2147483647L, 2147483648L, 9223372036854775807L] {
    expect_sync_error(
      () => {
        let _ = read_u32_be(full64, offset)
      },
      "IntegerOutOfRange",
    )
    expect_sync_error(
      () => {
        let _ = read_u64_be(full64, offset)
      },
      "IntegerOutOfRange",
    )
  }
  expect_sync_error(
    () => {
      let _ = read_u32_be(full64, 8L)
    },
    "TruncatedInput",
  )
  expect_sync_error(
    () => {
      let _ = read_u64_be(full64, 8L)
    },
    "TruncatedInput",
  )
}

///|
test "wire failed writes leave all bytes untouched" {
  for prefix in [0, 2] {
    for remain in 0..<8 {
      let output = FixedArray::make(remain + prefix, b'\xa5')
      expect_sync_error(
        () => write_u64_be(output, prefix.to_int64(), 0xffffffffffffffffUL),
        "TruncatedInput",
      )
      if remain < 4 {
        expect_sync_error(
          () => write_u32_be(output, prefix.to_int64(), 0xffffffffU),
          "TruncatedInput",
        )
      }
      for byte in output {
        assert_eq(byte, b'\xa5')
      }
    }
  }
  let output = FixedArray::make(12, b'\xa5')
  for offset in [-1L, 13L, 2147483647L, 2147483648L, 9223372036854775807L] {
    expect_sync_error(
      () => write_u32_be(output, offset, 0xffffffffU),
      "IntegerOutOfRange",
    )
    expect_sync_error(
      () => write_u64_be(output, offset, 0xffffffffffffffffUL),
      "IntegerOutOfRange",
    )
    for byte in output {
      assert_eq(byte, b'\xa5')
    }
  }
}

///|
test "wire index conversion checks the unsigned bound before narrowing" {
  assert_eq(checked_index(0UL), 0)
  assert_eq(checked_index(2147483647UL), 2147483647)
  for
    value in [
      2147483648UL, 0xffffffffUL, 0x8000000000000000UL, 0xffffffffffffffffUL,
    ] {
    expect_sync_error(
      () => {
        let _ = checked_index(value)
      },
      "IntegerOutOfRange",
    )
  }
}

///|
test "wire span arithmetic checks subtraction boundaries without huge buffers" {
  assert_eq(checked_wire_span(0, 0L, 0), 0)
  assert_eq(checked_wire_span(2147483647, 2147483643L, 4), 2147483643)
  assert_eq(checked_wire_span(2147483647, 2147483647L, 0), 2147483647)
  expect_sync_error(
    () => {
      let _ = checked_wire_span(2147483647, 2147483644L, 4)
    },
    "TruncatedInput",
  )
  expect_sync_error(
    () => {
      let _ = checked_wire_span(2147483647, 2147483647L, 1)
    },
    "TruncatedInput",
  )
  expect_sync_error(
    () => {
      let _ = checked_wire_span(1, 1L, 2147483647)
    },
    "TruncatedInput",
  )
  expect_sync_error(
    () => {
      let _ = checked_wire_span(-1, 0L, 4)
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = checked_wire_span(1, 0L, -1)
    },
    "IntegerOutOfRange",
  )
}

///|
test "wire nominal block multiplication checks the full UInt64 boundary" {
  assert_eq(checked_block_offset(0UL, 0xffffffffffffffffUL), 0UL)
  assert_eq(checked_block_offset(0xffffffffffffffffUL, 0UL), 0UL)
  assert_eq(
    checked_block_offset(0xffffffffffffffffUL, 1UL),
    0xffffffffffffffffUL,
  )
  assert_eq(
    checked_block_offset(0x5555555555555555UL, 3UL),
    0xffffffffffffffffUL,
  )
  assert_eq(
    checked_block_offset(0xffffffffUL, 0xffffffffUL),
    0xfffffffe00000001UL,
  )
  expect_sync_error(
    () => {
      let _ = checked_block_offset(0x5555555555555556UL, 3UL)
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = checked_block_offset(0x8000000000000000UL, 2UL)
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = checked_block_offset(0x100000000UL, 0x100000000UL)
    },
    "IntegerOutOfRange",
  )
}
