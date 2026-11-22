// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn append_view(buf : @buffer.Buffer, view : BytesView) -> Unit {
  if view.length() > 0 {
    buf.write_bytesview(view)
  }
}

///|
fn sync_err_label(err : Error) -> String {
  match err {
    @lib.SyncError::InvalidOptions(field) => "InvalidOptions:" + field
    @lib.SyncError::UnsupportedSignatureProfile => "UnsupportedSignatureProfile"
    @lib.SyncError::TruncatedInput => "TruncatedInput"
    @lib.SyncError::InvalidSignature => "InvalidSignature"
    @lib.SyncError::InvalidDelta => "InvalidDelta"
    @lib.SyncError::InvalidOpcode => "InvalidOpcode"
    @lib.SyncError::IntegerOutOfRange => "IntegerOutOfRange"
    @lib.SyncError::CopyOutOfBounds => "CopyOutOfBounds"
    @lib.SyncError::TrailingData => "TrailingData"
    @lib.SyncError::LimitExceeded => "LimitExceeded"
    @lib.ManifestError::Core(c) => "Core:" + sync_err_label(c)
    @lib.ManifestError::BindingMismatch(f) => "BindingMismatch:" + f
    @lib.ManifestError::InvalidField(f) => "InvalidField:" + f
    @lib.ManifestError::ResourceLimit(f) => "ResourceLimit:" + f
    @lib.ManifestError::InvalidUtf8 => "InvalidUtf8"
    @lib.ManifestError::InvalidJson => "InvalidJson"
    @lib.ManifestError::InvalidSchema => "InvalidSchema"
    @lib.ManifestError::HashFailure => "HashFailure"
    _ => "UnexpectedError"
  }
}

///|
fn run_streaming_sync_impl(
  old_bytes : Bytes,
  new_bytes : Bytes,
  block_len : Int32,
  strong_sum_len : Int32,
  chunk_size : Int32,
) -> String raise {
  guard chunk_size > 0 else {
    raise @lib.SyncError::InvalidOptions("chunk_size")
  }
  let limits = @lib.Limits::default()
  let sum_len = strong_sum_len.to_int64()
  let actual_block = if block_len == 0 {
    @lib.recommend_block_len(old_bytes.length().to_int64(), sum_len, limits)
  } else {
    block_len.to_int64()
  }
  let opts : @lib.SignatureOptions = {
    block_len: actual_block,
    strong_sum_len: sum_len,
  }

  // 1. Streaming signature + basis SHA-256 in `chunk_size` slices.
  let sig_hasher = @lib.SignatureHasher::new(opts, limits)
  let old_sha_hasher = @lib.Sha256Hasher::new(limits.max_old_bytes)
  let sig_buf = @buffer.Buffer(size_hint=512)
  append_view(sig_buf, sig_hasher.take_ready()[:])
  let mut pos = 0
  while pos < old_bytes.length() {
    let rem = old_bytes.length() - pos
    let take = if rem < chunk_size { rem } else { chunk_size }
    let view = old_bytes[pos:pos + take]
    old_sha_hasher.update(view)
    sig_hasher.update(view)
    append_view(sig_buf, sig_hasher.take_ready()[:])
    pos = pos + take
  }
  append_view(sig_buf, sig_hasher.finish()[:])
  let sig = sig_buf.to_bytes()
  let old_digest = old_sha_hasher.finish()

  // 2. Prepare reusable signature index + streaming delta generation.
  let prepared = @lib.prepare_signature(sig, limits)
  let scanner = @lib.DeltaScanner::new(prepared, limits)
  let new_sha_hasher = @lib.Sha256Hasher::new(limits.max_new_bytes)
  let delta_buf = @buffer.Buffer(size_hint=256)
  append_view(delta_buf, scanner.take_ready()[:])
  let mut npos = 0
  while npos < new_bytes.length() {
    let rem = new_bytes.length() - npos
    let take = if rem < chunk_size { rem } else { chunk_size }
    let view = new_bytes[npos:npos + take]
    new_sha_hasher.update(view)
    scanner.feed(view)
    append_view(delta_buf, scanner.take_ready()[:])
    npos = npos + take
  }
  append_view(delta_buf, scanner.finish()[:])
  let delta = delta_buf.to_bytes()
  let new_digest = new_sha_hasher.finish()

  // 3. Sans-IO PatchDecoder + streaming output SHA-256 verification.
  let decoder = @lib.PatchDecoder::new(old_digest.byte_length, limits)
  let rec_sha_hasher = @lib.Sha256Hasher::new(limits.max_output_bytes)
  let rec_buf = @buffer.Buffer(size_hint=new_bytes.length())
  let mut dpos = 0
  while dpos < delta.length() {
    let rem = delta.length() - dpos
    let take = if rem < chunk_size { rem } else { chunk_size }
    let dslice = delta[dpos:dpos + take]
    let mut step_pos = 0
    while step_pos < dslice.length() || decoder.has_pending_copy() {
      let (consumed, step) = decoder.step(dslice[step_pos:])
      step_pos = step_pos + consumed
      match step {
        NeedInput => ()
        EmitLiteral(lit) => {
          rec_sha_hasher.update(lit)
          rec_buf.write_bytesview(lit)
        }
        CopyBasis(off, len) => {
          let start = off.to_int()
          let view = old_bytes[start:start + len]
          rec_sha_hasher.update(view)
          rec_buf.write_bytesview(view)
        }
      }
    }
    dpos = dpos + take
  }
  let summary = decoder.finish()
  let rec_digest = rec_sha_hasher.finish()
  let restored = rec_buf.to_bytes()
  let verified = rec_digest.sha256 == new_digest.sha256 && restored == new_bytes

  "{\"ok\":true,\"block_len\":\"\{actual_block}\",\"strong_sum_len\":\"\{sum_len}\",\"old_bytes\":\"\{old_digest.byte_length}\",\"new_bytes\":\"\{new_digest.byte_length}\",\"signature_bytes\":\"\{sig.length()}\",\"delta_bytes\":\"\{summary.delta_bytes}\",\"copy_bytes\":\"\{summary.copy_bytes}\",\"literal_bytes\":\"\{summary.literal_bytes}\",\"instruction_count\":\"\{summary.instruction_count}\",\"copy_commands\":\"\{summary.copy_commands}\",\"literal_commands\":\"\{summary.literal_commands}\",\"old_sha256\":\"\{old_digest.sha256}\",\"new_sha256\":\"\{new_digest.sha256}\",\"restored_sha256\":\"\{rec_digest.sha256}\",\"verified\":\{verified}}"
}

///|
/// Execute the full chunked MoonLibSync streaming pipeline in pure MoonBit JS/ESM
/// without C FFI and return JSON diagnostics and SHA-256 verification state.
pub fn run_streaming_sync_json(
  old_bytes : Bytes,
  new_bytes : Bytes,
  block_len : Int32,
  strong_sum_len : Int32,
  chunk_size : Int32,
) -> String {
  run_streaming_sync_impl(
    old_bytes, new_bytes, block_len, strong_sum_len, chunk_size,
  ) catch {
    err => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
  }
}

///|
/// Parse two Schema 3 directory snapshot JSON texts and return the Schema 3 plan JSON.
pub fn plan_dir_snapshots_json(
  basis_json : String,
  target_json : String,
) -> String {
  let limits = @lib.DirLimits::default()
  let res = try {
    let basis = @lib.parse_dir_snapshot(@utf8.encode(basis_json), limits)
    let target = @lib.parse_dir_snapshot(@utf8.encode(target_json), limits)
    let plan = @lib.plan_dir_sync(basis, target, limits)
    @utf8.decode(@lib.encode_dir_plan(plan, limits)) catch {
      _ => "{\"ok\":false,\"error\":\"InvalidUtf8\"}"
    }
  } catch {
    err => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
  }
  res
}
