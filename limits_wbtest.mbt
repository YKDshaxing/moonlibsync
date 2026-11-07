// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "default limits are valid and preserve the initial policy" {
  let limits = Limits::default()
  limits.validate()
  assert_eq(limits.max_old_bytes, 64L * 1024L * 1024L)
  assert_eq(limits.max_new_bytes, limits.max_old_bytes)
  assert_eq(limits.max_signature_bytes, 16L * 1024L * 1024L)
  assert_eq(limits.max_signature_records, 1000000L)
  assert_eq(limits.max_block_bytes, 1024L * 1024L)
  assert_eq(limits.max_delta_bytes, 80L * 1024L * 1024L)
  assert_eq(limits.max_output_bytes, limits.max_old_bytes)
  assert_eq(limits.max_instructions, 1000000L)
  assert_eq(limits.max_match_work, 256L * 1024L * 1024L)
}

///|
fn with_field(name : String, value : Int64) -> Limits {
  let d = Limits::default()
  match name {
    "max_old_bytes" => { ..d, max_old_bytes: value, }
    "max_new_bytes" => { ..d, max_new_bytes: value, }
    "max_signature_bytes" => { ..d, max_signature_bytes: value, }
    "max_signature_records" => { ..d, max_signature_records: value, }
    "max_block_bytes" => { ..d, max_block_bytes: value, }
    "max_delta_bytes" => { ..d, max_delta_bytes: value, }
    "max_output_bytes" => { ..d, max_output_bytes: value, }
    "max_instructions" => { ..d, max_instructions: value, }
    "max_match_work" => { ..d, max_match_work: value, }
    _ => abort("unknown test field")
  }
}

///|
test "every limits field accepts boundaries and rejects out of range values" {
  let fields = [
    "max_old_bytes", "max_new_bytes", "max_signature_bytes", "max_signature_records",
    "max_block_bytes", "max_delta_bytes", "max_output_bytes", "max_instructions",
    "max_match_work",
  ]
  for name in fields {
    for value in [1L, 2147483647L] {
      with_field(name, value).validate()
    }
    if name != "max_block_bytes" {
      with_field(name, 0L).validate()
    }
    for value in [-1L, -9223372036854775808L, 2147483648L, 9223372036854775807L] {
      let result = Ok(with_field(name, value).validate()) catch { e => Err(e) }
      match result {
        Err(InvalidOptions(field)) => assert_eq(field, name)
        _ => fail("expected InvalidOptions for \{name} at \{value}")
      }
    }
  }
}

///|
test "block bytes must be positive" {
  let result = Ok(with_field("max_block_bytes", 0L).validate()) catch {
    e => Err(e)
  }
  match result {
    Err(InvalidOptions(field)) => assert_eq(field, "max_block_bytes")
    _ => fail("expected zero block length to be rejected")
  }
}
