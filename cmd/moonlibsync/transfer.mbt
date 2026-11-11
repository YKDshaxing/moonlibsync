// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Only prepare a path before validation. The injected publisher is called
/// after all verification, sharing the original no-overwrite transaction.
async fn execute_transfer_write(
  plan : Plan,
  output_path : String,
  publisher~ : async (String, Bytes) -> Unit = publish_output,
) -> Unit {
  try {
    let limits = @lib.Limits::default()
    limits.validate()
    let output = prepare_output(output_path)
    let p = plan.inputs
    let data = if plan.operation == "make-transfer-manifest" {
      let info = @lib.parse_basis_info(bounded_read(p[0], 65536L), limits)
      let sig = bounded_read(p[1], limits.max_signature_bytes)
      let new = bounded_read(p[2], limits.max_new_bytes)
      let candidate = bounded_read(p[3], limits.max_delta_bytes)
      @lib.encode_transfer_manifest(
        @lib.create_transfer_manifest(
          info,
          sig,
          new,
          candidate,
          { min_savings_bytes: plan.min_savings, },
          limits,
        ),
        limits,
      )
    } else {
      let manifest = @lib.parse_transfer_manifest(
        bounded_read(p[1], 65536L),
        limits,
      )
      let cap = match manifest {
        @lib.TransferManifest::Delta(_) => limits.max_delta_bytes
        @lib.TransferManifest::Full(_, _) => limits.max_new_bytes
      }
      let basis = match manifest {
        @lib.TransferManifest::Delta(_) => {
          guard plan.basis_path is Some(path) else {
            raise Usage("Delta requires --basis OLD")
          }
          Some(bounded_read(path, limits.max_old_bytes))
        }
        @lib.TransferManifest::Full(_, _) => {
          guard plan.basis_path is None else {
            raise Usage("Full forbids --basis")
          }
          None
        }
      }
      let payload = bounded_read(p[0], cap)
      @lib.apply_update(basis, payload, manifest, limits)
    }
    publisher(output, data)
  } catch {
    Usage(message) => raise Usage(message)
    error =>
      raise FileFailure(plan.operation + ": " + manifest_error_tag(error))
  }
}
