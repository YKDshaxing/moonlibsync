// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Options controlling HTTP Range coalescing for client-pull incremental sync.
pub(all) struct RangeFetchOptions {
  merge_gap_bytes : Int64
  max_ranges : Int64
}

///|
/// Default range-fetch options: coalesce gaps up to 4 KiB, allow up to 256 ranges.
pub fn RangeFetchOptions::default() -> RangeFetchOptions {
  { merge_gap_bytes: 4096L, max_ranges: 256L, }
}

///|
/// Half-open byte interval `[start, start + length)` inside a remote target file.
#derive(Eq, Debug)
pub(all) struct ByteRange {
  start : Int64
  length : Int64
}

///|
/// Format an RFC 9110 single-range HTTP `Range` header value (`bytes=START-END`).
/// Returns `""` if the range is invalid (`start < 0`, `length <= 0`, or end overflows `Int64`).
pub fn ByteRange::http_range_spec(self : ByteRange) -> String {
  if self.start < 0L ||
    self.length <= 0L ||
    self.length - 1L > 9223372036854775807L - self.start {
    return ""
  }
  let end = self.start + (self.length - 1L)
  "bytes=\{self.start}-\{end}"
}

///|
/// Reconstruction operation in a `RangeFetchPlan`.
/// - `CopyLocal(basis_offset, length)` copies `length` bytes from local `basis`.
/// - `FetchRemote(remote_offset, length)` copies `length` bytes from fetched HTTP ranges.
#derive(Eq, Debug)
pub(all) enum RangePlanOp {
  CopyLocal(Int64, Int64)
  FetchRemote(Int64, Int64)
}

///|
/// Deterministic client-pull incremental fetch plan derived from a remote
/// librsync signature, target file length, and local basis bytes.
pub(all) struct RangeFetchPlan {
  target_length : Int64
  block_len : Int32
  profile : SignatureProfile
  ops : Array[RangePlanOp]
  ranges : Array[ByteRange]
  reused_bytes : Int64
  fetch_bytes : Int64
  request_bytes : Int64
}

///|
fn range_weak_digest(magic : UInt32, input : BytesView) -> UInt32 {
  if magic == 0x72730137U {
    rollsum_digest(input)
  } else {
    rabinkarp_digest(input)
  }
}

///|
fn range_profile_for_magic(magic : UInt32) -> SignatureProfile {
  if magic == 0x72730137U {
    SignatureProfile::RollsumBlake2
  } else {
    SignatureProfile::RkBlake2
  }
}

///|
fn range_profile_label(profile : SignatureProfile) -> String {
  match profile {
    RkBlake2 => "rk-blake2"
    RollsumBlake2 => "rollsum-blake2"
  }
}

///|
/// Try matching the short trailing target block at a single basis offset.
fn try_match_short_tail_at(
  basis : Bytes,
  pos : Int32,
  tail_len : Int32,
  magic : UInt32,
  strong_sum_len : Int32,
  tail_rec : SignatureRecord,
  work : MatchWork,
) -> Bool raise SyncError {
  work.spend(1L + tail_len.to_int64())
  let window = basis[pos:pos + tail_len]
  let w = range_weak_digest(magic, window)
  if w != tail_rec.weak_sum {
    return false
  }
  work.spend(1L + tail_len.to_int64() + strong_sum_len.to_int64())
  strong_sum(window, strong_sum_len) == tail_rec.strong_sum
}

///|
/// Compute a deterministic client-pull HTTP Range fetch plan from a standard
/// librsync signature (`0x72730147` RK+BLAKE2 or `0x72730137` Rollsum+BLAKE2),
/// the remote `target_length`, and local `basis` bytes.
pub fn plan_range_fetch(
  target_sig : Bytes,
  target_length : Int64,
  basis : Bytes,
  options : RangeFetchOptions,
  limits : Limits,
) -> RangeFetchPlan raise SyncError {
  limits.validate()
  guard options.merge_gap_bytes >= 0L else {
    raise InvalidOptions("merge_gap_bytes")
  }
  guard options.max_ranges >= 1L && options.max_ranges <= 65536L else {
    raise InvalidOptions("max_ranges")
  }
  guard target_length >= 0L else { raise InvalidOptions("target_length") }
  guard target_length <= limits.max_new_bytes &&
    target_length <= limits.max_output_bytes else {
    raise LimitExceeded
  }
  guard basis.length().to_int64() <= limits.max_old_bytes else {
    raise LimitExceeded
  }
  let sig = parse_signature(target_sig, limits)
  let profile = range_profile_for_magic(sig.magic)
  let block_len = sig.block_len
  let block_len_i64 = block_len.to_int64()
  let expected_records : Int64 = if target_length == 0L {
    0L
  } else {
    (target_length - 1L) / block_len_i64 + 1L
  }
  guard sig.records.length().to_int64() == expected_records else {
    raise InvalidSignature
  }
  if target_length == 0L {
    return {
      target_length: 0L,
      block_len,
      profile,
      ops: [],
      ranges: [],
      reused_bytes: 0L,
      fetch_bytes: 0L,
      request_bytes: 0L,
    }
  }
  let work = MatchWork::new(limits)
  let num_blocks = sig.records.length()
  let tail_rem = (target_length % block_len_i64).to_int()
  let has_short_tail = tail_rem > 0
  let full_block_count = if has_short_tail {
    num_blocks - 1
  } else {
    num_blocks
  }
  let matched_basis_off = FixedArray::make(num_blocks, -1L)
  let basis_len = basis.length()

  // Step 1: Index and scan all full-length target blocks against `basis`.
  if full_block_count > 0 && basis_len >= block_len {
    let full_sig : Signature = if !has_short_tail {
      sig
    } else {
      let recs : Array[SignatureRecord] = Array(capacity=full_block_count)
      for i in 0..<full_block_count {
        recs.push(sig.records[i])
      }
      {
        magic: sig.magic,
        block_len: sig.block_len,
        strong_sum_len: sig.strong_sum_len,
        records: recs,
      }
    }
    let full_index = build_signature_index(full_sig, work)
    let mut remaining_full = full_block_count
    let mut pos = 0
    let mut weak = RollingWeak::new_for_magic(sig.magic)
    work.spend(1L + block_len_i64)
    weak.update(basis[0:block_len])
    let last_start = basis_len - block_len
    while pos <= last_start && remaining_full > 0 {
      work.spend(1L)
      let w = weak.digest()
      let mut any_matched = false
      match match_signature_weak(full_index, w, work) {
        Some(lo) => {
          let mut has_unmatched = false
          for idx in lo..<full_index.sorted_weaks.length() {
            work.spend(1L)
            if full_index.sorted_weaks[idx] != w {
              break
            }
            let blk = full_index.order[idx]
            if matched_basis_off[blk] < 0L {
              has_unmatched = true
              break
            }
          }
          if has_unmatched {
            work.spend(1L + block_len_i64)
            let digest = strong_sum(
              basis[pos:pos + block_len],
              sig.strong_sum_len,
            )
            for idx in lo..<full_index.sorted_weaks.length() {
              work.spend(1L)
              if full_index.sorted_weaks[idx] != w {
                break
              }
              let blk = full_index.order[idx]
              if matched_basis_off[blk] < 0L {
                work.spend(sig.strong_sum_len.to_int64())
                if full_sig.records[blk].strong_sum == digest {
                  matched_basis_off[blk] = pos.to_int64()
                  remaining_full = remaining_full - 1
                  any_matched = true
                }
              }
            }
          }
        }
        None => ()
      }
      if any_matched {
        pos = pos + block_len
        if pos <= last_start && remaining_full > 0 {
          weak = RollingWeak::new_for_magic(sig.magic)
          work.spend(1L + block_len_i64)
          weak.update(basis[pos:pos + block_len])
        }
      } else {
        if pos < last_start {
          work.spend(3L)
          weak.rotate(basis[pos], basis[pos + block_len])
        }
        pos = pos + 1
      }
    }
  }

  // Step 2: Check short trailing target block (if any).
  if has_short_tail && basis_len >= tail_rem {
    let tail_idx = num_blocks - 1
    let tail_rec = sig.records[tail_idx]
    let end_pos = basis_len - tail_rem
    if try_match_short_tail_at(
        basis,
        end_pos,
        tail_rem,
        sig.magic,
        sig.strong_sum_len,
        tail_rec,
        work,
      ) {
      matched_basis_off[tail_idx] = end_pos.to_int64()
    } else {
      // Also probe the aligned target tail offset in O(tail_rem) before rolling scan.
      let aligned_off_i64 = tail_idx.to_int64() * block_len_i64
      if aligned_off_i64 < end_pos.to_int64() {
        let aligned_pos = aligned_off_i64.to_int()
        if try_match_short_tail_at(
            basis,
            aligned_pos,
            tail_rem,
            sig.magic,
            sig.strong_sum_len,
            tail_rec,
            work,
          ) {
          matched_basis_off[tail_idx] = aligned_off_i64
        }
      }
      // Rolling-hash scan for shifted short tails within bounded basis length.
      if matched_basis_off[tail_idx] < 0L && end_pos > 0 && basis_len <= 1048576 {
        let tail_weak = RollingWeak::new_for_magic(sig.magic)
        work.spend(1L + tail_rem.to_int64())
        tail_weak.update(basis[0:tail_rem])
        let mut p = 0
        while p < end_pos {
          work.spend(1L)
          if tail_weak.digest() == tail_rec.weak_sum {
            work.spend(1L + tail_rem.to_int64() + sig.strong_sum_len.to_int64())
            if strong_sum(basis[p:p + tail_rem], sig.strong_sum_len) ==
              tail_rec.strong_sum {
              matched_basis_off[tail_idx] = p.to_int64()
              break
            }
          }
          if p + 1 < end_pos {
            work.spend(3L)
            tail_weak.rotate(basis[p], basis[p + tail_rem])
          }
          p = p + 1
        }
      }
    }
  }

  // Step 3: Emit coalesced CopyLocal / FetchRemote operations covering [0, target_length).
  let ops : Array[RangePlanOp] = []
  let mut reused_bytes = 0L
  let mut fetch_bytes = 0L
  for k in 0..<num_blocks {
    let target_off = k.to_int64() * block_len_i64
    let blk_len : Int64 = if k == num_blocks - 1 && has_short_tail {
      tail_rem.to_int64()
    } else {
      block_len_i64
    }
    let b_off = matched_basis_off[k]
    if b_off >= 0L {
      reused_bytes = reused_bytes + blk_len
      let n = ops.length()
      if n > 0 {
        match ops[n - 1] {
          CopyLocal(prev_off, prev_len) if prev_off + prev_len == b_off =>
            ops[n - 1] = CopyLocal(prev_off, prev_len + blk_len)
          _ => ops.push(CopyLocal(b_off, blk_len))
        }
      } else {
        ops.push(CopyLocal(b_off, blk_len))
      }
    } else {
      fetch_bytes = fetch_bytes + blk_len
      let n = ops.length()
      if n > 0 {
        match ops[n - 1] {
          FetchRemote(prev_off, prev_len) if prev_off + prev_len == target_off =>
            ops[n - 1] = FetchRemote(prev_off, prev_len + blk_len)
          _ => ops.push(FetchRemote(target_off, blk_len))
        }
      } else {
        ops.push(FetchRemote(target_off, blk_len))
      }
    }
  }
  guard ops.length().to_int64() <= limits.max_instructions else {
    raise LimitExceeded
  }

  // Step 4: Coalesce FetchRemote spans separated by <= merge_gap_bytes into HTTP ranges.
  let ranges : Array[ByteRange] = []
  for op in ops {
    match op {
      FetchRemote(start, length) =>
        if ranges.length() > 0 {
          let last_idx = ranges.length() - 1
          let prev = ranges[last_idx]
          let prev_end = prev.start + prev.length
          let gap = start - prev_end
          if gap <= options.merge_gap_bytes {
            ranges[last_idx] = {
              start: prev.start,
              length: start + length - prev.start,
            }
          } else {
            guard ranges.length().to_int64() < options.max_ranges else {
              raise LimitExceeded
            }
            ranges.push({ start, length, })
          }
        } else {
          guard ranges.length().to_int64() < options.max_ranges else {
            raise LimitExceeded
          }
          ranges.push({ start, length, })
        }
      CopyLocal(_, _) => ()
    }
  }
  let mut request_bytes = 0L
  for r in ranges {
    request_bytes = request_bytes + r.length
  }
  {
    target_length,
    block_len,
    profile,
    ops,
    ranges,
    reused_bytes,
    fetch_bytes,
    request_bytes,
  }
}

///|
fn find_covering_range(
  ranges : Array[ByteRange],
  remote_offset : Int64,
  length : Int64,
) -> Int32? {
  let n = ranges.length()
  if n == 0 {
    return None
  }
  let mut lo = 0
  let mut hi = n
  while lo + 1 < hi {
    let mid = lo + (hi - lo) / 2
    if ranges[mid].start <= remote_offset {
      lo = mid
    } else {
      hi = mid
    }
  }
  let r = ranges[lo]
  if r.start <= remote_offset &&
    length <= r.length &&
    remote_offset - r.start <= r.length - length {
    Some(lo)
  } else {
    None
  }
}

///|
/// Reconstruct the target file bytes from local `basis`, a `RangeFetchPlan`,
/// and the corresponding `fetched_slices` returned for `plan.ranges`.
pub fn apply_range_fetch(
  basis : Bytes,
  plan : RangeFetchPlan,
  fetched_slices : Array[Bytes],
  limits : Limits,
) -> Bytes raise SyncError {
  limits.validate()
  let basis_len = basis.length().to_int64()
  guard basis_len <= limits.max_old_bytes else { raise LimitExceeded }
  guard plan.target_length >= 0L else { raise InvalidOptions("target_length") }
  guard plan.target_length <= limits.max_output_bytes else {
    raise LimitExceeded
  }
  guard plan.block_len >= 1 &&
    plan.block_len.to_int64() <= limits.max_block_bytes else {
    raise InvalidOptions("block_len")
  }
  guard plan.ops.length().to_int64() <= limits.max_instructions else {
    raise LimitExceeded
  }
  guard plan.ranges.length().to_int64() <= 65536L &&
    plan.ranges.length().to_int64() <= limits.max_instructions else {
    raise LimitExceeded
  }
  guard fetched_slices.length() == plan.ranges.length() else {
    raise InvalidOptions("fetched_slices")
  }
  let mut prev_end = 0L
  for i in 0..<plan.ranges.length() {
    let r = plan.ranges[i]
    guard r.start >= 0L && r.length > 0L else { raise InvalidOptions("range") }
    guard r.start <= plan.target_length &&
      r.length <= plan.target_length - r.start else {
      raise CopyOutOfBounds
    }
    guard i == 0 || prev_end <= r.start else { raise InvalidOptions("range") }
    guard fetched_slices[i].length().to_int64() == r.length else {
      raise InvalidOptions("fetched_slices")
    }
    prev_end = r.start + r.length
  }

  // Preflight every op and exact reconstructed length before allocating output.
  let resolved_range_idx : Array[Int32] = Array(capacity=plan.ops.length())
  let mut total_out = 0UL
  let target_u64 = plan.target_length.reinterpret_as_uint64()
  for op in plan.ops {
    match op {
      CopyLocal(b_off, len) => {
        guard b_off >= 0L && len > 0L else { raise CopyOutOfBounds }
        guard b_off <= basis_len && len <= basis_len - b_off else {
          raise CopyOutOfBounds
        }
        let len_u64 = len.reinterpret_as_uint64()
        guard len_u64 <= target_u64 - total_out else { raise InvalidDelta }
        total_out = total_out + len_u64
        resolved_range_idx.push(-1)
      }
      FetchRemote(r_off, len) => {
        guard r_off >= 0L && len > 0L else { raise CopyOutOfBounds }
        guard r_off <= plan.target_length && len <= plan.target_length - r_off else {
          raise CopyOutOfBounds
        }
        match find_covering_range(plan.ranges, r_off, len) {
          Some(idx) => resolved_range_idx.push(idx)
          None => raise CopyOutOfBounds
        }
        let len_u64 = len.reinterpret_as_uint64()
        guard len_u64 <= target_u64 - total_out else { raise InvalidDelta }
        total_out = total_out + len_u64
      }
    }
  }
  guard total_out == target_u64 else { raise InvalidDelta }

  let out_size = checked_index(target_u64)
  let out = FixedArray::make(out_size, b'\x00')
  let mut cursor = 0
  for i in 0..<plan.ops.length() {
    match plan.ops[i] {
      CopyLocal(b_off, len) => {
        let len_i32 = len.to_int()
        out.blit_from_bytes(cursor, basis, b_off.to_int(), len_i32)
        cursor = cursor + len_i32
      }
      FetchRemote(r_off, len) => {
        let range_idx = resolved_range_idx[i]
        let slice = fetched_slices[range_idx]
        let rel_off = (r_off - plan.ranges[range_idx].start).to_int()
        let len_i32 = len.to_int()
        out.blit_from_bytes(cursor, slice, rel_off, len_i32)
        cursor = cursor + len_i32
      }
    }
  }
  Bytes::from_array(out[:])
}

///|
/// Encode a `RangeFetchPlan` into deterministic canonical Schema 3 JSON.
pub fn encode_range_plan_json(plan : RangeFetchPlan) -> Bytes {
  let out = StringBuilder()
  out.write_string(
    "{\"schema\":3,\"kind\":\"moonlibsync-range-plan\",\"target_length\":\{plan.target_length},\"block_len\":\{plan.block_len},\"profile\":\"\{range_profile_label(plan.profile)}\",\"reused_bytes\":\{plan.reused_bytes},\"fetch_bytes\":\{plan.fetch_bytes},\"request_bytes\":\{plan.request_bytes},\"ranges\":[",
  )
  for i in 0..<plan.ranges.length() {
    if i > 0 {
      out.write_char(',')
    }
    let r = plan.ranges[i]
    out.write_string(
      "{\"start\":\{r.start},\"length\":\{r.length},\"http_range\":\"\{r.http_range_spec()}\"}",
    )
  }
  out.write_string("],\"ops\":[")
  for i in 0..<plan.ops.length() {
    if i > 0 {
      out.write_char(',')
    }
    match plan.ops[i] {
      CopyLocal(offset, length) =>
        out.write_string(
          "{\"op\":\"copy_local\",\"offset\":\{offset},\"length\":\{length}}",
        )
      FetchRemote(offset, length) =>
        out.write_string(
          "{\"op\":\"fetch_remote\",\"offset\":\{offset},\"length\":\{length}}",
        )
    }
  }
  out.write_string("]}\n")
  @utf8.encode(out.to_string())
}
