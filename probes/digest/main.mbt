// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Expected values come from CPython hashlib (digest_size=32), not mooncrypt.
fn vectors() -> Array[(Bytes, String)] {
  [
    (b"", "0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"),
    (b"abc", "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"),
  ]
}

///|
fn main {
  for (input, expected) in vectors() {
    let digest = @blake2.hash(input, kind=Blake2b, len=32)
    let actual = @hex.encode(digest)
    println(
      "input_hex=\{@hex.encode(input)} expected=\{expected} actual=\{actual}",
    )
    guard digest.length() == 32 && actual == expected else {
      abort("BLAKE2b-256 vector mismatch")
    }
    // strong_sum_len is a PREFIX of BLAKE2b(len=32), never a new len parameter.
    for strong_sum_len in 1..<=32 {
      let prefix = @hex.encode(digest[0:strong_sum_len])
      guard prefix == expected[0:strong_sum_len * 2].to_owned() else {
        abort("strong checksum prefix mismatch")
      }
    }
    guard actual != @hex.encode(@blake2.hash(input, kind=Blake2b, len=64)[0:32]) else {
      abort("BLAKE2b-512 truncation unexpectedly equals BLAKE2b-256")
    }
    guard actual != @hex.encode(@blake2.hash(input, kind=Blake2s, len=32)) else {
      abort("BLAKE2s-256 unexpectedly equals BLAKE2b-256")
    }
  }
}
