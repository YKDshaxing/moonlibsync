// SPDX-License-Identifier: LGPL-2.1-or-later
// Finite stage B public-API adapter; not a product command or timing tool.

///|
async fn run(args : Array[String]) -> Unit {
  let d = @lib.Limits::default()
  let sig = @fs.read_binary(args[2])
  let new = @fs.read_binary(args[3])
  if args[1] == "work-error" {
    let _ = @lib.plan_update(sig, new, @lib.UpdateOptions::default(), {
      ..d,
      max_match_work: 0L,
    })
    abort("WORK_ERROR_NOT_REJECTED")
  }
  let info = @lib.parse_basis_info(@fs.read_binary(args[4]), d)
  let options : @lib.UpdateOptions = {
    min_savings_bytes: @string.parse_int64(args[6]),
  }
  let candidate = if args[1] == "prepared" {
    @lib.prepare_signature(sig, d).delta(new, d)
  } else {
    @lib.delta(sig, new, d)
  }
  let manifest = @lib.create_transfer_manifest(
    info, sig, new, candidate, options, d,
  )
  let payload = match manifest {
    @lib.TransferManifest::Delta(_) => candidate
    @lib.TransferManifest::Full(_, _) => new
  }
  let plan = @lib.plan_update(sig, new, options, d)
  if args[1] != "prepared" {
    assert_eq(plan.decision.delta_bytes, candidate.length().to_int64())
    assert_eq(plan.decision.payload_bytes, payload.length().to_int64())
  }
  @fs.write_binary(args[5] + "/candidate", candidate, create_mode=CreateNew)
  @fs.write_binary(args[5] + "/payload", payload, create_mode=CreateNew)
  @fs.write_binary(
    args[5] + "/manifest",
    @lib.encode_transfer_manifest(manifest, d),
    create_mode=CreateNew,
  )
  println("STAGE_B_GENERATED")
}

///|
async fn main {
  run(@env.args()) catch {
    error => {
      println("STAGE_B_API_FAILURE \{error}")
      @env.exit(1)
    }
  }
}
