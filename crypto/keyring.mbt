// SPDX-License-Identifier: LGPL-2.1-or-later

///|
let keyring_max_json_bytes : Int32 = 65536

///|
let signature_bundle_max_json_bytes : Int32 = 131072

///|
let signature_bundle_max_count : Int32 = 64

///|
let keyring_max_trusted_keys : Int32 = 64

///|
let keyring_max_revoked_ids : Int32 = 256

///|
/// Ed25519 trust keyring with revocation list and M-of-N threshold quorum policy.
#derive(Eq)
pub(all) struct TrustKeyring {
  trusted_keys : Array[Bytes]
  revoked_key_ids : Array[String]
  min_quorum : Int32
}

///|
pub extend TrustKeyring with Eq::{equal, not_equal}

///|
/// Multi-signer Ed25519 signature bundle binding one `(payload_length, payload_sha256)`.
#derive(Eq)
pub(all) struct SignatureBundle {
  payload_length : Int64
  payload_sha256 : String
  signatures : Array[PublisherSignature]
}

///|
pub extend SignatureBundle with Eq::{equal, not_equal}

///|
/// Verification report produced by threshold quorum verification.
#derive(Eq)
pub(all) struct QuorumVerifyReport {
  verified_key_ids : Array[String]
  rejected_key_ids : Array[String]
  revoked_hits : Array[String]
  required_quorum : Int32
}

///|
pub extend QuorumVerifyReport with Eq::{equal, not_equal}

///|
fn validate_key_id_hex(text : String, field : String) -> Unit raise CryptoError {
  guard text.length() == 16 else { raise InvalidFormat(field) }
  for i in 0..<16 {
    guard hex_nibble_strict(text[i].to_int()) is Some(_) else {
      raise InvalidFormat(field)
    }
  }
}

///|
fn parse_strict_json_object(
  bytes : Bytes,
  max_bytes : Int32,
  size_field : String,
  depth_limit : Int32,
  depth_field : String,
) -> Map[String, @json.Json] raise CryptoError {
  guard bytes.length() <= max_bytes else { raise LimitExceeded(size_field) }
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
    max_nesting_depth=depth_limit,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    @json.ParseError::DepthLimitExceeded => raise LimitExceeded(depth_field)
    _ => raise InvalidFormat("json")
  }
  guard value is @json.Json::Object(fields) else {
    raise InvalidFormat("schema")
  }
  fields
}

///|
fn validate_exact_json_keys(
  fields : Map[String, @json.Json],
  required_keys : Array[String],
  field : String,
) -> Unit raise CryptoError {
  guard fields.length() == required_keys.length() else {
    raise InvalidFormat(field)
  }
  for key in required_keys {
    guard fields.contains(key) else { raise InvalidFormat(field) }
  }
}

///|
fn json_int32_field(
  fields : Map[String, @json.Json],
  key : String,
) -> Int32 raise CryptoError {
  guard fields.get(key) is Some(@json.Json::Number(_, repr=Some(repr_str))) else {
    raise InvalidFormat(key)
  }
  let value = parse_strict_nonneg_decimal(repr_str, key)
  guard value <= 2147483647L else { raise InvalidFormat(key) }
  value.to_int()
}

///|
/// Construct and validate a deterministic `TrustKeyring`.
/// Validates every Ed25519 public key, rejects duplicates and malformed revoked
/// key IDs, ensures `1 <= min_quorum <= active_count`, and sorts `trusted_keys`
/// by key ID and `revoked_key_ids` lexicographically.
pub fn create_trust_keyring(
  trusted_keys : Array[Bytes],
  revoked_key_ids : Array[String],
  min_quorum : Int32,
) -> TrustKeyring raise CryptoError {
  guard trusted_keys.length() <= keyring_max_trusted_keys else {
    raise LimitExceeded("trusted_keys")
  }
  guard revoked_key_ids.length() <= keyring_max_revoked_ids else {
    raise LimitExceeded("revoked_key_ids")
  }
  let seen_keys : Map[String, Bool] = Map([])
  let keyed : Array[(String, Bytes)] = []
  for pk in trusted_keys {
    let key_id = key_id_from_public_key(pk)
    guard !seen_keys.contains(key_id) else {
      raise InvalidOptions("duplicate_key")
    }
    seen_keys[key_id] = true
    keyed.push((key_id, pk))
  }

  let seen_revoked : Map[String, Bool] = Map([])
  let revoked_sorted : Array[String] = []
  for rev_id in revoked_key_ids {
    validate_key_id_hex(rev_id, "revoked_key_id")
    guard !seen_revoked.contains(rev_id) else {
      raise InvalidOptions("duplicate_revoked_key_id")
    }
    seen_revoked[rev_id] = true
    revoked_sorted.push(rev_id)
  }

  let mut active_count = 0
  for item in keyed {
    let (key_id, _) = item
    if !seen_revoked.contains(key_id) {
      active_count = active_count + 1
    }
  }
  guard min_quorum >= 1 && min_quorum <= active_count else {
    raise InvalidOptions("min_quorum")
  }

  keyed.sort_by((a, b) => a.0.compare(b.0))
  revoked_sorted.sort_by((a, b) => a.compare(b))
  let sorted_keys : Array[Bytes] = []
  for item in keyed {
    sorted_keys.push(item.1)
  }
  { trusted_keys: sorted_keys, revoked_key_ids: revoked_sorted, min_quorum, }
}

///|
/// Encode a validated `TrustKeyring` as canonical Schema 4 JSON (`schema: 4`,
/// `kind: "moonlibsync-keyring"`, UTF-8 without BOM + LF).
pub fn encode_trust_keyring(keyring : TrustKeyring) -> Bytes raise CryptoError {
  let normalized = create_trust_keyring(
    keyring.trusted_keys,
    keyring.revoked_key_ids,
    keyring.min_quorum,
  )
  let out = @buffer.Buffer(capacity=256)
  out.write_bytes(
    @utf8.encode(
      "{\"schema\":4,\"kind\":\"moonlibsync-keyring\",\"min_quorum\":\{normalized.min_quorum},\"trusted_keys_hex\":[",
    ),
  )
  for i in 0..<normalized.trusted_keys.length() {
    if i > 0 {
      out.write_byte(b',')
    }
    out.write_byte(b'"')
    out.write_bytes(@utf8.encode(encode_key_hex(normalized.trusted_keys[i])))
    out.write_byte(b'"')
  }
  out.write_bytes(b"],\"revoked_key_ids\":[")
  for i in 0..<normalized.revoked_key_ids.length() {
    if i > 0 {
      out.write_byte(b',')
    }
    out.write_byte(b'"')
    out.write_bytes(@utf8.encode(normalized.revoked_key_ids[i]))
    out.write_byte(b'"')
  }
  out.write_bytes(b"]}\n")
  out.to_bytes()
}

///|
/// Strictly parse a Schema 4 `TrustKeyring` JSON document, rejecting unknown
/// fields, duplicate keys, invalid hex, malformed Ed25519 keys, and invalid quorum.
pub fn parse_trust_keyring(bytes : Bytes) -> TrustKeyring raise CryptoError {
  let fields = parse_strict_json_object(
    bytes, keyring_max_json_bytes, "keyring_json_bytes", 3, "keyring_json_depth",
  )
  validate_exact_json_keys(
    fields,
    ["schema", "kind", "min_quorum", "trusted_keys_hex", "revoked_key_ids"],
    "schema",
  )
  guard fields.get("schema") is Some(@json.Json::Number(4.0, repr=Some("4"))) else {
    raise InvalidFormat("schema")
  }
  guard fields.get("kind") is Some(@json.Json::String("moonlibsync-keyring")) else {
    raise InvalidFormat("kind")
  }
  let min_quorum = json_int32_field(fields, "min_quorum")
  guard fields.get("trusted_keys_hex") is Some(@json.Json::Array(key_items)) else {
    raise InvalidFormat("trusted_keys_hex")
  }
  guard key_items.length() <= keyring_max_trusted_keys else {
    raise LimitExceeded("trusted_keys")
  }
  let trusted_keys : Array[Bytes] = []
  for item in key_items {
    guard item is @json.Json::String(hex_str) else {
      raise InvalidFormat("trusted_keys_hex")
    }
    trusted_keys.push(decode_key_hex(hex_str, 32, "trusted_keys_hex"))
  }
  guard fields.get("revoked_key_ids") is Some(@json.Json::Array(rev_items)) else {
    raise InvalidFormat("revoked_key_ids")
  }
  guard rev_items.length() <= keyring_max_revoked_ids else {
    raise LimitExceeded("revoked_key_ids")
  }
  let revoked_key_ids : Array[String] = []
  for item in rev_items {
    guard item is @json.Json::String(id_str) else {
      raise InvalidFormat("revoked_key_ids")
    }
    revoked_key_ids.push(id_str)
  }
  create_trust_keyring(trusted_keys, revoked_key_ids, min_quorum)
}

///|
/// Construct and validate a multi-signer `SignatureBundle` (1..=64 unique signers
/// sharing identical `(payload_length, payload_sha256)`).
pub fn create_signature_bundle(
  signatures : Array[PublisherSignature],
) -> SignatureBundle raise CryptoError {
  guard signatures.length() >= 1 &&
    signatures.length() <= signature_bundle_max_count else {
    raise InvalidOptions("signature_count")
  }
  let _ = validate_publisher_signature_fields(signatures[0])
  let payload_length = signatures[0].payload_length
  let payload_sha256 = signatures[0].payload_sha256
  let seen_signers : Map[String, Bool] = Map([])
  let copied : Array[PublisherSignature] = []
  for sig in signatures {
    let _ = validate_publisher_signature_fields(sig)
    guard sig.payload_length == payload_length &&
      sig.payload_sha256 == payload_sha256 else {
      raise DigestMismatch("bundle_payload_mismatch")
    }
    guard !seen_signers.contains(sig.key_id) else {
      raise InvalidSignature("duplicate_signer")
    }
    seen_signers[sig.key_id] = true
    copied.push(sig)
  }
  { payload_length, payload_sha256, signatures: copied, }
}

///|
fn validate_signature_bundle(
  bundle : SignatureBundle,
) -> SignatureBundle raise CryptoError {
  guard bundle.payload_length >= 0L else {
    raise InvalidFormat("payload_length")
  }
  validate_sha256_hex(bundle.payload_sha256, "payload_sha256")
  let validated = create_signature_bundle(bundle.signatures)
  guard validated.payload_length == bundle.payload_length &&
    validated.payload_sha256 == bundle.payload_sha256 else {
    raise DigestMismatch("bundle_payload_mismatch")
  }
  validated
}

///|
/// Encode a validated `SignatureBundle` as canonical Schema 4 JSON (`schema: 4`,
/// `kind: "moonlibsync-signature-bundle"`, UTF-8 without BOM + LF).
pub fn encode_signature_bundle(
  bundle : SignatureBundle,
) -> Bytes raise CryptoError {
  let valid = validate_signature_bundle(bundle)
  let out = @buffer.Buffer(capacity=512)
  out.write_bytes(
    @utf8.encode(
      "{\"schema\":4,\"kind\":\"moonlibsync-signature-bundle\",\"payload_length\":\"\{valid.payload_length}\",\"payload_sha256\":\"\{valid.payload_sha256}\",\"signatures\":[",
    ),
  )
  for i in 0..<valid.signatures.length() {
    if i > 0 {
      out.write_byte(b',')
    }
    let sig = valid.signatures[i]
    out.write_bytes(
      @utf8.encode(
        "{\"algorithm\":\"ed25519\",\"key_id\":\"\{sig.key_id}\",\"public_key\":\"\{sig.public_key_hex}\",\"payload_length\":\"\{sig.payload_length}\",\"payload_sha256\":\"\{sig.payload_sha256}\",\"signature\":\"\{sig.signature_hex}\"}",
      ),
    )
  }
  out.write_bytes(b"]}\n")
  out.to_bytes()
}

///|
/// Strictly parse a Schema 4 `SignatureBundle` JSON document.
pub fn parse_signature_bundle(
  bytes : Bytes,
) -> SignatureBundle raise CryptoError {
  let fields = parse_strict_json_object(
    bytes, signature_bundle_max_json_bytes, "signature_bundle_json_bytes", 4, "signature_bundle_json_depth",
  )
  validate_exact_json_keys(
    fields,
    ["schema", "kind", "payload_length", "payload_sha256", "signatures"],
    "schema",
  )
  guard fields.get("schema") is Some(@json.Json::Number(4.0, repr=Some("4"))) else {
    raise InvalidFormat("schema")
  }
  guard fields.get("kind")
    is Some(@json.Json::String("moonlibsync-signature-bundle")) else {
    raise InvalidFormat("kind")
  }
  let payload_length = parse_strict_nonneg_decimal(
    json_string_field(fields, "payload_length"),
    "payload_length",
  )
  let payload_sha256 = json_string_field(fields, "payload_sha256")
  validate_sha256_hex(payload_sha256, "payload_sha256")
  guard fields.get("signatures") is Some(@json.Json::Array(sig_items)) else {
    raise InvalidFormat("signatures")
  }
  let sig_required_keys = [
    "algorithm", "key_id", "public_key", "payload_length", "payload_sha256", "signature",
  ]
  let sigs : Array[PublisherSignature] = []
  for item in sig_items {
    guard item is @json.Json::Object(sig_fields) else {
      raise InvalidFormat("signatures")
    }
    validate_exact_json_keys(sig_fields, sig_required_keys, "signature_schema")
    let sig : PublisherSignature = {
      algorithm: json_string_field(sig_fields, "algorithm"),
      key_id: json_string_field(sig_fields, "key_id"),
      public_key_hex: json_string_field(sig_fields, "public_key"),
      payload_length: parse_strict_nonneg_decimal(
        json_string_field(sig_fields, "payload_length"),
        "payload_length",
      ),
      payload_sha256: json_string_field(sig_fields, "payload_sha256"),
      signature_hex: json_string_field(sig_fields, "signature"),
    }
    sigs.push(sig)
  }
  let bundle = create_signature_bundle(sigs)
  guard bundle.payload_length == payload_length &&
    bundle.payload_sha256 == payload_sha256 else {
    raise DigestMismatch("bundle_payload_mismatch")
  }
  bundle
}

///|
/// Verify an M-of-N Ed25519 signature bundle against a `TrustKeyring` and an
/// expected `(payload_length, payload_sha256)` pair, enforcing revocations.
pub fn verify_quorum_digest(
  bundle : SignatureBundle,
  keyring : TrustKeyring,
  payload_length : Int64,
  payload_sha256 : String,
) -> QuorumVerifyReport raise CryptoError {
  let valid_keyring = create_trust_keyring(
    keyring.trusted_keys,
    keyring.revoked_key_ids,
    keyring.min_quorum,
  )
  let valid_bundle = validate_signature_bundle(bundle)
  guard payload_length >= 0L else { raise InvalidOptions("payload_length") }
  validate_sha256_hex(payload_sha256, "payload_sha256")
  guard valid_bundle.payload_length == payload_length else {
    raise DigestMismatch("payload_length")
  }
  guard @spec.eq(
    @utf8.encode(valid_bundle.payload_sha256)[:],
    @utf8.encode(payload_sha256)[:],
  ) else {
    raise DigestMismatch("payload_sha256")
  }

  let revoked_set : Map[String, Bool] = Map([])
  for rev_id in valid_keyring.revoked_key_ids {
    revoked_set[rev_id] = true
  }
  let trusted_by_id : Map[String, Bytes] = Map([])
  for tk in valid_keyring.trusted_keys {
    let tk_id = encode_key_hex(
      @sha2.hash(tk[:], kind=@sha2.Kind::Sha256)[0:8].to_owned(),
    )
    trusted_by_id[tk_id] = tk
  }
  let verified_seen : Map[String, Bool] = Map([])
  let verified_key_ids : Array[String] = []
  let rejected_key_ids : Array[String] = []
  let revoked_hits : Array[String] = []

  for sig in valid_bundle.signatures {
    if revoked_set.contains(sig.key_id) {
      revoked_hits.push(sig.key_id)
      rejected_key_ids.push(sig.key_id)
    } else {
      let ok = match trusted_by_id.get(sig.key_id) {
        Some(trusted_pk) =>
          try {
            let (pk_bytes, sig_bytes) = validate_publisher_signature_fields(sig)
            verify_digest_with_validated_key(
              sig, pk_bytes, sig_bytes, trusted_pk, payload_length, payload_sha256,
            )
            true
          } catch {
            _ => false
          }
        None => false
      }
      if ok {
        if !verified_seen.contains(sig.key_id) {
          verified_seen[sig.key_id] = true
          verified_key_ids.push(sig.key_id)
        }
      } else {
        rejected_key_ids.push(sig.key_id)
      }
    }
  }

  guard verified_key_ids.length() >= valid_keyring.min_quorum else {
    raise UntrustedKey("quorum_not_met")
  }
  {
    verified_key_ids,
    rejected_key_ids,
    revoked_hits,
    required_quorum: valid_keyring.min_quorum,
  }
}

///|
/// Hash `payload` with SHA-256 and verify a `SignatureBundle` against `keyring`.
pub fn verify_quorum_bytes(
  bundle : SignatureBundle,
  keyring : TrustKeyring,
  payload : Bytes,
) -> QuorumVerifyReport raise CryptoError {
  let digest = @sha2.hash(payload[:], kind=@sha2.Kind::Sha256)
  guard digest.length() == 32 else { raise InvalidFormat("sha256") }
  verify_quorum_digest(
    bundle,
    keyring,
    payload.length().to_int64(),
    encode_key_hex(digest),
  )
}
