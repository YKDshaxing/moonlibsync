// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Schema 2 only. Delta reuses schema-1 descriptor data, but encodes `payload`.
/// Public data is not a verified credential; every consumer revalidates it.
pub(all) enum TransferManifest {
  Delta(UpdateManifest)
  Full(FileDigest, FileDigest)
}

///|
fn validate_transfer(
  value : TransferManifest,
  limits : Limits,
) -> Unit raise ManifestError {
  match value {
    Delta(m) => validate_update_manifest(m, limits)
    Full(payload, result) => {
      validate_file_digest(payload, 0L, limits.max_new_bytes, "payload")
      validate_file_digest(result, 0L, limits.max_output_bytes, "result")
      guard payload.byte_length == result.byte_length else {
        raise ManifestError::BindingMismatch("result_length")
      }
      guard payload.sha256 == result.sha256 else {
        raise ManifestError::BindingMismatch("result_sha256")
      }
    }
  }
}

///|
/// Sender has INFO, SIG, NEW and an existing candidate, never OLD. Validate
/// every candidate input even if Full wins; creation does not prove recovery.
pub fn create_transfer_manifest(
  info : BasisInfo,
  sig : Bytes,
  new : Bytes,
  candidate : Bytes,
  options : UpdateOptions,
  limits : Limits,
) -> TransferManifest raise ManifestError {
  manifest_limits(limits)
  update_options(options) catch {
    e => raise ManifestError::Core(e)
  }
  let m = create_update_manifest(info, sig, new, candidate, limits)
  let decision = update_decision(
    new.length().to_int64(),
    candidate.length().to_int64(),
    options,
  )
  if decision.kind == "librsync-delta" {
    Delta(m)
  } else {
    Full(m.result, m.result)
  }
}

///|
/// Separate schema-2 parser; same bounded strict JSON front end as schema 1.
pub fn parse_transfer_manifest(
  input : Bytes,
  limits : Limits,
) -> TransferManifest raise ManifestError {
  let tree = manifest_tree(input, limits)
  guard tree is @json.Json::Object(fields) else {
    raise ManifestError::InvalidSchema
  }
  guard manifest_get(fields, "schema_version")
    is @json.Json::Number(2.0, repr=Some("2")) else {
    raise ManifestError::InvalidSchema
  }
  let kind = manifest_string(manifest_get(fields, "kind"), "kind")
  let value = if kind == "librsync-delta" {
    let f = manifest_object(tree, [
      "schema_version", "kind", "basis", "signature", "payload", "result",
    ])
    TransferManifest::Delta({
      basis: parse_file_digest(manifest_get(f, "basis")),
      signature: parse_file_digest(manifest_get(f, "signature")),
      delta: parse_file_digest(manifest_get(f, "payload")),
      result: parse_file_digest(manifest_get(f, "result")),
    })
  } else if kind == "full-file" {
    let f = manifest_object(tree, [
      "schema_version", "kind", "payload", "result",
    ])
    TransferManifest::Full(
      parse_file_digest(manifest_get(f, "payload")),
      parse_file_digest(manifest_get(f, "result")),
    )
  } else {
    raise ManifestError::InvalidSchema
  }
  validate_transfer(value, limits)
  value
}

///|
/// Fixed field order, UTF-8 without BOM plus LF; revalidate public data.
pub fn encode_transfer_manifest(
  value : TransferManifest,
  limits : Limits,
) -> Bytes raise ManifestError {
  manifest_limits(limits)
  validate_transfer(value, limits)
  let text = match value {
    Delta(m) =>
      "{\"schema_version\":2,\"kind\":\"librsync-delta\",\"basis\":\{file_digest_json(m.basis)},\"signature\":\{file_digest_json(m.signature)},\"payload\":\{file_digest_json(m.delta)},\"result\":\{file_digest_json(m.result)}}\n"
    Full(p, r) =>
      "{\"schema_version\":2,\"kind\":\"full-file\",\"payload\":\{file_digest_json(p)},\"result\":\{file_digest_json(r)}}\n"
  }
  @utf8.encode(text)
}

///|
/// Limits -> descriptor validation -> branch-specific checks. Delta requires
/// basis and reuses verified_patch's hash/preflight/copier/result validation.
/// Full never inspects basis, never parses delta, and uses new/output budgets.
pub fn apply_update(
  basis : Bytes?,
  payload : Bytes,
  manifest : TransferManifest,
  limits : Limits,
) -> Bytes raise ManifestError {
  manifest_limits(limits)
  validate_transfer(manifest, limits)
  match manifest {
    Delta(m) => {
      guard basis is Some(old) else {
        raise ManifestError::InvalidField("basis")
      }
      verified_patch(old, payload, m, limits)
    }
    Full(p, _) => {
      guard payload.length().to_int64() <= limits.max_new_bytes &&
        payload.length().to_int64() <= limits.max_output_bytes else {
        raise ManifestError::Core(LimitExceeded)
      }
      guard payload.length().to_int64() == p.byte_length else {
        raise ManifestError::BindingMismatch("payload_length")
      }
      guard manifest_sha256(payload, limits.max_new_bytes) == p.sha256 else {
        raise ManifestError::BindingMismatch("payload_sha256")
      }
      payload
    }
  }
}
