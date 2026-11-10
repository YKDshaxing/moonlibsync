// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "prepared delta documented prepare once two targets and independent recovery" {
  let limits = @moonlibsync.Limits::default()
  let old = b"ABCDEFGHIJKLMN\x00\x80\xff"
  let sig = @moonlibsync.signature(
    old,
    { block_len: 7L, strong_sum_len: 32L, },
    limits,
  )
  let prepared = @moonlibsync.prepare_signature(sig, limits)
  let first = b"!ABCDEFGHIJKLMN\x00\x80\xff"
  let second = b"ABCDEFG!HIJKLMN\x00\x80\xff"
  let a = prepared.delta(first, limits)
  let b = prepared.delta(second, limits)
  assert_eq(@moonlibsync.patch(old, a, limits), first)
  assert_eq(@moonlibsync.patch(old, b, limits), second)
  assert_eq(a, @moonlibsync.delta(sig, first, limits))
  assert_eq(b, @moonlibsync.delta(sig, second, limits))
  assert_true(@moonlibsync.inspect_delta(a, limits).copy_bytes >= 14L)
  assert_true(@moonlibsync.inspect_delta(b, limits).copy_bytes >= 14L)
}

///|
test "prepared delta edits EOF shrink moved tail and disjoint new bytes" {
  let d = @moonlibsync.Limits::default()
  let old = Bytes::makei(512, i => (16 + i / 64).to_byte()) + b"\x00\x80\xff"
  let sig = @moonlibsync.signature(
    old,
    { block_len: 64L, strong_sum_len: 32L, },
    d,
  )
  let p = @moonlibsync.prepare_signature(sig, d)
  for
    new in [
      old,
      b"!" + old,
      old + b"!",
      old[0:256].to_owned() + b"!" + old[256:].to_owned(),
      old[1:].to_owned(),
      old[0:514].to_owned(),
      old[0:256].to_owned() + old[257:].to_owned(),
      b"!" + old[1:].to_owned(),
      old[0:256].to_owned() + b"!" + old[257:].to_owned(),
      old[0:514].to_owned() + b"!",
      old[512:].to_owned() + old[0:512].to_owned(),
      old[0:256].to_owned() + old[512:].to_owned() + old[256:512].to_owned(),
    ] {
    let result = p.delta(new, d)
    assert_eq(result, @moonlibsync.delta(sig, new, d))
    assert_eq(@moonlibsync.patch(old, result, d), new)
    assert_true(@moonlibsync.inspect_delta(result, d).copy_bytes >= 384L)
  }
  let different = Bytes::makei(128, _ => b'\xfe')
  let result = p.delta(different, d)
  assert_eq(result, @moonlibsync.delta(sig, different, d))
  assert_eq(@moonlibsync.patch(old, result, d), different)
  assert_eq(@moonlibsync.inspect_delta(result, d).copy_bytes, 0L)
}

///|
test "prepared delta repeated blocks preserve deterministic COPY selection" {
  let d = @moonlibsync.Limits::default()
  let old = Bytes::makei(128, _ => b'A')
  let sig = @moonlibsync.signature(
    old,
    { block_len: 16L, strong_sum_len: 32L, },
    d,
  )
  let p = @moonlibsync.prepare_signature(sig, d)
  let new = Bytes::makei(160, _ => b'A')
  let result = p.delta(new, d)
  assert_eq(result, @moonlibsync.delta(sig, new, d))
  assert_eq(@moonlibsync.patch(old, result, d), new)
  assert_eq(@moonlibsync.inspect_delta(result, d).copy_bytes, 160L)
}

///|
test "prepared delta strict current signature and generation limits exact boundaries" {
  let d = @moonlibsync.Limits::default()
  let sig = @moonlibsync.signature(
    b"abc",
    { block_len: 3L, strong_sum_len: 16L, },
    d,
  )
  let p = @moonlibsync.prepare_signature(sig, d)
  // Single record build=3; shared one-shot=33; scan=30 independently:
  // window4 + dispatch1 + binary1 + presence1 + hash4 + candidate1 + digest16 + append/capacity2.
  for
    (field, need) in [
      ("signature", 32L),
      ("block", 3L),
      ("records", 1L),
      ("new", 3L),
      ("output", 3L),
      ("delta", 8L),
      ("instructions", 1L),
      ("work", 30L),
    ] {
    for cap in [need - 1L, need, need + 1L] {
      let limits = match field {
        "signature" => { ..d, max_signature_bytes: cap, }
        "block" => { ..d, max_block_bytes: cap, }
        "records" => { ..d, max_signature_records: cap, }
        "new" => { ..d, max_new_bytes: cap, }
        "output" => { ..d, max_output_bytes: cap, }
        "delta" => { ..d, max_delta_bytes: cap, }
        "instructions" => { ..d, max_instructions: cap, }
        _ => { ..d, max_match_work: cap, }
      }
      if cap < need {
        inspect_error(
          () => {
            let _ = p.delta(b"abc", limits)
          },
          "LimitExceeded",
        )
      } else {
        assert_eq(
          @moonlibsync.patch(b"abc", p.delta(b"abc", limits), d),
          b"abc",
        )
      }
    }
  }
}

///|
test "prepared delta empty still rechecks current metadata and all config" {
  let d = @moonlibsync.Limits::default()
  let sig = @moonlibsync.signature(
    b"abc",
    { block_len: 3L, strong_sum_len: 16L, },
    d,
  )
  let p = @moonlibsync.prepare_signature(sig, d)
  let zero = {
    ..d,
    max_old_bytes: 0L,
    max_new_bytes: 0L,
    max_output_bytes: 0L,
    max_delta_bytes: 5L,
    max_instructions: 0L,
    max_match_work: 0L,
  }
  assert_eq(p.delta(b"", zero), b"\x72\x73\x02\x36\x00")
  for
    limits in [
      { ..zero, max_signature_bytes: 31L, },
      { ..zero, max_block_bytes: 2L, },
      { ..zero, max_signature_records: 0L, },
      { ..zero, max_delta_bytes: 4L, },
    ] {
    inspect_error(
      () => {
        let _ = p.delta(b"", limits)
      },
      "LimitExceeded",
    )
  }
  inspect_error(
    () => {
      let _ = p.delta(b"", {
        ..zero,
        max_old_bytes: -1L,
        max_signature_bytes: 0L,
      })
    },
    "InvalidOptions:max_old_bytes",
  )
  inspect_error(
    () => {
      let _ = p.delta(b"", { ..zero, max_match_work: -1L, })
    },
    "InvalidOptions:max_match_work",
  )
  for
    (limits, field) in [
      ({ ..zero, max_new_bytes: -1L, }, "max_new_bytes"),
      ({ ..zero, max_signature_bytes: -1L, }, "max_signature_bytes"),
      ({ ..zero, max_signature_records: -1L, }, "max_signature_records"),
      ({ ..zero, max_block_bytes: 0L, }, "max_block_bytes"),
      ({ ..zero, max_delta_bytes: -1L, }, "max_delta_bytes"),
      ({ ..zero, max_output_bytes: -1L, }, "max_output_bytes"),
      ({ ..zero, max_instructions: -1L, }, "max_instructions"),
    ] {
    inspect_error(
      () => {
        let _ = p.delta(b"", limits)
      },
      "InvalidOptions:" + field,
    )
  }
  assert_eq(
    @moonlibsync.patch(b"abc", p.delta(b"abc", { ..d, max_old_bytes: 0L, }), d),
    b"abc",
  )
}

///|
test "prepared delta interleaved failures preserve objects previous results and inputs" {
  let d = @moonlibsync.Limits::default()
  let sa = @moonlibsync.signature(
    b"abc",
    { block_len: 3L, strong_sum_len: 16L, },
    d,
  )
  let sb = @moonlibsync.signature(
    b"xyz",
    { block_len: 3L, strong_sum_len: 16L, },
    d,
  )
  let a = @moonlibsync.prepare_signature(sa, d)
  let b = @moonlibsync.prepare_signature(sb, d)
  let first = a.delta(b"!abc", d)
  for _ in 0..<3 {
    inspect_error(
      () => {
        let _ = a.delta(b"abc", { ..d, max_match_work: 29L, })
      },
      "LimitExceeded",
    )
    inspect_error(
      () => {
        let _ = a.delta(b"abc", { ..d, max_instructions: 0L, })
      },
      "LimitExceeded",
    )
    assert_eq(@moonlibsync.patch(b"xyz", b.delta(b"xyz!", d), d), b"xyz!")
    assert_eq(a.delta(b"!abc", d), first)
    assert_eq(@moonlibsync.patch(b"abc", first, d), b"!abc")
  }
  assert_eq(
    sa,
    @moonlibsync.signature(b"abc", { block_len: 3L, strong_sum_len: 16L, }, d),
  )
  assert_eq(
    sb,
    @moonlibsync.signature(b"xyz", { block_len: 3L, strong_sum_len: 16L, }, d),
  )
}
