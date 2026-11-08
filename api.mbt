// SPDX-License-Identifier: LGPL-2.1-or-later

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
/// Generate standard 0x72730147 signature bytes, not a delta or file recovery.
/// Validates limits, options, basis and output budgets before hashing/allocation.
/// Empty basis emits only the 12-byte header; the final short block is unpadded.
pub fn signature(
  basis : Bytes,
  options : SignatureOptions,
  limits : Limits,
) -> Bytes raise SyncError {
  let (block, strong, count, size) = signature_plan(
    basis.length().to_uint64(),
    options,
    limits,
  )
  let output = signature_header(block, strong, size)
  let mut pos = 0
  let mut cursor = 12L
  for _ in 0..<count {
    let remaining = basis.length() - pos
    let take = if remaining < block { remaining } else { block }
    let end = pos + take // take <= remaining; addition is now bounded.
    let window = basis[pos:end]
    let weak = RabinKarp::new()
    weak.update(window)
    write_signature_record(
      output,
      cursor,
      weak.digest(),
      strong_sum(window, strong),
    )
    pos = end
    cursor = cursor + (4 + strong).to_int64()
  }
  Bytes::from_array(output[:])
}

///|
/// Apply a standard librsync delta to the original basis; no signature needed.
/// Validates Limits, basis budget, the complete delta, then every COPY span and
/// final output size before allocating recovery bytes. Failure returns no output.
/// Requires END with no trailing data. Delta does not authenticate basis identity;
/// applications must verify whole-file content outside this standard format.
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
pub fn delta(
  signature_bytes : Bytes,
  new_bytes : Bytes,
  limits : Limits,
) -> Bytes raise SyncError {
  generate_remote_delta(signature_bytes, new_bytes, limits)
}
