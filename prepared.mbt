// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Opaque, owned signature and final index order; no basis, input view, sort
/// scratch array, work balance or scanning state is retained. Private arrays
/// are read-only after construction. This is not a thread-safety guarantee.
/// Development source only; reusable delta generation is not yet provided.
#warnings("-unused_field")
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
