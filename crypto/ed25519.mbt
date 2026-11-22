// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Ed25519 signing key pair derived from a 32-byte RFC 8032 seed.
#derive(Eq)
pub(all) struct Ed25519KeyPair {
  seed : Bytes
  public_key : Bytes
}

///|
pub extend Ed25519KeyPair with Eq::{equal, not_equal}

///|
/// Canonical publisher signature metadata and Ed25519 signature over
/// `"moonlibsync-ed25519-v1\x00" + payload_length + ":" + payload_sha256`.
#derive(Eq)
pub(all) struct PublisherSignature {
  algorithm : String
  key_id : String
  public_key_hex : String
  payload_length : Int64
  payload_sha256 : String
  signature_hex : String
}

///|
pub extend PublisherSignature with Eq::{equal, not_equal}

///|
let ed25519_p : BigInt = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEDN

///|
let ed25519_d : BigInt = 0x52036CEE2B6FFE738CC740797779E89800700A4D4141D8AB75EB4DCA135978A3N

///|
let ed25519_sqrt_m1 : BigInt = 0x2B8324804FC1DF0B2B4D00993DFBD7A72F431806AD2FE478C4EE1B274A0EA0B0N

///|
let ed25519_p_minus_2 : BigInt = ed25519_p - 2

///|
let ed25519_p_plus_3_div_8 : BigInt = (ed25519_p + 3) / 8

///|
fn ed_mod_p(a : BigInt) -> BigInt {
  let m = a % ed25519_p
  if m < (0 : BigInt) {
    m + ed25519_p
  } else {
    m
  }
}

///|
fn ed_inv(a : BigInt) -> BigInt {
  ed_mod_p(a).pow(ed25519_p_minus_2, modulus=ed25519_p)
}

///|
fn ed_double(pt : (BigInt, BigInt)) -> (BigInt, BigInt) {
  let (x, y) = pt
  let xx = ed_mod_p(x * x)
  let yy = ed_mod_p(y * y)
  let dxy = ed_mod_p(ed25519_d * xx * yy)
  let x2 = ed_mod_p(2 * x * y * ed_inv(ed_mod_p(1 + dxy)))
  let y2 = ed_mod_p((yy + xx) * ed_inv(ed_mod_p(1 - dxy)))
  (x2, y2)
}

///|
/// Strict RFC 8032 §5.1.3 compressed Ed25519 point decoder.
/// Rejects non-canonical `y >= p`, off-curve `y`, and non-canonical `(0, y)` with sign bit 1.
fn decode_ed25519_point_strict(raw : BytesView) -> (BigInt, BigInt)? {
  if raw.length() != 32 {
    return None
  }
  let sign = (raw[31].to_int() >> 7) & 1
  let be = FixedArray::make(32, b'\x00')
  be[0] = (raw[31].to_int() & 0x7F).to_byte()
  for i in 0..<31 {
    be[31 - i] = raw[i]
  }
  let y = BigInt::from_octets(Bytes::from_array(be[:])[:])
  if y >= ed25519_p {
    return None
  }
  let yy = ed_mod_p(y * y)
  let u = ed_mod_p(yy - 1)
  let v = ed_mod_p(ed25519_d * yy + 1)
  if v == (0 : BigInt) {
    return None
  }
  let xx = ed_mod_p(u * ed_inv(v))
  if xx == (0 : BigInt) {
    if sign == 1 {
      return None
    }
    return Some(((0 : BigInt), y))
  }
  let mut x = xx.pow(ed25519_p_plus_3_div_8, modulus=ed25519_p)
  if ed_mod_p(x * x - xx) != (0 : BigInt) {
    x = ed_mod_p(x * ed25519_sqrt_m1)
    if ed_mod_p(x * x - xx) != (0 : BigInt) {
      return None
    }
  }
  let parity = if x % 2 == (1 : BigInt) { 1 } else { 0 }
  if parity != sign {
    x = ed25519_p - x
  }
  Some((x, y))
}

///|
fn is_small_order_point(pt : (BigInt, BigInt)) -> Bool {
  let p2 = ed_double(pt)
  let p4 = ed_double(p2)
  let p8 = ed_double(p4)
  p8.0 == (0 : BigInt) && p8.1 == (1 : BigInt)
}

///|
/// Encode raw bytes as strict lowercase hexadecimal.
pub fn encode_key_hex(bytes : Bytes) -> String {
  @hex.encode(bytes)
}

///|
fn hex_nibble_strict(code_unit : Int32) -> Int32? {
  if code_unit >= 0x30 && code_unit <= 0x39 {
    Some(code_unit - 0x30)
  } else if code_unit >= 0x61 && code_unit <= 0x66 {
    Some(code_unit - 0x61 + 10)
  } else {
    None
  }
}

///|
/// Decode strict lowercase hexadecimal of exact byte length `expected_len`.
/// Rejects wrong length, uppercase hex, whitespace, and any non-hex characters.
pub fn decode_key_hex(
  text : String,
  expected_len : Int32,
  field : String,
) -> Bytes raise CryptoError {
  guard expected_len >= 0 && expected_len <= 1073741823 else {
    raise InvalidOptions("expected_len")
  }
  guard text.length() == expected_len * 2 else { raise InvalidFormat(field) }
  let out = FixedArray::make(expected_len, b'\x00')
  for i in 0..<expected_len {
    let hi = match hex_nibble_strict(text[i * 2].to_int()) {
      Some(v) => v
      None => raise InvalidFormat(field)
    }
    let lo = match hex_nibble_strict(text[i * 2 + 1].to_int()) {
      Some(v) => v
      None => raise InvalidFormat(field)
    }
    out[i] = ((hi << 4) | lo).to_byte()
  }
  Bytes::from_array(out[:])
}

///|
fn validate_sha256_hex(text : String, field : String) -> Unit raise CryptoError {
  guard text.length() == 64 else { raise InvalidFormat(field) }
  for i in 0..<64 {
    guard hex_nibble_strict(text[i].to_int()) is Some(_) else {
      raise InvalidFormat(field)
    }
  }
}

///|
/// Derive an `Ed25519KeyPair` from a 32-byte RFC 8032 seed.
pub fn keypair_from_seed(seed : Bytes) -> Ed25519KeyPair raise CryptoError {
  guard seed.length() == @ed25519.key_size else {
    raise InvalidKey("seed_length")
  }
  let sk = @ed25519.PrivateKey::new(seed[:]) catch {
    _ => raise InvalidKey("seed")
  }
  let public_key = sk.public().bytes()
  validate_public_key(public_key)
  { seed: sk.bytes(), public_key, }
}

///|
/// Validate that `public_key` is a canonical 32-byte non-small-order Ed25519 point.
pub fn validate_public_key(public_key : Bytes) -> Unit raise CryptoError {
  guard public_key.length() == @ed25519.key_size else {
    raise InvalidKey("public_key_length")
  }
  let _ = @ed25519.PublicKey::new(public_key[:]) catch {
    _ => raise InvalidKey("public_key")
  }
  let pt = match decode_ed25519_point_strict(public_key[:]) {
    Some(p) => p
    None => raise InvalidKey("public_key_point")
  }
  guard !is_small_order_point(pt) else {
    raise InvalidKey("public_key_low_order")
  }
}

///|
/// Compute the 16-character lowercase hex key identifier (first 8 bytes of
/// SHA-256 of the 32-byte Ed25519 public key).
pub fn key_id_from_public_key(public_key : Bytes) -> String raise CryptoError {
  validate_public_key(public_key)
  let digest = @sha2.hash(public_key[:], kind=@sha2.Kind::Sha256)
  guard digest.length() == 32 else { raise InvalidFormat("sha256") }
  encode_key_hex(digest[0:8].to_owned())
}

///|
fn build_signing_message(
  payload_length : Int64,
  payload_sha256 : String,
) -> Bytes {
  let out = @buffer.Buffer(capacity=104)
  out.write_bytes(b"moonlibsync-ed25519-v1\x00")
  out.write_bytes(@utf8.encode(payload_length.to_string()))
  out.write_byte(b':')
  out.write_bytes(@utf8.encode(payload_sha256))
  out.to_bytes()
}

///|
/// Sign a `(payload_length, payload_sha256)` pair with a 32-byte Ed25519 seed.
pub fn sign_digest(
  seed : Bytes,
  payload_length : Int64,
  payload_sha256 : String,
) -> PublisherSignature raise CryptoError {
  guard seed.length() == @ed25519.key_size else {
    raise InvalidKey("seed_length")
  }
  guard payload_length >= 0L else { raise InvalidOptions("payload_length") }
  validate_sha256_hex(payload_sha256, "payload_sha256")
  let sk = @ed25519.PrivateKey::new(seed[:]) catch {
    _ => raise InvalidKey("seed")
  }
  let public_key = sk.public().bytes()
  let key_id = key_id_from_public_key(public_key)
  let msg = build_signing_message(payload_length, payload_sha256)
  let sig_bytes = sk.sign(msg[:])
  guard sig_bytes.length() == @ed25519.sig_size else {
    raise InvalidSignature("ed25519_length")
  }
  {
    algorithm: "ed25519",
    key_id,
    public_key_hex: encode_key_hex(public_key),
    payload_length,
    payload_sha256,
    signature_hex: encode_key_hex(sig_bytes),
  }
}

///|
/// Hash `payload` with SHA-256 and produce a `PublisherSignature`.
pub fn sign_bytes(
  seed : Bytes,
  payload : Bytes,
) -> PublisherSignature raise CryptoError {
  let digest = @sha2.hash(payload[:], kind=@sha2.Kind::Sha256)
  guard digest.length() == 32 else { raise InvalidFormat("sha256") }
  sign_digest(seed, payload.length().to_int64(), encode_key_hex(digest))
}

///|
fn validate_publisher_signature_fields(
  sig : PublisherSignature,
) -> (Bytes, Bytes) raise CryptoError {
  guard sig.algorithm == "ed25519" else { raise InvalidSignature("algorithm") }
  let pk_bytes = decode_key_hex(sig.public_key_hex, 32, "public_key")
  let expected_key_id = key_id_from_public_key(pk_bytes)
  guard sig.key_id == expected_key_id else { raise InvalidSignature("key_id") }
  let sig_bytes = decode_key_hex(sig.signature_hex, 64, "signature")
  guard sig.payload_length >= 0L else { raise InvalidFormat("payload_length") }
  validate_sha256_hex(sig.payload_sha256, "payload_sha256")
  (pk_bytes, sig_bytes)
}

///|
/// Verify a `PublisherSignature` against a non-empty trusted publisher key set
/// and an expected `(payload_length, payload_sha256)` pair.
pub fn verify_digest(
  sig : PublisherSignature,
  trusted_pubkeys : Array[Bytes],
  payload_length : Int64,
  payload_sha256 : String,
) -> Unit raise CryptoError {
  let (pk_bytes, sig_bytes) = validate_publisher_signature_fields(sig)
  guard trusted_pubkeys.length() > 0 else {
    raise InvalidOptions("trusted_pubkeys")
  }
  let mut trusted = false
  for tk in trusted_pubkeys {
    validate_public_key(tk)
    if @spec.eq(pk_bytes[:], tk[:]) {
      trusted = true
    }
  }
  guard trusted else { raise UntrustedKey(sig.key_id) }
  guard payload_length >= 0L else { raise InvalidOptions("payload_length") }
  validate_sha256_hex(payload_sha256, "payload_sha256")
  guard sig.payload_length == payload_length else {
    raise DigestMismatch("payload_length")
  }
  guard @spec.eq(
    @utf8.encode(sig.payload_sha256)[:],
    @utf8.encode(payload_sha256)[:],
  ) else {
    raise DigestMismatch("payload_sha256")
  }
  guard decode_ed25519_point_strict(sig_bytes[0:32]) is Some(_) else {
    raise InvalidSignature("ed25519")
  }
  let pk = @ed25519.PublicKey::new(pk_bytes[:]) catch {
    _ => raise InvalidKey("public_key")
  }
  let msg = build_signing_message(payload_length, payload_sha256)
  guard pk.verify(msg[:], sig_bytes[:]) else {
    raise InvalidSignature("ed25519")
  }
}

///|
/// Hash `payload` with SHA-256 and verify `sig` against `trusted_pubkeys`.
pub fn verify_bytes(
  sig : PublisherSignature,
  trusted_pubkeys : Array[Bytes],
  payload : Bytes,
) -> Unit raise CryptoError {
  let digest = @sha2.hash(payload[:], kind=@sha2.Kind::Sha256)
  guard digest.length() == 32 else { raise InvalidFormat("sha256") }
  verify_digest(
    sig,
    trusted_pubkeys,
    payload.length().to_int64(),
    encode_key_hex(digest),
  )
}

///|
fn parse_strict_nonneg_decimal(
  text : String,
  field : String,
) -> Int64 raise CryptoError {
  guard text.length() > 0 && (text == "0" || !text.has_prefix("0")) else {
    raise InvalidFormat(field)
  }
  let mut result = 0L
  for i in 0..<text.length() {
    let code = text[i].to_int()
    guard code >= 0x30 && code <= 0x39 else { raise InvalidFormat(field) }
    let digit = (code - 0x30).to_int64()
    guard result <= (9223372036854775807L - digit) / 10L else {
      raise InvalidFormat(field)
    }
    result = result * 10L + digit
  }
  result
}

///|
fn json_string_field(
  fields : Map[String, @json.Json],
  key : String,
) -> String raise CryptoError {
  guard fields.get(key) is Some(@json.Json::String(text)) else {
    raise InvalidFormat(key)
  }
  text
}

///|
/// Encode a validated `PublisherSignature` into the canonical Schema 4 JSON
/// envelope (`schema_version: 1`, `kind: "moonlibsync-signature"`, UTF-8 without BOM + LF).
pub fn encode_publisher_signature(
  sig : PublisherSignature,
) -> Bytes raise CryptoError {
  let _ = validate_publisher_signature_fields(sig)
  @utf8.encode(
    "{\"schema_version\":1,\"kind\":\"moonlibsync-signature\",\"algorithm\":\"ed25519\",\"key_id\":\"\{sig.key_id}\",\"public_key\":\"\{sig.public_key_hex}\",\"payload_length\":\"\{sig.payload_length}\",\"payload_sha256\":\"\{sig.payload_sha256}\",\"signature\":\"\{sig.signature_hex}\"}\n",
  )
}

///|
/// Strictly parse a bounded (`<= 8192` bytes), UTF-8 without BOM, duplicate-key-free
/// Schema 4 publisher signature JSON envelope.
pub fn parse_publisher_signature(
  bytes : Bytes,
) -> PublisherSignature raise CryptoError {
  guard bytes.length() <= 8192 else {
    raise LimitExceeded("signature_json_bytes")
  }
  let text = @utf8.decode(bytes, ignore_bom=false) catch {
    _ => raise InvalidFormat("utf8")
  }
  guard !(bytes.length() >= 3 &&
    bytes[0] == b'\xef' &&
    bytes[1] == b'\xbb' &&
    bytes[2] == b'\xbf') else {
    raise InvalidFormat("utf8_bom")
  }
  let value = @json.parse(
    text,
    max_nesting_depth=2,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    @json.ParseError::DepthLimitExceeded =>
      raise LimitExceeded("signature_json_depth")
    _ => raise InvalidFormat("json")
  }
  guard value is @json.Json::Object(fields) else {
    raise InvalidFormat("schema")
  }
  let required_keys = [
    "schema_version", "kind", "algorithm", "key_id", "public_key", "payload_length",
    "payload_sha256", "signature",
  ]
  guard fields.length() == required_keys.length() else {
    raise InvalidFormat("schema")
  }
  for key in required_keys {
    guard fields.contains(key) else { raise InvalidFormat("schema") }
  }
  guard fields.get("schema_version")
    is Some(@json.Json::Number(1.0, repr=Some("1"))) else {
    raise InvalidFormat("schema_version")
  }
  guard fields.get("kind") is Some(@json.Json::String("moonlibsync-signature")) else {
    raise InvalidFormat("kind")
  }
  let sig : PublisherSignature = {
    algorithm: json_string_field(fields, "algorithm"),
    key_id: json_string_field(fields, "key_id"),
    public_key_hex: json_string_field(fields, "public_key"),
    payload_length: parse_strict_nonneg_decimal(
      json_string_field(fields, "payload_length"),
      "payload_length",
    ),
    payload_sha256: json_string_field(fields, "payload_sha256"),
    signature_hex: json_string_field(fields, "signature"),
  }
  let _ = validate_publisher_signature_fields(sig)
  sig
}
