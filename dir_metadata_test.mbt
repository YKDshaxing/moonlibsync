// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn expect_meta_create_error(
  execs : Array[String],
  empties : Array[String],
  limits : @moonlibsync.DirLimits,
  expected : String,
) -> Unit raise {
  let actual = try {
    let _ = @moonlibsync.create_dir_metadata(execs, empties, limits)
    "success"
  } catch {
    @moonlibsync.ManifestError::InvalidField(f) => "InvalidField:" + f
    @moonlibsync.ManifestError::ResourceLimit(r) => "ResourceLimit:" + r
    @moonlibsync.ManifestError::Core(@moonlibsync.SyncError::InvalidOptions(f)) =>
      "InvalidOptions:" + f
    _ => "other"
  }
  assert_eq(actual, expected)
}

///|
fn expect_meta_parse_error(
  bytes : Bytes,
  limits : @moonlibsync.DirLimits,
  expected : String,
) -> Unit raise {
  let actual = try {
    let _ = @moonlibsync.parse_dir_metadata(bytes, limits)
    "success"
  } catch {
    @moonlibsync.ManifestError::InvalidUtf8 => "InvalidUtf8"
    @moonlibsync.ManifestError::InvalidJson => "InvalidJson"
    @moonlibsync.ManifestError::InvalidSchema => "InvalidSchema"
    @moonlibsync.ManifestError::InvalidField(f) => "InvalidField:" + f
    @moonlibsync.ManifestError::ResourceLimit(r) => "ResourceLimit:" + r
    _ => "other"
  }
  assert_eq(actual, expected)
}

///|
test "dir_metadata empty roundtrip deterministic sorting and JSON wire format" {
  let limits = @moonlibsync.DirLimits::default()

  let empty = @moonlibsync.DirMetadata::empty()
  let empty_json = @moonlibsync.encode_dir_metadata(empty, limits)
  assert_eq(
    @utf8.decode(empty_json),
    "{\"schema\":3,\"kind\":\"moonlibsync-dir-metadata\",\"executable_paths\":[],\"empty_dirs\":[]}\n",
  )
  assert_eq(@moonlibsync.parse_dir_metadata(empty_json, limits), empty)

  // Unsorted input becomes deterministically sorted in UTF-8 byte order.
  let meta = @moonlibsync.create_dir_metadata(
    ["scripts/z.sh", "bin/run", "a.sh"],
    ["var/empty/sub", "cache", "var/empty"],
    limits,
  )
  assert_eq(meta.executable_paths, ["a.sh", "bin/run", "scripts/z.sh"])
  assert_eq(meta.empty_dirs, ["cache", "var/empty", "var/empty/sub"])

  let encoded = @moonlibsync.encode_dir_metadata(meta, limits)
  assert_eq(@moonlibsync.encode_dir_metadata(meta, limits), encoded)
  assert_eq(
    @utf8.decode(encoded),
    "{\"schema\":3,\"kind\":\"moonlibsync-dir-metadata\",\"executable_paths\":[\"a.sh\",\"bin/run\",\"scripts/z.sh\"],\"empty_dirs\":[\"cache\",\"var/empty\",\"var/empty/sub\"]}\n",
  )
  let parsed = @moonlibsync.parse_dir_metadata(encoded, limits)
  assert_eq(parsed, meta)

  // Non-ASCII UTF-8 and JSON-escaped double-quote paths roundtrip cleanly.
  let unicode_meta = @moonlibsync.create_dir_metadata(
    ["脚本/运行.sh", "bin/a\"b.sh"],
    ["空目录/子目录", "空目录"],
    limits,
  )
  assert_eq(unicode_meta.executable_paths, ["bin/a\"b.sh", "脚本/运行.sh"])
  assert_eq(unicode_meta.empty_dirs, ["空目录", "空目录/子目录"])
  let unicode_encoded = @moonlibsync.encode_dir_metadata(unicode_meta, limits)
  assert_eq(
    @moonlibsync.parse_dir_metadata(unicode_encoded, limits),
    unicode_meta,
  )
}

///|
test "dir_metadata plan_dir_metadata chmod diffs and nested mkdir/rmdir ordering" {
  let limits = @moonlibsync.DirLimits::default()
  let basis = @moonlibsync.create_dir_metadata(
    ["bin/keep", "bin/old.sh", "scripts/drop"],
    ["old", "old/sub", "old/sub/deep", "stay", "z/leaf"],
    limits,
  )
  let target = @moonlibsync.create_dir_metadata(
    ["bin/keep", "bin/new.sh", "tools/cli"],
    ["a/b/c", "a", "a/b", "m", "stay", "m/n"],
    limits,
  )
  let plan = @moonlibsync.plan_dir_metadata(basis, target, limits)
  assert_eq(plan.chmod_exec, ["bin/new.sh", "tools/cli"])
  assert_eq(plan.chmod_nonexec, ["bin/old.sh", "scripts/drop"])
  // mkdir_empty MUST be shallowest-first (depth 1, then depth 2, then depth 3)
  assert_eq(plan.mkdir_empty, ["a", "m", "a/b", "m/n", "a/b/c"])
  // rmdir_empty MUST be deepest-first (depth 3, then depth 2, then depth 1)
  assert_eq(plan.rmdir_empty, ["old/sub/deep", "old/sub", "z/leaf", "old"])

  // Self-plan produces completely empty diff
  let self_plan = @moonlibsync.plan_dir_metadata(target, target, limits)
  assert_eq(self_plan, {
    chmod_exec: [],
    chmod_nonexec: [],
    mkdir_empty: [],
    rmdir_empty: [],
  })
}

///|
test "dir_metadata rejects traversal DOS reserved names case collisions and prefix collisions" {
  let limits = @moonlibsync.DirLimits::default()

  // Unsafe paths (traversal, absolute, backslash, colon, control chars, trailing dot/space)
  for
    bad in [
      "", "/abs", "dir/", "a//b", ".", "..", "a/../b", "a/./b", "a\\b", "C:file",
      "bad\u0000x", "line\nbreak", "trail.", "trail ",
    ] {
    expect_meta_create_error([bad], [], limits, "InvalidField:path")
    expect_meta_create_error([], [bad], limits, "InvalidField:path")
  }

  // Windows DOS reserved names
  for
    reserved in [
      "NUL", "CON", "con.sh", "sub/PRN", "AUX.txt", "COM1", "com9.bin", "LPT1", "dir/lpt9.dat",
    ] {
    expect_meta_create_error([reserved], [], limits, "InvalidField:path")
    expect_meta_create_error([], [reserved], limits, "InvalidField:path")
  }

  // Duplicates & ASCII case collisions inside executable_paths and empty_dirs
  expect_meta_create_error(
    ["bin/run", "bin/run"],
    [],
    limits,
    "InvalidField:path_collision",
  )
  expect_meta_create_error(
    ["bin/Run", "bin/run"],
    [],
    limits,
    "InvalidField:path_collision",
  )
  expect_meta_create_error(
    ["Bin/a", "bin/b"],
    [],
    limits,
    "InvalidField:path_collision",
  )
  expect_meta_create_error(
    [],
    ["tmp/a", "tmp/a"],
    limits,
    "InvalidField:path_collision",
  )
  expect_meta_create_error(
    [],
    ["Tmp/a", "tmp/a"],
    limits,
    "InvalidField:path_collision",
  )
  expect_meta_create_error(
    [],
    ["Dir/a", "dir/b"],
    limits,
    "InvalidField:path_collision",
  )
  expect_meta_create_error(
    [],
    ["Dir", "dir/sub"],
    limits,
    "InvalidField:path_collision",
  )

  // Prefix collisions between executable_paths and empty_dirs
  // 1) exact and case-folded same path
  expect_meta_create_error(
    ["foo"],
    ["foo"],
    limits,
    "InvalidField:path_collision",
  )
  expect_meta_create_error(
    ["foo/bar"],
    ["FOO/BAR"],
    limits,
    "InvalidField:path_collision",
  )
  // 2) executable file is ancestor of empty dir
  expect_meta_create_error(
    ["foo"],
    ["foo/sub"],
    limits,
    "InvalidField:path_collision",
  )
  expect_meta_create_error(
    ["FOO"],
    ["foo/sub"],
    limits,
    "InvalidField:path_collision",
  )
  // 3) empty dir is ancestor of executable file
  expect_meta_create_error(
    ["foo/run.sh"],
    ["foo"],
    limits,
    "InvalidField:path_collision",
  )
  expect_meta_create_error(
    ["FOO/run.sh"],
    ["foo"],
    limits,
    "InvalidField:path_collision",
  )
  // 4) shared parent directory case mismatch
  expect_meta_create_error(
    ["App/run.sh"],
    ["app/empty"],
    limits,
    "InvalidField:path_collision",
  )
  // 5) cross-tree case collision in plan_dir_metadata
  let b_case = @moonlibsync.create_dir_metadata(["Bin/tool"], [], limits)
  let t_case = @moonlibsync.create_dir_metadata(["bin/tool"], [], limits)
  let cross_err = try {
    let _ = @moonlibsync.plan_dir_metadata(b_case, t_case, limits)
    "success"
  } catch {
    @moonlibsync.ManifestError::InvalidField(f) => f
    _ => "other"
  }
  assert_eq(cross_err, "path_collision")
}

///|
test "dir_metadata rejects unknown JSON keys duplicate keys bad schema unsorted and limits" {
  let limits = @moonlibsync.DirLimits::default()

  // Unknown key
  expect_meta_parse_error(
    @utf8.encode(
      "{\"schema\":3,\"kind\":\"moonlibsync-dir-metadata\",\"executable_paths\":[],\"empty_dirs\":[],\"extra\":1}",
    ),
    limits,
    "InvalidSchema",
  )
  // Missing key
  expect_meta_parse_error(
    @utf8.encode(
      "{\"schema\":3,\"kind\":\"moonlibsync-dir-metadata\",\"executable_paths\":[]}",
    ),
    limits,
    "InvalidSchema",
  )
  // Duplicate key
  expect_meta_parse_error(
    @utf8.encode(
      "{\"schema\":3,\"schema\":3,\"kind\":\"moonlibsync-dir-metadata\",\"executable_paths\":[],\"empty_dirs\":[]}",
    ),
    limits,
    "InvalidJson",
  )
  // Wrong schema version / kind
  expect_meta_parse_error(
    @utf8.encode(
      "{\"schema\":2,\"kind\":\"moonlibsync-dir-metadata\",\"executable_paths\":[],\"empty_dirs\":[]}",
    ),
    limits,
    "InvalidSchema",
  )
  expect_meta_parse_error(
    @utf8.encode(
      "{\"schema\":3,\"kind\":\"wrong-kind\",\"executable_paths\":[],\"empty_dirs\":[]}",
    ),
    limits,
    "InvalidSchema",
  )
  // Unsorted array rejected
  expect_meta_parse_error(
    @utf8.encode(
      "{\"schema\":3,\"kind\":\"moonlibsync-dir-metadata\",\"executable_paths\":[\"z\",\"a\"],\"empty_dirs\":[]}",
    ),
    limits,
    "InvalidField:path_order",
  )
  // Non-string array element rejected
  expect_meta_parse_error(
    @utf8.encode(
      "{\"schema\":3,\"kind\":\"moonlibsync-dir-metadata\",\"executable_paths\":[123],\"empty_dirs\":[]}",
    ),
    limits,
    "InvalidField:executable_paths",
  )
  // UTF-8 BOM rejected
  let with_bom = b"\xef\xbb\xbf" +
    @utf8.encode(
      "{\"schema\":3,\"kind\":\"moonlibsync-dir-metadata\",\"executable_paths\":[],\"empty_dirs\":[]}",
    )
  expect_meta_parse_error(with_bom, limits, "InvalidJson")

  // Limits: max_entries, max_path_bytes, max_depth, max_snapshot_bytes
  expect_meta_create_error(
    ["a.sh", "b.sh"],
    [],
    { ..limits, max_entries: 1L, },
    "ResourceLimit:dir_entries",
  )
  expect_meta_create_error(
    ["a.sh"],
    ["empty"],
    { ..limits, max_entries: 1L, },
    "ResourceLimit:dir_entries",
  )
  expect_meta_create_error(
    ["too-long-path.sh"],
    [],
    { ..limits, max_path_bytes: 5L, },
    "ResourceLimit:path_bytes",
  )
  expect_meta_create_error(
    [],
    ["a/b/c"],
    { ..limits, max_depth: 2L, },
    "ResourceLimit:path_depth",
  )
  let small_meta = @moonlibsync.create_dir_metadata(["bin/run.sh"], [], limits)
  let enc_limit_err = try {
    let _ = @moonlibsync.encode_dir_metadata(small_meta, {
      ..limits,
      max_snapshot_bytes: 64L,
    })
    "success"
  } catch {
    @moonlibsync.ManifestError::ResourceLimit(r) => r
    _ => "other"
  }
  assert_eq(enc_limit_err, "metadata_bytes")
  expect_meta_parse_error(
    @moonlibsync.encode_dir_metadata(small_meta, limits),
    { ..limits, max_snapshot_bytes: 64L, },
    "ResourceLimit:metadata_bytes",
  )
}

///|
test "dir_metadata red-team hardening: ancestor rmdir filtering cross-tree case check and DOS bypasses" {
  let limits = @moonlibsync.DirLimits::default()

  // Ancestor empty dir promoted to hold a child dir or executable file is NOT rmdir'd
  let basis_parent = @moonlibsync.create_dir_metadata([], ["a"], limits)
  let target_nested = @moonlibsync.create_dir_metadata([], ["a/b"], limits)
  let plan_nested = @moonlibsync.plan_dir_metadata(
    basis_parent, target_nested, limits,
  )
  assert_eq(plan_nested.mkdir_empty, ["a/b"])
  assert_eq(plan_nested.rmdir_empty, [])

  let target_exec_child = @moonlibsync.create_dir_metadata(
    ["a/run.sh"],
    [],
    limits,
  )
  let plan_exec_child = @moonlibsync.plan_dir_metadata(
    basis_parent, target_exec_child, limits,
  )
  assert_eq(plan_exec_child.chmod_exec, ["a/run.sh"])
  assert_eq(plan_exec_child.rmdir_empty, [])

  // Cross-tree (b_exec, t_exec_dirs) & (t_exec, b_exec_dirs) case collisions rejected
  let m_file = @moonlibsync.create_dir_metadata(["App"], [], limits)
  let m_sub = @moonlibsync.create_dir_metadata(["app/run.sh"], [], limits)
  for pair in [(m_file, m_sub), (m_sub, m_file)] {
    let err = try {
      let _ = @moonlibsync.plan_dir_metadata(pair.0, pair.1, limits)
      "success"
    } catch {
      @moonlibsync.ManifestError::InvalidField(f) => f
      _ => "other"
    }
    assert_eq(err, "path_collision")
  }

  // Space-before-dot and superscript DOS reserved segments rejected
  for
    tricky in ["CON .txt", "NUL .sh", "COM\u{00b9}", "LPT\u{00b2}.bin", "COM0"] {
    expect_meta_create_error([tricky], [], limits, "InvalidField:path")
    expect_meta_create_error([], [tricky], limits, "InvalidField:path")
  }
}
