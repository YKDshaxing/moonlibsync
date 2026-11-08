// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "public patch restores all sixteen original upstream deltas against independent new bytes" {
  let bases = reference_bases()
  let deltas = reference_deltas()
  let news = reference_news()
  assert_eq(bases.length(), 16)
  assert_eq(deltas.length(), 16)
  assert_eq(news.length(), 16)
  for i in 0..<16 {
    let (id, basis) = bases[i]
    let (delta_id, delta) = deltas[i]
    let (new_id, expected) = news[i]
    assert_eq(id, delta_id)
    assert_eq(id, new_id)
    let restored = patch(basis, delta, Limits::default())
    assert_eq(restored, expected)
    assert_eq(patch(basis, delta, Limits::default()), expected)
  }
}
