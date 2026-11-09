// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "inspect all handwritten opcode vectors with independent statistics" {
  let d = Limits::default()
  let vectors = opcode_vectors()
  assert_eq(vectors.length(), 29)
  for (bytes, kind) in vectors {
    if kind != "E" && kind != "L" && kind != "C" {
      expect_sync_error(
        () => {
          let _ = inspect_delta(bytes, d)
        },
        kind,
      )
      expect_sync_error(
        () => {
          let _ = check_patch(5L, bytes, d)
        },
        kind,
      )
      continue
    }
    let s = inspect_delta(bytes, d)
    assert_eq(s.delta_bytes, bytes.length().to_int64())
    match kind {
      "E" => {
        assert_eq(s.instruction_count, 0L)
        assert_eq(s.literal_commands, 0L)
        assert_eq(s.copy_commands, 0L)
        assert_eq(s.literal_bytes, 0L)
        assert_eq(s.copy_bytes, 0L)
        assert_eq(s.output_bytes, 0L)
      }
      "L" => {
        assert_eq(s.instruction_count, 1L)
        assert_eq(s.literal_commands, 1L)
        assert_eq(s.copy_commands, 0L)
        assert_eq(s.literal_bytes, 2L)
        assert_eq(s.copy_bytes, 0L)
        assert_eq(s.output_bytes, 2L)
      }
      "C" => {
        assert_eq(s.instruction_count, 1L)
        assert_eq(s.literal_commands, 0L)
        assert_eq(s.copy_commands, 1L)
        assert_eq(s.literal_bytes, 0L)
        assert_eq(s.copy_bytes, 3L)
        assert_eq(s.output_bytes, 3L)
        assert_eq(check_patch(5L, bytes, d).summary.output_bytes, 3L)
      }
      _ => abort("unexpected opcode vector category")
    }
  }
}

///|
test "inspect sixteen fixed upstream fixtures independent lengths and recovery" {
  let bases = reference_bases()
  let signatures = reference_signatures()
  let deltas = reference_deltas()
  let news = reference_news()
  assert_eq(signatures.length(), 16)
  assert_eq(bases.length(), 16)
  assert_eq(deltas.length(), 16)
  assert_eq(news.length(), 16)
  for i in 0..<16 {
    let (id, sig) = signatures[i]
    assert_eq(bases[i].0, id)
    assert_eq(deltas[i].0, id)
    assert_eq(news[i].0, id)
    let block = match id {
      "empty" | "default-edit" => 2048L
      "before-block" | "exact-block" | "after-block" | "repeat" => 16L
      _ => 7L
    }
    let strong = match id {
      "empty-new" | "one" | "after-block" | "insert-head" | "delete-tail" => 1L
      "to-empty"
      | "before-block"
      | "repeat"
      | "insert-middle"
      | "delete-head" => 16L
      _ => 32L
    }
    let count = match id {
      "empty" | "empty-new" => 0L
      "one" | "before-block" | "exact-block" => 1L
      "after-block" => 2L
      _ => 3L
    }
    let d = Limits::default()
    let s = inspect_signature(sig, d)
    assert_eq(s.magic, 0x72730147U)
    assert_eq(s.block_len, block)
    assert_eq(s.strong_sum_len, strong)
    assert_eq(s.record_count, count)
    assert_eq(s.signature_bytes, 12L + count * (4L + strong))
    let delta = deltas[i].1
    let old = bases[i].1
    let expected = news[i].1
    let ds = inspect_delta(delta, d)
    assert_eq(ds.output_bytes, expected.length().to_int64())
    assert_eq(ds.instruction_count, ds.literal_commands + ds.copy_commands)
    assert_eq(ds.output_bytes, ds.literal_bytes + ds.copy_bytes)
    assert_eq(ds.delta_bytes, delta.length().to_int64())
    let p = check_patch(old.length().to_int64(), delta, d)
    assert_eq(p.basis_bytes, old.length().to_int64())
    assert_eq(p.summary.output_bytes, expected.length().to_int64())
    assert_eq(patch(old, delta, d), expected)
  }
}

///|
test "inspect preflight shares patch range helper without recovery allocation" {
  // Exercise exactly the helper both public operations call. No apply_patch_bytes
  // or output buffer is needed; COPY reads may repeat the same original byte.
  let commands : Array[DeltaCommand] = [
    Copy(0UL, 1UL),
    Copy(0UL, 1UL),
    Literal(b"ab"),
  ]
  assert_eq(patch_size(1UL, commands, Limits::default()), 4)
  expect_sync_error(
    () => {
      let _ = patch_size(0UL, commands, Limits::default())
    },
    "CopyOutOfBounds",
  )
  assert_eq(summarize_delta(13L, commands, Limits::default()).output_bytes, 4L)
}
