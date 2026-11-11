// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn run() -> Unit raise {
  let d = @lib.Limits::default()
  let old = b"abcdefghijklmnop"
  let sig = @lib.signature(old, { block_len: 8L, strong_sum_len: 32L, }, d)
  let info = @lib.create_basis_info(old, sig, d)
  for (new, expected) in [(old, "librsync-delta"), (b"xyz", "full-file")] {
    let options = @lib.UpdateOptions::default()
    let plan = @lib.plan_update(sig, new, options, d)
    assert_eq(plan.decision.kind, expected)
    let candidate = @lib.delta(sig, new, d)
    let manifest = @lib.create_transfer_manifest(
      info, sig, new, candidate, options, d,
    )
    let parsed = @lib.parse_transfer_manifest(
      @lib.encode_transfer_manifest(manifest, d),
      d,
    )
    let (payload, basis) = match plan.payload {
      Delta(bytes) => (bytes, Some(old))
      Full(bytes) => (bytes, None)
    }
    assert_eq(@lib.apply_update(basis, payload, parsed, d), new)
    println(
      "TRANSFER_EXAMPLE_OK kind=\{expected} new=\{new.length()} delta=\{candidate.length()} payload=\{payload.length()}",
    )
  }
}

///|
fn main {
  run() catch {
    _ => {
      println("TRANSFER_EXAMPLE_FAILED")
      abort("TRANSFER_EXAMPLE_FAILED")
    }
  }
}
