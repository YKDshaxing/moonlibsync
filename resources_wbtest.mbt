// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "resources command relocation must be charged before capacity or length changes" {
  let d = Limits::default()
  let commands : Array[DeltaCommand] = Array(capacity=1)
  commands.push(Copy(0UL, 1UL))
  let builder : DeltaBuilder = { commands, size: 8UL, }
  let found : BlockMatch = { record_index: 0, nominal_offset: 0UL, length: 1, }
  let work = index_work(3L) // append1 + new slots2 + relocation1 requires4
  expect_sync_error(
    () => {
      append_generated_span(
        builder,
        b"AA",
        1,
        2,
        Some(found),
        { ..d, max_instructions: 2L, max_delta_bytes: 11L, },
        work,
      )
    },
    "LimitExceeded",
  )
  assert_eq(work.remaining, 2L)
  assert_eq(builder.commands.length(), 1)
  assert_eq(builder.commands.capacity(), 1)
  assert_eq(builder.size, 8UL)
  let exact = index_work(4L)
  append_generated_span(
    builder,
    b"AA",
    1,
    2,
    Some(found),
    { ..d, max_instructions: 2L, max_delta_bytes: 11L, },
    exact,
  )
  assert_eq(exact.remaining, 0L)
  assert_eq(builder.commands.length(), 2)
  assert_eq(builder.commands.capacity(), 2)
  assert_eq(builder.size, 11UL)
}

///|
fn resource_triplets(
  field : String,
  needed : Int64,
  action : (Limits) -> Unit raise SyncError,
) -> Unit raise {
  expect_sync_error(
    () => action(with_field(field, needed - 1L)),
    "LimitExceeded",
  )
  action(with_field(field, needed))
  action(with_field(field, needed + 1L))
}

///|
test "resources signature four applicable limits have explicit three point boundaries" {
  let options : SignatureOptions = { block_len: 2L, strong_sum_len: 16L, }
  // abc uses two records, each 4+16 bytes: 12+2*20=52 bytes.
  for
    (field, needed) in [
      ("max_old_bytes", 3L),
      ("max_block_bytes", 2L),
      ("max_signature_records", 2L),
      ("max_signature_bytes", 52L),
    ] {
    resource_triplets(field, needed, limits => {
      let _ = signature(b"abc", options, limits)
    })
  }
}

///|
test "resources delta eight applicable limits have explicit three point boundaries" {
  let d = Limits::default()
  let sig = signature(b"abc", { block_len: 3L, strong_sum_len: 16L, }, d)
  // One record =>32-byte signature; one COPY =>8-byte delta; full match work33.
  for
    (field, needed) in [
      ("max_signature_bytes", 32L),
      ("max_signature_records", 1L),
      ("max_block_bytes", 3L),
      ("max_new_bytes", 3L),
      ("max_output_bytes", 3L),
      ("max_delta_bytes", 8L),
      ("max_instructions", 1L),
      ("max_match_work", 33L),
    ] {
    resource_triplets(field, needed, limits => {
      let _ = delta(sig, b"abc", limits)
    })
  }
}

///|
test "resources patch four applicable limits have explicit three point boundaries" {
  let encoded = b"\x72\x73\x02\x36\x01X\x45\x00\x03\x00"
  for
    (field, needed) in [
      ("max_old_bytes", 3L),
      ("max_delta_bytes", 10L),
      ("max_output_bytes", 4L),
      ("max_instructions", 2L),
    ] {
    resource_triplets(field, needed, limits => {
      let _ = patch(b"abc", encoded, limits)
    })
  }
}

///|
test "resources all entry points validate even irrelevant configuration fields" {
  let fields = [
    "max_old_bytes", "max_new_bytes", "max_signature_bytes", "max_signature_records",
    "max_block_bytes", "max_delta_bytes", "max_output_bytes", "max_instructions",
    "max_match_work",
  ]
  for field in fields {
    for value in [-1L, 2147483648L] {
      let limits = with_field(field, value)
      expect_sync_error(
        () => {
          let _ = signature(b"", SignatureOptions::default(), limits)
        },
        "InvalidOptions:" + field,
      )
      expect_sync_error(
        () => {
          let _ = delta(b"", b"", limits)
        },
        "InvalidOptions:" + field,
      )
      expect_sync_error(
        () => {
          let _ = patch(b"", b"", limits)
        },
        "InvalidOptions:" + field,
      )
    }
  }
  expect_sync_error(
    () => {
      let _ = delta(b"", b"", with_field("max_block_bytes", 0L))
    },
    "InvalidOptions:max_block_bytes",
  )
}

///|
test "resources valid irrelevant zero limits do not meter other operations" {
  let d = Limits::default()
  let sig = signature(b"ab", { block_len: 2L, strong_sum_len: 16L, }, {
    ..d,
    max_new_bytes: 0L,
    max_delta_bytes: 0L,
    max_output_bytes: 0L,
    max_instructions: 0L,
    max_match_work: 0L,
  })
  let encoded = delta(sig, b"ab", { ..d, max_old_bytes: 0L, })
  assert_eq(
    patch(b"ab", encoded, {
      ..d,
      max_new_bytes: 0L,
      max_signature_bytes: 0L,
      max_signature_records: 0L,
      max_block_bytes: 1L,
      max_match_work: 0L,
    }),
    b"ab",
  )
}

///|
test "resources empty signature and delta minima zero items and zero output" {
  let d = Limits::default()
  let sig = b"\x72\x73\x01\x47\x00\x00\x08\x00\x00\x00\x00\x20"
  let empty = b"\x72\x73\x02\x36\x00"
  for cap in [11L, 12L, 13L] {
    let limits = {
      ..d,
      max_old_bytes: 0L,
      max_signature_records: 0L,
      max_signature_bytes: cap,
    }
    if cap < 12L {
      expect_sync_error(
        () => {
          let _ = signature(b"", SignatureOptions::default(), limits)
        },
        "LimitExceeded",
      )
      expect_sync_error(
        () => {
          let _ = delta(sig, b"", limits)
        },
        "LimitExceeded",
      )
    } else {
      assert_eq(signature(b"", SignatureOptions::default(), limits), sig)
      assert_eq(delta(sig, b"", limits), empty)
    }
  }
  for cap in [4L, 5L, 6L] {
    let limits = {
      ..d,
      max_old_bytes: 0L,
      max_new_bytes: 0L,
      max_signature_records: 0L,
      max_delta_bytes: cap,
      max_instructions: 0L,
      max_output_bytes: 0L,
      max_match_work: 0L,
    }
    if cap < 5L {
      expect_sync_error(
        () => {
          let _ = delta(sig, b"", limits)
        },
        "LimitExceeded",
      )
      expect_sync_error(
        () => {
          let _ = patch(b"", empty, limits)
        },
        "LimitExceeded",
      )
    } else {
      assert_eq(delta(sig, b"", limits), empty)
      assert_eq(patch(b"", empty, limits), b"")
    }
  }
  expect_sync_error(
    () => {
      let _ = delta(b"", b"", { ..d, max_match_work: 0L, })
    },
    "TruncatedInput",
  )
  expect_sync_error(
    () => {
      let _ = patch(b"a", empty, { ..d, max_old_bytes: 0L, })
    },
    "LimitExceeded",
  )
}

///|
test "resources signature precedence keeps configuration options representation and budgets distinct" {
  let d = Limits::default()
  let o = SignatureOptions::default()
  expect_sync_error(
    () => {
      let _ = signature(b"abc", { ..o, block_len: 0L, }, {
        ..d,
        max_match_work: -1L,
      })
    },
    "InvalidOptions:max_match_work",
  )
  expect_sync_error(
    () => {
      let _ = signature(b"abc", { ..o, block_len: 0L, }, {
        ..d,
        max_old_bytes: 0L,
      })
    },
    "InvalidOptions:block_len",
  )
  expect_sync_error(
    () => {
      let _ = signature(
        b"abc",
        { block_len: 2147483648L, strong_sum_len: 0L, },
        d,
      )
    },
    "InvalidOptions:strong_sum_len",
  )
  expect_sync_error(
    () => {
      let _ = signature(b"abc", { ..o, block_len: 2147483648L, }, {
        ..d,
        max_old_bytes: 0L,
      })
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = signature(b"abc", o, {
        ..d,
        max_old_bytes: 0L,
        max_block_bytes: 1L,
      })
    },
    "LimitExceeded",
  )
}

///|
test "resources delta precedence preserves complete signature before new policy" {
  let d = Limits::default()
  expect_sync_error(
    () => {
      let _ = delta(b"", b"abc", { ..d, max_new_bytes: 0L, })
    },
    "TruncatedInput",
  )
  expect_sync_error(
    () => {
      let _ = delta(b"", b"abc", {
        ..d,
        max_signature_bytes: 0L,
        max_new_bytes: 0L,
      })
    },
    "TruncatedInput",
  )
  expect_sync_error(
    () => {
      let _ = delta(b"x", b"", { ..d, max_signature_bytes: 0L, })
    },
    "LimitExceeded",
  )
  let high = b"\x72\x73\x01\x47\x80\x00\x00\x00\x00\x00\x00\x10"
  expect_sync_error(
    () => {
      let _ = delta(high, b"", d)
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = delta(high + b"x", b"", d)
    },
    "TruncatedInput",
  )
  let unsupported = b"\x72\x73\x01\x36\x00\x00\x00\x00\x00\x00\x00\x00"
  expect_sync_error(
    () => {
      let _ = delta(unsupported, b"abc", { ..d, max_new_bytes: 0L, })
    },
    "UnsupportedSignatureProfile",
  )
}

///|
test "resources patch precedence retains full parse before basis copy checks" {
  let d = Limits::default()
  expect_sync_error(
    () => {
      let _ = patch(b"abc", b"bad!", { ..d, max_old_bytes: 0L, })
    },
    "LimitExceeded",
  )
  expect_sync_error(
    () => {
      let _ = patch(b"abc", b"bad!", d)
    },
    "InvalidDelta",
  )
  expect_sync_error(
    () => {
      let _ = patch(b"", b"x", { ..d, max_delta_bytes: 0L, })
    },
    "LimitExceeded",
  )
  let bad_copy = b"\x72\x73\x02\x36\x45\xff\x01"
  expect_sync_error(
    () => {
      let _ = patch(b"a", bad_copy, d)
    },
    "TruncatedInput",
  )
  expect_sync_error(
    () => {
      let _ = patch(b"a", bad_copy + b"\x00\xff", d)
    },
    "TrailingData",
  )
  expect_sync_error(
    () => {
      let _ = patch(b"a", bad_copy + b"\x55", d)
    },
    "InvalidOpcode",
  )
  expect_sync_error(
    () => {
      let _ = patch(b"a", bad_copy + b"\x00", d)
    },
    "CopyOutOfBounds",
  )
  expect_sync_error(
    () => {
      let _ = patch(b"a", b"\x72\x73\x02\x36\x45\xff\x00\x00", d)
    },
    "InvalidDelta",
  )
  let high = b"\x72\x73\x02\x36\x51\xff\xff\xff\xff\xff\xff\xff\xff\x01\x00"
  expect_sync_error(
    () => {
      let _ = patch(b"a", high, d)
    },
    "CopyOutOfBounds",
  )
  let huge = b"\x72\x73\x02\x36\x48\x00\xff\xff\xff\xff\xff\xff\xff\xff\x00"
  expect_sync_error(
    () => {
      let _ = patch(b"a", huge, d)
    },
    "LimitExceeded",
  )
}

///|
test "resources record preflight exact storage and index allocation precharge" {
  let d = Limits::default()
  let bytes = signature(
    Bytes::make(65, b'a'),
    { block_len: 1L, strong_sum_len: 16L, },
    d,
  )
  expect_sync_error(
    () => {
      let _ = parse_signature(bytes, { ..d, max_signature_records: 64L, })
    },
    "LimitExceeded",
  )
  let parsed = parse_signature(bytes, { ..d, max_signature_records: 65L, })
  assert_eq(parsed.records.length(), 65)
  assert_eq(parsed.records.capacity(), 65)
  let before = index_work(194L) // first 3*n charge fails before both sort arrays
  expect_sync_error(
    () => {
      let _ = build_signature_index(parsed, before)
    },
    "LimitExceeded",
  )
  assert_eq(before.remaining, 194L)
  let after = index_work(195L) // arrays may exist; first comparison has no credit
  expect_sync_error(
    () => {
      let _ = build_signature_index(parsed, after)
    },
    "LimitExceeded",
  )
  assert_eq(after.remaining, 0L)
}

///|
test "resources hostile 128 candidate prefixes charge one digest and all actual comparisons" {
  let d = Limits::default()
  let correct = strong_sum(b"abc", 32)
  let wrong = correct[0:31].to_owned() +
    Bytes::make(1, (correct[31].to_int() ^ 1).to_byte())
  let weak = window_weak(b"abc")
  let records = Array::make(128, (weak, wrong))
  let sig = crafted_index_signature(3, 32, records)
  // Sorted128: init384 + 7*128 writes + 7*64 comparisons =1728.
  let build = index_work(1728L)
  let index = build_signature_index(sig, build)
  assert_eq(build.remaining, 0L)
  // lower_bound8 + presence1 + digest(1+3) + 128*(visit1+compare32)=4237.
  let query = index_work(4237L)
  assert_true(match_signature_window(index, b"abc", weak, query) is None)
  assert_eq(query.remaining, 0L)
  let short = index_work(4236L)
  expect_sync_error(
    () => {
      let _ = match_signature_window(index, b"abc", weak, short)
    },
    "LimitExceeded",
  )
  assert_eq(short.remaining, 31L) // failed full32 comparison is not deducted
  records[127] = (weak, correct)
  let late = encode_signature(crafted_index_signature(3, 32, records), d)
  for budget in [5971L, 5972L, 5973L] {
    if budget == 5971L {
      expect_sync_error(
        () => {
          let _ = delta(late, b"abc", { ..d, max_match_work: budget, })
        },
        "LimitExceeded",
      )
    } else {
      assert_eq(
        delta(late, b"abc", { ..d, max_match_work: budget, }),
        b"\x72\x73\x02\x36\x49\x01\x7d\x03\x00",
      )
    }
  }
}

///|
test "resources repeated windows and unmergeable copies consume shared work and slots" {
  let d = Limits::default()
  let input = Bytes::make(64, b'a')
  let sig = signature(input, { block_len: 1L, strong_sum_len: 16L, }, d)
  // Index768 +64*(setup2+dispatch1+query27+append1) +growth190 =2942.
  let work = index_work(10000L)
  let index = build_signature_index(parse_signature(sig, d), work)
  let encoded = scan_signature_delta(
    index,
    input,
    { ..d, max_instructions: 64L, max_delta_bytes: 197L, },
    work,
  )
  assert_eq(work.remaining, 7058L)
  assert_eq(parse_delta(encoded, d).length(), 64)
  for
    limits in [
      { ..d, max_instructions: 63L, },
      { ..d, max_delta_bytes: 196L, },
      { ..d, max_match_work: 2941L, },
    ] {
    expect_sync_error(
      () => {
        let _ = delta(sig, input, limits)
      },
      "LimitExceeded",
    )
  }
  assert_eq(delta(sig, input, { ..d, max_match_work: 2942L, }), encoded)
}

///|
test "resources long misses merge without payload copies and meter rotate plus EOF" {
  let d = Limits::default()
  let sig = signature(b"", { block_len: 64L, strong_sum_len: 32L, }, d)
  let input = Bytes::make(512, b'x')
  // setup65 +448 rotate steps*5 +64 rollout steps*4 +first slot1 =2562.
  let exact = {
    ..d,
    max_instructions: 1L,
    max_delta_bytes: 520L,
    max_match_work: 2562L,
  }
  let encoded = delta(sig, input, exact)
  assert_eq(encoded.length(), 520)
  delta_same(parse_delta(encoded, d), [Literal(input)])
  expect_sync_error(
    () => {
      let _ = delta(sig, input, { ..exact, max_match_work: 2561L, })
    },
    "LimitExceeded",
  )
  expect_sync_error(
    () => {
      let _ = delta(sig, input, { ..exact, max_delta_bytes: 519L, })
    },
    "LimitExceeded",
  )
}

///|
test "resources delta size rejection precedes command replacement or reserve" {
  let d = Limits::default()
  let input = Bytes::make(512, b'x')
  let commands : Array[DeltaCommand] = Array(capacity=1)
  commands.push(Literal(input[0:511]))
  let builder : DeltaBuilder = { commands, size: 519UL, }
  let work = index_work(1L)
  expect_sync_error(
    () => {
      append_generated_span(
        builder,
        input,
        511,
        512,
        None,
        { ..d, max_delta_bytes: 519L, },
        work,
      )
    },
    "LimitExceeded",
  )
  assert_eq(work.remaining, 0L)
  assert_eq(builder.size, 519UL)
  assert_eq(builder.commands.capacity(), 1)
  delta_same(builder.commands, [Literal(input[0:511])])
}

///|
test "resources unsigned multiplication addition index and write boundaries avoid huge inputs" {
  let max = 0xffffffffffffffffUL
  assert_eq(checked_block_offset(max, 1UL), max)
  expect_sync_error(
    () => {
      let _ = checked_block_offset(max, 2UL)
    },
    "IntegerOutOfRange",
  )
  assert_eq(checked_match_end(max - 1UL, 1UL), max)
  expect_sync_error(
    () => {
      let _ = checked_match_end(max, 1UL)
    },
    "IntegerOutOfRange",
  )
  assert_eq(checked_index(2147483647UL), 2147483647)
  expect_sync_error(
    () => {
      let _ = checked_index(2147483648UL)
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = signature_size(max, 32UL)
    },
    "IntegerOutOfRange",
  )
  expect_sync_error(
    () => {
      let _ = delta_add_output(max, 1UL, max)
    },
    "LimitExceeded",
  )
  let out = FixedArray::make(2, b'\xaa')
  expect_sync_error(
    () => write_uint_be(out, 0L, 2, 65536UL),
    "IntegerOutOfRange",
  )
  assert_eq(Bytes::from_array(out[:]), b"\xaa\xaa")
  assert_eq(
    read_uint_be(b"\x80\x00\x00\x00\x00\x00\x00\x00", 0L, 8),
    0x8000000000000000UL,
  )
}

///|
test "resources all public operations recover after interleaved failures without input mutation" {
  let d = Limits::default()
  let o : SignatureOptions = { block_len: 3L, strong_sum_len: 16L, }
  let input = b"abc"
  let sig = signature(input, o, d)
  let saved = sig.to_array()
  let encoded = delta(sig, input, { ..d, max_match_work: 33L, })
  let output = patch(input, encoded, d)
  for _ in 0..<4 {
    expect_sync_error(
      () => {
        let _ = signature(input, o, { ..d, max_old_bytes: 0L, })
      },
      "LimitExceeded",
    )
    expect_sync_error(
      () => {
        let _ = signature(input, { ..o, block_len: 0L, }, d)
      },
      "InvalidOptions:block_len",
    )
    assert_eq(signature(input, o, d), sig)
    expect_sync_error(
      () => {
        let _ = delta(sig, input, { ..d, max_match_work: 32L, })
      },
      "LimitExceeded",
    )
    expect_sync_error(
      () => {
        let _ = delta(sig, input, { ..d, max_instructions: 0L, })
      },
      "LimitExceeded",
    )
    expect_sync_error(
      () => {
        let _ = delta(b"", input, d)
      },
      "TruncatedInput",
    )
    assert_eq(delta(sig, input, { ..d, max_match_work: 33L, }), encoded)
    expect_sync_error(
      () => {
        let _ = patch(input, encoded, { ..d, max_output_bytes: 0L, })
      },
      "LimitExceeded",
    )
    expect_sync_error(
      () => {
        let _ = patch(input, b"\x72\x73\x02\x36\x45\x03\x01\x00", d)
      },
      "CopyOutOfBounds",
    )
    expect_sync_error(
      () => {
        let _ = patch(input, encoded + b"\x00", d)
      },
      "TrailingData",
    )
    assert_eq(patch(input, encoded, d), input)
    assert_eq(input, b"abc")
    assert_eq(Bytes::from_array(saved[:]), sig)
    assert_eq(output, b"abc")
  }
}

///|
test "resources actual weak input length and unpaid rollout leave shared credit exhausted" {
  let d = Limits::default()
  let input = Bytes::make(256, b'x')
  let too_short = index_work(256L)
  expect_sync_error(
    () => {
      let _ = generation_window(input, 0, 256, too_short)
    },
    "LimitExceeded",
  )
  assert_eq(too_short.remaining, 256L)
  let exact = index_work(257L)
  assert_eq(generation_window(input, 0, 256, exact).count, 256)
  assert_eq(exact.remaining, 0L)
  // Strong digest precharge is 1+256 input bytes, even with a one-byte prefix.
  let single = crafted_index_signature(256, 1, [
    (window_weak(input), strong_sum(input, 1)),
  ])
  let one_index = build_signature_index(single, index_work(3L))
  let hash_short = index_work(258L) // two probes leave256, insufficient for257
  expect_sync_error(
    () => {
      let _ = match_signature_window(
        one_index,
        input,
        window_weak(input),
        hash_short,
      )
    },
    "LimitExceeded",
  )
  assert_eq(hash_short.remaining, 256L)
  let hash_exact = index_work(261L) // binary1 +presence1 +hash257 +visit1 +compare1
  assert_block_match(
    match_signature_window(one_index, input, window_weak(input), hash_exact),
    0,
    0UL,
    256,
  )
  assert_eq(hash_exact.remaining, 0L)
  let empty = parse_signature(
    signature(b"", { block_len: 3L, strong_sum_len: 1L, }, d),
    d,
  )
  let empty_index = build_signature_index(empty, index_work(0L))
  let unpaid = index_work(8L) // first setup4+dispatch1+append1+slot1 leaves1 < rollout2
  expect_sync_error(
    () => {
      let _ = scan_signature_delta(empty_index, b"abc", d, unpaid)
    },
    "LimitExceeded",
  )
  assert_eq(unpaid.remaining, 1L)
  expect_sync_error(
    () => {
      let _ = scan_signature_delta(empty_index, b"abc", d, unpaid)
    },
    "LimitExceeded",
  )
  assert_eq(unpaid.remaining, 1L)
  assert_eq(
    scan_signature_delta(empty_index, b"abc", d, index_work(17L)),
    b"\x72\x73\x02\x36\x03abc\x00",
  )
}

///|
test "resources command growth respects the logical instruction ceiling" {
  let d = Limits::default()
  let builder : DeltaBuilder = { commands: [], size: 5UL, }
  let found : BlockMatch = { record_index: 0, nominal_offset: 0UL, length: 1, }
  let work = index_work(100L)
  let limits = { ..d, max_instructions: 3L, }
  append_generated_span(builder, b"aaaa", 0, 1, Some(found), limits, work)
  assert_eq(builder.commands.capacity(), 1)
  append_generated_span(builder, b"aaaa", 1, 2, Some(found), limits, work)
  assert_eq(builder.commands.capacity(), 2)
  append_generated_span(builder, b"aaaa", 2, 3, Some(found), limits, work)
  assert_eq(builder.commands.capacity(), 3)
  // Three append actions +growth(1+3+5)=12 units, not automatic capacity4.
  assert_eq(work.remaining, 88L)
  expect_sync_error(
    () => {
      append_generated_span(builder, b"aaaa", 3, 4, Some(found), limits, work)
    },
    "LimitExceeded",
  )
  assert_eq(builder.commands.length(), 3)
  assert_eq(builder.commands.capacity(), 3)
  assert_eq(work.remaining, 87L)
}
