// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "offline upstream signatures preserve reference bytes and record structure" {
  for (id, bytes) in reference_signatures() {
    let sig = parse_signature(bytes, Limits::default())
    let block = match id {
      "empty" | "default-edit" => 2048
      "before-block" | "exact-block" | "after-block" | "repeat" => 16
      _ => 7
    }
    let strong = match id {
      "empty-new" | "one" | "after-block" | "insert-head" | "delete-tail" => 1
      "to-empty"
      | "before-block"
      | "repeat"
      | "insert-middle"
      | "delete-head" => 16
      _ => 32
    }
    let count = match id {
      "empty" | "empty-new" => 0
      "one" | "before-block" | "exact-block" => 1
      "after-block" => 2
      "default-edit" | "repeat" => 3
      _ => 3
    }
    assert_eq(sig.block_len, block)
    assert_eq(sig.strong_sum_len, strong)
    assert_eq(sig.records.length(), count)
    for i in 0..<count {
      let record = sig.records[i]
      let pos = 12 + i * (4 + strong)
      let expected_weak = (bytes[pos].to_uint() << 24) |
        (bytes[pos + 1].to_uint() << 16) |
        (bytes[pos + 2].to_uint() << 8) |
        bytes[pos + 3].to_uint()
      assert_eq(record.weak_sum, expected_weak)
      assert_eq(record.strong_sum, bytes[pos + 4:pos + 4 + strong].to_owned())
      assert_eq(record.block_index, i)
      assert_eq(record.nominal_offset, i.to_uint64() * block.to_uint64())
    }
    if id == "repeat" {
      assert_eq(sig.records[0].weak_sum, sig.records[1].weak_sum)
      assert_eq(sig.records[0].strong_sum, sig.records[1].strong_sum)
      assert_eq(sig.records[1].strong_sum, sig.records[2].strong_sum)
    }
  }
}
