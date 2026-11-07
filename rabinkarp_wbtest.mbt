// Copyright (C) 2003 Donovan Baarda <abo@minkirri.apana.org.au>
// Additional MoonBit tests: Copyright (C) 2026 MoonLibSync contributors
// SPDX-License-Identifier: LGPL-2.1-or-later
// Fixed vectors: librsync e364852674780e43d578e4239128ff7014190ed3/tests/rabinkarp_test.c

///|
/// Independent scalar oracle; never calls any tested state operation.
fn rk_recompute(window : BytesView) -> UInt32 {
  let mut expected = 1U
  for byte in window {
    expected = expected * 0x08104225U + byte.to_uint()
  }
  expected
}

///|
fn rk_check(state : RabinKarp, window : BytesView) -> Unit raise {
  assert_eq(state.count, window.length())
  assert_eq(state.digest(), rk_recompute(window))
  let mut power = 1U
  for _ in 0..<window.length() {
    power = power * 0x08104225U
  }
  assert_eq(state.mult, power)
  assert_eq(state.digest(), state.hash)
}

///|
fn rk_inputs() -> Array[Bytes] {
  let mut seed = 0x12345678U
  let random = Bytes::makei(2070, _ => {
    seed = seed * 1664525U + 1013904223U
    (seed >> 24).to_byte()
  })
  [
    Bytes::make(2070, b'\x00'),
    Bytes::make(2070, b'\xff'),
    Bytes::makei(2070, i => (i % 256).to_byte()),
    Bytes::makei(2070, i => [b'\x00', b'\x7f', b'\x80', b'\xff'][i % 4]),
    Bytes::makei(2070, i => b"repeat!"[i % 7]),
    random,
  ]
}

///|
test "rabinkarp fixed upstream vectors exercise rollin rotate rollout and update" {
  let r = RabinKarp::new()
  assert_eq(r.digest(), 1U)
  r.rollin(b'\x00')
  assert_eq(r.digest(), 0x08104225U)
  for byte in b"\x01\x02\x03" {
    r.rollin(byte)
  }
  assert_eq(r.digest(), 0xaf981e97U)
  r.rotate(b'\x00', b'\x04')
  assert_eq(r.digest(), 0xe2ef15f3U)
  for i in 1..<4 {
    r.rotate(i.to_byte(), (i + 4).to_byte())
  }
  assert_eq(r.digest(), 0x7cf3fc07U)
  r.rollout(b'\x04')
  assert_eq(r.digest(), 0xf284a77fU)
  for byte in b"\x05\x06\x07" {
    r.rollout(byte)
  }
  rk_check(r, b"")
  r.update(Bytes::makei(256, i => i.to_byte()))
  assert_eq(r.digest(), 0xc1972381U)
  for
    (bytes, expected) in [
      (b"", 1U),
      (b"\x00", 0x08104225U),
      (b"\x00\x01\x02\x03", 0xaf981e97U),
      (b"\x01\x02\x03\x04", 0xe2ef15f3U),
      (b"\x04\x05\x06\x07", 0x7cf3fc07U),
      (b"\x05\x06\x07", 0xf284a77fU),
    ] {
    let s = RabinKarp::new()
    s.update(bytes)
    assert_eq(s.digest(), expected)
    rk_check(s, bytes)
  }
}

///|
test "rabinkarp each sliding window and EOF suffix matches independent recomputation" {
  for data in rk_inputs() {
    for width in [0, 1, 6, 7, 8, 15, 16, 17, 2047, 2048, 2049] {
      let r = RabinKarp::new()
      r.update(data[0:width])
      rk_check(r, data[0:width])
      if width > 0 {
        // All possible windows for small widths; several for the large EOF window.
        let slides = data.length() - width
        for start in 0..<slides {
          r.rotate(data[start], data[start + width])
          rk_check(r, data[start + 1:start + width + 1])
        }
        for start in (data.length() - width)..<data.length() {
          r.rollout(data[start])
          rk_check(r, data[start + 1:data.length()])
        }
        r.rollin(b'\xff')
        rk_check(r, b"\xff")
      }
    }
  }
}

///|
test "rabinkarp segmented updates empty segments and interleaved states are independent" {
  for data in rk_inputs() {
    let whole = RabinKarp::new()
    whole.update(data)
    let segmented = RabinKarp::new()
    let singles = RabinKarp::new()
    let cuts = [0, 1, 7, 16, 17, 2048, 2070]
    let mut start = 0
    for end in cuts {
      segmented.update(b"")
      segmented.update(data[start:end])
      rk_check(segmented, data[0:end])
      for byte in data[start:end] {
        singles.rollin(byte)
      }
      rk_check(singles, data[0:end])
      start = end
    }
    rk_check(singles, data)
    rk_check(whole, data)
    assert_eq(segmented.hash, whole.hash)
    assert_eq(segmented.mult, whole.mult)
  }
}

///|
test "rabinkarp direct EOF shortening returns all state to seed and permits reuse" {
  for data in [b"", b"\x80", b"\x00\x7f\x80\xff", Bytes::make(2048, b'\xff')] {
    let r = RabinKarp::new()
    r.update(data)
    rk_check(r, data)
    for start in 0..<data.length() {
      r.rollout(data[start])
      rk_check(r, data[start + 1:data.length()])
    }
    assert_eq(r.count, 0)
    assert_eq(r.hash, 1U)
    assert_eq(r.mult, 1U)
    r.update(b"\x00\xff")
    rk_check(r, b"\x00\xff")
  }
}

///|
test "rabinkarp invalid empty operations and capacity failures preserve state" {
  let r = RabinKarp::new()
  expect_sync_error(
    () => r.rotate(b'\x00', b'\xff'),
    "InvalidOptions:empty_rabinkarp_window",
  )
  expect_sync_error(
    () => r.rollout(b'\x00'),
    "InvalidOptions:empty_rabinkarp_window",
  )
  rk_check(r, b"")
  r.rollin(b'\x80')
  rk_check(r, b"\x80")
  r.rollout(b'\x80')
  rk_check(r, b"")
  // Synthetic count boundary; no huge window allocation is needed.
  let full : RabinKarp = {
    count: 2147483647,
    hash: 0x80000000U,
    mult: 0xffffffffU,
  }
  expect_sync_error(() => full.rollin(b'\xff'), "IntegerOutOfRange")
  expect_sync_error(() => full.update(b"\x00\xff"), "IntegerOutOfRange")
  assert_eq(full.count, 2147483647)
  assert_eq(full.hash, 0x80000000U)
  assert_eq(full.mult, 0xffffffffU)
  full.update(b"")
  full.count = 2147483646
  expect_sync_error(() => full.update(b"\x00\xff"), "IntegerOutOfRange")
  assert_eq(full.count, 2147483646)
  assert_eq(full.hash, 0x80000000U)
  assert_eq(full.mult, 0xffffffffU)
  full.rollin(b'\x00')
  assert_eq(full.count, 2147483647)
}

///|
test "rabinkarp actual basis blocks match every fixed rdiff weak record including short tails" {
  let bases = reference_bases()
  let signatures = reference_signatures()
  assert_eq(bases.length(), signatures.length())
  for i in 0..<bases.length() {
    let (id, basis) = bases[i]
    let (sig_id, bytes) = signatures[i]
    assert_eq(id, sig_id)
    let sig = parse_signature(bytes, Limits::default())
    let mut pos = 0
    for record in sig.records {
      let remaining = basis.length() - pos
      let size = if remaining < sig.block_len {
        remaining
      } else {
        sig.block_len
      }
      let r = RabinKarp::new()
      r.update(basis[pos:pos + size])
      assert_eq(r.digest(), record.weak_sum)
      rk_check(r, basis[pos:pos + size])
      pos = pos + size
    }
    assert_eq(pos, basis.length())
    if basis.length() == 0 {
      assert_eq(sig.records.length(), 0)
    }
  }
}
