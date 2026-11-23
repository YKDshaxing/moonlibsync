// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn adler32_ref(data : Bytes) -> UInt32 {
  let mut s1 : UInt32 = 1U
  let mut s2 : UInt32 = 0U
  for i in 0..<data.length() {
    s1 = (s1 + data[i].to_uint()) % 65521U
    s2 = (s2 + s1) % 65521U
  }
  (s2 << 16) | s1
}

///|
fn read_u32_be(data : Bytes, off : Int32) -> UInt32 {
  (data[off].to_uint() << 24) |
  (data[off + 1].to_uint() << 16) |
  (data[off + 2].to_uint() << 8) |
  data[off + 3].to_uint()
}

///|
fn make_incompressible(n : Int32) -> Bytes {
  let buf = FixedArray::make(n, b'\x00')
  let mut rng : UInt32 = 0x12345678U
  for i in 0..<n {
    rng = rng ^ (rng << 13)
    rng = rng ^ (rng >> 17)
    rng = rng ^ (rng << 5)
    buf[i] = (rng & 0xffU).to_byte()
  }
  Bytes::from_array(buf[:])
}

///|
fn assert_valid_zlib_framing(compressed : Bytes, plain : Bytes) -> Unit raise {
  assert_true(compressed.length() >= 8)
  let cmf = compressed[0].to_int()
  let flg = compressed[1].to_int()
  assert_eq(cmf, 0x78)
  assert_eq((cmf * 256 + flg) % 31, 0)
  assert_eq(flg & 0x20, 0)
  let expected_adler = adler32_ref(plain)
  let actual_adler = read_u32_be(compressed, compressed.length() - 4)
  assert_eq(actual_adler, expected_adler)
}

///|
test "compress_zlib and decompress_zlib roundtrip empty small and delta payloads with RFC 1950 header and Adler-32" {
  let d = @lib.Limits::default()
  // Empty payload roundtrip including exact max_output=0 boundary
  let z_empty = @compress.compress_zlib(b""[:], 0L, 1024L)
  assert_valid_zlib_framing(z_empty, b"")
  assert_eq(
    @compress.decompress_zlib(z_empty[:], z_empty.length().to_int64(), 0L),
    b"",
  )

  // Small payload and known Adler-32 check ("Wikipedia" -> 0x11E60398)
  let wiki = b"Wikipedia"
  assert_eq(adler32_ref(wiki), 0x11E60398U)
  let z_wiki = @compress.compress_zlib(wiki[:], 1024L, 1024L)
  assert_valid_zlib_framing(z_wiki, wiki)
  assert_eq(@compress.decompress_zlib(z_wiki[:], 1024L, 1024L), wiki)

  // Stored (level=0) and max (level=9) compression levels
  for lv in [0, 1, 6, 9] {
    let z_lv = @compress.compress_zlib(wiki[:], 1024L, 1024L, level=lv)
    assert_valid_zlib_framing(z_lv, wiki)
    assert_eq(@compress.decompress_zlib(z_lv[:], 1024L, 1024L), wiki)
  }

  // Repetitive text/delta payload shrinks substantially and preserves patch fidelity
  let old_bytes = Bytes::makei(16384, i => (65 + i % 16).to_byte())
  let new_bytes = old_bytes[0:4096].to_owned() +
    Bytes::makei(4096, i => (97 + i % 4).to_byte()) +
    old_bytes[8192:].to_owned()
  let sig = @lib.signature(old_bytes, @lib.SignatureOptions::default(), d)
  let delta = @lib.delta(sig, new_bytes, d)
  let z_delta = @compress.compress_zlib(
    delta[:],
    d.max_new_bytes,
    d.max_output_bytes,
  )
  assert_valid_zlib_framing(z_delta, delta)
  assert_true(z_delta.length() < delta.length())
  let restored_delta = @compress.decompress_zlib(
    z_delta[:],
    d.max_delta_bytes,
    d.max_output_bytes,
  )
  assert_eq(restored_delta, delta)
  assert_eq(@lib.patch(old_bytes, restored_delta, d), new_bytes)

  // Cross-check: stripping RFC 1950 header (2 bytes) + Adler-32 trailer (4 bytes) yields valid raw DEFLATE
  let inner_deflate = z_delta[2:z_delta.length() - 4]
  assert_eq(
    @compress.decompress_deflate(
      inner_deflate,
      d.max_delta_bytes,
      d.max_output_bytes,
    ),
    delta,
  )
}

///|
test "compress_deflate and decompress_deflate roundtrip empty small and delta payloads" {
  let d = @lib.Limits::default()
  // Empty payload roundtrip including exact max_output=0 boundary
  let df_empty = @compress.compress_deflate(b""[:], 0L, 1024L)
  assert_eq(df_empty.length(), 2)
  assert_eq(
    @compress.decompress_deflate(df_empty[:], df_empty.length().to_int64(), 0L),
    b"",
  )

  // Small payload across stored and Huffman levels
  let small = b"moonlibsync raw deflate RFC 1951 payload"
  for lv in [0, 1, 6, 9] {
    let df = @compress.compress_deflate(small[:], 1024L, 1024L, level=lv)
    assert_eq(@compress.decompress_deflate(df[:], 1024L, 1024L), small)
  }

  // Delta payload shrinks substantially and patches cleanly
  let old_bytes = Bytes::makei(16384, i => (65 + i % 16).to_byte())
  let new_bytes = old_bytes[0:4096].to_owned() +
    Bytes::makei(4096, i => (97 + i % 4).to_byte()) +
    old_bytes[8192:].to_owned()
  let sig = @lib.signature(old_bytes, @lib.SignatureOptions::default(), d)
  let delta = @lib.delta(sig, new_bytes, d)
  let df_delta = @compress.compress_deflate(
    delta[:],
    d.max_new_bytes,
    d.max_output_bytes,
  )
  assert_true(df_delta.length() < delta.length())
  let restored_delta = @compress.decompress_deflate(
    df_delta[:],
    d.max_delta_bytes,
    d.max_output_bytes,
  )
  assert_eq(restored_delta, delta)
  assert_eq(@lib.patch(old_bytes, restored_delta, d), new_bytes)
}

///|
test "streaming ZlibEncoder and ZlibDecoder match across 1-byte chunks and small output buffers" {
  let payload = Bytes::makei(9000, i => ((i * 13 + i / 64) % 256).to_byte())
  let enc = @compress.ZlibEncoder::new(10000L, 20000L, level=6)
  let enc_out = FixedArray::make(19, b'\x00')
  let z_buf = @buffer.Buffer(capacity=256)
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
        z_buf.write_bytesview(Bytes::from_array(enc_out[0:st.produced])[:])
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
      z_buf.write_bytesview(Bytes::from_array(enc_out[0:st.produced])[:])
    }
    if st.status is Done {
      break
    }
  }
  let enc_sum = enc.summary()
  let z = z_buf.to_bytes()
  assert_valid_zlib_framing(z, payload)
  assert_eq(enc_sum.input_bytes, payload.length().to_int64())
  assert_eq(enc_sum.output_bytes, z.length().to_int64())

  // Decode 1 byte at a time into a 17-byte output buffer
  let dec = @compress.ZlibDecoder::new(
    z.length().to_int64(),
    payload.length().to_int64(),
  )
  let dec_out = FixedArray::make(17, b'\x00')
  let plain_buf = @buffer.Buffer(capacity=256)
  for i in 0..<z.length() {
    let chunk = z[i:i + 1]
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
  assert_eq(dec_sum.input_bytes, z.length().to_int64())
  assert_eq(dec_sum.output_bytes, payload.length().to_int64())
  assert_eq(plain_buf.to_bytes(), payload)
}

///|
test "streaming DeflateEncoder and DeflateDecoder match across 1-byte chunks and small output buffers" {
  let payload = Bytes::makei(9000, i => ((i * 13 + i / 64) % 256).to_byte())
  let enc = @compress.DeflateEncoder::new(10000L, 20000L, level=6)
  let enc_out = FixedArray::make(19, b'\x00')
  let df_buf = @buffer.Buffer(capacity=256)
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
        df_buf.write_bytesview(Bytes::from_array(enc_out[0:st.produced])[:])
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
      df_buf.write_bytesview(Bytes::from_array(enc_out[0:st.produced])[:])
    }
    if st.status is Done {
      break
    }
  }
  let enc_sum = enc.summary()
  let df = df_buf.to_bytes()
  assert_eq(enc_sum.input_bytes, payload.length().to_int64())
  assert_eq(enc_sum.output_bytes, df.length().to_int64())

  // Decode 1 byte at a time into a 17-byte output buffer
  let dec = @compress.DeflateDecoder::new(
    df.length().to_int64(),
    payload.length().to_int64(),
  )
  let dec_out = FixedArray::make(17, b'\x00')
  let plain_buf = @buffer.Buffer(capacity=256)
  for i in 0..<df.length() {
    let chunk = df[i:i + 1]
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
  assert_eq(dec_sum.input_bytes, df.length().to_int64())
  assert_eq(dec_sum.output_bytes, payload.length().to_int64())
  assert_eq(plain_buf.to_bytes(), payload)
}

///|
test "zlib encoder step finish=true preserves all bytes on large incompressible chunks into 64 KiB and 16 B buffers" {
  for total_len in [65536, 200000] {
    let data = make_incompressible(total_len)
    for out_cap in [65536, 16] {
      let enc = @compress.ZlibEncoder::new(
        total_len.to_int64(),
        (total_len + 65536).to_int64(),
        level=6,
      )
      let out_buf = FixedArray::make(out_cap, b'\x00')
      let compressed = @buffer.Buffer(capacity=256)
      let mut pos = 0
      while pos < data.length() {
        let step = enc.step(data[pos:], out_buf, finish=true)
        if step.produced > 0 {
          compressed.write_bytes(Bytes::from_array(out_buf[0:step.produced]))
        }
        pos = pos + step.consumed
        if step.status is Done {
          assert_eq(pos, data.length())
          break
        }
      }
      let mut finished = try {
        let _ = enc.summary()
        true
      } catch {
        _ => false
      }
      while !finished {
        let step = enc.step(b""[:], out_buf, finish=true)
        if step.produced > 0 {
          compressed.write_bytes(Bytes::from_array(out_buf[0:step.produced]))
        }
        if step.status is Done {
          finished = true
        }
      }
      let summary = enc.summary()
      assert_eq(summary.input_bytes, total_len.to_int64())
      let z_bytes = compressed.to_bytes()
      assert_valid_zlib_framing(z_bytes, data)
      let restored = @compress.decompress_zlib(
        z_bytes[:],
        (total_len + 65536).to_int64(),
        total_len.to_int64(),
      )
      assert_eq(restored, data)
    }
  }
}

///|
test "deflate encoder step finish=true preserves all bytes on large incompressible chunks into 64 KiB and 16 B buffers" {
  for total_len in [65536, 200000] {
    let data = make_incompressible(total_len)
    for out_cap in [65536, 16] {
      let enc = @compress.DeflateEncoder::new(
        total_len.to_int64(),
        (total_len + 65536).to_int64(),
        level=6,
      )
      let out_buf = FixedArray::make(out_cap, b'\x00')
      let compressed = @buffer.Buffer(capacity=256)
      let mut pos = 0
      while pos < data.length() {
        let step = enc.step(data[pos:], out_buf, finish=true)
        if step.produced > 0 {
          compressed.write_bytes(Bytes::from_array(out_buf[0:step.produced]))
        }
        pos = pos + step.consumed
        if step.status is Done {
          assert_eq(pos, data.length())
          break
        }
      }
      let mut finished = try {
        let _ = enc.summary()
        true
      } catch {
        _ => false
      }
      while !finished {
        let step = enc.step(b""[:], out_buf, finish=true)
        if step.produced > 0 {
          compressed.write_bytes(Bytes::from_array(out_buf[0:step.produced]))
        }
        if step.status is Done {
          finished = true
        }
      }
      let summary = enc.summary()
      assert_eq(summary.input_bytes, total_len.to_int64())
      let restored = @compress.decompress_deflate(
        compressed.to_bytes()[:],
        (total_len + 65536).to_int64(),
        total_len.to_int64(),
      )
      assert_eq(restored, data)
    }
  }
}

///|
test "zlib decoder rejects zip bomb trailing data truncation corruption and invalid options" {
  // Zip bomb: 1 MiB of zeros compresses to ~1 KiB; max_output=4096 must reject with LimitExceeded
  let bomb_plain = Bytes::make(1048576, b'\x00')
  let bomb_z = @compress.compress_zlib(bomb_plain[:], 2000000L, 100000L)
  assert_true(bomb_z.length() < 4096)
  let bomb_rejected = try {
    let _ = @compress.decompress_zlib(bomb_z[:], 100000L, 4096L)
    false
  } catch {
    @lib.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(bomb_rejected)

  // Exact max_output boundary succeeds, off-by-one fails with LimitExceeded
  let sample = b"0123456789abcdef"
  let sample_z = @compress.compress_zlib(sample[:], 100L, 200L)
  assert_eq(@compress.decompress_zlib(sample_z[:], 200L, 16L), sample)
  let off_by_one = try {
    let _ = @compress.decompress_zlib(sample_z[:], 200L, 15L)
    false
  } catch {
    @lib.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(off_by_one)

  // Trailing single byte in same chunk -> TrailingData
  let with_trailing = sample_z + b"\x00"
  let trailing_same = try {
    let _ = @compress.decompress_zlib(with_trailing[:], 200L, 200L)
    false
  } catch {
    @lib.SyncError::TrailingData => true
    _ => false
  }
  assert_true(trailing_same)

  // Trailing byte buffered across small-output-buffer backpressure -> TrailingData via unused_input()
  let trailing_backpressure = try {
    let dec = @compress.ZlibDecoder::new(200L, 200L)
    let small_out = FixedArray::make(4, b'\x00')
    let mut pos = 0
    while true {
      let st = dec.step(with_trailing[pos:], small_out)
      pos = pos + st.consumed
      match st.status {
        NeedMoreOutput => continue
        NeedMoreInput => if pos >= with_trailing.length() { break }
        Done => break
      }
    }
    let _ = dec.finish()
    false
  } catch {
    @lib.SyncError::TrailingData => true
    _ => false
  }
  assert_true(trailing_backpressure)

  // Trailing byte fed as separate chunk after Done -> TrailingData
  let dec = @compress.ZlibDecoder::new(200L, 200L)
  let out = FixedArray::make(64, b'\x00')
  let st = dec.step(sample_z[:], out)
  assert_true(st.status is Done)
  let trailing_next = try {
    let _ = dec.step(b"x"[:], out)
    false
  } catch {
    @lib.SyncError::TrailingData => true
    _ => false
  }
  assert_true(trailing_next)

  // Truncated stream (empty, 1-byte header, missing last byte) -> TruncatedInput
  for
    trunc in [
      b"",
      sample_z[0:1].to_owned(),
      sample_z[0:sample_z.length() - 1].to_owned(),
    ] {
    let ok = try {
      let _ = @compress.decompress_zlib(trunc[:], 200L, 200L)
      false
    } catch {
      @lib.SyncError::TruncatedInput => true
      _ => false
    }
    assert_true(ok)
  }

  // Corrupt header (bad CMF/FCHECK), FDICT bit set without dict, corrupt DEFLATE body, corrupt Adler-32 -> InvalidDelta
  let bad_header = b"\x00\x00" + sample_z[2:].to_owned()
  let bad_fcheck = b"\x78\x02" + sample_z[2:].to_owned()
  let bad_fdict = b"\x78\x20\x00\x00\x00\x01" + sample_z[2:].to_owned()
  let bad_adler = sample_z[0:sample_z.length() - 1].to_owned() +
    Bytes::from_array([
      (sample_z[sample_z.length() - 1].to_int() ^ 0xff).to_byte(),
    ])
  // Corrupt DEFLATE body: reserved block type (btype=3 -> 0b111 = 0x07)
  let bad_body = b"\x78\x01\x07\x00\x00\x00\x00\x01"
  for corrupt in [bad_header, bad_fcheck, bad_fdict, bad_adler, bad_body] {
    let ok = try {
      let _ = @compress.decompress_zlib(corrupt[:], 200L, 200L)
      false
    } catch {
      @lib.SyncError::InvalidDelta => true
      _ => false
    }
    assert_true(ok)
  }

  // Invalid compression levels (10 and -1) -> InvalidOptions("level")
  for bad_lv in [10, -1] {
    let ok = try {
      let _ = @compress.compress_zlib(b"a"[:], 10L, 100L, level=bad_lv)
      false
    } catch {
      @lib.SyncError::InvalidOptions("level") => true
      _ => false
    }
    assert_true(ok)
  }
}

///|
test "deflate decoder rejects zip bomb trailing data truncation corruption and invalid options" {
  // Zip bomb: 1 MiB of zeros compresses to ~1 KiB; max_output=4096 must reject with LimitExceeded
  let bomb_plain = Bytes::make(1048576, b'\x00')
  let bomb_df = @compress.compress_deflate(bomb_plain[:], 2000000L, 100000L)
  assert_true(bomb_df.length() < 4096)
  let bomb_rejected = try {
    let _ = @compress.decompress_deflate(bomb_df[:], 100000L, 4096L)
    false
  } catch {
    @lib.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(bomb_rejected)

  // Exact max_output boundary succeeds (including exact-size streaming output buffer), off-by-one fails
  let sample = b"0123456789abcdef"
  let sample_df = @compress.compress_deflate(sample[:], 100L, 200L)
  assert_eq(@compress.decompress_deflate(sample_df[:], 200L, 16L), sample)
  let exact_stream_dec = @compress.DeflateDecoder::new(200L, 16L)
  let exact_out = FixedArray::make(16, b'\x00')
  let exact_buf = @buffer.Buffer(capacity=16)
  let mut exact_pos = 0
  while true {
    let st = exact_stream_dec.step(sample_df[exact_pos:], exact_out)
    exact_pos = exact_pos + st.consumed
    if st.produced > 0 {
      exact_buf.write_bytesview(Bytes::from_array(exact_out[0:st.produced])[:])
    }
    match st.status {
      NeedMoreOutput => continue
      NeedMoreInput => if exact_pos >= sample_df.length() { break }
      Done => break
    }
  }
  let exact_sum = exact_stream_dec.finish()
  assert_eq(exact_sum.output_bytes, 16L)
  assert_eq(exact_buf.to_bytes(), sample)

  let off_by_one = try {
    let _ = @compress.decompress_deflate(sample_df[:], 200L, 15L)
    false
  } catch {
    @lib.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(off_by_one)

  // Trailing single byte in same chunk -> TrailingData
  let with_trailing = sample_df + b"\x00"
  let trailing_same = try {
    let _ = @compress.decompress_deflate(with_trailing[:], 200L, 200L)
    false
  } catch {
    @lib.SyncError::TrailingData => true
    _ => false
  }
  assert_true(trailing_same)

  // Trailing byte fed as separate chunk after Done -> TrailingData
  let dec = @compress.DeflateDecoder::new(200L, 200L)
  let out = FixedArray::make(64, b'\x00')
  let st = dec.step(sample_df[:], out)
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
  for trunc in [b"", sample_df[0:sample_df.length() - 1].to_owned()] {
    let ok = try {
      let _ = @compress.decompress_deflate(trunc[:], 200L, 200L)
      false
    } catch {
      @lib.SyncError::TruncatedInput => true
      _ => false
    }
    assert_true(ok)
  }

  // Corrupt DEFLATE stream (reserved block type 3, invalid stored NLEN mismatch) -> InvalidDelta
  let bad_btype = b"\x07"
  let bad_stored_nlen = b"\x01\x04\x00\x00\x00abcd"
  for corrupt in [bad_btype, bad_stored_nlen] {
    let ok = try {
      let _ = @compress.decompress_deflate(corrupt[:], 200L, 200L)
      false
    } catch {
      @lib.SyncError::InvalidDelta => true
      _ => false
    }
    assert_true(ok)
  }

  // Invalid compression levels (10 and -1) -> InvalidOptions("level")
  for bad_lv in [10, -1] {
    let ok = try {
      let _ = @compress.compress_deflate(b"a"[:], 10L, 100L, level=bad_lv)
      false
    } catch {
      @lib.SyncError::InvalidOptions("level") => true
      _ => false
    }
    assert_true(ok)
  }
}

///|
test "zlib and deflate enforce encoder/decoder limits state contracts and large-stream trailing data" {
  // Exact empty output bounds and off-by-one LimitExceeded on encoders
  let z_empty = @compress.compress_zlib(b""[:], 0L, 8L)
  assert_eq(z_empty.length(), 8)
  let z_out_limit = try {
    let _ = @compress.compress_zlib(b""[:], 0L, 7L)
    false
  } catch {
    @lib.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(z_out_limit)

  let df_empty = @compress.compress_deflate(b""[:], 0L, 2L)
  assert_eq(df_empty.length(), 2)
  let df_out_limit = try {
    let _ = @compress.compress_deflate(b""[:], 0L, 1L)
    false
  } catch {
    @lib.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(df_out_limit)

  // Encoder input limits
  let z_in_limit = try {
    let _ = @compress.compress_zlib(b"abc"[:], 2L, 100L)
    false
  } catch {
    @lib.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(z_in_limit)

  let df_in_limit = try {
    let _ = @compress.compress_deflate(b"abc"[:], 2L, 100L)
    false
  } catch {
    @lib.SyncError::LimitExceeded => true
    _ => false
  }
  assert_true(df_in_limit)

  // Negative bounds rejected with InvalidOptions
  let bad_z_bounds = try {
    let _ = @compress.ZlibEncoder::new(-1L, 100L)
    false
  } catch {
    @lib.SyncError::InvalidOptions("max_input") => true
    _ => false
  }
  assert_true(bad_z_bounds)

  let bad_df_bounds = try {
    let _ = @compress.DeflateDecoder::new(100L, -1L)
    false
  } catch {
    @lib.SyncError::InvalidOptions("max_output") => true
    _ => false
  }
  assert_true(bad_df_bounds)

  // Summary before Done -> TruncatedInput; step after Done -> InvalidOptions("stream_finished")
  let z_enc = @compress.ZlibEncoder::new(100L, 100L)
  let z_pre_sum = try {
    let _ = z_enc.summary()
    false
  } catch {
    @lib.SyncError::TruncatedInput => true
    _ => false
  }
  assert_true(z_pre_sum)
  let out = FixedArray::make(64, b'\x00')
  let st = z_enc.step(b"hi"[:], out, finish=true)
  assert_true(st.status is Done)
  let z_after_done = try {
    let _ = z_enc.step(b""[:], out, finish=true)
    false
  } catch {
    @lib.SyncError::InvalidOptions("stream_finished") => true
    _ => false
  }
  assert_true(z_after_done)

  // Large (>65,536 B compressed) stream with trailing byte -> TrailingData for both Zlib and Raw DEFLATE
  let big = make_incompressible(100000)
  let big_z = @compress.compress_zlib(big[:], 100000L, 200000L)
  assert_true(big_z.length() > 65536)
  assert_eq(@compress.decompress_zlib(big_z[:], 200000L, 100000L), big)
  let big_z_trailing = try {
    let _ = @compress.decompress_zlib((big_z + b"\x00")[:], 200000L, 100000L)
    false
  } catch {
    @lib.SyncError::TrailingData => true
    _ => false
  }
  assert_true(big_z_trailing)

  let big_df = @compress.compress_deflate(big[:], 100000L, 200000L)
  assert_true(big_df.length() > 65536)
  assert_eq(@compress.decompress_deflate(big_df[:], 200000L, 100000L), big)
  let big_df_trailing = try {
    let _ = @compress.decompress_deflate(
      (big_df + b"\x00")[:],
      200000L,
      100000L,
    )
    false
  } catch {
    @lib.SyncError::TrailingData => true
    _ => false
  }
  assert_true(big_df_trailing)
}
