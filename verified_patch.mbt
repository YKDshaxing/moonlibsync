// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Recover bytes only after basis, delta and result match a trusted manifest.
/// Revalidates public descriptors; signature is metadata only (no SIG input).
/// Parses once and shares the ordinary patch copier. Full-buffer operation;
/// SHA-256 integrity does not authenticate the manifest's publisher.
pub fn verified_patch(
  basis : Bytes,
  delta_bytes : Bytes,
  manifest : UpdateManifest,
  limits : Limits,
) -> Bytes raise ManifestError {
  manifest_limits(limits)
  validate_update_manifest(manifest, limits)
  guard basis.length().to_int64() <= limits.max_old_bytes &&
    delta_bytes.length().to_int64() <= limits.max_delta_bytes else {
    raise ManifestError::Core(LimitExceeded)
  }
  guard basis.length().to_int64() == manifest.basis.byte_length else {
    raise ManifestError::BindingMismatch("basis_length")
  }
  guard delta_bytes.length().to_int64() == manifest.delta.byte_length else {
    raise ManifestError::BindingMismatch("delta_length")
  }
  guard manifest_sha256(basis, limits.max_old_bytes) == manifest.basis.sha256 else {
    raise ManifestError::BindingMismatch("basis_sha256")
  }
  guard manifest_sha256(delta_bytes, limits.max_delta_bytes) ==
    manifest.delta.sha256 else {
    raise ManifestError::BindingMismatch("delta_sha256")
  }
  let (commands, size) = try {
    let commands = parse_delta(delta_bytes, limits)
    let size = patch_size(basis.length().to_uint64(), commands, limits)
    (commands, size)
  } catch {
    error => raise ManifestError::Core(error)
  }
  // This guard precedes the only recovery-buffer allocation in the shared copier.
  guard size.to_int64() == manifest.result.byte_length else {
    raise ManifestError::BindingMismatch("result_length")
  }
  let result = execute_patch_commands(basis, commands, size)
  guard result.length().to_int64() == manifest.result.byte_length else {
    raise ManifestError::BindingMismatch("result_length")
  }
  guard manifest_sha256(result, limits.max_output_bytes) ==
    manifest.result.sha256 else {
    raise ManifestError::BindingMismatch("result_sha256")
  }
  result
}
