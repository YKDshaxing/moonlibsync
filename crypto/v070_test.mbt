// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn v070_expect_err(
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
fn v070_flip_byte(data : Bytes, index : Int32) -> Bytes {
  let arr = data.to_array()
  arr[index] = (arr[index].to_int() ^ 0x01).to_byte()
  Bytes::from_array(arr)
}

///|
fn v070_set_byte(data : Bytes, index : Int32, value : Byte) -> Bytes {
  let arr = data.to_array()
  arr[index] = value
  Bytes::from_array(arr)
}

///|
fn v070_make_secret(seed_byte : Int32) -> Bytes {
  Bytes::makei(32, i => ((seed_byte * 31 + i * 17 + 5) % 256).to_byte())
}

///|
fn v070_ed25519_seed(tag : Int32) -> Bytes {
  Bytes::makei(32, i => ((tag * 43 + i * 13 + 7) % 256).to_byte())
}

///|
test "X25519 keypair derivation RFC 7748 vectors and secret/public key validation" {
  // RFC 7748 section 6.1 test vectors (Alice and Bob)
  let alice_sk = @crypto.decode_key_hex(
    "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a", 32, "alice_sk",
  )
  let alice_pk_want = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"
  let bob_sk = @crypto.decode_key_hex(
    "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb", 32, "bob_sk",
  )
  let bob_pk_want = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"

  let alice = @crypto.x25519_keypair_from_secret(alice_sk)
  assert_eq(alice.secret_key, alice_sk)
  assert_eq(@crypto.encode_key_hex(alice.public_key), alice_pk_want)
  assert_eq(@crypto.x25519_public_from_secret(alice_sk), alice.public_key)
  assert_true(alice == @crypto.x25519_keypair_from_secret(alice_sk))

  let bob = @crypto.x25519_keypair_from_secret(bob_sk)
  assert_eq(@crypto.encode_key_hex(bob.public_key), bob_pk_want)
  assert_false(alice == bob)

  let alice_id = @crypto.x25519_key_id(alice.public_key)
  let want_alice_id = @crypto.encode_key_hex(
    @sha2.hash(alice.public_key[:], kind=@sha2.Kind::Sha256)[0:8].to_owned(),
  )
  assert_eq(alice_id, want_alice_id)
  assert_eq(alice_id.length(), 16)

  // Reject wrong secret lengths and all-zero secret
  v070_expect_err(
    () => ignore(@crypto.x25519_keypair_from_secret(b"")),
    "InvalidKey:x25519_secret",
  )
  v070_expect_err(
    () => ignore(@crypto.x25519_keypair_from_secret(Bytes::make(31, b'\x01'))),
    "InvalidKey:x25519_secret",
  )
  v070_expect_err(
    () => ignore(@crypto.x25519_keypair_from_secret(Bytes::make(33, b'\x01'))),
    "InvalidKey:x25519_secret",
  )
  v070_expect_err(
    () => ignore(@crypto.x25519_keypair_from_secret(Bytes::make(32, b'\x00'))),
    "InvalidKey:x25519_secret",
  )
  v070_expect_err(
    () => ignore(@crypto.x25519_public_from_secret(Bytes::make(32, b'\x00'))),
    "InvalidKey:x25519_secret",
  )

  // Reject wrong public key lengths
  v070_expect_err(
    () => ignore(@crypto.x25519_key_id(Bytes::make(31, b'\x09'))),
    "InvalidKey:x25519_public_key",
  )
  v070_expect_err(
    () => ignore(@crypto.x25519_key_id(Bytes::make(33, b'\x09'))),
    "InvalidKey:x25519_public_key",
  )

  // Reject all low-order Curve25519 points (including non-canonical u >= p and high-bit variants)
  let low_order_hexes = [
    "0000000000000000000000000000000000000000000000000000000000000000", "0100000000000000000000000000000000000000000000000000000000000000",
    "e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800", "5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157",
    "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f", "edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
    "eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f", "0000000000000000000000000000000000000000000000000000000000000080",
    "0100000000000000000000000000000000000000000000000000000000000080", "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
  ]
  let limits = @crypto.SealLimits::default()
  let opts = @crypto.SealOptions::default()
  let cek = v070_make_secret(9)
  let eph = v070_make_secret(10)
  for lo_hex in low_order_hexes {
    let lo_pt = @crypto.decode_key_hex(lo_hex, 32, "lo")
    // Confirm mooncrypt x25519.shared also rejects every listed point
    let shared_failed = try {
      ignore(@x25519.shared(alice_sk[:], lo_pt[:]))
      false
    } catch {
      _ => true
    }
    assert_true(shared_failed)
    v070_expect_err(
      () => ignore(@crypto.x25519_key_id(lo_pt)),
      "InvalidKey:x25519_public_key",
    )
    v070_expect_err(
      () => {
        ignore(
          @crypto.seal_envelope(
            b"hello",
            [alice.public_key, lo_pt],
            eph,
            cek,
            b"\x01\x02\x03\x04",
            opts,
            limits,
          ),
        )
      },
      "InvalidKey:recipient_public_key",
    )
  }
}

///|
test "MLSENC02 multi-recipient roundtrip for empty small and multi-chunk >128KiB plaintexts" {
  assert_eq(@crypto.envelope_magic(), b"MLSENC02")
  let limits = @crypto.SealLimits::default()
  let r1 = @crypto.x25519_keypair_from_secret(v070_make_secret(1))
  let r2 = @crypto.x25519_keypair_from_secret(v070_make_secret(2))
  let r3 = @crypto.x25519_keypair_from_secret(v070_make_secret(3))
  let r4_unauth = @crypto.x25519_keypair_from_secret(v070_make_secret(4))
  let eph = @crypto.x25519_keypair_from_secret(v070_make_secret(5))
  let cek = v070_make_secret(6)
  let nonce_prefix = b"\xa1\xb2\xc3\xd4"
  let recipients = [r1.public_key, r2.public_key, r3.public_key]
  let want_ids = [
    @crypto.x25519_key_id(r1.public_key),
    @crypto.x25519_key_id(r2.public_key),
    @crypto.x25519_key_id(r3.public_key),
  ]

  // Empty, small, and multi-chunk (>128 KiB with default 64 KiB chunk_size -> 3 chunks)
  let default_opts = @crypto.SealOptions::default()
  let payloads = [
    b"",
    b"multi-recipient X25519 envelope test payload!",
    Bytes::makei(140000, i => ((i * 73 + i / 251 + 19) % 256).to_byte()),
  ]
  for plain in payloads {
    let ct = @crypto.seal_envelope(
      plain,
      recipients,
      eph.secret_key,
      cek,
      nonce_prefix,
      default_opts,
      limits,
    )
    let expected_chunks = if plain.length() == 0 {
      1
    } else {
      (plain.length() - 1) / default_opts.chunk_size + 1
    }
    // 51B preamble + 3 * 56B slots = 219B header; each chunk has 5B hdr + 16B tag
    assert_eq(ct.length(), 51 + 3 * 56 + plain.length() + expected_chunks * 21)

    let hdr = @crypto.inspect_envelope_header(ct[:], limits)
    assert_true(
      hdr ==
      {
        ephemeral_public_key: eph.public_key,
        recipient_key_ids: want_ids,
        chunk_size: default_opts.chunk_size,
        nonce_prefix,
      },
    )

    // All 3 recipients independently recover exact plaintext
    assert_eq(@crypto.unseal_envelope(ct, r1.secret_key, limits), plain)
    assert_eq(@crypto.unseal_envelope(ct, r2.secret_key, limits), plain)
    assert_eq(@crypto.unseal_envelope(ct, r3.secret_key, limits), plain)

    // 4th unauthorized recipient fails with AuthenticationFailed
    v070_expect_err(
      () => ignore(@crypto.unseal_envelope(ct, r4_unauth.secret_key, limits)),
      "AuthenticationFailed",
    )
  }

  // Exact chunk boundary sizes with small chunk_size=1024
  let small_opts : @crypto.SealOptions = { ..default_opts, chunk_size: 1024, }
  for size in [1023, 1024, 1025, 2048] {
    let plain = Bytes::makei(size, i => ((i * 29 + 3) % 256).to_byte())
    let ct = @crypto.seal_envelope(
      plain,
      recipients,
      eph.secret_key,
      cek,
      nonce_prefix,
      small_opts,
      limits,
    )
    assert_eq(@crypto.unseal_envelope(ct, r2.secret_key, limits), plain)
  }
}

///|
test "MLSENC02 rejects header/slot/ciphertext tampering truncation trailing data duplicates and limits" {
  let limits = @crypto.SealLimits::default()
  let opts : @crypto.SealOptions = {
    ..@crypto.SealOptions::default(),
    chunk_size: 1024,
  }
  let r1 = @crypto.x25519_keypair_from_secret(v070_make_secret(11))
  let r2 = @crypto.x25519_keypair_from_secret(v070_make_secret(12))
  let r3 = @crypto.x25519_keypair_from_secret(v070_make_secret(13))
  let eph = @crypto.x25519_keypair_from_secret(v070_make_secret(14))
  let cek = v070_make_secret(15)
  let nonce_prefix = b"\x11\x22\x33\x44"
  let plain = Bytes::makei(2500, i => ((i * 41 + 9) % 256).to_byte())
  let ct = @crypto.seal_envelope(
    plain,
    [r1.public_key, r2.public_key, r3.public_key],
    eph.secret_key,
    cek,
    nonce_prefix,
    opts,
    limits,
  )
  let header_len = 51 + 3 * 56

  // Header magic and version tampering
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(v070_flip_byte(ct, 0), r1.secret_key, limits),
      )
    },
    "InvalidFormat:magic",
  )
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(
          v070_set_byte(ct, 8, b'\x01'),
          r1.secret_key,
          limits,
        ),
      )
    },
    "InvalidFormat:version",
  )

  // Header chunk_size tampered from 1024 (0x00000400) to 2048 (0x00000800):
  // header still parses, recipient unwrap succeeds, payload chunk header_aad fails!
  let bad_cs = v070_set_byte(v070_set_byte(ct, 13, b'\x08'), 14, b'\x00')
  v070_expect_err(
    () => ignore(@crypto.unseal_envelope(bad_cs, r1.secret_key, limits)),
    "AuthenticationFailed",
  )

  // Header nonce_prefix tamper -> AuthenticationFailed
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(v070_flip_byte(ct, 15), r1.secret_key, limits),
      )
    },
    "AuthenticationFailed",
  )

  // Header ephemeral_public_key tamper -> AuthenticationFailed
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(v070_flip_byte(ct, 25), r1.secret_key, limits),
      )
    },
    "AuthenticationFailed",
  )

  // Own recipient slot (slot 0) key_id tamper -> no matching slot -> AuthenticationFailed
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(v070_flip_byte(ct, 51), r1.secret_key, limits),
      )
    },
    "AuthenticationFailed",
  )

  // Own recipient slot (slot 0) wrapped_cek tamper -> AuthenticationFailed
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(v070_flip_byte(ct, 60), r1.secret_key, limits),
      )
    },
    "AuthenticationFailed",
  )

  // ANOTHER recipient's slot (slot 2) wrapped_cek tamper -> header_aad mismatch -> AuthenticationFailed for r1!
  let slot2_cek_offset = 51 + 2 * 56 + 10
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(
          v070_flip_byte(ct, slot2_cek_offset),
          r1.secret_key,
          limits,
        ),
      )
    },
    "AuthenticationFailed",
  )

  // Ciphertext body and Poly1305 tag tamper -> AuthenticationFailed
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(
          v070_flip_byte(ct, header_len + 5),
          r1.secret_key,
          limits,
        ),
      )
    },
    "AuthenticationFailed",
  )
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(
          v070_flip_byte(ct, ct.length() - 1),
          r1.secret_key,
          limits,
        ),
      )
    },
    "AuthenticationFailed",
  )

  // Trailing byte appended -> TrailingData
  v070_expect_err(
    () => ignore(@crypto.unseal_envelope(ct + b"\x00", r1.secret_key, limits)),
    "TrailingData",
  )

  // Truncated inputs at multiple boundaries -> TruncatedInput
  for
    cut in [
      0,
      10,
      50,
      51,
      header_len - 1,
      header_len,
      header_len + 4,
      header_len + 5,
      ct.length() - 1,
    ] {
    let truncated = ct[0:cut].to_owned()
    v070_expect_err(
      () => ignore(@crypto.unseal_envelope(truncated, r1.secret_key, limits)),
      "TruncatedInput",
    )
  }

  // Duplicate recipient rejected
  v070_expect_err(
    () => {
      ignore(
        @crypto.seal_envelope(
          b"dup",
          [r1.public_key, r2.public_key, r1.public_key],
          eph.secret_key,
          cek,
          nonce_prefix,
          opts,
          limits,
        ),
      )
    },
    "InvalidOptions:duplicate_recipient",
  )

  // Empty recipients and >64 recipients rejected
  v070_expect_err(
    () => {
      ignore(
        @crypto.seal_envelope(
          b"none",
          [],
          eph.secret_key,
          cek,
          nonce_prefix,
          opts,
          limits,
        ),
      )
    },
    "InvalidOptions:recipient_count",
  )
  let too_many : Array[Bytes] = []
  for i in 0..<65 {
    too_many.push(@crypto.x25519_public_from_secret(v070_make_secret(100 + i)))
  }
  v070_expect_err(
    () => {
      ignore(
        @crypto.seal_envelope(
          b"many",
          too_many,
          eph.secret_key,
          cek,
          nonce_prefix,
          opts,
          limits,
        ),
      )
    },
    "InvalidOptions:recipient_count",
  )

  // Invalid CEK and nonce_prefix lengths
  v070_expect_err(
    () => {
      ignore(
        @crypto.seal_envelope(
          b"x",
          [r1.public_key],
          eph.secret_key,
          b"short",
          nonce_prefix,
          opts,
          limits,
        ),
      )
    },
    "InvalidKey:content_key",
  )
  v070_expect_err(
    () => {
      ignore(
        @crypto.seal_envelope(
          b"x",
          [r1.public_key],
          eph.secret_key,
          cek,
          b"\x01\x02\x03",
          opts,
          limits,
        ),
      )
    },
    "InvalidOptions:nonce_prefix",
  )

  // Limits enforcement
  v070_expect_err(
    () => {
      ignore(
        @crypto.seal_envelope(
          plain,
          [r1.public_key],
          eph.secret_key,
          cek,
          nonce_prefix,
          opts,
          { ..limits, max_input_bytes: 100L, },
        ),
      )
    },
    "LimitExceeded:max_input_bytes",
  )
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(ct, r1.secret_key, {
          ..limits,
          max_output_bytes: 1000L,
        }),
      )
    },
    "LimitExceeded:max_output_bytes",
  )
  v070_expect_err(
    () => {
      ignore(
        @crypto.inspect_envelope_header(ct[:], {
          ..limits,
          max_chunk_size: 1024,
        }),
      )
      ignore(
        @crypto.inspect_envelope_header(
          @crypto.seal_envelope(
            b"hi",
            [r1.public_key],
            eph.secret_key,
            cek,
            nonce_prefix,
            @crypto.SealOptions::default(),
            limits,
          )[:],
          { ..limits, max_chunk_size: 2048, },
        ),
      )
    },
    "LimitExceeded:chunk_size",
  )
}

///|
test "TrustKeyring creation deterministic sorting Schema 4 encode/parse and strict validation" {
  let kp1 = @crypto.keypair_from_seed(v070_ed25519_seed(1))
  let kp2 = @crypto.keypair_from_seed(v070_ed25519_seed(2))
  let kp3 = @crypto.keypair_from_seed(v070_ed25519_seed(3))
  let kp4 = @crypto.keypair_from_seed(v070_ed25519_seed(4))
  let id3 = @crypto.key_id_from_public_key(kp3.public_key)
  let id4 = @crypto.key_id_from_public_key(kp4.public_key)

  // Input order independence: reversed order produces identical keyring and JSON
  let kr_a = @crypto.create_trust_keyring(
    [kp3.public_key, kp1.public_key, kp2.public_key],
    [id4, id3],
    2,
  )
  let kr_b = @crypto.create_trust_keyring(
    [kp1.public_key, kp2.public_key, kp3.public_key],
    [id3, id4],
    2,
  )
  assert_true(kr_a == kr_b)
  assert_eq(kr_a.min_quorum, 2)
  assert_eq(kr_a.trusted_keys.length(), 3)
  assert_eq(kr_a.revoked_key_ids.length(), 2)
  // Verify sorted order
  assert_true(
    @crypto.key_id_from_public_key(kr_a.trusted_keys[0]) <
    @crypto.key_id_from_public_key(kr_a.trusted_keys[1]),
  )
  assert_true(
    @crypto.key_id_from_public_key(kr_a.trusted_keys[1]) <
    @crypto.key_id_from_public_key(kr_a.trusted_keys[2]),
  )
  assert_true(kr_a.revoked_key_ids[0] < kr_a.revoked_key_ids[1])

  // Encode / parse roundtrip
  let encoded = @crypto.encode_trust_keyring(kr_a)
  assert_eq(encoded, @crypto.encode_trust_keyring(kr_b))
  let parsed = @crypto.parse_trust_keyring(encoded)
  assert_true(parsed == kr_a)

  // Verify exact Schema 4 JSON fields
  let json_text = @utf8.decode(encoded)
  assert_true(
    json_text.has_prefix(
      "{\"schema\":4,\"kind\":\"moonlibsync-keyring\",\"min_quorum\":2,\"trusted_keys_hex\":[",
    ),
  )
  assert_true(json_text.has_suffix("]}\n"))

  // Creation validation errors
  v070_expect_err(
    () => ignore(@crypto.create_trust_keyring([], [], 1)),
    "InvalidOptions:min_quorum",
  )
  v070_expect_err(
    () => ignore(@crypto.create_trust_keyring([kp1.public_key], [], 0)),
    "InvalidOptions:min_quorum",
  )
  v070_expect_err(
    () => ignore(@crypto.create_trust_keyring([kp1.public_key], [], 2)),
    "InvalidOptions:min_quorum",
  )
  // 3 trusted keys with 1 revoked -> active_count = 2 -> min_quorum = 3 must fail!
  v070_expect_err(
    () => {
      ignore(
        @crypto.create_trust_keyring(
          [kp1.public_key, kp2.public_key, kp3.public_key],
          [id3],
          3,
        ),
      )
    },
    "InvalidOptions:min_quorum",
  )
  // Duplicate trusted key
  v070_expect_err(
    () => {
      ignore(
        @crypto.create_trust_keyring([kp1.public_key, kp1.public_key], [], 1),
      )
    },
    "InvalidOptions:duplicate_key",
  )
  // Duplicate revoked key ID
  v070_expect_err(
    () => {
      ignore(
        @crypto.create_trust_keyring(
          [kp1.public_key, kp2.public_key],
          [id3, id3],
          1,
        ),
      )
    },
    "InvalidOptions:duplicate_revoked_key_id",
  )
  // Invalid revoked key ID format (uppercase / wrong len)
  v070_expect_err(
    () => {
      ignore(
        @crypto.create_trust_keyring([kp1.public_key], ["0123456789ABCDEF"], 1),
      )
    },
    "InvalidFormat:revoked_key_id",
  )
  v070_expect_err(
    () => {
      ignore(@crypto.create_trust_keyring([kp1.public_key], ["deadbeef"], 1))
    },
    "InvalidFormat:revoked_key_id",
  )
  // Invalid Ed25519 key (low-order all-zero)
  v070_expect_err(
    () => {
      ignore(@crypto.create_trust_keyring([Bytes::make(32, b'\x00')], [], 1))
    },
    "InvalidKey:public_key_low_order",
  )

  // Strict JSON parser rejections
  let cases : Array[(Bytes, String)] = [
    // Unknown extra field
    (
      @utf8.encode(
        json_text.replace(
          old="\"schema\":4",
          new="\"schema\":4,\"unknown_field\":1",
        ),
      ),
      "InvalidFormat:schema",
    ),
    // Duplicate JSON key
    (
      @utf8.encode(
        json_text.replace(old="\"schema\":4", new="\"schema\":4,\"schema\":4"),
      ),
      "InvalidFormat:json",
    ),
    // Wrong schema number
    (
      @utf8.encode(json_text.replace(old="\"schema\":4", new="\"schema\":3")),
      "InvalidFormat:schema",
    ),
    // Float schema number
    (
      @utf8.encode(json_text.replace(old="\"schema\":4", new="\"schema\":4.0")),
      "InvalidFormat:schema",
    ),
    // Wrong kind
    (
      @utf8.encode(
        json_text.replace(old="moonlibsync-keyring", new="moonlibsync-other"),
      ),
      "InvalidFormat:kind",
    ),
    // Bad quorum > active_count
    (
      @utf8.encode(
        json_text.replace(old="\"min_quorum\":2", new="\"min_quorum\":3"),
      ),
      "InvalidOptions:min_quorum",
    ),
    // Float min_quorum
    (
      @utf8.encode(
        json_text.replace(old="\"min_quorum\":2", new="\"min_quorum\":2.0"),
      ),
      "InvalidFormat:min_quorum",
    ),
    // UTF-8 BOM
    (b"\xef\xbb\xbf" + encoded, "InvalidFormat:utf8_bom"),
    // Oversized JSON
    (Bytes::make(65537, b' '), "LimitExceeded:keyring_json_bytes"),
  ]
  for item in cases {
    let (bad_bytes, expected) = item
    v070_expect_err(
      () => ignore(@crypto.parse_trust_keyring(bad_bytes)),
      expected,
    )
  }
}

///|
test "SignatureBundle Schema 4 encode/parse and 2-of-3 Ed25519 quorum verification with revocation" {
  let seed1 = v070_ed25519_seed(21)
  let seed2 = v070_ed25519_seed(22)
  let seed3 = v070_ed25519_seed(23)
  let seed_untrusted = v070_ed25519_seed(24)

  let kp1 = @crypto.keypair_from_seed(seed1)
  let kp2 = @crypto.keypair_from_seed(seed2)
  let kp3 = @crypto.keypair_from_seed(seed3)
  let kp_untrusted = @crypto.keypair_from_seed(seed_untrusted)

  let id1 = @crypto.key_id_from_public_key(kp1.public_key)
  let id2 = @crypto.key_id_from_public_key(kp2.public_key)
  let id3 = @crypto.key_id_from_public_key(kp3.public_key)
  let id_untrusted = @crypto.key_id_from_public_key(kp_untrusted.public_key)

  let payload = b"moonlibsync release v0.7.0 canonical artifact payload"
  let sig1 = @crypto.sign_bytes(seed1, payload)
  let sig2 = @crypto.sign_bytes(seed2, payload)
  let sig3 = @crypto.sign_bytes(seed3, payload)
  let sig_untrusted = @crypto.sign_bytes(seed_untrusted, payload)

  // Keyring: 2-of-3 active trusted keys (no revocations)
  let kr_2of3 = @crypto.create_trust_keyring(
    [kp1.public_key, kp2.public_key, kp3.public_key],
    [],
    2,
  )

  // 2 valid trusted signers pass + encode/parse bundle roundtrip
  let bundle_2valid = @crypto.create_signature_bundle([sig1, sig2])
  let bundle_json = @crypto.encode_signature_bundle(bundle_2valid)
  let bundle_text = @utf8.decode(bundle_json)
  assert_true(
    bundle_text.has_prefix(
      "{\"schema\":4,\"kind\":\"moonlibsync-signature-bundle\",\"payload_length\":\"\{payload.length()}\",",
    ),
  )
  let bundle_parsed = @crypto.parse_signature_bundle(bundle_json)
  assert_true(bundle_parsed == bundle_2valid)

  let report_ok = @crypto.verify_quorum_bytes(bundle_parsed, kr_2of3, payload)
  assert_true(
    report_ok ==
    {
      verified_key_ids: [id1, id2],
      rejected_key_ids: [],
      revoked_hits: [],
      required_quorum: 2,
    },
  )

  // 1 valid + 1 untrusted fails (UntrustedKey:quorum_not_met)
  let bundle_1valid_1untrusted = @crypto.create_signature_bundle([
    sig1, sig_untrusted,
  ])
  v070_expect_err(
    () => {
      ignore(
        @crypto.verify_quorum_bytes(bundle_1valid_1untrusted, kr_2of3, payload),
      )
    },
    "UntrustedKey:quorum_not_met",
  )

  // 2 valid + 1 untrusted passes and records rejected untrusted key
  let bundle_2valid_1untrusted = @crypto.create_signature_bundle([
    sig1, sig_untrusted, sig2,
  ])
  let report_with_untrusted = @crypto.verify_quorum_bytes(
    bundle_2valid_1untrusted, kr_2of3, payload,
  )
  assert_true(
    report_with_untrusted ==
    {
      verified_key_ids: [id1, id2],
      rejected_key_ids: [id_untrusted],
      revoked_hits: [],
      required_quorum: 2,
    },
  )

  // 1 valid + 1 forged (tampered Ed25519 signature byte) fails (UntrustedKey:quorum_not_met)
  let sig2_raw = @crypto.decode_key_hex(sig2.signature_hex, 64, "sig2")
  let sig2_forged : @crypto.PublisherSignature = {
    ..sig2,
    signature_hex: @crypto.encode_key_hex(v070_flip_byte(sig2_raw, 63)),
  }
  let bundle_1valid_1forged = @crypto.create_signature_bundle([
    sig1, sig2_forged,
  ])
  v070_expect_err(
    () => {
      ignore(
        @crypto.verify_quorum_bytes(bundle_1valid_1forged, kr_2of3, payload),
      )
    },
    "UntrustedKey:quorum_not_met",
  )

  // Keyring with kp3 revoked (2 active keys remain, min_quorum = 2)
  let kr_revoked = @crypto.create_trust_keyring(
    [kp1.public_key, kp2.public_key, kp3.public_key],
    [id3],
    2,
  )

  // 1 valid + 1 revoked fails (UntrustedKey:quorum_not_met)
  let bundle_1valid_1revoked = @crypto.create_signature_bundle([sig1, sig3])
  v070_expect_err(
    () => {
      ignore(
        @crypto.verify_quorum_bytes(bundle_1valid_1revoked, kr_revoked, payload),
      )
    },
    "UntrustedKey:quorum_not_met",
  )

  // 2 valid + 1 revoked passes with revoked_hits recorded!
  let bundle_2valid_1revoked = @crypto.create_signature_bundle([
    sig1, sig3, sig2,
  ])
  let report_revoked = @crypto.verify_quorum_bytes(
    bundle_2valid_1revoked, kr_revoked, payload,
  )
  assert_true(
    report_revoked ==
    {
      verified_key_ids: [id1, id2],
      rejected_key_ids: [id3],
      revoked_hits: [id3],
      required_quorum: 2,
    },
  )

  // Duplicate signer rejected both at creation and in verify_quorum_bytes
  v070_expect_err(
    () => ignore(@crypto.create_signature_bundle([sig1, sig1])),
    "InvalidSignature:duplicate_signer",
  )
  let raw_dup_bundle : @crypto.SignatureBundle = {
    payload_length: sig1.payload_length,
    payload_sha256: sig1.payload_sha256,
    signatures: [sig1, sig1],
  }
  v070_expect_err(
    () => ignore(@crypto.verify_quorum_bytes(raw_dup_bundle, kr_2of3, payload)),
    "InvalidSignature:duplicate_signer",
  )

  // Payload tamper rejected with DigestMismatch
  v070_expect_err(
    () => {
      ignore(
        @crypto.verify_quorum_bytes(
          bundle_2valid,
          kr_2of3,
          v070_flip_byte(payload, 0),
        ),
      )
    },
    "DigestMismatch:payload_sha256",
  )
  v070_expect_err(
    () => {
      ignore(
        @crypto.verify_quorum_bytes(bundle_2valid, kr_2of3, payload + b"!"),
      )
    },
    "DigestMismatch:payload_length",
  )

  // Bundle with mismatched payload digests across signatures rejected
  let sig2_other = @crypto.sign_bytes(seed2, b"different payload")
  v070_expect_err(
    () => ignore(@crypto.create_signature_bundle([sig1, sig2_other])),
    "DigestMismatch:bundle_payload_mismatch",
  )

  // Strict bundle JSON parser rejects unknown fields and bad schema
  v070_expect_err(
    () => {
      ignore(
        @crypto.parse_signature_bundle(
          @utf8.encode(
            bundle_text.replace(
              old="\"schema\":4",
              new="\"schema\":4,\"extra\":true",
            ),
          ),
        ),
      )
    },
    "InvalidFormat:schema",
  )
  v070_expect_err(
    () => {
      ignore(
        @crypto.parse_signature_bundle(
          @utf8.encode(
            bundle_text.replace(
              old="\"algorithm\":\"ed25519\"",
              new="\"algorithm\":\"ed25519\",\"extra\":1",
            ),
          ),
        ),
      )
    },
    "InvalidFormat:signature_schema",
  )

  // Streaming large (>4 GiB) payload_length via verify_quorum_digest roundtrip
  let large_len = 5000000000L
  let large_sha = sig1.payload_sha256
  let large_s1 = @crypto.sign_digest(seed1, large_len, large_sha)
  let large_s2 = @crypto.sign_digest(seed2, large_len, large_sha)
  let large_bundle = @crypto.parse_signature_bundle(
    @crypto.encode_signature_bundle(
      @crypto.create_signature_bundle([large_s1, large_s2]),
    ),
  )
  let large_report = @crypto.verify_quorum_digest(
    large_bundle, kr_2of3, large_len, large_sha,
  )
  assert_eq(large_report.verified_key_ids, [id1, id2])
  assert_eq(large_report.required_quorum, 2)
}

///|
test "MLSENC02 inspect_envelope_header edge cases slot swap and chunk reorder rejection" {
  let limits = @crypto.SealLimits::default()
  let opts : @crypto.SealOptions = {
    ..@crypto.SealOptions::default(),
    chunk_size: 1024,
  }
  let r1 = @crypto.x25519_keypair_from_secret(v070_make_secret(31))
  let r2 = @crypto.x25519_keypair_from_secret(v070_make_secret(32))
  let eph = @crypto.x25519_keypair_from_secret(v070_make_secret(33))
  let cek = v070_make_secret(34)
  let plain = Bytes::makei(2500, i => ((i * 17 + 13) % 256).to_byte())
  let ct = @crypto.seal_envelope(
    plain,
    [r1.public_key, r2.public_key],
    eph.secret_key,
    cek,
    b"\xde\xad\xbe\xef",
    opts,
    limits,
  )

  // inspect_envelope_header rejects 0 recipients, 65 recipients, bad chunk_size, low-order eph pub, duplicate slot IDs
  v070_expect_err(
    () => {
      ignore(
        @crypto.inspect_envelope_header(
          v070_set_byte(v070_set_byte(ct, 9, b'\x00'), 10, b'\x00')[:],
          limits,
        ),
      )
    },
    "InvalidFormat:recipient_count",
  )
  v070_expect_err(
    () => {
      ignore(
        @crypto.inspect_envelope_header(
          v070_set_byte(v070_set_byte(ct, 9, b'\x00'), 10, b'\x41')[:],
          limits,
        ),
      )
    },
    "InvalidFormat:recipient_count",
  )
  // Zero out ephemeral public key (bytes 19..51)
  let mut zero_eph = ct
  for i in 19..<51 {
    zero_eph = v070_set_byte(zero_eph, i, b'\x00')
  }
  v070_expect_err(
    () => ignore(@crypto.inspect_envelope_header(zero_eph[:], limits)),
    "InvalidKey:ephemeral_public_key",
  )
  // Copy slot 0 key_id into slot 1 -> duplicate_recipient
  let mut dup_slot = ct
  for j in 0..<8 {
    dup_slot = v070_set_byte(dup_slot, 51 + 56 + j, ct[51 + j])
  }
  v070_expect_err(
    () => ignore(@crypto.inspect_envelope_header(dup_slot[:], limits)),
    "InvalidFormat:duplicate_recipient",
  )

  // Swap slot 0 and slot 1: slot_index is bound in wrap_nonce & wrap_aad -> AuthenticationFailed
  let swapped_slots = ct[0:51].to_owned() +
    ct[51 + 56:51 + 112].to_owned() +
    ct[51:51 + 56].to_owned() +
    ct[51 + 112:].to_owned()
  v070_expect_err(
    () => ignore(@crypto.unseal_envelope(swapped_slots, r1.secret_key, limits)),
    "AuthenticationFailed",
  )
  v070_expect_err(
    () => ignore(@crypto.unseal_envelope(swapped_slots, r2.secret_key, limits)),
    "AuthenticationFailed",
  )

  // Swap chunk 0 and chunk 1 (both 1024B plain -> 1045B frame): chunk_index bound -> AuthenticationFailed
  let header_len = 51 + 2 * 56
  let frame_len = 5 + 1024 + 16
  let swapped_chunks = ct[0:header_len].to_owned() +
    ct[header_len + frame_len:header_len + 2 * frame_len].to_owned() +
    ct[header_len:header_len + frame_len].to_owned() +
    ct[header_len + 2 * frame_len:].to_owned()
  v070_expect_err(
    () => ignore(@crypto.unseal_envelope(swapped_chunks, r1.secret_key, limits)),
    "AuthenticationFailed",
  )

  // Invalid chunk flags (0x02) -> InvalidFormat:chunk_final_flag
  v070_expect_err(
    () => {
      ignore(
        @crypto.unseal_envelope(
          v070_set_byte(ct, header_len + 4, b'\x02'),
          r1.secret_key,
          limits,
        ),
      )
    },
    "InvalidFormat:chunk_final_flag",
  )
}

///|
test "crypto 0.7.0 red-team hardening: canonical X25519 keys non-zero CEK and bounded O(K+S) keyring" {
  let limits = @crypto.SealLimits::default()
  let opts = @crypto.SealOptions::default()
  let r1 = @crypto.x25519_keypair_from_secret(v070_make_secret(71))
  let eph = @crypto.x25519_keypair_from_secret(v070_make_secret(72))
  let cek = Bytes::make(32, b'\x44')
  let nonce_prefix = b"\x01\x02\x03\x04"

  // Non-canonical X25519 pubkey (bit 255 set) rejected in x25519_key_id and seal_envelope
  let high_bit_pub = v070_set_byte(
    r1.public_key,
    31,
    (r1.public_key[31].to_int() | 0x80).to_byte(),
  )
  v070_expect_err(
    () => ignore(@crypto.x25519_key_id(high_bit_pub)),
    "InvalidKey:x25519_public_key",
  )
  v070_expect_err(
    () => {
      ignore(
        @crypto.seal_envelope(
          b"test",
          [high_bit_pub],
          eph.secret_key,
          cek,
          nonce_prefix,
          opts,
          limits,
        ),
      )
    },
    "InvalidKey:recipient_public_key",
  )

  // Non-canonical u >= p with bit 255 == 0 (u = p + 9 = 0x7fff...fff6 -> LE: f6 ff ... ff 7f)
  let non_canon_ge_p = Bytes::makei(32, i => {
    if i == 0 {
      b'\xf6'
    } else if i == 31 {
      b'\x7f'
    } else {
      b'\xff'
    }
  })
  v070_expect_err(
    () => ignore(@crypto.x25519_key_id(non_canon_ge_p)),
    "InvalidKey:x25519_public_key",
  )

  // All-zero content_key rejected
  v070_expect_err(
    () => {
      ignore(
        @crypto.seal_envelope(
          b"test",
          [r1.public_key],
          eph.secret_key,
          Bytes::make(32, b'\x00'),
          nonce_prefix,
          opts,
          limits,
        ),
      )
    },
    "InvalidKey:content_key",
  )

  // TrustKeyring caps >64 trusted keys and >256 revoked key IDs
  let keys64 : Array[Bytes] = []
  let keys65 : Array[Bytes] = []
  for i in 0..<65 {
    let kp = @crypto.keypair_from_seed(v070_ed25519_seed(10 + i))
    if i < 64 {
      keys64.push(kp.public_key)
    }
    keys65.push(kp.public_key)
  }
  v070_expect_err(
    () => ignore(@crypto.create_trust_keyring(keys65, [], 1)),
    "LimitExceeded:trusted_keys",
  )
  let revoked257 : Array[String] = []
  for i in 0..<257 {
    let id = @crypto.key_id_from_public_key(
      @crypto.keypair_from_seed(v070_ed25519_seed(100 + i)).public_key,
    )
    revoked257.push(id)
  }
  v070_expect_err(
    () => ignore(@crypto.create_trust_keyring([keys64[0]], revoked257, 1)),
    "LimitExceeded:revoked_key_ids",
  )

  // 64-key keyring with 64-signature bundle verifies fast & accurately
  let payload = b"64x64 quorum performance check"
  let sigs64 : Array[@crypto.PublisherSignature] = []
  for i in 0..<64 {
    sigs64.push(@crypto.sign_bytes(v070_ed25519_seed(10 + i), payload))
  }
  let bundle64 = @crypto.create_signature_bundle(sigs64)
  let kr64 = @crypto.create_trust_keyring(keys64, [], 64)
  let report64 = @crypto.verify_quorum_bytes(bundle64, kr64, payload)
  assert_eq(report64.verified_key_ids.length(), 64)
  assert_eq(report64.rejected_key_ids.length(), 0)
}
