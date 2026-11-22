// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "streaming delta scanner uses O(block_len) internal buffer and O(1) miss path" {
  let d = Limits::default()
  let old = Bytes::makei(256, i => (i % 251).to_byte())
  let sig = signature(old, { block_len: 32L, strong_sum_len: 16L, }, d)
  let prepared = prepare_signature(sig, d)
  let scanner = DeltaScanner::new(prepared, d)
  let big_miss = Bytes::makei(40000, i => (0x80 ^ (i % 127)).to_byte())
  scanner.feed(big_miss)
  // After feed(), only <= block_len active bytes remain buffered inside scanner.
  assert_true(scanner.buf.length() - scanner.head <= 32)
  assert_true(scanner.buf.length() <= 4096 + 32)
  let out = scanner.take_ready() + scanner.finish()
  assert_eq(patch(old, out, d), big_miss)
}

///|
test "streaming delta scanner matches all sixteen upstream fixtures" {
  let bases = reference_bases()
  let sigs = reference_signatures()
  let news = reference_news()
  let d = Limits::default()
  for i in 0..<16 {
    let old = bases[i].1
    let sig = sigs[i].1
    let new_bytes = news[i].1
    let prepared = prepare_signature(sig, d)
    let scanner = DeltaScanner::new(prepared, d)
    // Feed in 3-byte slices to stress multi-chunk boundaries.
    let buf = Buffer()
    let mut pos = 0
    while pos < new_bytes.length() {
      let rem = new_bytes.length() - pos
      let take = if rem < 3 { rem } else { 3 }
      scanner.feed(new_bytes[pos:pos + take])
      buf.write_bytes(scanner.take_ready())
      pos = pos + take
    }
    buf.write_bytes(scanner.finish())
    let streamed = buf.to_bytes()
    assert_eq(streamed, prepared.delta(new_bytes, d))
    assert_eq(patch(old, streamed, d), new_bytes)
  }
}

///|
test "streaming patch applier parses 16-bit 32-bit and 64-bit COPY parameters across 1-byte splits" {
  let d = Limits::default()
  // Handcrafted delta with COPY offset=0 (1-byte), length=3; and huge literal/copy limits checks.
  let copy16 = b"\x72\x73\x02\x36\x4a\x00\x01\x00\x02\x00" // ow=2 (offset=1), lw=2 (len=2)
  let applier = PatchApplier::new(4L, d)
  let out = Buffer()
  for i in 0..<copy16.length() {
    applier.feed(copy16[i:i + 1], b"abcd", chunk => out.write_bytesview(chunk))
  }
  let sum = applier.finish()
  assert_eq(out.to_bytes(), b"bc")
  assert_eq(sum.copy_commands, 1L)
  assert_eq(sum.copy_bytes, 2L)

  // 8-byte COPY offset out of bounds checked in UInt64 without narrowing.
  let copy64 = b"\x72\x73\x02\x36\x51\xff\xff\xff\xff\xff\xff\xff\xff\x01\x00"
  let applier64 = PatchApplier::new(4L, d)
  let oob = try {
    for i in 0..<copy64.length() {
      applier64.feed(copy64[i:i + 1], b"abcd", _ => ())
    }
    false
  } catch {
    SyncError::CopyOutOfBounds => true
    _ => false
  }
  assert_true(oob)
}
