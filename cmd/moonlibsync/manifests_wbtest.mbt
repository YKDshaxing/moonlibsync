// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "cli manifest parser accepts command paths separator and literal dash" {
  for
    args in [
      ["basis-info", "--", "--old", "-", "out"],
      ["make-manifest", "info", "sig", "new", "delta", "out"],
      ["patch-verified", "old", "delta", "manifest", "out"],
    ] {
    let plan = parse_plan(args)
    assert_eq(
      plan.inputs.length(),
      args.length() - (if args[1] == "--" { 3 } else { 2 }),
    )
  }
}

///|
async test "cli sync failure cleans owned temporary and permits publication reuse" {
  cli_test_scope(dir => {
    let temp = dir + "/temp"
    let out = dir + "/out"
    expect_file_failure(
      () => {
        publish_at(temp, out, b"abc", syncer=_ => {
          raise FileFailure("controlled sync failure")
        })
      },
      "controlled sync failure",
    )
    assert_true(!entry_exists(temp) && !entry_exists(out))
    publish_at(temp, out, b"abc")
    assert_eq(bounded_read(out, 3L), b"abc")
  })
}

///|
async test "cli result digest failure never invokes publisher then normal call succeeds" {
  cli_test_scope(dir => {
    let d = @lib.Limits::default()
    let old = dir + "/old"
    let delta = dir + "/delta"
    let manifest = dir + "/manifest"
    let out = dir + "/out"
    let sig = @lib.signature(b"abc", @lib.SignatureOptions::default(), d)
    let info = @lib.create_basis_info(b"abc", sig, d)
    let bytes = b"\x72\x73\x02\x36\x03xyz\x00"
    @fs.write_binary(old, b"abc", create_mode=CreateNew)
    @fs.write_binary(delta, bytes, create_mode=CreateNew)
    let bad = @lib.create_update_manifest(info, sig, b"abc", bytes, d)
    @fs.write_binary(
      manifest,
      @lib.encode_update_manifest(bad, d),
      create_mode=CreateNew,
    )
    let plan = parse_plan(["patch-verified", old, delta, manifest, out])
    let mut calls = 0
    expect_file_failure(
      () => {
        execute_manifest_write(plan, out, publisher=(_, _) => calls = calls + 1)
      },
      "result_sha256",
    )
    assert_eq(calls, 0)
    assert_true(!entry_exists(out))
    assert_eq(bounded_read(old, 3L), b"abc")
    let good = @lib.create_update_manifest(info, sig, b"xyz", bytes, d)
    @fs.write_binary(
      manifest,
      @lib.encode_update_manifest(good, d),
      create_mode=TruncateExisting,
    )
    execute_manifest_write(plan, out, publisher=(_, data) => {
      assert_eq(data, b"xyz")
      calls = calls + 1
    })
    assert_eq(calls, 1)
    execute_manifest_write(plan, out)
    assert_eq(bounded_read(out, 3L), b"xyz")
  })
}
