// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "cli auto selection is explicit and resolves from actual Bytes with chosen strong length" {
  let d = @lib.Limits::default()
  let auto = parse_plan([
    "signature", "old", "out", "--block-size", "auto", "--sum-size", "16",
  ])
  assert_true(auto.block_choice is Auto)
  let short = signature_options(auto, b"abc", d)
  assert_eq(short.block_len, 64L)
  assert_eq(short.strong_sum_len, 16L)
  assert_eq(
    signature_options(auto, Bytes::make(32769, b'0'), d).block_len,
    128L,
  )
  let numeric = parse_plan(["signature", "old", "out", "--block-size", "17"])
  assert_true(numeric.block_choice is Explicit(17L))
  assert_eq(signature_options(numeric, b"abc", d).block_len, 17L)
  assert_eq(
    signature_options(parse_plan(["signature", "old", "out"]), b"abc", d).block_len,
    2048L,
  )
  assert_eq(
    parse_plan(["signature", "--block-size", "auto", "--", "-", "--out"]).inputs[0],
    "-",
  )
}

///|
async test "cli auto refuses size changes before resolving or publishing a signature" {
  cli_test_scope(dir => {
    let old = dir + "/old"
    @fs.write_binary(old, b"abc", create_mode=CreateNew)
    let file = open_regular_input(old)
    defer file.close()
    let plan = parse_plan([
      "signature",
      old,
      dir + "/out",
      "--block-size",
      "auto",
    ])
    let mut resolved = false
    expect_file_failure(
      () => {
        let actual = read_open_file(file, old, 100L, after_size=() => {
          @fs.write_binary(old, b"abcd", create_mode=TruncateExisting)
        })
        let _ = signature_options(plan, actual, @lib.Limits::default())
        resolved = true
      },
      "InputChanged",
    )
    assert_true(!resolved && !entry_exists(dir + "/out"))
  })
}
