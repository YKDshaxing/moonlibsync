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
    if is_literal {
      cursor = cursor + length.to_int()
    }
    if emitted > 0 {
      items.write_char(',')
    }
    let kind = if is_literal { "literal" } else { "copy" }
    items.write_string(
      "{\"kind\":\"\{kind}\",\"offset\":\"\{offset}\",\"length\":\"\{length}\",\"output_offset\":\"\{output_offset}\"}",
    )
    output_offset = output_offset + length
    emitted = emitted + 1
  }
  "{\"ok\":true,\"summary\":\{delta_summary_json(summary)},\"truncated\":\{truncated},\"items\":[\{items.to_string()}]}"
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
fn is_schema12_tree_limit(err : Error) -> Bool {
  match err {
    @lib.ManifestError::ResourceLimit("manifest_depth")
    | @lib.ManifestError::ResourceLimit("manifest_fields")
    | @lib.ManifestError::ResourceLimit("manifest_bytes") => true
    _ => false
  }
}

///|
fn inspect_artifact_impl(data : Bytes) -> String raise {
  let limits = @lib.Limits::default()
  let dir_limits = @lib.DirLimits::default()
  if data.length() >= 4 &&
    data[0] == b'\x72' &&
    data[1] == b'\x73' &&
    data[2] == b'\x01' &&
    data[3] == b'\x47' {
    let s = @lib.inspect_signature(data, limits)
    return "{\"ok\":true,\"artifact_kind\":\"signature\",\"summary\":{\"magic\":\"0x72730147\",\"block_len\":\"\{s.block_len}\",\"strong_sum_len\":\"\{s.strong_sum_len}\",\"record_count\":\"\{s.record_count}\",\"signature_bytes\":\"\{s.signature_bytes}\"}}"
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
    return "{\"ok\":true,\"artifact_kind\":\"bundle-archive\",\"archive_bytes\":\"\{data.length()}\",\"summary\":{\"unchanged\":\"\{m.unchanged_count}\",\"add_full\":\"\{m.add_full_count}\",\"update_delta\":\"\{m.update_delta_count}\",\"update_full\":\"\{m.update_full_count}\",\"delete\":\"\{m.delete_count}\",\"total_payload_bytes\":\"\{m.total_payload_bytes}\"}}"
  }

  let mut specific_err : Error? = None
  try {
    let tm = @lib.parse_transfer_manifest(data, limits)
    match tm {
      Delta(m) =>
        return "{\"ok\":true,\"artifact_kind\":\"librsync-delta\",\"schema_version\":2,\"summary\":{\"mode\":\"delta\",\"basis_bytes\":\"\{m.basis.byte_length}\",\"signature_bytes\":\"\{m.signature.byte_length}\",\"payload_bytes\":\"\{m.delta.byte_length}\",\"result_bytes\":\"\{m.result.byte_length}\",\"result_sha256\":\"\{m.result.sha256}\"}}"
      Full(p, r) =>
        return "{\"ok\":true,\"artifact_kind\":\"full-file\",\"schema_version\":2,\"summary\":{\"mode\":\"full\",\"payload_bytes\":\"\{p.byte_length}\",\"result_bytes\":\"\{r.byte_length}\",\"result_sha256\":\"\{r.sha256}\"}}"
    }
  } catch {
    err =>
      if !is_generic_json_mismatch(err) && !is_schema12_tree_limit(err) {
        specific_err = Some(err)
      }
  }
  try {
    let um = @lib.parse_update_manifest(data, limits)
    return "{\"ok\":true,\"artifact_kind\":\"librsync-delta\",\"schema_version\":1,\"summary\":{\"basis_bytes\":\"\{um.basis.byte_length}\",\"signature_bytes\":\"\{um.signature.byte_length}\",\"delta_bytes\":\"\{um.delta.byte_length}\",\"result_bytes\":\"\{um.result.byte_length}\",\"result_sha256\":\"\{um.result.sha256}\"}}"
  } catch {
    err =>
      if !is_generic_json_mismatch(err) && !is_schema12_tree_limit(err) {
        specific_err = Some(err)
      }
  }
  try {
    let bi = @lib.parse_basis_info(data, limits)
    return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-basis-info\",\"schema_version\":1,\"summary\":{\"basis_bytes\":\"\{bi.basis.byte_length}\",\"basis_sha256\":\"\{bi.basis.sha256}\",\"signature_bytes\":\"\{bi.signature.byte_length}\",\"signature_sha256\":\"\{bi.signature.sha256}\"}}"
  } catch {
    err =>
      if !is_generic_json_mismatch(err) && !is_schema12_tree_limit(err) {
        specific_err = Some(err)
      }
  }
  try {
    let snap = @lib.parse_dir_snapshot(data, dir_limits)
    let mut total_bytes = 0UL
    for e in snap.entries {
      total_bytes = total_bytes + e.digest.byte_length.reinterpret_as_uint64()
    }
    return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-dir-snapshot\",\"schema_version\":3,\"summary\":{\"entries\":\"\{snap.entries.length()}\",\"total_bytes\":\"\{total_bytes}\"}}"
  } catch {
    err => if !is_generic_json_mismatch(err) { specific_err = Some(err) }
  }
  try {
    let plan = @lib.parse_dir_plan(data, dir_limits)
    return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-dir-plan\",\"schema_version\":3,\"summary\":{\"unchanged\":\"\{plan.unchanged_count}\",\"add\":\"\{plan.add_count}\",\"update\":\"\{plan.update_count}\",\"delete\":\"\{plan.delete_count}\",\"transfer_upper_bound_bytes\":\"\{plan.transfer_upper_bound_bytes}\"}}"
  } catch {
    err => if !is_generic_json_mismatch(err) { specific_err = Some(err) }
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
    err => if !is_generic_json_mismatch(err) { specific_err = Some(err) }
  }
  try {
    let b = @lib.parse_dir_bundle_manifest(data, dir_limits, limits)
    return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-dir-bundle\",\"schema_version\":3,\"summary\":{\"unchanged\":\"\{b.unchanged_count}\",\"add_full\":\"\{b.add_full_count}\",\"update_delta\":\"\{b.update_delta_count}\",\"update_full\":\"\{b.update_full_count}\",\"delete\":\"\{b.delete_count}\",\"total_payload_bytes\":\"\{b.total_payload_bytes}\"}}"
  } catch {
    err => if !is_generic_json_mismatch(err) { specific_err = Some(err) }
  }
  try {
    let r = @lib.parse_dir_verify_report(data, dir_limits)
    return "{\"ok\":true,\"artifact_kind\":\"moonlibsync-dir-verify\",\"schema_version\":3,\"summary\":{\"ok\":\{r.ok},\"matched\":\"\{r.matched_count}\",\"modified\":\"\{r.modified_count}\",\"missing\":\"\{r.missing_count}\",\"extra\":\"\{r.extra_count}\"}}"
  } catch {
    err => if !is_generic_json_mismatch(err) { specific_err = Some(err) }
  }

  match specific_err {
    Some(err) => "{\"ok\":false,\"error\":\"\{sync_err_label(err)}\"}"
    None => "{\"ok\":false,\"error\":\"UnsupportedArtifact\"}"
  }
}

///|
/// Auto-detect and validate any MoonLibSync binary artifact (.sig, .delta, .gz,
/// .mbundle) or Schema 1/2/3 JSON document and return structured summary JSON.
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
  let is_gz = delta_or_gz.length() >= 2 &&
    delta_or_gz[0] == b'\x1f' &&
    delta_or_gz[1] == b'\x8b'
  let payload = if is_gz {
    @compress.decompress_gzip(
      delta_or_gz[:],
      limits.max_delta_bytes,
      limits.max_delta_bytes,
    )
  } else {
    delta_or_gz
  }
  let trimmed = trim_ascii_whitespace(manifest_json)
  let (restored, verified_manifest) = if trimmed.length() > 0 {
    let m_bytes = @utf8.encode(trimmed)
    let mut parsed_tm : @lib.TransferManifest? = None
    let mut tm_err : Error? = None
    try {
      parsed_tm = Some(@lib.parse_transfer_manifest(m_bytes, limits))
    } catch {
      err => tm_err = Some(err)
    }
    match parsed_tm {
      Some(tm) =>
        (@lib.apply_update(Some(old_bytes), payload, tm, limits), true)
      None => {
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
