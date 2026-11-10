// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn manifest_error_tag(error : Error) -> String {
  match error {
    @lib.ManifestError::Core(core) => "Core:" + core_error_tag(core)
    @lib.ManifestError::BindingMismatch(field) => "BindingMismatch:" + field
    @lib.ManifestError::InvalidField(field) => "InvalidField:" + field
    @lib.ManifestError::ResourceLimit(field) => "ResourceLimit:" + field
    @lib.ManifestError::InvalidUtf8 => "InvalidUtf8"
    @lib.ManifestError::InvalidJson => "InvalidJson"
    @lib.ManifestError::InvalidSchema => "InvalidSchema"
    @lib.ManifestError::HashFailure => "HashFailure"
    _ => cli_error_text(error)
  }
}

///|
/// Preparing a path is read-only. No temporary is created until verification ends.
async fn execute_manifest_write(
  plan : Plan,
  output_path : String,
  publisher~ : async (String, Bytes) -> Unit = publish_output,
) -> Unit {
  try {
    let limits = @lib.Limits::default()
    let output = prepare_output(output_path)
    let p = plan.inputs
    let data = match plan.operation {
      "basis-info" => {
        let old = bounded_read(p[0], limits.max_old_bytes)
        let sig = bounded_read(p[1], limits.max_signature_bytes)
        @lib.encode_basis_info(@lib.create_basis_info(old, sig, limits), limits)
      }
      "make-manifest" => {
        let info = @lib.parse_basis_info(bounded_read(p[0], 65536L), limits)
        let sig = bounded_read(p[1], limits.max_signature_bytes)
        let new = bounded_read(p[2], limits.max_new_bytes)
        let delta = bounded_read(p[3], limits.max_delta_bytes)
        @lib.encode_update_manifest(
          @lib.create_update_manifest(info, sig, new, delta, limits),
          limits,
        )
      }
      _ => {
        let old = bounded_read(p[0], limits.max_old_bytes)
        let delta = bounded_read(p[1], limits.max_delta_bytes)
        let manifest = @lib.parse_update_manifest(
          bounded_read(p[2], 65536L),
          limits,
        )
        @lib.verified_patch(old, delta, manifest, limits)
      }
    }
    publisher(output, data)
  } catch {
    error =>
      raise FileFailure(
        plan.operation +
        " inputs [" +
        plan.inputs.join(", ") +
        "] output '" +
        output_path +
        "': " +
        manifest_error_tag(error),
      )
  }
}
