// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn range_make_data(length : Int32, seed : Int32) -> Bytes {
  Bytes::makei(length, i => ((i * 73 + seed * 31 + i / 17 * 19) % 256).to_byte())
}

///|
fn slice_ranges_from_target(
  target : Bytes,
  ranges : Array[@moonlibsync.ByteRange],
) -> Array[Bytes] {
  let out : Array[Bytes] = Array(capacity=ranges.length())
  for r in ranges {
    let s = r.start.to_int()
    let e = (r.start + r.length).to_int()
    out.push(target[s:e].to_owned())
  }
  out
}

///|
fn expect_range_plan_error(
  sig : Bytes,
  target_length : Int64,
  basis : Bytes,
  options : @moonlibsync.RangeFetchOptions,
  limits : @moonlibsync.Limits,
  expected : String,
) -> Unit raise {
  let actual = try {
    let _ = @moonlibsync.plan_range_fetch(
      sig, target_length, basis, options, limits,
    )
    "success"
  } catch {
    @moonlibsync.SyncError::InvalidOptions(field) => "InvalidOptions:" + field
    @moonlibsync.SyncError::UnsupportedSignatureProfile =>
      "UnsupportedSignatureProfile"
    @moonlibsync.SyncError::TruncatedInput => "TruncatedInput"
    @moonlibsync.SyncError::InvalidSignature => "InvalidSignature"
    @moonlibsync.SyncError::LimitExceeded => "LimitExceeded"
    _ => "other"
  }
  assert_eq(actual, expected)
}

///|
fn expect_range_apply_error(
  basis : Bytes,
  plan : @moonlibsync.RangeFetchPlan,
  slices : Array[Bytes],
  limits : @moonlibsync.Limits,
  expected : String,
) -> Unit raise {
  let actual = try {
    let _ = @moonlibsync.apply_range_fetch(basis, plan, slices, limits)
    "success"
  } catch {
    @moonlibsync.SyncError::InvalidOptions(field) => "InvalidOptions:" + field
    @moonlibsync.SyncError::CopyOutOfBounds => "CopyOutOfBounds"
    @moonlibsync.SyncError::InvalidDelta => "InvalidDelta"
    @moonlibsync.SyncError::LimitExceeded => "LimitExceeded"
    _ => "other"
  }
  assert_eq(actual, expected)
}

///|
test "range_sync identical file reuses 100 percent with zero ranges" {
  let limits = @moonlibsync.Limits::default()
  let opts = @moonlibsync.RangeFetchOptions::default()
  let data = range_make_data(300, 7) // 4 * 64 + 44 short tail
  let sig = @moonlibsync.signature(
    data,
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )
  let plan = @moonlibsync.plan_range_fetch(
    sig,
    data.length().to_int64(),
    data,
    opts,
    limits,
  )
  assert_eq(plan.target_length, 300L)
  assert_eq(plan.block_len, 64)
  assert_true(plan.profile is RkBlake2)
  assert_eq(plan.ranges.length(), 0)
  assert_eq(plan.reused_bytes, 300L)
  assert_eq(plan.fetch_bytes, 0L)
  assert_eq(plan.request_bytes, 0L)
  assert_eq(plan.ops, [@moonlibsync.RangePlanOp::CopyLocal(0L, 300L)])
  let recovered = @moonlibsync.apply_range_fetch(data, plan, [], limits)
  assert_eq(recovered, data)
}

///|
test "range_sync middle edit and unaligned prepended insertion reuse" {
  let limits = @moonlibsync.Limits::default()
  let opts = @moonlibsync.RangeFetchOptions::default()
  let basis = range_make_data(512, 11) // 8 blocks of 64 bytes

  // Middle edit: replace bytes [128..192)
  let middle_target = basis[0:128].to_owned() +
    Bytes::make(64, b'\xaa') +
    basis[192:512].to_owned()
  let sig_mid = @moonlibsync.signature(
    middle_target,
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )
  let plan_mid = @moonlibsync.plan_range_fetch(
    sig_mid,
    middle_target.length().to_int64(),
    basis,
    opts,
    limits,
  )
  assert_eq(plan_mid.reused_bytes, 448L)
  assert_eq(plan_mid.fetch_bytes, 64L)
  assert_eq(plan_mid.request_bytes, 64L)
  assert_eq(plan_mid.ranges, [{ start: 128L, length: 64L, }])
  assert_eq(plan_mid.ranges[0].http_range_spec(), "bytes=128-191")
  assert_eq(plan_mid.ops, [
    @moonlibsync.RangePlanOp::CopyLocal(0L, 128L),
    @moonlibsync.RangePlanOp::FetchRemote(128L, 64L),
    @moonlibsync.RangePlanOp::CopyLocal(192L, 320L),
  ])
  let slices_mid = slice_ranges_from_target(middle_target, plan_mid.ranges)
  assert_eq(
    @moonlibsync.apply_range_fetch(basis, plan_mid, slices_mid, limits),
    middle_target,
  )

  // Prepended unaligned insertion: prepend 23 bytes to basis -> rolling hash finds shifted blocks!
  let shifted_target = Bytes::make(23, b'\xfe') + basis
  let sig_shift = @moonlibsync.signature(
    shifted_target,
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )
  let plan_shift = @moonlibsync.plan_range_fetch(
    sig_shift,
    shifted_target.length().to_int64(),
    basis,
    opts,
    limits,
  )
  // Block 0 contains the 23 new bytes + 41 basis bytes (must fetch 64B);
  // remaining 7 full blocks (448B) + 23B short tail are all unaligned substrings of `basis`!
  assert_eq(plan_shift.reused_bytes, 471L)
  assert_eq(plan_shift.fetch_bytes, 64L)
  assert_eq(plan_shift.ranges, [{ start: 0L, length: 64L, }])
  let slices_shift = slice_ranges_from_target(shifted_target, plan_shift.ranges)
  assert_eq(
    @moonlibsync.apply_range_fetch(basis, plan_shift, slices_shift, limits),
    shifted_target,
  )
}

///|
test "range_sync duplicate target blocks all reuse single local block" {
  let limits = @moonlibsync.Limits::default()
  let opts = @moonlibsync.RangeFetchOptions::default()
  let blk_a = range_make_data(64, 3)
  let blk_b = range_make_data(64, 99)
  let basis = blk_a
  let target = blk_a + blk_b + blk_a + blk_a
  let sig = @moonlibsync.signature(
    target,
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )
  let plan = @moonlibsync.plan_range_fetch(
    sig,
    target.length().to_int64(),
    basis,
    opts,
    limits,
  )
  assert_eq(plan.reused_bytes, 192L)
  assert_eq(plan.fetch_bytes, 64L)
  assert_eq(plan.ranges, [{ start: 64L, length: 64L, }])
  let slices = slice_ranges_from_target(target, plan.ranges)
  assert_eq(@moonlibsync.apply_range_fetch(basis, plan, slices, limits), target)
}

///|
test "range_sync completely different file and empty file" {
  let limits = @moonlibsync.Limits::default()
  let opts = @moonlibsync.RangeFetchOptions::default()
  let basis = Bytes::make(200, b'\x11')
  let target = range_make_data(200, 42)
  let sig = @moonlibsync.signature(
    target,
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )
  let plan = @moonlibsync.plan_range_fetch(
    sig,
    target.length().to_int64(),
    basis,
    opts,
    limits,
  )
  assert_eq(plan.reused_bytes, 0L)
  assert_eq(plan.fetch_bytes, 200L)
  assert_eq(plan.request_bytes, 200L)
  assert_eq(plan.ranges, [{ start: 0L, length: 200L, }])
  assert_eq(plan.ranges[0].http_range_spec(), "bytes=0-199")
  let slices = slice_ranges_from_target(target, plan.ranges)
  assert_eq(@moonlibsync.apply_range_fetch(basis, plan, slices, limits), target)

  // Empty target with non-empty and empty basis
  let empty_sig = @moonlibsync.signature(
    b"",
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )
  for b in [b"", basis] {
    let p_empty = @moonlibsync.plan_range_fetch(empty_sig, 0L, b, opts, limits)
    assert_eq(p_empty.target_length, 0L)
    assert_eq(p_empty.reused_bytes, 0L)
    assert_eq(p_empty.fetch_bytes, 0L)
    assert_eq(p_empty.request_bytes, 0L)
    assert_eq(p_empty.ops.length(), 0)
    assert_eq(p_empty.ranges.length(), 0)
    assert_eq(@moonlibsync.apply_range_fetch(b, p_empty, [], limits), b"")
  }
}

///|
test "range_sync short tail reuse including shifted short tail and sub-block file" {
  let limits = @moonlibsync.Limits::default()
  let opts = @moonlibsync.RangeFetchOptions::default()
  let tail = range_make_data(19, 55)
  // Basis contains `tail` buried in the middle (not at end, not at aligned offset)
  let basis = Bytes::make(40, b'\x01') + tail + Bytes::make(80, b'\x02')
  let target = range_make_data(64, 88) + tail
  let sig = @moonlibsync.signature(
    target,
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )
  let plan = @moonlibsync.plan_range_fetch(
    sig,
    target.length().to_int64(),
    basis,
    opts,
    limits,
  )
  assert_eq(plan.reused_bytes, 19L)
  assert_eq(plan.fetch_bytes, 64L)
  assert_eq(plan.ops, [
    @moonlibsync.RangePlanOp::FetchRemote(0L, 64L),
    @moonlibsync.RangePlanOp::CopyLocal(40L, 19L),
  ])
  let slices = slice_ranges_from_target(target, plan.ranges)
  assert_eq(@moonlibsync.apply_range_fetch(basis, plan, slices, limits), target)

  // Sub-block file (target_length < block_len)
  let tiny_sig = @moonlibsync.signature(
    tail,
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )
  let tiny_plan = @moonlibsync.plan_range_fetch(
    tiny_sig,
    tail.length().to_int64(),
    basis,
    opts,
    limits,
  )
  assert_eq(tiny_plan.reused_bytes, 19L)
  assert_eq(tiny_plan.fetch_bytes, 0L)
  assert_eq(tiny_plan.ranges.length(), 0)
  assert_eq(@moonlibsync.apply_range_fetch(basis, tiny_plan, [], limits), tail)
}

///|
test "range_sync gap coalescing and max_ranges limit" {
  let limits = @moonlibsync.Limits::default()
  // 6 blocks of 64 bytes: blocks 1 and 4 are edited, separated by blocks 2 and 3 (128-byte gap)
  let basis = range_make_data(384, 17)
  let target = basis[0:64].to_owned() +
    Bytes::make(64, b'\xc1') +
    basis[128:256].to_owned() +
    Bytes::make(64, b'\xc2') +
    basis[320:384].to_owned()
  let sig = @moonlibsync.signature(
    target,
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )

  // Gap = 128 bytes; merge_gap_bytes = 127 -> 2 distinct ranges
  let plan_split = @moonlibsync.plan_range_fetch(
    sig,
    384L,
    basis,
    { merge_gap_bytes: 127L, max_ranges: 8L, },
    limits,
  )
  assert_eq(plan_split.reused_bytes, 256L)
  assert_eq(plan_split.fetch_bytes, 128L)
  assert_eq(plan_split.request_bytes, 128L)
  assert_eq(plan_split.ranges, [
    { start: 64L, length: 64L, },
    { start: 256L, length: 64L, },
  ])
  assert_eq(plan_split.ranges[0].http_range_spec(), "bytes=64-127")
  assert_eq(plan_split.ranges[1].http_range_spec(), "bytes=256-319")
  let slices_split = slice_ranges_from_target(target, plan_split.ranges)
  assert_eq(
    @moonlibsync.apply_range_fetch(basis, plan_split, slices_split, limits),
    target,
  )

  // Gap = 128 bytes; merge_gap_bytes = 128 -> coalesced into 1 range covering [64..320)
  let plan_merged = @moonlibsync.plan_range_fetch(
    sig,
    384L,
    basis,
    { merge_gap_bytes: 128L, max_ranges: 1L, },
    limits,
  )
  assert_eq(plan_merged.reused_bytes, 256L)
  assert_eq(plan_merged.fetch_bytes, 128L)
  assert_eq(plan_merged.request_bytes, 256L)
  assert_eq(plan_merged.ranges, [{ start: 64L, length: 256L, }])
  let slices_merged = slice_ranges_from_target(target, plan_merged.ranges)
  assert_eq(
    @moonlibsync.apply_range_fetch(basis, plan_merged, slices_merged, limits),
    target,
  )

  // max_ranges = 1 with merge_gap_bytes = 0 rejects 2 ranges with LimitExceeded
  expect_range_plan_error(
    sig,
    384L,
    basis,
    { merge_gap_bytes: 0L, max_ranges: 1L, },
    limits,
    "LimitExceeded",
  )
}

///|
test "range_sync supports both RkBlake2 and RollsumBlake2 profiles and rejects MD4" {
  let limits = @moonlibsync.Limits::default()
  let opts = @moonlibsync.RangeFetchOptions::default()
  let basis = range_make_data(350, 29)
  let target = Bytes::make(17, b'\x99') +
    basis[0:200].to_owned() +
    Bytes::make(64, b'\x77') +
    basis[200:350].to_owned()

  for
    profile in [
      @moonlibsync.SignatureProfile::RkBlake2,
      @moonlibsync.SignatureProfile::RollsumBlake2,
    ] {
    let sig = @moonlibsync.signature_with_profile(
      target,
      { block_len: 64L, strong_sum_len: 16L, },
      profile,
      limits,
    )
    let plan = @moonlibsync.plan_range_fetch(
      sig,
      target.length().to_int64(),
      basis,
      opts,
      limits,
    )
    match profile {
      RkBlake2 => assert_true(plan.profile is RkBlake2)
      RollsumBlake2 => assert_true(plan.profile is RollsumBlake2)
    }
    assert_true(plan.reused_bytes > 0L)
    assert_eq(plan.reused_bytes + plan.fetch_bytes, target.length().to_int64())
    let slices = slice_ranges_from_target(target, plan.ranges)
    assert_eq(
      @moonlibsync.apply_range_fetch(basis, plan, slices, limits),
      target,
    )
  }

  // Legacy MD4 profiles (0x72730136, 0x72730146) are rejected
  expect_range_plan_error(
    b"\x72\x73\x01\x36\x00\x00\x00\x40\x00\x00\x00\x10", 0L, b"", opts, limits, "UnsupportedSignatureProfile",
  )
  expect_range_plan_error(
    b"\x72\x73\x01\x46\x00\x00\x00\x40\x00\x00\x00\x10", 0L, b"", opts, limits, "UnsupportedSignatureProfile",
  )
}

///|
test "range_sync rejects invalid options target_length and fetched_slices bounds" {
  let limits = @moonlibsync.Limits::default()
  let opts = @moonlibsync.RangeFetchOptions::default()
  let basis = range_make_data(128, 5)
  let target = basis[0:64].to_owned() + Bytes::make(64, b'\xee')
  let sig = @moonlibsync.signature(
    target,
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )

  // Invalid options
  expect_range_plan_error(
    sig,
    128L,
    basis,
    { merge_gap_bytes: -1L, max_ranges: 16L, },
    limits,
    "InvalidOptions:merge_gap_bytes",
  )
  expect_range_plan_error(
    sig,
    128L,
    basis,
    { merge_gap_bytes: 0L, max_ranges: 0L, },
    limits,
    "InvalidOptions:max_ranges",
  )
  expect_range_plan_error(
    sig,
    128L,
    basis,
    { merge_gap_bytes: 0L, max_ranges: 65537L, },
    limits,
    "InvalidOptions:max_ranges",
  )

  // Wrong target_length vs signature record count (2 records for block_len=64 means 65..128)
  expect_range_plan_error(
    sig, -1L, basis, opts, limits, "InvalidOptions:target_length",
  )
  expect_range_plan_error(sig, 0L, basis, opts, limits, "InvalidSignature")
  expect_range_plan_error(sig, 64L, basis, opts, limits, "InvalidSignature")
  expect_range_plan_error(sig, 129L, basis, opts, limits, "InvalidSignature")
  expect_range_plan_error(
    sig,
    128L,
    basis,
    opts,
    { ..limits, max_new_bytes: 100L, },
    "LimitExceeded",
  )
  expect_range_plan_error(
    sig,
    128L,
    basis,
    opts,
    { ..limits, max_old_bytes: 100L, },
    "LimitExceeded",
  )

  // Bad fetched_slices and tampered plans in apply_range_fetch
  let plan = @moonlibsync.plan_range_fetch(sig, 128L, basis, opts, limits)
  let good_slices = slice_ranges_from_target(target, plan.ranges)
  expect_range_apply_error(
    basis,
    plan,
    [],
    limits,
    "InvalidOptions:fetched_slices",
  )
  expect_range_apply_error(
    basis,
    plan,
    [b"too short"],
    limits,
    "InvalidOptions:fetched_slices",
  )
  expect_range_apply_error(
    basis,
    plan,
    [Bytes::make(65, b'\x00')],
    limits,
    "InvalidOptions:fetched_slices",
  )
  expect_range_apply_error(
    basis,
    plan,
    good_slices,
    { ..limits, max_output_bytes: 100L, },
    "LimitExceeded",
  )
  // Basis truncated shorter than CopyLocal
  expect_range_apply_error(
    basis[0:32].to_owned(),
    plan,
    good_slices,
    limits,
    "CopyOutOfBounds",
  )
  // Tampered plan with FetchRemote outside declared ranges
  let bad_remote_plan : @moonlibsync.RangeFetchPlan = {
    ..plan,
    ops: [
      @moonlibsync.RangePlanOp::CopyLocal(0L, 64L),
      @moonlibsync.RangePlanOp::FetchRemote(0L, 64L),
    ],
  }
  expect_range_apply_error(
    basis, bad_remote_plan, good_slices, limits, "CopyOutOfBounds",
  )
  // Tampered plan whose ops don't sum to target_length
  let short_ops_plan : @moonlibsync.RangeFetchPlan = {
    ..plan,
    ops: [@moonlibsync.RangePlanOp::CopyLocal(0L, 64L)],
  }
  expect_range_apply_error(
    basis, short_ops_plan, good_slices, limits, "InvalidDelta",
  )
}

///|
test "range_sync encode_range_plan_json emits deterministic canonical JSON" {
  let limits = @moonlibsync.Limits::default()
  let basis = range_make_data(192, 13)
  let target = basis[0:64].to_owned() +
    Bytes::make(64, b'\x5a') +
    basis[128:192].to_owned()
  let sig = @moonlibsync.signature_with_profile(
    target,
    { block_len: 64L, strong_sum_len: 16L, },
    RollsumBlake2,
    limits,
  )
  let plan = @moonlibsync.plan_range_fetch(
    sig,
    192L,
    basis,
    @moonlibsync.RangeFetchOptions::default(),
    limits,
  )
  let json_bytes = @moonlibsync.encode_range_plan_json(plan)
  assert_eq(@moonlibsync.encode_range_plan_json(plan), json_bytes)
  let text = @utf8.decode(json_bytes)
  let parsed = @json.parse(text)
  guard parsed is @json.Json::Object(fields) else { fail("expected object") }
  assert_true(fields.get("schema") is Some(@json.Json::Number(3.0, ..)))
  assert_true(
    fields.get("kind") is Some(@json.Json::String("moonlibsync-range-plan")),
  )
  assert_true(
    fields.get("profile") is Some(@json.Json::String("rollsum-blake2")),
  )
  assert_true(
    fields.get("target_length") is Some(@json.Json::Number(192.0, ..)),
  )
  assert_true(fields.get("block_len") is Some(@json.Json::Number(64.0, ..)))
  assert_true(fields.get("reused_bytes") is Some(@json.Json::Number(128.0, ..)))
  assert_true(fields.get("fetch_bytes") is Some(@json.Json::Number(64.0, ..)))
  assert_true(fields.get("request_bytes") is Some(@json.Json::Number(64.0, ..)))
  guard fields.get("ranges") is Some(@json.Json::Array(ranges)) else {
    fail("expected ranges")
  }
  assert_eq(ranges.length(), 1)
  guard ranges[0] is @json.Json::Object(r0) else { fail("expected range obj") }
  assert_true(r0.get("http_range") is Some(@json.Json::String("bytes=64-127")))
  guard fields.get("ops") is Some(@json.Json::Array(ops)) else {
    fail("expected ops")
  }
  assert_eq(ops.length(), 3)
}

///|
test "range_sync red-team hardening enforces sorted disjoint ranges max_instructions max_output_bytes and http_range_spec safety" {
  let limits = @moonlibsync.Limits::default()
  let opts = @moonlibsync.RangeFetchOptions::default()
  let basis = range_make_data(256, 37)
  let target = basis[0:64].to_owned() + Bytes::make(192, b'\xd4')
  let sig = @moonlibsync.signature(
    target,
    { block_len: 64L, strong_sum_len: 16L, },
    limits,
  )

  // plan_range_fetch enforces limits.max_output_bytes and limits.max_instructions
  expect_range_plan_error(
    sig,
    256L,
    basis,
    opts,
    { ..limits, max_output_bytes: 255L, },
    "LimitExceeded",
  )
  expect_range_plan_error(
    sig,
    256L,
    basis,
    { merge_gap_bytes: 0L, max_ranges: 16L, },
    { ..limits, max_instructions: 1L, },
    "LimitExceeded",
  )

  // apply_range_fetch rejects unsorted or overlapping ranges (anti-DoS / anti-ambiguity)
  let overlapping_plan : @moonlibsync.RangeFetchPlan = {
    target_length: 8L,
    block_len: 64,
    profile: @moonlibsync.SignatureProfile::RkBlake2,
    ops: [
      @moonlibsync.RangePlanOp::FetchRemote(0L, 4L),
      @moonlibsync.RangePlanOp::FetchRemote(4L, 4L),
    ],
    ranges: [{ start: 0L, length: 4L, }, { start: 0L, length: 8L, }],
    reused_bytes: 0L,
    fetch_bytes: 8L,
    request_bytes: 12L,
  }
  expect_range_apply_error(
    basis,
    overlapping_plan,
    [b"AAAA", b"BBBBCCCC"],
    limits,
    "InvalidOptions:range",
  )
  let unsorted_plan : @moonlibsync.RangeFetchPlan = {
    ..overlapping_plan,
    ranges: [{ start: 4L, length: 4L, }, { start: 0L, length: 4L, }],
  }
  expect_range_apply_error(
    basis,
    unsorted_plan,
    [b"BBBB", b"AAAA"],
    limits,
    "InvalidOptions:range",
  )

  // apply_range_fetch enforces limits.max_instructions & limits.max_block_bytes
  let plan = @moonlibsync.plan_range_fetch(sig, 256L, basis, opts, limits)
  let slices = slice_ranges_from_target(target, plan.ranges)
  expect_range_apply_error(
    basis,
    {
      ..plan,
      ops: [
        @moonlibsync.RangePlanOp::FetchRemote(0L, 128L),
        @moonlibsync.RangePlanOp::FetchRemote(128L, 128L),
      ],
    },
    slices,
    { ..limits, max_instructions: 1L, },
    "LimitExceeded",
  )
  expect_range_apply_error(
    basis,
    plan,
    slices,
    { ..limits, max_block_bytes: 32L, },
    "InvalidOptions:block_len",
  )

  // ByteRange::http_range_spec guards invalid or overflowing handcrafted ranges
  assert_eq(
    ({ start: 0L, length: 0L, } : @moonlibsync.ByteRange).http_range_spec(),
    "",
  )
  assert_eq(
    ({ start: -1L, length: 4L, } : @moonlibsync.ByteRange).http_range_spec(),
    "",
  )
  assert_eq(
    ({ start: 9223372036854775807L, length: 2L, } : @moonlibsync.ByteRange).http_range_spec(),
    "",
  )
}
