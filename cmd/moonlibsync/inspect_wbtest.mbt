// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "cli inspection plans option positions separators and usage errors" {
  for
    args in [["inspect-delta", "--json", "d"], ["inspect-delta", "d", "--json"]] {
    let p = parse_plan(args)
    assert_eq(p.inputs, ["d"])
    assert_true(p.mode is Inspect(true))
  }
  let p = parse_plan(["check-patch", "old", "--json", "delta"])
  assert_eq(p.inputs, ["old", "delta"])
  assert_true(p.mode is Inspect(true))
  let p = parse_plan(["inspect-signature", "--", "--json"])
  assert_eq(p.inputs, ["--json"])
  assert_true(p.mode is Inspect(false))
  assert_eq(parse_plan(["inspect-delta", "-"]).inputs, ["-"])
  assert_true(parse_plan(["signature", "old", "out"]).mode is WriteFile("out"))
  for
    args in [
      ["inspect-delta"],
      ["inspect-delta", "d", "extra"],
      ["inspect-signature", "--json", "x", "--json"],
      ["check-patch", "x"],
      ["check-patch", "--wat", "x", "y"],
      ["signature", "x", "y", "--json"],
      ["delta", "x", "y", "z", "--json"],
      ["patch", "x", "y", "z", "--json"],
      ["inspect-delta", "x", "--sum-size", "1"],
    ] {
    let rejected = try {
      let _ = parse_plan(args)
      false
    } catch {
      Usage(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "cli inspection JSON exact Int64 formatting beyond JS safe integer" {
  // Formatting-only values, not claims of reachability under file budgets.
  let s : @lib.DeltaSummary = {
    delta_bytes: 9007199254740993L,
    instruction_count: 9223372036854775807L,
    literal_commands: 0L,
    copy_commands: 1L,
    literal_bytes: 0L,
    copy_bytes: 9007199254740993L,
    output_bytes: 9007199254740993L,
  }
  let expected = "{\"delta_bytes\":\"9007199254740993\",\"instruction_count\":\"9223372036854775807\",\"literal_commands\":\"0\",\"copy_commands\":\"1\",\"literal_bytes\":\"0\",\"copy_bytes\":\"9007199254740993\",\"output_bytes\":\"9007199254740993\"}"
  assert_eq(delta_json(s), expected)
  assert_eq(
    format_delta(s, true),
    "{\"schema_version\":1,\"command\":\"inspect-delta\",\"summary\":" +
    expected +
    "}\n",
  )
  assert_eq(
    format_patch({ basis_bytes: 9007199254740993L, summary: s, }, true),
    "{\"schema_version\":1,\"command\":\"check-patch\",\"basis_bytes\":\"9007199254740993\",\"summary\":" +
    expected +
    "}\n",
  )
  assert_eq(
    format_signature(
      {
        magic: 0x72730147U,
        block_len: 9007199254740993L,
        strong_sum_len: 32L,
        record_count: 9223372036854775807L,
        signature_bytes: 9007199254740993L,
      },
      true,
    ),
    "{\"schema_version\":1,\"command\":\"inspect-signature\",\"summary\":{\"magic\":\"0x72730147\",\"profile\":\"RS_RK_BLAKE2_SIG_MAGIC\",\"block_len\":\"9007199254740993\",\"strong_sum_len\":\"32\",\"record_count\":\"9223372036854775807\",\"signature_bytes\":\"9007199254740993\"}}\n",
  )
}

///|
async test "cli preflight reads only delta through content reader" {
  cli_test_scope(dir => {
    let path = dir + "/basis"
    @fs.write_binary(path, b"abc", create_mode=CreateNew)
    let file = open_regular_input(path)
    defer file.close()
    let mut reads = 0
    let result = check_open_basis(
      file,
      path,
      "delta-only",
      @lib.Limits::default(),
      reader=(actual, maximum) => {
        assert_eq(actual, "delta-only")
        assert_eq(maximum, 83886080L)
        reads = reads + 1
        // Same-size content mutation is intentionally NOT detected/authenticated.
        @fs.write_binary(path, b"xyz", create_mode=TruncateExisting)
        b"\x72\x73\x02\x36\x45\x00\x03\x00"
      },
    )
    assert_eq(reads, 1)
    assert_eq(result.basis_bytes, 3L)
    assert_eq(result.summary.copy_bytes, 3L)
  })
}

///|
async test "cli preflight basis size recheck and complete parse priority" {
  cli_test_scope(dir => {
    let path = dir + "/basis"
    @fs.write_binary(path, b"abc", create_mode=CreateNew)
    for replacement in [b"a", b"abcd"] {
      @fs.write_binary(path, b"abc", create_mode=TruncateExisting)
      let file = open_regular_input(path)
      defer file.close()
      expect_file_failure(
        () => {
          let _ = check_open_basis(
            file,
            path,
            "delta",
            @lib.Limits::default(),
            reader=(_, _) => {
              @fs.write_binary(path, replacement, create_mode=TruncateExisting)
              b"\x72\x73\x02\x36\x00"
            },
          )
        },
        "InputChanged",
      )
    }
    @fs.write_binary(path, b"abc", create_mode=TruncateExisting)
    let file = open_regular_input(path)
    defer file.close()
    let actual = try {
      let _ = check_open_basis(file, path, "delta", @lib.Limits::default(), reader=(
        _,
        _,
      ) => {
        @fs.write_binary(path, b"", create_mode=TruncateExisting)
        b"\x72\x73\x02\x36\x45\xff\x01\x55"
      })
      "success"
    } catch {
      error => core_error_tag(error)
    }
    assert_eq(actual, "InvalidOpcode")
  })
}

///|
async test "cli preflight owns and closes metadata handle on errors" {
  cli_test_scope(dir => {
    let path = dir + "/basis"
    @fs.write_binary(path, b"abc", create_mode=CreateNew)
    expect_file_failure(
      () => {
        let _ = check_patch_file(
          path,
          dir + "/missing-delta",
          @lib.Limits::default(),
        )
      },
      "read '",
    )
    // Exercise removal/recreation after failure; check_patch_file owns the
    // handle and closes it with defer on both success and error paths.
    @fs.remove(path)
    @fs.write_binary(path, b"abc", create_mode=CreateNew)
    let delta = dir + "/delta"
    @fs.write_binary(
      delta,
      b"\x72\x73\x02\x36\x45\x00\x03\x00",
      create_mode=CreateNew,
    )
    assert_eq(
      check_patch_file(path, delta, @lib.Limits::default()).summary.output_bytes,
      3L,
    )
    @fs.remove(path)
  })
}

///|
async test "cli inspection output write failure propagates" {
  let mut calls = 0
  expect_file_failure(
    () => {
      write_inspection("complete object\n", writer=data => {
        assert_eq(data, b"complete object\n")
        calls = calls + 1
        raise FileFailure("controlled stdout failure")
      })
    },
    "controlled stdout failure",
  )
  assert_eq(calls, 1)
}
