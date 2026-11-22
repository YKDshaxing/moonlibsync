// Copyright (C) 2003 Donovan Baarda <abo@minkirri.apana.org.au>
// MoonBit test adaptation: Copyright (C) 2026 MoonLibSync contributors
// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "rollsum digest update rotate and rollout match direct formula across wraparound" {
  // Known exact librsync Rollsum formula checks (char_offset = 31):
  // Empty => 0
  assert_eq(rollsum_digest(b""[:]), 0U)
  // Single byte 0x00 => s1 = 31, s2 = 31 => (31 << 16) | 31 = 0x001f001f
  assert_eq(rollsum_digest(b"\x00"[:]), 0x001f001fU)
  // "abc" (97, 98, 99):
  // c0 = 128, c1 = 129, c2 = 130
  // s1 = 128 + 129 + 130 = 387 (0x0183)
  // s2 = 128 + (128+129) + 387 = 128 + 257 + 387 = 772 (0x0304)
  assert_eq(rollsum_digest(b"abc"[:]), 0x03040183U)

  // Verify rotate & rollout match fresh rollsum_digest on arbitrary binary data including 0x00 & 0xff.
  let data = Bytes::makei(512, i => ((i * 73 + 19) & 0xff).to_byte())
  let win = 64
  let rs = Rollsum::new()
  rs.update(data[0:win])
  assert_eq(rs.count, win)
  assert_eq(rs.digest(), rollsum_digest(data[0:win]))

  // Slide across entire buffer using rotate
  for pos in 0..<(data.length() - win) {
    rs.rotate(data[pos], data[pos + win])
    assert_eq(rs.digest(), rollsum_digest(data[pos + 1:pos + 1 + win]))
  }

  // Shorten EOF tail down to 0 using rollout
  let tail_start = data.length() - win
  for k in 0..<win {
    rs.rollout(data[tail_start + k])
    assert_eq(rs.count, win - k - 1)
    assert_eq(rs.digest(), rollsum_digest(data[tail_start + k + 1:]))
  }
  assert_eq(rs.digest(), 0U)

  // Verify 16-bit s1/s2 wraparound with 1024 bytes of 0xff (1024 * 286 = 292864 >> 65536).
  let big = Bytes::make(1024, b'\xff')
  let rbig = Rollsum::new()
  rbig.update(big[0:512])
  assert_eq(rbig.digest(), rollsum_digest(big[0:512]))
  rbig.rotate(b'\xff', b'\x00')
  let expected_rot = Bytes::make(511, b'\xff') + b"\x00"
  assert_eq(rbig.digest(), rollsum_digest(expected_rot[:]))
}

///|
test "rolling weak enum dispatches cleanly between 0x72730147 and 0x72730137" {
  let sample = b"MoonLibSync-0.6.0-dual-profile-check!"
  let rk = RollingWeak::new_for_magic(0x72730147U)
  let rs = RollingWeak::new_for_magic(0x72730137U)
  rk.update(sample[0:16])
  rs.update(sample[0:16])
  assert_eq(rk.count(), 16)
  assert_eq(rs.count(), 16)
  assert_eq(rk.digest(), rabinkarp_digest(sample[0:16]))
  assert_eq(rs.digest(), rollsum_digest(sample[0:16]))
  rk.rotate(sample[0], sample[16])
  rs.rotate(sample[0], sample[16])
  assert_eq(rk.digest(), rabinkarp_digest(sample[1:17]))
  assert_eq(rs.digest(), rollsum_digest(sample[1:17]))
}
