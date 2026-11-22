// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn drive_patch_decoder(
  old : Bytes,
  delta_bytes : Bytes,
  limits : @moonlibsync.Limits,
  split : Int32,
) -> (Bytes, @moonlibsync.DeltaSummary, Int32) raise {
  let dec = @moonlibsync.PatchDecoder::new(old.length().to_int64(), limits)
  let out = Buffer()
  let mut copy_steps = 0
  let mut off = 0
  while off < delta_bytes.length() {
    let rem = delta_bytes.length() - off
    let take = if rem < split { rem } else { split }
    let chunk = delta_bytes[off:off + take]
    let mut pos = 0
    while pos < chunk.length() || dec.has_pending_copy() {
      let (consumed, step) = dec.step(chunk[pos:])
      pos = pos + consumed
      match step {
        NeedInput => ()
        EmitLiteral(lit) => out.write_bytesview(lit)
        CopyBasis(basis_off, basis_len) => {
          assert_true(basis_len > 0 && basis_len <= 65536)
          copy_steps = copy_steps + 1
          let start = basis_off.to_int()
          out.write_bytesview(old[start:start + basis_len])
        }
      }
    }
    off = off + take
  }
  while dec.has_pending_copy() {
    let (_, step) = dec.step(b""[:])
    match step {
      CopyBasis(basis_off, basis_len) => {
        copy_steps = copy_steps + 1
        let start = basis_off.to_int()
        out.write_bytesview(old[start:start + basis_len])
      }
      _ => abort("expected pending CopyBasis")
    }
  }
  (out.to_bytes(), dec.finish(), copy_steps)
}

///|
test "sans-io PatchDecoder 1-byte splits and >64KiB COPY steps match patch" {
  let d = @moonlibsync.Limits::default()
  let old = Bytes::makei(70000, i => ((i * 53 + 17) % 256).to_byte())
  let new_bytes = b"HEAD-" + old + b"-TAIL"
  let sig = @moonlibsync.signature(
    old,
    @moonlibsync.SignatureOptions::default(),
    d,
  )
  let delta_bytes = @moonlibsync.delta(sig, new_bytes, d)
  for split in [1, 7, 1024] {
    let (out, summary, copy_steps) = drive_patch_decoder(
      old, delta_bytes, d, split,
    )
    assert_eq(out, new_bytes)
    assert_eq(summary.output_bytes, new_bytes.length().to_int64())
    assert_true(copy_steps >= 2)
  }

  // Test single-command 70000-byte COPY opcode directly:
  // COPY(0, 70000): ow=1 (0x00), lw=4 (0x00011170) -> opcode 0x45 + 2 = 0x47.
  let big_copy_delta = b"\x72\x73\x02\x36\x47\x00\x00\x01\x11\x70\x00"
  let (big_out, big_sum, big_steps) = drive_patch_decoder(
    old, big_copy_delta, d, 3,
  )
  assert_eq(big_out, old)
  assert_eq(big_sum.copy_commands, 1L)
  assert_eq(big_sum.copy_bytes, 70000L)
  assert_eq(big_steps, 2)
}

///|
test "sans-io PatchDecoder enforces errors trailing data truncation and poisoning" {
  let d = @moonlibsync.Limits::default()
  // Negative basis_len -> InvalidOptions("basis_len")
  let neg = try {
    let _ = @moonlibsync.PatchDecoder::new(-1L, d)
    false
  } catch {
    @moonlibsync.SyncError::InvalidOptions("basis_len") => true
    _ => false
  }
  assert_true(neg)

  // TrailingData both same chunk and following chunk, then stream_failed.
  let dec1 = @moonlibsync.PatchDecoder::new(4L, d)
  let t1 = try {
    let chunk = b"\x72\x73\x02\x36\x00\x99"
    let mut pos = 0
    while pos < chunk.length() || dec1.has_pending_copy() {
      let (consumed, _) = dec1.step(chunk[pos:])
      pos = pos + consumed
    }
    false
  } catch {
    @moonlibsync.SyncError::TrailingData => true
    _ => false
  }
  assert_true(t1)
  let f1 = try {
    let _ = dec1.finish()
    false
  } catch {
    @moonlibsync.SyncError::InvalidOptions("stream_failed") => true
    _ => false
  }
  assert_true(f1)

  // Separate trailing chunk after valid END.
  let dec2 = @moonlibsync.PatchDecoder::new(4L, d)
  let (c2, s2) = dec2.step(b"\x72\x73\x02\x36\x00"[:])
  assert_eq(c2, 5)
  assert_true(s2 is NeedInput)
  let t2 = try {
    let _ = dec2.step(b"\x01"[:])
    false
  } catch {
    @moonlibsync.SyncError::TrailingData => true
    _ => false
  }
  assert_true(t2)

  // CopyOutOfBounds & TruncatedInput without finishing InCopy.
  let dec3 = @moonlibsync.PatchDecoder::new(4L, d)
  let oob = try {
    let _ = dec3.step(b"\x72\x73\x02\x36\x45\x02\x03\x00"[:])
    false
  } catch {
    @moonlibsync.SyncError::CopyOutOfBounds => true
    _ => false
  }
  assert_true(oob)

  // delta_bytes limit exceeded mid-stream.
  let dec4 = @moonlibsync.PatchDecoder::new(4L, { ..d, max_delta_bytes: 5L, })
  let lim = try {
    let chunk = b"\x72\x73\x02\x36\x01x\x00"
    let mut pos = 0
    while pos < chunk.length() {
      let (consumed, _) = dec4.step(chunk[pos:])
      pos = pos + consumed
    }
    false
  } catch {
    @moonlibsync.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(lim)
}

///|
test "streaming Sha256Hasher matches known vectors incremental splits and enforces limits" {
  // Known SHA-256 vectors for "" and "abc".
  let h0 = @moonlibsync.Sha256Hasher::new(0L)
  let d0 = h0.finish()
  assert_eq(d0.byte_length, 0L)
  assert_eq(
    d0.sha256,
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )

  let h1 = @moonlibsync.Sha256Hasher::new(3L)
  h1.update(b"a"[:])
  h1.update(b""[:])
  h1.update(b"bc"[:])
  let d1 = h1.finish()
  assert_eq(d1.byte_length, 3L)
  assert_eq(
    d1.sha256,
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )

  // Reuse after finish -> InvalidOptions("stream_finished")
  let after_finish = try {
    h1.update(b"x"[:])
    false
  } catch {
    @moonlibsync.ManifestError::Core(
      @moonlibsync.SyncError::InvalidOptions("stream_finished"),
    ) => true
    _ => false
  }
  assert_true(after_finish)

  // Multi-block streaming matches create_basis_info SHA-256 exactly.
  let lim = @moonlibsync.Limits::default()
  let payload = Bytes::makei(4099, i => ((i * 37 + 11) % 256).to_byte())
  let expected_sig = @moonlibsync.signature(
    payload,
    @moonlibsync.SignatureOptions::default(),
    lim,
  )
  let info = @moonlibsync.create_basis_info(payload, expected_sig, lim)
  let hasher = @moonlibsync.Sha256Hasher::new(payload.length().to_int64())
  let mut pos = 0
  while pos < payload.length() {
    let rem = payload.length() - pos
    let take = if rem < 17 { rem } else { 17 }
    hasher.update(payload[pos:pos + take])
    pos = pos + take
  }
  let digest = hasher.finish()
  assert_eq(digest.byte_length, info.basis.byte_length)
  assert_eq(digest.sha256, info.basis.sha256)

  // Budget exceed poisons hasher.
  let capped = @moonlibsync.Sha256Hasher::new(4L)
  capped.update(b"ab"[:])
  let over = try {
    capped.update(b"cde"[:])
    false
  } catch {
    @moonlibsync.ManifestError::ResourceLimit("sha256_input") => true
    _ => false
  }
  assert_true(over)
  let poisoned = try {
    let _ = capped.finish()
    false
  } catch {
    @moonlibsync.ManifestError::Core(
      @moonlibsync.SyncError::InvalidOptions("stream_failed"),
    ) => true
    _ => false
  }
  assert_true(poisoned)

  // Invalid max_bytes -> InvalidOptions("sha256_max_bytes")
  for bad_max in [-1L, 2147483648L] {
    let bad = try {
      let _ = @moonlibsync.Sha256Hasher::new(bad_max)
      false
    } catch {
      @moonlibsync.ManifestError::Core(
        @moonlibsync.SyncError::InvalidOptions("sha256_max_bytes"),
      ) => true
      _ => false
    }
    assert_true(bad)
  }
}

///|
test "PatchDecoder format_only and feed_inspect match inspect_delta and check_patch across splits" {
  let d = @moonlibsync.Limits::default()
  // Format-valid delta with high UInt64 COPY offset (0xffffffff00000000, len 12) + literal.
  let high_delta = b"\x72\x73\x02\x36" +
    b"\x51\xff\xff\xff\xff\x00\x00\x00\x00\x0c" +
    b"\x03abc\x00"
  let expected = @moonlibsync.inspect_delta(high_delta, d)
  let dec_fmt = @moonlibsync.PatchDecoder::new_format_only(d)
  for i in 0..<high_delta.length() {
    dec_fmt.feed_inspect(high_delta[i:i + 1])
  }
  let got = dec_fmt.finish()
  assert_eq(got.delta_bytes, expected.delta_bytes)
  assert_eq(got.instruction_count, expected.instruction_count)
  assert_eq(got.literal_commands, expected.literal_commands)
  assert_eq(got.copy_commands, expected.copy_commands)
  assert_eq(got.literal_bytes, expected.literal_bytes)
  assert_eq(got.copy_bytes, expected.copy_bytes)
  assert_eq(got.output_bytes, expected.output_bytes)

  // Calling step() on format_only decoder is rejected.
  let dec_step = @moonlibsync.PatchDecoder::new_format_only(d)
  let step_rejected = try {
    let _ = dec_step.step(high_delta[:])
    false
  } catch {
    @moonlibsync.SyncError::InvalidOptions("format_only_decoder") => true
    _ => false
  }
  assert_true(step_rejected)

  // Basis-bound feed_inspect rejects high COPY offset as CopyOutOfBounds,
  // and matches check_patch on valid multi-command deltas.
  let dec_oob = @moonlibsync.PatchDecoder::new(100L, d)
  let oob = try {
    dec_oob.feed_inspect(high_delta[:])
    false
  } catch {
    @moonlibsync.SyncError::CopyOutOfBounds => true
    _ => false
  }
  assert_true(oob)

  let basis = Bytes::makei(4096, i => ((i * 29 + 7) % 256).to_byte())
  let new_bytes = basis[0:2048].to_owned() +
    b"INSPECT" +
    basis[2055:].to_owned()
  let sig = @moonlibsync.signature(
    basis,
    { block_len: 512L, strong_sum_len: 16L, },
    d,
  )
  let delta_bytes = @moonlibsync.delta(sig, new_bytes, d)
  let checked = @moonlibsync.check_patch(
    basis.length().to_int64(),
    delta_bytes,
    d,
  )
  let dec_check = @moonlibsync.PatchDecoder::new(basis.length().to_int64(), d)
  for i in 0..<delta_bytes.length() {
    dec_check.feed_inspect(delta_bytes[i:i + 1])
  }
  let got_check = dec_check.finish()
  assert_eq(got_check.delta_bytes, checked.summary.delta_bytes)
  assert_eq(got_check.output_bytes, checked.summary.output_bytes)
  assert_eq(got_check.copy_bytes, checked.summary.copy_bytes)
  assert_eq(got_check.literal_bytes, checked.summary.literal_bytes)
}
