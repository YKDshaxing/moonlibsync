// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "cli transfer options preserve separator and exact nonnegative Int64" {
  let plan = parse_plan([
    "make-transfer-manifest", "info", "sig", "new", "delta", "out", "--min-savings",
    "9223372036854775807",
  ])
  assert_eq(plan.min_savings, 9223372036854775807L)
  let apply = parse_plan([
    "apply-update", "--basis", "old", "--", "--payload", "-", "out",
  ])
  assert_eq(apply.basis_path, Some("old"))
  assert_eq(apply.inputs[0], "--payload")
}

///|
async test "cli transfer invalid payload never invokes publisher and normal call reuses path" {
  cli_test_scope(dir => {
    let d = @lib.Limits::default()
    let sig = @lib.signature(b"abc", @lib.SignatureOptions::default(), d)
    let info = @lib.create_basis_info(b"abc", sig, d)
    let candidate = @lib.delta(sig, b"xyz", d)
    let m = @lib.create_transfer_manifest(
      info,
      sig,
      b"xyz",
      candidate,
      @lib.UpdateOptions::default(),
      d,
    )
    let manifest = dir + "/manifest"
    let payload = dir + "/payload"
    let out = dir + "/out"
    @fs.write_binary(
      manifest,
      @lib.encode_transfer_manifest(m, d),
      create_mode=CreateNew,
    )
    @fs.write_binary(payload, b"bad", create_mode=CreateNew)
    let plan = parse_plan(["apply-update", payload, manifest, out])
    let mut calls = 0
    expect_file_failure(
      () => {
        execute_transfer_write(plan, out, publisher=(_, _) => calls = calls + 1)
      },
      "payload_sha256",
    )
    assert_eq(calls, 0)
    assert_true(!entry_exists(out))
    @fs.write_binary(payload, b"xyz", create_mode=TruncateExisting)
    execute_transfer_write(plan, out)
    assert_eq(bounded_read(out, 3L), b"xyz")
  })
}
