// SPDX-License-Identifier: LGPL-2.1-or-later

///|
async fn expect_file_failure(
  action : async () -> Unit,
  needle : String,
) -> Unit {
  let actual = try {
    action()
    None
  } catch {
    error => Some(cli_error_text(error))
  }
  guard actual is Some(text) else { fail("expected controlled failure") }
  if !text.contains(needle) {
    fail("wanted " + needle + ", actual " + text)
  }
}

///|
async fn cli_test_scope(body : async (String) -> Unit) -> Unit {
  let created = @fs.tmpdir(prefix="moonlibsync-cli-test-")
  let absolute = @fs.realpath(created)
  // Fresh, exclusively created test directory, never a workspace/user directory.
  guard @path.Path(absolute).basename().has_prefix("moonlibsync-cli-test-") else {
    fail("unexpected temporary root")
  }
  defer @fs.rmdir(absolute, recursive=true)
  body(absolute)
}

///|
test "cli parser full decimals options positions and separator" {
  let p = parse_plan([
    "signature", "--sum-size", "16", "old", "out", "--block-size", "2",
  ])
  assert_eq(p.options.block_len, 2L)
  assert_eq(p.options.strong_sum_len, 16L)
  assert_eq(parse_plan(["signature", "--", "--old", "-"]).inputs[0], "--old")
  assert_eq(parse_plan(["signature", "old", "out"]).options.block_len, 2048L)
  for
    args in [
      ["bad"],
      ["signature"],
      ["signature", "old", "out", "extra"],
      ["signature", "old", "out", "--block-size"],
      ["signature", "old", "out", "--sum-size", "1", "--sum-size", "2"],
      ["delta", "sig", "new", "out", "--sum-size", "1"],
    ] {
    let actual = try {
      let _ = parse_plan(args)
      false
    } catch {
      Usage(_) => true
      _ => false
    }
    assert_true(actual)
  }
  for
    value in [
      "", "0", "-1", "+1", "1x", " 2", "2 ", "2147483648", "9999999999999999999999999999999999999",
      "1048577",
    ] {
    let actual = try {
      let _ = positive_decimal(value, 1048576L)
      false
    } catch {
      Usage(_) => true
      _ => false
    }
    assert_true(actual)
  }
  assert_eq(positive_decimal("0002", 32L), 2L)
}

///|
async test "cli bounded handle reads empty chunk boundaries and shrink errors" {
  cli_test_scope(dir => {
    let path = dir + "/old"
    let data = Bytes::makei(70001, i => (i % 256).to_byte())
    @fs.write_binary(path, data, create_mode=CreateNew)
    assert_eq(bounded_read(path, 70001L), data)
    expect_file_failure(
      () => {
        let _ = bounded_read(path, 70000L)
      },
      "ReadLimitExceeded",
    )
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    expect_file_failure(
      () => {
        let _ = read_open_file(file, path, 70001L, after_size=() => {
          @fs.write_binary(path, b"x", create_mode=TruncateExisting)
        })
      },
      "short read",
    )
    @fs.remove(path)
    @fs.write_binary(path, b"", create_mode=CreateNew)
    assert_eq(bounded_read(path, 0L), b"")
  })
}

///|
async test "cli growth is rejected using one byte sentinel without growing allocation" {
  cli_test_scope(dir => {
    let path = dir + "/old"
    @fs.write_binary(path, b"abc", create_mode=CreateNew)
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    expect_file_failure(
      () => {
        let _ = read_open_file(file, path, 3L, after_size=() => {
          @fs.write_binary(path, b"abcd", create_mode=TruncateExisting)
        })
      },
      "InputChanged",
    )
  })
}

///|
async test "cli partial write failure removes owned temporary and permits next publication" {
  cli_test_scope(dir => {
    let temp = dir + "/temp"
    let out = dir + "/out"
    expect_file_failure(
      () => {
        publish_at(temp, out, b"abc", writer=(file, data) => {
          file.write(data[0:1])
          raise FileFailure("controlled write failure")
        })
      },
      "controlled write failure",
    )
    assert_true(!entry_exists(temp) && !entry_exists(out))
    publish_at(temp, out, b"abc")
    assert_eq(bounded_read(out, 3L), b"abc")
  })
}

///|
async test "cli failed exclusive create never cleans foreign temporary or output" {
  cli_test_scope(dir => {
    let temp = dir + "/temp"
    let out = dir + "/out"
    @fs.write_binary(temp, b"FOREIGN", create_mode=CreateNew)
    @fs.write_binary(out, b"BEFORE", create_mode=CreateNew)
    expect_file_failure(() => publish_at(temp, out, b"abc"), "")
    assert_eq(bounded_read(temp, 7L), b"FOREIGN")
    assert_eq(bounded_read(out, 6L), b"BEFORE")
  })
}

///|
async test "cli no replace commit and cleanup failure preserve diagnostic and ownership" {
  cli_test_scope(dir => {
    let temp = dir + "/temp"
    let out = dir + "/out"
    expect_file_failure(
      () => {
        publish_at(temp, out, b"abc", before_commit=() => {
          @fs.write_binary(out, b"USER", create_mode=CreateNew)
        })
      },
      "write/commit",
    )
    assert_eq(bounded_read(out, 4L), b"USER")
    assert_true(!entry_exists(temp))
    @fs.remove(out)
    expect_file_failure(
      () => {
        publish_at(
          temp,
          out,
          b"abc",
          writer=(file, data) => {
            file.write(data[0:1])
            raise FileFailure("controlled write failure")
          },
          cleanup=_ => raise FileFailure("controlled cleanup failure"),
        )
      },
      "cleanup failed",
    )
    assert_true(entry_exists(temp) && !entry_exists(out))
    assert_eq(bounded_read(temp, 1L), b"a")
    @fs.remove(temp)
    publish_at(temp, out, b"OK")
    assert_eq(bounded_read(out, 2L), b"OK")
  })
}
