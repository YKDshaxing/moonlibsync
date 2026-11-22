// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "compress_gzip and decompress_gzip roundtrip empty small and delta payloads" {
  let d = @lib.Limits::default()
  // Empty payload roundtrip including exact max_output=0 boundary
  let gz_empty = @compress.compress_gzip(b""[:], 0L, 1024L)
  assert_true(gz_empty.length() >= 18)
  assert_eq(
    @compress.decompress_gzip(gz_empty[:], gz_empty.length().to_int64(), 0L),
    b"",
  )

  // Repetitive text/delta payload shrinks substantially
  let old_bytes = Bytes::makei(16384, i => (65 + i % 16).to_byte())
  let new_bytes = old_bytes[0:4096].to_owned() +
    Bytes::makei(4096, i => (97 + i % 4).to_byte()) +
    old_bytes[8192:].to_owned()
  let sig = @lib.signature(old_bytes, @lib.SignatureOptions::default(), d)
  let delta = @lib.delta(sig, new_bytes, d)
  let gz_delta = @compress.compress_gzip(
    delta[:],
    d.max_new_bytes,
    d.max_output_bytes,
  )
  assert_true(gz_delta.length() < delta.length())
  let restored_delta = @compress.decompress_gzip(
    gz_delta[:],
    d.max_delta_bytes,
    d.max_output_bytes,
  )
  assert_eq(restored_delta, delta)
  assert_eq(@lib.patch(old_bytes, restored_delta, d), new_bytes)
}

///|
test "streaming GzipEncoder and GzipDecoder match across 1-byte chunks and small output buffers" {
  let payload = Bytes::makei(9000, i => ((i * 13 + i / 64) % 256).to_byte())
  let enc = @compress.GzipEncoder::new(10000L, 20000L, level=6)
  let enc_out = FixedArray::make(19, b'\x00')
  let gz_buf = @buffer.Buffer()
  let mut pos = 0
  while pos < payload.length() {
    let rem = payload.length() - pos
    let take = if rem < 11 { rem } else { 11 }
    let chunk = payload[pos:pos + take]
    let mut cpos = 0
    while true {
      let st = enc.step(chunk[cpos:], enc_out, finish=false)
      cpos = cpos + st.consumed
      if st.produced > 0 {
        gz_buf.write_bytesview(Bytes::from_array(enc_out[0:st.produced])[:])
      }
      match st.status {
        NeedMoreOutput => continue
        NeedMoreInput => if cpos >= chunk.length() { break }
        Done => break
      }
    }
    pos = pos + take
  }
  while true {
    let st = enc.step(b""[:], enc_out, finish=true)
    if st.produced > 0 {
      gz_buf.write_bytesview(Bytes::from_array(enc_out[0:st.produced])[:])
    }
    if st.status is Done {
      break
    }
  }
  let enc_sum = enc.summary()
  let gz = gz_buf.to_bytes()
  assert_eq(enc_sum.input_bytes, payload.length().to_int64())
  assert_eq(enc_sum.output_bytes, gz.length().to_int64())

  // Decode 1 byte at a time into a 17-byte output buffer
  let dec = @compress.GzipDecoder::new(
    gz.length().to_int64(),
    payload.length().to_int64(),
  )
  let dec_out = FixedArray::make(17, b'\x00')
  let plain_buf = @buffer.Buffer()
  for i in 0..<gz.length() {
    let chunk = gz[i:i + 1]
    let mut cpos = 0
    while true {
      let st = dec.step(chunk[cpos:], dec_out)
      cpos = cpos + st.consumed
      if st.produced > 0 {
        plain_buf.write_bytesview(Bytes::from_array(dec_out[0:st.produced])[:])
      }
      match st.status {
        NeedMoreOutput => continue
        NeedMoreInput => if cpos >= chunk.length() { break }
        Done => break
      }
    }
  }
  let dec_sum = dec.finish()
  assert_eq(dec_sum.input_bytes, gz.length().to_int64())
  assert_eq(dec_sum.output_bytes, payload.length().to_int64())
  assert_eq(plain_buf.to_bytes(), payload)
}

///|
test "gzip decoder rejects zip bomb trailing data truncation and corruption" {
  // Zip bomb: 1 MiB of zeros compresses to ~1 KiB; max_output=4096 must reject with LimitExceeded
  let bomb_plain = Bytes::make(1048576, b'\x00')
  let bomb_gz = @compress.compress_gzip(bomb_plain[:], 2000000L, 100000L)
  assert_true(bomb_gz.length() < 4096)
  let bomb_rejected = try {
    let _ = @compress.decompress_gzip(bomb_gz[:], 100000L, 4096L)
    false
  } catch {
    @lib.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(bomb_rejected)

  // Exact boundary succeeds, boundary - 1 fails
  let sample = b"0123456789abcdef"
  let sample_gz = @compress.compress_gzip(sample[:], 100L, 200L)
  assert_eq(@compress.decompress_gzip(sample_gz[:], 200L, 16L), sample)
  let off_by_one = try {
    let _ = @compress.decompress_gzip(sample_gz[:], 200L, 15L)
    false
  } catch {
    @lib.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(off_by_one)

  // Trailing single byte in same buffer -> TrailingData
  let with_trailing = sample_gz + b"\x00"
  let trailing_same = try {
    let _ = @compress.decompress_gzip(with_trailing[:], 200L, 200L)
    false
  } catch {
    @lib.SyncError::TrailingData => true
    _ => false
  }
  assert_true(trailing_same)

  // Concatenated second gzip member -> rejected as TrailingData (single-member framing)
  let multi = sample_gz + sample_gz
  let multi_rejected = try {
    let _ = @compress.decompress_gzip(multi[:], 400L, 400L)
    false
  } catch {
    @lib.SyncError::TrailingData => true
    _ => false
  }
  assert_true(multi_rejected)

  // Trailing byte fed as separate chunk after Done -> TrailingData
  let dec = @compress.GzipDecoder::new(200L, 200L)
  let out = FixedArray::make(64, b'\x00')
  let st = dec.step(sample_gz[:], out)
  assert_true(st.status is Done)
  let trailing_next = try {
    let _ = dec.step(b"x"[:], out)
    false
  } catch {
    @lib.SyncError::TrailingData => true
    _ => false
  }
  assert_true(trailing_next)

  // Truncated stream (empty or missing last byte) -> TruncatedInput
  for trunc in [b"", sample_gz[0:sample_gz.length() - 1].to_owned()] {
    let ok = try {
      let _ = @compress.decompress_gzip(trunc[:], 200L, 200L)
      false
    } catch {
      @lib.SyncError::TruncatedInput => true
      _ => false
    }
    assert_true(ok)
  }

  // Corrupted magic and corrupted CRC -> InvalidDelta
  let bad_magic = b"\x00\x00" + sample_gz[2:].to_owned()
  let bad_crc = sample_gz[0:sample_gz.length() - 5].to_owned() +
    Bytes::from_array([
      (sample_gz[sample_gz.length() - 5].to_int() ^ 0xff).to_byte(),
    ]) +
    sample_gz[sample_gz.length() - 4:].to_owned()
  for corrupt in [bad_magic, bad_crc] {
    let ok = try {
      let _ = @compress.decompress_gzip(corrupt[:], 200L, 200L)
      false
    } catch {
      @lib.SyncError::InvalidDelta => true
      _ => false
    }
    assert_true(ok)
  }

  // Invalid options
  let bad_level = try {
    let _ = @compress.compress_gzip(b"a"[:], 10L, 100L, level=10)
    false
  } catch {
    @lib.SyncError::InvalidOptions("level") => true
    _ => false
  }
  assert_true(bad_level)
}
