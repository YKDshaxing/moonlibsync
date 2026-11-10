// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn manifest_error(
  action : () -> Unit raise @moonlibsync.ManifestError,
  expected : String,
) -> Unit raise {
  let result = try {
    action()
    "success"
  } catch {
    @moonlibsync.ManifestError::InvalidUtf8 => "InvalidUtf8"
    @moonlibsync.ManifestError::InvalidJson => "InvalidJson"
    @moonlibsync.ManifestError::InvalidSchema => "InvalidSchema"
    @moonlibsync.ManifestError::InvalidField(field) => "Field:" + field
    @moonlibsync.ManifestError::BindingMismatch(field) => "Binding:" + field
    @moonlibsync.ManifestError::ResourceLimit(field) => "Resource:" + field
    @moonlibsync.ManifestError::HashFailure => "HashFailure"
    @moonlibsync.ManifestError::Core(error) =>
      match error {
        InvalidOptions(field) => "Core:InvalidOptions:" + field
        UnsupportedSignatureProfile => "Core:UnsupportedSignatureProfile"
        TruncatedInput => "Core:TruncatedInput"
        InvalidSignature => "Core:InvalidSignature"
        InvalidDelta => "Core:InvalidDelta"
        InvalidOpcode => "Core:InvalidOpcode"
        IntegerOutOfRange => "Core:IntegerOutOfRange"
        CopyOutOfBounds => "Core:CopyOutOfBounds"
        TrailingData => "Core:TrailingData"
        LimitExceeded => "Core:LimitExceeded"
      }
  }
  assert_eq(result, expected)
}

///|
fn basis_json() -> String {
  // Independent Python hashlib/json oracle, also in tests/integrity/basis.json.
  "{\"schema_version\":1,\"kind\":\"moonlibsync-basis-info\",\"basis\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"},\"signature\":{\"byte_length\":\"48\",\"sha256\":\"59a030db700124f21acc20a3563329bb1d90b64c8e8de59f19cbc0ead26c9573\"}}\n"
}

///|
fn manifest_sig() -> Bytes {
  b"\x72\x73\x01\x47\x00\x00\x08\x00\x00\x00\x00\x20\x66\x29\x89\x23\xbd\xdd\x81\x3c\x63\x42\x39\x72\x31\x71\xef\x3f\xee\x98\x57\x9b\x94\x96\x4e\x3b\xb1\xcb\x3e\x42\x72\x62\xc8\xc0\x68\xd5\x23\x19"
}

///|
fn manifest_bytes(text : String) -> Bytes {
  // Test inputs below are ASCII; explicit conversion avoids importing JSON into
  // the public client or trusting the manifest encoder as an input oracle.
  Bytes::makei(text.length(), i => text[i].to_int().to_byte())
}

///|
test "manifest public update schema delta and result fields are independently strict" {
  let d = @moonlibsync.Limits::default()
  let info = @moonlibsync.parse_basis_info(manifest_bytes(basis_json()), d)
  let value = @moonlibsync.create_update_manifest(
    info,
    manifest_sig(),
    b"abc",
    b"\x72\x73\x02\x36\x45\x00\x03\x00",
    d,
  )
  let good = "{\"schema_version\":1,\"kind\":\"librsync-delta\",\"basis\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"},\"signature\":{\"byte_length\":\"48\",\"sha256\":\"59a030db700124f21acc20a3563329bb1d90b64c8e8de59f19cbc0ead26c9573\"},\"delta\":{\"byte_length\":\"8\",\"sha256\":\"22120222ab5b762c88d44e81d72884fcd4ff5f2d82b02a6ae5edb0f56b3b1b53\"},\"result\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"}}\n"
  assert_eq(@moonlibsync.encode_update_manifest(value, d), manifest_bytes(good))
  for
    (text, error) in [
      (
        good.replace(old="librsync-delta", new="moonlibsync-basis-info"),
        "InvalidSchema",
      ),
      (
        good.replace(old="\"schema_version\":1", new="\"schema_version\":0"),
        "InvalidSchema",
      ),
      (
        good.replace(
          old="\"schema_version\":1",
          new="\"schema_version\":1,\"extra\":0",
        ),
        "InvalidSchema",
      ),
      (
        good.replace(
          old="\"schema_version\":1",
          new="\"schema_version\":1,\"schema_version\":1",
        ),
        "InvalidJson",
      ),
      (
        good.replace(
          old="\"delta\":{\"byte_length\":\"8\"",
          new="\"delta\":{\"byte_length\":\"4\"",
        ),
        "Field:delta.byte_length",
      ),
      (
        good.replace(
          old="\"signature\":{\"byte_length\":\"48\"",
          new="\"signature\":{\"byte_length\":\"11\"",
        ),
        "Field:signature.byte_length",
      ),
      (
        good.replace(
          old="\"result\":{\"byte_length\":\"3\"",
          new="\"result\":{\"byte_length\":\"03\"",
        ),
        "Field:byte_length",
      ),
      (
        good.replace(
          old="\"result\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"}",
          new="\"result\":{\"byte_length\":\"3\",\"sha256\":\"" +
            "A".repeat(64) +
            "\"}",
        ),
        "Field:result.sha256",
      ),
    ] {
    manifest_error(
      () => {
        let _ = @moonlibsync.parse_update_manifest(manifest_bytes(text), d)
      },
      error,
    )
  }
}

///|
fn parse_basis_error(text : String, expected : String) -> Unit raise {
  manifest_error(
    () => {
      let _ = @moonlibsync.parse_basis_info(
        manifest_bytes(text),
        @moonlibsync.Limits::default(),
      )
    },
    expected,
  )
}

///|
test "manifest public independent abc fields deterministic encoding and sender without OLD" {
  let d = @moonlibsync.Limits::default()
  let sig = manifest_sig()
  let delta = b"\x72\x73\x02\x36\x45\x00\x03\x00"
  let info = @moonlibsync.create_basis_info(b"abc", sig, d)
  assert_eq(info.basis.byte_length, 3L)
  assert_eq(
    info.basis.sha256,
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(info.signature.byte_length, 48L)
  assert_eq(
    info.signature.sha256,
    "59a030db700124f21acc20a3563329bb1d90b64c8e8de59f19cbc0ead26c9573",
  )
  assert_eq(
    @moonlibsync.encode_basis_info(info, d),
    manifest_bytes(basis_json()),
  )
  let value = @moonlibsync.create_update_manifest(info, sig, b"abc", delta, d)
  assert_eq(value.basis.byte_length, 3L)
  assert_eq(value.basis.sha256, info.basis.sha256)
  assert_eq(value.signature.byte_length, 48L)
  assert_eq(value.signature.sha256, info.signature.sha256)
  assert_eq(value.delta.byte_length, 8L)
  assert_eq(
    value.delta.sha256,
    "22120222ab5b762c88d44e81d72884fcd4ff5f2d82b02a6ae5edb0f56b3b1b53",
  )
  assert_eq(value.result.byte_length, 3L)
  assert_eq(value.result.sha256, info.basis.sha256)
  let encoded = @moonlibsync.encode_update_manifest(value, d)
  assert_eq(encoded, @moonlibsync.encode_update_manifest(value, d))
  let parsed = @moonlibsync.parse_update_manifest(encoded, d)
  assert_eq(parsed.result.sha256, value.result.sha256)
  assert_eq(@moonlibsync.encode_update_manifest(parsed, d), encoded)
}

///|
test "manifest public empty and nondefault signature parameters" {
  let d = @moonlibsync.Limits::default()
  for
    (old, options, delta) in [
      (b"", @moonlibsync.SignatureOptions::default(), b"\x72\x73\x02\x36\x00"),
      (
        b"\x00",
        { block_len: 7L, strong_sum_len: 1L, },
        b"\x72\x73\x02\x36\x45\x00\x01\x00",
      ),
    ] {
    let sig = @moonlibsync.signature(old, options, d)
    let info = @moonlibsync.create_basis_info(old, sig, d)
    let value = @moonlibsync.create_update_manifest(info, sig, old, delta, d)
    let parsed = @moonlibsync.parse_update_manifest(
      @moonlibsync.encode_update_manifest(value, d),
      d,
    )
    assert_eq(parsed.result.byte_length, old.length().to_int64())
    assert_eq(parsed.delta.byte_length, delta.length().to_int64())
    if old.length() == 0 {
      assert_eq(
        info.basis.sha256,
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      )
      let zero = {
        ..d,
        max_old_bytes: 0L,
        max_new_bytes: 0L,
        max_output_bytes: 0L,
        max_signature_bytes: 12L,
        max_signature_records: 0L,
        max_delta_bytes: 5L,
        max_instructions: 0L,
        max_match_work: 0L,
      }
      let empty_info = @moonlibsync.create_basis_info(old, sig, zero)
      let empty_manifest = @moonlibsync.create_update_manifest(
        empty_info, sig, old, delta, zero,
      )
      assert_eq(
        @moonlibsync.parse_update_manifest(
          @moonlibsync.encode_update_manifest(empty_manifest, zero),
          zero,
        ).result.byte_length,
        0L,
      )
    }
  }
}

///|
test "manifest public receiver refuses mismatching equal length OLD and malformed SIG" {
  let d = @moonlibsync.Limits::default()
  for old in [b"xyz", b"abcd"] {
    manifest_error(
      () => {
        let _ = @moonlibsync.create_basis_info(old, manifest_sig(), d)
      },
      "Binding:basis_signature",
    )
  }
  manifest_error(
    () => {
      let _ = @moonlibsync.create_basis_info(b"abc", b"bad", d)
    },
    "Core:TruncatedInput",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.create_basis_info(
        b"abc", b"\x72\x73\x01\x46\x00\x00\x08\x00\x00\x00\x00\x20", d,
      )
    },
    "Core:UnsupportedSignatureProfile",
  )
}

///|
test "manifest public sender performs actual SIG length and SHA binding" {
  let d = @moonlibsync.Limits::default()
  let info = @moonlibsync.create_basis_info(b"abc", manifest_sig(), d)
  let other = @moonlibsync.signature(
    b"xyz",
    @moonlibsync.SignatureOptions::default(),
    d,
  )
  let delta = b"\x72\x73\x02\x36\x45\x00\x03\x00"
  manifest_error(
    () => {
      let _ = @moonlibsync.create_update_manifest(info, other, b"abc", delta, d)
    },
    "Binding:signature_sha256",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.create_update_manifest(
        { ..info, signature: { ..info.signature, byte_length: 49L, }, },
        manifest_sig(),
        b"abc",
        delta,
        d,
      )
    },
    "Binding:signature_length",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.create_update_manifest(
        { ..info, signature: { ..info.signature, sha256: "A".repeat(64), }, },
        manifest_sig(),
        b"abc",
        delta,
        d,
      )
    },
    "Field:signature.sha256",
  )
}

///|
test "manifest public sender checks delta complete format result length and COPY range" {
  let d = @moonlibsync.Limits::default()
  let info = @moonlibsync.create_basis_info(b"abc", manifest_sig(), d)
  for
    (delta, new, error) in [
      (b"\x72\x73\x02\x36\x45\x00\x03\x00", b"abcd", "Binding:result_length"),
      (b"\x72\x73\x02\x36\x45\x02\x03\x00", b"abc", "Core:CopyOutOfBounds"),
      (b"\x72\x73\x02\x36\x55\x00", b"abc", "Core:InvalidOpcode"),
      (b"\x72\x73\x02\x36\x45\xff\x01", b"a", "Core:TruncatedInput"),
      (b"\x72\x73\x02\x36\x00\xff", b"", "Core:TrailingData"),
    ] {
    manifest_error(
      () => {
        let _ = @moonlibsync.create_update_manifest(
          info,
          manifest_sig(),
          new,
          delta,
          d,
        )
      },
      error,
    )
  }
}

///|
test "manifest public creation is metadata not verified recovery or authentication" {
  let d = @moonlibsync.Limits::default()
  let info = @moonlibsync.create_basis_info(b"abc", manifest_sig(), d)
  // Valid literal format and length, but no OLD exists at the sender to prove
  // these bytes recover NEW. Commit 22 must reject the eventual result mismatch.
  let value = @moonlibsync.create_update_manifest(
    info,
    manifest_sig(),
    b"abc",
    b"\x72\x73\x02\x36\x03xyz\x00",
    d,
  )
  assert_eq(value.result.sha256, info.basis.sha256)
  assert_eq(value.delta.byte_length, 9L)
  let untrusted = { ..info, basis: { ..info.basis, sha256: "0".repeat(64), }, }
  assert_eq(
    @moonlibsync.create_update_manifest(
      untrusted,
      manifest_sig(),
      b"abc",
      b"\x72\x73\x02\x36\x45\x00\x03\x00",
      d,
    ).basis.sha256,
    "0".repeat(64),
  )
}

///|
test "manifest public strict root schema kinds and exact field sets" {
  let good = basis_json()
  for
    text in [
      "[]",
      "null",
      "true",
      good.replace(old="\"schema_version\":1", new="\"schema_version\":2"),
      good.replace(old="\"schema_version\":1", new="\"schema_version\":1.0"),
      good.replace(old="\"schema_version\":1", new="\"schema_version\":1e0"),
      good.replace(old="moonlibsync-basis-info", new="librsync-delta"),
      good.replace(old="\"kind\":\"moonlibsync-basis-info\",", new=""),
      good.replace(
        old="\"schema_version\":1",
        new="\"schema_version\":1,\"unknown\":0",
      ),
      good.replace(
        old="\"byte_length\":\"3\"",
        new="\"byte_length\":\"3\",\"path\":\"x\"",
      ),
    ] {
    parse_basis_error(text, "InvalidSchema")
  }
}

///|
test "manifest public rejects duplicate keys including normalized escaped keys" {
  let good = basis_json()
  for
    text in [
      good.replace(
        old="\"schema_version\":1",
        new="\"schema_version\":1,\"schema_version\":1",
      ),
      good.replace(
        old="\"schema_version\":1",
        new="\"schema_version\":1,\"schema\\u005fversion\":1",
      ),
      good.replace(
        old="\"byte_length\":\"3\"",
        new="\"byte_length\":\"3\",\"byte_length\":\"3\"",
      ),
      good.replace(
        old="\"byte_length\":\"3\"",
        new="\"byte_length\":\"3\",\"byte\\u005flength\":\"3\"",
      ),
    ] {
    parse_basis_error(text, "InvalidJson")
  }
}

///|
test "manifest public rejects ambiguous field types arrays and numeric lengths" {
  let good = basis_json()
  parse_basis_error(
    good.replace(old="\"byte_length\":\"3\"", new="\"byte_length\":3"),
    "Field:byte_length",
  )
  parse_basis_error(
    good.replace(
      old="\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"",
      new="\"sha256\":null",
    ),
    "Field:sha256",
  )
  parse_basis_error(
    "{\"schema_version\":1,\"kind\":\"moonlibsync-basis-info\",\"basis\":[],\"signature\":[]}",
    "InvalidSchema",
  )
  parse_basis_error(
    good.replace(old="\"kind\":\"moonlibsync-basis-info\"", new="\"kind\":1"),
    "InvalidSchema",
  )
}

///|
test "manifest public canonical decimal syntax overflow and full digest syntax" {
  let good = basis_json()
  for
    text in [
      "-1",
      "+3",
      "01",
      "00",
      " 3",
      "3 ",
      "3.0",
      "1e0",
      "",
      "9223372036854775808",
      "9".repeat(100),
    ] {
    parse_basis_error(
      good.replace(
        old="\"byte_length\":\"3\"",
        new="\"byte_length\":\"" + text + "\"",
      ),
      "Field:byte_length",
    )
  }
  parse_basis_error(
    good.replace(
      old="\"byte_length\":\"3\"",
      new="\"byte_length\":\"9223372036854775807\"",
    ),
    "Resource:basis",
  )
  for
    digest in [
      "A".repeat(64),
      "g".repeat(64),
      "0".repeat(63),
      "0".repeat(65),
      " ".repeat(64),
    ] {
    parse_basis_error(
      good.replace(
        old="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        new=digest,
      ),
      "Field:basis.sha256",
    )
  }
}

///|
test "manifest public strict UTF8 no BOM complete JSON and trailing whitespace" {
  let d = @moonlibsync.Limits::default()
  let good = manifest_bytes(basis_json())
  for bytes in [b"\xff", b"\xc2", b"\xed\xa0\x80", b"\xc0\x80"] {
    manifest_error(
      () => {
        let _ = @moonlibsync.parse_basis_info(bytes, d)
      },
      "InvalidUtf8",
    )
  }
  for
    bytes in [b"\xef\xbb\xbf" + good, good + b"{}", good + b"x", b"{", b"\x00"] {
    manifest_error(
      () => {
        let _ = @moonlibsync.parse_basis_info(bytes, d)
      },
      "InvalidJson",
    )
  }
  assert_eq(
    @moonlibsync.parse_basis_info(good + b" \r\n\t", d).basis.byte_length,
    3L,
  )
}

///|
test "manifest public byte depth and post tree field limits" {
  let d = @moonlibsync.Limits::default()
  let good = basis_json()
  let exact = manifest_bytes(good + " ".repeat(65536 - good.length()))
  assert_eq(@moonlibsync.parse_basis_info(exact, d).basis.byte_length, 3L)
  manifest_error(
    () => {
      let _ = @moonlibsync.parse_basis_info(exact + b"\xff", d)
    },
    "Resource:manifest_bytes",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.parse_basis_info(exact + b"\xff", {
        ..d,
        max_old_bytes: -1L,
      })
    },
    "Core:InvalidOptions:max_old_bytes",
  )
  parse_basis_error(
    good.replace(
      old="\"byte_length\":\"3\"",
      new="\"byte_length\":{\"deep\":3}",
    ),
    "Resource:manifest_depth",
  )
  let fields = Array::makei(16, i => "\"k\{i}\":0").join(",")
  parse_basis_error("{" + fields + "}", "InvalidSchema")
  parse_basis_error("{" + fields + ",\"extra\":0}", "Resource:manifest_fields")
}

///|
test "manifest public encoder revalidates publicly constructed descriptors" {
  let d = @moonlibsync.Limits::default()
  let info = @moonlibsync.parse_basis_info(manifest_bytes(basis_json()), d)
  for
    (bad, error) in [
      (
        { ..info, basis: { ..info.basis, byte_length: -1L, }, },
        "Field:basis.byte_length",
      ),
      (
        { ..info, signature: { ..info.signature, byte_length: 11L, }, },
        "Field:signature.byte_length",
      ),
      (
        { ..info, basis: { ..info.basis, sha256: "\"}".repeat(32), }, },
        "Field:basis.sha256",
      ),
    ] {
    manifest_error(
      () => {
        let _ = @moonlibsync.encode_basis_info(bad, d)
      },
      error,
    )
  }
  let value = @moonlibsync.create_update_manifest(
    info,
    manifest_sig(),
    b"abc",
    b"\x72\x73\x02\x36\x45\x00\x03\x00",
    d,
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.encode_update_manifest(
        { ..value, delta: { ..value.delta, byte_length: 4L, }, },
        d,
      )
    },
    "Field:delta.byte_length",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.encode_update_manifest(
        { ..value, result: { ..value.result, byte_length: -1L, }, },
        d,
      )
    },
    "Field:result.byte_length",
  )
}

///|
test "manifest public creation input limits hash work and failure recovery" {
  let d = @moonlibsync.Limits::default()
  let sig = manifest_sig()
  let info = @moonlibsync.create_basis_info(b"abc", sig, d)
  let delta = b"\x72\x73\x02\x36\x45\x00\x03\x00"
  manifest_error(
    () => {
      let _ = @moonlibsync.create_basis_info(b"abc", sig, {
        ..d,
        max_old_bytes: 2L,
      })
    },
    "Resource:basis",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.create_basis_info(b"abc", sig, {
        ..d,
        max_signature_bytes: 47L,
      })
    },
    "Core:LimitExceeded",
  )
  for
    (limits, error) in [
      ({ ..d, max_new_bytes: 2L, }, "Resource:new"),
      ({ ..d, max_output_bytes: 2L, }, "Resource:result"),
      ({ ..d, max_delta_bytes: 7L, }, "Resource:delta"),
      ({ ..d, max_instructions: 0L, }, "Core:LimitExceeded"),
    ] {
    manifest_error(
      () => {
        let _ = @moonlibsync.create_update_manifest(
          info, sig, b"abc", delta, limits,
        )
      },
      error,
    )
  }
  let zero = { ..d, max_match_work: 0L, }
  let again = @moonlibsync.create_basis_info(b"abc", sig, zero)
  let result = @moonlibsync.create_update_manifest(
    again, sig, b"abc", delta, zero,
  )
  assert_eq(result.result.sha256, info.basis.sha256)
  assert_eq(sig, manifest_sig())
  assert_eq(delta, b"\x72\x73\x02\x36\x45\x00\x03\x00")
}
