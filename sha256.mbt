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

///|
/// Incremental bounded SHA-256 hasher for streaming integrity verification.
/// Keeps O(1) internal hash state; rejects overflow, budget exceedance, and reuse
/// after `finish()` or failure.
pub struct Sha256Hasher {
  priv hasher : @sha2.Hasher
  priv max_bytes : UInt64
  priv mut total_bytes : UInt64
  priv mut finished : Bool
  priv mut failed : Bool
}

///|
/// Create a streaming SHA-256 hasher bounded by `0 <= max_bytes <= 2^31 - 1`.
pub fn Sha256Hasher::new(max_bytes : Int64) -> Sha256Hasher raise ManifestError {
  guard max_bytes >= 0L && max_bytes <= 2147483647L else {
    raise ManifestError::Core(InvalidOptions("sha256_max_bytes"))
  }
  {
    hasher: @sha2.Hasher::new(kind=@sha2.Kind::Sha256),
    max_bytes: max_bytes.reinterpret_as_uint64(),
    total_bytes: 0UL,
    finished: false,
    failed: false,
  }
}

///|
/// Feed incremental bytes into the SHA-256 hasher after strict budget checks.
/// Any error permanently transitions the hasher to failed state.
pub fn Sha256Hasher::update(
  self : Sha256Hasher,
  chunk : BytesView,
) -> Unit raise ManifestError {
  guard !self.finished else {
    raise ManifestError::Core(InvalidOptions("stream_finished"))
  }
  guard !self.failed else {
    raise ManifestError::Core(InvalidOptions("stream_failed"))
  }
  errdefer {
    self.failed = true
  }
  let incoming = chunk.length().to_uint64()
  guard incoming <= 0xffffffffffffffffUL - self.total_bytes else {
    raise ManifestError::Core(IntegerOutOfRange)
  }
  let next_total = self.total_bytes + incoming
  guard next_total <= self.max_bytes else {
    raise ManifestError::ResourceLimit("sha256_input")
  }
  if chunk.length() > 0 {
    self.hasher.write(chunk)
  }
  self.total_bytes = next_total
}

///|
/// Finalize the SHA-256 stream and return the verified `FileDigest`.
pub fn Sha256Hasher::finish(
  self : Sha256Hasher,
) -> FileDigest raise ManifestError {
  guard !self.finished else {
    raise ManifestError::Core(InvalidOptions("stream_finished"))
  }
  guard !self.failed else {
    raise ManifestError::Core(InvalidOptions("stream_failed"))
  }
  errdefer {
    self.failed = true
  }
  let digest = self.hasher.finish()
  guard digest.length() == 32 else { raise ManifestError::HashFailure }
  self.finished = true
  {
    byte_length: self.total_bytes.reinterpret_as_int64(),
    sha256: @hex.encode(digest),
  }
}
