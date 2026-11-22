// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn expect_crypto_err(
  action : () -> Unit raise @crypto.CryptoError,
  expected : String,
) -> Unit raise {
  let got = try {
    action()
    "ok"
  } catch {
    err => @crypto.crypto_error_tag(err)
  }
  assert_eq(got, expected)
}

///|
fn flip_byte(data : Bytes, index : Int32) -> Bytes {
  let arr = data.to_array()
  arr[index] = (arr[index].to_int() ^ 0x01).to_byte()
  Bytes::from_array(arr)
}

///|
fn set_byte(data : Bytes, index : Int32, value : Byte) -> Bytes {
  let arr = data.to_array()
  arr[index] = value
  Bytes::from_array(arr)
}

///|
fn test_key32() -> Bytes {
  Bytes::makei(32, i => (0x10 + i).to_byte())
}

///|
fn test_salt16() -> Bytes {
  Bytes::makei(16, i => (0xa0 + i).to_byte())
}

///|
fn test_nonce_prefix12() -> Bytes {
  Bytes::makei(12, i => if i < 8 { (0x50 + i).to_byte() } else { b'\x00' })
}

///|
fn fast_seal_options(chunk_size~ : Int32 = 1024) -> @crypto.SealOptions {
  { chunk_size, argon2_memory_kib: 64, argon2_passes: 1, argon2_lanes: 1, }
}

///|
test "crypto_error_tag covers all CryptoError variants" {
  assert_eq(
    @crypto.crypto_error_tag(@crypto.CryptoError::InvalidKey("seed")),
    "InvalidKey:seed",
  )
  assert_eq(
    @crypto.crypto_error_tag(@crypto.CryptoError::InvalidSignature("ed25519")),
    "InvalidSignature:ed25519",
  )
  assert_eq(
    @crypto.crypto_error_tag(@crypto.CryptoError::UntrustedKey("abcd")),
    "UntrustedKey:abcd",
  )
  assert_eq(
    @crypto.crypto_error_tag(
      @crypto.CryptoError::DigestMismatch("payload_sha256"),
    ),
    "DigestMismatch:payload_sha256",
  )
  assert_eq(
    @crypto.crypto_error_tag(@crypto.CryptoError::InvalidFormat("magic")),
    "InvalidFormat:magic",
  )
  assert_eq(
    @crypto.crypto_error_tag(@crypto.CryptoError::AuthenticationFailed),
    "AuthenticationFailed",
  )
  assert_eq(
    @crypto.crypto_error_tag(@crypto.CryptoError::TruncatedInput),
    "TruncatedInput",
  )
  assert_eq(
    @crypto.crypto_error_tag(@crypto.CryptoError::TrailingData),
    "TrailingData",
  )
  assert_eq(
    @crypto.crypto_error_tag(@crypto.CryptoError::LimitExceeded("chunk_size")),
    "LimitExceeded:chunk_size",
  )
  assert_eq(
    @crypto.crypto_error_tag(@crypto.CryptoError::InvalidOptions("salt")),
    "InvalidOptions:salt",
  )
}

///|
test "encode_key_hex and decode_key_hex enforce strict lowercase hex" {
  let raw = b"\x00\x09\x0a\x1f\xab\xff"
  let hex = @crypto.encode_key_hex(raw)
  assert_eq(hex, "00090a1fabff")
  assert_eq(@crypto.decode_key_hex(hex, 6, "sample"), raw)
  assert_eq(@crypto.decode_key_hex("", 0, "empty"), b"")

  expect_crypto_err(
    () => ignore(@crypto.decode_key_hex("00090A1fabff", 6, "upper")),
    "InvalidFormat:upper",
  )
  expect_crypto_err(
    () => ignore(@crypto.decode_key_hex(" 00", 1, "ws")),
    "InvalidFormat:ws",
  )
  expect_crypto_err(
    () => ignore(@crypto.decode_key_hex("00 ", 1, "ws2")),
    "InvalidFormat:ws2",
  )
  expect_crypto_err(
    () => ignore(@crypto.decode_key_hex("0g", 1, "nonhex")),
    "InvalidFormat:nonhex",
  )
  expect_crypto_err(
    () => ignore(@crypto.decode_key_hex("00", 2, "short")),
    "InvalidFormat:short",
  )
  expect_crypto_err(
    () => ignore(@crypto.decode_key_hex("001122", 2, "long")),
    "InvalidFormat:long",
  )
  expect_crypto_err(
    () => ignore(@crypto.decode_key_hex("😀", 1, "emoji")),
    "InvalidFormat:emoji",
  )
  expect_crypto_err(
    () => ignore(@crypto.decode_key_hex("", -1, "neg")),
    "InvalidOptions:expected_len",
  )
}

///|
test "keypair_from_seed matches RFC 8032 vectors and validates keys strictly" {
  // RFC 8032 section 7.1 TEST 1, TEST 2, TEST 3
  let vectors = [
    (
      "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
    ),
    (
      "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb", "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
    ),
    (
      "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7", "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
    ),
  ]
  for pair in vectors {
    let (seed_hex, want_pk_hex) = pair
    let seed = @crypto.decode_key_hex(seed_hex, 32, "seed")
    let kp = @crypto.keypair_from_seed(seed)
    assert_eq(kp.seed, seed)
    assert_eq(@crypto.encode_key_hex(kp.public_key), want_pk_hex)
    @crypto.validate_public_key(kp.public_key)
    let want_key_id = @crypto.encode_key_hex(
      @sha2.hash(kp.public_key[:], kind=@sha2.Kind::Sha256)[0:8].to_owned(),
    )
    assert_eq(@crypto.key_id_from_public_key(kp.public_key), want_key_id)
    assert_eq(want_key_id.length(), 16)
  }

  // Wrong seed lengths
  expect_crypto_err(
    () => ignore(@crypto.keypair_from_seed(b"")),
    "InvalidKey:seed_length",
  )
  expect_crypto_err(
    () => ignore(@crypto.keypair_from_seed(Bytes::make(31, b'\x01'))),
    "InvalidKey:seed_length",
  )
  expect_crypto_err(
    () => ignore(@crypto.keypair_from_seed(Bytes::make(33, b'\x01'))),
    "InvalidKey:seed_length",
  )

  // Wrong public key lengths
  expect_crypto_err(
    () => @crypto.validate_public_key(Bytes::make(31, b'\x01')),
    "InvalidKey:public_key_length",
  )
  expect_crypto_err(
    () => @crypto.validate_public_key(Bytes::make(33, b'\x01')),
    "InvalidKey:public_key_length",
  )

  // Small-order points (all-zero is 4-torsion, 0x01 || 0x00*31 is identity)
  expect_crypto_err(
    () => @crypto.validate_public_key(Bytes::make(32, b'\x00')),
    "InvalidKey:public_key_low_order",
  )
  let identity = set_byte(Bytes::make(32, b'\x00'), 0, b'\x01')
  expect_crypto_err(
    () => @crypto.validate_public_key(identity),
    "InvalidKey:public_key_low_order",
  )

  // Non-canonical y >= p (0xff * 32 has y = 2^255 - 1 >= 2^255 - 19)
  expect_crypto_err(
    () => @crypto.validate_public_key(Bytes::make(32, b'\xff')),
    "InvalidKey:public_key_point",
  )
  // Exact y = p = 2^255 - 19 (little-endian: ed ff .. ff 7f)
  let exact_p = set_byte(
    set_byte(Bytes::make(32, b'\xff'), 0, b'\xed'),
    31,
    b'\x7f',
  )
  expect_crypto_err(
    () => @crypto.validate_public_key(exact_p),
    "InvalidKey:public_key_point",
  )
  // Non-canonical x = 0 with sign bit 1 (y = 1, sign = 1)
  let noncanon_zero_x = set_byte(identity, 31, b'\x80')
  expect_crypto_err(
    () => @crypto.validate_public_key(noncanon_zero_x),
    "InvalidKey:public_key_point",
  )
  // Off-curve y (y = 2 has no square root for (y^2 - 1)/(d*y^2 + 1) mod p)
  let off_curve = set_byte(Bytes::make(32, b'\x00'), 0, b'\x02')
  expect_crypto_err(
    () => @crypto.validate_public_key(off_curve),
    "InvalidKey:public_key_point",
  )
}

///|
test "Ed25519 sign_bytes sign_digest verify_bytes verify_digest and domain separation" {
  let seed1 = @crypto.decode_key_hex(
    "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", 32, "seed1",
  )
  let seed2 = @crypto.decode_key_hex(
    "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb", 32, "seed2",
  )
  let kp1 = @crypto.keypair_from_seed(seed1)
  let kp2 = @crypto.keypair_from_seed(seed2)

  // Empty payload and "abc" match sign_digest identically
  let sig_empty = @crypto.sign_bytes(seed1, b"")
  let sig_empty_digest = @crypto.sign_digest(
    seed1, 0L, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_true(sig_empty == sig_empty_digest)
  @crypto.verify_bytes(sig_empty, [kp1.public_key], b"")
  @crypto.verify_bytes(sig_empty, [kp2.public_key, kp1.public_key], b"")

  let sig_abc = @crypto.sign_bytes(seed1, b"abc")
  assert_eq(sig_abc.algorithm, "ed25519")
  assert_eq(sig_abc.payload_length, 3L)
  assert_eq(
    sig_abc.payload_sha256,
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  // Independent verification of the exact domain-separated message format
  let domain_msg = b"moonlibsync-ed25519-v1\x003:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  let raw_pk = @ed25519.PublicKey::new(kp1.public_key[:])
  let raw_sig = @crypto.decode_key_hex(sig_abc.signature_hex, 64, "sig")
  assert_true(raw_pk.verify(domain_msg[:], raw_sig[:]))
  // Raw payload without domain separation MUST NOT verify
  assert_false(raw_pk.verify(b"abc"[:], raw_sig[:]))

  // Streaming >4GiB payload_length via sign_digest / verify_digest
  let large_len = 5000000000L
  let large_sig = @crypto.sign_digest(seed2, large_len, sig_abc.payload_sha256)
  @crypto.verify_digest(
    large_sig,
    [kp1.public_key, kp2.public_key],
    large_len,
    sig_abc.payload_sha256,
  )

  // Trust failures
  expect_crypto_err(
    () => @crypto.verify_bytes(sig_abc, [], b"abc"),
    "InvalidOptions:trusted_pubkeys",
  )
  expect_crypto_err(
    () => @crypto.verify_bytes(sig_abc, [kp2.public_key], b"abc"),
    "UntrustedKey:" + sig_abc.key_id,
  )
  // Invalid trusted key must be rejected even if another trusted key matches
  expect_crypto_err(
    () => {
      @crypto.verify_bytes(
        sig_abc,
        [kp1.public_key, Bytes::make(32, b'\x00')],
        b"abc",
      )
    },
    "InvalidKey:public_key_low_order",
  )

  // Digest mismatches
  expect_crypto_err(
    () => @crypto.verify_bytes(sig_abc, [kp1.public_key], b"abcd"),
    "DigestMismatch:payload_length",
  )
  expect_crypto_err(
    () => @crypto.verify_bytes(sig_abc, [kp1.public_key], b"abd"),
    "DigestMismatch:payload_sha256",
  )

  // Cryptographic signature tampering (flip bit in R and S)
  let bad_r = @crypto.encode_key_hex(flip_byte(raw_sig, 0))
  expect_crypto_err(
    () => {
      @crypto.verify_bytes(
        { ..sig_abc, signature_hex: bad_r, },
        [kp1.public_key],
        b"abc",
      )
    },
    "InvalidSignature:ed25519",
  )
  let bad_s = @crypto.encode_key_hex(flip_byte(raw_sig, 63))
  expect_crypto_err(
    () => {
      @crypto.verify_bytes(
        { ..sig_abc, signature_hex: bad_s, },
        [kp1.public_key],
        b"abc",
      )
    },
    "InvalidSignature:ed25519",
  )
  // Non-canonical S >= l
  let high_s = @crypto.encode_key_hex(set_byte(raw_sig, 63, b'\xff'))
  expect_crypto_err(
    () => {
      @crypto.verify_bytes(
        { ..sig_abc, signature_hex: high_s, },
        [kp1.public_key],
        b"abc",
      )
    },
    "InvalidSignature:ed25519",
  )

  // Field validation errors
  expect_crypto_err(
    () => {
      @crypto.verify_bytes(
        { ..sig_abc, algorithm: "rsa", },
        [kp1.public_key],
        b"abc",
      )
    },
    "InvalidSignature:algorithm",
  )
  expect_crypto_err(
    () => {
      @crypto.verify_bytes(
        { ..sig_abc, key_id: "0000000000000000", },
        [kp1.public_key],
        b"abc",
      )
    },
    "InvalidSignature:key_id",
  )
  expect_crypto_err(
    () => ignore(@crypto.sign_digest(seed1, -1L, sig_abc.payload_sha256)),
    "InvalidOptions:payload_length",
  )
  expect_crypto_err(
    () => ignore(@crypto.sign_digest(seed1, 3L, "A".repeat(64))),
    "InvalidFormat:payload_sha256",
  )
}

///|
test "Schema 4 publisher signature JSON encode and strict parse" {
  let seed = @crypto.decode_key_hex(
    "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", 32, "seed",
  )
  let kp = @crypto.keypair_from_seed(seed)
  let sig = @crypto.sign_bytes(seed, b"abc")
  let encoded = @crypto.encode_publisher_signature(sig)
  let expected_json = "{\"schema_version\":1,\"kind\":\"moonlibsync-signature\",\"algorithm\":\"ed25519\",\"key_id\":\"\{sig.key_id}\",\"public_key\":\"\{sig.public_key_hex}\",\"payload_length\":\"3\",\"payload_sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\",\"signature\":\"\{sig.signature_hex}\"}\n"
  assert_eq(encoded, @utf8.encode(expected_json))

  let parsed = @crypto.parse_publisher_signature(encoded)
  assert_true(parsed == sig)
  @crypto.verify_bytes(parsed, [kp.public_key], b"abc")

  // Max Int64 payload_length roundtrip
  let max_sig = @crypto.sign_digest(
    seed,
    9223372036854775807L,
    sig.payload_sha256,
  )
  let max_parsed = @crypto.parse_publisher_signature(
    @crypto.encode_publisher_signature(max_sig),
  )
  assert_true(max_parsed == max_sig)

  // Strict parser rejections
  let cases : Array[(Bytes, String)] = [
    // > 8192 bytes
    (Bytes::make(8193, b' '), "LimitExceeded:signature_json_bytes"),
    // Invalid UTF-8
    (b"\xff\xfe\xfd", "InvalidFormat:utf8"),
    // UTF-8 BOM
    (b"\xef\xbb\xbf" + encoded, "InvalidFormat:utf8_bom"),
    // Duplicate key
    (
      @utf8.encode(
        expected_json.replace(
          old="\"schema_version\":1",
          new="\"schema_version\":1,\"schema_version\":1",
        ),
      ),
      "InvalidFormat:json",
    ),
    // Extra field
    (
      @utf8.encode(
        expected_json.replace(
          old="\"schema_version\":1",
          new="\"schema_version\":1,\"extra\":true",
        ),
      ),
      "InvalidFormat:schema",
    ),
    // Non-integer schema_version 1.0
    (
      @utf8.encode(
        expected_json.replace(
          old="\"schema_version\":1",
          new="\"schema_version\":1.0",
        ),
      ),
      "InvalidFormat:schema_version",
    ),
    // Wrong schema_version 2
    (
      @utf8.encode(
        expected_json.replace(
          old="\"schema_version\":1",
          new="\"schema_version\":2",
        ),
      ),
      "InvalidFormat:schema_version",
    ),
    // Wrong kind
    (
      @utf8.encode(
        expected_json.replace(
          old="moonlibsync-signature",
          new="moonlibsync-other",
        ),
      ),
      "InvalidFormat:kind",
    ),
    // Leading zero payload_length
    (
      @utf8.encode(
        expected_json.replace(
          old="\"payload_length\":\"3\"",
          new="\"payload_length\":\"03\"",
        ),
      ),
      "InvalidFormat:payload_length",
    ),
    // Negative payload_length
    (
      @utf8.encode(
        expected_json.replace(
          old="\"payload_length\":\"3\"",
          new="\"payload_length\":\"-1\"",
        ),
      ),
      "InvalidFormat:payload_length",
    ),
    // Overflow Int64 payload_length
    (
      @utf8.encode(
        expected_json.replace(
          old="\"payload_length\":\"3\"",
          new="\"payload_length\":\"9223372036854775808\"",
        ),
      ),
      "InvalidFormat:payload_length",
    ),
    // Uppercase hex in payload_sha256
    (
      @utf8.encode(
        expected_json.replace(
          old="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
          new="BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD",
        ),
      ),
      "InvalidFormat:payload_sha256",
    ),
    // Wrong algorithm
    (
      @utf8.encode(
        expected_json.replace(
          old="\"algorithm\":\"ed25519\"",
          new="\"algorithm\":\"ed448\"",
        ),
      ),
      "InvalidSignature:algorithm",
    ),
  ]
  for item in cases {
    let (bad_bytes, expected_err) = item
    expect_crypto_err(
      () => ignore(@crypto.parse_publisher_signature(bad_bytes)),
      expected_err,
    )
  }

  // encode_publisher_signature revalidates caller-built structs
  expect_crypto_err(
    () => {
      ignore(
        @crypto.encode_publisher_signature({ ..sig, payload_length: -5L, }),
      )
    },
    "InvalidFormat:payload_length",
  )
}

///|
test "MLSENC01 raw-key one-shot roundtrips exact header layout and chunk boundaries" {
  assert_eq(@crypto.seal_magic(), b"MLSENC01")
  let limits = @crypto.SealLimits::default()
  let def_opts = @crypto.SealOptions::default()
  assert_eq(def_opts.chunk_size, 65536)
  assert_eq(def_opts.argon2_memory_kib, 16384)
  assert_eq(def_opts.argon2_passes, 2)
  assert_eq(def_opts.argon2_lanes, 1)

  let key = test_key32()
  let salt = test_salt16()
  let nonce = test_nonce_prefix12()

  // Raw-key mode with SealOptions::default zeroes argon2 header fields
  let ct_default = @crypto.seal_with_key(
    b"", key, salt, nonce, def_opts, limits,
  )
  // 56B header + 4B plain_len + 1B is_final + 16B tag = 77 bytes
  assert_eq(ct_default.length(), 77)
  let hdr_default = @crypto.inspect_seal_header(ct_default[:], limits)
  assert_true(
    hdr_default ==
    {
      kdf_mode: b'\x00',
      chunk_size: 65536,
      argon2_memory_kib: 0,
      argon2_passes: 0,
      argon2_lanes: 0,
      salt,
      nonce_prefix: nonce,
    },
  )
  assert_eq(@crypto.unseal_with_key(ct_default, key, limits), b"")

  // Test chunk boundary sizes with chunk_size = 1024
  let opts = fast_seal_options(chunk_size=1024)
  for size in [0, 1, 1023, 1024, 1025, 2048, 3500] {
    let plain = Bytes::makei(size, i => ((i * 37 + 11) % 256).to_byte())
    let ct = @crypto.seal_with_key(plain, key, salt, nonce, opts, limits)
    // Verify exact chunk count: 1 chunk for 0..1024, 2 for 1025..2048, 4 for 3500
    let expected_chunks = if size == 0 { 1 } else { (size + 1023) / 1024 }
    assert_eq(ct.length(), 56 + size + expected_chunks * 21)
    let pt = @crypto.unseal_with_key(ct, key, limits)
    assert_eq(pt, plain)
  }

  // Wrong key fails authentication
  let ct_hello = @crypto.seal_with_key(
    b"secret message", key, salt, nonce, opts, limits,
  )
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(ct_hello, flip_byte(key, 0), limits)),
    "AuthenticationFailed",
  )
  // Cross-mode mismatch
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_passphrase(ct_hello, b"pw", limits)),
    "InvalidFormat:kdf_mode_mismatch",
  )
}

///|
test "MLSENC01 Argon2id passphrase roundtrip and derive_argon2_key checks" {
  let limits = @crypto.SealLimits::default()
  let salt = test_salt16()
  let nonce = test_nonce_prefix12()
  let opts = fast_seal_options(chunk_size=1024)

  // Deterministic derivation and parameter sensitivity
  let k1 = @crypto.derive_argon2_key(b"correct horse", salt, 64, 1, 1, limits)
  let k2 = @crypto.derive_argon2_key(b"correct horse", salt, 64, 1, 1, limits)
  let k_pw = @crypto.derive_argon2_key(b"wrong horse", salt, 64, 1, 1, limits)
  let k_salt = @crypto.derive_argon2_key(
    b"correct horse",
    flip_byte(salt, 0),
    64,
    1,
    1,
    limits,
  )
  let k_lanes = @crypto.derive_argon2_key(
    b"correct horse", salt, 64, 1, 2, limits,
  )
  assert_eq(k1.length(), 32)
  assert_eq(k1, k2)
  assert_not_eq(k1, k_pw)
  assert_not_eq(k1, k_salt)
  assert_not_eq(k1, k_lanes)

  // Passphrase seal / inspect / unseal roundtrip across multiple chunks
  let plain = Bytes::makei(2500, i => ((i * 19 + 3) % 256).to_byte())
  let ct = @crypto.seal_with_passphrase(
    plain, b"passphrase-v1", salt, nonce, opts, limits,
  )
  let hdr = @crypto.inspect_seal_header(ct[:], limits)
  assert_true(
    hdr ==
    {
      kdf_mode: b'\x01',
      chunk_size: 1024,
      argon2_memory_kib: 64,
      argon2_passes: 1,
      argon2_lanes: 1,
      salt,
      nonce_prefix: nonce,
    },
  )
  assert_eq(@crypto.unseal_with_passphrase(ct, b"passphrase-v1", limits), plain)

  // Wrong passphrase fails authentication
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_passphrase(ct, b"wrong-pass", limits)),
    "AuthenticationFailed",
  )
  // Cross-mode mismatch
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(ct, test_key32(), limits)),
    "InvalidFormat:kdf_mode_mismatch",
  )

  // Argon2 limits vs format option validation
  let tight_limits : @crypto.SealLimits = {
    ..limits,
    max_argon2_memory_kib: 64,
    max_argon2_passes: 1,
    max_argon2_lanes: 1,
  }
  expect_crypto_err(
    () => {
      ignore(@crypto.derive_argon2_key(b"pw", salt, 128, 1, 1, tight_limits))
    },
    "LimitExceeded:argon2_memory_kib",
  )
  expect_crypto_err(
    () => ignore(@crypto.derive_argon2_key(b"pw", salt, 64, 2, 1, tight_limits)),
    "LimitExceeded:argon2_passes",
  )
  expect_crypto_err(
    () => ignore(@crypto.derive_argon2_key(b"pw", salt, 64, 1, 2, tight_limits)),
    "LimitExceeded:argon2_lanes",
  )
  expect_crypto_err(
    () => ignore(@crypto.derive_argon2_key(b"pw", salt, 32, 1, 1, limits)),
    "InvalidOptions:argon2_memory_kib",
  )
  expect_crypto_err(
    () => ignore(@crypto.derive_argon2_key(b"pw", b"short", 64, 1, 1, limits)),
    "InvalidOptions:salt_length",
  )
}

///|
test "streaming SealEncoder and SealDecoder match one-shot across arbitrary splits" {
  let limits = @crypto.SealLimits::default()
  let key = test_key32()
  let salt = test_salt16()
  let nonce = test_nonce_prefix12()
  let opts = fast_seal_options(chunk_size=1024)
  let plain = Bytes::makei(3100, i => ((i * 53 + i / 17) % 256).to_byte())
  let oneshot = @crypto.seal_with_key(plain, key, salt, nonce, opts, limits)

  // Stream encode with varied split sizes including exact chunk_size and 0-byte updates
  for step in [1, 7, 1024, 1025] {
    let enc = @crypto.SealEncoder::new_with_key(key, salt, nonce, opts, limits)
    let out = @buffer.Buffer()
    let mut pos = 0
    while pos < plain.length() {
      let rem = plain.length() - pos
      let take = if rem < step { rem } else { step }
      enc.update(plain[pos:pos + take])
      enc.update(b""[:])
      out.write_bytes(enc.take_ready())
      pos = pos + take
    }
    out.write_bytes(enc.finish())
    assert_eq(out.to_bytes(), oneshot)
  }

  // Stream decode with 1-byte and 13-byte splits, draining before finish
  for step in [1, 13, 57, 1045] {
    let dec = @crypto.SealDecoder::new_with_key(key, limits)
    let out = @buffer.Buffer()
    let mut pos = 0
    while pos < oneshot.length() {
      let rem = oneshot.length() - pos
      let take = if rem < step { rem } else { step }
      dec.feed(oneshot[pos:pos + take])
      out.write_bytes(dec.take_ready())
      pos = pos + take
    }
    let hdr = dec.finish()
    assert_eq(hdr.chunk_size, 1024)
    assert_eq(hdr.kdf_mode, b'\x00')
    assert_eq(dec.take_ready(), b"")
    assert_eq(out.to_bytes(), plain)
  }

  // Passphrase streaming encode + decode with drain AFTER finish
  let pw_enc = @crypto.SealEncoder::new_with_passphrase(
    b"stream-pass", salt, nonce, opts, limits,
  )
  pw_enc.update(plain[0:1024])
  let part1 = pw_enc.take_ready()
  pw_enc.update(plain[1024:])
  let part2 = pw_enc.finish()
  let pw_ct = part1 + part2
  assert_eq(
    pw_ct,
    @crypto.seal_with_passphrase(
      plain, b"stream-pass", salt, nonce, opts, limits,
    ),
  )
  let pw_dec = @crypto.SealDecoder::new_with_passphrase(b"stream-pass", limits)
  pw_dec.feed(pw_ct[0:40])
  pw_dec.feed(pw_ct[40:60])
  pw_dec.feed(pw_ct[60:])
  let pw_hdr = pw_dec.finish()
  assert_eq(pw_hdr.kdf_mode, b'\x01')
  assert_eq(pw_dec.take_ready(), plain)
}

///|
test "MLSENC01 rejects tampering reordering truncation trailing data and bad framing" {
  let limits = @crypto.SealLimits::default()
  let key = test_key32()
  let salt = test_salt16()
  let nonce = test_nonce_prefix12()
  let opts = fast_seal_options(chunk_size=1024)
  // 3 chunks: 1024 (final=0), 1024 (final=0), 200 (final=1)
  let plain = Bytes::makei(2248, i => ((i * 29 + 7) % 256).to_byte())
  let ct = @crypto.seal_with_key(plain, key, salt, nonce, opts, limits)

  // Header field tampering
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(flip_byte(ct, 0), key, limits)),
    "InvalidFormat:magic",
  )
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(set_byte(ct, 8, b'\x02'), key, limits)),
    "InvalidFormat:kdf_mode",
  )
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(set_byte(ct, 9, b'\x01'), key, limits)),
    "InvalidFormat:reserved",
  )
  expect_crypto_err(
    () => {
      ignore(@crypto.unseal_with_key(set_byte(ct, 11, b'\x01'), key, limits))
    },
    "InvalidFormat:flags",
  )
  // Tamper chunk_size to valid 2048 -> authenticated header AAD mismatch
  let bad_cs = set_byte(set_byte(ct, 14, b'\x08'), 15, b'\x00')
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(bad_cs, key, limits)),
    "AuthenticationFailed",
  )
  // Tamper salt byte -> AAD mismatch
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(flip_byte(ct, 28), key, limits)),
    "AuthenticationFailed",
  )
  // Tamper nonce_prefix byte 0 -> nonce + AAD mismatch
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(flip_byte(ct, 44), key, limits)),
    "AuthenticationFailed",
  )
  // Non-zero last 4 bytes of nonce_prefix in header
  expect_crypto_err(
    () => {
      ignore(@crypto.unseal_with_key(set_byte(ct, 55, b'\x01'), key, limits))
    },
    "InvalidFormat:nonce_prefix",
  )
  // Raw-key mode with non-zero argon2 param
  expect_crypto_err(
    () => {
      ignore(@crypto.unseal_with_key(set_byte(ct, 19, b'\x40'), key, limits))
    },
    "InvalidFormat:argon2_params",
  )

  // Chunk 0 occupies [56 .. 56 + 1045) = [56 .. 1101)
  // Chunk 1 occupies [1101 .. 2146)
  // Chunk 2 occupies [2146 .. 2367)
  let header_raw = ct[0:56].to_owned()
  let chunk0 = ct[56:1101].to_owned()
  let chunk1 = ct[1101:2146].to_owned()
  let chunk2 = ct[2146:].to_owned()

  // Flip ciphertext byte in chunk 0 and tag byte in chunk 2
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(flip_byte(ct, 70), key, limits)),
    "AuthenticationFailed",
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.unseal_with_key(flip_byte(ct, ct.length() - 1), key, limits),
      )
    },
    "AuthenticationFailed",
  )
  // Truncation attack: mark chunk 0 as is_final=1 and drop chunk 1 & 2
  let fake_final_c0 = set_byte(chunk0, 4, b'\x01')
  expect_crypto_err(
    () => {
      ignore(@crypto.unseal_with_key(header_raw + fake_final_c0, key, limits))
    },
    "AuthenticationFailed",
  )
  // Invalid is_final flag (0x02)
  expect_crypto_err(
    () => {
      ignore(@crypto.unseal_with_key(set_byte(ct, 60, b'\x02'), key, limits))
    },
    "InvalidFormat:chunk_final_flag",
  )
  // Chunk reorder: chunk1 before chunk0
  expect_crypto_err(
    () => {
      ignore(
        @crypto.unseal_with_key(
          header_raw + chunk1 + chunk0 + chunk2,
          key,
          limits,
        ),
      )
    },
    "AuthenticationFailed",
  )
  // Chunk duplication: chunk0 twice
  expect_crypto_err(
    () => {
      ignore(
        @crypto.unseal_with_key(
          header_raw + chunk0 + chunk0 + chunk2,
          key,
          limits,
        ),
      )
    },
    "AuthenticationFailed",
  )
  // Chunk deletion: skip chunk0
  expect_crypto_err(
    () => {
      ignore(@crypto.unseal_with_key(header_raw + chunk1 + chunk2, key, limits))
    },
    "AuthenticationFailed",
  )

  // Truncation at every stage
  for cut in [0, 10, 55, 56, 58, 61, 100, 1100, 1101, ct.length() - 1] {
    expect_crypto_err(
      () => ignore(@crypto.unseal_with_key(ct[0:cut].to_owned(), key, limits)),
      "TruncatedInput",
    )
  }

  // Trailing data in single call and separate feed call
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(ct + b"\x00", key, limits)),
    "TrailingData",
  )
  let dec_trail = @crypto.SealDecoder::new_with_key(key, limits)
  dec_trail.feed(ct[:])
  expect_crypto_err(() => dec_trail.feed(b"\x00"[:]), "TrailingData")

  // Manual wire test: non-final chunk with 1 <= plain_len < chunk_size succeeds,
  // while non-final chunk with plain_len == 0 is rejected.
  let aead = @chachapoly.ChaChaPoly::new(key[:])
  let n0 = nonce[0:8].to_owned() + b"\x00\x00\x00\x00"
  let n1 = nonce[0:8].to_owned() + b"\x00\x00\x00\x01"
  let aad0 = header_raw + b"\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  let aad1 = header_raw + b"\x00\x00\x00\x00\x00\x00\x00\x01\x01"
  let short_c0 = b"\x00\x00\x00\x05\x00" +
    aead.seal(nonce=n0[:], plain=b"hello"[:], aad=aad0[:])
  let short_c1 = b"\x00\x00\x00\x06\x01" +
    aead.seal(nonce=n1[:], plain=b" world"[:], aad=aad1[:])
  assert_eq(
    @crypto.unseal_with_key(header_raw + short_c0 + short_c1, key, limits),
    b"hello world",
  )
  let empty_non_final = b"\x00\x00\x00\x00\x00" +
    aead.seal(nonce=n0[:], plain=b""[:], aad=aad0[:])
  expect_crypto_err(
    () => {
      ignore(
        @crypto.unseal_with_key(
          header_raw + empty_non_final + short_c1,
          key,
          limits,
        ),
      )
    },
    "InvalidFormat:empty_non_final_chunk",
  )
}

///|
test "MLSENC01 enforces SealLimits options and fail-closed stream poisoning" {
  let limits = @crypto.SealLimits::default()
  let key = test_key32()
  let salt = test_salt16()
  let nonce = test_nonce_prefix12()
  let opts = fast_seal_options(chunk_size=1024)

  // Invalid options & keys
  expect_crypto_err(
    () => {
      ignore(
        @crypto.seal_with_key(
          b"a",
          Bytes::make(31, b'\x00'),
          salt,
          nonce,
          opts,
          limits,
        ),
      )
    },
    "InvalidKey:key_length",
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.seal_with_key(
          b"a",
          key,
          Bytes::make(15, b'\x00'),
          nonce,
          opts,
          limits,
        ),
      )
    },
    "InvalidOptions:salt_length",
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.seal_with_key(
          b"a",
          key,
          salt,
          set_byte(nonce, 11, b'\x01'),
          opts,
          limits,
        ),
      )
    },
    "InvalidOptions:nonce_prefix",
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.seal_with_key(
          b"a",
          key,
          salt,
          nonce,
          { ..opts, chunk_size: 1023, },
          limits,
        ),
      )
    },
    "InvalidOptions:chunk_size",
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.seal_with_key(b"a", key, salt, nonce, opts, {
          ..limits,
          max_chunk_size: 512,
        }),
      )
    },
    "InvalidOptions:max_chunk_size",
  )

  // Exact boundary budgets for empty plaintext (0B plain <-> 77B cipher)
  let exact_enc_limits : @crypto.SealLimits = {
    ..limits,
    max_input_bytes: 0L,
    max_output_bytes: 77L,
  }
  let ct0 = @crypto.seal_with_key(b"", key, salt, nonce, opts, exact_enc_limits)
  assert_eq(ct0.length(), 77)
  expect_crypto_err(
    () => {
      ignore(
        @crypto.seal_with_key(b"", key, salt, nonce, opts, {
          ..exact_enc_limits,
          max_output_bytes: 76L,
        }),
      )
    },
    "LimitExceeded:max_output_bytes",
  )
  let exact_dec_limits : @crypto.SealLimits = {
    ..limits,
    max_input_bytes: 77L,
    max_output_bytes: 0L,
  }
  assert_eq(@crypto.unseal_with_key(ct0, key, exact_dec_limits), b"")
  expect_crypto_err(
    () => {
      ignore(
        @crypto.unseal_with_key(ct0, key, {
          ..exact_dec_limits,
          max_input_bytes: 76L,
        }),
      )
    },
    "LimitExceeded:max_input_bytes",
  )

  // Output limit enforcement on decoder before decrypting
  let ct_big = @crypto.seal_with_key(
    Bytes::make(100, b'x'),
    key,
    salt,
    nonce,
    opts,
    limits,
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.unseal_with_key(ct_big, key, {
          ..limits,
          max_output_bytes: 99L,
        }),
      )
    },
    "LimitExceeded:max_output_bytes",
  )

  // Fail-closed poisoning on SealEncoder
  let enc = @crypto.SealEncoder::new_with_key(key, salt, nonce, opts, {
    ..limits,
    max_input_bytes: 4L,
  })
  enc.update(b"1234"[:])
  expect_crypto_err(() => enc.update(b"5"[:]), "LimitExceeded:max_input_bytes")
  expect_crypto_err(() => enc.update(b""[:]), "InvalidOptions:stream_failed")
  expect_crypto_err(
    () => ignore(enc.take_ready()),
    "InvalidOptions:stream_failed",
  )
  expect_crypto_err(() => ignore(enc.finish()), "InvalidOptions:stream_failed")

  // Reuse after finish on SealEncoder
  let enc_done = @crypto.SealEncoder::new_with_key(
    key, salt, nonce, opts, limits,
  )
  let _ = enc_done.finish()
  expect_crypto_err(
    () => enc_done.update(b""[:]),
    "InvalidOptions:stream_finished",
  )
  expect_crypto_err(
    () => ignore(enc_done.take_ready()),
    "InvalidOptions:stream_finished",
  )
  expect_crypto_err(
    () => ignore(enc_done.finish()),
    "InvalidOptions:stream_finished",
  )

  // Fail-closed poisoning on SealDecoder (even after chunk 0 decrypted!)
  let ct_two = @crypto.seal_with_key(
    Bytes::make(1200, b'a'),
    key,
    salt,
    nonce,
    opts,
    limits,
  )
  let bad_second = flip_byte(ct_two, ct_two.length() - 1)
  let dec = @crypto.SealDecoder::new_with_key(key, limits)
  expect_crypto_err(() => dec.feed(bad_second[:]), "AuthenticationFailed")
  expect_crypto_err(() => dec.feed(b""[:]), "InvalidOptions:stream_failed")
  expect_crypto_err(
    () => ignore(dec.take_ready()),
    "InvalidOptions:stream_failed",
  )
  expect_crypto_err(() => ignore(dec.finish()), "InvalidOptions:stream_failed")

  // Reuse after finish on SealDecoder
  let dec_done = @crypto.SealDecoder::new_with_key(key, limits)
  dec_done.feed(ct_two[:])
  let _ = dec_done.finish()
  expect_crypto_err(
    () => dec_done.feed(b""[:]),
    "InvalidOptions:stream_finished",
  )
  expect_crypto_err(
    () => ignore(dec_done.finish()),
    "InvalidOptions:stream_finished",
  )
  assert_eq(dec_done.take_ready().length(), 1200)
}

///|
test "inspect_seal_header and decoder enforce header format and Argon2 limits before KDF" {
  let limits = @crypto.SealLimits::default()
  let salt = test_salt16()
  let nonce = test_nonce_prefix12()
  let pw_opts : @crypto.SealOptions = {
    chunk_size: 2048,
    argon2_memory_kib: 128,
    argon2_passes: 2,
    argon2_lanes: 2,
  }
  let pw_ct = @crypto.seal_with_passphrase(
    b"hello", b"pw", salt, nonce, pw_opts, limits,
  )

  // Truncated header inputs
  expect_crypto_err(
    () => ignore(@crypto.inspect_seal_header(b""[:], limits)),
    "TruncatedInput",
  )
  expect_crypto_err(
    () => ignore(@crypto.inspect_seal_header(pw_ct[0:55], limits)),
    "TruncatedInput",
  )

  // Exact 56-byte slice inspection succeeds
  let hdr56 = @crypto.inspect_seal_header(pw_ct[0:56], limits)
  assert_true(
    hdr56 ==
    {
      kdf_mode: b'\x01',
      chunk_size: 2048,
      argon2_memory_kib: 128,
      argon2_passes: 2,
      argon2_lanes: 2,
      salt,
      nonce_prefix: nonce,
    },
  )

  // Header limit rejections before KDF execution
  expect_crypto_err(
    () => {
      ignore(
        @crypto.inspect_seal_header(pw_ct[0:56], {
          ..limits,
          max_chunk_size: 1024,
        }),
      )
    },
    "LimitExceeded:chunk_size",
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.unseal_with_passphrase(pw_ct, b"pw", {
          ..limits,
          max_argon2_memory_kib: 64,
        }),
      )
    },
    "LimitExceeded:argon2_memory_kib",
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.unseal_with_passphrase(pw_ct, b"pw", {
          ..limits,
          max_argon2_passes: 1,
        }),
      )
    },
    "LimitExceeded:argon2_passes",
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.unseal_with_passphrase(pw_ct, b"pw", {
          ..limits,
          max_argon2_lanes: 1,
        }),
      )
    },
    "LimitExceeded:argon2_lanes",
  )

  // Out-of-spec header values (format errors, not limits)
  // chunk_size = 1023 (0x000003ff)
  let bad_cs_small = set_byte(
    set_byte(pw_ct[0:56].to_owned(), 14, b'\x03'),
    15,
    b'\xff',
  )
  expect_crypto_err(
    () => ignore(@crypto.inspect_seal_header(bad_cs_small[:], limits)),
    "InvalidFormat:chunk_size",
  )
  // argon2_memory_kib = 32 (< 64)
  let bad_mem = set_byte(pw_ct[0:56].to_owned(), 19, b'\x20')
  expect_crypto_err(
    () => ignore(@crypto.inspect_seal_header(bad_mem[:], limits)),
    "InvalidFormat:argon2_memory_kib",
  )
  // argon2_passes = 0
  let bad_passes = set_byte(pw_ct[0:56].to_owned(), 23, b'\x00')
  expect_crypto_err(
    () => ignore(@crypto.inspect_seal_header(bad_passes[:], limits)),
    "InvalidFormat:argon2_passes",
  )
  // argon2_lanes = 5 (> 4)
  let bad_lanes = set_byte(pw_ct[0:56].to_owned(), 27, b'\x05')
  expect_crypto_err(
    () => ignore(@crypto.inspect_seal_header(bad_lanes[:], limits)),
    "InvalidFormat:argon2_lanes",
  )

  // Chunk plain_len exceeding header chunk_size
  let key_ct = @crypto.seal_with_key(
    b"hi",
    test_key32(),
    salt,
    nonce,
    fast_seal_options(chunk_size=1024),
    limits,
  )
  // Set chunk 0 plain_len to 1025 (0x00000401)
  let bad_chunk_len = set_byte(set_byte(key_ct, 58, b'\x04'), 59, b'\x01')
  expect_crypto_err(
    () => ignore(@crypto.unseal_with_key(bad_chunk_len, test_key32(), limits)),
    "InvalidFormat:chunk_length",
  )

  // Invalid SealLimits fields
  expect_crypto_err(
    () => {
      ignore(
        @crypto.inspect_seal_header(pw_ct[0:56], {
          ..limits,
          max_input_bytes: -1L,
        }),
      )
    },
    "InvalidOptions:max_input_bytes",
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.inspect_seal_header(pw_ct[0:56], {
          ..limits,
          max_output_bytes: -1L,
        }),
      )
    },
    "InvalidOptions:max_output_bytes",
  )
  expect_crypto_err(
    () => {
      ignore(
        @crypto.inspect_seal_header(pw_ct[0:56], {
          ..limits,
          max_argon2_memory_kib: 300000,
        }),
      )
    },
    "InvalidOptions:max_argon2_memory_kib",
  )
}

///|
test "Schema 4 JSON edge cases and CryptoError Eq behavior" {
  assert_true(
    @crypto.CryptoError::AuthenticationFailed ==
    @crypto.CryptoError::AuthenticationFailed,
  )
  assert_true(
    @crypto.CryptoError::TruncatedInput != @crypto.CryptoError::TrailingData,
  )
  assert_true(
    @crypto.CryptoError::InvalidKey("a") != @crypto.CryptoError::InvalidKey("b"),
  )

  let seed = @crypto.decode_key_hex(
    "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7", 32, "seed",
  )
  let kp = @crypto.keypair_from_seed(seed)
  let sig = @crypto.sign_bytes(seed, b"payload")

  // Pretty-printed JSON without trailing LF still parses cleanly
  let pretty = @utf8.encode(
    "{ \"schema_version\" : 1 , \"kind\" : \"moonlibsync-signature\" , \"algorithm\" : \"ed25519\" , \"key_id\" : \"\{sig.key_id}\" , \"public_key\" : \"\{sig.public_key_hex}\" , \"payload_length\" : \"7\" , \"payload_sha256\" : \"\{sig.payload_sha256}\" , \"signature\" : \"\{sig.signature_hex}\" }",
  )
  let parsed = @crypto.parse_publisher_signature(pretty)
  assert_true(parsed == sig)
  @crypto.verify_bytes(parsed, [kp.public_key], b"payload")

  // Deep nesting rejected with LimitExceeded
  expect_crypto_err(
    () => {
      ignore(@crypto.parse_publisher_signature(b"{\"a\":{\"b\":{\"c\":1}}}"))
    },
    "LimitExceeded:signature_json_depth",
  )
  // Non-object JSON rejected
  expect_crypto_err(
    () => ignore(@crypto.parse_publisher_signature(b"[1,2,3]")),
    "InvalidFormat:schema",
  )
  // Numeric payload_length instead of string rejected
  let num_len = @utf8.encode(
    "{\"schema_version\":1,\"kind\":\"moonlibsync-signature\",\"algorithm\":\"ed25519\",\"key_id\":\"\{sig.key_id}\",\"public_key\":\"\{sig.public_key_hex}\",\"payload_length\":7,\"payload_sha256\":\"\{sig.payload_sha256}\",\"signature\":\"\{sig.signature_hex}\"}",
  )
  expect_crypto_err(
    () => ignore(@crypto.parse_publisher_signature(num_len)),
    "InvalidFormat:payload_length",
  )
  // Signature with non-canonical R (y >= p -> 0xff * 32) rejected during verify
  let raw_sig = @crypto.decode_key_hex(sig.signature_hex, 64, "sig")
  let bad_r_bytes = Bytes::make(32, b'\xff') + raw_sig[32:64].to_owned()
  expect_crypto_err(
    () => {
      @crypto.verify_bytes(
        { ..sig, signature_hex: @crypto.encode_key_hex(bad_r_bytes), },
        [kp.public_key],
        b"payload",
      )
    },
    "InvalidSignature:ed25519",
  )
}
