// SPDX-License-Identifier: LGPL-2.1-or-later

///|
// The sender has no basis argument or filesystem access.
fn sender(
  remote_signature : Bytes,
  new_bytes : Bytes,
) -> Bytes raise @lib.SyncError {
  @lib.delta(remote_signature, new_bytes, @lib.Limits::default())
}

///|
fn main {
  let old = Bytes::makei(512, i => (0x10 + i / 64).to_byte())
  let new_bytes = old[0:256].to_owned() + b"\x00\x80\xff" + old[256:].to_owned()
  let limits = @lib.Limits::default()
  let remote_signature = @lib.signature(
    old,
    { block_len: 64, strong_sum_len: 32, },
    limits,
  ) catch {
    _ => abort("BASIC_SIGNATURE_FAILED")
  }
  let encoded = sender(remote_signature, new_bytes) catch {
    _ => abort("BASIC_GENERATION_FAILED")
  }
  let restored = @lib.patch(old, encoded, limits) catch {
    _ => abort("BASIC_PATCH_FAILED")
  }
  let expected = new_bytes
  guard restored == expected else {
    println("BASIC_RESTORE_MISMATCH")
    abort("BASIC_RESTORE_MISMATCH")
  }
  guard encoded.length() < new_bytes.length() else { abort("BASIC_DELTA_SIZE") }
  let alphabet = "0123456789abcdef"
  let mut hex = ""
  for byte in encoded {
    let value = byte.to_int()
    let high = value >> 4
    let low = value & 15
    hex = hex +
      alphabet[high:high + 1].to_owned() +
      alphabet[low:low + 1].to_owned()
  }
  println(
    "old_bytes=\{old.length()} new_bytes=\{new_bytes.length()} signature_bytes=\{remote_signature.length()} delta_bytes=\{encoded.length()}",
  )
  println("delta_hex=\{hex}")
  println("restored_equal=true")
}
