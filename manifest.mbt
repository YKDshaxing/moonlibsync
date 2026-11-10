// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Data, not an authenticated credential. Every consumer/encoder revalidates.
pub(all) struct FileDigest {
  byte_length : Int64
  sha256 : String
}

///|
/// Schema 1, kind moonlibsync-basis-info. Does not carry paths or commands.
pub(all) struct BasisInfo {
  basis : FileDigest
  signature : FileDigest
}

///|
/// Schema 1, kind librsync-delta. Creation does not prove recovered content.
pub(all) struct UpdateManifest {
  basis : FileDigest
  signature : FileDigest
  delta : FileDigest
  result : FileDigest
}

///|
fn manifest_limits(limits : Limits) -> Unit raise ManifestError {
  limits.validate() catch {
    error => raise ManifestError::Core(error)
  }
}

///|
fn manifest_length(
  value : Int64,
  minimum : Int64,
  maximum : Int64,
  name : String,
) -> Unit raise ManifestError {
  guard value >= minimum else {
    raise ManifestError::InvalidField(name + ".byte_length")
  }
  guard value <= maximum else { raise ManifestError::ResourceLimit(name) }
}

///|
fn validate_file_digest(
  value : FileDigest,
  minimum : Int64,
  maximum : Int64,
  name : String,
) -> Unit raise ManifestError {
  manifest_length(value.byte_length, minimum, maximum, name)
  guard value.sha256.length() == 64 else {
    raise ManifestError::InvalidField(name + ".sha256")
  }
  for c in value.sha256 {
    guard (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') else {
      raise ManifestError::InvalidField(name + ".sha256")
    }
  }
}

///|
fn validate_basis_info(
  value : BasisInfo,
  limits : Limits,
) -> Unit raise ManifestError {
  validate_file_digest(value.basis, 0L, limits.max_old_bytes, "basis")
  validate_file_digest(
    value.signature,
    12L,
    limits.max_signature_bytes,
    "signature",
  )
}

///|
fn validate_update_manifest(
  value : UpdateManifest,
  limits : Limits,
) -> Unit raise ManifestError {
  validate_basis_info(
    { basis: value.basis, signature: value.signature, },
    limits,
  )
  validate_file_digest(value.delta, 5L, limits.max_delta_bytes, "delta")
  validate_file_digest(value.result, 0L, limits.max_output_bytes, "result")
}

///|
/// Exact Int64 decimal parse BEFORE narrowing or applying a byte budget.
fn manifest_decimal(text : String) -> Int64 raise ManifestError {
  guard text.length() > 0 && (text == "0" || !text.has_prefix("0")) else {
    raise ManifestError::InvalidField("byte_length")
  }
  let mut result = 0L
  for c in text {
    guard c >= '0' && c <= '9' else {
      raise ManifestError::InvalidField("byte_length")
    }
    let digit = (c.to_int() - 48).to_int64()
    guard result <= (9223372036854775807L - digit) / 10L else {
      raise ManifestError::InvalidField("byte_length")
    }
    result = result * 10L + digit
  }
  result
}

///|
/// Count object fields after JSON construction, not before each allocation.
/// Before this traversal, tree allocation is bounded by 64KiB and depth 2.
fn manifest_field_count(value : @json.Json) -> Int32 raise ManifestError {
  let mut count = 0
  match value {
    @json.Json::Object(fields) => {
      count = fields.length()
      guard count <= 16 else {
        raise ManifestError::ResourceLimit("manifest_fields")
      }
      for (_, child) in fields {
        count = count + manifest_field_count(child)
      }
    }
    @json.Json::Array(items) =>
      for child in items {
        count = count + manifest_field_count(child)
      }
    _ => ()
  }
  guard count <= 16 else {
    raise ManifestError::ResourceLimit("manifest_fields")
  }
  count
}

///|
fn manifest_tree(
  input : Bytes,
  limits : Limits,
) -> @json.Json raise ManifestError {
  manifest_limits(limits)
  guard input.length() <= 65536 else {
    raise ManifestError::ResourceLimit("manifest_bytes")
  }
  let text = @utf8.decode(input, ignore_bom=false) catch {
    _ => raise ManifestError::InvalidUtf8
  }
  // Strict UTF-8 decoding precedes the explicit no-BOM JSON policy.
  guard !(input.length() >= 3 &&
    input[0] == b'\xef' &&
    input[1] == b'\xbb' &&
    input[2] == b'\xbf') else {
    raise ManifestError::InvalidJson
  }
  let value = @json.parse(
    text,
    max_nesting_depth=2,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    @json.ParseError::DepthLimitExceeded =>
      raise ManifestError::ResourceLimit("manifest_depth")
    _ => raise ManifestError::InvalidJson
  }
  let _ = manifest_field_count(value)
  value
}

///|
fn manifest_object(
  value : @json.Json,
  keys : ArrayView[String],
) -> Map[String, @json.Json] raise ManifestError {
  guard value is @json.Json::Object(fields) else {
    raise ManifestError::InvalidSchema
  }
  guard fields.length() == keys.length() else {
    raise ManifestError::InvalidSchema
  }
  for key in keys {
    guard fields.contains(key) else { raise ManifestError::InvalidSchema }
  }
  fields
}

///|
fn manifest_get(
  fields : Map[String, @json.Json],
  key : String,
) -> @json.Json raise ManifestError {
  guard fields.get(key) is Some(value) else {
    raise ManifestError::InvalidSchema
  }
  value
}

///|
fn manifest_string(
  value : @json.Json,
  name : String,
) -> String raise ManifestError {
  guard value is @json.Json::String(text) else {
    raise ManifestError::InvalidField(name)
  }
  text
}

///|
fn manifest_header(
  fields : Map[String, @json.Json],
  kind : String,
) -> Unit raise ManifestError {
  guard manifest_get(fields, "schema_version")
    is @json.Json::Number(1.0, repr=Some("1")) else {
    raise ManifestError::InvalidSchema
  }
  guard manifest_get(fields, "kind") is @json.Json::String(actual) &&
    actual == kind else {
    raise ManifestError::InvalidSchema
  }
}

///|
fn parse_file_digest(value : @json.Json) -> FileDigest raise ManifestError {
  let fields = manifest_object(value, ["byte_length", "sha256"])
  {
    byte_length: manifest_decimal(
      manifest_string(manifest_get(fields, "byte_length"), "byte_length"),
    ),
    sha256: manifest_string(manifest_get(fields, "sha256"), "sha256"),
  }
}

///|
/// Limits -> 64KiB -> strict UTF-8/no BOM -> full duplicate-rejecting JSON,
/// container depth 2 -> <=16 total object fields -> schema/types/resources.
/// Declared lengths/hashes do not prove files exist or match these declarations.
pub fn parse_basis_info(
  input : Bytes,
  limits : Limits,
) -> BasisInfo raise ManifestError {
  let fields = manifest_object(manifest_tree(input, limits), [
    "schema_version", "kind", "basis", "signature",
  ])
  manifest_header(fields, "moonlibsync-basis-info")
  let value = {
    basis: parse_file_digest(manifest_get(fields, "basis")),
    signature: parse_file_digest(manifest_get(fields, "signature")),
  }
  validate_basis_info(value, limits)
  value
}

///|
/// Same strict parser policy as basis-info; result is data, not verified output.
pub fn parse_update_manifest(
  input : Bytes,
  limits : Limits,
) -> UpdateManifest raise ManifestError {
  let fields = manifest_object(manifest_tree(input, limits), [
    "schema_version", "kind", "basis", "signature", "delta", "result",
  ])
  manifest_header(fields, "librsync-delta")
  let value = {
    basis: parse_file_digest(manifest_get(fields, "basis")),
    signature: parse_file_digest(manifest_get(fields, "signature")),
    delta: parse_file_digest(manifest_get(fields, "delta")),
    result: parse_file_digest(manifest_get(fields, "result")),
  }
  validate_update_manifest(value, limits)
  value
}

///|
fn file_digest_json(value : FileDigest) -> String {
  "{\"byte_length\":\"\{value.byte_length}\",\"sha256\":\"\{value.sha256}\"}"
}

///|
/// Revalidate public data; fixed field order, ASCII-safe validated scalars,
/// UTF-8 without BOM plus LF. Not a general cryptographic JSON canonicalizer.
pub fn encode_basis_info(
  value : BasisInfo,
  limits : Limits,
) -> Bytes raise ManifestError {
  manifest_limits(limits)
  validate_basis_info(value, limits)
  @utf8.encode(
    "{\"schema_version\":1,\"kind\":\"moonlibsync-basis-info\",\"basis\":\{file_digest_json(value.basis)},\"signature\":\{file_digest_json(value.signature)}}\n",
  )
}

///|
/// Revalidate all four descriptors; same deterministic wire convention.
pub fn encode_update_manifest(
  value : UpdateManifest,
  limits : Limits,
) -> Bytes raise ManifestError {
  manifest_limits(limits)
  validate_update_manifest(value, limits)
  @utf8.encode(
    "{\"schema_version\":1,\"kind\":\"librsync-delta\",\"basis\":\{file_digest_json(value.basis)},\"signature\":\{file_digest_json(value.signature)},\"delta\":\{file_digest_json(value.delta)},\"result\":\{file_digest_json(value.result)}}\n",
  )
}

///|
/// Receiver: check sizes and complete SIG, regenerate OLD's signature using
/// SIG's parameters, compare all bytes, THEN hash OLD and SIG. No authentication.
pub fn create_basis_info(
  old : Bytes,
  sig : Bytes,
  limits : Limits,
) -> BasisInfo raise ManifestError {
  manifest_limits(limits)
  manifest_length(old.length().to_int64(), 0L, limits.max_old_bytes, "basis")
  let summary = inspect_signature(sig, limits) catch {
    error => raise ManifestError::Core(error)
  }
  let expected = signature(
    old,
    { block_len: summary.block_len, strong_sum_len: summary.strong_sum_len, },
    limits,
  ) catch {
    error => raise ManifestError::Core(error)
  }
  guard expected == sig else {
    raise ManifestError::BindingMismatch("basis_signature")
  }
  {
    basis: {
      byte_length: old.length().to_int64(),
      sha256: manifest_sha256(old, limits.max_old_bytes),
    },
    signature: {
      byte_length: sig.length().to_int64(),
      sha256: manifest_sha256(sig, limits.max_signature_bytes),
    },
  }
}

///|
/// Sender: NO OLD argument or lookup. Validate public basis-info and sizes,
/// inspect SIG, bind its exact bytes/SHA-256, fully preflight DELTA against the
/// declared basis length, and require its output length to equal NEW's length.
/// This cannot prove DELTA recovers NEW; trusted metadata and result checking
/// during application are separate responsibilities (Commit 22).
pub fn create_update_manifest(
  info : BasisInfo,
  sig : Bytes,
  new : Bytes,
  delta_bytes : Bytes,
  limits : Limits,
) -> UpdateManifest raise ManifestError {
  manifest_limits(limits)
  validate_basis_info(info, limits)
  manifest_length(
    sig.length().to_int64(),
    12L,
    limits.max_signature_bytes,
    "signature",
  )
  manifest_length(new.length().to_int64(), 0L, limits.max_new_bytes, "new")
  manifest_length(
    new.length().to_int64(),
    0L,
    limits.max_output_bytes,
    "result",
  )
  manifest_length(
    delta_bytes.length().to_int64(),
    5L,
    limits.max_delta_bytes,
    "delta",
  )
  guard sig.length().to_int64() == info.signature.byte_length else {
    raise ManifestError::BindingMismatch("signature_length")
  }
  let _ = inspect_signature(sig, limits) catch {
    error => raise ManifestError::Core(error)
  }
  let signature_hash = manifest_sha256(sig, limits.max_signature_bytes)
  guard signature_hash == info.signature.sha256 else {
    raise ManifestError::BindingMismatch("signature_sha256")
  }
  let checked = check_patch(info.basis.byte_length, delta_bytes, limits) catch {
    error => raise ManifestError::Core(error)
  }
  guard checked.summary.output_bytes == new.length().to_int64() else {
    raise ManifestError::BindingMismatch("result_length")
  }
  {
    basis: info.basis,
    signature: { byte_length: sig.length().to_int64(), sha256: signature_hash, },
    delta: {
      byte_length: delta_bytes.length().to_int64(),
      sha256: manifest_sha256(delta_bytes, limits.max_delta_bytes),
    },
    result: {
      byte_length: new.length().to_int64(),
      sha256: manifest_sha256(new, limits.max_output_bytes),
    },
  }
}
