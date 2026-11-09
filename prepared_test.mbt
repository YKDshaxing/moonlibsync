// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn prepared_error(
  bytes : Bytes,
  limits : @moonlibsync.Limits,
  expected : String,
) -> Unit raise {
  inspect_error(
    () => {
      let _ = @moonlibsync.prepare_signature(bytes, limits)
    },
    expected,
  )
}

///|
fn hold_prepared(
  input : Bytes,
) -> @moonlibsync.PreparedSignature raise @moonlibsync.SyncError {
  @moonlibsync.prepare_signature(input, @moonlibsync.Limits::default())
}

///|
test "prepared public opaque objects can be received held and passed across scopes" {
  let empty = b"\x72\x73\x01\x47\x00\x00\x00\x02\x00\x00\x00\x01"
  let one = empty + b"\x80\x00\x00\x00\xff"
  let many = one + b"\x00\x00\x00\x01\x80"
  let objects : Array[@moonlibsync.PreparedSignature] = [
    hold_prepared(empty),
    hold_prepared(one),
    hold_prepared(many),
  ]
  assert_eq(objects.length(), 3)
  // There are no public fields or constructors to access here.
  let _ = objects[0]
  assert_eq(empty, b"\x72\x73\x01\x47\x00\x00\x00\x02\x00\x00\x00\x01")
  assert_eq(one, empty + b"\x80\x00\x00\x00\xff")
  assert_eq(many, one + b"\x00\x00\x00\x01\x80")
}

///|
test "prepared public preserves full signature validation and error precedence" {
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
      (b"\x72\x73\x01\x36", "TruncatedInput"),
      (b"\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x01", "InvalidSignature"),
      (b"\x72\x73\x01\x47\x00\x00\x00\x00\x00\x00\x00\x01", "InvalidSignature"),
      (b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x00", "InvalidSignature"),
      (b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x21", "InvalidSignature"),
      (b"\x72\x73\x01\x47\x80\x00\x00\x00\x00\x00\x00\x01", "IntegerOutOfRange"),
      (
        b"\x72\x73\x01\x47\x80\x00\x00\x00\x00\x00\x00\x01\xff", "TruncatedInput",
      ),
      (
        b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x01\xff", "TruncatedInput",
      ),
    ] {
    prepared_error(bytes, { ..d, max_match_work: 0L, }, error)
  }
  prepared_error(b"", { ..d, max_signature_bytes: 0L, }, "TruncatedInput")
  prepared_error(b"x", { ..d, max_signature_bytes: 0L, }, "LimitExceeded")
  prepared_error(
    b"",
    { ..d, max_old_bytes: -1L, },
    "InvalidOptions:max_old_bytes",
  )
}

///|
test "prepared public byte record block and work boundaries are exact" {
  let bytes = b"\x72\x73\x01\x47\x00\x00\x00\x02\x00\x00\x00\x01\x00\x00\x00\x00\xff"
  let exact = {
    ..@moonlibsync.Limits::default(),
    max_signature_bytes: 17L,
    max_signature_records: 1L,
    max_block_bytes: 2L,
    max_match_work: 3L,
  }
  let _ = @moonlibsync.prepare_signature(bytes, exact)
  let _ = @moonlibsync.prepare_signature(bytes, {
    ..exact,
    max_signature_bytes: 18L,
    max_signature_records: 2L,
    max_block_bytes: 3L,
    max_match_work: 4L,
  })
  for
    limits in [
      { ..exact, max_signature_bytes: 16L, },
      { ..exact, max_signature_records: 0L, },
      { ..exact, max_block_bytes: 1L, },
      { ..exact, max_match_work: 2L, },
    ] {
    prepared_error(bytes, limits, "LimitExceeded")
  }
}

///|
test "prepared public empty accepts zero work and legal irrelevant zero limits" {
  let d = {
    ..@moonlibsync.Limits::default(),
    max_old_bytes: 0L,
    max_new_bytes: 0L,
    max_delta_bytes: 0L,
    max_output_bytes: 0L,
    max_instructions: 0L,
  }
  let header = b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x01"
  for available in [0L, 1L] {
    let _ = @moonlibsync.prepare_signature(header, {
      ..d,
      max_signature_records: 0L,
      max_signature_bytes: 12L,
      max_block_bytes: 1L,
      max_match_work: available,
    })
  }
  let _ = @moonlibsync.prepare_signature(header + b"\x00\x00\x00\x00\xff", {
    ..d,
    max_match_work: 3L,
  })
  prepared_error(
    header,
    { ..d, max_match_work: -1L, },
    "InvalidOptions:max_match_work",
  )
  prepared_error(
    header,
    { ..d, max_output_bytes: -1L, },
    "InvalidOptions:max_output_bytes",
  )
  prepared_error(
    header,
    { ..d, max_instructions: 2147483648L, },
    "InvalidOptions:max_instructions",
  )
}

///|
test "prepared public repeated failures do not change input or prevent success" {
  let bytes = b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x01\xff\xff\xff\xff\x00"
  let d = @moonlibsync.Limits::default()
  let saved = hold_prepared(bytes)
  for _ in 0..<4 {
    prepared_error(bytes, { ..d, max_match_work: 2L, }, "LimitExceeded")
    prepared_error(bytes + b"\xff", d, "TruncatedInput")
  }
  let _ = hold_prepared(bytes)
  let held = [saved]
  assert_eq(held.length(), 1)
  assert_eq(
    bytes, b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x01\xff\xff\xff\xff\x00",
  )
}
