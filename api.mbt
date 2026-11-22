// SPDX-License-Identifier: LGPL-2.1-or-later

// Core librsync-compatible byte-buffer operations: signature, delta and patch.
// Inspection, prepared signatures, integrity manifests, auto block sizing and
// transfer planning are defined in their respective modules.

///|
/// Options for the standard RK+BLAKE2 signature profile. Zero never means auto.
pub(all) struct SignatureOptions {
  block_len : Int64
  strong_sum_len : Int64
}

///|
/// Default signature block size 2048; prefix of BLAKE2b-256 of length 32.
pub fn SignatureOptions::default() -> SignatureOptions {
  { block_len: 2048L, strong_sum_len: 32L, }
}

///|
/// Supported modern librsync BLAKE2 signature profiles.
pub(all) enum SignatureProfile {
  /// RS_RK_BLAKE2_SIG_MAGIC (`0x72730147`, Rabin-Karp + BLAKE2b, default).
  RkBlake2
  /// RS_BLAKE2_SIG_MAGIC (`0x72730137`, Adler-style Rollsum + BLAKE2b).
  RollsumBlake2
}

///|
/// Wire magic value for a supported `SignatureProfile`.
pub fn SignatureProfile::magic(self : SignatureProfile) -> UInt32 {
  match self {
    RkBlake2 => 0x72730147U
    RollsumBlake2 => 0x72730137U
  }
}

///|
/// Generate signature bytes for either `RkBlake2` (`0x72730147`) or
/// `RollsumBlake2` (`0x72730137`), validating limits and options before hashing.
pub fn signature_with_profile(
  basis : Bytes,
  options : SignatureOptions,
  profile : SignatureProfile,
  limits : Limits,
) -> Bytes raise SyncError {
  let (block, strong, count, size) = signature_plan(
    basis.length().to_uint64(),
    options,
    limits,
  )
  let output = signature_header_with_magic(profile.magic(), block, strong, size)
  let mut pos = 0
  let mut cursor = 12L
  for _ in 0..<count {
    let remaining = basis.length() - pos
    let take = if remaining < block { remaining } else { block }
    let end = pos + take // take <= remaining; addition is now bounded.
    let window = basis[pos:end]
    let weak = match profile {
      RkBlake2 => rabinkarp_digest(window)
      RollsumBlake2 => rollsum_digest(window)
    }
    write_signature_record(output, cursor, weak, strong_sum(window, strong))
    pos = end
    cursor = cursor + (4 + strong).to_int64()
  }
  Bytes::from_array(output[:])
}

///|
/// Generate standard 0x72730147 signature bytes, not a delta or file recovery.
/// Validates limits, options, basis and output budgets before hashing/allocation.
/// Empty basis emits only the 12-byte header; the final short block is unpadded.
/// Full-buffer API: input is already allocated; final Bytes conversion may copy
/// the output buffer. These limits are not a process-wide peak-memory bound.
pub fn signature(
  basis : Bytes,
  options : SignatureOptions,
  limits : Limits,
) -> Bytes raise SyncError {
  signature_with_profile(basis, options, RkBlake2, limits)
}

///|
/// Generate a rollback delta (`NEW -> OLD`) that reverts `new_bytes` back to
/// `old_bytes` when passed to `patch(new_bytes, rev_delta, limits)`.
pub fn create_reverse_delta(
  old_bytes : Bytes,
  new_bytes : Bytes,
  options : SignatureOptions,
  limits : Limits,
) -> Bytes raise SyncError {
  let new_sig = signature(new_bytes, options, limits)
  delta(new_sig, old_bytes, limits)
}

///|
/// Generate a rollback delta (`NEW -> OLD`) using policy-v1 auto block sizing
/// (`recommend_block_len` with 16-byte BLAKE2b strong digests).
pub fn create_reverse_delta_auto(
  old_bytes : Bytes,
  new_bytes : Bytes,
  limits : Limits,
) -> Bytes raise SyncError {
  let block_len = recommend_block_len(
    new_bytes.length().to_int64(),
    16L,
    limits,
  )
  create_reverse_delta(
    old_bytes,
    new_bytes,
    { block_len, strong_sum_len: 16L, },
    limits,
  )
}

///|
/// Apply a standard librsync delta to the original basis; no signature needed.
/// Validates Limits, basis budget, the complete delta, then every COPY span and
/// final output size before allocating recovery bytes. Failure returns no output.
/// Requires END with no trailing data. Delta does not authenticate basis identity;
/// applications must verify whole-file content outside this standard format.
/// Parsed commands and input views can coexist with recovery/output buffers;
/// see docs/resources.md. Matching work is not charged by patch.
pub fn patch(
  basis : Bytes,
  delta_bytes : Bytes,
  limits : Limits,
) -> Bytes raise SyncError {
  apply_patch_bytes(basis, delta_bytes, limits)
}

///|
/// Generate a standard delta using only the remote signature and new bytes.
/// Validates the signature even for empty new input. One work budget covers
/// indexing, rolling scan, candidate confirmation and instruction accumulation.
/// COPY uses confirmed checksum prefixes, not basis identity authentication;
/// callers must check final content outside the standard format.
/// Command capacity allocation and live-slot relocation are precharged before
/// reserve/push. Parsed digest copies, index arrays, views and final conversion
/// storage coexist; see docs/resources.md, not a constant-memory promise.
pub fn delta(
  signature_bytes : Bytes,
  new_bytes : Bytes,
  limits : Limits,
) -> Bytes raise SyncError {
  generate_remote_delta(signature_bytes, new_bytes, limits)
}
