// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn expect_delta_error(
  sig : Bytes,
  input : Bytes,
  limits : @moonlibsync.Limits,
  expected : String,
) -> Unit raise {
  let actual = try {
    let _ = @moonlibsync.delta(sig, input, limits)
    "success"
  } catch {
    @moonlibsync.SyncError::InvalidOptions(field) => "InvalidOptions:" + field
    @moonlibsync.SyncError::TruncatedInput => "TruncatedInput"
    @moonlibsync.SyncError::InvalidSignature => "InvalidSignature"
    @moonlibsync.SyncError::UnsupportedSignatureProfile =>
      "UnsupportedSignatureProfile"
    @moonlibsync.SyncError::LimitExceeded => "LimitExceeded"
    _ => "unexpected error variant"
  }
  assert_eq(actual, expected)
}

///|
fn public_delta_roundtrip(
  old : Bytes,
  input : Bytes,
  block : Int64,
  strong : Int64,
) -> Bytes raise {
  let limits = @moonlibsync.Limits::default()
  let options : @moonlibsync.SignatureOptions = {
    block_len: block,
    strong_sum_len: strong,
  }
  let sig = @moonlibsync.signature(old, options, limits)
  let actual = @moonlibsync.delta(sig, input, limits)
  assert_eq(@moonlibsync.patch(old, actual, limits), input)
  assert_eq(@moonlibsync.delta(sig, input, limits), actual)
  actual
}

///|
test "public delta empty inputs still validate remote signatures" {
  let d = @moonlibsync.Limits::default()
  let sig = b"\x72\x73\x01\x47\x00\x00\x00\x40\x00\x00\x00\x20"
  assert_eq(
    @moonlibsync.delta(sig, b"", {
      ..d,
      max_match_work: 0L,
      max_instructions: 0L,
      max_output_bytes: 0L,
      max_new_bytes: 0L,
      max_delta_bytes: 5L,
    }),
    b"\x72\x73\x02\x36\x00",
  )
  assert_eq(
    public_delta_roundtrip(b"abc", b"", 2L, 16L),
    b"\x72\x73\x02\x36\x00",
  )
  let _ = public_delta_roundtrip(b"", b"\x00\x80\xff", 64L, 32L)
  expect_delta_error(b"", b"", d, "TruncatedInput")
  expect_delta_error(
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00", b"", d, "InvalidSignature",
  )
  expect_delta_error(
    b"\x72\x73\x01\x36\x00\x00\x00\x40\x00\x00\x00\x10", b"", d, "UnsupportedSignatureProfile",
  )
}

///|
test "public delta representative edit and block movement roundtrips" {
  for (block, strong) in [(1, 1L), (2, 16L), (64, 32L), (2048, 32L)] {
    let tail = if block / 2 > 0 { block / 2 } else { 1 }
    let old = Bytes::makei(3 * block + tail, i => {
      ((i * 73 + 19 + i / block * 11) % 256).to_byte()
    })
    for
      input in [
        old,
        b"",
        Bytes::make(old.length(), b'\x55'),
        b"\x00\x80\xff" + old,
        old[0:block].to_owned() + b"\x00\x80\xff" + old[block:].to_owned(),
        old + b"\x00\x80\xff",
        old[1:].to_owned(),
        old[0:block].to_owned() + old[block + 1:].to_owned(),
        old[0:old.length() - 1].to_owned(),
        b"\xff" + old[1:].to_owned(),
        old[0:block].to_owned() + b"\x80" + old[block + 1:].to_owned(),
        old[0:old.length() - 1].to_owned() + b"\x00",
        old[block:2 * block].to_owned() +
        old[0:block].to_owned() +
        old[2 * block:].to_owned(),
        old[3 * block:].to_owned() + old[0:3 * block].to_owned() + b"!",
      ] {
      let _ = public_delta_roundtrip(old, input, block.to_int64(), strong)
    }
  }
}

///|
test "public delta inputs immutable and independent failures do not poison later calls" {
  let d = @moonlibsync.Limits::default()
  let sig = @moonlibsync.signature(
    b"abc",
    { block_len: 3L, strong_sum_len: 16L, },
    d,
  )
  let saved = sig.to_array()
  let input = b"abcXabc"
  let first = @moonlibsync.delta(sig, input, { ..d, max_old_bytes: 0L, })
  for _ in 0..<3 {
    expect_delta_error(
      sig,
      input,
      { ..d, max_match_work: 0L, },
      "LimitExceeded",
    )
    expect_delta_error(
      sig,
      input,
      { ..d, max_delta_bytes: 5L, },
      "LimitExceeded",
    )
    let _ = public_delta_roundtrip(b"xyz", b"!xyz", 2L, 32L)
    assert_eq(@moonlibsync.delta(sig, input, d), first)
    assert_eq(Bytes::from_array(saved[:]), sig)
    assert_eq(input, b"abcXabc")
    assert_eq(@moonlibsync.patch(b"abc", first, d), input)
  }
}

///|
test "public delta input signature and output policy precedence is fixed" {
  let d = @moonlibsync.Limits::default()
  let sig = @moonlibsync.signature(
    b"abc",
    { block_len: 2L, strong_sum_len: 16L, },
    d,
  )
  for
    limits in [
      { ..d, max_signature_bytes: 11L, },
      { ..d, max_signature_records: 1L, },
      { ..d, max_block_bytes: 1L, },
      { ..d, max_new_bytes: 2L, },
      { ..d, max_output_bytes: 2L, },
      { ..d, max_delta_bytes: 4L, },
    ] {
    expect_delta_error(sig, b"abc", limits, "LimitExceeded")
  }
  expect_delta_error(b"", b"abc", { ..d, max_new_bytes: 0L, }, "TruncatedInput")
  expect_delta_error(
    b"",
    b"abc",
    { ..d, max_match_work: -1L, },
    "InvalidOptions:max_match_work",
  )
  expect_delta_error(
    sig,
    b"",
    { ..d, max_signature_records: 0L, },
    "LimitExceeded",
  )
}

///|
test "public delta literal merging byte instruction and no-match work boundaries" {
  let d = @moonlibsync.Limits::default()
  let sig = b"\x72\x73\x01\x47\x00\x00\x00\x40\x00\x00\x00\x20"
  // Empty index; setup+update=4, three (dispatch+append+rollout)=12: total16.
  let exact = {
    ..d,
    max_signature_bytes: 12L,
    max_signature_records: 0L,
    max_block_bytes: 64L,
    max_new_bytes: 3L,
    max_output_bytes: 3L,
    max_instructions: 1L,
    max_delta_bytes: 9L,
    max_match_work: 16L,
  }
  assert_eq(
    @moonlibsync.delta(sig, b"abc", exact),
    b"\x72\x73\x02\x36\x03abc\x00",
  )
  for
    limits in [
      { ..exact, max_match_work: 15L, },
      { ..exact, max_delta_bytes: 8L, },
      { ..exact, max_instructions: 0L, },
      { ..exact, max_new_bytes: 2L, },
      { ..exact, max_output_bytes: 2L, },
    ] {
    expect_delta_error(sig, b"abc", limits, "LimitExceeded")
  }
}

///|
test "public delta block-one instruction growth never merges repeated same offsets" {
  let d = @moonlibsync.Limits::default()
  let sig = @moonlibsync.signature(
    b"A",
    { block_len: 1L, strong_sum_len: 32L, },
    d,
  )
  let exact = { ..d, max_instructions: 4L, max_delta_bytes: 17L, }
  assert_eq(
    @moonlibsync.delta(sig, b"AAAA", exact),
    b"\x72\x73\x02\x36\x45\x00\x01\x45\x00\x01\x45\x00\x01\x45\x00\x01\x00",
  )
  expect_delta_error(
    sig,
    b"AAAA",
    { ..exact, max_instructions: 3L, },
    "LimitExceeded",
  )
  expect_delta_error(
    sig,
    b"AAAA",
    { ..exact, max_delta_bytes: 16L, },
    "LimitExceeded",
  )
}
