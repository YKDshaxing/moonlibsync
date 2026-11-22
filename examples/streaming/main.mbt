// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn append_bytes(buf : Array[Byte], data : BytesView) -> Unit {
  for byte in data {
    buf.push(byte)
  }
}

///|
fn run() -> Unit raise {
  let limits = @lib.Limits::default()
  let opts : @lib.SignatureOptions = { block_len: 512L, strong_sum_len: 16L, }
  let old = Bytes::makei(10240, i => {
    ((i * 73 + 19 + i / 512 * 11) % 256).to_byte()
  })
  let new = old[0:2048].to_owned() +
    b"---STREAMING-PATCH---" +
    old[2069:8192].to_owned() +
    b"TAIL!"

  // 1. Streaming signature generation with irregular chunks + incremental take_ready().
  let hasher = @lib.SignatureHasher::new(opts, limits)
  let sig_buf : Array[Byte] = []
  let mut off = 0
  for step in [13, 300, 2048, 700, 1024] {
    if off < old.length() {
      let end = if off + step > old.length() {
        old.length()
      } else {
        off + step
      }
      hasher.update(old[off:end])
      append_bytes(sig_buf, hasher.take_ready())
      off = end
    }
  }
  if off < old.length() {
    hasher.update(old[off:old.length()])
  }
  append_bytes(sig_buf, hasher.finish())
  let sig = Bytes::from_array(sig_buf)
  assert_eq(sig, @lib.signature(old, opts, limits))

  // 2. Prepare reusable signature index + inspect summary.
  let prepared = @lib.prepare_signature(sig, limits)
  let sig_summary = prepared.summary()
  assert_eq(sig_summary.block_len, 512L)
  assert_eq(sig_summary.record_count, 20L)

  // 3. Streaming delta generation across split boundaries.
  let scanner = @lib.DeltaScanner::new(prepared, limits)
  let delta_buf : Array[Byte] = []
  let mut noff = 0
  for step in [7, 250, 1500, 4096] {
    if noff < new.length() {
      let end = if noff + step > new.length() {
        new.length()
      } else {
        noff + step
      }
      scanner.feed(new[noff:end])
      append_bytes(delta_buf, scanner.take_ready())
      noff = end
    }
  }
  if noff < new.length() {
    scanner.feed(new[noff:new.length()])
  }
  append_bytes(delta_buf, scanner.finish())
  let delta = Bytes::from_array(delta_buf)

  // 4. Streaming patch application using BasisReader (Bytes) over 1-byte and 7-byte splits.
  let applier = @lib.PatchApplier::new(old.length().to_int64(), limits)
  let out_buf : Array[Byte] = []
  let mut doff = 0
  let mut step = 1
  while doff < delta.length() {
    let end = if doff + step > delta.length() {
      delta.length()
    } else {
      doff + step
    }
    applier.feed(delta[doff:end], old, chunk => append_bytes(out_buf, chunk))
    doff = end
    step = if step == 1 { 7 } else { 1 }
  }
  let delta_summary = applier.finish()
  let recovered = Bytes::from_array(out_buf)
  assert_eq(recovered, new)
  assert_true(delta_summary.copy_bytes > 0L)
  assert_eq(delta_summary.output_bytes, new.length().to_int64())
  println(
    "STREAMING_EXAMPLE_OK sig=\{sig.length()} delta=\{delta.length()} copy=\{delta_summary.copy_bytes} output=\{recovered.length()}",
  )
}

///|
fn main {
  run() catch {
    _ => {
      println("STREAMING_EXAMPLE_MISMATCH")
      abort("STREAMING_EXAMPLE_MISMATCH")
    }
  }
}
