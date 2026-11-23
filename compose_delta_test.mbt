// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn compose_make_data(length : Int32, seed : Int32) -> Bytes {
  Bytes::makei(length, i => ((i * 59 + seed * 43 + i / 13 * 7) % 256).to_byte())
}

///|
fn make_step_delta(
  old_bytes : Bytes,
  new_bytes : Bytes,
  block_len : Int64,
  profile : @moonlibsync.SignatureProfile,
  limits : @moonlibsync.Limits,
) -> Bytes raise {
  let sig = @moonlibsync.signature_with_profile(
    old_bytes,
    { block_len, strong_sum_len: 16L, },
    profile,
    limits,
  )
  @moonlibsync.delta(sig, new_bytes, limits)
}

///|
fn expect_compose_error(
  first : Bytes,
  second : Bytes,
  limits : @moonlibsync.Limits,
  expected : String,
) -> Unit raise {
  let actual = try {
    let _ = @moonlibsync.compose_deltas(first, second, limits)
    "success"
  } catch {
    @moonlibsync.SyncError::InvalidOptions(field) => "InvalidOptions:" + field
    @moonlibsync.SyncError::TruncatedInput => "TruncatedInput"
    @moonlibsync.SyncError::InvalidDelta => "InvalidDelta"
    @moonlibsync.SyncError::InvalidOpcode => "InvalidOpcode"
    @moonlibsync.SyncError::IntegerOutOfRange => "IntegerOutOfRange"
    @moonlibsync.SyncError::CopyOutOfBounds => "CopyOutOfBounds"
    @moonlibsync.SyncError::TrailingData => "TrailingData"
    @moonlibsync.SyncError::LimitExceeded => "LimitExceeded"
    _ => "other"
  }
  assert_eq(actual, expected)
}

///|
test "compose_deltas two-step edits insert delete overwrite reorder empty and large" {
  let limits = @moonlibsync.Limits::default()
  let base = compose_make_data(600, 1)
  let cases : Array[(Bytes, Bytes, Bytes, Int64)] = [
    // Insert then edit middle
    (
      base,
      b"HEADER:" + base,
      b"HEADER:" +
      base[0:200].to_owned() +
      b"PATCHED" +
      base[250:600].to_owned(),
      64L,
    ),
    // Delete prefix then reorder blocks
    (
      base,
      base[100:600].to_owned(),
      base[350:600].to_owned() + b"MID" + base[100:300].to_owned(),
      64L,
    ),
    // Overwrite then revert back to original
    (base, Bytes::make(128, b'\x42') + base[128:600].to_owned(), base, 64L),
    // Empty -> non-empty -> empty
    (b"", b"intermediate payload bytes", b"", 16L),
    // Non-empty -> empty -> non-empty
    (b"initial bytes", b"", b"brand new bytes", 8L),
    // Empty -> non-empty -> modified non-empty
    (b"", base, base[64:512].to_owned() + b"tail!", 64L),
    // Large multi-block (16 KiB)
    (
      compose_make_data(16384, 10),
      compose_make_data(16384, 10)[0:4096].to_owned() +
      compose_make_data(1024, 20) +
      compose_make_data(16384, 10)[5120:16384].to_owned(),
      compose_make_data(512, 30) +
      compose_make_data(16384, 10)[5120:12288].to_owned() +
      compose_make_data(1024, 20) +
      compose_make_data(16384, 10)[0:4096].to_owned(),
      512L,
    ),
  ]

  for c in cases {
    let (v1, v2, v3, blk) = c
    let d12 = make_step_delta(v1, v2, blk, RkBlake2, limits)
    let d23 = make_step_delta(v2, v3, blk, RollsumBlake2, limits)
    let composed = @moonlibsync.compose_deltas(d12, d23, limits)
    let summary = @moonlibsync.inspect_delta(composed, limits)
    assert_eq(summary.output_bytes, v3.length().to_int64())
    assert_eq(@moonlibsync.patch(v1, composed, limits), v3)
    // Deterministic composition
    assert_eq(@moonlibsync.compose_deltas(d12, d23, limits), composed)
  }
}

///|
test "compose_delta_chain 5-step evolution v1 through v6" {
  let limits = @moonlibsync.Limits::default()
  let v1 = compose_make_data(2048, 1)
  let v2 = b"v2-prefix-" + v1[0:1024].to_owned() + v1[1024:2048].to_owned()
  let v3 = v2[512:1536].to_owned() +
    Bytes::make(128, b'\xaa') +
    v2[0:512].to_owned()
  let v4 = v3 + compose_make_data(300, 4)
  let v5 = v4[100:v4.length() - 50].to_owned()
  let v6 = v5[400:].to_owned() + b"FINAL-MARKER" + v5[0:400].to_owned()

  let versions = [v1, v2, v3, v4, v5, v6]
  let chain : Array[Bytes] = []
  for i in 0..<5 {
    chain.push(
      make_step_delta(versions[i], versions[i + 1], 64L, RkBlake2, limits),
    )
  }
  let direct = @moonlibsync.compose_delta_chain(chain, limits)
  let summary = @moonlibsync.inspect_delta(direct, limits)
  assert_eq(summary.output_bytes, v6.length().to_int64())
  assert_eq(@moonlibsync.patch(v1, direct, limits), v6)
}

///|
test "compose_deltas overlapping copy across literal-copy-literal and coalescing" {
  let limits = @moonlibsync.Limits::default()
  // Hand-craft standard 0x72730236 deltas:
  // first = Literal(3: "AAA") + Copy(off=10, len=4) + Literal(3: "BBB") + END
  // v2 = "AAA" + v1[10..14] + "BBB" (length 10)
  let first = b"\x72\x73\x02\x36\x03AAA\x45\x0a\x04\x03BBB\x00"
  // second = Copy(off=1, len=8) + END -> slices "AA" + v1[10..14] + "BB"
  let second = b"\x72\x73\x02\x36\x45\x01\x08\x00"
  let composed = @moonlibsync.compose_deltas(first, second, limits)
  let sum = @moonlibsync.inspect_delta(composed, limits)
  assert_eq(sum.instruction_count, 3L)
  assert_eq(sum.literal_commands, 2L)
  assert_eq(sum.copy_commands, 1L)
  assert_eq(sum.literal_bytes, 4L)
  assert_eq(sum.copy_bytes, 4L)
  assert_eq(sum.output_bytes, 8L)
  let v1 = b"0123456789WXYZabcdef"
  let v2 = @moonlibsync.patch(v1, first, limits)
  let v3 = @moonlibsync.patch(v2, second, limits)
  assert_eq(v3, b"AAWXYZBB")
  assert_eq(@moonlibsync.patch(v1, composed, limits), v3)

  // Adjacent Copy coalescing: first has Copy(0,5) + Copy(5,5); second has Copy(0,10) -> single Copy(0,10)
  let split_copies = b"\x72\x73\x02\x36\x45\x00\x05\x45\x05\x05\x00"
  let copy_all = b"\x72\x73\x02\x36\x45\x00\x0a\x00"
  let coalesced_copy = @moonlibsync.compose_deltas(
    split_copies, copy_all, limits,
  )
  let sc = @moonlibsync.inspect_delta(coalesced_copy, limits)
  assert_eq(sc.instruction_count, 1L)
  assert_eq(sc.copy_commands, 1L)
  assert_eq(sc.copy_bytes, 10L)
  assert_eq(@moonlibsync.patch(v1, coalesced_copy, limits), v1[0:10].to_owned())

  // Adjacent Literal coalescing: first has Literal("hello"); second has Copy(0,5) + Literal(" world")
  let lit_first = b"\x72\x73\x02\x36\x05hello\x00"
  let lit_second = b"\x72\x73\x02\x36\x45\x00\x05\x06 world\x00"
  let coalesced_lit = @moonlibsync.compose_deltas(lit_first, lit_second, limits)
  let sl = @moonlibsync.inspect_delta(coalesced_lit, limits)
  assert_eq(sl.instruction_count, 1L)
  assert_eq(sl.literal_commands, 1L)
  assert_eq(sl.literal_bytes, 11L)
  assert_eq(@moonlibsync.patch(b"", coalesced_lit, limits), b"hello world")

  // 1-element chain normalizes uncoalesced copies and literals
  let uncoalesced = b"\x72\x73\x02\x36\x02ab\x02cd\x45\x00\x03\x45\x03\x04\x00"
  let normalized = @moonlibsync.compose_delta_chain([uncoalesced], limits)
  let sn = @moonlibsync.inspect_delta(normalized, limits)
  assert_eq(sn.instruction_count, 2L)
  assert_eq(sn.literal_commands, 1L)
  assert_eq(sn.copy_commands, 1L)
  assert_eq(@moonlibsync.patch(v1, normalized, limits), b"abcd0123456")

  // Coalescing across 64-byte and 255-byte literal header-width boundaries and 255-byte copy width
  let lit60 = Bytes::make(60, b'\x41')
  let lit210 = Bytes::make(210, b'\x42')
  // first = Literal(60) + Literal(210) + Copy(0, 200) + Copy(200, 100)
  let d_first = b"\x72\x73\x02\x36\x3c" +
    lit60 +
    b"\x41\xd2" +
    lit210 +
    b"\x45\x00\xc8\x45\xc8\x64\x00"
  // second = Copy(0, 570) -> opcode 0x46 (1-byte off=0, 2-byte len=570=0x023a)
  let d_second = b"\x72\x73\x02\x36\x46\x00\x02\x3a\x00"
  let d_wide = @moonlibsync.compose_deltas(d_first, d_second, limits)
  let sw = @moonlibsync.inspect_delta(d_wide, limits)
  assert_eq(sw.instruction_count, 2L)
  assert_eq(sw.literal_commands, 1L)
  assert_eq(sw.copy_commands, 1L)
  assert_eq(sw.literal_bytes, 270L)
  assert_eq(sw.copy_bytes, 300L)
  assert_eq(sw.output_bytes, 570L)
  let big_v1 = compose_make_data(350, 9)
  assert_eq(
    @moonlibsync.patch(big_v1, d_wide, limits),
    lit60 + lit210 + big_v1[0:300].to_owned(),
  )
}

///|
test "compose_deltas rejects CopyOutOfBounds overflow limits and malformed deltas" {
  let limits = @moonlibsync.Limits::default()
  let valid_empty = b"\x72\x73\x02\x36\x00"
  let first_4 = b"\x72\x73\x02\x36\x04abcd\x00"

  // CopyOutOfBounds when second reads past first's output
  let copy_0_5 = b"\x72\x73\x02\x36\x45\x00\x05\x00"
  expect_compose_error(first_4, copy_0_5, limits, "CopyOutOfBounds")
  let copy_0_1 = b"\x72\x73\x02\x36\x45\x00\x01\x00"
  expect_compose_error(valid_empty, copy_0_1, limits, "CopyOutOfBounds")

  // UInt64 overflow on Copy offset in first (opcode 0x51 = 8-byte off, 1-byte len)
  // off = 0xffffffffffffffff, len = 1 -> off + len overflows UInt64
  let max_u64_copy = b"\x72\x73\x02\x36\x51\xff\xff\xff\xff\xff\xff\xff\xff\x01\x00"
  expect_compose_error(max_u64_copy, copy_0_1, limits, "IntegerOutOfRange")

  // LimitExceeded: max_instructions, max_output_bytes, max_delta_bytes
  // first = Literal("a") + Copy(0,1) (2 ops); second copies both twice -> 4 ops, 4 bytes
  let first_alt = b"\x72\x73\x02\x36\x01a\x45\x00\x01\x00"
  let second_dup = b"\x72\x73\x02\x36\x45\x00\x02\x45\x00\x02\x00"
  expect_compose_error(
    first_alt,
    second_dup,
    { ..limits, max_instructions: 3L, },
    "LimitExceeded",
  )
  expect_compose_error(
    first_alt,
    second_dup,
    { ..limits, max_output_bytes: 3L, },
    "LimitExceeded",
  )
  expect_compose_error(
    first_alt,
    second_dup,
    { ..limits, max_delta_bytes: 12L, },
    "LimitExceeded",
  )

  // Malformed deltas: missing END, trailing byte, invalid opcode, zero length
  let missing_end = b"\x72\x73\x02\x36\x01a"
  let trailing = b"\x72\x73\x02\x36\x00\x00"
  let bad_opcode = b"\x72\x73\x02\x36\x55\x00"
  let zero_len = b"\x72\x73\x02\x36\x45\x00\x00\x00"
  expect_compose_error(missing_end, valid_empty, limits, "TruncatedInput")
  expect_compose_error(valid_empty, missing_end, limits, "TruncatedInput")
  expect_compose_error(trailing, valid_empty, limits, "TrailingData")
  expect_compose_error(valid_empty, trailing, limits, "TrailingData")
  expect_compose_error(bad_opcode, valid_empty, limits, "InvalidOpcode")
  expect_compose_error(valid_empty, zero_len, limits, "InvalidDelta")

  // Empty chain raises InvalidOptions("deltas")
  let empty_err = try {
    let _ = @moonlibsync.compose_delta_chain([], limits)
    "success"
  } catch {
    @moonlibsync.SyncError::InvalidOptions(f) => f
    _ => "other"
  }
  assert_eq(empty_err, "deltas")
}
