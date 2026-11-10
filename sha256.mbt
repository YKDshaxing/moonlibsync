// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Always SHA-256 (not SHA-512/256 or BLAKE2), with preflight before hashing.
/// Fresh dependency state; hash work is not charged to matching work units.
fn manifest_sha256(
  input : BytesView,
  maximum : Int64,
) -> String raise ManifestError {
  guard maximum >= 0L && input.length().to_int64() <= maximum else {
    raise ManifestError::ResourceLimit("sha256_input")
  }
  let digest = @sha2.hash(input, kind=@sha2.Kind::Sha256)
  guard digest.length() == 32 else { raise ManifestError::HashFailure }
  @hex.encode(digest)
}
