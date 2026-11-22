// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Incremental RK+BLAKE2 signature generator with O(1) hashing state.
/// Calling `take_ready` between chunks keeps buffered output O(1); calling
/// only `finish` collects all signature bytes identical to `signature()`.
pub struct SignatureHasher {
  priv magic : UInt32
  priv block_len : Int32
  priv strong_sum_len : Int32
  priv limits : Limits
  priv mut weak_hash : UInt32
  priv mut rs_s1 : UInt32
  priv mut rs_s2 : UInt32
  priv strong : @blake2.Hasher
  priv mut in_block : Int32
  priv mut total_bytes : UInt64
  priv ready : @buffer.Buffer
  priv mut finished : Bool
}

///|
/// Validate Limits and SignatureOptions, then initialize an incremental
/// signature stream for either `RkBlake2` (`0x72730147`) or
/// `RollsumBlake2` (`0x72730137`).
pub fn SignatureHasher::new_with_profile(
  options : SignatureOptions,
  profile : SignatureProfile,
  limits : Limits,
) -> SignatureHasher raise SyncError {
  let (block_len, strong_sum_len, _, _) = signature_plan(0UL, options, limits)
  let magic = profile.magic()
  let ready = Buffer(size_hint=12)
  ready.write_uint_be(magic)
  ready.write_uint_be(block_len.reinterpret_as_uint())
  ready.write_uint_be(strong_sum_len.reinterpret_as_uint())
  {
    magic,
    block_len,
    strong_sum_len,
    limits,
    weak_hash: 1U,
    rs_s1: 0U,
    rs_s2: 0U,
    strong: @blake2.Hasher::new(kind=Blake2b, len=32),
    in_block: 0,
    total_bytes: 0UL,
    ready,
    finished: false,
  }
}

///|
/// Validate Limits and SignatureOptions, then initialize an incremental
/// 0x72730147 signature stream holding the 12-byte wire header.
pub fn SignatureHasher::new(
  options : SignatureOptions,
  limits : Limits,
) -> SignatureHasher raise SyncError {
  SignatureHasher::new_with_profile(options, RkBlake2, limits)
}

///|
fn SignatureHasher::emit_block_record(self : SignatureHasher) -> Unit {
  let weak = if self.magic == 0x72730137U {
    ((self.rs_s2 & 0xffffU) << 16) | (self.rs_s1 & 0xffffU)
  } else {
    self.weak_hash
  }
  self.ready.write_uint_be(weak)
  let digest = self.strong.finish()
  self.ready.write_bytesview(digest[0:self.strong_sum_len])
  self.weak_hash = 1U
  self.rs_s1 = 0U
  self.rs_s2 = 0U
  self.strong.reset()
  self.in_block = 0
}

///|
/// Feed basis bytes incrementally. Validates the resulting total against
/// Limits before mutating any internal state; failures leave state intact.
pub fn SignatureHasher::update(
  self : SignatureHasher,
  chunk : BytesView,
) -> Unit raise SyncError {
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  let incoming = chunk.length().to_uint64()
  guard incoming <= 0xffffffffffffffffUL - self.total_bytes else {
    raise IntegerOutOfRange
  }
  let new_total = self.total_bytes + incoming
  let _ = signature_plan(
    new_total,
    {
      block_len: self.block_len.to_int64(),
      strong_sum_len: self.strong_sum_len.to_int64(),
    },
    self.limits,
  )
  let mut pos = 0
  while pos < chunk.length() {
    let room = self.block_len - self.in_block
    let remaining = chunk.length() - pos
    let take = if remaining < room { remaining } else { room }
    let slice = chunk[pos:pos + take]
    if self.magic == 0x72730137U {
      let mut s1 = self.rs_s1
      let mut s2 = self.rs_s2
      for byte in slice {
        s1 = (s1 + byte.to_uint() + rollsum_char_offset) & 0xffffU
        s2 = (s2 + s1) & 0xffffU
      }
      self.rs_s1 = s1
      self.rs_s2 = s2
    } else {
      let mut h = self.weak_hash
      for byte in slice {
        h = h * 0x08104225U + byte.to_uint()
      }
      self.weak_hash = h
    }
    self.strong.write(slice)
    self.in_block = self.in_block + take
    pos = pos + take
    if self.in_block == self.block_len {
      self.emit_block_record()
    }
  }
  self.total_bytes = new_total
}

///|
/// Drain any completed signature header and block record bytes buffered so far.
pub fn SignatureHasher::take_ready(
  self : SignatureHasher,
) -> Bytes raise SyncError {
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  let out = self.ready.to_bytes()
  self.ready.reset()
  out
}

///|
/// Flush any trailing short block (unpadded), finalize the stream, and return
/// all remaining undrained signature bytes.
pub fn SignatureHasher::finish(self : SignatureHasher) -> Bytes raise SyncError {
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  if self.in_block > 0 {
    self.emit_block_record()
  }
  self.finished = true
  let out = self.ready.to_bytes()
  self.ready.reset()
  out
}
