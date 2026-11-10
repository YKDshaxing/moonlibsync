// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Opaque, owned signature and final index order; no basis, input view, sort
/// scratch array, work balance or scanning state is retained. Private arrays
/// are read-only after construction. This is not a thread-safety guarantee.
/// Development source only; each delta call has independent state and work.
pub struct PreparedSignature {
  priv signature_bytes : Int64
  priv index : SignatureIndex
}

///|
/// Validate and parse the complete RK+BLAKE2 signature, then build its stable
/// index with a fresh, preparation-only MatchWork. All Limits fields are
/// validated; applicable limits are signature bytes/records, block and work.
/// Parsing can allocate bounded records/digest copies before index work fails.
/// The result owns those records and the final ordinal array, without copying
/// digests again. No basis length or identity is inferred. Multiple live objects
/// retain separate storage; the original one-shot delta budget is unchanged.
pub fn prepare_signature(
  signature_bytes : Bytes,
  limits : Limits,
) -> PreparedSignature raise SyncError {
  limits.validate()
  let signature = parse_signature(signature_bytes, limits)
  let work = MatchWork::new(limits)
  let index = build_signature_index(signature, work)
  { signature_bytes: signature_bytes.length().to_int64(), index, }
}

///|
/// Reuse the owned index without parsing, sorting or copying it. Revalidate
/// current Limits, signature bytes, block, records, new bytes, output bytes and
/// the five-byte delta minimum, in that order. Each call owns one fresh shared
/// scan/match/command budget; preparation work is not charged again. Empty new
/// input still rechecks limits, but needs no scan work. No basis is available;
/// COPY confirms checksum prefixes, not file identity. Failures discard local
/// state and do not change the prepared object or previous returned Bytes.
pub fn PreparedSignature::delta(
  self : PreparedSignature,
  new_bytes : Bytes,
  limits : Limits,
) -> Bytes raise SyncError {
  limits.validate()
  guard self.signature_bytes <= limits.max_signature_bytes else {
    raise LimitExceeded
  }
  guard self.index.signature.block_len.to_int64() <= limits.max_block_bytes else {
    raise LimitExceeded
  }
  guard self.index.signature.records.length().to_int64() <=
    limits.max_signature_records else {
    raise LimitExceeded
  }
  guard new_bytes.length().to_int64() <= limits.max_new_bytes else {
    raise LimitExceeded
  }
  guard new_bytes.length().to_int64() <= limits.max_output_bytes else {
    raise LimitExceeded
  }
  guard limits.max_delta_bytes >= 5L else { raise LimitExceeded }
  let work = MatchWork::new(limits)
  if new_bytes.length() == 0 {
    return encode_delta([], limits)
  }
  scan_signature_delta(self.index, new_bytes, limits, work)
}
