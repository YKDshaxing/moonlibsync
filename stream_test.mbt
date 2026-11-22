// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn collect_signature_chunks(
  old : Bytes,
  options : @moonlibsync.SignatureOptions,
  limits : @moonlibsync.Limits,
  step : Int32,
  drain_each~ : Bool,
) -> Bytes raise @moonlibsync.SyncError {
  let hasher = @moonlibsync.SignatureHasher::new(options, limits)
  let out = Buffer()
  let mut pos = 0
  while pos < old.length() {
    let rem = old.length() - pos
    let take = if rem < step { rem } else { step }
    hasher.update(old[pos:pos + take])
    if drain_each {
      let ready = hasher.take_ready()
      if ready.length() > 0 {
        out.write_bytes(ready)
      }
    }
    pos = pos + take
  }
  if drain_each {
    // Also exercise empty chunk update and take_ready drain before finish.
    hasher.update(b""[:])
  }
  out.write_bytes(hasher.finish())
  out.to_bytes()
}

///|
fn collect_delta_chunks(
  prepared : @moonlibsync.PreparedSignature,
  new_bytes : Bytes,
  limits : @moonlibsync.Limits,
  step : Int32,
  drain_each~ : Bool,
) -> Bytes raise @moonlibsync.SyncError {
  let scanner = @moonlibsync.DeltaScanner::new(prepared, limits)
  let out = Buffer()
  let mut pos = 0
  while pos < new_bytes.length() {
    let rem = new_bytes.length() - pos
    let take = if rem < step { rem } else { step }
    scanner.feed(new_bytes[pos:pos + take])
    if drain_each {
      let ready = scanner.take_ready()
      if ready.length() > 0 {
        out.write_bytes(ready)
      }
    }
    pos = pos + take
  }
  if drain_each {
    scanner.feed(b""[:])
  }
  out.write_bytes(scanner.finish())
  out.to_bytes()
}

///|
fn[R : @moonlibsync.BasisReader] apply_patch_chunks(
  basis : R,
  basis_len : Int64,
  delta_bytes : Bytes,
  limits : @moonlibsync.Limits,
  step : Int32,
) -> (Bytes, @moonlibsync.DeltaSummary) raise @moonlibsync.SyncError {
  let applier = @moonlibsync.PatchApplier::new(basis_len, limits)
  let out = Buffer()
  let mut pos = 0
  while pos < delta_bytes.length() {
    let rem = delta_bytes.length() - pos
    let take = if rem < step { rem } else { step }
    applier.feed(delta_bytes[pos:pos + take], basis, chunk => {
      out.write_bytesview(chunk)
    })
    pos = pos + take
  }
  applier.feed(b""[:], basis, chunk => out.write_bytesview(chunk))
  let summary = applier.finish()
  (out.to_bytes(), summary)
}

///|
struct CountingReader {
  data : Bytes
  mut calls : Int32
  mut max_len : Int32
}

///|
impl @moonlibsync.BasisReader for CountingReader with fn read_at(
  self : CountingReader,
  offset : UInt64,
  len : Int32,
) -> Bytes raise @moonlibsync.SyncError {
  self.calls = self.calls + 1
  if len > self.max_len {
    self.max_len = len
  }
  @moonlibsync.BasisReader::read_at(self.data, offset, len)
}

///|
struct FaultyReader {
  truncate_after : Int32
  mut calls : Int32
}

///|
impl @moonlibsync.BasisReader for FaultyReader with fn read_at(
  self : FaultyReader,
  _offset : UInt64,
  len : Int32,
) -> Bytes raise @moonlibsync.SyncError {
  self.calls = self.calls + 1
  if self.calls > self.truncate_after {
    b""
  } else {
    Bytes::make(len, b'A')
  }
}

///|
test "streaming signature matches one-shot across empty single-byte and multi-block splits" {
  let d = @moonlibsync.Limits::default()
  let inputs : Array[(Bytes, Int64, Int64)] = [
    (b"", 2048L, 32L),
    (b"a", 1L, 1L),
    (b"ABCDEFGHIJKLMN\x00\x80\xff", 7L, 16L),
    (Bytes::makei(5000, i => (i * 73 + 19).to_byte()), 64L, 32L),
  ]
  for item in inputs {
    let (old, block_len, strong_sum_len) = item
    let opts : @moonlibsync.SignatureOptions = { block_len, strong_sum_len, }
    let expected = @moonlibsync.signature(old, opts, d)
    for step in [1, 3, 7, 128, 4096] {
      assert_eq(
        collect_signature_chunks(old, opts, d, step, drain_each=true),
        expected,
      )
      assert_eq(
        collect_signature_chunks(old, opts, d, step, drain_each=false),
        expected,
      )
    }
  }
}

///|
test "streaming delta and patch match one-shot across 1-byte and cross-block splits" {
  let d = @moonlibsync.Limits::default()
  let old = Bytes::makei(512, i => (0x10 + i / 64).to_byte()) + b"\x00\x80\xff"
  let sig = @moonlibsync.signature(
    old,
    { block_len: 64L, strong_sum_len: 32L, },
    d,
  )
  let prepared = @moonlibsync.prepare_signature(sig, d)
  let targets : Array[Bytes] = [
    b"",
    old,
    b"!" + old,
    old[0:256].to_owned() + b"\x00\x80\xff" + old[256:].to_owned(),
    old[512:].to_owned() + old[0:256].to_owned() + b"TAIL",
    Bytes::makei(300, i => (0xf0 ^ (i % 13)).to_byte()),
  ]
  for new_bytes in targets {
    let expected_delta = prepared.delta(new_bytes, d)
    let expected_summary = @moonlibsync.inspect_delta(expected_delta, d)
    for step in [1, 5, 63, 64, 65, 1024] {
      let streamed_delta = collect_delta_chunks(
        prepared,
        new_bytes,
        d,
        step,
        drain_each=true,
      )
      assert_eq(streamed_delta, expected_delta)
      let (restored, summary) = apply_patch_chunks(
        old,
        old.length().to_int64(),
        streamed_delta,
        d,
        step,
      )
      assert_eq(restored, new_bytes)
      assert_eq(summary.delta_bytes, expected_summary.delta_bytes)
      assert_eq(summary.instruction_count, expected_summary.instruction_count)
      assert_eq(summary.literal_commands, expected_summary.literal_commands)
      assert_eq(summary.copy_commands, expected_summary.copy_commands)
      assert_eq(summary.literal_bytes, expected_summary.literal_bytes)
      assert_eq(summary.copy_bytes, expected_summary.copy_bytes)
      assert_eq(summary.output_bytes, expected_summary.output_bytes)
    }
  }
}

///|
test "streaming delta > 64 KiB literal flushes bounded instructions and large COPY chunks <= 64 KiB" {
  let d = @moonlibsync.Limits::default()
  // Test >64 KiB all-literal flush in DeltaScanner + 1-byte streaming PatchApplier.
  let empty_sig = @moonlibsync.signature(
    b"",
    @moonlibsync.SignatureOptions::default(),
    d,
  )
  let prepared_empty = @moonlibsync.prepare_signature(empty_sig, d)
  let big_lit = Bytes::makei(70000, i => ((i * 29 + 3) % 256).to_byte())
  let scanner = @moonlibsync.DeltaScanner::new(prepared_empty, d)
  // Default block_len=2048 keeps up to 2048 trailing bytes in the sliding buffer;
  // feeding 68000 bytes emits 65952 miss bytes, triggering an immediate 65536 flush.
  scanner.feed(big_lit[0:68000])
  let first_drain = scanner.take_ready()
  assert_eq(first_drain.length(), 65545)
  scanner.feed(big_lit[68000:])
  let final_drain = scanner.finish()
  let combined_lit_delta = first_drain + final_drain
  let summary_lit = @moonlibsync.inspect_delta(combined_lit_delta, d)
  assert_eq(summary_lit.literal_commands, 2L)
  assert_eq(summary_lit.literal_bytes, 70000L)
  let (restored_lit, applier_sum) = apply_patch_chunks(
    b"", 0L, combined_lit_delta, d, 17,
  )
  assert_eq(restored_lit, big_lit)
  assert_eq(applier_sum.output_bytes, 70000L)

  // Test >64 KiB COPY reading in PatchApplier via custom BasisReader.
  let big_old = Bytes::makei(140000, i => ((i * 17 + 5) % 256).to_byte())
  let big_sig = @moonlibsync.signature(
    big_old,
    @moonlibsync.SignatureOptions::default(),
    d,
  )
  let prepared_big = @moonlibsync.prepare_signature(big_sig, d)
  let copy_delta = collect_delta_chunks(
    prepared_big,
    big_old,
    d,
    8192,
    drain_each=true,
  )
  let reader : CountingReader = { data: big_old, calls: 0, max_len: 0, }
  let (restored_copy, copy_sum) = apply_patch_chunks(
    reader,
    big_old.length().to_int64(),
    copy_delta,
    d,
    3,
  )
  assert_eq(restored_copy, big_old)
  assert_eq(copy_sum.copy_bytes, 140000L)
  assert_true(reader.calls >= 3)
  assert_true(reader.max_len <= 65536)
}

///|
test "streaming state machines enforce limits error precedence atomic update and failure poisoning" {
  let d = @moonlibsync.Limits::default()
  // SignatureHasher: failed update must preserve state and permit smaller finish.
  let hasher = @moonlibsync.SignatureHasher::new(
    { block_len: 4L, strong_sum_len: 16L, },
    { ..d, max_old_bytes: 5L, },
  )
  hasher.update(b"ab")
  let rejected = try {
    hasher.update(b"cdef")
    false
  } catch {
    @moonlibsync.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(rejected)
  hasher.update(b"cde")
  assert_eq(
    hasher.finish(),
    @moonlibsync.signature(b"abcde", { block_len: 4L, strong_sum_len: 16L, }, d),
  )
  let after_finish = try {
    hasher.update(b"")
    false
  } catch {
    @moonlibsync.SyncError::InvalidOptions("stream_finished") => true
    _ => false
  }
  assert_true(after_finish)

  // DeltaScanner: budget failure poisons scanner without mutating PreparedSignature.
  let sig = @moonlibsync.signature(
    b"abcd",
    { block_len: 4L, strong_sum_len: 16L, },
    d,
  )
  let prepared = @moonlibsync.prepare_signature(sig, d)
  let scanner = @moonlibsync.DeltaScanner::new(prepared, {
    ..d,
    max_new_bytes: 3L,
  })
  let feed_err = try {
    scanner.feed(b"abcd")
    false
  } catch {
    @moonlibsync.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(feed_err)
  let poisoned = try {
    let _ = scanner.finish()
    false
  } catch {
    @moonlibsync.SyncError::InvalidOptions("stream_failed") => true
    _ => false
  }
  assert_true(poisoned)
  assert_eq(@moonlibsync.patch(b"abcd", prepared.delta(b"abcd", d), d), b"abcd")

  // PatchApplier: malformed opcode, COPY OOB, short BasisReader read, trailing, and truncated finish.
  let bad_cases : Array[(Int64, Bytes, String)] = [
    (4L, b"\x00\x00\x00\x00\x00", "InvalidDelta"),
    (4L, b"\x72\x73\x02\x36\x55\x00", "InvalidOpcode"),
    (4L, b"\x72\x73\x02\x36\x45\x04\x01\x00", "CopyOutOfBounds"),
    (4L, b"\x72\x73\x02\x36\x00\xff", "TrailingData"),
  ]
  for item in bad_cases {
    let (blen, bytes, expected) = item
    let applier = @moonlibsync.PatchApplier::new(blen, d)
    let actual = try {
      for i in 0..<bytes.length() {
        applier.feed(bytes[i:i + 1], b"abcd", _ => ())
      }
      "ok"
    } catch {
      @moonlibsync.SyncError::InvalidDelta => "InvalidDelta"
      @moonlibsync.SyncError::InvalidOpcode => "InvalidOpcode"
      @moonlibsync.SyncError::CopyOutOfBounds => "CopyOutOfBounds"
      @moonlibsync.SyncError::TrailingData => "TrailingData"
      _ => "other"
    }
    assert_eq(actual, expected)
    let post = try {
      let _ = applier.finish()
      "ok"
    } catch {
      @moonlibsync.SyncError::InvalidOptions("stream_failed") => "stream_failed"
      _ => "other"
    }
    assert_eq(post, "stream_failed")
  }

  // Truncated stream fails on finish().
  let trunc = @moonlibsync.PatchApplier::new(4L, d)
  trunc.feed(b"\x72\x73\x02", b"abcd", _ => ())
  let trunc_err = try {
    let _ = trunc.finish()
    false
  } catch {
    @moonlibsync.SyncError::TruncatedInput => true
    _ => false
  }
  assert_true(trunc_err)

  // Short read from BasisReader raises TruncatedInput and poisons PatchApplier.
  let faulty : FaultyReader = { truncate_after: 0, calls: 0, }
  let applier2 = @moonlibsync.PatchApplier::new(4L, d)
  let short_err = try {
    applier2.feed(b"\x72\x73\x02\x36\x45\x00\x04\x00", faulty, _ => ())
    false
  } catch {
    @moonlibsync.SyncError::TruncatedInput => true
    _ => false
  }
  assert_true(short_err)
}
