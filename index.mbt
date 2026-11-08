// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Only record ordinals are sorted; digest bytes remain in the parsed signature.
#warnings("-unused_field")
priv struct SignatureIndex {
  signature : Signature
  order : Array[Int32]
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
/// Metered bottom-up merge sort, with no unmetered hash collision path.
#warnings("-unused_value")
fn build_signature_index(
  sig : Signature,
  work : MatchWork,
) -> SignatureIndex raise SyncError {
  let n = sig.records.length()
  // n <= Int32.MAX; this Int64 multiplication cannot overflow. Charge for
  // one record visit and two index slots per record BEFORE either allocation.
  work.spend(n.to_int64() * 3L)
  let mut source = Array::makei(n, i => i)
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
  { signature: sig, order: source, }
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
/// Supplied weak sum comes from the rolling scanner; only this window is hashed.
#warnings("-unused_value")
fn match_signature_window(
  index : SignatureIndex,
  window : BytesView,
  weak : UInt32,
  work : MatchWork,
) -> BlockMatch? raise SyncError {
  let length = window.length()
  if length == 0 {
    return None
  }
  guard length <= index.signature.block_len else {
    raise InvalidOptions("window_len")
  }
  let mut lo = 0
  let mut hi = index.order.length()
  while lo < hi {
    work.spend(1L) // binary probe before accessing the record
    let mid = lo + (hi - lo) / 2
    if index.signature.records[index.order[mid]].weak_sum < weak {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo == index.order.length() {
    return None
  }
  work.spend(1L) // group presence check; misses do not incur digest charges
  if index.signature.records[index.order[lo]].weak_sum != weak {
    return None
  }
  work.spend(1L + length.to_int64()) // digest setup + actual input bytes, ONCE
  let digest = strong_sum(window, index.signature.strong_sum_len)
  for pos in lo..<index.order.length() {
    work.spend(1L) // candidate visit / group-end probe and bounded metadata work
    let record = index.signature.records[index.order[pos]]
    if record.weak_sum != weak {
      break
    }
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
