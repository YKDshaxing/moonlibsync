// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "whitebox PatchDecoder multi-step InCopy state transitions and partial finish rejection" {
  let d = Limits::default()
  // 70000-byte COPY starting at offset 1 -> steps: CopyBasis(1, 65536) then CopyBasis(65537, 4464)
  // Wire: magic (4B) + opcode 0x45 (1+0*4+2=0x47, ow=1, lw=4) + off=1 (1B) + len=70000 (4B) + END (1B)
  let delta = b"\x72\x73\x02\x36\x47\x01\x00\x01\x11\x70\x00"
  let dec = PatchDecoder::new(80000L, d)
  let (c1, s1) = dec.step(delta[0:10])
  assert_eq(c1, 10)
  assert_true(s1 is CopyBasis(1UL, 65536))
  assert_true(dec.has_pending_copy())
  assert_true(dec.state is InCopy(65537UL, 4464UL))

  // Calling finish while InCopy still has pending bytes raises TruncatedInput and poisons.
  let dec_trunc = PatchDecoder::new(80000L, d)
  let _ = dec_trunc.step(delta[0:10])
  let trunc = try {
    let _ = dec_trunc.finish()
    false
  } catch {
    SyncError::TruncatedInput => true
    _ => false
  }
  assert_true(trunc)
  assert_true(dec_trunc.failed)

  // Completing second CopyBasis returns NeedOpcode, then consuming END gives SawEnd.
  let (c2, s2) = dec.step(delta[10:])
  assert_eq(c2, 0)
  assert_true(s2 is CopyBasis(65537UL, 4464))
  assert_true(!dec.has_pending_copy())
  let (c3, s3) = dec.step(delta[10:])
  assert_eq(c3, 1)
  assert_true(s3 is NeedInput)
  assert_true(dec.state is SawEnd)
  let sum = dec.finish()
  assert_eq(sum.delta_bytes, 11L)
  assert_eq(sum.copy_bytes, 70000L)
  assert_eq(sum.output_bytes, 70000L)
}
