// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Called after full delta parsing. Prove all COPY spans in UInt64 before
/// narrowing any parameter or allocating the recovery buffer.
fn patch_size(
  basis_length : UInt64,
  commands : ArrayView[DeltaCommand],
  limits : Limits,
) -> Int32 raise SyncError {
  let mut total = 0UL
  for command in commands {
    let length = match command {
      Literal(data) => data.length().to_uint64()
      Copy(offset, length) => {
        guard offset <= basis_length && length <= basis_length - offset else {
          raise CopyOutOfBounds
        }
        length
      }
    }
    total = delta_add_output(
      total,
      length,
      limits.max_output_bytes.reinterpret_as_uint64(),
    )
  }
  checked_index(total)
}

///|
/// No input mutation, incremental concatenation, shared state or partial return.
fn apply_patch_bytes(
  basis : Bytes,
  delta_bytes : Bytes,
  limits : Limits,
) -> Bytes raise SyncError {
  limits.validate()
  guard basis.length().to_int64() <= limits.max_old_bytes else {
    raise LimitExceeded
  }
  let commands = parse_delta(delta_bytes, limits)
  let size = patch_size(basis.length().to_uint64(), commands, limits)
  execute_patch_commands(basis, commands, size)
}

///|
/// Inputs and exact size have already passed complete parsing and preflight.
fn execute_patch_commands(
  basis : Bytes,
  commands : ArrayView[DeltaCommand],
  size : Int32,
) -> Bytes {
  let out = FixedArray::make(size, b'\x00')
  let mut cursor = 0
  for command in commands {
    let source = match command {
      Literal(data) => data
      Copy(offset, length) => {
        // patch_size proved offset <= basis.length and length <= remaining.
        // Both fit Int32; this bounded addition is <= basis.length.
        let start = offset.to_int()
        basis[start:start + length.to_int()]
      }
    }
    // Preflight proved cursor + source.length <= the final checked size.
    for i in 0..<source.length() {
      out[cursor + i] = source[i]
    }
    cursor = cursor + source.length()
  }
  Bytes::from_array(out[:])
}
