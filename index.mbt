// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Record ordinals, contiguous sorted weak checksums, and an open-addressed
/// weak-sum lookup table (load factor <= 0.50); digest bytes remain in signature.
priv struct SignatureIndex {
  signature : Signature
  order : Array[Int32]
  sorted_weaks : FixedArray[UInt32]
  bucket_weak : FixedArray[UInt32]
  bucket_start : FixedArray[Int32]
}

///|
/// Confirmed against saved checksums, not proof that a real basis range exists.
#warnings("-unused_field")
priv struct BlockMatch {
  record_index : Int32
  nominal_offset : UInt64
  length : Int32
}

///|
fn weak_slot(weak : UInt32, mask : Int32) -> Int32 {
  let mut h = weak
  h = h ^ (h >> 16)
  h = h * 0x85ebca6bU
  h = h ^ (h >> 13)
  h.reinterpret_as_int() & mask
}

///|
/// Metered bottom-up merge sort plus linear O(n) open-addressed weak table,
/// with no unmetered hash collision path.
fn build_signature_index(
  sig : Signature,
  work : MatchWork,
) -> SignatureIndex raise SyncError {
  let n = sig.records.length()
  // n <= Int32.MAX; this Int64 multiplication cannot overflow. Charge for
  // one record visit and two index slots per record BEFORE either allocation.
  work.spend(n.to_int64() * 3L)
  let mut source = Array::makei(n, i => i)
  if n == 0 {
    return {
      signature: sig,
      order: source,
      sorted_weaks: [],
      bucket_weak: [],
      bucket_start: [],
    }
  }
  let mut dest = Array::make(n, 0)
  let mut width = 1
  while width < n {
    let mut left = 0
    while left < n {
      let mid = left + (if width < n - left { width } else { n - left })
      let end = mid + (if width < n - mid { width } else { n - mid })
      let mut a = left
      let mut b = mid
      let mut out = left
      while out < end {
        let take_a = if a == mid {
          false
        } else if b == end {
          true
        } else {
          work.spend(1L) // one bounded lexicographic comparison
          let x = source[a]
          let y = source[b]
          let wx = sig.records[x].weak_sum
          let wy = sig.records[y].weak_sum
          wx < wy || (wx == wy && x < y)
        }
        work.spend(1L) // one merge destination write, including remainder copies
        if take_a {
          dest[out] = source[a]
          a = a + 1
        } else {
          dest[out] = source[b]
          b = b + 1
        }
        out = out + 1
      }
      left = end
    }
    let temp = source
    source = dest
    dest = temp
    if width >= n - width {
      break
    }
    width = width * 2 // proven less than n before doubling
  }
  let sorted_weaks = FixedArray::make(n, 0U)
  for i in 0..<n {
    sorted_weaks[i] = sig.records[source[i]].weak_sum
  }
  let mut distinct = 1
  for i in 1..<n {
    if sorted_weaks[i] != sorted_weaks[i - 1] {
      distinct = distinct + 1
    }
  }
  let target = distinct.to_uint64() * 2UL
  let mut table_size = 2UL
  while table_size < target {
    table_size = table_size * 2UL
  }
  let m = checked_index(table_size)
  // Precharge both open-addressed hash table arrays before allocation.
  work.spend(2L * m.to_int64())
  let bucket_weak = FixedArray::make(m, 0U)
  let bucket_start = FixedArray::make(m, -1)
  let mask = m - 1
  let mut i = 0
  while i < n {
    let weak = sorted_weaks[i]
    let mut slot = weak_slot(weak, mask)
    while true {
      work.spend(1L) // metered open-addressed insertion probe
      if bucket_start[slot] < 0 {
        bucket_weak[slot] = weak
        bucket_start[slot] = i
        break
      }
      slot = (slot + 1) & mask
    }
    i = i + 1
    while i < n && sorted_weaks[i] == weak {
      i = i + 1
    }
  }
  { signature: sig, order: source, sorted_weaks, bucket_weak, bucket_start, }
}

///|
fn checked_match_end(
  offset : UInt64,
  length : UInt64,
) -> UInt64 raise SyncError {
  guard length <= 0xffffffffffffffffUL - offset else { raise IntegerOutOfRange }
  offset + length
}

///|
/// Probe the open-addressed weak-checksum table in O(1) expected time.
/// Returns the start ordinal in `sorted_weaks` on weak hit, or None on miss.
fn match_signature_weak(
  index : SignatureIndex,
  weak : UInt32,
  work : MatchWork,
) -> Int32? raise SyncError {
  let m = index.bucket_start.length()
  if m == 0 {
    return None
  }
  let mask = m - 1
  let mut slot = weak_slot(weak, mask)
  while true {
    work.spend(1L) // open-addressed probe before accessing candidate run
    let candidate_start = index.bucket_start[slot]
    if candidate_start < 0 {
      return None
    }
    if index.bucket_weak[slot] == weak {
      return Some(candidate_start)
    }
    slot = (slot + 1) & mask
  }
  None
}

///|
/// Confirm a weak-checksum bucket hit against strong checksums starting at `lo`.
fn confirm_signature_match(
  index : SignatureIndex,
  lo : Int32,
  window : BytesView,
  weak : UInt32,
  work : MatchWork,
) -> BlockMatch? raise SyncError {
  let length = window.length()
  work.spend(1L + length.to_int64()) // digest setup + actual input bytes, ONCE
  let digest = strong_sum(window, index.signature.strong_sum_len)
  for pos in lo..<index.sorted_weaks.length() {
    work.spend(1L) // candidate visit / group-end probe and bounded metadata work
    if index.sorted_weaks[pos] != weak {
      break
    }
    let record = index.signature.records[index.order[pos]]
    work.spend(index.signature.strong_sum_len.to_int64()) // full comparison precharge
    if record.strong_sum == digest {
      let offset = checked_block_offset(
        record.block_index.to_uint64(),
        index.signature.block_len.to_uint64(),
      )
      guard offset == record.nominal_offset else { raise InvalidSignature }
      let _ = checked_match_end(offset, length.to_uint64())
      return Some({
        record_index: record.block_index,
        nominal_offset: offset,
        length,
      })
    }
  }
  None
}

///|
/// Supplied weak sum comes from the rolling scanner; slices input[start:start+length]
/// and computes strong digest only after an O(1) open-addressed bucket hit.
fn match_signature_at(
  index : SignatureIndex,
  input : BytesView,
  start : Int32,
  length : Int32,
  weak : UInt32,
  work : MatchWork,
) -> BlockMatch? raise SyncError {
  if length == 0 {
    return None
  }
  guard start >= 0 &&
    length <= index.signature.block_len &&
    length <= input.length() - start else {
    raise InvalidOptions("window_len")
  }
  match match_signature_weak(index, weak, work) {
    None => None
    Some(lo) =>
      confirm_signature_match(
        index,
        lo,
        input[start:start + length],
        weak,
        work,
      )
  }
}

///|
/// Supplied weak sum comes from the rolling scanner; only this window is hashed.
#warnings("-unused_value")
fn match_signature_window(
  index : SignatureIndex,
  window : BytesView,
  weak : UInt32,
  work : MatchWork,
) -> BlockMatch? raise SyncError {
  match_signature_at(index, window, 0, window.length(), weak, work)
}
