// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Internal only. The wire format provides no actual final-block length.
/// Fields have whitebox test consumers; production matching is a later stage.
#warnings("-unused_field")
priv struct SignatureRecord {
  block_index : Int32
  nominal_offset : UInt64
  weak_sum : UInt32
  strong_sum : Bytes
}

///|
/// Parsed structure, not a generated signature or proof of basis identity.
/// Fields have whitebox test consumers; the type stays private.
#warnings("-unused_field")
priv struct Signature {
  magic : UInt32
  block_len : Int32
  strong_sum_len : Int32
  records : Array[SignatureRecord]
}

///|
/// Only the RK/BLAKE2 profile is accepted. See docs/signature-format.md for
/// the explicit error precedence, resource policy, and wire-format sources.
/// The parser is exercised only by whitebox tests until a later core consumer.
#warnings("-unused_value")
fn parse_signature(
  input : BytesView,
  limits : Limits,
) -> Signature raise SyncError {
  limits.validate()
  let input_len = input.length()
  guard input_len.to_int64() <= limits.max_signature_bytes else {
    raise LimitExceeded
  }
  guard input_len >= 12 else { raise TruncatedInput }
  let magic = read_u32_be(input, 0L)
  let block_wire = read_u32_be(input, 4L)
  let strong_wire = read_u32_be(input, 8L)
  match magic {
    0x72730147U => ()
    0x72730136U | 0x72730137U | 0x72730146U => raise UnsupportedSignatureProfile
    _ => raise InvalidSignature
  }
  guard block_wire != 0U && strong_wire >= 1U && strong_wire <= 32U else {
    raise InvalidSignature
  }
  // strong_wire is already proven to fit; never narrow an unchecked wire u32.
  let strong_sum_len = checked_index(strong_wire.to_uint64())
  let record_width = 4 + strong_sum_len // bounded by 5..36
  let body_len = input_len - 12
  guard body_len % record_width == 0 else { raise TruncatedInput }
  let record_count = body_len / record_width
  let block_len = checked_index(block_wire.to_uint64())
  guard block_len.to_int64() <= limits.max_block_bytes else {
    raise LimitExceeded
  }
  guard record_count.to_int64() <= limits.max_signature_records else {
    raise LimitExceeded
  }
  // Validate the greatest nominal offset before any record storage allocation.
  // Earlier offsets cannot exceed it: count >= 1 and block_len > 0 here.
  if record_count > 0 {
    let _ = checked_block_offset(
      (record_count - 1).to_uint64(),
      block_wire.to_uint64(),
    )
  }
  let records : Array[SignatureRecord] = []
  let mut cursor = 12L
  for block_index in 0..<record_count {
    let start = checked_wire_span(input_len, cursor, record_width)
    // Addition is safe only AFTER the complete span has been checked.
    let end = start + record_width
    let weak_sum = read_u32_be(input, cursor)
    let strong_sum = input[start + 4:end].to_owned()
    let nominal_offset = checked_block_offset(
      block_index.to_uint64(),
      block_wire.to_uint64(),
    )
    records.push({ block_index, nominal_offset, weak_sum, strong_sum, })
    cursor = end.to_int64()
  }
  { magic, block_len, strong_sum_len, records, }
}
