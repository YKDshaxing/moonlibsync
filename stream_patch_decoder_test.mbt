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
      @moonlibsync.SyncError::InvalidOptions("stream_finished")
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
      @moonlibsync.SyncError::InvalidOptions("stream_failed")
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
        @moonlibsync.SyncError::InvalidOptions("sha256_max_bytes")
      ) => true
      _ => false
    }
    assert_true(bad)
  }
}
