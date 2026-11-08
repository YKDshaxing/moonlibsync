// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "public signature defaults and independent complete byte expectations" {
  let options = @moonlibsync.SignatureOptions::default()
  assert_eq(options.block_len, 2048L)
  assert_eq(options.strong_sum_len, 32L)
  let sample = @moonlibsync.signature(
    b"abc",
    options,
    @moonlibsync.Limits::default(),
  )
  assert_eq(sample.length(), 48)
  assert_eq(
    @moonlibsync.signature(b"", options, @moonlibsync.Limits::default()),
    b"\x72\x73\x01\x47\x00\x00\x08\x00\x00\x00\x00\x20",
  )
  let short : @moonlibsync.SignatureOptions = {
    block_len: 2L,
    strong_sum_len: 1L,
  }
  let single : @moonlibsync.SignatureOptions = {
    block_len: 1L,
    strong_sum_len: 1L,
  }
  assert_eq(
    @moonlibsync.signature(b"\x00\xff", single, @moonlibsync.Limits::default()),
    b"\x72\x73\x01\x47\x00\x00\x00\x01\x00\x00\x00\x01\x08\x10\x42\x25\x03\x08\x10\x43\x24\xac",
  )
  assert_eq(
    @moonlibsync.signature(
      b"\x00\xff\x80",
      short,
      @moonlibsync.Limits::default(),
    ),
    b"\x72\x73\x01\x47\x00\x00\x00\x02\x00\x00\x00\x01\xa5\xb7\x1a\x58\x96\x08\x10\x42\xa5\x45",
  )
  // Independent scalar weak sums and CPython hashlib prefix values for 00, ff.
  assert_eq(
    @moonlibsync.signature(b"\x00", short, @moonlibsync.Limits::default()),
    b"\x72\x73\x01\x47\x00\x00\x00\x02\x00\x00\x00\x01\x08\x10\x42\x25\x03",
  )
}

///|
test "public signature block boundaries and deterministic calls" {
  for block in [1, 2, 64, 2048] {
    for strong in [1, 16, 32] {
      for size in [0, 1, block - 1, block, block + 1, 2 * block - 1, 2 * block] {
        let basis = Bytes::makei(size, i => ((i * 73 + 19) % 256).to_byte())
        let options : @moonlibsync.SignatureOptions = {
          block_len: block.to_int64(),
          strong_sum_len: strong.to_int64(),
        }
        let first = @moonlibsync.signature(
          basis,
          options,
          @moonlibsync.Limits::default(),
        )
        let count = size / block + (if size % block > 0 { 1 } else { 0 })
        assert_eq(first.length(), 12 + count * (4 + strong))
        assert_eq(
          first,
          @moonlibsync.signature(basis, options, @moonlibsync.Limits::default()),
        )
        assert_eq(
          basis,
          Bytes::makei(size, i => ((i * 73 + 19) % 256).to_byte()),
        )
      }
    }
  }
}
