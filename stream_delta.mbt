// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Incremental remote-delta scanner reusing an immutable PreparedSignature.
/// Holds only an O(block_len) sliding window plus up to 64 KiB of pending
/// literal bytes, keeping memory bounded across multi-chunk feeds.
pub struct DeltaScanner {
  priv index : SignatureIndex
  priv block_len : Int32
  priv limits : Limits
  priv work : MatchWork
  priv buf : Array[Byte]
  priv mut head : Int32
  priv mut weak : RollingWeak
  priv mut has_weak : Bool
  priv mut pending_copy : (UInt64, UInt64)?
  priv pending_lit : @buffer.Buffer
  priv mut pending_lit_cap : Int32
  priv ready : @buffer.Buffer
  priv mut total_new_bytes : UInt64
  priv mut emitted_delta_bytes : UInt64
  priv mut emitted_instructions : Int64
  priv mut finished : Bool
  priv mut failed : Bool
}

///|
fn write_stream_uint_be(
  buf : @buffer.Buffer,
  width : Int32,
  value : UInt64,
) -> Unit {
  for i in 0..<width {
    buf.write_byte(((value >> ((width - 1 - i) * 8)) & 0xffUL).to_byte())
  }
}

///|
fn DeltaScanner::pending_overhead_bytes(self : DeltaScanner) -> UInt64 {
  match self.pending_copy {
    Some((offset, length)) =>
      (1 + delta_width(offset) + delta_width(length)).to_uint64()
    None => {
      let lit_len = self.pending_lit.length()
      if lit_len == 0 {
        0UL
      } else {
        let len = lit_len.to_uint64()
        let hdr = if len <= 64UL {
          1UL
        } else {
          (1 + delta_width(len)).to_uint64()
        }
        hdr + len
      }
    }
  }
}

///|
fn DeltaScanner::flush_pending(self : DeltaScanner) -> Unit raise SyncError {
  match self.pending_copy {
    Some((offset, length)) => {
      self.work.spend(1L)
      guard self.emitted_instructions < self.limits.max_instructions else {
        raise LimitExceeded
      }
      let ow = delta_width(offset)
      let lw = delta_width(length)
      let cmd_bytes = (1 + ow + lw).to_uint64()
      let max_delta = self.limits.max_delta_bytes.reinterpret_as_uint64()
      guard self.emitted_delta_bytes <= max_delta &&
        cmd_bytes <= max_delta - self.emitted_delta_bytes else {
        raise LimitExceeded
      }
      self.ready.write_byte(
        (0x45 + 4 * delta_width_code(ow) + delta_width_code(lw)).to_byte(),
      )
      write_stream_uint_be(self.ready, ow, offset)
      write_stream_uint_be(self.ready, lw, length)
      self.emitted_delta_bytes = self.emitted_delta_bytes + cmd_bytes
      self.emitted_instructions = self.emitted_instructions + 1L
      self.pending_copy = None
    }
    None => {
      let lit_len = self.pending_lit.length()
      if lit_len > 0 {
        self.work.spend(1L)
        guard self.emitted_instructions < self.limits.max_instructions else {
          raise LimitExceeded
        }
        let len_u64 = lit_len.to_uint64()
        let hdr = literal_header_size(len_u64).to_uint64()
        let cmd_bytes = hdr + len_u64
        let max_delta = self.limits.max_delta_bytes.reinterpret_as_uint64()
        guard self.emitted_delta_bytes <= max_delta &&
          cmd_bytes <= max_delta - self.emitted_delta_bytes else {
          raise LimitExceeded
        }
        if len_u64 <= 64UL {
          self.ready.write_byte(len_u64.to_byte())
        } else {
          let width = delta_width(len_u64)
          self.ready.write_byte((0x41 + delta_width_code(width)).to_byte())
          write_stream_uint_be(self.ready, width, len_u64)
        }
        self.ready.write_bytes(self.pending_lit.to_bytes())
        self.pending_lit.reset()
        self.pending_lit_cap = 0
        self.emitted_delta_bytes = self.emitted_delta_bytes + cmd_bytes
        self.emitted_instructions = self.emitted_instructions + 1L
      }
    }
  }
}

///|
fn DeltaScanner::record_match(
  self : DeltaScanner,
  found : BlockMatch,
) -> Unit raise SyncError {
  if self.pending_lit.length() > 0 {
    self.flush_pending()
  }
  let length = found.length.to_uint64()
  let max_delta = self.limits.max_delta_bytes.reinterpret_as_uint64()
  match self.pending_copy {
    Some((prev_off, prev_len)) =>
      if checked_match_end(prev_off, prev_len) == found.nominal_offset {
        let merged_len = checked_match_end(prev_len, length)
        let cmd_bytes = (1 + delta_width(prev_off) + delta_width(merged_len)).to_uint64()
        guard self.emitted_delta_bytes <= max_delta &&
          cmd_bytes <= max_delta - self.emitted_delta_bytes else {
          raise LimitExceeded
        }
        self.work.spend(1L)
        self.pending_copy = Some((prev_off, merged_len))
        return
      } else {
        self.flush_pending()
      }
    None => ()
  }
  guard self.emitted_instructions < self.limits.max_instructions else {
    raise LimitExceeded
  }
  let cmd_bytes = (1 + delta_width(found.nominal_offset) + delta_width(length)).to_uint64()
  guard self.emitted_delta_bytes <= max_delta &&
    cmd_bytes <= max_delta - self.emitted_delta_bytes else {
    raise LimitExceeded
  }
  self.pending_copy = Some((found.nominal_offset, length))
}

///|
fn DeltaScanner::record_miss(
  self : DeltaScanner,
  byte : Byte,
) -> Unit raise SyncError {
  if self.pending_copy is Some(_) {
    self.flush_pending()
  }
  let max_delta = self.limits.max_delta_bytes.reinterpret_as_uint64()
  if self.pending_lit.length() == 0 {
    guard self.emitted_instructions < self.limits.max_instructions else {
      raise LimitExceeded
    }
    self.pending_lit.write_byte(byte)
    self.pending_lit_cap = literal_run_limit(
      self.emitted_delta_bytes,
      1,
      max_delta,
    )
  } else {
    self.pending_lit.write_byte(byte)
    let len = self.pending_lit.length()
    if len > self.pending_lit_cap {
      self.pending_lit_cap = literal_run_limit(
        self.emitted_delta_bytes,
        len,
        max_delta,
      )
    }
    if len >= 65536 {
      self.flush_pending()
    }
  }
}

///|
fn DeltaScanner::ensure_weak(
  self : DeltaScanner,
  len : Int32,
) -> Unit raise SyncError {
  if !self.has_weak {
    self.work.spend(1L + len.to_int64())
    let w = RollingWeak::new_for_magic(self.index.signature.magic)
    w.update_array(self.buf, self.head, len)
    self.weak = w
    self.has_weak = true
  }
}

///|
fn DeltaScanner::probe_window(
  self : DeltaScanner,
  len : Int32,
) -> BlockMatch? raise SyncError {
  match match_signature_weak(self.index, self.weak.digest(), self.work) {
    None => None
    Some(lo) => {
      let start = self.head
      let window = Bytes::makei(len, i => self.buf[start + i])
      confirm_signature_match(
        self.index,
        lo,
        window[:],
        self.weak.digest(),
        self.work,
      )
    }
  }
}

///|
fn DeltaScanner::compact_buffer(self : DeltaScanner, threshold : Int32) -> Unit {
  if self.head > 0 && (self.head >= threshold || self.head == self.buf.length()) {
    let rem = self.buf.length() - self.head
    for i in 0..<rem {
      self.buf[i] = self.buf[self.head + i]
    }
    self.buf.truncate(rem)
    self.head = 0
  }
}

///|
fn DeltaScanner::process_full_windows(
  self : DeltaScanner,
) -> Unit raise SyncError {
  while self.buf.length() - self.head > self.block_len {
    self.ensure_weak(self.block_len)
    self.work.spend(1L) // window dispatch
    match self.probe_window(self.block_len) {
      Some(found) => {
        self.record_match(found)
        self.head = self.head + self.block_len
        self.has_weak = false
      }
      None => {
        let out_byte = self.buf[self.head]
        let in_byte = self.buf[self.head + self.block_len]
        self.record_miss(out_byte)
        self.work.spend(3L)
        self.weak.rotate(out_byte, in_byte)
        self.head = self.head + 1
      }
    }
  }
}

///|
/// Initialize an incremental delta scanner from a prepared signature.
/// Revalidates current Limits (signature bytes, block, records, delta >= 5).
pub fn DeltaScanner::new(
  prepared : PreparedSignature,
  limits : Limits,
) -> DeltaScanner raise SyncError {
  limits.validate()
  guard prepared.signature_bytes <= limits.max_signature_bytes else {
    raise LimitExceeded
  }
  guard prepared.index.signature.block_len.to_int64() <= limits.max_block_bytes else {
    raise LimitExceeded
  }
  guard prepared.index.signature.records.length().to_int64() <=
    limits.max_signature_records else {
    raise LimitExceeded
  }
  guard limits.max_delta_bytes >= 5L else { raise LimitExceeded }
  let work = MatchWork::new(limits)
  let ready = Buffer(size_hint=64)
  ready.write_uint_be(0x72730236U)
  {
    index: prepared.index,
    block_len: prepared.index.signature.block_len,
    limits,
    work,
    buf: [],
    head: 0,
    weak: RollingWeak::new_for_magic(prepared.index.signature.magic),
    has_weak: false,
    pending_copy: None,
    pending_lit: Buffer(),
    pending_lit_cap: 0,
    ready,
    total_new_bytes: 0UL,
    emitted_delta_bytes: 5UL, // 4-byte magic + reserved final END byte
    emitted_instructions: 0L,
    finished: false,
    failed: false,
  }
}

///|
/// Feed a new-data chunk. Any budget or matching error transitions the scanner
/// to failed state; prepared signature state remains completely unchanged.
pub fn DeltaScanner::feed(
  self : DeltaScanner,
  chunk : BytesView,
) -> Unit raise SyncError {
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  errdefer {
    self.failed = true
  }
  let incoming = chunk.length().to_uint64()
  guard incoming <= 0xffffffffffffffffUL - self.total_new_bytes else {
    raise IntegerOutOfRange
  }
  let next_total = self.total_new_bytes + incoming
  guard next_total <= self.limits.max_new_bytes.reinterpret_as_uint64() &&
    next_total <= self.limits.max_output_bytes.reinterpret_as_uint64() else {
    raise LimitExceeded
  }
  self.total_new_bytes = next_total
  let step = if self.block_len > 4096 { self.block_len } else { 4096 }
  let mut pos = 0
  while pos < chunk.length() {
    let rem = chunk.length() - pos
    let take = if rem < step { rem } else { step }
    for byte in chunk[pos:pos + take] {
      self.buf.push(byte)
    }
    pos = pos + take
    self.process_full_windows()
    self.compact_buffer(step)
  }
}

///|
/// Drain currently encoded delta bytes (4-byte magic on first drain plus
/// flushed instructions). Never emits END before `finish`.
pub fn DeltaScanner::take_ready(self : DeltaScanner) -> Bytes raise SyncError {
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  let out = self.ready.to_bytes()
  self.ready.reset()
  out
}

///|
/// Run EOF short-tail rollout matching, flush trailing instructions and END,
/// close the scanner, and return all remaining undrained delta bytes.
pub fn DeltaScanner::finish(self : DeltaScanner) -> Bytes raise SyncError {
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  errdefer {
    self.failed = true
  }
  let active = self.buf.length() - self.head
  if active > 0 {
    self.ensure_weak(active)
    while self.head < self.buf.length() {
      let len = self.buf.length() - self.head
      self.work.spend(1L) // window dispatch
      match self.probe_window(len) {
        Some(found) => {
          self.record_match(found)
          self.head = self.buf.length()
          self.has_weak = false
        }
        None => {
          let out_byte = self.buf[self.head]
          self.record_miss(out_byte)
          self.work.spend(2L)
          self.weak.rollout(out_byte)
          self.head = self.head + 1
        }
      }
    }
  }
  self.flush_pending()
  let max_delta = self.limits.max_delta_bytes.reinterpret_as_uint64()
  guard self.emitted_delta_bytes <= max_delta &&
    self.pending_overhead_bytes() == 0UL else {
    raise LimitExceeded
  }
  self.ready.write_byte(b'\x00')
  self.buf.clear()
  self.head = 0
  self.finished = true
  let out = self.ready.to_bytes()
  self.ready.reset()
  out
}
