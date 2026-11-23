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
    @crypto.CryptoError::InvalidKey(d) => "InvalidKey:" + d
    @crypto.CryptoError::InvalidSignature(d) => "InvalidSignature:" + d
    @crypto.CryptoError::UntrustedKey(d) => "UntrustedKey:" + d
    @crypto.CryptoError::DigestMismatch(d) => "DigestMismatch:" + d
    @crypto.CryptoError::InvalidFormat(d) => "InvalidFormat:" + d
    @crypto.CryptoError::AuthenticationFailed => "AuthenticationFailed"
    @crypto.CryptoError::TruncatedInput => "TruncatedInput"
    @crypto.CryptoError::TrailingData => "TrailingData"
    @crypto.CryptoError::LimitExceeded(d) => "LimitExceeded:" + d
    @crypto.CryptoError::InvalidOptions(d) => "InvalidOptions:" + d
    _ => "UnexpectedError"
  }
}

///|
fn hex_nibble_char(v : Int32) -> Char {
  if v < 10 {
    (48 + v).unsafe_to_char()
  } else {
    (87 + v).unsafe_to_char()
  }
}

///|
fn json_escape_str(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    let code = c.to_int()
    if c == '"' {
      out.write_string("\\\"")
    } else if c == '\\' {
      out.write_string("\\\\")
    } else if c == '\n' {
      out.write_string("\\n")
    } else if c == '\r' {
      out.write_string("\\r")
    } else if c == '\t' {
      out.write_string("\\t")
    } else if code < 0x20 {
      out.write_string("\\u00")
      out.write_char(hex_nibble_char((code >> 4) & 0xf))
      out.write_char(hex_nibble_char(code & 0xf))
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn err_json(err : Error) -> String {
  let tag = json_escape_str(sync_err_label(err))
  "{\"ok\":false,\"error\":\"\{tag}\",\"message\":\"\{tag}\"}"
}

///|
fn bytes_view_to_hex(view : BytesView) -> String {
  let out = StringBuilder()
  for i in 0..<view.length() {
    let b = view[i].to_int()
    out.write_char(hex_nibble_char((b >> 4) & 0xf))
    out.write_char(hex_nibble_char(b & 0xf))
  }
  out.to_string()
}

///|
fn decode_hex_nibble(code : Int32) -> Int32? {
  if code >= 0x30 && code <= 0x39 {
    Some(code - 0x30)
  } else if code >= 0x61 && code <= 0x66 {
    Some(code - 0x61 + 10)
  } else if code >= 0x41 && code <= 0x46 {
    Some(code - 0x41 + 10)
  } else {
    None
  }
}

///|
fn decode_hex_bytes(
  text : String,
  field : String,
  max_bytes : Int64,
) -> Bytes raise @lib.ManifestError {
  guard text.length() % 2 == 0 else {
    raise @lib.ManifestError::InvalidField(field)
  }
  let n = text.length() / 2
  guard n.to_int64() <= max_bytes else {
    raise @lib.ManifestError::ResourceLimit(field)
  }
  let out = FixedArray::make(n, b'\x00')
  for i in 0..<n {
    let hi = match decode_hex_nibble(text[i * 2].to_int()) {
      Some(v) => v
      None => raise @lib.ManifestError::InvalidField(field)
    }
    let lo = match decode_hex_nibble(text[i * 2 + 1].to_int()) {
      Some(v) => v
      None => raise @lib.ManifestError::InvalidField(field)
    }
    out[i] = ((hi << 4) | lo).to_byte()
  }
  Bytes::from_array(out[:])
}

///|
fn literal_preview_utf8_json(view : BytesView) -> String {
  let out = StringBuilder()
  let n = view.length()
  let mut i = 0
  while i < n {
    let b0 = view[i].to_int()
    if b0 < 0x80 {
      if b0 >= 0x20 && b0 < 0x7f {
        if b0 == 0x22 {
          out.write_string("\\\"")
        } else if b0 == 0x5c {
          out.write_string("\\\\")
        } else {
          out.write_char(b0.unsafe_to_char())
        }
      } else {
        out.write_char('.')
      }
      i = i + 1
    } else if b0 >= 0xc2 && b0 <= 0xdf {
      if i + 1 < n {
        let b1 = view[i + 1].to_int()
        if b1 >= 0x80 && b1 <= 0xbf {
          let cp = ((b0 & 0x1f) << 6) | (b1 & 0x3f)
          if cp >= 0x80 && cp <= 0x9f {
            out.write_char('.')
          } else {
            out.write_char(cp.unsafe_to_char())
          }
          i = i + 2
        } else {
          out.write_char('.')
          i = i + 1
        }
      } else {
        out.write_char('.')
        i = i + 1
      }
    } else if b0 >= 0xe0 && b0 <= 0xef {
      if i + 2 < n {
        let b1 = view[i + 1].to_int()
        let b2 = view[i + 2].to_int()
        let b1_ok = if b0 == 0xe0 {
          b1 >= 0xa0 && b1 <= 0xbf
        } else if b0 == 0xed {
          b1 >= 0x80 && b1 <= 0x9f
        } else {
          b1 >= 0x80 && b1 <= 0xbf
        }
        if b1_ok && b2 >= 0x80 && b2 <= 0xbf {
          let cp = ((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f)
          out.write_char(cp.unsafe_to_char())
          i = i + 3
        } else {
          out.write_char('.')
          i = i + 1
        }
      } else {
        out.write_char('.')
        i = i + 1
      }
    } else if b0 >= 0xf0 && b0 <= 0xf4 {
      if i + 3 < n {
        let b1 = view[i + 1].to_int()
        let b2 = view[i + 2].to_int()
        let b3 = view[i + 3].to_int()
        let b1_ok = if b0 == 0xf0 {
          b1 >= 0x90 && b1 <= 0xbf
        } else if b0 == 0xf4 {
          b1 >= 0x80 && b1 <= 0x8f
        } else {
          b1 >= 0x80 && b1 <= 0xbf
        }
        if b1_ok && b2 >= 0x80 && b2 <= 0xbf && b3 >= 0x80 && b3 <= 0xbf {
          let cp = ((b0 & 0x07) << 18) |
            ((b1 & 0x3f) << 12) |
            ((b2 & 0x3f) << 6) |
            (b3 & 0x3f)
          out.write_char(cp.unsafe_to_char())
          i = i + 4
        } else {
          out.write_char('.')
          i = i + 1
        }
      } else {
        out.write_char('.')
        i = i + 1
      }
    } else {
      out.write_char('.')
      i = i + 1
    }
  }
  out.to_string()
}

///|
fn path_basename(path : String) -> String {
  let chars = path.to_array()
  let mut last_slash = -1
  for i in 0..<chars.length() {
    if chars[i] == '/' {
      last_slash = i
    }
  }
  if last_slash < 0 {
    return path
  }
  let out = StringBuilder()
  for i in (last_slash + 1)..<chars.length() {
    out.write_char(chars[i])
  }
  out.to_string()
}

///|
fn sha256_file_digest(
  data : Bytes,
  max_bytes : Int64,
) -> @lib.FileDigest raise @lib.ManifestError {
  let h = @lib.Sha256Hasher::new(max_bytes)
  h.update(data[:])
  h.finish()
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
  let sig_buf = @buffer.Buffer(capacity=512)
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
  let delta_buf = @buffer.Buffer(capacity=256)
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
  let rec_buf = @buffer.Buffer(capacity=new_bytes.length())
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
  if max_output < 0 {
    return b""
  }
  let limits = @lib.Limits::default()
  @compress.decompress_gzip(
    data[:],
    limits.max_delta_bytes,
    max_output.to_int64(),
  ) catch {
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

///|
fn read_be_u64(data : Bytes, pos : Int32, width : Int32) -> UInt64 {
  let mut v = 0UL
  for i in 0..<width {
    v = (v << 8) | data[pos + i].to_uint64()
  }
  v
}

///|
fn has_prefix_bytes(data : Bytes, prefix : Bytes) -> Bool {
  if data.length() < prefix.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if data[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
fn trim_ascii_whitespace(text : String) -> String {
  let chars = text.to_array()
  let mut start = 0
  let mut end = chars.length()
  while start < end {
    let c = chars[start]
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      start = start + 1
    } else {
      break
    }
  }
  while end > start {
    let c = chars[end - 1]
    if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
      end = end - 1
    } else {
      break
    }
  }
  if start == 0 && end == chars.length() {
    return text
  }
  let out = StringBuilder()
  for i in start..<end {
    out.write_char(chars[i])
  }
  out.to_string()
}

///|
fn delta_summary_json(s : @lib.DeltaSummary) -> String {
  "{\"delta_bytes\":\"\{s.delta_bytes}\",\"instruction_count\":\"\{s.instruction_count}\",\"literal_commands\":\"\{s.literal_commands}\",\"copy_commands\":\"\{s.copy_commands}\",\"literal_bytes\":\"\{s.literal_bytes}\",\"copy_bytes\":\"\{s.copy_bytes}\",\"output_bytes\":\"\{s.output_bytes}\"}"
}

///|
fn inspect_delta_detailed_impl(
  delta_bytes : Bytes,
  max_items : Int32,
) -> String raise {
  let limits = @lib.Limits::default()
  let summary = @lib.inspect_delta(delta_bytes, limits)
  let cap = if max_items < 1 {
    1
  } else if max_items > 2048 {
    2048
  } else {
    max_items
  }
  let items = StringBuilder()
  let mut cursor = 4
  let mut output_offset = 0UL
  let mut emitted = 0
  let mut truncated = false
  while cursor < delta_bytes.length() {
    let opcode = delta_bytes[cursor].to_int()
    cursor = cursor + 1
    if opcode == 0 {
      break
    }
    if emitted >= cap {
      truncated = true
      break
    }
    let is_literal = opcode <= 0x44
    let mut offset = 0UL
    let length = if opcode <= 0x40 {
      opcode.to_uint64()
    } else if is_literal {
      let width = 1 << (opcode - 0x41)
      let value = read_be_u64(delta_bytes, cursor, width)
      cursor = cursor + width
      value
    } else {
      let ow = 1 << ((opcode - 0x45) / 4)
      let lw = 1 << ((opcode - 0x45) % 4)
      offset = read_be_u64(delta_bytes, cursor, ow)
      cursor = cursor + ow
      let value = read_be_u64(delta_bytes, cursor, lw)
      cursor = cursor + lw
      value
    }
    let lit_start = cursor
    if is_literal {
      cursor = cursor + length.to_int()
    }
    if emitted > 0 {
      items.write_char(',')
    }
    if is_literal {
      let lit_len = length.to_int()
      let preview_len = if lit_len > 64 { 64 } else { lit_len }
      let preview_view = delta_bytes[lit_start:lit_start + preview_len]
      let preview_hex = bytes_view_to_hex(preview_view)
      let preview_utf8 = literal_preview_utf8_json(preview_view)
      let preview_truncated = lit_len > 64
      items.write_string(
        "{\"index\":\{emitted},\"kind\":\"literal\",\"offset\":\"\{offset}\",\"length\":\"\{length}\",\"output_offset\":\"\{output_offset}\",\"preview_hex\":\"\{preview_hex}\",\"preview_utf8\":\"\{preview_utf8}\",\"preview_truncated\":\{preview_truncated}}",
      )
    } else {
      items.write_string(
        "{\"index\":\{emitted},\"kind\":\"copy\",\"offset\":\"\{offset}\",\"length\":\"\{length}\",\"output_offset\":\"\{output_offset}\"}",
      )
    }
    output_offset = output_offset + length
    emitted = emitted + 1
  }
  "{\"ok\":true,\"summary\":\{delta_summary_json(summary)},\"total_commands\":\"\{summary.instruction_count}\",\"truncated\":\{truncated},\"items\":[\{items.to_string()}]}"
}

///|
/// Validate a standard 0x72730236 delta and emit up to `max_items` (clamped 1..2048)
/// ordered COPY/Literal spans with output offsets for visualization and SDK inspection.
pub fn inspect_delta_detailed_json(
  delta_bytes : Bytes,
  max_items : Int32,
) -> String {
  inspect_delta_detailed_impl(delta_bytes, max_items) catch {
    err => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
  }
}

///|
fn is_generic_json_mismatch(err : Error) -> Bool {
  match err {
    @lib.ManifestError::InvalidSchema
    | @lib.ManifestError::InvalidJson
    | @lib.ManifestError::InvalidUtf8 => true
    _ => false
  }
}

///|
fn starts_with_json_object(data : Bytes) -> Bool {
  let mut i = 0
  let n = data.length()
  while i < n {
    let b = data[i]
    if b == b' ' || b == b'\t' || b == b'\n' || b == b'\r' {
      i = i + 1
    } else {
      return b == b'{'
    }
  }
  false
}

///|
fn parse_range_plan_inspect_json(
  data : Bytes,
  dir_limits : @lib.DirLimits,
) -> String? raise {
  guard data.length().to_int64() <= dir_limits.max_snapshot_bytes else {
    raise @lib.ManifestError::ResourceLimit("range_plan_bytes")
  }
  let text = @utf8.decode(data) catch {
    _ => raise @lib.ManifestError::InvalidUtf8
  }
  if text.has_prefix("\u{feff}") {
    raise @lib.ManifestError::InvalidUtf8
  }
  let parsed = @json.parse(
    text,
    max_nesting_depth=16,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    @json.ParseError::DepthLimitExceeded =>
      raise @lib.ManifestError::ResourceLimit("manifest_depth")
    _ => raise @lib.ManifestError::InvalidJson
  }
  guard parsed is @json.Json::Object(fields) else { return None }
  guard fields.get("schema") is Some(@json.Json::Number(3.0, repr=Some("3"))) else {
    return None
  }
  guard fields.get("kind") is Some(@json.Json::String("moonlibsync-range-plan")) else {
    return None
  }
  guard fields.get("target_length")
    is Some(@json.Json::Number(_, repr=Some(target_len))) else {
    raise @lib.ManifestError::InvalidField("target_length")
  }
  ignore(parse_nonneg_decimal_str(target_len))
  guard fields.get("block_len")
    is Some(@json.Json::Number(_, repr=Some(block_len))) else {
    raise @lib.ManifestError::InvalidField("block_len")
  }
  ignore(parse_nonneg_decimal_str(block_len))
  guard fields.get("profile") is Some(@json.Json::String(profile)) &&
    (profile == "rk-blake2" || profile == "rollsum-blake2") else {
    raise @lib.ManifestError::InvalidField("profile")
  }
  guard fields.get("reused_bytes")
    is Some(@json.Json::Number(_, repr=Some(reused_bytes))) else {
    raise @lib.ManifestError::InvalidField("reused_bytes")
  }
  ignore(parse_nonneg_decimal_str(reused_bytes))
  guard fields.get("fetch_bytes")
    is Some(@json.Json::Number(_, repr=Some(fetch_bytes))) else {
    raise @lib.ManifestError::InvalidField("fetch_bytes")
  }
  ignore(parse_nonneg_decimal_str(fetch_bytes))
  guard fields.get("request_bytes")
    is Some(@json.Json::Number(_, repr=Some(request_bytes))) else {
    raise @lib.ManifestError::InvalidField("request_bytes")
  }
  ignore(parse_nonneg_decimal_str(request_bytes))
  guard fields.get("ranges") is Some(@json.Json::Array(ranges)) else {
    raise @lib.ManifestError::InvalidField("ranges")
  }
  for item in ranges {
    guard item is @json.Json::Object(_) else {
      raise @lib.ManifestError::InvalidField("ranges")
    }
  }
  Some(
    "{\"ok\":true,\"artifact_kind\":\"moonlibsync-range-plan\",\"schema_version\":3,\"summary\":{\"target_length\":\"\{target_len}\",\"block_len\":\"\{block_len}\",\"profile\":\"\{json_escape_str(profile)}\",\"reused_bytes\":\"\{reused_bytes}\",\"fetch_bytes\":\"\{fetch_bytes}\",\"request_bytes\":\"\{request_bytes}\",\"range_count\":\{ranges.length()}}}",
  )
}

///|
fn json_string_array(items : Array[String]) -> String {
  let sb = StringBuilder()
  sb.write_char('[')
  for i in 0..<items.length() {
    if i > 0 {
      sb.write_char(',')
    }
    sb.write_char('"')
    sb.write_string(json_escape_str(items[i]))
    sb.write_char('"')
  }
  sb.write_char(']')
  sb.to_string()
}

///|
fn has_zlib_header(data : Bytes) -> Bool {
  if data.length() < 2 {
    return false
  }
  let cmf = data[0].to_int()
  let flg = data[1].to_int()
  (cmf & 0x0f) == 8 &&
  cmf >> 4 <= 7 &&
  (flg & 0x20) == 0 &&
  ((cmf << 8) | flg) % 31 == 0
}

///|
fn inspect_artifact_impl(data : Bytes) -> String raise {
  let limits = @lib.Limits::default()
  let dir_limits = @lib.DirLimits::default()
  if data.length() >= 4 &&
    data[0] == b'\x72' &&
    data[1] == b'\x73' &&
    data[2] == b'\x01' &&
    (data[3] == b'\x47' || data[3] == b'\x37') {
    let s = @lib.inspect_signature(data, limits)
    let magic_str = if s.magic == 0x72730137U {
      "0x72730137"
    } else {
      "0x72730147"
    }
    let profile_str = if s.magic == 0x72730137U {
      "rollsum-blake2"
    } else {
      "rk-blake2"
    }
    return "{\"ok\":true,\"artifact_kind\":\"signature\",\"summary\":{\"magic\":\"\{magic_str}\",\"profile\":\"\{profile_str}\",\"block_len\":\"\{s.block_len}\",\"strong_sum_len\":\"\{s.strong_sum_len}\",\"record_count\":\"\{s.record_count}\",\"signature_bytes\":\"\{s.signature_bytes}\"}}"
  }
  if data.length() >= 4 &&
    data[0] == b'\x72' &&
    data[1] == b'\x73' &&
    data[2] == b'\x02' &&
    data[3] == b'\x36' {
    let s = @lib.inspect_delta(data, limits)
    return "{\"ok\":true,\"artifact_kind\":\"delta\",\"summary\":\{delta_summary_json(s)}}"
  }
  if data.length() >= 2 && data[0] == b'\x1f' && data[1] == b'\x8b' {
    let plain = @compress.decompress_gzip(
      data[:],
      limits.max_delta_bytes,
      limits.max_output_bytes,
    )
    let h = @lib.Sha256Hasher::new(limits.max_output_bytes)
    h.update(plain[:])
    let dig = h.finish()
    return "{\"ok\":true,\"artifact_kind\":\"gzip\",\"compressed_bytes\":\"\{data.length()}\",\"uncompressed_bytes\":\"\{dig.byte_length}\",\"uncompressed_sha256\":\"\{dig.sha256}\"}"
  }
  if has_prefix_bytes(data, @lib.bundle_archive_magic()) {
    let decoded = @lib.parse_bundle_archive(data, dir_limits, limits)
    let m = decoded.manifest
    return "{\"ok\":true,\"artifact_kind\":\"bundle-archive\",\"archive_bytes\":\"\{data.length()}\",\"summary\":{\"unchanged\":\"\{m.unchanged_count}\",\"add_full\":\"\{m.add_full_count}\",\"update_delta\":\"\{m.update_delta_count}\",\"update_full\":\"\{m.update_full_count}\",\"delete\":\"\{m.delete_count}\",\"copy_from_basis\":\"\{m.copy_from_basis_count}\",\"total_payload_bytes\":\"\{m.total_payload_bytes}\"}}"
  }
  if has_prefix_bytes(data, @crypto.seal_magic()) {
    let seal_limits = @crypto.SealLimits::default()
    let hdr = @crypto.inspect_seal_header(data[:], seal_limits)
    let kdf_mode = hdr.kdf_mode.to_int()
    let kdf_name = if kdf_mode == 0 { "raw-key" } else { "argon2id" }
    let salt_hex = @crypto.encode_key_hex(hdr.salt)
    let nonce_prefix_hex = @crypto.encode_key_hex(hdr.nonce_prefix)
    let header_hex = bytes_view_to_hex(data[0:56])
    return "{\"ok\":true,\"artifact_kind\":\"seal-archive\",\"byte_length\":\"\{data.length()}\",\"summary\":{\"kdf_mode\":\{kdf_mode},\"kdf_name\":\"\{kdf_name}\",\"chunk_size\":\{hdr.chunk_size},\"argon2_memory_kib\":\{hdr.argon2_memory_kib},\"argon2_passes\":\{hdr.argon2_passes},\"argon2_lanes\":\{hdr.argon2_lanes},\"salt_hex\":\"\{salt_hex}\",\"nonce_prefix_hex\":\"\{nonce_prefix_hex}\",\"byte_length\":\"\{data.length()}\",\"header_hex\":\"\{header_hex}\"}}"
  }
  if has_prefix_bytes(data, @crypto.envelope_magic()) {
    let seal_limits = @crypto.SealLimits::default()
    let hdr = @crypto.inspect_envelope_header(data[:], seal_limits)
    let eph_hex = @crypto.encode_key_hex(hdr.ephemeral_public_key)
    let nonce_prefix_hex = @crypto.encode_key_hex(hdr.nonce_prefix)
    let rec_ids_json = json_string_array(hdr.recipient_key_ids)
    return "{\"ok\":true,\"artifact_kind\":\"envelope-archive\",\"byte_length\":\"\{data.length()}\",\"summary\":{\"magic\":\"MLSENC02\",\"version\":2,\"recipient_count\":\{hdr.recipient_key_ids.length()},\"recipient_key_ids\":\{rec_ids_json},\"chunk_size\":\{hdr.chunk_size},\"nonce_prefix_hex\":\"\{nonce_prefix_hex}\",\"ephemeral_public_key_hex\":\"\{eph_hex}\",\"byte_length\":\"\{data.length()}\"}}"
  }

  let mut specific_err : Error? = None
  let mut limit_err : Error? = None
  let record_manifest_err = fn(err : Error) {
    match err {
      @lib.ManifestError::ResourceLimit(_) =>
        if limit_err is None {
          limit_err = Some(err)
        }
      _ => if !is_generic_json_mismatch(err) { specific_err = Some(err) }
    }
  }
  if starts_with_json_object(data) {
    try {
      let tm = @lib.parse_transfer_manifest(data, limits)
      match tm {
        Delta(m) =>
          return "{\"ok\":true,\"artifact_kind\":\"librsync-delta\",\"schema_version\":2,\"summary\":{\"mode\":\"delta\",\"basis_bytes\":\"\{m.basis.byte_length}\",\"signature_bytes\":\"\{m.signature.byte_length}\",\"payload_bytes\":\"\{m.delta.byte_length}\",\"result_bytes\":\"\{m.result.byte_length}\",\"result_sha256\":\"\{m.result.sha256}\"}}"
        Full(p, r) =>
          return "{\"ok\":true,\"artifact_kind\":\"full-file\",\"schema_version\":2,\"summary\":{\"mode\":\"full\",\"payload_bytes\":\"\{p.byte_length}\",\"result_bytes\":\"\{r.byte_length}\",\"result_sha256\":\"\{r.sha256}\"}}"
      }
    } catch {
      err => record_manifest_err(err)
    }
    try {
      let um = @lib.parse_update_manifest(data, limits)
      return "{\"ok\":true,\"artifact_kind\":\"librsync-delta\",\"schema_version\":1,\"summary\":{\"basis_bytes\":\"\{um.basis.byte_length}\",\"signature_bytes\":\"\{um.signature.byte_length}\",\"delta_bytes\":\"\{um.delta.byte_length}\",\"result_bytes\":\"\{um.result.byte_length}\",\"result_sha256\":\"\{um.result.sha256}\"}}"
    } catch {
      err => record_manifest_err(err)
    }
    try {
      let bi = @lib.parse_basis_info(data, limits)
      return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-basis-info\",\"schema_version\":1,\"summary\":{\"basis_bytes\":\"\{bi.basis.byte_length}\",\"basis_sha256\":\"\{bi.basis.sha256}\",\"signature_bytes\":\"\{bi.signature.byte_length}\",\"signature_sha256\":\"\{bi.signature.sha256}\"}}"
    } catch {
      err => record_manifest_err(err)
    }
    try {
      let snap = @lib.parse_dir_snapshot(data, dir_limits)
      let mut total_bytes = 0UL
      for e in snap.entries {
        total_bytes = total_bytes + e.digest.byte_length.reinterpret_as_uint64()
      }
      return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-dir-snapshot\",\"schema_version\":3,\"summary\":{\"entries\":\"\{snap.entries.length()}\",\"total_bytes\":\"\{total_bytes}\"}}"
    } catch {
      err => record_manifest_err(err)
    }
    try {
      let plan = @lib.parse_dir_plan(data, dir_limits)
      return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-dir-plan\",\"schema_version\":3,\"summary\":{\"unchanged\":\"\{plan.unchanged_count}\",\"add\":\"\{plan.add_count}\",\"update\":\"\{plan.update_count}\",\"delete\":\"\{plan.delete_count}\",\"copy_from_basis\":\"\{plan.copy_from_basis_count}\",\"transfer_upper_bound_bytes\":\"\{plan.transfer_upper_bound_bytes}\"}}"
    } catch {
      err => record_manifest_err(err)
    }
    try {
      let idx = @lib.parse_dir_signature_index(data, dir_limits, limits)
      let mut total_basis = 0UL
      let mut total_sig = 0UL
      for e in idx.entries {
        total_basis = total_basis + e.basis.byte_length.reinterpret_as_uint64()
        total_sig = total_sig + e.signature.byte_length.reinterpret_as_uint64()
      }
      return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-dir-signatures\",\"schema_version\":3,\"summary\":{\"entries\":\"\{idx.entries.length()}\",\"total_basis_bytes\":\"\{total_basis}\",\"total_signature_bytes\":\"\{total_sig}\"}}"
    } catch {
      err => record_manifest_err(err)
    }
    try {
      let b = @lib.parse_dir_bundle_manifest(data, dir_limits, limits)
      return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-dir-bundle\",\"schema_version\":3,\"summary\":{\"unchanged\":\"\{b.unchanged_count}\",\"add_full\":\"\{b.add_full_count}\",\"update_delta\":\"\{b.update_delta_count}\",\"update_full\":\"\{b.update_full_count}\",\"delete\":\"\{b.delete_count}\",\"copy_from_basis\":\"\{b.copy_from_basis_count}\",\"total_payload_bytes\":\"\{b.total_payload_bytes}\"}}"
    } catch {
      err => record_manifest_err(err)
    }
    try {
      let r = @lib.parse_dir_verify_report(data, dir_limits)
      return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-dir-verify\",\"schema_version\":3,\"summary\":{\"ok\":\{r.ok},\"matched\":\"\{r.matched_count}\",\"modified\":\"\{r.modified_count}\",\"missing\":\"\{r.missing_count}\",\"extra\":\"\{r.extra_count}\"}}"
    } catch {
      err => record_manifest_err(err)
    }
    try {
      let meta = @lib.parse_dir_metadata(data, dir_limits)
      let exec_json = json_string_array(meta.executable_paths)
      let empty_json = json_string_array(meta.empty_dirs)
      return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-dir-metadata\",\"schema_version\":3,\"summary\":{\"executable_count\":\{meta.executable_paths.length()},\"empty_dir_count\":\{meta.empty_dirs.length()},\"executable_paths\":\{exec_json},\"empty_dirs\":\{empty_json}}}"
    } catch {
      err => record_manifest_err(err)
    }
    try {
      let ps = @crypto.parse_publisher_signature(data)
      return "{\"ok\":true,\"artifact_kind\":\"publisher-signature\",\"schema_version\":1,\"summary\":{\"algorithm\":\"\{ps.algorithm}\",\"key_id\":\"\{ps.key_id}\",\"public_key\":\"\{ps.public_key_hex}\",\"payload_length\":\"\{ps.payload_length}\",\"payload_sha256\":\"\{ps.payload_sha256}\",\"signature\":\"\{ps.signature_hex}\"}}"
    } catch {
      err =>
        match err {
          @crypto.CryptoError::InvalidFormat("json")
          | @crypto.CryptoError::InvalidFormat("schema")
          | @crypto.CryptoError::InvalidFormat("kind")
          | @crypto.CryptoError::InvalidFormat("schema_version")
          | @crypto.CryptoError::InvalidFormat("utf8")
          | @crypto.CryptoError::InvalidFormat("utf8_bom")
          | @crypto.CryptoError::LimitExceeded("signature_json_bytes")
          | @crypto.CryptoError::LimitExceeded("signature_json_depth") => ()
          _ => specific_err = Some(err)
        }
    }
    try {
      let kr = @crypto.parse_trust_keyring(data)
      let key_ids : Array[String] = Array(capacity=kr.trusted_keys.length())
      for pk in kr.trusted_keys {
        key_ids.push(@crypto.key_id_from_public_key(pk))
      }
      let key_ids_json = json_string_array(key_ids)
      let revoked_json = json_string_array(kr.revoked_key_ids)
      return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-keyring\",\"schema_version\":4,\"summary\":{\"trusted_count\":\{kr.trusted_keys.length()},\"revoked_count\":\{kr.revoked_key_ids.length()},\"min_quorum\":\{kr.min_quorum},\"key_ids\":\{key_ids_json},\"revoked_key_ids\":\{revoked_json}}}"
    } catch {
      err =>
        match err {
          @crypto.CryptoError::InvalidFormat("json")
          | @crypto.CryptoError::InvalidFormat("schema")
          | @crypto.CryptoError::InvalidFormat("kind")
          | @crypto.CryptoError::InvalidFormat("utf8")
          | @crypto.CryptoError::InvalidFormat("utf8_bom")
          | @crypto.CryptoError::LimitExceeded("keyring_json_bytes")
          | @crypto.CryptoError::LimitExceeded("keyring_json_depth") => ()
          _ => specific_err = Some(err)
        }
    }
    try {
      let bundle = @crypto.parse_signature_bundle(data)
      let signer_ids : Array[String] = Array(
        capacity=bundle.signatures.length(),
      )
      for sig in bundle.signatures {
        signer_ids.push(sig.key_id)
      }
      let signer_ids_json = json_string_array(signer_ids)
      return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-signature-bundle\",\"schema_version\":4,\"summary\":{\"signature_count\":\{bundle.signatures.length()},\"signer_key_ids\":\{signer_ids_json},\"payload_length\":\"\{bundle.payload_length}\",\"payload_sha256\":\"\{bundle.payload_sha256}\"}}"
    } catch {
      err =>
        match err {
          @crypto.CryptoError::InvalidFormat("json")
          | @crypto.CryptoError::InvalidFormat("schema")
          | @crypto.CryptoError::InvalidFormat("kind")
          | @crypto.CryptoError::InvalidFormat("utf8")
          | @crypto.CryptoError::InvalidFormat("utf8_bom")
          | @crypto.CryptoError::LimitExceeded("signature_bundle_json_bytes")
          | @crypto.CryptoError::LimitExceeded("signature_bundle_json_depth") =>
            ()
          _ => specific_err = Some(err)
        }
    }
    try {
      match parse_range_plan_inspect_json(data, dir_limits) {
        Some(out) => return out
        None => ()
      }
    } catch {
      err => record_manifest_err(err)
    }
    if specific_err is None {
      specific_err = limit_err
    }
  }
  if specific_err is None && has_zlib_header(data) {
    try {
      let plain = @compress.decompress_zlib(
        data[:],
        limits.max_delta_bytes,
        limits.max_output_bytes,
      )
      let h = @lib.Sha256Hasher::new(limits.max_output_bytes)
      h.update(plain[:])
      let dig = h.finish()
      return "{\"ok\":true,\"artifact_kind\":\"zlib\",\"compressed_bytes\":\"\{data.length()}\",\"uncompressed_bytes\":\"\{dig.byte_length}\",\"uncompressed_sha256\":\"\{dig.sha256}\"}"
    } catch {
      err =>
        match err {
          @lib.SyncError::LimitExceeded | @lib.SyncError::TrailingData =>
            specific_err = Some(err)
          _ => {
            let cmf = data[0].to_int()
            let flg = data[1].to_int()
            if cmf == 0x78 &&
              (flg == 0x01 || flg == 0x5e || flg == 0x9c || flg == 0xda) {
              specific_err = Some(err)
            }
          }
        }
    }
  }

  match specific_err {
    Some(err) => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
    None => "{\"ok\":false,\"error\":\"UnsupportedArtifact\"}"
  }
}

///|
/// Auto-detect and validate any MoonLibSync binary artifact (.sig, .delta, .gz,
/// .zlib, .mbundle, .menc, MLSENC02) or Schema 1/2/3/4 JSON document and return structured summary JSON.
pub fn inspect_artifact_json(data : Bytes) -> String {
  inspect_artifact_impl(data) catch {
    err => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
  }
}

///|
fn benchmark_block_sizes_impl(
  old_bytes : Bytes,
  new_bytes : Bytes,
  strong_sum_len : Int32,
) -> String raise {
  let limits = @lib.Limits::default()
  let sum_len = strong_sum_len.to_int64()
  let candidates : Array[(Int32, String)] = [
    (0, "auto"),
    (256, "256"),
    (512, "512"),
    (2048, "2048"),
    (4096, "4096"),
  ]
  let rows = StringBuilder()
  for i in 0..<candidates.length() {
    let (raw_block, label) = candidates[i]
    let actual_block = if raw_block == 0 {
      @lib.recommend_block_len(old_bytes.length().to_int64(), sum_len, limits)
    } else {
      raw_block.to_int64()
    }
    let sig = @lib.signature(
      old_bytes,
      { block_len: actual_block, strong_sum_len: sum_len, },
      limits,
    )
    let delta = @lib.delta(sig, new_bytes, limits)
    let summary = @lib.inspect_delta(delta, limits)
    let gz = @compress.compress_gzip(
      delta[:],
      limits.max_delta_bytes,
      limits.max_output_bytes,
    )
    if i > 0 {
      rows.write_char(',')
    }
    rows.write_string(
      "{\"label\":\"\{label}\",\"block_len\":\"\{actual_block}\",\"signature_bytes\":\"\{sig.length()}\",\"delta_bytes\":\"\{summary.delta_bytes}\",\"gzip_delta_bytes\":\"\{gz.length()}\",\"copy_bytes\":\"\{summary.copy_bytes}\",\"literal_bytes\":\"\{summary.literal_bytes}\",\"instruction_count\":\"\{summary.instruction_count}\"}",
    )
  }
  "{\"ok\":true,\"old_bytes\":\"\{old_bytes.length()}\",\"new_bytes\":\"\{new_bytes.length()}\",\"results\":[\{rows.to_string()}]}"
}

///|
/// Evaluate `[auto, 256, 512, 2048, 4096]` block sizes in pure MoonBit,
/// returning signature, delta, gzip-delta, copy/literal, and instruction counts.
pub fn benchmark_block_sizes_json(
  old_bytes : Bytes,
  new_bytes : Bytes,
  strong_sum_len : Int32,
) -> String {
  benchmark_block_sizes_impl(old_bytes, new_bytes, strong_sum_len) catch {
    err => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
  }
}

///|
/// Parse two Schema 3 directory snapshots and emit a Schema 3 verification report JSON.
pub fn verify_dir_snapshots_json(
  expected_json : String,
  actual_json : String,
) -> String {
  let limits = @lib.DirLimits::default()
  try {
    let expected = @lib.parse_dir_snapshot(@utf8.encode(expected_json), limits)
    let actual = @lib.parse_dir_snapshot(@utf8.encode(actual_json), limits)
    let report = @lib.verify_dir_snapshot(expected, actual, limits)
    @utf8.decode(@lib.encode_dir_verify_report(report, limits)) catch {
      _ => "{\"ok\":false,\"error\":\"InvalidUtf8\"}"
    }
  } catch {
    err => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
  }
}

///|
fn filter_dir_entries_impl(
  entries_json : String,
  patterns_json : String,
) -> String raise {
  let limits = @lib.DirLimits::default()
  let pat_tree = @json.parse(
    patterns_json,
    max_nesting_depth=2,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise @lib.ManifestError::InvalidJson
  }
  guard pat_tree is @json.Json::Array(raw_pats) else {
    raise @lib.ManifestError::InvalidSchema
  }
  guard raw_pats.length() <= 256 else {
    raise @lib.ManifestError::ResourceLimit("exclude_patterns")
  }
  let patterns : Array[String] = Array(capacity=raw_pats.length())
  for item in raw_pats {
    guard item is @json.Json::String(p) else {
      raise @lib.ManifestError::InvalidField("exclude")
    }
    let _ = @lib.match_dir_exclude("a", p)
    patterns.push(p)
  }
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
  guard items.length().to_int64() <= limits.max_entries * 4L else {
    raise @lib.ManifestError::ResourceLimit("dir_entries")
  }
  let entries : Array[@lib.DirEntry] = []
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
    let byte_length = parse_nonneg_decimal_str(len_str)
    let mut excluded = false
    for p in patterns {
      if @lib.match_dir_exclude(path, p) {
        excluded = true
        break
      }
    }
    if !excluded {
      entries.push({ path, digest: { byte_length, sha256, }, })
    }
  }
  let snapshot = @lib.create_dir_snapshot(entries, limits)
  let encoded = @lib.encode_dir_snapshot(snapshot, limits)
  @utf8.decode(encoded) catch {
    _ => raise @lib.ManifestError::InvalidUtf8
  }
}

///|
/// Validate exclude patterns upfront, filter raw `{path, byte_length, sha256}`
/// entries, and emit a canonical Schema 3 `moonlibsync-dir-snapshot` JSON string.
pub fn filter_dir_entries_json(
  entries_json : String,
  patterns_json : String,
) -> String {
  filter_dir_entries_impl(entries_json, patterns_json) catch {
    err => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
  }
}

///|
fn apply_verified_patch_impl(
  old_bytes : Bytes,
  delta_or_gz : Bytes,
  manifest_json : String,
) -> String raise {
  let limits = @lib.Limits::default()
  let trimmed = trim_ascii_whitespace(manifest_json)
  let mut parsed_tm : @lib.TransferManifest? = None
  let mut tm_err : Error? = None
  if trimmed.length() > 0 {
    let m_bytes = @utf8.encode(trimmed)
    try {
      parsed_tm = Some(@lib.parse_transfer_manifest(m_bytes, limits))
    } catch {
      err => tm_err = Some(err)
    }
  }
  let has_gz_magic = delta_or_gz.length() >= 2 &&
    delta_or_gz[0] == b'\x1f' &&
    delta_or_gz[1] == b'\x8b'
  let raw_full_matches = if has_gz_magic {
    match parsed_tm {
      Some(@lib.TransferManifest::Full(p, _)) =>
        delta_or_gz.length().to_int64() == p.byte_length &&
        sha256_file_digest(delta_or_gz, limits.max_new_bytes).sha256 == p.sha256
      _ => false
    }
  } else {
    false
  }
  let is_gz = has_gz_magic && !raw_full_matches
  let payload = if is_gz {
    @compress.decompress_gzip(
      delta_or_gz[:],
      limits.max_delta_bytes,
      limits.max_delta_bytes,
    )
  } else {
    delta_or_gz
  }
  let (restored, verified_manifest) = if trimmed.length() > 0 {
    match parsed_tm {
      Some(tm) =>
        (@lib.apply_update(Some(old_bytes), payload, tm, limits), true)
      None => {
        let m_bytes = @utf8.encode(trimmed)
        let mut parsed_um : @lib.UpdateManifest? = None
        let mut um_err : Error? = None
        try {
          parsed_um = Some(@lib.parse_update_manifest(m_bytes, limits))
        } catch {
          err => um_err = Some(err)
        }
        match parsed_um {
          Some(um) =>
            (@lib.verified_patch(old_bytes, payload, um, limits), true)
          None =>
            match tm_err {
              Some(e1) if !is_generic_json_mismatch(e1) => raise e1
              _ =>
                match um_err {
                  Some(e2) => raise e2
                  None => raise @lib.ManifestError::InvalidSchema
                }
            }
        }
      }
    }
  } else {
    (@lib.patch(old_bytes, payload, limits), false)
  }
  let h = @lib.Sha256Hasher::new(limits.max_output_bytes)
  h.update(restored[:])
  let dig = h.finish()
  "{\"ok\":true,\"decompressed_gzip\":\{is_gz},\"verified_manifest\":\{verified_manifest},\"output_bytes\":\"\{dig.byte_length}\",\"sha256\":\"\{dig.sha256}\"}"
}

///|
/// Apply a delta or gzip-wrapped delta with optional Schema 1/2 manifest verification,
/// returning structured JSON diagnostics and restored SHA-256.
pub fn apply_verified_patch_json(
  old_bytes : Bytes,
  delta_or_gz : Bytes,
  manifest_json : String,
) -> String {
  apply_verified_patch_impl(old_bytes, delta_or_gz, manifest_json) catch {
    err => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
  }
}

///|
/// Auto-decompress RFC 1952 gzip if present, then apply a standard 0x72730236 delta
/// to `old_bytes`, returning restored bytes (or empty bytes on error).
pub fn apply_patch_or_gzip_bytes(
  old_bytes : Bytes,
  delta_or_gz : Bytes,
) -> Bytes {
  let limits = @lib.Limits::default()
  try {
    let raw_delta = if delta_or_gz.length() >= 2 &&
      delta_or_gz[0] == b'\x1f' &&
      delta_or_gz[1] == b'\x8b' {
      @compress.decompress_gzip(
        delta_or_gz[:],
        limits.max_delta_bytes,
        limits.max_delta_bytes,
      )
    } else {
      delta_or_gz
    }
    @lib.patch(old_bytes, raw_delta, limits)
  } catch {
    _ => b""
  }
}

///|
/// Generate signature bytes for either `rk-blake2` (`0x72730147`) or
/// `rollsum-blake2` (`0x72730137`); `block_len = 0` uses auto policy v1.
/// Returns empty bytes on negative options, unknown profiles, or exceeded limits.
pub fn create_signature_with_profile_bytes(
  basis : Bytes,
  block_len : Int32,
  strong_sum_len : Int32,
  profile : String,
) -> Bytes {
  if block_len < 0 || strong_sum_len < 0 {
    return b""
  }
  let prof = match profile {
    "rk-blake2" | "0x72730147" => @lib.SignatureProfile::RkBlake2
    "rollsum-blake2" | "0x72730137" => @lib.SignatureProfile::RollsumBlake2
    _ => return b""
  }
  let limits = @lib.Limits::default()
  try {
    let sum_len = strong_sum_len.to_int64()
    let actual_block = if block_len == 0 {
      @lib.recommend_block_len(basis.length().to_int64(), sum_len, limits)
    } else {
      block_len.to_int64()
    }
    @lib.signature_with_profile(
      basis,
      { block_len: actual_block, strong_sum_len: sum_len, },
      prof,
      limits,
    )
  } catch {
    _ => b""
  }
}

///|
/// Generate a rollback delta (`NEW -> OLD`) that reverts `new_bytes` back to
/// `old_bytes` when passed to `apply_patch_bytes(new_bytes, rev_delta)`.
/// `block_len = 0` selects auto; `strong_sum_len = 0` selects default `16`.
/// Returns empty bytes on negative options or exceeded limits.
pub fn create_reverse_delta_bytes(
  old_bytes : Bytes,
  new_bytes : Bytes,
  block_len : Int32,
  strong_sum_len : Int32,
) -> Bytes {
  if block_len < 0 || strong_sum_len < 0 {
    return b""
  }
  let limits = @lib.Limits::default()
  try {
    let sum = if strong_sum_len == 0 { 16L } else { strong_sum_len.to_int64() }
    let actual_block = if block_len == 0 {
      @lib.recommend_block_len(new_bytes.length().to_int64(), sum, limits)
    } else {
      block_len.to_int64()
    }
    @lib.create_reverse_delta(
      old_bytes,
      new_bytes,
      { block_len: actual_block, strong_sum_len: sum, },
      limits,
    )
  } catch {
    _ => b""
  }
}

///|
fn parse_snapshot_or_entries(
  input : String,
  limits : @lib.DirLimits,
) -> @lib.DirSnapshot raise {
  let trimmed = trim_ascii_whitespace(input)
  if trimmed.has_prefix("[") {
    let snap_str = build_dir_snapshot_json_impl(trimmed)
    @lib.parse_dir_snapshot(@utf8.encode(snap_str), limits)
  } else {
    @lib.parse_dir_snapshot(@utf8.encode(input), limits)
  }
}

///|
/// Plan a Schema 3 directory sync from two snapshots (or raw entry arrays) with
/// optional content-digest move/copy detection (`detect_moves`).
pub fn plan_dir_snapshots_with_options_json(
  basis_entries_json : String,
  target_entries_json : String,
  detect_moves : Bool,
) -> String {
  let limits = @lib.DirLimits::default()
  try {
    let basis = parse_snapshot_or_entries(basis_entries_json, limits)
    let target = parse_snapshot_or_entries(target_entries_json, limits)
    let plan = @lib.plan_dir_sync_with_options(
      basis,
      target,
      { detect_moves, },
      limits,
    )
    @utf8.decode(@lib.encode_dir_plan(plan, limits)) catch {
      _ =>
        "{\"ok\":false,\"error\":\"InvalidUtf8\",\"message\":\"InvalidUtf8\"}"
    }
  } catch {
    err => err_json(err)
  }
}

///|
fn parse_hex_files_json(
  files_json : String,
  dir_limits : @lib.DirLimits,
  max_file_bytes : Int64,
) -> (Map[String, Bytes], Map[String, @lib.FileDigest], @lib.DirSnapshot) raise {
  let parsed = @json.parse(
    files_json,
    max_nesting_depth=3,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise @lib.ManifestError::InvalidJson
  }
  guard parsed is @json.Json::Array(items) else {
    raise @lib.ManifestError::InvalidSchema
  }
  guard items.length().to_int64() <= dir_limits.max_entries else {
    raise @lib.ManifestError::ResourceLimit("dir_entries")
  }
  let file_map : Map[String, Bytes] = Map([])
  let digest_map : Map[String, @lib.FileDigest] = Map([])
  let entries : Array[@lib.DirEntry] = Array(capacity=items.length())
  for item in items {
    guard item is @json.Json::Object(fields) else {
      raise @lib.ManifestError::InvalidSchema
    }
    guard fields.get("path") is Some(@json.Json::String(path)) else {
      raise @lib.ManifestError::InvalidField("path")
    }
    guard fields.get("content_hex") is Some(@json.Json::String(content_hex)) else {
      raise @lib.ManifestError::InvalidField("content_hex")
    }
    let data = decode_hex_bytes(content_hex, "content_hex", max_file_bytes)
    let digest = sha256_file_digest(data, max_file_bytes)
    file_map[path] = data
    digest_map[path] = digest
    entries.push({ path, digest, })
  }
  let snap = @lib.create_dir_snapshot(entries, dir_limits)
  (file_map, digest_map, snap)
}

///|
fn pack_dir_bundle_archive_impl(
  basis_files_json : String,
  target_files_json : String,
  detect_moves : Bool,
  gzip_compress : Bool,
) -> String raise {
  let limits = @lib.Limits::default()
  let dir_limits = @lib.DirLimits::default()
  let max_file = if dir_limits.max_file_bytes < limits.max_new_bytes {
    dir_limits.max_file_bytes
  } else {
    limits.max_new_bytes
  }
  let (basis_map, _, basis_snap) = parse_hex_files_json(
    basis_files_json, dir_limits, max_file,
  )
  let (target_map, _, target_snap) = parse_hex_files_json(
    target_files_json, dir_limits, max_file,
  )
  let plan = @lib.plan_dir_sync_with_options(
    basis_snap,
    target_snap,
    { detect_moves, },
    dir_limits,
  )
  let deleted_by_base : Map[String, String] = Map([])
  if detect_moves {
    for action in plan.actions {
      if action.kind is Delete {
        let base = path_basename(action.path)
        if !deleted_by_base.contains(base) {
          deleted_by_base[base] = action.path
        }
      }
    }
  }
  let bundle_entries : Array[@lib.DirBundleEntry] = []
  let payloads : Map[String, Bytes] = Map([])
  let mut payload_idx = 0
  for action in plan.actions {
    match action.kind {
      Unchanged =>
        match action.target {
          Some(d) =>
            bundle_entries.push({
              path: action.path,
              action: @lib.DirBundleAction::Unchanged(d),
            })
          None => raise @lib.ManifestError::InvalidField("target")
        }
      Delete =>
        match action.basis {
          Some(b) =>
            bundle_entries.push({
              path: action.path,
              action: @lib.DirBundleAction::Delete(b),
            })
          None => raise @lib.ManifestError::InvalidField("basis")
        }
      CopyFromBasis(src) =>
        match action.target {
          Some(d) =>
            bundle_entries.push({
              path: action.path,
              action: @lib.DirBundleAction::CopyFromBasis(src, d),
            })
          None => raise @lib.ManifestError::InvalidField("target")
        }
      UpdateCandidate => {
        let basis_bytes = match basis_map.get(action.path) {
          Some(b) => b
          None => raise @lib.ManifestError::BindingMismatch("basis_missing")
        }
        let target_bytes = match target_map.get(action.path) {
          Some(t) => t
          None => raise @lib.ManifestError::BindingMismatch("target_missing")
        }
        let basis_digest = match action.basis {
          Some(d) => d
          None => raise @lib.ManifestError::InvalidField("basis")
        }
        let target_digest = match action.target {
          Some(d) => d
          None => raise @lib.ManifestError::InvalidField("target")
        }
        let blen = @lib.recommend_block_len(
          basis_bytes.length().to_int64(),
          16L,
          limits,
        )
        let sig = @lib.signature(
          basis_bytes,
          { block_len: blen, strong_sum_len: 16L, },
          limits,
        )
        let delta = @lib.delta(sig, target_bytes, limits)
        if delta.length() < target_bytes.length() {
          let binfo = @lib.create_basis_info(basis_bytes, sig, limits)
          let um = @lib.create_update_manifest(
            binfo, sig, target_bytes, delta, limits,
          )
          let ppath = "payloads/\{payload_idx}.delta"
          payload_idx = payload_idx + 1
          payloads[ppath] = delta
          bundle_entries.push({
            path: action.path,
            action: @lib.DirBundleAction::UpdateDelta(ppath, um),
          })
        } else {
          let ppath = "payloads/\{payload_idx}.full"
          payload_idx = payload_idx + 1
          payloads[ppath] = target_bytes
          bundle_entries.push({
            path: action.path,
            action: @lib.DirBundleAction::UpdateFull(
              ppath, basis_digest, target_digest,
            ),
          })
        }
      }
      AddFull => {
        let target_bytes = match target_map.get(action.path) {
          Some(t) => t
          None => raise @lib.ManifestError::BindingMismatch("target_missing")
        }
        let target_digest = match action.target {
          Some(d) => d
          None => raise @lib.ManifestError::InvalidField("target")
        }
        let mut emitted_move_delta = false
        if detect_moves {
          match deleted_by_base.get(path_basename(action.path)) {
            Some(src_path) if src_path != action.path =>
              match basis_map.get(src_path) {
                Some(src_bytes) if src_bytes.length() > 0 => {
                  let blen = @lib.recommend_block_len(
                    src_bytes.length().to_int64(),
                    16L,
                    limits,
                  )
                  let sig = @lib.signature(
                    src_bytes,
                    { block_len: blen, strong_sum_len: 16L, },
                    limits,
                  )
                  let delta = @lib.delta(sig, target_bytes, limits)
                  if delta.length() < target_bytes.length() {
                    let binfo = @lib.create_basis_info(src_bytes, sig, limits)
                    let um = @lib.create_update_manifest(
                      binfo, sig, target_bytes, delta, limits,
                    )
                    let ppath = "payloads/\{payload_idx}.delta"
                    payload_idx = payload_idx + 1
                    payloads[ppath] = delta
                    bundle_entries.push({
                      path: action.path,
                      action: @lib.DirBundleAction::UpdateDeltaFrom(
                        src_path, ppath, um,
                      ),
                    })
                    emitted_move_delta = true
                  }
                }
                _ => ()
              }
            _ => ()
          }
        }
        if !emitted_move_delta {
          let ppath = "payloads/\{payload_idx}.full"
          payload_idx = payload_idx + 1
          payloads[ppath] = target_bytes
          bundle_entries.push({
            path: action.path,
            action: @lib.DirBundleAction::AddFull(ppath, target_digest),
          })
        }
      }
    }
  }
  let manifest = @lib.create_dir_bundle_manifest(
    bundle_entries, dir_limits, limits,
  )
  let manifest_raw_bytes = @lib.encode_dir_bundle_manifest(
    manifest, dir_limits, limits,
  )
  let manifest_json = trim_ascii_whitespace(
    @utf8.decode(manifest_raw_bytes) catch {
      _ => raise @lib.ManifestError::InvalidUtf8
    },
  )
  let raw_archive = @lib.encode_bundle_archive(
    manifest, payloads, dir_limits, limits,
  )
  let final_archive = if gzip_compress {
    @compress.compress_gzip(
      raw_archive[:],
      limits.max_output_bytes,
      limits.max_output_bytes,
      level=6,
    )
  } else {
    raw_archive
  }
  let archive_hex = bytes_view_to_hex(final_archive[:])
  "{\"ok\":true,\"gzip\":\{gzip_compress},\"raw_bytes\":\{raw_archive.length()},\"archive_bytes\":\{final_archive.length()},\"archive_hex\":\"\{archive_hex}\",\"manifest\":\{manifest_json},\"summary\":{\"unchanged\":\"\{manifest.unchanged_count}\",\"add_full\":\"\{manifest.add_full_count}\",\"update_delta\":\"\{manifest.update_delta_count}\",\"update_full\":\"\{manifest.update_full_count}\",\"delete\":\"\{manifest.delete_count}\",\"copy_from_basis\":\"\{manifest.copy_from_basis_count}\",\"total_payload_bytes\":\"\{manifest.total_payload_bytes}\"}}"
}

///|
/// Pack two in-memory file lists (`[{"path","content_hex"}]`) into a single-file
/// `MLSBDL01` `.mbundle` (or `.mbundle.gz`) archive with optional move detection.
pub fn pack_dir_bundle_archive_json(
  basis_files_json : String,
  target_files_json : String,
  detect_moves : Bool,
  gzip_compress : Bool,
) -> String {
  pack_dir_bundle_archive_impl(
    basis_files_json, target_files_json, detect_moves, gzip_compress,
  ) catch {
    err => err_json(err)
  }
}

///|
fn unpack_dir_bundle_archive_impl(
  basis_files_json : String,
  archive_bytes : Bytes,
) -> String raise {
  let limits = @lib.Limits::default()
  let dir_limits = @lib.DirLimits::default()
  let max_file = if dir_limits.max_file_bytes < limits.max_output_bytes {
    dir_limits.max_file_bytes
  } else {
    limits.max_output_bytes
  }
  let (basis_map, basis_digests, _) = parse_hex_files_json(
    basis_files_json, dir_limits, max_file,
  )
  let was_gzip = archive_bytes.length() >= 2 &&
    archive_bytes[0] == b'\x1f' &&
    archive_bytes[1] == b'\x8b'
  let raw_archive = if was_gzip {
    @compress.decompress_gzip(
      archive_bytes[:],
      limits.max_output_bytes,
      67108864L,
    )
  } else {
    archive_bytes
  }
  let decoded = @lib.parse_bundle_archive(raw_archive, dir_limits, limits)
  let manifest = decoded.manifest
  let payloads = decoded.payloads
  let files_sb = StringBuilder()
  let mut file_count = 0
  for entry in manifest.entries {
    let restored_opt : (Bytes, @lib.FileDigest)? = match entry.action {
      Unchanged(expected) => {
        let data = match basis_map.get(entry.path) {
          Some(b) => b
          None => raise @lib.ManifestError::BindingMismatch("missing_basis")
        }
        let actual = match basis_digests.get(entry.path) {
          Some(d) => d
          None => raise @lib.ManifestError::BindingMismatch("missing_basis")
        }
        guard actual.byte_length == expected.byte_length &&
          actual.sha256 == expected.sha256 else {
          raise @lib.ManifestError::BindingMismatch("basis_digest")
        }
        Some((data, expected))
      }
      Delete(expected_basis) => {
        match basis_digests.get(entry.path) {
          Some(actual) => {
            guard actual.byte_length == expected_basis.byte_length &&
              actual.sha256 == expected_basis.sha256 else {
              raise @lib.ManifestError::BindingMismatch("delete_basis_digest")
            }
          }
          None => ()
        }
        None
      }
      CopyFromBasis(source_path, expected) => {
        let data = match basis_map.get(source_path) {
          Some(b) => b
          None => raise @lib.ManifestError::BindingMismatch("missing_source")
        }
        let actual = match basis_digests.get(source_path) {
          Some(d) => d
          None => raise @lib.ManifestError::BindingMismatch("missing_source")
        }
        guard actual.byte_length == expected.byte_length &&
          actual.sha256 == expected.sha256 else {
          raise @lib.ManifestError::BindingMismatch("source_digest")
        }
        Some((data, expected))
      }
      UpdateDelta(payload_path, um) => {
        let basis_data = match basis_map.get(entry.path) {
          Some(b) => b
          None => raise @lib.ManifestError::BindingMismatch("missing_basis")
        }
        let delta_data = match payloads.get(payload_path) {
          Some(d) => d
          None => raise @lib.ManifestError::BindingMismatch("missing_payload")
        }
        let restored = @lib.verified_patch(basis_data, delta_data, um, limits)
        let actual = sha256_file_digest(restored, max_file)
        guard actual.byte_length == um.result.byte_length &&
          actual.sha256 == um.result.sha256 else {
          raise @lib.ManifestError::BindingMismatch("result_digest")
        }
        Some((restored, actual))
      }
      UpdateDeltaFrom(source_path, payload_path, um) => {
        let src_data = match basis_map.get(source_path) {
          Some(b) => b
          None => raise @lib.ManifestError::BindingMismatch("missing_source")
        }
        let delta_data = match payloads.get(payload_path) {
          Some(d) => d
          None => raise @lib.ManifestError::BindingMismatch("missing_payload")
        }
        let restored = @lib.verified_patch(src_data, delta_data, um, limits)
        let actual = sha256_file_digest(restored, max_file)
        guard actual.byte_length == um.result.byte_length &&
          actual.sha256 == um.result.sha256 else {
          raise @lib.ManifestError::BindingMismatch("result_digest")
        }
        Some((restored, actual))
      }
      AddFull(payload_path, expected) => {
        let data = match payloads.get(payload_path) {
          Some(d) => d
          None => raise @lib.ManifestError::BindingMismatch("missing_payload")
        }
        let actual = sha256_file_digest(data, max_file)
        guard actual.byte_length == expected.byte_length &&
          actual.sha256 == expected.sha256 else {
          raise @lib.ManifestError::BindingMismatch("payload_digest")
        }
        Some((data, actual))
      }
      UpdateFull(payload_path, expected_basis, expected_target) => {
        let basis_actual = match basis_digests.get(entry.path) {
          Some(d) => d
          None => raise @lib.ManifestError::BindingMismatch("missing_basis")
        }
        guard basis_actual.byte_length == expected_basis.byte_length &&
          basis_actual.sha256 == expected_basis.sha256 else {
          raise @lib.ManifestError::BindingMismatch("basis_digest")
        }
        let data = match payloads.get(payload_path) {
          Some(d) => d
          None => raise @lib.ManifestError::BindingMismatch("missing_payload")
        }
        let actual = sha256_file_digest(data, max_file)
        guard actual.byte_length == expected_target.byte_length &&
          actual.sha256 == expected_target.sha256 else {
          raise @lib.ManifestError::BindingMismatch("payload_digest")
        }
        Some((data, actual))
      }
    }
    match restored_opt {
      Some((bytes, digest)) => {
        if file_count > 0 {
          files_sb.write_char(',')
        }
        let p_esc = json_escape_str(entry.path)
        let content_hex = bytes_view_to_hex(bytes[:])
        files_sb.write_string(
          "{\"path\":\"\{p_esc}\",\"byte_length\":\{bytes.length()},\"sha256\":\"\{digest.sha256}\",\"content_hex\":\"\{content_hex}\"}",
        )
        file_count = file_count + 1
      }
      None => ()
    }
  }
  let manifest_raw_bytes = @lib.encode_dir_bundle_manifest(
    manifest, dir_limits, limits,
  )
  let manifest_json = trim_ascii_whitespace(
    @utf8.decode(manifest_raw_bytes) catch {
      _ => raise @lib.ManifestError::InvalidUtf8
    },
  )
  "{\"ok\":true,\"was_gzip\":\{was_gzip},\"file_count\":\{file_count},\"manifest\":\{manifest_json},\"files\":[\{files_sb.to_string()}]}"
}

///|
/// Unpack and cryptographically verify a `.mbundle` or `.mbundle.gz` archive
/// against `basis_files_json`, returning all restored files and SHA-256 digests.
pub fn unpack_dir_bundle_archive_json(
  basis_files_json : String,
  archive_bytes : Bytes,
) -> String {
  unpack_dir_bundle_archive_impl(basis_files_json, archive_bytes) catch {
    err => err_json(err)
  }
}

///|
fn ed25519_keypair_from_seed_impl(seed : Bytes) -> String raise {
  let kp = @crypto.keypair_from_seed(seed)
  let key_id = @crypto.key_id_from_public_key(kp.public_key)
  let seed_hex = @crypto.encode_key_hex(kp.seed)
  let public_key_hex = @crypto.encode_key_hex(kp.public_key)
  "{\"ok\":true,\"seed_hex\":\"\{seed_hex}\",\"public_key_hex\":\"\{public_key_hex}\",\"key_id\":\"\{key_id}\"}"
}

///|
/// Derive a canonical Ed25519 key pair and 16-hex key ID from a 32-byte seed.
pub fn ed25519_keypair_from_seed_json(seed : Bytes) -> String {
  ed25519_keypair_from_seed_impl(seed) catch {
    err => err_json(err)
  }
}

///|
fn ed25519_sign_bytes_impl(seed : Bytes, payload : Bytes) -> String raise {
  let sig = @crypto.sign_bytes(seed, payload)
  let raw = @crypto.encode_publisher_signature(sig)
  let sig_json = @utf8.decode(raw) catch {
    _ => raise @crypto.CryptoError::InvalidFormat("utf8")
  }
  let sig_obj = trim_ascii_whitespace(sig_json)
  let sig_escaped = json_escape_str(sig_json)
  "{\"ok\":true,\"signature_json\":\"\{sig_escaped}\",\"signature\":\{sig_obj}}"
}

///|
/// Sign raw bytes with a 32-byte Ed25519 seed and emit a canonical Schema 4
/// `moonlibsync-signature` JSON envelope.
pub fn ed25519_sign_bytes_json(seed : Bytes, payload : Bytes) -> String {
  ed25519_sign_bytes_impl(seed, payload) catch {
    err => err_json(err)
  }
}

///|
fn ed25519_verify_bytes_impl(
  sig_json : String,
  trusted_pubkeys_json : String,
  payload : Bytes,
) -> String raise {
  let sig = @crypto.parse_publisher_signature(@utf8.encode(sig_json))
  let parsed = @json.parse(
    trusted_pubkeys_json,
    max_nesting_depth=2,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise @crypto.CryptoError::InvalidFormat("trusted_pubkeys_json")
  }
  guard parsed is @json.Json::Array(items) else {
    raise @crypto.CryptoError::InvalidFormat("trusted_pubkeys")
  }
  guard items.length() <= 256 else {
    raise @crypto.CryptoError::LimitExceeded("trusted_pubkeys")
  }
  let keys : Array[Bytes] = Array(capacity=items.length())
  for item in items {
    guard item is @json.Json::String(pk_hex) else {
      raise @crypto.CryptoError::InvalidFormat("trusted_pubkeys")
    }
    keys.push(@crypto.decode_key_hex(pk_hex, 32, "trusted_pubkeys"))
  }
  @crypto.verify_bytes(sig, keys, payload)
  "{\"ok\":true,\"verified\":true,\"key_id\":\"\{sig.key_id}\",\"public_key\":\"\{sig.public_key_hex}\",\"payload_length\":\"\{sig.payload_length}\",\"payload_sha256\":\"\{sig.payload_sha256}\"}"
}

///|
/// Verify a Schema 4 `moonlibsync-signature` JSON envelope against a JSON array
/// of trusted 64-hex Ed25519 public keys and the payload bytes.
pub fn ed25519_verify_bytes_json(
  sig_json : String,
  trusted_pubkeys_json : String,
  payload : Bytes,
) -> String {
  ed25519_verify_bytes_impl(sig_json, trusted_pubkeys_json, payload) catch {
    err => {
      let tag = json_escape_str(sync_err_label(err))
      "{\"ok\":false,\"verified\":false,\"error\":\"\{tag}\",\"message\":\"\{tag}\"}"
    }
  }
}

///|
fn seal_bytes_impl(
  plain : Bytes,
  secret : Bytes,
  use_passphrase : Bool,
  salt16 : Bytes,
  nonce_prefix12 : Bytes,
  chunk_size : Int32,
  argon2_memory_kib : Int32,
  argon2_passes : Int32,
) -> String raise {
  guard chunk_size >= 0 else {
    raise @crypto.CryptoError::InvalidOptions("chunk_size")
  }
  guard argon2_memory_kib >= 0 else {
    raise @crypto.CryptoError::InvalidOptions("argon2_memory_kib")
  }
  guard argon2_passes >= 0 else {
    raise @crypto.CryptoError::InvalidOptions("argon2_passes")
  }
  let actual_chunk = if chunk_size == 0 { 65536 } else { chunk_size }
  let actual_mem = if argon2_memory_kib == 0 {
    16384
  } else {
    argon2_memory_kib
  }
  let actual_passes = if argon2_passes == 0 { 2 } else { argon2_passes }
  let opts : @crypto.SealOptions = {
    chunk_size: actual_chunk,
    argon2_memory_kib: actual_mem,
    argon2_passes: actual_passes,
    argon2_lanes: 1,
  }
  let limits = @crypto.SealLimits::default()
  let cipher = if use_passphrase {
    @crypto.seal_with_passphrase(
      plain, secret, salt16, nonce_prefix12, opts, limits,
    )
  } else {
    @crypto.seal_with_key(plain, secret, salt16, nonce_prefix12, opts, limits)
  }
  let kdf_mode = if use_passphrase { "argon2id" } else { "raw-key" }
  let cipher_hex = bytes_view_to_hex(cipher[:])
  "{\"ok\":true,\"kdf_mode\":\"\{kdf_mode}\",\"plain_bytes\":\{plain.length()},\"cipher_bytes\":\{cipher.length()},\"chunk_size\":\{actual_chunk},\"cipher_hex\":\"\{cipher_hex}\"}"
}

///|
/// Seal plaintext into an authenticated `MLSENC01` ChaCha20-Poly1305 `.menc`
/// container using either a raw 32-byte key or Argon2id passphrase derivation.
pub fn seal_bytes_json(
  plain : Bytes,
  secret : Bytes,
  use_passphrase : Bool,
  salt16 : Bytes,
  nonce_prefix12 : Bytes,
  chunk_size : Int32,
  argon2_memory_kib : Int32,
  argon2_passes : Int32,
) -> String {
  seal_bytes_impl(
    plain, secret, use_passphrase, salt16, nonce_prefix12, chunk_size, argon2_memory_kib,
    argon2_passes,
  ) catch {
    err => err_json(err)
  }
}

///|
fn unseal_bytes_impl(
  cipher : Bytes,
  secret : Bytes,
  use_passphrase : Bool,
) -> String raise {
  let limits = @crypto.SealLimits::default()
  let hdr = @crypto.inspect_seal_header(cipher[:], limits)
  let plain = if use_passphrase {
    @crypto.unseal_with_passphrase(cipher, secret, limits)
  } else {
    @crypto.unseal_with_key(cipher, secret, limits)
  }
  let digest = sha256_file_digest(plain, limits.max_output_bytes)
  let kdf_mode = if hdr.kdf_mode == b'\x00' { "raw-key" } else { "argon2id" }
  let plain_hex = bytes_view_to_hex(plain[:])
  "{\"ok\":true,\"kdf_mode\":\"\{kdf_mode}\",\"chunk_size\":\{hdr.chunk_size},\"plain_bytes\":\{plain.length()},\"plain_sha256\":\"\{digest.sha256}\",\"plain_hex\":\"\{plain_hex}\"}"
}

///|
/// Unseal and authenticate a `MLSENC01` `.menc` container using either a raw
/// 32-byte key or Argon2id passphrase, returning plaintext hex and SHA-256.
pub fn unseal_bytes_json(
  cipher : Bytes,
  secret : Bytes,
  use_passphrase : Bool,
) -> String {
  unseal_bytes_impl(cipher, secret, use_passphrase) catch {
    err => err_json(err)
  }
}

///|
fn plan_range_fetch_impl(
  target_sig : Bytes,
  target_length : Int32,
  basis : Bytes,
  merge_gap_bytes : Int32,
  max_ranges : Int32,
) -> String raise {
  let limits = @lib.Limits::default()
  let plan = @lib.plan_range_fetch(
    target_sig,
    target_length.to_int64(),
    basis,
    {
      merge_gap_bytes: merge_gap_bytes.to_int64(),
      max_ranges: max_ranges.to_int64(),
    },
    limits,
  )
  let raw = @lib.encode_range_plan_json(plan)
  let plan_json = trim_ascii_whitespace(
    @utf8.decode(raw) catch {
      _ => raise @lib.ManifestError::InvalidUtf8
    },
  )
  "{\"ok\":true,\"plan\":\{plan_json}}"
}

///|
/// Plan a client-pull HTTP Range fetch (`zsync`-style) from a remote librsync
/// signature, remote target byte length, and local basis bytes.
pub fn plan_range_fetch_json(
  target_sig : Bytes,
  target_length : Int32,
  basis : Bytes,
  merge_gap_bytes : Int32,
  max_ranges : Int32,
) -> String {
  plan_range_fetch_impl(
    target_sig, target_length, basis, merge_gap_bytes, max_ranges,
  ) catch {
    err => err_json(err)
  }
}

///|
fn apply_range_fetch_impl(
  target_sig : Bytes,
  target_length : Int32,
  basis : Bytes,
  merge_gap_bytes : Int32,
  max_ranges : Int32,
  slices_json : String,
) -> String raise {
  let limits = @lib.Limits::default()
  let plan = @lib.plan_range_fetch(
    target_sig,
    target_length.to_int64(),
    basis,
    {
      merge_gap_bytes: merge_gap_bytes.to_int64(),
      max_ranges: max_ranges.to_int64(),
    },
    limits,
  )
  let parsed = @json.parse(
    slices_json,
    max_nesting_depth=2,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise @lib.ManifestError::InvalidJson
  }
  guard parsed is @json.Json::Array(items) else {
    raise @lib.ManifestError::InvalidSchema
  }
  guard items.length() == plan.ranges.length() else {
    raise @lib.SyncError::InvalidOptions("fetched_slices")
  }
  let slices : Array[Bytes] = Array(capacity=items.length())
  let mut total_slice_bytes = 0L
  for item in items {
    guard item is @json.Json::String(hex_str) else {
      raise @lib.ManifestError::InvalidField("slices")
    }
    let slice = decode_hex_bytes(hex_str, "slices", limits.max_output_bytes)
    guard slice.length().to_int64() <=
      limits.max_output_bytes - total_slice_bytes else {
      raise @lib.SyncError::LimitExceeded
    }
    total_slice_bytes = total_slice_bytes + slice.length().to_int64()
    slices.push(slice)
  }
  let restored = @lib.apply_range_fetch(basis, plan, slices, limits)
  let digest = sha256_file_digest(restored, limits.max_output_bytes)
  let restored_hex = bytes_view_to_hex(restored[:])
  "{\"ok\":true,\"restored_hex\":\"\{restored_hex}\",\"restored_bytes\":\{restored.length()},\"restored_sha256\":\"\{digest.sha256}\",\"reused_bytes\":\{plan.reused_bytes},\"fetch_bytes\":\{plan.fetch_bytes},\"request_bytes\":\{plan.request_bytes},\"range_count\":\{plan.ranges.length()}}"
}

///|
/// Reconstruct a target file from local `basis` and hex-encoded HTTP Range slices
/// matching the deterministic plan computed from `(target_sig, target_length)`.
pub fn apply_range_fetch_json(
  target_sig : Bytes,
  target_length : Int32,
  basis : Bytes,
  merge_gap_bytes : Int32,
  max_ranges : Int32,
  slices_json : String,
) -> String {
  apply_range_fetch_impl(
    target_sig, target_length, basis, merge_gap_bytes, max_ranges, slices_json,
  ) catch {
    err => err_json(err)
  }
}

///|
fn compose_deltas_impl(deltas_json : String) -> String raise {
  let limits = @lib.Limits::default()
  let parsed = @json.parse(
    deltas_json,
    max_nesting_depth=2,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise @lib.ManifestError::InvalidJson
  }
  guard parsed is @json.Json::Array(items) else {
    raise @lib.ManifestError::InvalidSchema
  }
  guard items.length() >= 1 else {
    raise @lib.SyncError::InvalidOptions("deltas")
  }
  guard items.length() <= 256 else {
    raise @lib.ManifestError::ResourceLimit("deltas")
  }
  let deltas : Array[Bytes] = Array(capacity=items.length())
  let mut input_total_bytes = 0L
  for item in items {
    guard item is @json.Json::String(hex_str) else {
      raise @lib.ManifestError::InvalidField("deltas")
    }
    let d = decode_hex_bytes(hex_str, "deltas", limits.max_delta_bytes)
    input_total_bytes = input_total_bytes + d.length().to_int64()
    deltas.push(d)
  }
  let composed = @lib.compose_delta_chain(deltas, limits)
  let summary = @lib.inspect_delta(composed, limits)
  let digest = sha256_file_digest(composed, limits.max_delta_bytes)
  let composed_hex = bytes_view_to_hex(composed[:])
  "{\"ok\":true,\"composed_hex\":\"\{composed_hex}\",\"composed_bytes\":\{composed.length()},\"composed_sha256\":\"\{digest.sha256}\",\"input_total_bytes\":\{input_total_bytes},\"instruction_count\":\{summary.instruction_count},\"copy_count\":\{summary.copy_commands},\"literal_count\":\{summary.literal_commands},\"copy_bytes\":\{summary.copy_bytes},\"literal_bytes\":\{summary.literal_bytes},\"output_bytes\":\{summary.output_bytes}}"
}

///|
/// Compose a non-empty chain of hex-encoded librsync `0x72730236` deltas
/// (`v0->v1`, `v1->v2`, ..., `v(k-1)->vk`) into one direct `v0->vk` delta.
pub fn compose_deltas_json(deltas_json : String) -> String {
  compose_deltas_impl(deltas_json) catch {
    err => err_json(err)
  }
}

///|
/// Compress bytes into a bounded RFC 1950 zlib stream (`level` 0..=9).
/// Returns empty bytes on invalid options or exceeded limits.
pub fn compress_zlib_bytes(
  input : Bytes,
  max_input : Int32,
  max_output : Int32,
  level : Int32,
) -> Bytes {
  @compress.compress_zlib(
    input[:],
    max_input.to_int64(),
    max_output.to_int64(),
    level~,
  ) catch {
    _ => b""
  }
}

///|
fn decompress_zlib_check_impl(
  input : Bytes,
  max_input : Int32,
  max_output : Int32,
) -> String raise {
  let plain = @compress.decompress_zlib(
    input[:],
    max_input.to_int64(),
    max_output.to_int64(),
  )
  let digest = sha256_file_digest(plain, plain.length().to_int64())
  let output_hex = bytes_view_to_hex(plain[:])
  "{\"ok\":true,\"input_bytes\":\{input.length()},\"output_bytes\":\{plain.length()},\"output_sha256\":\"\{digest.sha256}\",\"output_hex\":\"\{output_hex}\"}"
}

///|
/// Decompress a bounded RFC 1950 zlib stream and return structured JSON diagnostics,
/// plaintext hex, and SHA-256 (rejecting zip bombs, trailing data, and truncation).
pub fn decompress_zlib_check_json(
  input : Bytes,
  max_input : Int32,
  max_output : Int32,
) -> String {
  decompress_zlib_check_impl(input, max_input, max_output) catch {
    err => err_json(err)
  }
}

///|
fn x25519_keypair_from_secret_impl(secret_hex : String) -> String raise {
  let secret = @crypto.decode_key_hex(secret_hex, 32, "x25519_secret")
  let kp = @crypto.x25519_keypair_from_secret(secret)
  let key_id = @crypto.x25519_key_id(kp.public_key)
  let sk_hex = @crypto.encode_key_hex(kp.secret_key)
  let pk_hex = @crypto.encode_key_hex(kp.public_key)
  "{\"ok\":true,\"secret_key_hex\":\"\{sk_hex}\",\"public_key_hex\":\"\{pk_hex}\",\"key_id\":\"\{key_id}\"}"
}

///|
/// Derive a canonical X25519 key pair and 16-hex key ID from a 64-hex secret scalar.
pub fn x25519_keypair_from_secret_json(secret_hex : String) -> String {
  x25519_keypair_from_secret_impl(secret_hex) catch {
    err => err_json(err)
  }
}

///|
fn seal_envelope_impl(
  plaintext : Bytes,
  recipient_pubs_json : String,
  ephemeral_secret_hex : String,
  content_key_hex : String,
  nonce_prefix_hex : String,
  chunk_size : Int32,
) -> String raise {
  guard chunk_size >= 0 else {
    raise @crypto.CryptoError::InvalidOptions("chunk_size")
  }
  let actual_chunk = if chunk_size == 0 { 65536 } else { chunk_size }
  let parsed = @json.parse(
    recipient_pubs_json,
    max_nesting_depth=2,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise @crypto.CryptoError::InvalidFormat("recipient_pubs_json")
  }
  guard parsed is @json.Json::Array(items) else {
    raise @crypto.CryptoError::InvalidFormat("recipient_pubs")
  }
  guard items.length() <= 64 else {
    raise @crypto.CryptoError::InvalidOptions("recipient_count")
  }
  let recipient_pubs : Array[Bytes] = Array(capacity=items.length())
  for item in items {
    guard item is @json.Json::String(pk_hex) else {
      raise @crypto.CryptoError::InvalidFormat("recipient_pubs")
    }
    recipient_pubs.push(
      @crypto.decode_key_hex(pk_hex, 32, "recipient_public_key"),
    )
  }
  let ephemeral_secret = @crypto.decode_key_hex(
    ephemeral_secret_hex, 32, "ephemeral_secret",
  )
  let content_key = @crypto.decode_key_hex(content_key_hex, 32, "content_key")
  let nonce_prefix = @crypto.decode_key_hex(nonce_prefix_hex, 4, "nonce_prefix")
  let opts : @crypto.SealOptions = {
    chunk_size: actual_chunk,
    argon2_memory_kib: 16384,
    argon2_passes: 2,
    argon2_lanes: 1,
  }
  let limits = @crypto.SealLimits::default()
  let cipher = @crypto.seal_envelope(
    plaintext, recipient_pubs, ephemeral_secret, content_key, nonce_prefix, opts,
    limits,
  )
  let hdr = @crypto.inspect_envelope_header(cipher[:], limits)
  let digest = sha256_file_digest(cipher, limits.max_output_bytes)
  let cipher_hex = bytes_view_to_hex(cipher[:])
  let eph_hex = @crypto.encode_key_hex(hdr.ephemeral_public_key)
  let rec_ids_json = json_string_array(hdr.recipient_key_ids)
  "{\"ok\":true,\"ciphertext_hex\":\"\{cipher_hex}\",\"ciphertext_bytes\":\{cipher.length()},\"ciphertext_sha256\":\"\{digest.sha256}\",\"recipient_count\":\{hdr.recipient_key_ids.length()},\"recipient_key_ids\":\{rec_ids_json},\"ephemeral_public_key_hex\":\"\{eph_hex}\",\"chunk_size\":\{hdr.chunk_size}}"
}

///|
/// Seal `plaintext` into an authenticated `MLSENC02` multi-recipient X25519
/// ChaCha20-Poly1305 envelope for 1..=64 recipients.
pub fn seal_envelope_json(
  plaintext : Bytes,
  recipient_pubs_json : String,
  ephemeral_secret_hex : String,
  content_key_hex : String,
  nonce_prefix_hex : String,
  chunk_size : Int32,
) -> String {
  seal_envelope_impl(
    plaintext, recipient_pubs_json, ephemeral_secret_hex, content_key_hex, nonce_prefix_hex,
    chunk_size,
  ) catch {
    err => err_json(err)
  }
}

///|
fn unseal_envelope_impl(
  ciphertext : Bytes,
  recipient_secret_hex : String,
) -> String raise {
  let recipient_secret = @crypto.decode_key_hex(
    recipient_secret_hex, 32, "x25519_secret",
  )
  let limits = @crypto.SealLimits::default()
  let plain = @crypto.unseal_envelope(ciphertext, recipient_secret, limits)
  let hdr = @crypto.inspect_envelope_header(ciphertext[:], limits)
  let digest = sha256_file_digest(plain, limits.max_output_bytes)
  let plain_hex = bytes_view_to_hex(plain[:])
  let eph_hex = @crypto.encode_key_hex(hdr.ephemeral_public_key)
  let rec_ids_json = json_string_array(hdr.recipient_key_ids)
  "{\"ok\":true,\"plaintext_hex\":\"\{plain_hex}\",\"plaintext_bytes\":\{plain.length()},\"plaintext_sha256\":\"\{digest.sha256}\",\"recipient_count\":\{hdr.recipient_key_ids.length()},\"recipient_key_ids\":\{rec_ids_json},\"ephemeral_public_key_hex\":\"\{eph_hex}\"}"
}

///|
/// Unseal and authenticate an `MLSENC02` multi-recipient envelope using one
/// recipient's 64-hex X25519 secret scalar.
pub fn unseal_envelope_json(
  ciphertext : Bytes,
  recipient_secret_hex : String,
) -> String {
  unseal_envelope_impl(ciphertext, recipient_secret_hex) catch {
    err => err_json(err)
  }
}

///|
fn create_trust_keyring_impl(
  trusted_keys_json : String,
  revoked_ids_json : String,
  min_quorum : Int32,
) -> String raise {
  let parsed_keys = @json.parse(
    trusted_keys_json,
    max_nesting_depth=2,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise @crypto.CryptoError::InvalidFormat("trusted_keys_json")
  }
  guard parsed_keys is @json.Json::Array(key_items) else {
    raise @crypto.CryptoError::InvalidFormat("trusted_keys")
  }
  guard key_items.length() <= 256 else {
    raise @crypto.CryptoError::LimitExceeded("trusted_keys")
  }
  let trusted_keys : Array[Bytes] = Array(capacity=key_items.length())
  for item in key_items {
    guard item is @json.Json::String(pk_hex) else {
      raise @crypto.CryptoError::InvalidFormat("trusted_keys")
    }
    trusted_keys.push(@crypto.decode_key_hex(pk_hex, 32, "trusted_keys"))
  }
  let parsed_rev = @json.parse(
    revoked_ids_json,
    max_nesting_depth=2,
    reject_duplicate_keys=true,
  ) catch {
    _ => raise @crypto.CryptoError::InvalidFormat("revoked_ids_json")
  }
  guard parsed_rev is @json.Json::Array(rev_items) else {
    raise @crypto.CryptoError::InvalidFormat("revoked_ids")
  }
  guard rev_items.length() <= 256 else {
    raise @crypto.CryptoError::LimitExceeded("revoked_ids")
  }
  let revoked_ids : Array[String] = Array(capacity=rev_items.length())
  for item in rev_items {
    guard item is @json.Json::String(id_str) else {
      raise @crypto.CryptoError::InvalidFormat("revoked_ids")
    }
    revoked_ids.push(id_str)
  }
  let kr = @crypto.create_trust_keyring(trusted_keys, revoked_ids, min_quorum)
  let raw = @crypto.encode_trust_keyring(kr)
  let kr_str = @utf8.decode(raw) catch {
    _ => raise @crypto.CryptoError::InvalidFormat("utf8")
  }
  let key_ids : Array[String] = Array(capacity=kr.trusted_keys.length())
  for pk in kr.trusted_keys {
    key_ids.push(@crypto.key_id_from_public_key(pk))
  }
  let kr_escaped = json_escape_str(kr_str)
  let key_ids_json = json_string_array(key_ids)
  "{\"ok\":true,\"keyring_json\":\"\{kr_escaped}\",\"trusted_count\":\{kr.trusted_keys.length()},\"revoked_count\":\{kr.revoked_key_ids.length()},\"min_quorum\":\{kr.min_quorum},\"key_ids\":\{key_ids_json}}"
}

///|
/// Construct and encode a canonical Schema 4 Ed25519 `TrustKeyring` JSON with
/// optional revoked key IDs and an M-of-N threshold quorum policy.
pub fn create_trust_keyring_json(
  trusted_keys_json : String,
  revoked_ids_json : String,
  min_quorum : Int32,
) -> String {
  create_trust_keyring_impl(trusted_keys_json, revoked_ids_json, min_quorum) catch {
    err => err_json(err)
  }
}

///|
fn parse_sig_json_object(
  fields : Map[String, @json.Json],
) -> @crypto.PublisherSignature raise @crypto.CryptoError {
  let len = fields.length()
  if len == 8 {
    guard fields.get("schema_version")
      is Some(@json.Json::Number(1.0, repr=Some("1"))) else {
      raise @crypto.CryptoError::InvalidFormat("schema_version")
    }
    guard fields.get("kind")
      is Some(@json.Json::String("moonlibsync-signature")) else {
      raise @crypto.CryptoError::InvalidFormat("kind")
    }
  } else if len != 6 {
    raise @crypto.CryptoError::InvalidFormat("signature_schema")
  }
  guard fields.get("algorithm") is Some(@json.Json::String(algorithm)) else {
    raise @crypto.CryptoError::InvalidFormat("algorithm")
  }
  guard fields.get("key_id") is Some(@json.Json::String(key_id)) else {
    raise @crypto.CryptoError::InvalidFormat("key_id")
  }
  guard fields.get("public_key") is Some(@json.Json::String(public_key_hex)) else {
    raise @crypto.CryptoError::InvalidFormat("public_key")
  }
  guard fields.get("payload_length") is Some(@json.Json::String(len_str)) else {
    raise @crypto.CryptoError::InvalidFormat("payload_length")
  }
  guard fields.get("payload_sha256") is Some(@json.Json::String(payload_sha256)) else {
    raise @crypto.CryptoError::InvalidFormat("payload_sha256")
  }
  guard fields.get("signature") is Some(@json.Json::String(signature_hex)) else {
    raise @crypto.CryptoError::InvalidFormat("signature")
  }
  let payload_length = parse_nonneg_decimal_str(len_str) catch {
    _ => raise @crypto.CryptoError::InvalidFormat("payload_length")
  }
  {
    algorithm,
    key_id,
    public_key_hex,
    payload_length,
    payload_sha256,
    signature_hex,
  }
}

///|
fn verify_quorum_bytes_impl(
  signatures_json : String,
  keyring_json : String,
  payload : Bytes,
) -> String raise {
  let trimmed = trim_ascii_whitespace(signatures_json)
  let bundle = if trimmed.has_prefix("[") {
    let raw_bytes = @utf8.encode(trimmed)
    guard raw_bytes.length() <= 131072 else {
      raise @crypto.CryptoError::LimitExceeded("signature_bundle_json_bytes")
    }
    let parsed = @json.parse(
      trimmed,
      max_nesting_depth=4,
      reject_duplicate_keys=true,
      preserve_number_repr=true,
    ) catch {
      @json.ParseError::DepthLimitExceeded =>
        raise @crypto.CryptoError::LimitExceeded("signature_bundle_json_depth")
      _ => raise @crypto.CryptoError::InvalidFormat("json")
    }
    guard parsed is @json.Json::Array(items) else {
      raise @crypto.CryptoError::InvalidFormat("signatures")
    }
    guard items.length() >= 1 && items.length() <= 64 else {
      raise @crypto.CryptoError::InvalidOptions("signature_count")
    }
    let sigs : Array[@crypto.PublisherSignature] = Array(
      capacity=items.length(),
    )
    for item in items {
      match item {
        @json.Json::String(sig_str) =>
          sigs.push(@crypto.parse_publisher_signature(@utf8.encode(sig_str)))
        @json.Json::Object(fields) => sigs.push(parse_sig_json_object(fields))
        _ => raise @crypto.CryptoError::InvalidFormat("signatures")
      }
    }
    @crypto.create_signature_bundle(sigs)
  } else {
    @crypto.parse_signature_bundle(@utf8.encode(signatures_json))
  }
  let keyring = @crypto.parse_trust_keyring(@utf8.encode(keyring_json))
  let report = @crypto.verify_quorum_bytes(bundle, keyring, payload)
  let bundle_raw = @crypto.encode_signature_bundle(bundle)
  let bundle_str = @utf8.decode(bundle_raw) catch {
    _ => raise @crypto.CryptoError::InvalidFormat("utf8")
  }
  let bundle_escaped = json_escape_str(bundle_str)
  let verified_json = json_string_array(report.verified_key_ids)
  let rejected_json = json_string_array(report.rejected_key_ids)
  let revoked_json = json_string_array(report.revoked_hits)
  "{\"ok\":true,\"bundle_json\":\"\{bundle_escaped}\",\"verified_key_ids\":\{verified_json},\"rejected_key_ids\":\{rejected_json},\"revoked_hits\":\{revoked_json},\"required_quorum\":\{report.required_quorum}}"
}

///|
/// Verify an M-of-N Ed25519 quorum from either a Schema 4 `SignatureBundle`
/// JSON string or a JSON array of `PublisherSignature` JSON strings/objects
/// against a Schema 4 `TrustKeyring` JSON and raw `payload` bytes.
pub fn verify_quorum_bytes_json(
  signatures_json : String,
  keyring_json : String,
  payload : Bytes,
) -> String {
  verify_quorum_bytes_impl(signatures_json, keyring_json, payload) catch {
    err => err_json(err)
  }
}
