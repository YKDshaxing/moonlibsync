// SPDX-License-Identifier: LGPL-2.1-or-later

///|
let seal_magic_bytes : Bytes = b"MLSENC01"

///|
let seal_header_size : Int32 = 56

///|
let seal_chunk_header_size : Int32 = 5

///|
let seal_tag_size : Int32 = 16

///|
let seal_min_chunk_size : Int32 = 1024

///|
let seal_max_chunk_size : Int32 = 1048576

///|
let seal_min_argon2_memory_kib : Int32 = 64

///|
let seal_max_argon2_memory_kib : Int32 = 262144

///|
let seal_min_argon2_passes : Int32 = 1

///|
let seal_max_argon2_passes : Int32 = 16

///|
let seal_min_argon2_lanes : Int32 = 1

///|
let seal_max_argon2_lanes : Int32 = 4

///|
let seal_kdf_raw_key : Byte = b'\x00'

///|
let seal_kdf_argon2id : Byte = b'\x01'

///|
/// Return the 8-byte container magic (`MLSENC01`) for chunked authenticated
/// encryption streams (`.menc`).
pub fn seal_magic() -> Bytes {
  seal_magic_bytes
}

///|
/// Resource limits enforced on `MLSENC01` sealing, unsealing, header inspection,
/// and Argon2id key derivation.
#derive(Eq)
pub(all) struct SealLimits {
  max_input_bytes : Int64
  max_output_bytes : Int64
  max_chunk_size : Int32
  max_argon2_memory_kib : Int32
  max_argon2_passes : Int32
  max_argon2_lanes : Int32
}

///|
pub extend SealLimits with Eq::{equal, not_equal}

///|
/// Default safe limits: 64 MiB input, 80 MiB output, 1 MiB max chunk size,
/// Argon2id capped at 64 MiB / 8 passes / 4 lanes.
pub fn SealLimits::default() -> SealLimits {
  {
    max_input_bytes: 67108864L,
    max_output_bytes: 83886080L,
    max_chunk_size: 1048576,
    max_argon2_memory_kib: 65536,
    max_argon2_passes: 8,
    max_argon2_lanes: 4,
  }
}

///|
/// Configurable sealing options for `MLSENC01` chunk size and Argon2id cost.
#derive(Eq)
pub(all) struct SealOptions {
  chunk_size : Int32
  argon2_memory_kib : Int32
  argon2_passes : Int32
  argon2_lanes : Int32
}

///|
pub extend SealOptions with Eq::{equal, not_equal}

///|
/// Default sealing options: 64 KiB chunks, Argon2id 16 MiB / 2 passes / 1 lane.
pub fn SealOptions::default() -> SealOptions {
  {
    chunk_size: 65536,
    argon2_memory_kib: 16384,
    argon2_passes: 2,
    argon2_lanes: 1,
  }
}

///|
/// Parsed 56-byte `MLSENC01` container header.
#derive(Eq)
pub(all) struct SealHeader {
  kdf_mode : Byte
  chunk_size : Int32
  argon2_memory_kib : Int32
  argon2_passes : Int32
  argon2_lanes : Int32
  salt : Bytes
  nonce_prefix : Bytes
}

///|
pub extend SealHeader with Eq::{equal, not_equal}

///|
fn write_u32_be(buf : FixedArray[Byte], offset : Int32, value : UInt64) -> Unit {
  buf[offset] = ((value >> 24) & 0xffUL).to_byte()
  buf[offset + 1] = ((value >> 16) & 0xffUL).to_byte()
  buf[offset + 2] = ((value >> 8) & 0xffUL).to_byte()
  buf[offset + 3] = (value & 0xffUL).to_byte()
}

///|
fn write_u64_be(buf : FixedArray[Byte], offset : Int32, value : UInt64) -> Unit {
  buf[offset] = ((value >> 56) & 0xffUL).to_byte()
  buf[offset + 1] = ((value >> 48) & 0xffUL).to_byte()
  buf[offset + 2] = ((value >> 40) & 0xffUL).to_byte()
  buf[offset + 3] = ((value >> 32) & 0xffUL).to_byte()
  buf[offset + 4] = ((value >> 24) & 0xffUL).to_byte()
  buf[offset + 5] = ((value >> 16) & 0xffUL).to_byte()
  buf[offset + 6] = ((value >> 8) & 0xffUL).to_byte()
  buf[offset + 7] = (value & 0xffUL).to_byte()
}

///|
fn read_u32_be_view(bytes : BytesView, offset : Int32) -> UInt64 {
  (bytes[offset].to_uint64() << 24) |
  (bytes[offset + 1].to_uint64() << 16) |
  (bytes[offset + 2].to_uint64() << 8) |
  bytes[offset + 3].to_uint64()
}

///|
fn read_u32_be_fixed(buf : FixedArray[Byte], offset : Int32) -> UInt64 {
  (buf[offset].to_uint64() << 24) |
  (buf[offset + 1].to_uint64() << 16) |
  (buf[offset + 2].to_uint64() << 8) |
  buf[offset + 3].to_uint64()
}

///|
fn validate_seal_limits(limits : SealLimits) -> Unit raise CryptoError {
  guard limits.max_input_bytes >= 0L else {
    raise InvalidOptions("max_input_bytes")
  }
  guard limits.max_output_bytes >= 0L else {
    raise InvalidOptions("max_output_bytes")
  }
  guard limits.max_chunk_size >= seal_min_chunk_size &&
    limits.max_chunk_size <= seal_max_chunk_size else {
    raise InvalidOptions("max_chunk_size")
  }
  guard limits.max_argon2_memory_kib >= 0 &&
    limits.max_argon2_memory_kib <= seal_max_argon2_memory_kib else {
    raise InvalidOptions("max_argon2_memory_kib")
  }
  guard limits.max_argon2_passes >= 0 &&
    limits.max_argon2_passes <= seal_max_argon2_passes else {
    raise InvalidOptions("max_argon2_passes")
  }
  guard limits.max_argon2_lanes >= 0 &&
    limits.max_argon2_lanes <= seal_max_argon2_lanes else {
    raise InvalidOptions("max_argon2_lanes")
  }
}

///|
fn validate_salt_and_nonce_prefix(
  salt16 : Bytes,
  nonce_prefix12 : Bytes,
) -> Unit raise CryptoError {
  guard salt16.length() == 16 else { raise InvalidOptions("salt_length") }
  guard nonce_prefix12.length() == 12 else {
    raise InvalidOptions("nonce_prefix")
  }
  guard nonce_prefix12[8] == b'\x00' &&
    nonce_prefix12[9] == b'\x00' &&
    nonce_prefix12[10] == b'\x00' &&
    nonce_prefix12[11] == b'\x00' else {
    raise InvalidOptions("nonce_prefix")
  }
}

///|
/// Derive a 32-byte encryption key using Argon2id after strict format and
/// `SealLimits` validation.
pub fn derive_argon2_key(
  passphrase : Bytes,
  salt : Bytes,
  memory_kib : Int32,
  passes : Int32,
  lanes : Int32,
  limits : SealLimits,
) -> Bytes raise CryptoError {
  validate_seal_limits(limits)
  guard salt.length() == 16 else { raise InvalidOptions("salt_length") }
  guard memory_kib >= seal_min_argon2_memory_kib &&
    memory_kib <= seal_max_argon2_memory_kib else {
    raise InvalidOptions("argon2_memory_kib")
  }
  guard passes >= seal_min_argon2_passes && passes <= seal_max_argon2_passes else {
    raise InvalidOptions("argon2_passes")
  }
  guard lanes >= seal_min_argon2_lanes && lanes <= seal_max_argon2_lanes else {
    raise InvalidOptions("argon2_lanes")
  }
  guard memory_kib <= limits.max_argon2_memory_kib else {
    raise LimitExceeded("argon2_memory_kib")
  }
  guard passes <= limits.max_argon2_passes else {
    raise LimitExceeded("argon2_passes")
  }
  guard lanes <= limits.max_argon2_lanes else {
    raise LimitExceeded("argon2_lanes")
  }
  let params = @argon2.Params::new(memory=memory_kib, passes~, lanes~)
  let derived = @argon2.key(
    passphrase[:],
    salt[:],
    kind=@argon2.Kind::Argon2id,
    params~,
    len=32,
  )
  guard derived.length() == 32 else { raise InvalidKey("derived_key_length") }
  derived
}

///|
fn encode_seal_header(
  kdf_mode : Byte,
  chunk_size : Int32,
  argon2_memory_kib : Int32,
  argon2_passes : Int32,
  argon2_lanes : Int32,
  salt16 : Bytes,
  nonce_prefix12 : Bytes,
) -> Bytes {
  let buf = FixedArray::make(seal_header_size, b'\x00')
  for i in 0..<8 {
    buf[i] = seal_magic_bytes[i]
  }
  buf[8] = kdf_mode
  buf[9] = b'\x00'
  buf[10] = b'\x00'
  buf[11] = b'\x00'
  write_u32_be(buf, 12, chunk_size.to_uint64())
  write_u32_be(buf, 16, argon2_memory_kib.to_uint64())
  write_u32_be(buf, 20, argon2_passes.to_uint64())
  write_u32_be(buf, 24, argon2_lanes.to_uint64())
  for i in 0..<16 {
    buf[28 + i] = salt16[i]
  }
  for i in 0..<12 {
    buf[44 + i] = nonce_prefix12[i]
  }
  Bytes::from_array(buf[:])
}

///|
/// Inspect and validate the leading 56-byte `MLSENC01` header against format
/// invariants and `limits`.
pub fn inspect_seal_header(
  bytes : BytesView,
  limits : SealLimits,
) -> SealHeader raise CryptoError {
  validate_seal_limits(limits)
  guard bytes.length() >= seal_header_size else { raise TruncatedInput }
  for i in 0..<8 {
    guard bytes[i] == seal_magic_bytes[i] else { raise InvalidFormat("magic") }
  }
  let kdf_mode = bytes[8]
  guard kdf_mode == seal_kdf_raw_key || kdf_mode == seal_kdf_argon2id else {
    raise InvalidFormat("kdf_mode")
  }
  guard bytes[9] == b'\x00' else { raise InvalidFormat("reserved") }
  guard bytes[10] == b'\x00' && bytes[11] == b'\x00' else {
    raise InvalidFormat("flags")
  }
  let chunk_size_u64 = read_u32_be_view(bytes, 12)
  guard chunk_size_u64 >= seal_min_chunk_size.to_uint64() &&
    chunk_size_u64 <= seal_max_chunk_size.to_uint64() else {
    raise InvalidFormat("chunk_size")
  }
  guard chunk_size_u64 <= limits.max_chunk_size.to_uint64() else {
    raise LimitExceeded("chunk_size")
  }
  let mem_u64 = read_u32_be_view(bytes, 16)
  let passes_u64 = read_u32_be_view(bytes, 20)
  let lanes_u64 = read_u32_be_view(bytes, 24)
  if kdf_mode == seal_kdf_raw_key {
    guard mem_u64 == 0UL && passes_u64 == 0UL && lanes_u64 == 0UL else {
      raise InvalidFormat("argon2_params")
    }
  } else {
    guard mem_u64 >= seal_min_argon2_memory_kib.to_uint64() &&
      mem_u64 <= seal_max_argon2_memory_kib.to_uint64() else {
      raise InvalidFormat("argon2_memory_kib")
    }
    guard passes_u64 >= seal_min_argon2_passes.to_uint64() &&
      passes_u64 <= seal_max_argon2_passes.to_uint64() else {
      raise InvalidFormat("argon2_passes")
    }
    guard lanes_u64 >= seal_min_argon2_lanes.to_uint64() &&
      lanes_u64 <= seal_max_argon2_lanes.to_uint64() else {
      raise InvalidFormat("argon2_lanes")
    }
    guard mem_u64 <= limits.max_argon2_memory_kib.to_uint64() else {
      raise LimitExceeded("argon2_memory_kib")
    }
    guard passes_u64 <= limits.max_argon2_passes.to_uint64() else {
      raise LimitExceeded("argon2_passes")
    }
    guard lanes_u64 <= limits.max_argon2_lanes.to_uint64() else {
      raise LimitExceeded("argon2_lanes")
    }
  }
  let salt = bytes[28:44].to_owned()
  let nonce_prefix = bytes[44:56].to_owned()
  guard nonce_prefix[8] == b'\x00' &&
    nonce_prefix[9] == b'\x00' &&
    nonce_prefix[10] == b'\x00' &&
    nonce_prefix[11] == b'\x00' else {
    raise InvalidFormat("nonce_prefix")
  }
  {
    kdf_mode,
    chunk_size: chunk_size_u64.to_int(),
    argon2_memory_kib: mem_u64.to_int(),
    argon2_passes: passes_u64.to_int(),
    argon2_lanes: lanes_u64.to_int(),
    salt,
    nonce_prefix,
  }
}

///|
fn make_chunk_nonce(nonce_prefix : Bytes, chunk_index : UInt64) -> Bytes {
  let buf = FixedArray::make(12, b'\x00')
  for i in 0..<8 {
    buf[i] = nonce_prefix[i]
  }
  write_u32_be(buf, 8, chunk_index)
  Bytes::from_array(buf[:])
}

///|
fn make_chunk_aad(
  raw_header : Bytes,
  chunk_index : UInt64,
  is_final : Byte,
) -> Bytes {
  let buf = FixedArray::make(65, b'\x00')
  for i in 0..<seal_header_size {
    buf[i] = raw_header[i]
  }
  write_u64_be(buf, 56, chunk_index)
  buf[64] = is_final
  Bytes::from_array(buf[:])
}

///|
/// Incremental streaming `MLSENC01` ChaCha20-Poly1305 encoder.
/// Keeps O(`chunk_size`) pending plaintext state and fails closed on any error.
pub struct SealEncoder {
  priv aead : @chachapoly.ChaChaPoly
  priv raw_header : Bytes
  priv nonce_prefix : Bytes
  priv chunk_size : Int32
  priv limits : SealLimits
  priv pending : FixedArray[Byte]
  priv mut pending_len : Int32
  priv ready : @buffer.Buffer
  priv mut chunk_index : UInt64
  priv mut input_bytes : Int64
  priv mut output_bytes : Int64
  priv mut finished : Bool
  priv mut failed : Bool
}

///|
fn init_seal_encoder(
  key32 : Bytes,
  kdf_mode : Byte,
  salt16 : Bytes,
  nonce_prefix12 : Bytes,
  chunk_size : Int32,
  argon2_memory_kib : Int32,
  argon2_passes : Int32,
  argon2_lanes : Int32,
  limits : SealLimits,
) -> SealEncoder raise CryptoError {
  guard seal_header_size.to_int64() <= limits.max_output_bytes else {
    raise LimitExceeded("max_output_bytes")
  }
  let aead = @chachapoly.ChaChaPoly::new(key32[:]) catch {
    _ => raise InvalidKey("key")
  }
  let raw_header = encode_seal_header(
    kdf_mode, chunk_size, argon2_memory_kib, argon2_passes, argon2_lanes, salt16,
    nonce_prefix12,
  )
  let ready = @buffer.Buffer(size_hint=seal_header_size + 64)
  ready.write_bytes(raw_header)
  {
    aead,
    raw_header,
    nonce_prefix: nonce_prefix12,
    chunk_size,
    limits,
    pending: FixedArray::make(chunk_size, b'\x00'),
    pending_len: 0,
    ready,
    chunk_index: 0UL,
    input_bytes: 0L,
    output_bytes: seal_header_size.to_int64(),
    finished: false,
    failed: false,
  }
}

///|
/// Create a streaming `MLSENC01` encoder using a raw 32-byte key (`kdf_mode = 0x00`).
pub fn SealEncoder::new_with_key(
  key32 : Bytes,
  salt16 : Bytes,
  nonce_prefix12 : Bytes,
  options : SealOptions,
  limits : SealLimits,
) -> SealEncoder raise CryptoError {
  validate_seal_limits(limits)
  guard key32.length() == 32 else { raise InvalidKey("key_length") }
  validate_salt_and_nonce_prefix(salt16, nonce_prefix12)
  guard options.chunk_size >= seal_min_chunk_size &&
    options.chunk_size <= seal_max_chunk_size else {
    raise InvalidOptions("chunk_size")
  }
  guard options.chunk_size <= limits.max_chunk_size else {
    raise LimitExceeded("chunk_size")
  }
  init_seal_encoder(
    key32,
    seal_kdf_raw_key,
    salt16,
    nonce_prefix12,
    options.chunk_size,
    0,
    0,
    0,
    limits,
  )
}

///|
/// Create a streaming `MLSENC01` encoder deriving its 32-byte key with Argon2id
/// (`kdf_mode = 0x01`).
pub fn SealEncoder::new_with_passphrase(
  passphrase : Bytes,
  salt16 : Bytes,
  nonce_prefix12 : Bytes,
  options : SealOptions,
  limits : SealLimits,
) -> SealEncoder raise CryptoError {
  validate_seal_limits(limits)
  validate_salt_and_nonce_prefix(salt16, nonce_prefix12)
  guard options.chunk_size >= seal_min_chunk_size &&
    options.chunk_size <= seal_max_chunk_size else {
    raise InvalidOptions("chunk_size")
  }
  guard options.chunk_size <= limits.max_chunk_size else {
    raise LimitExceeded("chunk_size")
  }
  guard seal_header_size.to_int64() <= limits.max_output_bytes else {
    raise LimitExceeded("max_output_bytes")
  }
  let key32 = derive_argon2_key(
    passphrase,
    salt16,
    options.argon2_memory_kib,
    options.argon2_passes,
    options.argon2_lanes,
    limits,
  )
  init_seal_encoder(
    key32,
    seal_kdf_argon2id,
    salt16,
    nonce_prefix12,
    options.chunk_size,
    options.argon2_memory_kib,
    options.argon2_passes,
    options.argon2_lanes,
    limits,
  )
}

///|
fn SealEncoder::emit_chunk(
  self : SealEncoder,
  plain : BytesView,
  is_final : Byte,
) -> Unit raise CryptoError {
  guard self.chunk_index <= 0xffffffffUL else {
    raise LimitExceeded("chunk_index")
  }
  let plain_len = plain.length()
  let frame_len = (seal_chunk_header_size + plain_len + seal_tag_size).to_int64()
  guard frame_len <= 9223372036854775807L - self.output_bytes &&
    self.output_bytes + frame_len <= self.limits.max_output_bytes else {
    raise LimitExceeded("max_output_bytes")
  }
  let nonce = make_chunk_nonce(self.nonce_prefix, self.chunk_index)
  let aad = make_chunk_aad(self.raw_header, self.chunk_index, is_final)
  let ciphertext = self.aead.seal(nonce=nonce[:], plain~, aad=aad[:])
  let hdr = FixedArray::make(seal_chunk_header_size, b'\x00')
  write_u32_be(hdr, 0, plain_len.to_uint64())
  hdr[4] = is_final
  self.ready.write_bytes(Bytes::from_array(hdr[:]))
  self.ready.write_bytes(ciphertext)
  self.output_bytes = self.output_bytes + frame_len
  self.chunk_index = self.chunk_index + 1UL
}

///|
/// Feed plaintext bytes into the streaming `MLSENC01` encoder.
pub fn SealEncoder::update(
  self : SealEncoder,
  chunk : BytesView,
) -> Unit raise CryptoError {
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  errdefer {
    self.failed = true
    @spec.wipe(self.pending)
    self.pending_len = 0
    self.ready.reset()
  }
  let incoming = chunk.length().to_int64()
  guard incoming <= 9223372036854775807L - self.input_bytes &&
    self.input_bytes + incoming <= self.limits.max_input_bytes else {
    raise LimitExceeded("max_input_bytes")
  }
  let mut pos = 0
  while pos < chunk.length() {
    if self.pending_len == self.chunk_size {
      self.emit_chunk(Bytes::from_array(self.pending[:])[:], b'\x00')
      self.pending_len = 0
    }
    if self.pending_len == 0 && chunk.length() - pos > self.chunk_size {
      self.emit_chunk(chunk[pos:pos + self.chunk_size], b'\x00')
      pos = pos + self.chunk_size
      self.input_bytes = self.input_bytes + self.chunk_size.to_int64()
    } else {
      let space = self.chunk_size - self.pending_len
      let rem = chunk.length() - pos
      let take = if rem < space { rem } else { space }
      for i in 0..<take {
        self.pending[self.pending_len + i] = chunk[pos + i]
      }
      self.pending_len = self.pending_len + take
      pos = pos + take
      self.input_bytes = self.input_bytes + take.to_int64()
    }
  }
}

///|
/// Drain any sealed header and completed chunk frames currently ready.
pub fn SealEncoder::take_ready(self : SealEncoder) -> Bytes raise CryptoError {
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  let out = self.ready.to_bytes()
  self.ready.reset()
  out
}

///|
/// Seal the final authenticated chunk (`is_final = 1`), wipe buffered plaintext,
/// close the encoder, and return all remaining undrained ciphertext bytes.
pub fn SealEncoder::finish(self : SealEncoder) -> Bytes raise CryptoError {
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  errdefer {
    self.failed = true
    @spec.wipe(self.pending)
    self.pending_len = 0
    self.ready.reset()
  }
  let tail = if self.pending_len == 0 {
    b""
  } else {
    Bytes::from_array(self.pending[0:self.pending_len])
  }
  self.emit_chunk(tail[:], b'\x01')
  @spec.wipe(self.pending)
  self.pending_len = 0
  self.finished = true
  let out = self.ready.to_bytes()
  self.ready.reset()
  out
}

///|
priv enum SealDecoderStage {
  NeedHeader
  NeedChunkHeader
  NeedChunkBody
  SawFinal
}

///|
/// Incremental streaming `MLSENC01` ChaCha20-Poly1305 decoder.
/// Authenticates every chunk with header, chunk index, and final-flag AAD before
/// releasing plaintext, rejects truncation and trailing data, and fails closed.
pub struct SealDecoder {
  priv expected_kdf_mode : Byte
  priv mut passphrase : Bytes
  priv mut aead : @chachapoly.ChaChaPoly?
  priv limits : SealLimits
  priv mut stage : SealDecoderStage
  priv header_buf : FixedArray[Byte]
  priv mut header_len : Int32
  priv mut raw_header : Bytes
  priv mut header : SealHeader?
  priv chunk_hdr_buf : FixedArray[Byte]
  priv mut chunk_hdr_len : Int32
  priv mut cipher_buf : FixedArray[Byte]
  priv mut cipher_len : Int32
  priv mut current_plain_len : Int32
  priv mut current_is_final : Byte
  priv ready : @buffer.Buffer
  priv mut chunk_index : UInt64
  priv mut input_bytes : Int64
  priv mut output_bytes : Int64
  priv mut finished : Bool
  priv mut failed : Bool
}

///|
/// Create a streaming `MLSENC01` decoder expecting raw-key mode (`kdf_mode = 0x00`).
pub fn SealDecoder::new_with_key(
  key32 : Bytes,
  limits : SealLimits,
) -> SealDecoder raise CryptoError {
  validate_seal_limits(limits)
  guard key32.length() == 32 else { raise InvalidKey("key_length") }
  let aead = @chachapoly.ChaChaPoly::new(key32[:]) catch {
    _ => raise InvalidKey("key")
  }
  {
    expected_kdf_mode: seal_kdf_raw_key,
    passphrase: b"",
    aead: Some(aead),
    limits,
    stage: NeedHeader,
    header_buf: FixedArray::make(seal_header_size, b'\x00'),
    header_len: 0,
    raw_header: b"",
    header: None,
    chunk_hdr_buf: FixedArray::make(seal_chunk_header_size, b'\x00'),
    chunk_hdr_len: 0,
    cipher_buf: FixedArray::make(0, b'\x00'),
    cipher_len: 0,
    current_plain_len: 0,
    current_is_final: b'\x00',
    ready: @buffer.Buffer(),
    chunk_index: 0UL,
    input_bytes: 0L,
    output_bytes: 0L,
    finished: false,
    failed: false,
  }
}

///|
/// Create a streaming `MLSENC01` decoder expecting Argon2id passphrase mode
/// (`kdf_mode = 0x01`).
pub fn SealDecoder::new_with_passphrase(
  passphrase : Bytes,
  limits : SealLimits,
) -> SealDecoder raise CryptoError {
  validate_seal_limits(limits)
  {
    expected_kdf_mode: seal_kdf_argon2id,
    passphrase,
    aead: None,
    limits,
    stage: NeedHeader,
    header_buf: FixedArray::make(seal_header_size, b'\x00'),
    header_len: 0,
    raw_header: b"",
    header: None,
    chunk_hdr_buf: FixedArray::make(seal_chunk_header_size, b'\x00'),
    chunk_hdr_len: 0,
    cipher_buf: FixedArray::make(0, b'\x00'),
    cipher_len: 0,
    current_plain_len: 0,
    current_is_final: b'\x00',
    ready: @buffer.Buffer(),
    chunk_index: 0UL,
    input_bytes: 0L,
    output_bytes: 0L,
    finished: false,
    failed: false,
  }
}

///|
fn SealDecoder::open_chunk(
  self : SealDecoder,
  cipher : BytesView,
) -> Unit raise CryptoError {
  let hdr = match self.header {
    Some(h) => h
    None => raise InvalidFormat("missing_header")
  }
  let aead = match self.aead {
    Some(a) => a
    None => raise InvalidKey("missing_cipher")
  }
  let nonce = make_chunk_nonce(hdr.nonce_prefix, self.chunk_index)
  let aad = make_chunk_aad(
    self.raw_header,
    self.chunk_index,
    self.current_is_final,
  )
  let plain = aead.open(nonce=nonce[:], cipher~, aad=aad[:]) catch {
    _ => raise AuthenticationFailed
  }
  guard plain.length() == self.current_plain_len else {
    raise AuthenticationFailed
  }
  self.ready.write_bytes(plain)
  self.output_bytes = self.output_bytes + self.current_plain_len.to_int64()
  self.chunk_index = self.chunk_index + 1UL
  if self.current_is_final == b'\x01' {
    self.stage = SawFinal
  } else {
    self.stage = NeedChunkHeader
    self.chunk_hdr_len = 0
  }
}

///|
/// Feed ciphertext bytes into the streaming `MLSENC01` decoder.
pub fn SealDecoder::feed(
  self : SealDecoder,
  chunk : BytesView,
) -> Unit raise CryptoError {
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  errdefer {
    self.failed = true
    self.passphrase = b""
    self.ready.reset()
  }
  let incoming = chunk.length().to_int64()
  guard incoming <= 9223372036854775807L - self.input_bytes &&
    self.input_bytes + incoming <= self.limits.max_input_bytes else {
    raise LimitExceeded("max_input_bytes")
  }
  self.input_bytes = self.input_bytes + incoming
  let mut pos = 0
  while pos < chunk.length() {
    match self.stage {
      NeedHeader => {
        let need = seal_header_size - self.header_len
        let rem = chunk.length() - pos
        let take = if rem < need { rem } else { need }
        for i in 0..<take {
          self.header_buf[self.header_len + i] = chunk[pos + i]
        }
        self.header_len = self.header_len + take
        pos = pos + take
        if self.header_len == seal_header_size {
          let raw = Bytes::from_array(self.header_buf[:])
          let hdr = inspect_seal_header(raw[:], self.limits)
          guard hdr.kdf_mode == self.expected_kdf_mode else {
            raise InvalidFormat("kdf_mode_mismatch")
          }
          if hdr.kdf_mode == seal_kdf_argon2id {
            let derived = derive_argon2_key(
              self.passphrase,
              hdr.salt,
              hdr.argon2_memory_kib,
              hdr.argon2_passes,
              hdr.argon2_lanes,
              self.limits,
            )
            self.passphrase = b""
            let aead = @chachapoly.ChaChaPoly::new(derived[:]) catch {
              _ => raise InvalidKey("derived_key")
            }
            self.aead = Some(aead)
          }
          self.raw_header = raw
          self.header = Some(hdr)
          self.stage = NeedChunkHeader
          self.chunk_hdr_len = 0
        }
      }
      NeedChunkHeader => {
        let need = seal_chunk_header_size - self.chunk_hdr_len
        let rem = chunk.length() - pos
        let take = if rem < need { rem } else { need }
        for i in 0..<take {
          self.chunk_hdr_buf[self.chunk_hdr_len + i] = chunk[pos + i]
        }
        self.chunk_hdr_len = self.chunk_hdr_len + take
        pos = pos + take
        if self.chunk_hdr_len == seal_chunk_header_size {
          let hdr = match self.header {
            Some(h) => h
            None => raise InvalidFormat("missing_header")
          }
          let plain_len_u64 = read_u32_be_fixed(self.chunk_hdr_buf, 0)
          let is_final = self.chunk_hdr_buf[4]
          guard is_final == b'\x00' || is_final == b'\x01' else {
            raise InvalidFormat("chunk_final_flag")
          }
          guard plain_len_u64 <= hdr.chunk_size.to_uint64() else {
            raise InvalidFormat("chunk_length")
          }
          if is_final == b'\x00' {
            guard plain_len_u64 >= 1UL else {
              raise InvalidFormat("empty_non_final_chunk")
            }
          }
          guard self.chunk_index <= 0xffffffffUL else {
            raise LimitExceeded("chunk_index")
          }
          let plain_len = plain_len_u64.to_int()
          guard plain_len.to_int64() <= 9223372036854775807L - self.output_bytes &&
            self.output_bytes + plain_len.to_int64() <=
            self.limits.max_output_bytes else {
            raise LimitExceeded("max_output_bytes")
          }
          let expected_cipher_len = plain_len + seal_tag_size
          if self.cipher_buf.length() < expected_cipher_len {
            self.cipher_buf = FixedArray::make(expected_cipher_len, b'\x00')
          }
          self.current_plain_len = plain_len
          self.current_is_final = is_final
          self.cipher_len = 0
          self.stage = NeedChunkBody
        }
      }
      NeedChunkBody => {
        let expected_cipher_len = self.current_plain_len + seal_tag_size
        let rem = chunk.length() - pos
        if self.cipher_len == 0 && rem >= expected_cipher_len {
          self.open_chunk(chunk[pos:pos + expected_cipher_len])
          pos = pos + expected_cipher_len
        } else {
          let need = expected_cipher_len - self.cipher_len
          let take = if rem < need { rem } else { need }
          for i in 0..<take {
            self.cipher_buf[self.cipher_len + i] = chunk[pos + i]
          }
          self.cipher_len = self.cipher_len + take
          pos = pos + take
          if self.cipher_len == expected_cipher_len {
            let cipher_bytes = Bytes::from_array(
              self.cipher_buf[0:expected_cipher_len],
            )
            self.cipher_len = 0
            self.open_chunk(cipher_bytes[:])
          }
        }
      }
      SawFinal => raise TrailingData
    }
  }
}

///|
/// Drain authenticated plaintext bytes decrypted so far.
pub fn SealDecoder::take_ready(self : SealDecoder) -> Bytes raise CryptoError {
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  let out = self.ready.to_bytes()
  self.ready.reset()
  out
}

///|
/// Finalize decoding, verify the stream ended cleanly at an authenticated final
/// chunk with no truncation or trailing bytes, and return the parsed `SealHeader`.
pub fn SealDecoder::finish(self : SealDecoder) -> SealHeader raise CryptoError {
  guard !self.failed else { raise InvalidOptions("stream_failed") }
  guard !self.finished else { raise InvalidOptions("stream_finished") }
  errdefer {
    self.failed = true
    self.passphrase = b""
    self.ready.reset()
  }
  guard self.stage is SawFinal else { raise TruncatedInput }
  let hdr = match self.header {
    Some(h) => h
    None => raise TruncatedInput
  }
  self.finished = true
  hdr
}

///|
/// One-shot `MLSENC01` authenticated encryption using a raw 32-byte key.
pub fn seal_with_key(
  plain : Bytes,
  key32 : Bytes,
  salt16 : Bytes,
  nonce_prefix12 : Bytes,
  options : SealOptions,
  limits : SealLimits,
) -> Bytes raise CryptoError {
  let enc = SealEncoder::new_with_key(
    key32, salt16, nonce_prefix12, options, limits,
  )
  enc.update(plain[:])
  enc.finish()
}

///|
/// One-shot `MLSENC01` authenticated encryption deriving a 32-byte key with Argon2id.
pub fn seal_with_passphrase(
  plain : Bytes,
  passphrase : Bytes,
  salt16 : Bytes,
  nonce_prefix12 : Bytes,
  options : SealOptions,
  limits : SealLimits,
) -> Bytes raise CryptoError {
  let enc = SealEncoder::new_with_passphrase(
    passphrase, salt16, nonce_prefix12, options, limits,
  )
  enc.update(plain[:])
  enc.finish()
}

///|
/// One-shot `MLSENC01` authenticated decryption using a raw 32-byte key.
pub fn unseal_with_key(
  cipher : Bytes,
  key32 : Bytes,
  limits : SealLimits,
) -> Bytes raise CryptoError {
  let dec = SealDecoder::new_with_key(key32, limits)
  dec.feed(cipher[:])
  let _ = dec.finish()
  dec.take_ready()
}

///|
/// One-shot `MLSENC01` authenticated decryption using an Argon2id passphrase.
pub fn unseal_with_passphrase(
  cipher : Bytes,
  passphrase : Bytes,
  limits : SealLimits,
) -> Bytes raise CryptoError {
  let dec = SealDecoder::new_with_passphrase(passphrase, limits)
  dec.feed(cipher[:])
  let _ = dec.finish()
  dec.take_ready()
}
