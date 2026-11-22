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
fn parse_nonneg_decimal_str(text : String) -> Int64 raise @lib.ManifestError {
  guard text.length() > 0 && (text == "0" || !text.has_prefix("0")) else {
    raise @lib.ManifestError::InvalidField("byte_length")
  }
  let mut result = 0L
  for c in text {
    guard c >= '0' && c <= '9' else {
      raise @lib.ManifestError::InvalidField("byte_length")
    }
    let digit = (c.to_int() - 48).to_int64()
    guard result <= (9223372036854775807L - digit) / 10L else {
      raise @lib.ManifestError::InvalidField("byte_length")
    }
    result = result * 10L + digit
  }
  result
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

  // Optional bounded RFC 1952 gzip compression size on the generated delta.
  let gz_delta = @compress.compress_gzip(
    delta[:],
    limits.max_delta_bytes,
    limits.max_output_bytes,
  )

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

  "{\"ok\":true,\"block_len\":\"\{actual_block}\",\"strong_sum_len\":\"\{sum_len}\",\"old_bytes\":\"\{old_digest.byte_length}\",\"new_bytes\":\"\{new_digest.byte_length}\",\"signature_bytes\":\"\{sig.length()}\",\"delta_bytes\":\"\{summary.delta_bytes}\",\"gzip_delta_bytes\":\"\{gz_delta.length()}\",\"copy_bytes\":\"\{summary.copy_bytes}\",\"literal_bytes\":\"\{summary.literal_bytes}\",\"instruction_count\":\"\{summary.instruction_count}\",\"copy_commands\":\"\{summary.copy_commands}\",\"literal_commands\":\"\{summary.literal_commands}\",\"old_sha256\":\"\{old_digest.sha256}\",\"new_sha256\":\"\{new_digest.sha256}\",\"restored_sha256\":\"\{rec_digest.sha256}\",\"verified\":\{verified}}"
}

///|
/// Execute the full chunked MoonLibSync streaming pipeline in pure MoonBit JS/ESM
/// without C FFI and return JSON diagnostics, gzip delta size, and SHA-256 state.
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
/// Generate standard 0x72730147 signature bytes (`block_len = 0` selects auto).
/// Returns empty bytes on invalid options or exceeded limits.
pub fn create_signature_bytes(
  old_bytes : Bytes,
  block_len : Int32,
  strong_sum_len : Int32,
) -> Bytes {
  let limits = @lib.Limits::default()
  try {
    let sum_len = strong_sum_len.to_int64()
    let actual_block = if block_len == 0 {
      @lib.recommend_block_len(old_bytes.length().to_int64(), sum_len, limits)
    } else {
      block_len.to_int64()
    }
    @lib.signature(
      old_bytes,
      { block_len: actual_block, strong_sum_len: sum_len, },
      limits,
    )
  } catch {
    _ => b""
  }
}

///|
/// Generate standard 0x72730236 delta bytes from remote signature and new bytes.
/// Returns empty bytes on error.
pub fn create_delta_bytes(sig_bytes : Bytes, new_bytes : Bytes) -> Bytes {
  let limits = @lib.Limits::default()
  @lib.delta(sig_bytes, new_bytes, limits) catch {
    _ => b""
  }
}

///|
/// Apply a standard 0x72730236 delta to basis bytes.
pub fn apply_patch_bytes(old_bytes : Bytes, delta_bytes : Bytes) -> Bytes {
  let limits = @lib.Limits::default()
  @lib.patch(old_bytes, delta_bytes, limits) catch {
    _ => b""
  }
}

///|
/// Compute lowercase hex SHA-256 using MoonLibSync's bounded streaming hasher.
pub fn sha256_hex_bytes(data : Bytes) -> String {
  let limits = @lib.Limits::default()
  try {
    let h = @lib.Sha256Hasher::new(limits.max_new_bytes)
    h.update(data[:])
    h.finish().sha256
  } catch {
    _ => ""
  }
}

///|
/// Compress bytes into a single-member RFC 1952 gzip frame (`level` 0..=9).
pub fn compress_gzip_bytes(data : Bytes, level : Int32) -> Bytes {
  let limits = @lib.Limits::default()
  @compress.compress_gzip(
    data[:],
    limits.max_new_bytes,
    limits.max_output_bytes,
    level~,
  ) catch {
    _ => b""
  }
}

///|
/// Decompress a bounded single-member RFC 1952 gzip frame.
pub fn decompress_gzip_bytes(data : Bytes, max_output : Int32) -> Bytes {
  let limits = @lib.Limits::default()
  let cap = if max_output < 0 { 0L } else { max_output.to_int64() }
  @compress.decompress_gzip(data[:], limits.max_delta_bytes, cap) catch {
    _ => b""
  }
}

///|
/// Decompress a bounded gzip frame and return structured JSON diagnostics
/// (including `LimitExceeded` for zip bombs and `TrailingData` for extra bytes).
pub fn decompress_gzip_check_json(data : Bytes, max_output : Int32) -> String {
  let limits = @lib.Limits::default()
  let cap = max_output.to_int64()
  try {
    let plain = @compress.decompress_gzip(data[:], limits.max_delta_bytes, cap)
    let h = @lib.Sha256Hasher::new(limits.max_output_bytes)
    h.update(plain[:])
    let dig = h.finish()
    "{\"ok\":true,\"byte_length\":\"\{dig.byte_length}\",\"sha256\":\"\{dig.sha256}\"}"
  } catch {
    err => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
  }
}

///|
fn build_dir_snapshot_json_impl(entries_json : String) -> String raise {
  let limits = @lib.DirLimits::default()
  let parsed = @json.parse(
    entries_json,
    max_nesting_depth=3,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise @lib.ManifestError::InvalidJson
  }
  guard parsed is @json.Json::Array(items) else {
    raise @lib.ManifestError::InvalidSchema
  }
  guard items.length().to_int64() <= limits.max_entries else {
    raise @lib.ManifestError::ResourceLimit("dir_entries")
  }
  let entries : Array[@lib.DirEntry] = Array(capacity=items.length())
  for item in items {
    guard item is @json.Json::Object(fields) else {
      raise @lib.ManifestError::InvalidSchema
    }
    guard fields.get("path") is Some(@json.Json::String(path)) else {
      raise @lib.ManifestError::InvalidField("path")
    }
    guard fields.get("byte_length") is Some(@json.Json::String(len_str)) else {
      raise @lib.ManifestError::InvalidField("byte_length")
    }
    guard fields.get("sha256") is Some(@json.Json::String(sha256)) else {
      raise @lib.ManifestError::InvalidField("sha256")
    }
    entries.push({
      path,
      digest: { byte_length: parse_nonneg_decimal_str(len_str), sha256, },
    })
  }
  let snapshot = @lib.create_dir_snapshot(entries, limits)
  let encoded = @lib.encode_dir_snapshot(snapshot, limits)
  @utf8.decode(encoded) catch {
    _ => raise @lib.ManifestError::InvalidUtf8
  }
}

///|
/// Validate, sort, and encode a raw JSON array of `{path, byte_length, sha256}`
/// entries into a canonical Schema 3 `moonlibsync-dir-snapshot` JSON string.
pub fn create_dir_snapshot_json(entries_json : String) -> String {
  build_dir_snapshot_json_impl(entries_json) catch {
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
