// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// No addition or narrowing before the unsigned output-length bounds check.
fn signature_size(count : UInt64, strong : UInt64) -> Int32 raise SyncError {
  guard strong >= 1UL && strong <= 32UL else {
    raise InvalidOptions("strong_sum_len")
  }
  let body = checked_block_offset(count, 4UL + strong)
  guard body <= 0xffffffffffffffffUL - 12UL else { raise IntegerOutOfRange }
  checked_index(body + 12UL)
}

///|
/// Generation precedence: limits, block option, strong option, representation,
/// old bytes, block budget, record budget, output representation, byte budget.
fn signature_plan(
  basis_len : UInt64,
  options : SignatureOptions,
  limits : Limits,
) -> (Int32, Int32, Int32, Int32) raise SyncError {
  limits.validate()
  guard options.block_len > 0L else { raise InvalidOptions("block_len") }
  guard options.strong_sum_len >= 1L && options.strong_sum_len <= 32L else {
    raise InvalidOptions("strong_sum_len")
  }
  let block = checked_index(options.block_len.reinterpret_as_uint64())
  let strong = checked_index(options.strong_sum_len.reinterpret_as_uint64())
  guard basis_len <= limits.max_old_bytes.reinterpret_as_uint64() else {
    raise LimitExceeded
  }
  guard options.block_len <= limits.max_block_bytes else { raise LimitExceeded }
  let divisor = block.to_uint64()
  let quotient = basis_len / divisor
  // If there is a remainder, divisor >= 2 so quotient cannot be UInt64.MAX.
  let count = quotient + (if basis_len % divisor != 0UL { 1UL } else { 0UL })
  guard count <= limits.max_signature_records.reinterpret_as_uint64() else {
    raise LimitExceeded
  }
  let size = signature_size(count, strong.to_uint64())
  guard size.to_int64() <= limits.max_signature_bytes else {
    raise LimitExceeded
  }
  (block, strong, checked_index(count), size)
}

///|
fn signature_header(
  block : Int32,
  strong : Int32,
  size : Int32,
) -> FixedArray[Byte] raise SyncError {
  let output = FixedArray::make(size, b'\x00')
  write_u32_be(output, 0L, 0x72730147U)
  write_u32_be(output, 4L, block.reinterpret_as_uint())
  write_u32_be(output, 8L, strong.reinterpret_as_uint())
  output
}

///|
fn write_signature_record(
  output : FixedArray[Byte],
  offset : Int64,
  weak : UInt32,
  strong : Bytes,
) -> Unit raise SyncError {
  guard strong.length() >= 1 && strong.length() <= 32 else {
    raise InvalidSignature
  }
  let start = checked_wire_span(output.length(), offset, 4 + strong.length())
  write_u32_be(output, offset, weak)
  for i in 0..<strong.length() {
    output[start + 4 + i] = strong[i]
  }
}

///|
/// Internal serialization of a validated parsed structure, no basis inference.
#warnings("-unused_value")
fn encode_signature(sig : Signature, limits : Limits) -> Bytes raise SyncError {
  limits.validate()
  guard sig.magic == 0x72730147U &&
    sig.block_len > 0 &&
    sig.strong_sum_len >= 1 &&
    sig.strong_sum_len <= 32 else {
    raise InvalidSignature
  }
  guard sig.block_len.to_int64() <= limits.max_block_bytes &&
    sig.records.length().to_int64() <= limits.max_signature_records else {
    raise LimitExceeded
  }
  let size = signature_size(
    sig.records.length().to_uint64(),
    sig.strong_sum_len.to_uint64(),
  )
  guard size.to_int64() <= limits.max_signature_bytes else {
    raise LimitExceeded
  }
  for record in sig.records {
    guard record.strong_sum.length() == sig.strong_sum_len else {
      raise InvalidSignature
    }
  }
  let output = signature_header(sig.block_len, sig.strong_sum_len, size)
  let mut cursor = 12L
  for record in sig.records {
    write_signature_record(output, cursor, record.weak_sum, record.strong_sum)
    cursor = cursor + (4 + sig.strong_sum_len).to_int64()
  }
  Bytes::from_array(output[:])
}

///|
/// Internal only. The wire format provides no actual final-block length.
/// Production consumers are the signature index and remote-delta scanner.
#warnings("-unused_field")
priv struct SignatureRecord {
  block_index : Int32
  nominal_offset : UInt64
  weak_sum : UInt32
  strong_sum : Bytes
}

///|
/// Parsed structure, not a generated signature or proof of basis identity.
/// The signature index and generator consume this private validated structure.
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
/// Public delta generation uses this parser before index construction.
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
  // Record count and greatest offset are checked before exact slot allocation.
  let records : Array[SignatureRecord] = Array(capacity=record_count)
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
