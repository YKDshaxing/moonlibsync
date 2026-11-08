// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn inspect_generated(
  old : Bytes,
  input : Bytes,
  block : Int64,
  strong : Int64,
) -> (Int32, Int32, Int32) raise {
  let d = Limits::default()
  let sig = signature(old, { block_len: block, strong_sum_len: strong, }, d)
  let bytes = delta(sig, input, d)
  let commands = parse_delta(bytes, d)
  let mut position = 0
  let mut copied = 0
  let mut previous : DeltaCommand? = None
  for command in commands {
    match (previous, command) {
      (Some(Literal(_)), Literal(_)) =>
        fail("adjacent literals were not merged")
      (Some(Copy(offset, length)), Copy(next, _)) =>
        assert_true(checked_match_end(offset, length) != next)
      _ => ()
    }
    let size = match command {
      Literal(data) => {
        assert_eq(
          data.to_owned(),
          input[position:position + data.length()].to_owned(),
        )
        data.length()
      }
      Copy(offset, length) => {
        assert_true(offset <= old.length().to_uint64())
        assert_true(length <= old.length().to_uint64() - offset)
        let start = checked_index(offset)
        let n = checked_index(length)
        assert_eq(
          old[start:start + n].to_owned(),
          input[position:position + n].to_owned(),
        )
        copied = copied + n
        n
      }
    }
    position = position + size
    previous = Some(command)
  }
  assert_eq(position, input.length())
  assert_eq(patch(old, bytes, d), input)
  assert_eq(delta(sig, input, d), bytes)
  (bytes.length(), copied, commands.length())
}

///|
test "generated instruction contents and ranges agree with all real fixed bases" {
  let bases = reference_bases()
  let news = reference_news()
  for i in 0..<16 {
    let (id, old) = bases[i]
    let (new_id, input) = news[i]
    assert_eq(id, new_id)
    let parsed = parse_signature(reference_signatures()[i].1, Limits::default())
    let _ = inspect_generated(
      old,
      input,
      parsed.block_len.to_int64(),
      parsed.strong_sum_len.to_int64(),
    )
  }
}

///|
test "generation predetermined eight-block reuse gate and unchanged file COPY" {
  // Eight distinct 64-byte blocks remain whole around a three-byte insertion.
  // Predefined gate: all 8*64=512 reusable bytes COPY; delta < 515 input bytes.
  let old = Bytes::makei(512, i => (0x10 + i / 64).to_byte())
  let input = old[0:256].to_owned() + b"\x00\x80\xff" + old[256:].to_owned()
  let (size, copied, count) = inspect_generated(old, input, 64L, 32L)
  assert_true(size < 515)
  assert_true(copied >= 512)
  assert_eq(count, 3)
  let (_, same_copied, same_count) = inspect_generated(old, old, 64L, 32L)
  assert_eq(same_copied, 512)
  assert_eq(same_count, 1)
  // Two changed bytes across distinct blocks still leave six known whole blocks.
  let edited = old[0:70].to_owned() +
    b"!" +
    old[71:330].to_owned() +
    b"?" +
    old[331:].to_owned()
  let (_, edit_copy, _) = inspect_generated(old, edited, 64L, 32L)
  assert_true(edit_copy >= 6 * 64)
}

///|
test "generation ordinary rotate then EOF rollout finds the real short tail" {
  let d = Limits::default()
  let sig = signature(b"ABCDxyz", { block_len: 4L, strong_sum_len: 32L, }, d)
  let bytes = delta(sig, b"\x00\x80xyz", d)
  assert_eq(bytes, b"\x72\x73\x02\x36\x02\x00\x80\x45\x04\x03\x00")
  let _ = inspect_generated(b"ABCDxyz", b"xyzABCD!", 4L, 32L)
}

///|
test "generation retained merged COPY fits one instruction and minimal byte budget" {
  let d = Limits::default()
  let sig = signature(b"abcdef", { block_len: 2L, strong_sum_len: 32L, }, d)
  assert_eq(
    delta(sig, b"abcdef", { ..d, max_instructions: 1L, max_delta_bytes: 8L, }),
    b"\x72\x73\x02\x36\x45\x00\x06\x00",
  )
  let repeated = signature(b"AB", { block_len: 1L, strong_sum_len: 32L, }, d)
  assert_eq(
    delta(repeated, b"ABAB", { ..d, max_instructions: 2L, }),
    b"\x72\x73\x02\x36\x45\x00\x02\x45\x00\x02\x00",
  )
  expect_sync_error(
    () => {
      let _ = delta(repeated, b"ABAB", { ..d, max_instructions: 1L, })
    },
    "LimitExceeded",
  )
}

///|
test "generation index scan and collision candidates share one exact work budget" {
  let d = Limits::default()
  let sig = signature(b"abc", { block_len: 3L, strong_sum_len: 16L, }, d)
  // 3 index +4 initialize +1 dispatch +23 match +1 append +1 slot =33.
  assert_eq(
    delta(sig, b"abc", { ..d, max_match_work: 33L, }),
    b"\x72\x73\x02\x36\x45\x00\x03\x00",
  )
  expect_sync_error(
    () => {
      let _ = delta(sig, b"abc", { ..d, max_match_work: 32L, })
    },
    "LimitExceeded",
  )
  let weak = window_weak(b"abc")
  // Adversarial metadata, not a claim of real distinct content weak collisions.
  let crafted = crafted_index_signature(3, 16, [
    (weak, Bytes::make(16, b'\x00')),
    (weak, Bytes::make(16, b'\x00')),
    (weak, strong_sum(b"abc", 16)),
  ])
  let encoded = encode_signature(crafted, d)
  // 18 index +4 initialize +1 dispatch +58 candidate query +1 append +1 slot =83.
  assert_eq(
    delta(encoded, b"abc", { ..d, max_match_work: 83L, }),
    b"\x72\x73\x02\x36\x45\x06\x03\x00",
  )
  expect_sync_error(
    () => {
      let _ = delta(encoded, b"abc", { ..d, max_match_work: 82L, })
    },
    "LimitExceeded",
  )
  expect_sync_error(
    () => {
      let _ = delta(encoded, b"abc", { ..d, max_match_work: 78L, })
    },
    "LimitExceeded",
  )
  let work = MatchWork::new({ ..d, max_match_work: 83L, })
  let index = build_signature_index(parse_signature(encoded, d), work)
  assert_eq(work.remaining, 65L)
  let _ = scan_signature_delta(index, b"abc", d, work)
  assert_eq(work.remaining, 0L)
}

///|
test "generation checked merged length overflow leaves local accumulator intact" {
  let d = Limits::default()
  // Synthetic UInt64 arithmetic only; no huge input or basis is allocated.
  let builder : DeltaBuilder = {
    commands: [Copy(0UL, 0xffffffffffffffffUL)],
    size: 15UL,
  }
  let found : BlockMatch = {
    record_index: 0,
    nominal_offset: 0xffffffffffffffffUL,
    length: 1,
  }
  expect_sync_error(
    () => {
      append_generated_span(builder, b"x", 0, 1, Some(found), d, index_work(1L))
    },
    "IntegerOutOfRange",
  )
  assert_eq(builder.size, 15UL)
  delta_same(builder.commands, [Copy(0UL, 0xffffffffffffffffUL)])
}

///|
test "generation incremental size checks include merged literal and COPY width jumps" {
  let d = Limits::default()
  let empty = signature(b"", { block_len: 64L, strong_sum_len: 32L, }, d)
  let literal = Bytes::make(65, b'x')
  let encoded = delta(empty, literal, {
    ..d,
    max_instructions: 1L,
    max_delta_bytes: 72L,
  })
  assert_eq(encoded.length(), 72)
  delta_same(parse_delta(encoded, d), [Literal(literal)])
  expect_sync_error(
    () => {
      let _ = delta(empty, literal, { ..d, max_delta_bytes: 71L, })
    },
    "LimitExceeded",
  )
  let old = Bytes::makei(256, i => i.to_byte())
  let sig = signature(old, { block_len: 1L, strong_sum_len: 16L, }, d)
  assert_eq(
    delta(sig, old[0:255].to_owned(), {
      ..d,
      max_instructions: 1L,
      max_delta_bytes: 8L,
    }),
    b"\x72\x73\x02\x36\x45\x00\xff\x00",
  )
  assert_eq(
    delta(sig, old, { ..d, max_instructions: 1L, max_delta_bytes: 9L, }),
    b"\x72\x73\x02\x36\x46\x00\x01\x00\x00",
  )
  expect_sync_error(
    () => {
      let _ = delta(sig, old, { ..d, max_delta_bytes: 8L, })
    },
    "LimitExceeded",
  )
}
