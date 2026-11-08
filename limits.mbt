// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// One upper operation owns this budget; helpers never replenish it.
#warnings("-unused_field")
priv struct MatchWork {
  mut remaining : Int64
}

///|
/// Existing max_match_work range/default is unchanged.
#warnings("-unused_value")
fn MatchWork::new(limits : Limits) -> MatchWork raise SyncError {
  limits.validate()
  { remaining: limits.max_match_work, }
}

///|
/// Charge before work; failed charges do not refund earlier successful work.
fn MatchWork::spend(self : MatchWork, amount : Int64) -> Unit raise SyncError {
  guard amount >= 0L else { raise InvalidOptions("match_work_charge") }
  guard amount <= self.remaining else { raise LimitExceeded }
  self.remaining = self.remaining - amount
}

///|
/// Signature parsing enforces byte, record and block limits. Generation also
/// enforces the old-file budget. Internal delta codecs enforce delta bytes,
/// data instructions and estimated output. Patch additionally enforces the basis
/// budget and COPY ranges before recovery allocation. Delta generation enforces
/// new/output bytes and shares one index/rolling-scan/instruction work budget.
/// Byte fields count bytes; records and instructions count items. Work units
/// meter index/matching, scanning and command-buffer growth (logical units,
/// not total CPU/heap). See docs/resources.md for phase-specific checks, live
/// structures and conversion copies. Inputs already exist before these checks.
/// Int64 fields are validated against the common signed 32-bit collection ceiling.
pub(all) struct Limits {
  max_old_bytes : Int64
  max_new_bytes : Int64
  max_signature_bytes : Int64
  max_signature_records : Int64
  max_block_bytes : Int64
  max_delta_bytes : Int64
  max_output_bytes : Int64
  max_instructions : Int64
  max_match_work : Int64
}

///|
/// Signature, index/matching, delta generation/codecs and patch enforce relevant budgets.
pub fn Limits::default() -> Limits {
  {
    max_old_bytes: 67108864L,
    max_new_bytes: 67108864L,
    max_signature_bytes: 16777216L,
    max_signature_records: 1000000L,
    max_block_bytes: 1048576L,
    max_delta_bytes: 83886080L,
    max_output_bytes: 67108864L,
    max_instructions: 1000000L,
    max_match_work: 268435456L,
  }
}

///|
fn validate_limit(
  name : String,
  value : Int64,
  minimum : Int64,
) -> Unit raise SyncError {
  if value < minimum || value > 2147483647L {
    raise InvalidOptions(name)
  }
}

///|
/// All fields accept 0..2^31-1, except block bytes which accept 1..2^31-1.
/// This validates every field on every entry, including fields unused by that
/// operation. Phase-specific relationships are enforced by the relevant plans.
pub fn Limits::validate(self : Limits) -> Unit raise SyncError {
  validate_limit("max_old_bytes", self.max_old_bytes, 0L)
  validate_limit("max_new_bytes", self.max_new_bytes, 0L)
  validate_limit("max_signature_bytes", self.max_signature_bytes, 0L)
  validate_limit("max_signature_records", self.max_signature_records, 0L)
  validate_limit("max_block_bytes", self.max_block_bytes, 1L)
  validate_limit("max_delta_bytes", self.max_delta_bytes, 0L)
  validate_limit("max_output_bytes", self.max_output_bytes, 0L)
  validate_limit("max_instructions", self.max_instructions, 0L)
  validate_limit("max_match_work", self.max_match_work, 0L)
}
