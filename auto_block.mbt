// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Explicit policy v1: approximately 512 records, preferred minimum 64,
/// round upward to a power of two, then cap at the current block limit.
/// Metadata-only integer calculation; never reads/hashes basis or builds an index.
/// Validates all Limits, basis length, strong length, old budget, then header.
/// Default SignatureOptions and signature behavior are unchanged. Not an optimum.
pub fn recommend_block_len(
  basis_len : Int64,
  strong_sum_len : Int64,
  limits : Limits,
) -> Int64 raise SyncError {
  limits.validate()
  guard basis_len >= 0L else { raise InvalidOptions("basis_len") }
  guard strong_sum_len >= 1L && strong_sum_len <= 32L else {
    raise InvalidOptions("strong_sum_len")
  }
  guard basis_len <= limits.max_old_bytes else { raise LimitExceeded }
  guard limits.max_signature_bytes >= 12L else { raise LimitExceeded }
  let block = if basis_len == 0L {
    if limits.max_block_bytes < 2048L {
      limits.max_block_bytes
    } else {
      2048L
    }
  } else {
    // Width 5..36; subtraction is guarded. Both caps are nonnegative Int32.
    let by_bytes = (limits.max_signature_bytes - 12L) / (4L + strong_sum_len)
    let allowed = if by_bytes < limits.max_signature_records {
      by_bytes
    } else {
      limits.max_signature_records
    }
    guard allowed > 0L else { raise LimitExceeded }
    // n <= Int32.MAX after old-budget validation. Quotient + remainder avoids
    // n + divisor - 1; for positive divisors each rounded quotient is <= n.
    let required = basis_len / allowed +
      (if basis_len % allowed == 0L { 0L } else { 1L })
    guard required <= limits.max_block_bytes else { raise LimitExceeded }
    let target = basis_len / 512L +
      (if basis_len % 512L == 0L { 0L } else { 1L })
    let mut preferred = if target > 64L { target } else { 64L }
    if required > preferred {
      preferred = required
    }
    let mut rounded = 1L
    // preferred <= max(64, Int32.MAX); at most 31 doublings, never above 2^31.
    // Int64 deliberately retains that last power before capping/narrowing.
    while rounded < preferred {
      rounded = rounded * 2L
    }
    if rounded > limits.max_block_bytes {
      limits.max_block_bytes
    } else {
      rounded
    }
  }
  let _ = signature_plan(
    basis_len.reinterpret_as_uint64(),
    { block_len: block, strong_sum_len, },
    limits,
  )
  block
}
