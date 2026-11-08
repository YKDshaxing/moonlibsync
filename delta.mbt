// SPDX-License-Identifier: LGPL-2.1-or-later
// Format reference: librsync e364852674780e43d578e4239128ff7014190ed3/src/prototab.c

///|
/// Literal borrows immutable input bytes; no payload copy or recovered output.
priv enum DeltaCommand {
  Literal(BytesView)
  Copy(UInt64, UInt64)
}

///|
fn delta_width(value : UInt64) -> Int32 {
  if value <= 0xffUL {
    1
  } else if value <= 0xffffUL {
    2
  } else if value <= 0xffffffffUL {
    4
  } else {
    8
  }
}

///|
fn delta_width_code(width : Int32) -> Int32 {
  match width {
    1 => 0
    2 => 1
    4 => 2
    _ => 3
  }
}

///|
/// Output estimate in the unsigned domain, before addition or storage growth.
fn delta_add_output(
  total : UInt64,
  length : UInt64,
  maximum : UInt64,
) -> UInt64 raise SyncError {
  guard length > 0UL else { raise InvalidDelta }
  guard total <= maximum && length <= maximum - total else {
    raise LimitExceeded
  }
  total + length
}

///|
/// Header-only encoding helper supports large literal lengths without payloads.
fn literal_header_size(length : UInt64) -> Int32 raise SyncError {
  guard length > 0UL else { raise InvalidDelta }
  if length <= 64UL {
    1
  } else {
    1 + delta_width(length)
  }
}

///|
fn write_literal_header(
  out : FixedArray[Byte],
  offset : Int64,
  length : UInt64,
) -> Int32 raise SyncError {
  let size = literal_header_size(length)
  let start = checked_wire_span(out.length(), offset, size)
  if length <= 64UL {
    out[start] = length.to_byte()
  } else {
    let width = delta_width(length)
    out[start] = (0x41 + delta_width_code(width)).to_byte()
    write_uint_be(out, offset + 1L, width, length)
  }
  size
}

///|
/// Limits, input bytes, complete magic, opcode, full parameters, zero length,
/// instruction budget, output budget, literal span, then command storage.
#warnings("-unused_value")
fn parse_delta(
  input : BytesView,
  limits : Limits,
) -> Array[DeltaCommand] raise SyncError {
  limits.validate()
  guard input.length().to_int64() <= limits.max_delta_bytes else {
    raise LimitExceeded
  }
  guard input.length() >= 4 else { raise TruncatedInput }
  guard read_u32_be(input, 0L) == 0x72730236U else { raise InvalidDelta }
  let commands : Array[DeltaCommand] = []
  let mut cursor = 4L
  let mut total = 0UL
  while cursor < input.length().to_int64() {
    let opcode = input[cursor.to_int()].to_int()
    cursor = cursor + 1L
    if opcode == 0 {
      guard cursor == input.length().to_int64() else { raise TrailingData }
      return commands
    }
    guard opcode <= 0x54 else { raise InvalidOpcode }
    let is_literal = opcode <= 0x44
    let mut offset = 0UL
    let length = if opcode <= 0x40 {
      opcode.to_uint64()
    } else if is_literal {
      let width = 1 << (opcode - 0x41)
      let value = read_uint_be(input, cursor, width)
      cursor = cursor + width.to_int64()
      value
    } else {
      let ow = 1 << ((opcode - 0x45) / 4)
      let lw = 1 << ((opcode - 0x45) % 4)
      offset = read_uint_be(input, cursor, ow)
      cursor = cursor + ow.to_int64()
      let value = read_uint_be(input, cursor, lw)
      cursor = cursor + lw.to_int64()
      value
    }
    guard length > 0UL else { raise InvalidDelta }
    guard commands.length().to_int64() < limits.max_instructions else {
      raise LimitExceeded
    }
    total = delta_add_output(
      total,
      length,
      limits.max_output_bytes.reinterpret_as_uint64(),
    )
    if is_literal {
      let size = checked_index(length)
      let start = checked_wire_span(input.length(), cursor, size)
      let end = start + size
      commands.push(Literal(input[start:end]))
      cursor = end.to_int64()
    } else {
      commands.push(Copy(offset, length)) // Never index a nonexistent basis.
    }
  }
  raise TruncatedInput
}

///|
/// Preflight byte size, command count and expected output before allocation.
#warnings("-unused_value")
fn encode_delta(
  commands : ArrayView[DeltaCommand],
  limits : Limits,
) -> Bytes raise SyncError {
  limits.validate()
  guard commands.length().to_int64() <= limits.max_instructions else {
    raise LimitExceeded
  }
  let mut size = 5UL // magic and exactly one END
  let mut total = 0UL
  for command in commands {
    let (length, overhead) = match command {
      Literal(data) =>
        (
          data.length().to_uint64(),
          literal_header_size(data.length().to_uint64()).to_uint64(),
        )
      Copy(offset, length) =>
        (length, (1 + delta_width(offset) + delta_width(length)).to_uint64())
    }
    total = delta_add_output(
      total,
      length,
      limits.max_output_bytes.reinterpret_as_uint64(),
    )
    let payload = match command {
      Literal(_) => length
      Copy(_, _) => 0UL
    }
    guard overhead <= 0xffffffffffffffffUL - size else {
      raise IntegerOutOfRange
    }
    size = size + overhead
    guard payload <= 0xffffffffffffffffUL - size else {
      raise IntegerOutOfRange
    }
    size = size + payload
  }
  guard size <= limits.max_delta_bytes.reinterpret_as_uint64() else {
    raise LimitExceeded
  }
  let out = FixedArray::make(checked_index(size), b'\x00')
  write_u32_be(out, 0L, 0x72730236U)
  let mut cursor = 4L
  for command in commands {
    match command {
      Literal(data) => {
        cursor = cursor +
          write_literal_header(out, cursor, data.length().to_uint64()).to_int64()
        let start = checked_wire_span(out.length(), cursor, data.length())
        for i in 0..<data.length() {
          out[start + i] = data[i]
        }
        cursor = cursor + data.length().to_int64()
      }
      Copy(offset, length) => {
        let ow = delta_width(offset)
        let lw = delta_width(length)
        let start = checked_wire_span(out.length(), cursor, 1 + ow + lw)
        out[start] = (0x45 + 4 * delta_width_code(ow) + delta_width_code(lw)).to_byte()
        write_uint_be(out, cursor + 1L, ow, offset)
        write_uint_be(out, cursor + 1L + ow.to_int64(), lw, length)
        cursor = cursor + (1 + ow + lw).to_int64()
      }
    }
  }
  out[cursor.to_int()] = b'\x00' // preflight included END
  Bytes::from_array(out[:])
}
