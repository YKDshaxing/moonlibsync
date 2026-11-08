// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Fixed legal widths only; preserve the complete unsigned parameter.
fn read_uint_be(
  input : BytesView,
  offset : Int64,
  width : Int32,
) -> UInt64 raise SyncError {
  guard width == 1 || width == 2 || width == 4 || width == 8 else {
    raise InvalidOptions("wire_width")
  }
  let start = checked_wire_span(input.length(), offset, width)
  let mut value = 0UL
  for i in 0..<width {
    value = (value << 8) | input[start + i].to_uint64()
  }
  value
}

///|
/// Check width, complete span and value before the first write.
fn write_uint_be(
  output : FixedArray[Byte],
  offset : Int64,
  width : Int32,
  value : UInt64,
) -> Unit raise SyncError {
  guard width == 1 || width == 2 || width == 4 || width == 8 else {
    raise InvalidOptions("wire_width")
  }
  let start = checked_wire_span(output.length(), offset, width)
  if width < 8 {
    guard value < 1UL << (width * 8) else { raise IntegerOutOfRange }
  }
  for i in 0..<width {
    output[start + i] = ((value >> ((width - 1 - i) * 8)) & 0xffUL).to_byte()
  }
}

///|
/// Convert only after proving that an unsigned wire value fits an array index.
fn checked_index(value : UInt64) -> Int32 raise SyncError {
  guard value <= 2147483647UL else { raise IntegerOutOfRange }
  value.to_int()
}

///|
/// Check a complete span before adding offsets or touching the buffer.
/// An invalid position is a range error; a valid position with too few bytes
/// is truncated input. The end position itself is a valid position.
fn checked_wire_span(
  length : Int32,
  offset : Int64,
  width : Int32,
) -> Int32 raise SyncError {
  guard length >= 0 && offset >= 0L && width >= 0 else {
    raise IntegerOutOfRange
  }
  // The signed offset was checked nonnegative before preserving its bits.
  let start = checked_index(offset.reinterpret_as_uint64())
  guard start <= length else { raise IntegerOutOfRange }
  guard width <= length - start else { raise TruncatedInput }
  start
}

///|
/// Keep the full UInt32 bit pattern, including values above signed Int32.
fn read_u32_be(input : BytesView, offset : Int64) -> UInt32 raise SyncError {
  let start = checked_wire_span(input.length(), offset, 4)
  let mut value = 0U
  for i in 0..<4 {
    value = (value << 8) | input[start + i].to_uint()
  }
  value
}

///|
/// UInt64 arithmetic never passes through a signed or floating-point value.
/// This stage exercises this internal entry point through whitebox tests only.
#warnings("-unused_value")
fn read_u64_be(input : BytesView, offset : Int64) -> UInt64 raise SyncError {
  let start = checked_wire_span(input.length(), offset, 8)
  let mut value = 0UL
  for i in 0..<8 {
    value = (value << 8) | input[start + i].to_uint64()
  }
  value
}

///|
/// Validate the whole output span first, so failure cannot partially write.
/// This stage exercises the internal writers through whitebox tests only.
#warnings("-unused_value")
fn write_u32_be(
  output : FixedArray[Byte],
  offset : Int64,
  value : UInt32,
) -> Unit raise SyncError {
  let start = checked_wire_span(output.length(), offset, 4)
  for i in 0..<4 {
    output[start + i] = ((value >> ((3 - i) * 8)) & 0xffU).to_byte()
  }
}

///|
/// Internal u64 writer; its callers in this stage are whitebox tests only.
#warnings("-unused_value")
fn write_u64_be(
  output : FixedArray[Byte],
  offset : Int64,
  value : UInt64,
) -> Unit raise SyncError {
  let start = checked_wire_span(output.length(), offset, 8)
  for i in 0..<8 {
    output[start + i] = ((value >> ((7 - i) * 8)) & 0xffUL).to_byte()
  }
}

///|
/// Check the division bound before computing a nominal block offset.
/// The result is not a basis length and is not yet an index into a basis file.
fn checked_block_offset(
  record_index : UInt64,
  block_len : UInt64,
) -> UInt64 raise SyncError {
  if block_len != 0UL && record_index > 0xffffffffffffffffUL / block_len {
    raise IntegerOutOfRange
  }
  record_index * block_len
}
