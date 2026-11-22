// SPDX-License-Identifier: LGPL-2.1-or-later

///|
test "cli inspect-manifest plan parsing separator and usage errors" {
  for
    args in [
      ["inspect-manifest", "m.json"],
      ["inspect-manifest", "--json", "m.json"],
      ["inspect-manifest", "m.json", "--json"],
    ] {
    let p = parse_plan(args)
    assert_eq(p.operation, "inspect-manifest")
    assert_eq(p.inputs, ["m.json"])
    match p.mode {
      Inspect(json) => assert_eq(json, args.length() == 3)
      WriteFile(_) | WriteDir(_) => abort("expected inspect mode")
    }
  }
  let sep = parse_plan(["inspect-manifest", "--json", "--", "--json"])
  assert_eq(sep.inputs, ["--json"])
  assert_true(sep.mode is Inspect(true))
  let dash = parse_plan(["inspect-manifest", "-"])
  assert_eq(dash.inputs, ["-"])
  assert_true(dash.mode is Inspect(false))
  for
    bad in [
      ["inspect-manifest"],
      ["inspect-manifest", "a", "b"],
      ["inspect-manifest", "--json", "a", "--json"],
      ["inspect-manifest", "a", "--sum-size", "1"],
      ["inspect-manifest", "a", "--min-savings", "0"],
    ] {
    let rejected = try {
      let _ = parse_plan(bad)
      false
    } catch {
      Usage(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "cli limit override flags and order independence" {
  let def = @lib.Limits::default()
  let plain = parse_plan(["delta", "sig", "new", "out"])
  assert_eq(plain.limits.max_old_bytes, def.max_old_bytes)
  assert_eq(plain.limits.max_block_bytes, def.max_block_bytes)
  assert_eq(plain.limits.max_match_work, def.max_match_work)
  let custom = parse_plan([
    "delta", "--max-old-bytes", "11", "--max-new-bytes", "12", "--max-signature-bytes",
    "13", "--max-signature-records", "14", "--max-block-bytes", "2097152", "--max-delta-bytes",
    "15", "--max-output-bytes", "16", "--max-instructions", "17", "--max-match-work",
    "18", "sig", "new", "out",
  ])
  assert_eq(custom.limits.max_old_bytes, 11L)
  assert_eq(custom.limits.max_new_bytes, 12L)
  assert_eq(custom.limits.max_signature_bytes, 13L)
  assert_eq(custom.limits.max_signature_records, 14L)
  assert_eq(custom.limits.max_block_bytes, 2097152L)
  assert_eq(custom.limits.max_delta_bytes, 15L)
  assert_eq(custom.limits.max_output_bytes, 16L)
  assert_eq(custom.limits.max_instructions, 17L)
  assert_eq(custom.limits.max_match_work, 18L)
  // Order independence between --block-size and --max-block-bytes
  let p1 = parse_plan([
    "signature", "old", "sig", "--block-size", "1048577", "--max-block-bytes", "2097152",
  ])
  let p2 = parse_plan([
    "signature", "old", "sig", "--max-block-bytes", "2097152", "--block-size", "1048577",
  ])
  assert_eq(p1.options.block_len, 1048577L)
  assert_eq(p2.options.block_len, 1048577L)
  assert_eq(p1.limits.max_block_bytes, 2097152L)
  assert_eq(p2.limits.max_block_bytes, 2097152L)
  for
    bad in [
      ["signature", "old", "sig", "--max-old-bytes"],
      ["signature", "old", "sig", "--max-old-bytes", "-1"],
      ["signature", "old", "sig", "--max-old-bytes", "2147483648"],
      ["signature", "old", "sig", "--max-block-bytes", "0"],
      [
        "signature", "old", "sig", "--max-old-bytes", "1", "--max-old-bytes", "2",
      ],
      ["signature", "old", "sig", "--block-size", "1048577"],
    ] {
    let rejected = try {
      let _ = parse_plan(bad)
      false
    } catch {
      Usage(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "cli parse_any_manifest and format_manifest across all schema 1 and schema 2 shapes" {
  let d = @lib.Limits::default()
  let old = Bytes::make(128, b'A') + Bytes::make(128, b'B')
  let sig = @lib.signature(old, { block_len: 32L, strong_sum_len: 16L, }, d)
  let info = @lib.create_basis_info(old, sig, d)
  let info_bytes = @lib.encode_basis_info(info, d)
  let parsed_info = parse_any_manifest(info_bytes, d)
  assert_true(parsed_info is Basis(_))
  let info_json = format_manifest(parsed_info, true)
  assert_true(info_json.contains("\"manifest_schema_version\":1"))
  assert_true(info_json.contains("\"kind\":\"moonlibsync-basis-info\""))
  assert_true(
    format_manifest(parsed_info, false).contains("manifest_schema_version: 1"),
  )
  let new_delta = Bytes::make(128, b'A') + b"XY" + Bytes::make(126, b'B')
  let delta_bytes = @lib.delta(sig, new_delta, d)
  let update = @lib.create_update_manifest(info, sig, new_delta, delta_bytes, d)
  let parsed_update = parse_any_manifest(
    @lib.encode_update_manifest(update, d),
    d,
  )
  assert_true(parsed_update is Update(_))
  let update_json = format_manifest(parsed_update, true)
  assert_true(update_json.contains("\"manifest_schema_version\":1"))
  assert_true(update_json.contains("\"kind\":\"librsync-delta\""))
  assert_true(update_json.contains("\"delta\":{"))
  let t_delta = @lib.create_transfer_manifest(
    info,
    sig,
    new_delta,
    delta_bytes,
    @lib.UpdateOptions::default(),
    d,
  )
  let parsed_t_delta = parse_any_manifest(
    @lib.encode_transfer_manifest(t_delta, d),
    d,
  )
  assert_true(parsed_t_delta is Transfer(Delta(_)))
  let t_delta_json = format_manifest(parsed_t_delta, true)
  assert_true(t_delta_json.contains("\"manifest_schema_version\":2"))
  assert_true(t_delta_json.contains("\"kind\":\"librsync-delta\""))
  assert_true(t_delta_json.contains("\"payload\":{"))
  let full_new = b"xyz"
  let full_cand = @lib.delta(sig, full_new, d)
  let t_full = @lib.create_transfer_manifest(
    info,
    sig,
    full_new,
    full_cand,
    @lib.UpdateOptions::default(),
    d,
  )
  let parsed_t_full = parse_any_manifest(
    @lib.encode_transfer_manifest(t_full, d),
    d,
  )
  assert_true(parsed_t_full is Transfer(Full(_, _)))
  let t_full_json = format_manifest(parsed_t_full, true)
  assert_true(t_full_json.contains("\"manifest_schema_version\":2"))
  assert_true(t_full_json.contains("\"kind\":\"full-file\""))
}

///|
test "cli parse_any_manifest error classification" {
  let d = @lib.Limits::default()
  let mut utf8_ok = false
  try {
    let _ = parse_any_manifest(b"\xff", d)
  } catch {
    @lib.ManifestError::InvalidUtf8 => utf8_ok = true
    _ => ()
  }
  assert_true(utf8_ok)
  let mut json_ok = false
  try {
    let _ = parse_any_manifest(
      b"{\"schema_version\":1,\"schema_version\":1}", d,
    )
  } catch {
    @lib.ManifestError::InvalidJson => json_ok = true
    _ => ()
  }
  assert_true(json_ok)
  let mut schema_ok = false
  try {
    let _ = parse_any_manifest(
      b"{\"schema_version\":3,\"kind\":\"unknown\"}", d,
    )
  } catch {
    @lib.ManifestError::InvalidSchema => schema_ok = true
    _ => ()
  }
  assert_true(schema_ok)
  let bad_hash = @lib.encode_basis_info(
    @lib.create_basis_info(
      b"abc",
      @lib.signature(b"abc", @lib.SignatureOptions::default(), d),
      d,
    ),
    d,
  )
  let info_tight : @lib.Limits = { ..d, max_old_bytes: 2L, }
  let mut limit_ok = false
  try {
    let _ = parse_any_manifest(bad_hash, info_tight)
  } catch {
    @lib.ManifestError::ResourceLimit("basis") => limit_ok = true
    _ => ()
  }
  assert_true(limit_ok)
  let bad_field_bytes = b"{\"schema_version\":1,\"kind\":\"moonlibsync-basis-info\",\"basis\":{\"byte_length\":\"3\",\"sha256\":\"bad\"},\"signature\":{\"byte_length\":\"12\",\"sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\"}}"
  let mut field_ok = false
  try {
    let _ = parse_any_manifest(bad_field_bytes, d)
  } catch {
    @lib.ManifestError::InvalidField("basis.sha256") => field_ok = true
    _ => ()
  }
  assert_true(field_ok)
}

///|
async test "cli inspect-manifest bounds check on real file and tight limits" {
  cli_test_scope(dir => {
    let d = @lib.Limits::default()
    let sig = @lib.signature(b"abc", @lib.SignatureOptions::default(), d)
    let info = @lib.create_basis_info(b"abc", sig, d)
    let manifest_path = dir + "/info.json"
    @fs.write_binary(
      manifest_path,
      @lib.encode_basis_info(info, d),
      create_mode=CreateNew,
    )
    let tight = parse_plan([
      "inspect-manifest", manifest_path, "--max-old-bytes", "2", "--json",
    ])
    expect_file_failure(() => execute_inspection(tight, true), "ResourceLimit")
    let oversize_path = dir + "/oversize.json"
    let big = Bytes::make(65537, b' ')
    @fs.write_binary(oversize_path, big, create_mode=CreateNew)
    let over = parse_plan(["inspect-manifest", oversize_path])
    expect_file_failure(
      () => execute_inspection(over, false),
      "ReadLimitExceeded",
    )
  })
}
