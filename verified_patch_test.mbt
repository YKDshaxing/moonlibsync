// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn verified_fixture() -> (@moonlibsync.UpdateManifest, Bytes) raise {
  let d = @moonlibsync.Limits::default()
  let delta = b"\x72\x73\x02\x36\x45\x00\x03\x00"
  let info = @moonlibsync.create_basis_info(b"abc", manifest_sig(), d)
  (
    @moonlibsync.create_update_manifest(info, manifest_sig(), b"abc", delta, d),
    delta,
  )
}

///|
test "verified public roundtrips empty edits tails and signature parameters" {
  let d = @moonlibsync.Limits::default()
  for
    (old, new) in [
      (b"", b""),
      (b"abc", b"abc"),
      (b"abc", b"!abc"),
      (b"abcdefghijk", b"abc!efghijk?"),
      (b"", b"xyz"),
      (b"abc", b""),
    ] {
    for (block, sum) in [(1L, 1L), (7L, 16L), (2048L, 32L)] {
      let sig = @moonlibsync.signature(
        old,
        { block_len: block, strong_sum_len: sum, },
        d,
      )
      let info = @moonlibsync.create_basis_info(old, sig, d)
      let delta = @moonlibsync.delta(sig, new, d)
      let value = @moonlibsync.create_update_manifest(info, sig, new, delta, d)
      let parsed = @moonlibsync.parse_update_manifest(
        @moonlibsync.encode_update_manifest(value, d),
        d,
      )
      assert_eq(@moonlibsync.verified_patch(old, delta, parsed, d), new)
    }
  }
}

///|
test "verified public equal length wrong basis and damaged delta rejected before parse" {
  let d = @moonlibsync.Limits::default()
  let (v, delta) = verified_fixture()
  manifest_error(
    () => {
      let _ = @moonlibsync.verified_patch(b"xyz", delta, v, d)
    },
    "Binding:basis_sha256",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.verified_patch(
        b"abc", b"\x72\x73\x02\x36\x55\x00\x03\x00", v, d,
      )
    },
    "Binding:delta_sha256",
  )
}

///|
test "verified public actual input lengths checked before hashes" {
  let d = @moonlibsync.Limits::default()
  let (v, delta) = verified_fixture()
  manifest_error(
    () => {
      let _ = @moonlibsync.verified_patch(b"abcd", delta, v, d)
    },
    "Binding:basis_length",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.verified_patch(b"abc", b"", v, d)
    },
    "Binding:delta_length",
  )
}

///|
test "verified public factory accepts wrong literal but application rejects result digest" {
  let d = @moonlibsync.Limits::default()
  let delta = b"\x72\x73\x02\x36\x03xyz\x00"
  let info = @moonlibsync.create_basis_info(b"abc", manifest_sig(), d)
  let v = @moonlibsync.create_update_manifest(
    info,
    manifest_sig(),
    b"abc",
    delta,
    d,
  )
  assert_eq(@moonlibsync.patch(b"abc", delta, d), b"xyz")
  manifest_error(
    () => {
      let _ = @moonlibsync.verified_patch(b"abc", delta, v, d)
    },
    "Binding:result_sha256",
  )
}

///|
test "verified public forged result length fails preflight and signature is metadata only" {
  let d = @moonlibsync.Limits::default()
  let (v, delta) = verified_fixture()
  manifest_error(
    () => {
      let _ = @moonlibsync.verified_patch(
        b"abc",
        delta,
        { ..v, result: { ..v.result, byte_length: 2L, }, },
        d,
      )
    },
    "Binding:result_length",
  )
  assert_eq(
    @moonlibsync.verified_patch(
      b"abc",
      delta,
      { ..v, signature: { ..v.signature, sha256: "0".repeat(64), }, },
      d,
    ),
    b"abc",
  )
}

///|
test "verified public every descriptor is revalidated including unused signature" {
  let d = @moonlibsync.Limits::default()
  let (v, delta) = verified_fixture()
  for
    (bad, error) in [
      (
        { ..v, basis: { ..v.basis, byte_length: -1L, }, },
        "Field:basis.byte_length",
      ),
      (
        { ..v, basis: { ..v.basis, sha256: "A".repeat(64), }, },
        "Field:basis.sha256",
      ),
      (
        { ..v, signature: { ..v.signature, byte_length: 11L, }, },
        "Field:signature.byte_length",
      ),
      (
        { ..v, signature: { ..v.signature, sha256: "a", }, },
        "Field:signature.sha256",
      ),
      (
        { ..v, delta: { ..v.delta, byte_length: 4L, }, },
        "Field:delta.byte_length",
      ),
      (
        { ..v, delta: { ..v.delta, sha256: "g".repeat(64), }, },
        "Field:delta.sha256",
      ),
      (
        { ..v, result: { ..v.result, byte_length: -1L, }, },
        "Field:result.byte_length",
      ),
      ({ ..v, result: { ..v.result, sha256: "", }, }, "Field:result.sha256"),
    ] {
    manifest_error(
      () => {
        let _ = @moonlibsync.verified_patch(b"abc", delta, bad, d)
      },
      error,
    )
  }
}

///|
test "verified public limits first exact caps zero matching work and error reuse" {
  let d = @moonlibsync.Limits::default()
  let (v, delta) = verified_fixture()
  for
    (limits, error) in [
      ({ ..d, max_old_bytes: -1L, }, "Core:InvalidOptions:max_old_bytes"),
      ({ ..d, max_old_bytes: 2L, }, "Resource:basis"),
      ({ ..d, max_signature_bytes: 47L, }, "Resource:signature"),
      ({ ..d, max_delta_bytes: 7L, }, "Resource:delta"),
      ({ ..d, max_output_bytes: 2L, }, "Resource:result"),
      ({ ..d, max_instructions: 0L, }, "Core:LimitExceeded"),
    ] {
    manifest_error(
      () => {
        let _ = @moonlibsync.verified_patch(b"abc", delta, v, limits)
      },
      error,
    )
  }
  manifest_error(
    () => {
      let _ = @moonlibsync.verified_patch(b"abcd", delta, v, {
        ..d,
        max_old_bytes: 3L,
      })
    },
    "Core:LimitExceeded",
  )
  manifest_error(
    () => {
      let _ = @moonlibsync.verified_patch(
        b"abc",
        b"\x72\x73\x02\x36\x45\x00\x03\x00x",
        v,
        { ..d, max_delta_bytes: 8L, },
      )
    },
    "Core:LimitExceeded",
  )
  let good = @moonlibsync.verified_patch(b"abc", delta, v, {
    ..d,
    max_old_bytes: 3L,
    max_signature_bytes: 48L,
    max_delta_bytes: 8L,
    max_output_bytes: 3L,
    max_new_bytes: 0L,
    max_match_work: 0L,
  })
  assert_eq(good, b"abc")
  assert_eq(@moonlibsync.verified_patch(b"abc", delta, v, d), good)
}
