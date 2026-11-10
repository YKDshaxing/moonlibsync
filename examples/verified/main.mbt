// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn run() -> Unit raise {
  let limits = @lib.Limits::default()
  let old = b"ABCDEFGHIJKLMN"
  let new = b"!ABCDEFGHIJKLMN?"
  let sig = @lib.signature(old, { block_len: 7L, strong_sum_len: 32L, }, limits)
  let info = @lib.create_basis_info(old, sig, limits)
  // The sender needs only info, SIG and NEW; no OLD is passed here.
  let delta = @lib.delta(sig, new, limits)
  let manifest = @lib.create_update_manifest(info, sig, new, delta, limits)
  let wire = @lib.encode_update_manifest(manifest, limits)
  let trusted = @lib.parse_update_manifest(wire, limits)
  assert_eq(@lib.verified_patch(old, delta, trusted, limits), new)
  println("VERIFIED_EXAMPLE_OK restored=true")
}

///|
fn main {
  run() catch {
    _ => abort("VERIFIED_EXAMPLE_FAILED")
  }
}
