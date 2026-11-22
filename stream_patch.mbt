// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Synchronous random-read abstraction over basis data for streaming patch.
/// Implementations must return exactly `len` bytes starting at `offset`,
/// or raise `SyncError` (for example `CopyOutOfBounds` or `TruncatedInput`).
pub(open) trait BasisReader {
  fn read_at(Self, UInt64, Int32) -> Bytes raise SyncError
}

///|
pub impl BasisReader for Bytes with fn read_at(
  self : Bytes,
  offset : UInt64,
  len : Int32,
) -> Bytes raise SyncError {
  guard len >= 0 else { raise InvalidOptions("read_len") }
  let total = self.length().to_uint64()
  let req = len.to_uint64()
  guard offset <= total && req <= total - offset else { raise CopyOutOfBounds }
  let start = offset.to_int()
  self[start:start + len].to_owned()
}

///|
priv enum PatchStreamState {
  NeedMagic(Int32)
  NeedOpcode
  NeedLiteralLen(Int32, Int32)
  InLiteral(UInt64)
  NeedCopyOffset(Int32, Int32, Int32)
  NeedCopyLen(UInt64, Int32, Int32)
  InCopy(UInt64, UInt64)
  SawEnd
}

///|
/// Sans-IO output step yielded by `PatchDecoder::step`.
pub(all) enum PatchStep {
  /// The supplied delta slice has been completely consumed; feed more delta bytes
  /// or call `finish()` at EOF.
  NeedInput
  /// Direct zero-copy view into literal bytes within the supplied delta slice.
  EmitLiteral(BytesView)
  /// Validated COPY request `(offset, len)` with `1 <= len <= 65536`.
  CopyBasis(UInt64, Int32)
}

///|
/// Sans-IO incremental standard 0x72730236 delta decoder usable from both
/// synchronous code and async I/O loops (Native `async/fs`, browser `File`/`Blob`).
/// Enforces all Limits and UInt64 basis range checks before emitting COPY steps.
pub struct PatchDecoder {
  priv basis_len : UInt64
  priv limits : Limits
  priv mut state : PatchStreamState
  priv param_buf : FixedArray[Byte]
  priv mut delta_bytes : UInt64
  priv mut instruction_count : Int64
  priv mut literal_commands : Int64
  priv mut copy_commands : Int64
  priv mut literal_bytes : UInt64
  priv mut copy_bytes : UInt64
  priv mut output_bytes : UInt64
  priv mut closed : Bool
  priv mut failed : Bool
}

///|
/// Incremental standard 0x72730236 delta applier.
/// Streams literals without buffering and executes COPY spans via `BasisReader`
/// in <= 64 KiB chunks after UInt64 range validation. Callers writing to disk
/// must write to an isolated temporary file and commit only after `finish()`
/// (and whole-file integrity verification, if applicable) succeeds.
pub struct PatchApplier {
  priv decoder : PatchDecoder
}

///|
fn decode_param_be(buf : FixedArray[Byte], width : Int32) -> UInt64 {
  let mut value = 0UL
  for i in 0..<width {
    value = (value << 8) | buf[i].to_uint64()
  }
  value
}

///|
/// Initialize a Sans-IO delta decoder against a basis of `basis_len` bytes.
/// Validates all Limits, non-negative `basis_len`, and `max_old_bytes`.
pub fn PatchDecoder::new(
  basis_len : Int64,
  limits : Limits,
) -> PatchDecoder raise SyncError {
  limits.validate()
  guard basis_len >= 0L else { raise InvalidOptions("basis_len") }
  guard basis_len <= limits.max_old_bytes else { raise LimitExceeded }
  {
    basis_len: basis_len.reinterpret_as_uint64(),
    limits,
    state: NeedMagic(0),
    param_buf: FixedArray::make(8, b'\x00'),
    delta_bytes: 0UL,
    instruction_count: 0L,
    literal_commands: 0L,
    copy_commands: 0L,
    literal_bytes: 0UL,
    copy_bytes: 0UL,
    output_bytes: 0UL,
    closed: false,
    failed: false,
  }
}

///|
/// Whether an active COPY command still has remaining chunks to yield via `step`.
pub fn PatchDecoder::has_pending_copy(self : PatchDecoder) -> Bool {
  self.state is InCopy(_, _)
}

///|
fn PatchDecoder::consume_delta(
  self : PatchDecoder,
  count : Int32,
) -> Unit raise SyncError {
  let inc = count.to_uint64()
  let max_delta = self.limits.max_delta_bytes.reinterpret_as_uint64()
  guard self.delta_bytes <= max_delta && inc <= max_delta - self.delta_bytes else {
    raise LimitExceeded
  }
  self.delta_bytes = self.delta_bytes + inc
}

///|
fn PatchDecoder::begin_literal(
  self : PatchDecoder,
  len : UInt64,
) -> Unit raise SyncError {
  guard len > 0UL else { raise InvalidDelta }
  guard self.instruction_count < self.limits.max_instructions else {
    raise LimitExceeded
  }
  let max_out = self.limits.max_output_bytes.reinterpret_as_uint64()
  let next_total = delta_add_output(self.output_bytes, len, max_out)
  let next_lit = delta_add_output(self.literal_bytes, len, max_out)
  self.instruction_count = self.instruction_count + 1L
  self.literal_commands = self.literal_commands + 1L
  self.literal_bytes = next_lit
  self.output_bytes = next_total
  self.state = InLiteral(len)
}

///|
fn PatchDecoder::begin_copy(
  self : PatchDecoder,
  offset : UInt64,
  length : UInt64,
) -> (UInt64, Int32) raise SyncError {
  guard length > 0UL else { raise InvalidDelta }
  guard self.instruction_count < self.limits.max_instructions else {
    raise LimitExceeded
  }
  let max_out = self.limits.max_output_bytes.reinterpret_as_uint64()
  let next_total = delta_add_output(self.output_bytes, length, max_out)
  let next_copy = delta_add_output(self.copy_bytes, length, max_out)
  guard offset <= self.basis_len && length <= self.basis_len - offset else {
    raise CopyOutOfBounds
  }
  self.instruction_count = self.instruction_count + 1L
  self.copy_commands = self.copy_commands + 1L
  self.copy_bytes = next_copy
  self.output_bytes = next_total
  let first_u64 = if length < 65536UL { length } else { 65536UL }
  let rem = length - first_u64
  self.state = if rem == 0UL {
    NeedOpcode
  } else {
    InCopy(offset + first_u64, rem)
  }
  (offset, first_u64.to_int())
}

///|
/// Advance the decoder over `delta_chunk`, returning `(consumed, step)`.
/// Callers should loop while `pos < chunk.length() || decoder.has_pending_copy()`,
/// advancing `pos = pos + consumed` after handling each `PatchStep`.
pub fn PatchDecoder::step(
  self : PatchDecoder,
  delta_chunk : BytesView,
) -> (Int32, PatchStep) raise SyncError {
  guard !self.closed else { raise InvalidOptions("stream_finished") }
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  errdefer {
    self.failed = true
  }
  match self.state {
    InCopy(cur, rem) => {
      let take_u64 = if rem < 65536UL { rem } else { 65536UL }
      let take = take_u64.to_int()
      let left = rem - take_u64
      self.state = if left == 0UL {
        NeedOpcode
      } else {
        InCopy(cur + take_u64, left)
      }
      return (0, CopyBasis(cur, take))
    }
    _ => ()
  }
  let mut pos = 0
  while pos < delta_chunk.length() {
    match self.state {
      NeedMagic(have) => {
        let need = 4 - have
        let avail = delta_chunk.length() - pos
        let take = if avail < need { avail } else { need }
        self.consume_delta(take)
        for i in 0..<take {
          self.param_buf[have + i] = delta_chunk[pos + i]
        }
        pos = pos + take
        let next_have = have + take
        if next_have == 4 {
          let magic = decode_param_be(self.param_buf, 4)
          guard magic == 0x72730236UL else { raise InvalidDelta }
          self.state = NeedOpcode
        } else {
          self.state = NeedMagic(next_have)
        }
      }
      SawEnd => {
        self.consume_delta(1)
        raise TrailingData
      }
      NeedOpcode => {
        self.consume_delta(1)
        let opcode = delta_chunk[pos].to_int()
        pos = pos + 1
        if opcode == 0 {
          self.state = SawEnd
        } else if opcode <= 0x40 {
          self.begin_literal(opcode.to_uint64())
        } else if opcode <= 0x44 {
          let width = 1 << (opcode - 0x41)
          self.state = NeedLiteralLen(width, 0)
        } else if opcode <= 0x54 {
          let ow = 1 << ((opcode - 0x45) / 4)
          let lw = 1 << ((opcode - 0x45) % 4)
          self.state = NeedCopyOffset(ow, lw, 0)
        } else {
          raise InvalidOpcode
        }
      }
      NeedLiteralLen(width, have) => {
        let need = width - have
        let avail = delta_chunk.length() - pos
        let take = if avail < need { avail } else { need }
        self.consume_delta(take)
        for i in 0..<take {
          self.param_buf[have + i] = delta_chunk[pos + i]
        }
        pos = pos + take
        let next_have = have + take
        if next_have == width {
          let len = decode_param_be(self.param_buf, width)
          self.begin_literal(len)
        } else {
          self.state = NeedLiteralLen(width, next_have)
        }
      }
      InLiteral(remaining) => {
        let avail = (delta_chunk.length() - pos).to_uint64()
        let max_step = if remaining < 65536UL { remaining } else { 65536UL }
        let take_u64 = if avail < max_step { avail } else { max_step }
        let take = take_u64.to_int()
        self.consume_delta(take)
        let view = delta_chunk[pos:pos + take]
        pos = pos + take
        let left = remaining - take_u64
        self.state = if left == 0UL { NeedOpcode } else { InLiteral(left) }
        return (pos, EmitLiteral(view))
      }
      NeedCopyOffset(ow, lw, have) => {
        let need = ow - have
        let avail = delta_chunk.length() - pos
        let take = if avail < need { avail } else { need }
        self.consume_delta(take)
        for i in 0..<take {
          self.param_buf[have + i] = delta_chunk[pos + i]
        }
        pos = pos + take
        let next_have = have + take
        if next_have == ow {
          let offset = decode_param_be(self.param_buf, ow)
          self.state = NeedCopyLen(offset, lw, 0)
        } else {
          self.state = NeedCopyOffset(ow, lw, next_have)
        }
      }
      NeedCopyLen(offset, lw, have) => {
        let need = lw - have
        let avail = delta_chunk.length() - pos
        let take = if avail < need { avail } else { need }
        self.consume_delta(take)
        for i in 0..<take {
          self.param_buf[have + i] = delta_chunk[pos + i]
        }
        pos = pos + take
        let next_have = have + take
        if next_have == lw {
          let length = decode_param_be(self.param_buf, lw)
          let (off, chunk_len) = self.begin_copy(offset, length)
          return (pos, CopyBasis(off, chunk_len))
        } else {
          self.state = NeedCopyLen(offset, lw, next_have)
        }
      }
      InCopy(_, _) => abort("unreachable pending copy in delta loop")
    }
  }
  (pos, NeedInput)
}

///|
/// Verify END was reached with complete instructions, close the decoder, and
/// return exact DeltaSummary statistics.
pub fn PatchDecoder::finish(
  self : PatchDecoder,
) -> DeltaSummary raise SyncError {
  guard !self.closed else { raise InvalidOptions("stream_finished") }
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  guard self.state is SawEnd else {
    self.failed = true
    raise TruncatedInput
  }
  self.closed = true
  {
    delta_bytes: self.delta_bytes.reinterpret_as_int64(),
    instruction_count: self.instruction_count,
    literal_commands: self.literal_commands,
    copy_commands: self.copy_commands,
    literal_bytes: self.literal_bytes.reinterpret_as_int64(),
    copy_bytes: self.copy_bytes.reinterpret_as_int64(),
    output_bytes: self.output_bytes.reinterpret_as_int64(),
  }
}

///|
/// Initialize an incremental patch applier against a basis of `basis_len` bytes.
/// Validates all Limits, non-negative `basis_len`, and `max_old_bytes`.
pub fn PatchApplier::new(
  basis_len : Int64,
  limits : Limits,
) -> PatchApplier raise SyncError {
  { decoder: PatchDecoder::new(basis_len, limits), }
}

///|
/// Feed an arbitrary delta chunk (including 1-byte splits across headers or
/// parameters). Streams decoded output slices to `on_output`.
pub fn[R : BasisReader] PatchApplier::feed(
  self : PatchApplier,
  delta_chunk : BytesView,
  basis : R,
  on_output : (BytesView) -> Unit raise SyncError,
) -> Unit raise SyncError {
  guard !self.decoder.closed else { raise InvalidOptions("stream_finished") }
  guard !self.decoder.failed else { raise InvalidOptions("stream_failed") }
  errdefer {
    self.decoder.failed = true
  }
  let incoming = delta_chunk.length().to_uint64()
  let max_delta = self.decoder.limits.max_delta_bytes.reinterpret_as_uint64()
  guard self.decoder.delta_bytes <= max_delta &&
    incoming <= max_delta - self.decoder.delta_bytes else {
    raise LimitExceeded
  }
  if delta_chunk.length() == 0 && !self.decoder.has_pending_copy() {
    return
  }
  let mut pos = 0
  while pos < delta_chunk.length() || self.decoder.has_pending_copy() {
    let (consumed, step) = self.decoder.step(delta_chunk[pos:])
    pos = pos + consumed
    match step {
      NeedInput => ()
      EmitLiteral(view) => on_output(view)
      CopyBasis(offset, len) => {
        let chunk = basis.read_at(offset, len)
        guard chunk.length() == len else { raise TruncatedInput }
        on_output(chunk[:])
      }
    }
  }
}

///|
/// Verify END was reached with complete instructions, close the stream, and
/// return exact DeltaSummary statistics.
pub fn PatchApplier::finish(
  self : PatchApplier,
) -> DeltaSummary raise SyncError {
  self.decoder.finish()
}
