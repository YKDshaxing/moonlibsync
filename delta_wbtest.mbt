// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn delta_same(
  a : ArrayView[DeltaCommand],
  b : ArrayView[DeltaCommand],
) -> Unit raise {
  assert_eq(a.length(), b.length())
  for i in 0..<a.length() {
    match (a[i], b[i]) {
      (Literal(x), Literal(y)) => assert_eq(x.to_owned(), y.to_owned())
      (Copy(x, n), Copy(y, m)) => {
        assert_eq(x, y)
        assert_eq(n, m)
      }
      _ => fail("command semantics changed")
    }
  }
}

///|
test "delta independent handwritten vectors cover every copy parameter pair and literal width" {
  for (bytes, expected) in opcode_vectors() {
    if expected == "E" || expected == "C" || expected == "L" {
      let parsed = parse_delta(bytes, Limits::default())
      match expected {
        "E" => assert_eq(parsed.length(), 0)
        "C" => delta_same(parsed, [Copy(2UL, 3UL)])
        _ => delta_same(parsed, [Literal(b"\x00\x80")])
      }
      let shortest = encode_delta(parsed, Limits::default())
      delta_same(parse_delta(shortest, Limits::default()), parsed)
      if expected == "C" {
        assert_eq(shortest, b"\x72\x73\x02\x36\x45\x02\x03\x00")
      }
      if expected == "L" {
        assert_eq(shortest, b"\x72\x73\x02\x36\x02\x00\x80\x00")
      }
    } else {
      expect_sync_error(
        () => {
          let _ = parse_delta(bytes, Limits::default())
        },
        expected,
      )
    }
  }
}

///|
test "delta literal shortest headers cover 1-64 and all length thresholds independently" {
  for n in 1..<=64 {
    let data = Bytes::make(n, b'\x00')
    let actual = encode_delta([Literal(data)], Limits::default())
    assert_eq(
      actual,
      b"\x72\x73\x02\x36" + Bytes::make(1, n.to_byte()) + data + b"\x00",
    )
    delta_same(parse_delta(actual, Limits::default()), [Literal(data)])
  }
  for
    (n, header) in [
      (65, b"\x41\x41"),
      (255, b"\x41\xff"),
      (256, b"\x42\x01\x00"),
      (65535, b"\x42\xff\xff"),
      (65536, b"\x43\x00\x01\x00\x00"),
    ] {
    let data = Bytes::makei(n, i => (i % 256).to_byte())
    let actual = encode_delta([Literal(data)], Limits::default())
    assert_eq(actual, b"\x72\x73\x02\x36" + header + data + b"\x00")
    delta_same(parse_delta(actual, Limits::default()), [Literal(data)])
  }
  for
    (n, header) in [
      (0xffffffffUL, b"\x43\xff\xff\xff\xff"),
      (0x100000000UL, b"\x44\x00\x00\x00\x01\x00\x00\x00\x00"),
      (0xffffffffffffffffUL, b"\x44\xff\xff\xff\xff\xff\xff\xff\xff"),
    ] {
    let out = FixedArray::make(header.length(), b'\x00')
    assert_eq(write_literal_header(out, 0L, n), header.length())
    assert_eq(Bytes::from_array(out[:]), header)
    expect_sync_error(
      () => {
        let _ = parse_delta(
          b"\x72\x73\x02\x36" + header + b"\x00",
          Limits::default(),
        )
      },
      "LimitExceeded",
    )
  }
}

///|
test "delta copy shortest parameters are independent and retain full UInt64 offsets" {
  for
    (offset, command) in [
      (0UL, b"\x45\x00\x01"),
      (255UL, b"\x45\xff\x01"),
      (256UL, b"\x49\x01\x00\x01"),
      (65535UL, b"\x49\xff\xff\x01"),
      (65536UL, b"\x4d\x00\x01\x00\x00\x01"),
      (0xffffffffUL, b"\x4d\xff\xff\xff\xff\x01"),
      (0x100000000UL, b"\x51\x00\x00\x00\x01\x00\x00\x00\x00\x01"),
      (0x8000000000000000UL, b"\x51\x80\x00\x00\x00\x00\x00\x00\x00\x01"),
      (0xffffffffffffffffUL, b"\x51\xff\xff\xff\xff\xff\xff\xff\xff\x01"),
    ] {
    let actual = encode_delta([Copy(offset, 1UL)], Limits::default())
    assert_eq(actual, b"\x72\x73\x02\x36" + command + b"\x00")
    delta_same(parse_delta(actual, Limits::default()), [Copy(offset, 1UL)])
  }
  for
    (length, command) in [
      (255UL, b"\x45\x00\xff"),
      (256UL, b"\x46\x00\x01\x00"),
      (65535UL, b"\x46\x00\xff\xff"),
      (65536UL, b"\x47\x00\x00\x01\x00\x00"),
    ] {
    assert_eq(
      encode_delta([Copy(0UL, length)], Limits::default()),
      b"\x72\x73\x02\x36" + command + b"\x00",
    )
  }
  for
    (n, width) in [
      (0xffffffffUL, 4),
      (0x100000000UL, 8),
      (0x8000000000000000UL, 8),
      (0xffffffffffffffffUL, 8),
    ] {
    assert_eq(delta_width(n), width)
    expect_sync_error(
      () => {
        let _ = encode_delta([Copy(0UL, n)], Limits::default())
      },
      "LimitExceeded",
    )
  }
}

///|
test "delta truncation at each parameter byte and every reserved opcode" {
  let header = b"\x72\x73\x02\x36"
  for n in 0..<4 {
    expect_sync_error(
      () => {
        let _ = parse_delta(header[0:n], Limits::default())
      },
      "TruncatedInput",
    )
  }
  for opcode in 0x41..<=0x54 {
    let width = if opcode <= 0x44 {
      1 << (opcode - 0x41)
    } else {
      (1 << ((opcode - 0x45) / 4)) + (1 << ((opcode - 0x45) % 4))
    }
    for n in 0..<width {
      let input = header +
        Bytes::make(1, opcode.to_byte()) +
        Bytes::make(n, b'\x00')
      expect_sync_error(
        () => {
          let _ = parse_delta(input, Limits::default())
        },
        "TruncatedInput",
      )
    }
  }
  for opcode in 0x55..<=0xff {
    expect_sync_error(
      () => {
        let _ = parse_delta(
          header + Bytes::make(1, opcode.to_byte()),
          Limits::default(),
        )
      },
      "InvalidOpcode",
    )
  }
  expect_sync_error(
    () => {
      let _ = parse_delta(header, Limits::default())
    },
    "TruncatedInput",
  )
  for tail in [b"\x00", header + b"\x00", b"\xff"] {
    expect_sync_error(
      () => {
        let _ = parse_delta(header + b"\x00" + tail, Limits::default())
      },
      "TrailingData",
    )
  }
}

///|
test "delta budgets zero lengths and competing errors are explicit" {
  let d = Limits::default()
  let empty = b"\x72\x73\x02\x36\x00"
  let literal = b"\x72\x73\x02\x36\x02\x00\xff\x00"
  let exact = {
    ..d,
    max_delta_bytes: 8L,
    max_instructions: 1L,
    max_output_bytes: 2L,
  }
  delta_same(parse_delta(literal, exact), [Literal(b"\x00\xff")])
  assert_eq(encode_delta([Literal(b"\x00\xff")], exact), literal)
  for
    limits in [
      { ..exact, max_delta_bytes: 7L, },
      { ..exact, max_instructions: 0L, },
      { ..exact, max_output_bytes: 1L, },
    ] {
    expect_sync_error(
      () => {
        let _ = parse_delta(literal, limits)
      },
      "LimitExceeded",
    )
    expect_sync_error(
      () => {
        let _ = encode_delta([Literal(b"\x00\xff")], limits)
      },
      "LimitExceeded",
    )
  }
  assert_eq(
    parse_delta(empty, {
      ..d,
      max_delta_bytes: 5L,
      max_instructions: 0L,
      max_output_bytes: 0L,
    }).length(),
    0,
  )
  expect_sync_error(
    () => {
      let _ = parse_delta(b"", { ..d, max_delta_bytes: -1L, })
    },
    "InvalidOptions:max_delta_bytes",
  )
  expect_sync_error(
    () => {
      let _ = parse_delta(b"\xff", { ..d, max_delta_bytes: 0L, })
    },
    "LimitExceeded",
  )
  expect_sync_error(
    () => {
      let _ = parse_delta(b"\xff\xff\xff\xff", d)
    },
    "InvalidDelta",
  )
  expect_sync_error(
    () => {
      let _ = parse_delta(b"\x72\x73\x02\x36\x45\x00", {
        ..d,
        max_instructions: 0L,
      })
    },
    "TruncatedInput",
  )
  expect_sync_error(
    () => {
      let _ = parse_delta(b"\x72\x73\x02\x36\x41\x00", {
        ..d,
        max_instructions: 0L,
      })
    },
    "InvalidDelta",
  )
  expect_sync_error(
    () => {
      let _ = parse_delta(
        b"\x72\x73\x02\x36\x44\xff\xff\xff\xff\xff\xff\xff\xff", d,
      )
    },
    "LimitExceeded",
  )
  expect_sync_error(
    () => {
      let _ = encode_delta([Literal(b"")], d)
    },
    "InvalidDelta",
  )
  expect_sync_error(
    () => {
      let _ = encode_delta([Copy(0UL, 0UL)], d)
    },
    "InvalidDelta",
  )
  expect_sync_error(
    () => {
      let _ = parse_delta(b"\x72\x73\x02\x36\x45\x00\x02\x45\x00\x01\x00", {
        ..d,
        max_output_bytes: 2L,
      })
    },
    "LimitExceeded",
  )
  expect_sync_error(
    () => {
      let _ = delta_add_output(0xffffffffffffffffUL, 1UL, 0xffffffffffffffffUL)
    },
    "LimitExceeded",
  )
  for opcode in 0x41..<=0x54 {
    let width = if opcode <= 0x44 {
      1 << (opcode - 0x41)
    } else {
      (1 << ((opcode - 0x45) / 4)) + (1 << ((opcode - 0x45) % 4))
    }
    expect_sync_error(
      () => {
        let _ = parse_delta(
          b"\x72\x73\x02\x36" +
          Bytes::make(1, opcode.to_byte()) +
          Bytes::make(width, b'\x00'),
          d,
        )
      },
      "InvalidDelta",
    )
  }
  for
    length in [
      b"\x80\x00\x00\x00\x00\x00\x00\x00", b"\xff\xff\xff\xff\xff\xff\xff\xff",
    ] {
    expect_sync_error(
      () => {
        let _ = parse_delta(b"\x72\x73\x02\x36\x48\x00" + length + b"\x00", d)
      },
      "LimitExceeded",
    )
  }
  let two = b"\x72\x73\x02\x36\x45\x00\x01\x45\x01\x01\x00"
  assert_eq(parse_delta(two, { ..d, max_instructions: 2L, }).length(), 2)
  expect_sync_error(
    () => {
      let _ = parse_delta(two, { ..d, max_instructions: 1L, })
    },
    "LimitExceeded",
  )
  for _ in 0..<3 {
    expect_sync_error(
      () => {
        let _ = parse_delta(literal[0:6], d)
      },
      "TruncatedInput",
    )
    assert_eq(encode_delta(parse_delta(literal, d), d), literal)
  }
}

///|
test "delta actual upstream streams parse fully and shortest reencoding preserves commands" {
  for (_, bytes) in reference_deltas() {
    let commands = parse_delta(bytes, Limits::default())
    let shortest = encode_delta(commands, Limits::default())
    delta_same(parse_delta(shortest, Limits::default()), commands)
    for command in commands {
      match command {
        Literal(data) => assert_true(data.length() > 0)
        Copy(_, length) => assert_true(length > 0UL)
      }
    }
  }
}

///|
test "wire variable width reads writes bounds and failed writes are atomic" {
  for
    (width, bytes, value) in [
      (1, b"\xff", 255UL),
      (2, b"\x80\xff", 0x80ffUL),
      (4, b"\x80\x00\x00\xff", 0x800000ffUL),
      (8, b"\xff\xff\xff\xff\xff\xff\xff\xff", 0xffffffffffffffffUL),
    ] {
    assert_eq(read_uint_be(bytes, 0L, width), value)
    let out = FixedArray::make(width + 2, b'\xaa')
    write_uint_be(out, 1L, width, value)
    assert_eq(Bytes::from_array(out[:]), b"\xaa" + bytes + b"\xaa")
    for n in 0..<width {
      expect_sync_error(
        () => {
          let _ = read_uint_be(bytes[0:n], 0L, width)
        },
        "TruncatedInput",
      )
    }
    if width < 8 {
      let untouched = FixedArray::make(width, b'\xaa')
      expect_sync_error(
        () => write_uint_be(untouched, 0L, width, 1UL << (width * 8)),
        "IntegerOutOfRange",
      )
      assert_eq(Bytes::from_array(untouched[:]), Bytes::make(width, b'\xaa'))
    }
    let short = FixedArray::make(width - 1, b'\xaa')
    expect_sync_error(
      () => write_uint_be(short, 0L, width, value),
      "TruncatedInput",
    )
    assert_eq(Bytes::from_array(short[:]), Bytes::make(width - 1, b'\xaa'))
  }
  expect_sync_error(
    () => {
      let _ = read_uint_be(b"", 0L, 3)
    },
    "InvalidOptions:wire_width",
  )
}
