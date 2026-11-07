// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Internal adapter: always BLAKE2b with output parameter 32, then prefix.
/// No key, salt, personalisation, shared hasher or public dependency types.
#warnings("-unused_value")
fn strong_sum(
  input : BytesView,
  strong_sum_len : Int32,
) -> Bytes raise SyncError {
  guard strong_sum_len >= 1 && strong_sum_len <= 32 else {
    raise InvalidOptions("strong_sum_len")
  }
  let full = @blake2.hash(input, kind=Blake2b, len=32)
  full[0:strong_sum_len].to_owned()
}
