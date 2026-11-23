// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Bounded coalescing instruction emitter for standard librsync delta composition.
/// Coalesces adjacent `Copy` ops (`prev_off + prev_len == next_off`) and adjacent
/// `Literal` ops while enforcing `max_instructions`, `max_output_bytes`, and
/// `max_delta_bytes` incrementally before growing buffers.
priv struct ComposeEmitter {
  commands : Array[DeltaCommand]
  max_instructions : Int64
  max_output_bytes : UInt64
  max_delta_bytes : UInt64
  mut total_output : UInt64
  mut encoded_size : UInt64
  mut pending_lit_view : BytesView?
  mut pending_lit_buf : @buffer.Buffer?
  mut pending_lit_len : UInt64
}

///|
fn ComposeEmitter::new(limits : Limits) -> ComposeEmitter raise SyncError {
  guard limits.max_delta_bytes >= 5L else { raise LimitExceeded }
  {
    commands: [],
    max_instructions: limits.max_instructions,
    max_output_bytes: limits.max_output_bytes.reinterpret_as_uint64(),
    max_delta_bytes: limits.max_delta_bytes.reinterpret_as_uint64(),
    total_output: 0UL,
    encoded_size: 5UL, // 4-byte magic + 1-byte END
    pending_lit_view: None,
    pending_lit_buf: None,
    pending_lit_len: 0UL,
  }
}

///|
fn ComposeEmitter::flush_literal(self : ComposeEmitter) -> Unit {
  if self.pending_lit_len == 0UL {
    return
  }
  match self.pending_lit_buf {
    Some(buf) => self.commands.push(DeltaCommand::Literal(buf.to_bytes()[:]))
    None =>
      match self.pending_lit_view {
        Some(view) => self.commands.push(DeltaCommand::Literal(view))
        None => ()
      }
  }
  self.pending_lit_view = None
  self.pending_lit_buf = None
  self.pending_lit_len = 0UL
}

///|
fn ComposeEmitter::emit_literal(
  self : ComposeEmitter,
  slice : BytesView,
) -> Unit raise SyncError {
  let len = slice.length().to_uint64()
  guard len > 0UL else { raise InvalidDelta }
  self.total_output = delta_add_output(
    self.total_output,
    len,
    self.max_output_bytes,
  )
  if self.pending_lit_len > 0UL {
    let old_cmd_size = checked_match_end(
      literal_header_size(self.pending_lit_len).to_uint64(),
      self.pending_lit_len,
    )
    let new_len = checked_match_end(self.pending_lit_len, len)
    let new_cmd_size = checked_match_end(
      literal_header_size(new_len).to_uint64(),
      new_len,
    )
    let retained = self.encoded_size - old_cmd_size
    guard retained <= self.max_delta_bytes &&
      new_cmd_size <= self.max_delta_bytes - retained else {
      raise LimitExceeded
    }
    match self.pending_lit_buf {
      Some(buf) => buf.write_bytesview(slice)
      None => {
        let cap = checked_index(new_len)
        let buf = @buffer.Buffer(capacity=cap)
        match self.pending_lit_view {
          Some(prev) => buf.write_bytesview(prev)
          None => ()
        }
        buf.write_bytesview(slice)
        self.pending_lit_buf = Some(buf)
        self.pending_lit_view = None
      }
    }
    self.pending_lit_len = new_len
    self.encoded_size = retained + new_cmd_size
  } else {
    guard self.commands.length().to_int64() < self.max_instructions else {
      raise LimitExceeded
    }
    let cmd_size = checked_match_end(literal_header_size(len).to_uint64(), len)
    guard self.encoded_size <= self.max_delta_bytes &&
      cmd_size <= self.max_delta_bytes - self.encoded_size else {
      raise LimitExceeded
    }
    self.pending_lit_view = Some(slice)
    self.pending_lit_len = len
    self.encoded_size = self.encoded_size + cmd_size
  }
}

///|
fn ComposeEmitter::emit_copy(
  self : ComposeEmitter,
  offset : UInt64,
  length : UInt64,
) -> Unit raise SyncError {
  guard length > 0UL else { raise InvalidDelta }
  let _ = checked_match_end(offset, length)
  self.total_output = delta_add_output(
    self.total_output,
    length,
    self.max_output_bytes,
  )
  self.flush_literal()
  let count = self.commands.length()
  if count > 0 {
    match self.commands[count - 1] {
      Copy(prev_off, prev_len) if prev_len <= 0xffffffffffffffffUL - prev_off &&
        prev_off + prev_len == offset => {
        let new_len = checked_match_end(prev_len, length)
        let _ = checked_match_end(prev_off, new_len)
        let old_cmd_size = (1 + delta_width(prev_off) + delta_width(prev_len)).to_uint64()
        let new_cmd_size = (1 + delta_width(prev_off) + delta_width(new_len)).to_uint64()
        let retained = self.encoded_size - old_cmd_size
        guard retained <= self.max_delta_bytes &&
          new_cmd_size <= self.max_delta_bytes - retained else {
          raise LimitExceeded
        }
        self.commands[count - 1] = DeltaCommand::Copy(prev_off, new_len)
        self.encoded_size = retained + new_cmd_size
        return
      }
      _ => ()
    }
  }
  guard count.to_int64() < self.max_instructions else { raise LimitExceeded }
  let cmd_size = (1 + delta_width(offset) + delta_width(length)).to_uint64()
  guard self.encoded_size <= self.max_delta_bytes &&
    cmd_size <= self.max_delta_bytes - self.encoded_size else {
    raise LimitExceeded
  }
  self.commands.push(DeltaCommand::Copy(offset, length))
  self.encoded_size = self.encoded_size + cmd_size
}

///|
fn ComposeEmitter::finish(
  self : ComposeEmitter,
  limits : Limits,
) -> Bytes raise SyncError {
  self.flush_literal()
  encode_delta(self.commands, limits)
}

///|
fn find_first_output_segment(starts : Array[UInt64], offset : UInt64) -> Int32 {
  let mut lo = 0
  let mut hi = starts.length()
  while lo + 1 < hi {
    let mid = lo + (hi - lo) / 2
    if starts[mid] <= offset {
      lo = mid
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// Compose two standard `librsync 0x72730236` deltas (`first`: `v1 -> v2`,
/// `second`: `v2 -> v3`) into a single direct delta (`v1 -> v3`) without
/// materializing `v1`, `v2`, or `v3`. Coalesces adjacent `Copy` and `Literal`
/// commands and enforces all `Limits` during parsing, emission, and encoding.
pub fn compose_deltas(
  first : Bytes,
  second : Bytes,
  limits : Limits,
) -> Bytes raise SyncError {
  limits.validate()
  let first_cmds = parse_delta(first, limits)
  let second_cmds = parse_delta(second, limits)

  // Build v2 output-offset index from `first`'s instructions.
  let first_len = first_cmds.length()
  let first_out_starts : Array[UInt64] = Array(capacity=first_len)
  let max_out = limits.max_output_bytes.reinterpret_as_uint64()
  let mut v2_total_len = 0UL
  for cmd in first_cmds {
    first_out_starts.push(v2_total_len)
    let seg_len = match cmd {
      Literal(data) => data.length().to_uint64()
      Copy(_, len) => len
    }
    v2_total_len = delta_add_output(v2_total_len, seg_len, max_out)
  }

  let emitter = ComposeEmitter::new(limits)
  for cmd in second_cmds {
    match cmd {
      Literal(data) => emitter.emit_literal(data)
      Copy(v2_off, v2_len) => {
        guard v2_off <= v2_total_len && v2_len <= v2_total_len - v2_off else {
          raise CopyOutOfBounds
        }
        let mut cur_off = v2_off
        let mut remaining = v2_len
        let mut idx = find_first_output_segment(first_out_starts, cur_off)
        while remaining > 0UL {
          let seg_start = first_out_starts[idx]
          let seg_end = if idx + 1 < first_len {
            first_out_starts[idx + 1]
          } else {
            v2_total_len
          }
          let rel_off = cur_off - seg_start
          let avail = seg_end - cur_off
          let take = if remaining < avail { remaining } else { avail }
          match first_cmds[idx] {
            Literal(data) => {
              let start_i = checked_index(rel_off)
              let take_i = checked_index(take)
              emitter.emit_literal(data[start_i:start_i + take_i])
            }
            Copy(v1_off, _) => {
              let new_off = checked_match_end(v1_off, rel_off)
              emitter.emit_copy(new_off, take)
            }
          }
          cur_off = cur_off + take
          remaining = remaining - take
          idx = idx + 1
        }
      }
    }
  }
  emitter.finish(limits)
}

///|
/// Compose a non-empty chain of standard `librsync 0x72730236` deltas
/// `[v0->v1, v1->v2, ..., v(k-1)->vk]` left-to-right into one direct delta `v0->vk`.
/// A 1-element chain is strictly validated and normalized (coalescing adjacent ops).
pub fn compose_delta_chain(
  deltas : Array[Bytes],
  limits : Limits,
) -> Bytes raise SyncError {
  limits.validate()
  guard deltas.length() > 0 else { raise InvalidOptions("deltas") }
  if deltas.length() == 1 {
    let cmds = parse_delta(deltas[0], limits)
    let emitter = ComposeEmitter::new(limits)
    for cmd in cmds {
      match cmd {
        Literal(data) => emitter.emit_literal(data)
        Copy(offset, length) => emitter.emit_copy(offset, length)
      }
    }
    return emitter.finish(limits)
  }
  let mut acc = compose_deltas(deltas[0], deltas[1], limits)
  for i in 2..<deltas.length() {
    acc = compose_deltas(acc, deltas[i], limits)
  }
  acc
}
