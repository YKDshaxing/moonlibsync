// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn expect_patch_error(
  basis : Bytes,
  delta : Bytes,
  limits : @moonlibsync.Limits,
  expected : String,
) -> Unit raise {
  let actual = try {
    let _ = @moonlibsync.patch(basis, delta, limits)
    "success"
  } catch {
    @moonlibsync.SyncError::InvalidOptions(field) => "InvalidOptions:" + field
    @moonlibsync.SyncError::TruncatedInput => "TruncatedInput"
    @moonlibsync.SyncError::InvalidDelta => "InvalidDelta"
    @moonlibsync.SyncError::InvalidOpcode => "InvalidOpcode"
    @moonlibsync.SyncError::CopyOutOfBounds => "CopyOutOfBounds"
    @moonlibsync.SyncError::TrailingData => "TrailingData"
    @moonlibsync.SyncError::LimitExceeded => "LimitExceeded"
    _ => "unexpected error variant"
  }
  assert_eq(actual, expected)
}

///|
test "public patch README example empty result and pure COPY" {
  let limits = @moonlibsync.Limits::default()
  // Same complete, handwritten standard delta as the README example.
  assert_eq(
    @moonlibsync.patch(b"abc", b"\x72\x73\x02\x36\x45\x00\x03\x00", limits),
    b"abc",
  )
  assert_eq(
    @moonlibsync.patch(b"abcdef", b"\x72\x73\x02\x36\x45\x01\x03\x00", limits),
    b"bcd",
  )
  for basis in [b"", b"abc"] {
    assert_eq(
      @moonlibsync.patch(basis, b"\x72\x73\x02\x36\x00", {
        ..limits,
        max_old_bytes: 3L,
        max_delta_bytes: 5L,
        max_instructions: 0L,
        max_output_bytes: 0L,
      }),
      b"",
    )
  }
}

///|
test "public patch literal and mixed binary output match independent bytes" {
  let limits = @moonlibsync.Limits::default()
  assert_eq(
    @moonlibsync.patch(b"", b"\x72\x73\x02\x36\x03\x00\x80\xff\x00", limits),
    b"\x00\x80\xff",
  )
  assert_eq(
    @moonlibsync.patch(
      b"\x00\x80\xffAB", b"\x72\x73\x02\x36\x02\xff\x00\x45\x01\x03\x01\x80\x45\x00\x01\x00",
      limits,
    ),
    b"\xff\x00\x80\xffA\x80\x00",
  )
  for
    header in [
      b"\x41\x02", b"\x42\x00\x02", b"\x43\x00\x00\x00\x02", b"\x44\x00\x00\x00\x00\x00\x00\x00\x02",
    ] {
    assert_eq(
      @moonlibsync.patch(
        b"",
        b"\x72\x73\x02\x36" + header + b"\x00\x80\x00",
        limits,
      ),
      b"\x00\x80",
    )
  }
  // A delta carries no basis identity: in-range bytes from another basis apply.
  assert_eq(
    @moonlibsync.patch(b"xyz", b"\x72\x73\x02\x36\x45\x00\x03\x00", limits),
    b"xyz",
  )
}

///|
test "public patch nonsequential repeated overlapping basis regions" {
  assert_eq(
    @moonlibsync.patch(
      b"abcdef",
      b"\x72\x73\x02\x36\x45\x04\x02\x45\x00\x04\x45\x01\x03\x45\x00\x04\x00",
      @moonlibsync.Limits::default(),
    ),
    b"efabcdbcdabcd",
  )
}

///|
test "public patch executes all sixteen standard COPY width pairs" {
  // Handwritten input bytes copied from the independently checked opcode data.
  for
    delta in [
      b"\x72\x73\x02\x36\x45\x02\x03\x00", b"\x72\x73\x02\x36\x46\x02\x00\x03\x00",
      b"\x72\x73\x02\x36\x47\x02\x00\x00\x00\x03\x00", b"\x72\x73\x02\x36\x48\x02\x00\x00\x00\x00\x00\x00\x00\x03\x00",
      b"\x72\x73\x02\x36\x49\x00\x02\x03\x00", b"\x72\x73\x02\x36\x4a\x00\x02\x00\x03\x00",
      b"\x72\x73\x02\x36\x4b\x00\x02\x00\x00\x00\x03\x00", b"\x72\x73\x02\x36\x4c\x00\x02\x00\x00\x00\x00\x00\x00\x00\x03\x00",
      b"\x72\x73\x02\x36\x4d\x00\x00\x00\x02\x03\x00", b"\x72\x73\x02\x36\x4e\x00\x00\x00\x02\x00\x03\x00",
      b"\x72\x73\x02\x36\x4f\x00\x00\x00\x02\x00\x00\x00\x03\x00", b"\x72\x73\x02\x36\x50\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x03\x00",
      b"\x72\x73\x02\x36\x51\x00\x00\x00\x00\x00\x00\x00\x02\x03\x00", b"\x72\x73\x02\x36\x52\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00",
      b"\x72\x73\x02\x36\x53\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x03\x00",
      b"\x72\x73\x02\x36\x54\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x03\x00",
    ] {
    assert_eq(
      @moonlibsync.patch(b"abcdef", delta, @moonlibsync.Limits::default()),
      b"cde",
    )
  }
}

///|
test "public patch preserves exact delta format errors" {
  let limits = @moonlibsync.Limits::default()
  for
    (delta, expected) in [
      (b"\xff\xff\xff\xff\x00", "InvalidDelta"),
      (b"\x72\x73\x02\x36\xff\x00", "InvalidOpcode"),
      (b"\x72\x73\x02\x36\x45\x00", "TruncatedInput"),
      (b"\x72\x73\x02\x36\x44\x00\x00", "TruncatedInput"),
      (b"\x72\x73\x02\x36\x02\xff", "TruncatedInput"),
      (b"\x72\x73\x02\x36\x41\x00\x00", "InvalidDelta"),
      (b"\x72\x73\x02\x36\x45\xff\x00\x00", "InvalidDelta"),
      (b"\x72\x73\x02\x36", "TruncatedInput"),
      (b"\x72\x73\x02\x36\x01\xff", "TruncatedInput"),
      (b"\x72\x73\x02\x36\x00\x00", "TrailingData"),
      (b"\x72\x73\x02\x36\x00\x72\x73\x02\x36\x00", "TrailingData"),
    ] {
    expect_patch_error(b"abc", delta, limits, expected)
  }
}

///|
test "public patch rejects unsigned COPY ranges and references into grown output" {
  let limits = @moonlibsync.Limits::default()
  for
    (basis, delta) in [
      (b"ab", b"\x72\x73\x02\x36\x45\x03\x01\x00"),
      (b"ab", b"\x72\x73\x02\x36\x45\x02\x01\x00"),
      (b"ab", b"\x72\x73\x02\x36\x45\x01\x02\x00"),
      (b"", b"\x72\x73\x02\x36\x45\x00\x01\x00"),
      (b"ab", b"\x72\x73\x02\x36\x51\x80\x00\x00\x00\x00\x00\x00\x00\x01\x00"),
      (b"ab", b"\x72\x73\x02\x36\x51\xff\xff\xff\xff\xff\xff\xff\xff\x01\x00"),
      (b"ab", b"\x72\x73\x02\x36\x4d\xff\xff\xff\xff\x01\x00"),
      (b"ab", b"\x72\x73\x02\x36\x03XYZ\x45\x02\x01\x00"),
      (b"ab", b"\x72\x73\x02\x36\x45\x00\x02\x45\x02\x01\x00"),
    ] {
    expect_patch_error(basis, delta, limits, "CopyOutOfBounds")
  }
}

///|
test "public patch budget boundaries and competing errors follow staged checks" {
  let d = @moonlibsync.Limits::default()
  let delta = b"\x72\x73\x02\x36\x01X\x45\x00\x02\x00"
  let exact = {
    ..d,
    max_old_bytes: 2L,
    max_delta_bytes: 10L,
    max_instructions: 2L,
    max_output_bytes: 3L,
    max_new_bytes: 0L,
    max_match_work: 0L,
  }
  assert_eq(@moonlibsync.patch(b"ab", delta, exact), b"Xab")
  for
    limits in [
      { ..exact, max_old_bytes: 1L, },
      { ..exact, max_delta_bytes: 9L, },
      { ..exact, max_instructions: 1L, },
      { ..exact, max_output_bytes: 2L, },
    ] {
    expect_patch_error(b"ab", delta, limits, "LimitExceeded")
  }
  // Invalid configuration precedes basis budget, which precedes delta format.
  expect_patch_error(
    b"ab",
    b"\xff",
    { ..d, max_old_bytes: -1L, },
    "InvalidOptions:max_old_bytes",
  )
  expect_patch_error(
    b"ab",
    b"\xff",
    { ..d, max_old_bytes: 1L, },
    "LimitExceeded",
  )
  expect_patch_error(
    b"ab",
    b"\xff",
    { ..d, max_old_bytes: 2L, },
    "TruncatedInput",
  )
  expect_patch_error(
    b"ab",
    b"\xff\xff\xff\xff",
    { ..d, max_old_bytes: 2L, },
    "InvalidDelta",
  )
  // Complete parse precedes COPY validation even when an earlier COPY is bad.
  expect_patch_error(
    b"ab", b"\x72\x73\x02\x36\x45\xff\x01\x00\xff", d, "TrailingData",
  )
  expect_patch_error(
    b"ab", b"\x72\x73\x02\x36\x45\xff\x01\x01", d, "TruncatedInput",
  )
  expect_patch_error(
    b"ab", b"\x72\x73\x02\x36\x45\xff\x01\x55", d, "InvalidOpcode",
  )
  for
    length in [
      b"\x80\x00\x00\x00\x00\x00\x00\x00", b"\xff\xff\xff\xff\xff\xff\xff\xff",
    ] {
    expect_patch_error(
      b"ab",
      b"\x72\x73\x02\x36\x48\x00" + length + b"\x00",
      d,
      "LimitExceeded",
    )
  }
  expect_patch_error(
    b"ab",
    b"\x72\x73\x02\x36\x45\xff\x02\x00",
    { ..d, max_output_bytes: 1L, },
    "LimitExceeded",
  )
}

///|
test "public patch input immutability failure recovery and interleaved calls" {
  let limits = @moonlibsync.Limits::default()
  let basis = b"\x00\x80\xffabc"
  let good = b"\x72\x73\x02\x36\x45\x00\x03\x01X\x00"
  let bad = b"\x72\x73\x02\x36\x01Y\x45\x06\x01\x00"
  let first = @moonlibsync.patch(basis, good, limits)
  assert_eq(first, b"\x00\x80\xffX")
  for _ in 0..<5 {
    expect_patch_error(basis, bad, limits, "CopyOutOfBounds")
    expect_patch_error(
      basis, b"\x72\x73\x02\x36\x01X", limits, "TruncatedInput",
    )
    assert_eq(
      @moonlibsync.patch(b"xy", b"\x72\x73\x02\x36\x45\x01\x01\x00", limits),
      b"y",
    )
    assert_eq(@moonlibsync.patch(basis, good, limits), first)
    assert_eq(first, b"\x00\x80\xffX")
    assert_eq(basis, b"\x00\x80\xffabc")
    assert_eq(good, b"\x72\x73\x02\x36\x45\x00\x03\x01X\x00")
    assert_eq(bad, b"\x72\x73\x02\x36\x01Y\x45\x06\x01\x00")
  }
}
