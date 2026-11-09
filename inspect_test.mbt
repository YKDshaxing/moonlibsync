// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn inspect_error(
  f : () -> Unit raise @moonlibsync.SyncError,
  expected : String,
) -> Unit raise {
  let actual = try {
    f()
    "success"
  } catch {
    @moonlibsync.SyncError::InvalidOptions(s) => "InvalidOptions:" + s
    @moonlibsync.SyncError::UnsupportedSignatureProfile =>
      "UnsupportedSignatureProfile"
    @moonlibsync.SyncError::InvalidSignature => "InvalidSignature"
    @moonlibsync.SyncError::TruncatedInput => "TruncatedInput"
    @moonlibsync.SyncError::InvalidDelta => "InvalidDelta"
    @moonlibsync.SyncError::InvalidOpcode => "InvalidOpcode"
    @moonlibsync.SyncError::IntegerOutOfRange => "IntegerOutOfRange"
    @moonlibsync.SyncError::CopyOutOfBounds => "CopyOutOfBounds"
    @moonlibsync.SyncError::TrailingData => "TrailingData"
    @moonlibsync.SyncError::LimitExceeded => "LimitExceeded"
  }
  assert_eq(actual, expected)
}

///|
fn check_stats(
  s : @moonlibsync.DeltaSummary,
  bytes : Int64,
  instructions : Int64,
  literals : Int64,
  copies : Int64,
  literal_bytes : Int64,
  copy_bytes : Int64,
  output : Int64,
) -> Unit raise {
  assert_eq(s.delta_bytes, bytes)
  assert_eq(s.instruction_count, instructions)
  assert_eq(s.literal_commands, literals)
  assert_eq(s.copy_commands, copies)
  assert_eq(s.literal_bytes, literal_bytes)
  assert_eq(s.copy_bytes, copy_bytes)
  assert_eq(s.output_bytes, output)
}

///|
test "inspect public handwritten signature empty one and multiple records" {
  let header = b"\x72\x73\x01\x47\x00\x00\x08\x00\x00\x00\x00\x01"
  for
    (body, count, size) in [
      (b"", 0L, 12L),
      (b"\x80\x00\x00\x01\xff", 1L, 17L),
      (b"\x80\x00\x00\x01\xff\x00\x00\x00\x02\x00", 2L, 22L),
    ] {
    let s = @moonlibsync.inspect_signature(
      header + body,
      @moonlibsync.Limits::default(),
    )
    assert_eq(s.magic, 0x72730147U)
    assert_eq(s.block_len, 2048L)
    assert_eq(s.strong_sum_len, 1L)
    assert_eq(s.record_count, count)
    assert_eq(s.signature_bytes, size)
  }
}

///|
test "inspect public signature profiles malformed parameters and truncation" {
  let d = @moonlibsync.Limits::default()
  for
    (bytes, error) in [
      (b"", "TruncatedInput"),
      (
        b"\x72\x73\x01\x36\x00\x00\x00\x00\x00\x00\x00\x00", "UnsupportedSignatureProfile",
      ),
      (
        b"\x72\x73\x01\x37\x00\x00\x00\x01\x00\x00\x00\x01", "UnsupportedSignatureProfile",
      ),
      (
        b"\x72\x73\x01\x46\x00\x00\x00\x01\x00\x00\x00\x01", "UnsupportedSignatureProfile",
      ),
      (b"\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x01", "InvalidSignature"),
      (b"\x72\x73\x01\x47\x00\x00\x00\x00\x00\x00\x00\x01", "InvalidSignature"),
      (b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x21", "InvalidSignature"),
      (b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x00", "InvalidSignature"),
      (b"\x72\x73\x01\x47\x80\x00\x00\x00\x00\x00\x00\x01", "IntegerOutOfRange"),
      (
        b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x01\xff", "TruncatedInput",
      ),
    ] {
    inspect_error(
      () => {
        let _ = @moonlibsync.inspect_signature(bytes, d)
      },
      error,
    )
  }
}

///|
test "inspect public signature exact byte record and block budgets" {
  let d = @moonlibsync.Limits::default()
  let bytes = b"\x72\x73\x01\x47\x00\x00\x00\x02\x00\x00\x00\x01\x00\x00\x00\x00\x00"
  let exact = {
    ..d,
    max_signature_bytes: 17L,
    max_signature_records: 1L,
    max_block_bytes: 2L,
  }
  assert_eq(@moonlibsync.inspect_signature(bytes, exact).record_count, 1L)
  for
    limits in [
      { ..exact, max_signature_bytes: 16L, },
      { ..exact, max_signature_records: 0L, },
      { ..exact, max_block_bytes: 1L, },
    ] {
    inspect_error(
      () => {
        let _ = @moonlibsync.inspect_signature(bytes, limits)
      },
      "LimitExceeded",
    )
  }
  inspect_error(
    () => {
      let _ = @moonlibsync.inspect_signature(b"", { ..d, max_new_bytes: -1L, })
    },
    "InvalidOptions:max_new_bytes",
  )
  inspect_error(
    () => {
      let _ = @moonlibsync.inspect_signature(bytes, {
        ..d,
        max_signature_bytes: 0L,
      })
    },
    "LimitExceeded",
  )
}

///|
test "inspect public empty delta and zero budgets" {
  let d = {
    ..@moonlibsync.Limits::default(),
    max_delta_bytes: 5L,
    max_instructions: 0L,
    max_output_bytes: 0L,
  }
  check_stats(
    @moonlibsync.inspect_delta(b"\x72\x73\x02\x36\x00", d),
    5L,
    0L,
    0L,
    0L,
    0L,
    0L,
    0L,
  )
  let p = @moonlibsync.check_patch(0L, b"\x72\x73\x02\x36\x00", {
    ..d,
    max_old_bytes: 0L,
  })
  assert_eq(p.basis_bytes, 0L)
  check_stats(p.summary, 5L, 0L, 0L, 0L, 0L, 0L, 0L)
}

///|
test "inspect public direct and all extended literals include zero payload" {
  for
    header in [
      b"\x02", b"\x41\x02", b"\x42\x00\x02", b"\x43\x00\x00\x00\x02", b"\x44\x00\x00\x00\x00\x00\x00\x00\x02",
    ] {
    let bytes = b"\x72\x73\x02\x36" + header + b"\x00\x80\x00"
    check_stats(
      @moonlibsync.inspect_delta(bytes, @moonlibsync.Limits::default()),
      7L + header.length().to_int64(),
      1L,
      1L,
      0L,
      2L,
      0L,
      2L,
    )
  }
}

///|
test "inspect public mixed repeated nonsequential COPY statistics" {
  // COPY(4,2), literal(00 ff), COPY(0,4), COPY(1,3), COPY(0,4).
  let bytes = b"\x72\x73\x02\x36\x45\x04\x02\x02\x00\xff\x45\x00\x04\x45\x01\x03\x45\x00\x04\x00"
  let d = @moonlibsync.Limits::default()
  check_stats(
    @moonlibsync.inspect_delta(bytes, d),
    20L,
    5L,
    1L,
    4L,
    2L,
    13L,
    15L,
  )
  let result = @moonlibsync.check_patch(6L, bytes, d)
  assert_eq(result.basis_bytes, 6L)
  check_stats(result.summary, 20L, 5L, 1L, 4L, 2L, 13L, 15L)
}

///|
test "inspect public high unsigned offset is format valid but range invalid" {
  let d = @moonlibsync.Limits::default()
  for
    offset in [
      b"\x80\x00\x00\x00\x00\x00\x00\x00", b"\xff\xff\xff\xff\xff\xff\xff\xff",
    ] {
    let bytes = b"\x72\x73\x02\x36\x51" + offset + b"\x01\x00"
    check_stats(
      @moonlibsync.inspect_delta(bytes, d),
      15L,
      1L,
      0L,
      1L,
      0L,
      1L,
      1L,
    )
    inspect_error(
      () => {
        let _ = @moonlibsync.check_patch(2147483647L, bytes, {
          ..d,
          max_old_bytes: 2147483647L,
        })
      },
      "CopyOutOfBounds",
    )
  }
}

///|
test "inspect public complete parsing rejects malformed delta" {
  let d = @moonlibsync.Limits::default()
  for
    (bytes, error) in [
      (b"", "TruncatedInput"),
      (b"xxxx\x00", "InvalidDelta"),
      (b"\x72\x73\x02\x36\x55", "InvalidOpcode"),
      (b"\x72\x73\x02\x36\x01\x00", "TruncatedInput"),
      (b"\x72\x73\x02\x36\x42\x00", "TruncatedInput"),
      (b"\x72\x73\x02\x36\x45\x00", "TruncatedInput"),
      (b"\x72\x73\x02\x36\x02\xff", "TruncatedInput"),
      (b"\x72\x73\x02\x36\x00\x00", "TrailingData"),
      (b"\x72\x73\x02\x36\x41\x00\x00", "InvalidDelta"),
      (b"\x72\x73\x02\x36\x45\xff\x00\x00", "InvalidDelta"),
      (
        b"\x72\x73\x02\x36\x48\xff\xff\xff\xff\xff\xff\xff\xff\xff\x00", "LimitExceeded",
      ),
    ] {
    inspect_error(
      () => {
        let _ = @moonlibsync.inspect_delta(bytes, d)
      },
      error,
    )
    inspect_error(
      () => {
        let _ = @moonlibsync.check_patch(0L, bytes, d)
      },
      error,
    )
  }
}

///|
test "inspect public delta exact input instruction and output budgets" {
  let bytes = b"\x72\x73\x02\x36\x01\x00\x45\x00\x02\x00"
  let d = {
    ..@moonlibsync.Limits::default(),
    max_delta_bytes: 10L,
    max_instructions: 2L,
    max_output_bytes: 3L,
  }
  for
    limits in [
      d,
      { ..d, max_delta_bytes: 11L, max_instructions: 3L, max_output_bytes: 4L, },
    ] {
    check_stats(
      @moonlibsync.inspect_delta(bytes, limits),
      10L,
      2L,
      1L,
      1L,
      1L,
      2L,
      3L,
    )
    assert_eq(
      @moonlibsync.check_patch(2L, bytes, limits).summary.output_bytes,
      3L,
    )
  }
  for
    limits in [
      { ..d, max_delta_bytes: 9L, },
      { ..d, max_instructions: 1L, },
      { ..d, max_output_bytes: 2L, },
    ] {
    inspect_error(
      () => {
        let _ = @moonlibsync.inspect_delta(bytes, limits)
      },
      "LimitExceeded",
    )
    inspect_error(
      () => {
        let _ = @moonlibsync.check_patch(2L, bytes, limits)
      },
      "LimitExceeded",
    )
  }
  inspect_error(
    () => {
      let _ = @moonlibsync.inspect_delta(b"", { ..d, max_match_work: -1L, })
    },
    "InvalidOptions:max_match_work",
  )
}

///|
test "inspect public preflight validates configuration negative basis and budget first" {
  let d = @moonlibsync.Limits::default()
  inspect_error(
    () => {
      let _ = @moonlibsync.check_patch(-1L, b"", { ..d, max_old_bytes: -1L, })
    },
    "InvalidOptions:max_old_bytes",
  )
  for length in [-1L, -9223372036854775807L] {
    inspect_error(
      () => {
        let _ = @moonlibsync.check_patch(length, b"", d)
      },
      "InvalidOptions:basis_len",
    )
  }
  inspect_error(
    () => {
      let _ = @moonlibsync.check_patch(3L, b"", { ..d, max_old_bytes: 2L, })
    },
    "LimitExceeded",
  )
  inspect_error(
    () => {
      let _ = @moonlibsync.check_patch(9223372036854775807L, b"", d)
    },
    "LimitExceeded",
  )
}

///|
test "inspect public preflight exact end and out of bounds boundaries" {
  let d = { ..@moonlibsync.Limits::default(), max_old_bytes: 3L, }
  for
    (length, delta, error) in [
      (0L, b"\x72\x73\x02\x36\x45\x00\x01\x00", "CopyOutOfBounds"),
      (3L, b"\x72\x73\x02\x36\x45\x01\x03\x00", "CopyOutOfBounds"),
      (3L, b"\x72\x73\x02\x36\x45\x03\x01\x00", "CopyOutOfBounds"),
      (3L, b"\x72\x73\x02\x36\x45\x04\x01\x00", "CopyOutOfBounds"),
    ] {
    inspect_error(
      () => {
        let _ = @moonlibsync.check_patch(length, delta, d)
      },
      error,
    )
  }
  let p = @moonlibsync.check_patch(3L, b"\x72\x73\x02\x36\x45\x01\x02\x00", d)
  assert_eq(p.basis_bytes, 3L)
  check_stats(p.summary, 8L, 1L, 0L, 1L, 0L, 2L, 2L)
  inspect_error(
    () => {
      let _ = @moonlibsync.check_patch(4L, b"\x72\x73\x02\x36\x00", d)
    },
    "LimitExceeded",
  )
}

///|
test "inspect public full parse errors precede early invalid COPY then reusable" {
  let d = @moonlibsync.Limits::default()
  let prefix = b"\x72\x73\x02\x36\x45\xff\x01"
  for
    (suffix, error) in [
      (b"", "TruncatedInput"),
      (b"\x55", "InvalidOpcode"),
      (b"\x00\xff", "TrailingData"),
      (b"\x41\x00\x00", "InvalidDelta"),
    ] {
    inspect_error(
      () => {
        let _ = @moonlibsync.check_patch(0L, prefix + suffix, d)
      },
      error,
    )
  }
  check_stats(
    @moonlibsync.check_patch(1L, b"\x72\x73\x02\x36\x45\x00\x01\x00", d).summary,
    8L,
    1L,
    0L,
    1L,
    0L,
    1L,
    1L,
  )
}

///|
test "inspect public result ownership and input preservation across later calls" {
  let d = @moonlibsync.Limits::default()
  let sig = b"\x72\x73\x01\x47\x00\x00\x00\x02\x00\x00\x00\x01\xff\x00\x00\x00\x80"
  let ss = @moonlibsync.inspect_signature(sig, d)
  let input = b"\x72\x73\x02\x36\x01\x00\x00"
  let s = @moonlibsync.inspect_delta(input, d)
  let p = @moonlibsync.check_patch(0L, input, d)
  let _ = @moonlibsync.inspect_delta(b"\x72\x73\x02\x36\x45\xff\x01\x00", d)
  inspect_error(
    () => {
      let _ = @moonlibsync.check_patch(0L, b"", d)
    },
    "TruncatedInput",
  )
  assert_eq(input, b"\x72\x73\x02\x36\x01\x00\x00")
  let _ = @moonlibsync.inspect_signature(
    b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x20", d,
  )
  assert_eq(
    sig, b"\x72\x73\x01\x47\x00\x00\x00\x02\x00\x00\x00\x01\xff\x00\x00\x00\x80",
  )
  assert_eq(ss.magic, 0x72730147U)
  assert_eq(ss.block_len, 2L)
  assert_eq(ss.strong_sum_len, 1L)
  assert_eq(ss.record_count, 1L)
  assert_eq(ss.signature_bytes, 17L)
  check_stats(s, 7L, 1L, 1L, 0L, 1L, 0L, 1L)
  check_stats(p.summary, 7L, 1L, 1L, 0L, 1L, 0L, 1L)
}
