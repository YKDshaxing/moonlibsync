// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn transfer_full_abc() -> String {
  "{\"schema_version\":2,\"kind\":\"full-file\",\"payload\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"},\"result\":{\"byte_length\":\"3\",\"sha256\":\"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\"}}\n"
}

///|
fn transfer_fixture(
  old : Bytes,
  new : Bytes,
  m~ : Int64 = 0L,
) -> (@moonlibsync.TransferManifest, @moonlibsync.UpdatePlan, Bytes) raise {
  let d = @moonlibsync.Limits::default()
  let sig = @moonlibsync.signature(
    old,
    { block_len: 8L, strong_sum_len: 32L, },
    d,
  )
  let info = @moonlibsync.create_basis_info(old, sig, d)
  let plan = @moonlibsync.plan_update(sig, new, { min_savings_bytes: m, }, d)
  let candidate = @moonlibsync.delta(sig, new, d)
  let manifest = @moonlibsync.create_transfer_manifest(
    info,
    sig,
    new,
    candidate,
    { min_savings_bytes: m, },
    d,
  )
  (manifest, plan, sig)
}

///|
fn transfer_payload(plan : @moonlibsync.UpdatePlan) -> Bytes {
  match plan.payload {
    Delta(p) | Full(p) => p
  }
}

///|
test "transfer public real selection and recovery with empty tiny unrelated reuse repeated" {
  let d = @moonlibsync.Limits::default()
  for
    (old, new, expected) in [
      (b"", b"", "full-file"),
      (b"abc", b"xyz", "full-file"),
      (b"abcdefgh", b"abcdefgh", "full-file"),
      (b"abcdefghijklmnop", b"abcdefghijklmnop", "librsync-delta"),
      (b"abcdefghijklmnop", b"!abcdefghijklmnop", "librsync-delta"),
      (b"aaaaaaaaaaaaaaaa", b"aaaaaaaaaaaaaaaa", "librsync-delta"),
    ] {
    let (m, plan, _) = transfer_fixture(old, new)
    assert_eq(plan.decision.kind, expected)
    let encoded = @moonlibsync.encode_transfer_manifest(m, d)
    let parsed = @moonlibsync.parse_transfer_manifest(encoded, d)
    assert_eq(
      @moonlibsync.apply_update(Some(old), transfer_payload(plan), parsed, d),
      new,
    )
    if expected == "full-file" {
      assert_eq(transfer_payload(plan), new)
      assert_eq(@moonlibsync.apply_update(None, new, parsed, d), new)
    }
  }
}

///|
test "transfer public actual candidate savings exactly threshold and one beyond" {
  let old = b"abcdefghijklmnop"
  let (_, plan, _) = transfer_fixture(old, old)
  assert_eq(plan.decision.delta_bytes, 8L)
  assert_eq(plan.decision.savings_bytes, 8L)
  let (_, exact, _) = transfer_fixture(old, old, m=8L)
  let (_, beyond, _) = transfer_fixture(old, old, m=9L)
  let (_, huge, _) = transfer_fixture(old, old, m=9223372036854775807L)
  assert_eq(exact.decision.kind, "librsync-delta")
  assert_eq(beyond.decision.reason, "below-minimum-savings")
  assert_eq(huge.decision.kind, "full-file")
}

///|
test "transfer public planner errors never fall back to Full" {
  let d = @moonlibsync.Limits::default()
  let sig = @moonlibsync.signature(
    b"abcdefghijklmnop",
    { block_len: 8L, strong_sum_len: 32L, },
    d,
  )
  let options = @moonlibsync.UpdateOptions::default()
  assert_eq(options.min_savings_bytes, 0L)
  transfer_reject(
    () => {
      let _ = @moonlibsync.plan_update(b"", b"", { min_savings_bytes: -1L, }, d)
    },
    "InvalidOptions:min_savings_bytes",
  )
  transfer_reject(
    () => {
      let _ = @moonlibsync.plan_update(b"", b"", options, {
        ..d,
        max_old_bytes: -1L,
      })
    },
    "InvalidOptions:max_old_bytes",
  )
  transfer_reject(
    () => {
      let _ = @moonlibsync.plan_update(sig, b"", options, {
        ..d,
        max_signature_bytes: 12L,
      })
    },
    "LimitExceeded",
  )
  transfer_reject(
    () => {
      let _ = @moonlibsync.plan_update(sig, b"xyz", options, {
        ..d,
        max_delta_bytes: 5L,
      })
    },
    "LimitExceeded",
  )
  transfer_reject(
    () => {
      let _ = @moonlibsync.plan_update(sig, b"abcdefghijklmnop", options, {
        ..d,
        max_match_work: 0L,
      })
    },
    "LimitExceeded",
  )
  transfer_reject(
    () => {
      let _ = @moonlibsync.plan_update(
        b"\x72\x73\x01\x36\x00\x00\x00\x08\x00\x00\x00\x20", b"abc", options, d,
      )
    },
    "UnsupportedSignatureProfile",
  )
  transfer_reject(
    () => {
      let _ = @moonlibsync.plan_update(b"", b"abc", options, d)
    },
    "TruncatedInput",
  )
  let full = @moonlibsync.plan_update(sig, b"xyz", options, d)
  assert_eq(transfer_payload(full), b"xyz")
  assert_eq(
    @moonlibsync.inspect_delta(@moonlibsync.delta(sig, b"xyz", d), d).output_bytes,
    3L,
  )
}

///|
test "transfer public schema2 independent Full encoding and schema separation" {
  let d = @moonlibsync.Limits::default()
  let text = transfer_full_abc()
  let parsed = @moonlibsync.parse_transfer_manifest(manifest_bytes(text), d)
  assert_eq(
    @moonlibsync.encode_transfer_manifest(parsed, d),
    manifest_bytes(text),
  )
  assert_eq(@moonlibsync.apply_update(None, b"abc", parsed, d), b"abc")
  manifest_error(
    () => {
      let _ = @moonlibsync.parse_update_manifest(manifest_bytes(text), d)
    },
    "InvalidSchema",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.parse_transfer_manifest(
        manifest_bytes(basis_json()),
        d,
      )
    },
    "InvalidSchema",
  )
}

///|
test "transfer public strict schema field types lengths digest and parser bounds" {
  let d = @moonlibsync.Limits::default()
  let good = transfer_full_abc()
  for
    (text, error) in [
      (
        good.replace(old="\"schema_version\":2", new="\"schema_version\":1"),
        "InvalidSchema",
      ),
      (
        good.replace(old="\"schema_version\":2", new="\"schema_version\":2.0"),
        "InvalidSchema",
      ),
      (good.replace(old="full-file", new="unknown"), "InvalidSchema"),
      (good.replace(old="full-file", new="librsync-delta"), "InvalidSchema"),
      (
        good.replace(old="\"payload\":", new="\"basis\":{},\"payload\":"),
        "InvalidSchema",
      ),
      (good.replace(old="\"3\"", new="\"03\""), "Field:byte_length"),
      (good.replace(old="\"3\"", new="3"), "Field:byte_length"),
      (
        good.replace(old="\"3\"", new="\"9223372036854775808\""),
        "Field:byte_length",
      ),
      (
        good.replace(old="\"3\"", new="\"9223372036854775807\""),
        "Resource:payload",
      ),
      (good.replace(old="ba7816", new="BA7816"), "Field:payload.sha256"),
      (
        good.replace(old="\"kind\":", new="\"kind\":\"full-file\",\"kind\":"),
        "InvalidJson",
      ),
      ("{\"x\":{\"y\":{}}}", "Resource:manifest_depth"),
      (
        "{\"a\":0,\"b\":0,\"c\":0,\"d\":0,\"e\":0,\"f\":0,\"g\":0,\"h\":0,\"i\":0,\"j\":0,\"k\":0,\"l\":0,\"m\":0,\"n\":0,\"o\":0,\"p\":0,\"q\":0}",
        "Resource:manifest_fields",
      ),
    ] {
    manifest_error(
      () => {
        let _ = @moonlibsync.parse_transfer_manifest(manifest_bytes(text), d)
      },
      error,
    )
  }
  manifest_error(
    () => {
      let _ = @moonlibsync.parse_transfer_manifest(b"\xff", d)
    },
    "InvalidUtf8",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.parse_transfer_manifest(
        b"\xef\xbb\xbf" + manifest_bytes(good),
        d,
      )
    },
    "InvalidJson",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.parse_transfer_manifest(Bytes::make(65537, b' '), d)
    },
    "Resource:manifest_bytes",
  )
}

///|
test "transfer public Full validates descriptors actual payload and ignores unused basis budgets" {
  let d = @moonlibsync.Limits::default()
  let m = @moonlibsync.parse_transfer_manifest(
    manifest_bytes(transfer_full_abc()),
    d,
  )
  let tiny = {
    ..d,
    max_delta_bytes: 0L,
    max_old_bytes: 0L,
    max_match_work: 0L,
    max_instructions: 0L,
  }
  assert_eq(@moonlibsync.apply_update(Some(b"unused"), b"abc", m, tiny), b"abc")
  manifest_error(
    () => {
      let _ = @moonlibsync.apply_update(None, b"ab", m, d)
    },
    "Binding:payload_length",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.apply_update(None, b"abd", m, d)
    },
    "Binding:payload_sha256",
  )
  for cap in [2L, 3L, 4L] {
    if cap == 2L {
      manifest_error(
        () => {
          let _ = @moonlibsync.apply_update(None, b"abc", m, {
            ..d,
            max_new_bytes: cap,
          })
        },
        "Resource:payload",
      )
      manifest_error(
        () => {
          let _ = @moonlibsync.apply_update(None, b"abc", m, {
            ..d,
            max_output_bytes: cap,
          })
        },
        "Resource:result",
      )
    } else {
      assert_eq(
        @moonlibsync.apply_update(None, b"abc", m, {
          ..tiny,
          max_new_bytes: cap,
          max_output_bytes: cap,
        }),
        b"abc",
      )
    }
  }
  manifest_error(
    () => {
      let _ = @moonlibsync.apply_update(None, b"abc", m, {
        ..d,
        max_old_bytes: -1L,
      })
    },
    "Core:InvalidOptions:max_old_bytes",
  )
  guard m is @moonlibsync.TransferManifest::Full(p, r) else {
    fail("expected Full")
  }
  let mismatch = @moonlibsync.TransferManifest::Full(p, {
    ..r,
    byte_length: 2L,
  })
  manifest_error(
    () => {
      let _ = @moonlibsync.encode_transfer_manifest(mismatch, d)
    },
    "Binding:result_length",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.apply_update(None, b"abc", mismatch, d)
    },
    "Binding:result_length",
  )
  let wrong = @moonlibsync.TransferManifest::Full(p, {
    ..r,
    sha256: "0".repeat(64),
  })
  manifest_error(
    () => {
      let _ = @moonlibsync.apply_update(None, b"abc", wrong, d)
    },
    "Binding:result_sha256",
  )
}

///|
test "transfer public Full starting with delta magic is raw bytes" {
  let new = b"\x72\x73\x02\x36\xff\x00"
  let (m, plan, _) = transfer_fixture(b"", new)
  assert_eq(plan.decision.kind, "full-file")
  assert_eq(
    @moonlibsync.apply_update(None, new, m, @moonlibsync.Limits::default()),
    new,
  )
}

///|
test "transfer public Delta requires correct basis payload and result before return" {
  let d = @moonlibsync.Limits::default()
  let old = b"abcdefghijklmnop"
  let (m, plan, _) = transfer_fixture(old, old)
  let payload = transfer_payload(plan)
  manifest_error(
    () => {
      let _ = @moonlibsync.apply_update(None, payload, m, d)
    },
    "Field:basis",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.apply_update(
        Some(b"ABCDEFGHIJKLMNOP"),
        payload,
        m,
        d,
      )
    },
    "Binding:basis_sha256",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.apply_update(
        Some(old),
        b"\x00" + payload[1:].to_owned(),
        m,
        d,
      )
    },
    "Binding:delta_sha256",
  )
  guard m is @moonlibsync.TransferManifest::Delta(v) else {
    fail("expected Delta")
  }
  let wrong = @moonlibsync.TransferManifest::Delta({
    ..v,
    result: { ..v.result, byte_length: 15L, },
  })
  manifest_error(
    () => {
      let _ = @moonlibsync.apply_update(Some(old), payload, wrong, d)
    },
    "Binding:result_length",
  )
  let wrong_hash = @moonlibsync.TransferManifest::Delta({
    ..v,
    result: { ..v.result, sha256: "0".repeat(64), },
  })
  manifest_error(
    () => {
      let _ = @moonlibsync.apply_update(Some(old), payload, wrong_hash, d)
    },
    "Binding:result_sha256",
  )
  assert_eq(@moonlibsync.apply_update(Some(old), payload, m, d), old)
  assert_eq(payload, transfer_payload(plan))
}

///|
test "transfer public sender still validates candidate even when Full would win" {
  let d = @moonlibsync.Limits::default()
  let sig = manifest_sig()
  let info = @moonlibsync.create_basis_info(b"abc", sig, d)
  manifest_error(
    () => {
      let wrong = {
        ..info,
        signature: { ..info.signature, sha256: "0".repeat(64), },
      }
      let _ = @moonlibsync.create_transfer_manifest(
        wrong,
        sig,
        b"abc",
        b"\x72\x73\x02\x36\x45\x00\x03\x00",
        @moonlibsync.UpdateOptions::default(),
        d,
      )
    },
    "Binding:signature_sha256",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.create_transfer_manifest(
        info,
        sig,
        b"abc",
        b"\x72\x73\x02\x36\xff",
        @moonlibsync.UpdateOptions::default(),
        d,
      )
    },
    "Core:InvalidOpcode",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.create_transfer_manifest(
        info,
        sig,
        b"abc",
        b"\x72\x73\x02\x36\x00",
        @moonlibsync.UpdateOptions::default(),
        d,
      )
    },
    "Binding:result_length",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.create_transfer_manifest(
        info,
        sig,
        b"abc",
        b"\x72\x73\x02\x36\x00",
        { min_savings_bytes: -1L, },
        d,
      )
    },
    "Core:InvalidOptions:min_savings_bytes",
  )
}

///|
fn transfer_reject(
  action : () -> Unit raise @moonlibsync.SyncError,
  expected : String,
) -> Unit raise {
  manifest_error(
    () => {
      action() catch {
        error => raise @moonlibsync.ManifestError::Core(error)
      }
    },
    "Core:" + expected,
  )
}
