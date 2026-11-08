// SPDX-License-Identifier: LGPL-2.1-or-later
// Format reference: librsync e364852674780e43d578e4239128ff7014190ed3/src/prototab.c
// Generation flow reference: the same src/delta.c, Martin Pool (2000, 2001),
// Donovan Baarda (2003), LGPL-2.1-or-later; independent full-buffer implementation.

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

///|
/// Mutable only within one generation call; size includes magic and final END.
priv struct DeltaBuilder {
  commands : Array[DeltaCommand]
  mut size : UInt64
}

///|
fn generated_command_size(command : DeltaCommand) -> UInt64 raise SyncError {
  match command {
    Literal(data) =>
      checked_match_end(
        literal_header_size(data.length().to_uint64()).to_uint64(),
        data.length().to_uint64(),
      )
    Copy(offset, length) =>
      (1 + delta_width(offset) + delta_width(length)).to_uint64()
  }
}

///|
/// One charged bounded append/merge action, before views, arithmetic or storage.
/// The scanner provides consecutive nonempty spans of the same new-file input.
fn append_generated_span(
  builder : DeltaBuilder,
  input : BytesView,
  start : Int32,
  end : Int32,
  matched : BlockMatch?,
  limits : Limits,
  work : MatchWork,
) -> Unit raise SyncError {
  work.spend(1L)
  let count = builder.commands.length()
  let mut replace = false
  let command = match matched {
    Some(found) => {
      let offset = found.nominal_offset
      let length = (end - start).to_uint64()
      if count > 0 {
        match builder.commands[count - 1] {
          Copy(previous, size) if checked_match_end(previous, size) == offset => {
            replace = true
            Copy(previous, checked_match_end(size, length))
          }
          _ => Copy(offset, length)
        }
      } else {
        Copy(offset, length)
      }
    }
    None =>
      if count > 0 {
        match builder.commands[count - 1] {
          Literal(previous) => {
            replace = true
            // Previous literal ends exactly at start; no byte concatenation.
            Literal(input[start - previous.length():end])
          }
          _ => Literal(input[start:end])
        }
      } else {
        Literal(input[start:end])
      }
  }
  let retained = builder.size -
    (if replace {
      generated_command_size(builder.commands[count - 1])
    } else {
      0UL
    })
  let addition = generated_command_size(command)
  let maximum = limits.max_delta_bytes.reinterpret_as_uint64()
  guard retained <= maximum && addition <= maximum - retained else {
    raise LimitExceeded
  }
  if !replace {
    guard count.to_int64() < limits.max_instructions else {
      raise LimitExceeded
    }
    // Array.push may otherwise hide a linear relocation in the append unit.
    // Reserve an explicit capped capacity, charging allocation slots and every
    // live slot moved BEFORE reserve/push. Replacement/merge needs no growth.
    let capacity = builder.commands.capacity()
    if count == capacity {
      let doubled = if capacity == 0 { 1L } else { capacity.to_int64() * 2L }
      let next = if doubled < limits.max_instructions {
        doubled
      } else {
        limits.max_instructions
      }
      work.spend(next + count.to_int64())
      builder.commands.reserve_capacity(
        checked_index(next.reinterpret_as_uint64()),
      )
    }
    builder.commands.push(command)
  } else {
    builder.commands[count - 1] = command
  }
  builder.size = retained + addition
}

///|
fn generation_window(
  input : BytesView,
  position : Int32,
  block : Int32,
  work : MatchWork,
) -> RabinKarp raise SyncError {
  let length = if block < input.length() - position {
    block
  } else {
    input.length() - position
  }
  work.spend(1L + length.to_int64()) // state setup and all actual update bytes
  let weak = RabinKarp::new()
  weak.update(input[position:position + length])
  weak
}

///|
/// Only the verified signature index and new bytes enter this rolling scan.
fn scan_signature_delta(
  index : SignatureIndex,
  input : BytesView,
  limits : Limits,
  work : MatchWork,
) -> Bytes raise SyncError {
  let builder : DeltaBuilder = { commands: [], size: 5UL, }
  let mut position = 0
  if input.length() > 0 {
    let mut weak = generation_window(
      input,
      position,
      index.signature.block_len,
      work,
    )
    while position < input.length() {
      work.spend(1L) // window dispatch and bounded progress/position bookkeeping
      let length = weak.count
      let matched = match_signature_window(
        index,
        input[position:position + length],
        weak.digest(),
        work,
      )
      match matched {
        Some(found) => {
          append_generated_span(
            builder,
            input,
            position,
            position + length,
            Some(found),
            limits,
            work,
          )
          position = position + length // nonempty; <= input.length by window invariant
          if position < input.length() {
            weak = generation_window(
              input,
              position,
              index.signature.block_len,
              work,
            )
          }
        }
        None => {
          append_generated_span(
            builder,
            input,
            position,
            position + 1,
            None,
            limits,
            work,
          )
          if length < input.length() - position {
            work.spend(3L) // one rotation, outgoing byte and incoming byte
            weak.rotate(input[position], input[position + length])
          } else {
            work.spend(2L) // one EOF rollout and outgoing byte
            weak.rollout(input[position])
          }
          position = position + 1
        }
      }
    }
  }
  encode_delta(builder.commands, limits)
}

///|
/// Precedence: limits, complete signature, new bytes, output bytes, minimum
/// delta bytes, then one shared index/scan budget and incremental output checks.
fn generate_remote_delta(
  signature_bytes : Bytes,
  new_bytes : Bytes,
  limits : Limits,
) -> Bytes raise SyncError {
  limits.validate()
  let sig = parse_signature(signature_bytes, limits)
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
  let index = build_signature_index(sig, work)
  scan_signature_delta(index, new_bytes, limits, work)
}
