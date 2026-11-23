// SPDX-License-Identifier: LGPL-2.1-or-later

///|
let envelope_magic_bytes : Bytes = b"MLSENC02"

///|
let envelope_version_byte : Byte = b'\x02'

///|
let envelope_preamble_size : Int32 = 51

///|
let envelope_slot_size : Int32 = 56

///|
let envelope_max_recipients : Int32 = 64

///|
let envelope_wrap_info : Bytes = b"moonlibsync-mlsenc02-wrap-v1"

///|
let envelope_slot_aad_prefix : Bytes = b"MLSENC02-SLOT\x00"

///|
let x25519_low_order_8a : BigInt = 0x00b8495f16056286fdb1329ceb8d09da6ac49ff1fae35616aeb8413b7c7aebe0N

///|
let x25519_low_order_8b : BigInt = 0x57119fd0dd4e22d8868e1c58c45c44045bef839c55b1d0b1248c50a3bc959c5fN

///|
/// Return the 8-byte container magic (`MLSENC02`) for multi-recipient X25519
/// envelope encryption.
pub fn envelope_magic() -> Bytes {
  envelope_magic_bytes
}

///|
/// X25519 key pair consisting of a 32-byte secret scalar and 32-byte public key.
#derive(Eq)
pub(all) struct X25519KeyPair {
  secret_key : Bytes
  public_key : Bytes
}

///|
pub extend X25519KeyPair with Eq::{equal, not_equal}

///|
/// Parsed `MLSENC02` multi-recipient envelope header.
#derive(Eq)
pub(all) struct EnvelopeHeader {
  ephemeral_public_key : Bytes
  recipient_key_ids : Array[String]
  chunk_size : Int32
  nonce_prefix : Bytes
}

///|
pub extend EnvelopeHeader with Eq::{equal, not_equal}

///|
fn is_all_zero(bytes : BytesView) -> Bool {
  let mut acc = 0
  for i in 0..<bytes.length() {
    acc = acc | bytes[i].to_int()
  }
  acc == 0
}

///|
fn validate_x25519_public_key(
  public_key : Bytes,
  field : String,
) -> Unit raise CryptoError {
  guard public_key.length() == @x25519.size else { raise InvalidKey(field) }
  guard (public_key[31].to_int() & 0x80) == 0 else { raise InvalidKey(field) }
  guard !is_all_zero(public_key[:]) else { raise InvalidKey(field) }
  let be = FixedArray::make(32, b'\x00')
  be[0] = public_key[31]
  for i in 0..<31 {
    be[31 - i] = public_key[i]
  }
  let u = BigInt::from_octets(Bytes::from_array(be[:])[:])
  guard u < ed25519_p else { raise InvalidKey(field) }
  guard u != 0N &&
    u != 1N &&
    u != ed25519_p - 1N &&
    u != x25519_low_order_8a &&
    u != x25519_low_order_8b else {
    raise InvalidKey(field)
  }
}

///|
fn x25519_key_id_raw(
  public_key : Bytes,
  field : String,
) -> Bytes raise CryptoError {
  validate_x25519_public_key(public_key, field)
  let digest = @sha2.hash(public_key[:], kind=@sha2.Kind::Sha256)
  guard digest.length() == 32 else { raise InvalidFormat("sha256") }
  digest[0:8].to_owned()
}

///|
/// Derive an `X25519KeyPair` from a 32-byte non-zero secret scalar.
pub fn x25519_keypair_from_secret(
  secret : Bytes,
) -> X25519KeyPair raise CryptoError {
  guard secret.length() == @x25519.size && !is_all_zero(secret[:]) else {
    raise InvalidKey("x25519_secret")
  }
  let public_key = @x25519.public(secret[:]) catch {
    _ => raise InvalidKey("x25519_secret")
  }
  validate_x25519_public_key(public_key, "x25519_secret")
  { secret_key: secret, public_key, }
}

///|
/// Derive the 32-byte X25519 public key from a 32-byte non-zero secret scalar.
pub fn x25519_public_from_secret(secret : Bytes) -> Bytes raise CryptoError {
  x25519_keypair_from_secret(secret).public_key
}

///|
/// Compute the 16-character lowercase hex key identifier (first 8 bytes of
/// SHA-256 of the 32-byte X25519 public key).
pub fn x25519_key_id(public_key : Bytes) -> String raise CryptoError {
  encode_key_hex(x25519_key_id_raw(public_key, "x25519_public_key"))
}

///|
fn derive_wrap_key(
  shared : Bytes,
  eph_pub : Bytes,
  recipient_pub : Bytes,
) -> Bytes {
  let salt = eph_pub + recipient_pub
  @hkdf.key(
    shared[:],
    () => (@sha2.Hasher::new(kind=@sha2.Kind::Sha256) : &@spec.Hash),
    salt=salt[:],
    info=envelope_wrap_info[:],
    len=32,
  )
}

///|
fn make_wrap_nonce(nonce_prefix4 : Bytes, slot_index : Int32) -> Bytes {
  let buf = FixedArray::make(12, b'\x00')
  for i in 0..<4 {
    buf[i] = nonce_prefix4[i]
  }
  write_u32_be(buf, 8, slot_index.to_uint64())
  Bytes::from_array(buf[:])
}

///|
fn make_wrap_aad(
  eph_pub : Bytes,
  recipient_pub : Bytes,
  slot_index : Int32,
) -> Bytes {
  let buf = FixedArray::make(82, b'\x00')
  for i in 0..<14 {
    buf[i] = envelope_slot_aad_prefix[i]
  }
  for i in 0..<32 {
    buf[14 + i] = eph_pub[i]
  }
  for i in 0..<32 {
    buf[46 + i] = recipient_pub[i]
  }
  write_u32_be(buf, 78, slot_index.to_uint64())
  Bytes::from_array(buf[:])
}

///|
fn make_envelope_chunk_nonce(
  nonce_prefix4 : Bytes,
  chunk_index : UInt64,
) -> Bytes {
  let buf = FixedArray::make(12, b'\x00')
  for i in 0..<4 {
    buf[i] = nonce_prefix4[i]
  }
  write_u64_be(buf, 4, chunk_index)
  Bytes::from_array(buf[:])
}

///|
fn make_envelope_chunk_aad(
  header_aad32 : Bytes,
  chunk_index : UInt64,
  flags : Byte,
  pt_len : Int32,
) -> Bytes {
  let buf = FixedArray::make(45, b'\x00')
  for i in 0..<32 {
    buf[i] = header_aad32[i]
  }
  write_u64_be(buf, 32, chunk_index)
  buf[40] = flags
  write_u32_be(buf, 41, pt_len.to_uint64())
  Bytes::from_array(buf[:])
}

///|
/// Inspect and validate the leading `MLSENC02` multi-recipient envelope header
/// (preamble + all recipient slots) against format invariants and `limits`.
pub fn inspect_envelope_header(
  data : BytesView,
  limits : SealLimits,
) -> EnvelopeHeader raise CryptoError {
  validate_seal_limits(limits)
  guard data.length() >= envelope_preamble_size else { raise TruncatedInput }
  for i in 0..<8 {
    guard data[i] == envelope_magic_bytes[i] else {
      raise InvalidFormat("magic")
    }
  }
  guard data[8] == envelope_version_byte else { raise InvalidFormat("version") }
  let recipient_count = (data[9].to_int() << 8) | data[10].to_int()
  guard recipient_count >= 1 && recipient_count <= envelope_max_recipients else {
    raise InvalidFormat("recipient_count")
  }
  let chunk_size_u64 = read_u32_be_view(data, 11)
  guard chunk_size_u64 >= seal_min_chunk_size.to_uint64() &&
    chunk_size_u64 <= seal_max_chunk_size.to_uint64() else {
    raise InvalidFormat("chunk_size")
  }
  guard chunk_size_u64 <= limits.max_chunk_size.to_uint64() else {
    raise LimitExceeded("chunk_size")
  }
  let nonce_prefix = data[15:19].to_owned()
  let ephemeral_public_key = data[19:51].to_owned()
  validate_x25519_public_key(ephemeral_public_key, "ephemeral_public_key")
  let total_header_len = envelope_preamble_size +
    recipient_count * envelope_slot_size
  guard data.length() >= total_header_len else { raise TruncatedInput }
  let recipient_key_ids : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for i in 0..<recipient_count {
    let slot_offset = envelope_preamble_size + i * envelope_slot_size
    let id_hex = encode_key_hex(data[slot_offset:slot_offset + 8].to_owned())
    guard !seen.contains(id_hex) else {
      raise InvalidFormat("duplicate_recipient")
    }
    seen[id_hex] = true
    recipient_key_ids.push(id_hex)
  }
  {
    ephemeral_public_key,
    recipient_key_ids,
    chunk_size: chunk_size_u64.to_int(),
    nonce_prefix,
  }
}

///|
/// Seal `plaintext` into a deterministic `MLSENC02` multi-recipient X25519
/// ChaCha20-Poly1305 envelope for 1..=64 recipients.
pub fn seal_envelope(
  plaintext : Bytes,
  recipient_public_keys : Array[Bytes],
  ephemeral_secret : Bytes,
  content_key : Bytes,
  nonce_prefix : Bytes,
  options : SealOptions,
  limits : SealLimits,
) -> Bytes raise CryptoError {
  validate_seal_limits(limits)
  guard options.chunk_size >= seal_min_chunk_size &&
    options.chunk_size <= seal_max_chunk_size else {
    raise InvalidOptions("chunk_size")
  }
  guard options.chunk_size <= limits.max_chunk_size else {
    raise LimitExceeded("chunk_size")
  }
  let recipient_count = recipient_public_keys.length()
  guard recipient_count >= 1 && recipient_count <= envelope_max_recipients else {
    raise InvalidOptions("recipient_count")
  }
  guard content_key.length() == 32 && !is_all_zero(content_key[:]) else {
    raise InvalidKey("content_key")
  }
  guard nonce_prefix.length() == 4 else { raise InvalidOptions("nonce_prefix") }
  guard plaintext.length().to_int64() <= limits.max_input_bytes else {
    raise LimitExceeded("max_input_bytes")
  }
  let eph_kp = x25519_keypair_from_secret(ephemeral_secret)
  let eph_pub = eph_kp.public_key

  let header_len = envelope_preamble_size + recipient_count * envelope_slot_size
  let chunk_size = options.chunk_size
  let plain_len = plaintext.length()
  let num_chunks = if plain_len == 0 {
    1
  } else {
    (plain_len - 1) / chunk_size + 1
  }
  let overhead = header_len.to_int64() +
    num_chunks.to_int64() * (seal_chunk_header_size + seal_tag_size).to_int64()
  guard plain_len.to_int64() <= 9223372036854775807L - overhead &&
    overhead + plain_len.to_int64() <= limits.max_output_bytes &&
    overhead + plain_len.to_int64() <= 2147483647L else {
    raise LimitExceeded("max_output_bytes")
  }

  let header_buf = FixedArray::make(header_len, b'\x00')
  for i in 0..<8 {
    header_buf[i] = envelope_magic_bytes[i]
  }
  header_buf[8] = envelope_version_byte
  header_buf[9] = ((recipient_count >> 8) & 0xff).to_byte()
  header_buf[10] = (recipient_count & 0xff).to_byte()
  write_u32_be(header_buf, 11, chunk_size.to_uint64())
  for i in 0..<4 {
    header_buf[15 + i] = nonce_prefix[i]
  }
  for i in 0..<32 {
    header_buf[19 + i] = eph_pub[i]
  }

  let seen_key_ids : Map[String, Bool] = Map([])
  for i in 0..<recipient_count {
    let recipient_pub = recipient_public_keys[i]
    let id_raw = x25519_key_id_raw(recipient_pub, "recipient_public_key")
    let id_hex = encode_key_hex(id_raw)
    guard !seen_key_ids.contains(id_hex) else {
      raise InvalidOptions("duplicate_recipient")
    }
    seen_key_ids[id_hex] = true
    let shared = @x25519.shared(ephemeral_secret[:], recipient_pub[:]) catch {
      _ => raise InvalidKey("recipient_public_key")
    }
    let wrap_key = derive_wrap_key(shared, eph_pub, recipient_pub)
    let wrap_aead = @chachapoly.ChaChaPoly::new(wrap_key[:]) catch {
      _ => raise InvalidKey("wrap_key")
    }
    let wrap_nonce = make_wrap_nonce(nonce_prefix, i)
    let wrap_aad = make_wrap_aad(eph_pub, recipient_pub, i)
    let wrapped_cek = wrap_aead.seal(
      nonce=wrap_nonce[:],
      plain=content_key[:],
      aad=wrap_aad[:],
    )
    guard wrapped_cek.length() == 48 else {
      raise InvalidFormat("wrapped_cek_length")
    }
    let slot_offset = envelope_preamble_size + i * envelope_slot_size
    for j in 0..<8 {
      header_buf[slot_offset + j] = id_raw[j]
    }
    for j in 0..<48 {
      header_buf[slot_offset + 8 + j] = wrapped_cek[j]
    }
  }

  let header_bytes = Bytes::from_array(header_buf[:])
  let header_aad = @sha2.hash(header_bytes[:], kind=@sha2.Kind::Sha256)
  guard header_aad.length() == 32 else { raise InvalidFormat("sha256") }

  let cek_aead = @chachapoly.ChaChaPoly::new(content_key[:]) catch {
    _ => raise InvalidKey("content_key")
  }
  let out = @buffer.Buffer(
    capacity=header_len +
      plain_len +
      num_chunks * (seal_chunk_header_size + seal_tag_size),
  )
  out.write_bytes(header_bytes)

  let frame_hdr = FixedArray::make(seal_chunk_header_size, b'\x00')
  if plain_len == 0 {
    let nonce = make_envelope_chunk_nonce(nonce_prefix, 0UL)
    let aad = make_envelope_chunk_aad(header_aad, 0UL, b'\x01', 0)
    let ct = cek_aead.seal(nonce=nonce[:], plain=b""[:], aad=aad[:])
    write_u32_be(frame_hdr, 0, 0UL)
    frame_hdr[4] = b'\x01'
    out.write_bytes(Bytes::from_array(frame_hdr[:]))
    out.write_bytes(ct)
  } else {
    let mut pos = 0
    let mut chunk_index = 0UL
    while pos < plain_len {
      let rem = plain_len - pos
      let take = if rem > chunk_size { chunk_size } else { rem }
      let flags = if pos + take == plain_len { b'\x01' } else { b'\x00' }
      let nonce = make_envelope_chunk_nonce(nonce_prefix, chunk_index)
      let aad = make_envelope_chunk_aad(header_aad, chunk_index, flags, take)
      let ct = cek_aead.seal(
        nonce=nonce[:],
        plain=plaintext[pos:pos + take],
        aad=aad[:],
      )
      write_u32_be(frame_hdr, 0, take.to_uint64())
      frame_hdr[4] = flags
      out.write_bytes(Bytes::from_array(frame_hdr[:]))
      out.write_bytes(ct)
      pos = pos + take
      chunk_index = chunk_index + 1UL
    }
  }
  out.to_bytes()
}

///|
/// Unseal an `MLSENC02` multi-recipient envelope using one recipient's 32-byte
/// X25519 secret key, authenticating the full header, recipient slot, every
/// chunk frame, and rejecting truncation or trailing data.
pub fn unseal_envelope(
  ciphertext : Bytes,
  recipient_secret_key : Bytes,
  limits : SealLimits,
) -> Bytes raise CryptoError {
  validate_seal_limits(limits)
  let my_kp = x25519_keypair_from_secret(recipient_secret_key)
  let my_pub = my_kp.public_key
  let my_id_raw = x25519_key_id_raw(my_pub, "x25519_secret")
  guard ciphertext.length().to_int64() <= limits.max_input_bytes else {
    raise LimitExceeded("max_input_bytes")
  }
  let hdr = inspect_envelope_header(ciphertext[:], limits)
  let recipient_count = hdr.recipient_key_ids.length()
  let header_len = envelope_preamble_size + recipient_count * envelope_slot_size

  let shared = @x25519.shared(
    recipient_secret_key[:],
    hdr.ephemeral_public_key[:],
  ) catch {
    _ => raise AuthenticationFailed
  }
  let wrap_key = derive_wrap_key(shared, hdr.ephemeral_public_key, my_pub)
  let wrap_aead = @chachapoly.ChaChaPoly::new(wrap_key[:]) catch {
    _ => raise AuthenticationFailed
  }

  let mut unwrapped_cek : Bytes? = None
  for i in 0..<recipient_count {
    let slot_offset = envelope_preamble_size + i * envelope_slot_size
    let slot_id = ciphertext[slot_offset:slot_offset + 8]
    if @spec.eq(slot_id, my_id_raw[:]) {
      let wrapped_cek = ciphertext[slot_offset + 8:slot_offset +
        envelope_slot_size]
      let wrap_nonce = make_wrap_nonce(hdr.nonce_prefix, i)
      let wrap_aad = make_wrap_aad(hdr.ephemeral_public_key, my_pub, i)
      let plain_cek = wrap_aead.open(
        nonce=wrap_nonce[:],
        cipher=wrapped_cek,
        aad=wrap_aad[:],
      ) catch {
        _ => raise AuthenticationFailed
      }
      guard plain_cek.length() == 32 else { raise AuthenticationFailed }
      unwrapped_cek = Some(plain_cek)
      break
    }
  }
  let cek = match unwrapped_cek {
    Some(k) => k
    None => raise AuthenticationFailed
  }

  let header_aad = @sha2.hash(ciphertext[0:header_len], kind=@sha2.Kind::Sha256)
  guard header_aad.length() == 32 else { raise InvalidFormat("sha256") }
  let cek_aead = @chachapoly.ChaChaPoly::new(cek[:]) catch {
    _ => raise AuthenticationFailed
  }

  let out = @buffer.Buffer()
  let mut pos = header_len
  let mut chunk_index = 0UL
  let mut output_bytes = 0L
  let mut saw_final = false
  while !saw_final {
    guard ciphertext.length() - pos >= seal_chunk_header_size else {
      raise TruncatedInput
    }
    let plain_len_u64 = read_u32_be_view(ciphertext[:], pos)
    let flags = ciphertext[pos + 4]
    pos = pos + seal_chunk_header_size
    guard flags == b'\x00' || flags == b'\x01' else {
      raise InvalidFormat("chunk_final_flag")
    }
    guard plain_len_u64 <= hdr.chunk_size.to_uint64() else {
      raise InvalidFormat("chunk_length")
    }
    if flags == b'\x00' {
      guard plain_len_u64 >= 1UL else {
        raise InvalidFormat("empty_non_final_chunk")
      }
    }
    let plain_len = plain_len_u64.to_int()
    guard plain_len.to_int64() <= 9223372036854775807L - output_bytes &&
      output_bytes + plain_len.to_int64() <= limits.max_output_bytes else {
      raise LimitExceeded("max_output_bytes")
    }
    let cipher_len = plain_len + seal_tag_size
    guard ciphertext.length() - pos >= cipher_len else { raise TruncatedInput }
    let nonce = make_envelope_chunk_nonce(hdr.nonce_prefix, chunk_index)
    let aad = make_envelope_chunk_aad(header_aad, chunk_index, flags, plain_len)
    let plain_chunk = cek_aead.open(
      nonce=nonce[:],
      cipher=ciphertext[pos:pos + cipher_len],
      aad=aad[:],
    ) catch {
      _ => raise AuthenticationFailed
    }
    guard plain_chunk.length() == plain_len else { raise AuthenticationFailed }
    out.write_bytes(plain_chunk)
    output_bytes = output_bytes + plain_len.to_int64()
    pos = pos + cipher_len
    chunk_index = chunk_index + 1UL
    if flags == b'\x01' {
      saw_final = true
    }
  }
  guard pos == ciphertext.length() else { raise TrailingData }
  out.to_bytes()
}
