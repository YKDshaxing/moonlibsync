// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn run() -> Unit raise {
  let limits = @lib.Limits::default()
  let old = Bytes::makei(32769, i => (i % 251).to_byte())
  let block = @lib.recommend_block_len(old.length().to_int64(), 16L, limits)
  assert_eq(block, 128L)
  let sig = @lib.signature(
    old,
    { block_len: block, strong_sum_len: 16L, },
    limits,
  )
  let summary = @lib.inspect_signature(sig, limits)
  assert_eq(summary.record_count, 257L)
  assert_eq(summary.signature_bytes, 5152L)
  let new = b"!" + old
  assert_eq(@lib.patch(old, @lib.delta(sig, new, limits), limits), new)
  let legacy = @lib.signature(old, @lib.SignatureOptions::default(), limits)
  assert_eq(@lib.inspect_signature(legacy, limits).block_len, 2048L)
  println("AUTO_BLOCK_EXAMPLE_OK policy=1 block=128 records=257 bytes=5152")
}

///|
fn main {
  run() catch {
    _ => {
      println("AUTO_BLOCK_EXAMPLE_FAILED")
      abort("AUTO_BLOCK_EXAMPLE_FAILED")
    }
  }
}
