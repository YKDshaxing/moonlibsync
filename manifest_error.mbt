// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Manifest-specific errors, without exposing JSON/UTF-8 dependency types.
/// Core preserves the original SyncError unchanged. ResourceLimit names the
/// fixed parser bound or the applicable byte budget; no old enum is extended.
pub(all) suberror ManifestError {
  Core(SyncError)
  InvalidUtf8
  InvalidJson
  InvalidSchema
  InvalidField(String)
  BindingMismatch(String)
  ResourceLimit(String)
  HashFailure
}
