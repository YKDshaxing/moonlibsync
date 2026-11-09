// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Validated RK+BLAKE2 signature metadata. The wire format does not encode
/// actual basis length, final-block length, or a whole-file identity digest.
pub(all) struct SignatureSummary {
  magic : UInt32
  block_len : Int64
  strong_sum_len : Int64
  record_count : Int64
  signature_bytes : Int64
}

///|
/// Exact data-instruction statistics; END is excluded. Contains no input views
/// or command storage. Format validity alone does not validate COPY ranges.
pub(all) struct DeltaSummary {
  delta_bytes : Int64
  instruction_count : Int64
  literal_commands : Int64
  copy_commands : Int64
  literal_bytes : Int64
  copy_bytes : Int64
  output_bytes : Int64
}

///|
/// Length-only preflight result, not proof of basis identity or output content.
pub(all) struct PatchCheck {
  basis_bytes : Int64
  summary : DeltaSummary
}

///|
/// Inspect a complete signature under Limits, with the same validation order
/// as delta's signature parser. No hashing or basis reconstruction is performed.
/// Parsing allocates bounded records/digest copies; the result retains none.
pub fn inspect_signature(
  signature_bytes : Bytes,
  limits : Limits,
) -> SignatureSummary raise SyncError {
  let sig = parse_signature(signature_bytes, limits)
  {
    magic: sig.magic,
    block_len: sig.block_len.to_int64(),
    strong_sum_len: sig.strong_sum_len.to_int64(),
    record_count: sig.records.length().to_int64(),
    signature_bytes: signature_bytes.length().to_int64(),
  }
}

///|
/// Only called after complete parsing. Counts cannot exceed the bounded Int32
/// command-array length; byte sums are checked before addition in UInt64.
fn summarize_delta(
  input_length : Int64,
  commands : ArrayView[DeltaCommand],
  limits : Limits,
) -> DeltaSummary raise SyncError {
  let mut literal_commands = 0L
  let mut copy_commands = 0L
  let mut literal_bytes = 0UL
  let mut copy_bytes = 0UL
  let maximum = limits.max_output_bytes.reinterpret_as_uint64()
  let mut output_bytes = 0UL
  for command in commands {
    let length = match command {
      Literal(data) => {
        literal_commands = literal_commands + 1L
        literal_bytes = delta_add_output(
          literal_bytes,
          data.length().to_uint64(),
          maximum,
        )
        data.length().to_uint64()
      }
      Copy(_, length) => {
        copy_commands = copy_commands + 1L
        copy_bytes = delta_add_output(copy_bytes, length, maximum)
        length
      }
    }
    output_bytes = delta_add_output(output_bytes, length, maximum)
  }
  // All byte totals <= validated max_output_bytes <= Int32.MAX; no narrowing.
  {
    delta_bytes: input_length,
    instruction_count: commands.length().to_int64(),
    literal_commands,
    copy_commands,
    literal_bytes: literal_bytes.reinterpret_as_int64(),
    copy_bytes: copy_bytes.reinterpret_as_int64(),
    output_bytes: output_bytes.reinterpret_as_int64(),
  }
}

///|
/// Validate the entire standard delta, including strict END and budgets, then
/// report exact statistics. High UInt64 COPY offsets are structurally valid.
/// Allocates bounded parsed metadata, never a recovered-output buffer.
pub fn inspect_delta(
  delta_bytes : Bytes,
  limits : Limits,
) -> DeltaSummary raise SyncError {
  let commands = parse_delta(delta_bytes, limits)
  summarize_delta(delta_bytes.length().to_int64(), commands, limits)
}

///|
/// Validate Limits, nonnegative basis_len, basis budget, complete delta, then
/// every COPY range and final output length, using patch's actual preflight.
/// Does not read basis bytes, allocate a virtual basis or recover output.
/// Passing only proves format/length bounds; it does not authenticate content.
pub fn check_patch(
  basis_len : Int64,
  delta_bytes : Bytes,
  limits : Limits,
) -> PatchCheck raise SyncError {
  limits.validate()
  guard basis_len >= 0L else { raise InvalidOptions("basis_len") }
  guard basis_len <= limits.max_old_bytes else { raise LimitExceeded }
  let commands = parse_delta(delta_bytes, limits)
  let _ = patch_size(basis_len.reinterpret_as_uint64(), commands, limits)
  {
    basis_bytes: basis_len,
    summary: summarize_delta(delta_bytes.length().to_int64(), commands, limits),
  }
}
