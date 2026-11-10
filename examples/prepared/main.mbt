// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn run() -> Unit raise {
  let limits = @lib.Limits::default()
  let old = b"ABCDEFGHIJKLMN\x00\x80\xff"
  let signature = @lib.signature(
    old,
    { block_len: 7L, strong_sum_len: 32L, },
    limits,
  )
  let prepared = @lib.prepare_signature(signature, limits)
  let first = b"!ABCDEFGHIJKLMN\x00\x80\xff"
  let second = b"ABCDEFG!HIJKLMN\x00\x80\xff"
  let a = prepared.delta(first, limits)
  let b = prepared.delta(second, limits)
  assert_eq(@lib.patch(old, a, limits), first)
  assert_eq(@lib.patch(old, b, limits), second)
  assert_eq(a, @lib.delta(signature, first, limits))
  assert_eq(b, @lib.delta(signature, second, limits))
  assert_true(@lib.inspect_delta(a, limits).copy_bytes >= 14L)
  assert_true(@lib.inspect_delta(b, limits).copy_bytes >= 14L)
  println("PREPARED_EXAMPLE_OK targets=2 restored=true COPY>=14 each")
}

///|
fn main {
  run() catch {
    _ => abort("PREPARED_EXAMPLE_FAILED")
  }
}
