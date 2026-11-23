// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Optional Schema 3 directory metadata recording POSIX executable file paths
/// (`+x`) and explicit empty directories in canonical UTF-8 sorted order.
#derive(Eq, Debug)
pub(all) struct DirMetadata {
  executable_paths : Array[String]
  empty_dirs : Array[String]
}

///|
/// Return an empty `DirMetadata` value.
pub fn DirMetadata::empty() -> DirMetadata {
  { executable_paths: [], empty_dirs: [], }
}

///|
/// Deterministic metadata reconciliation plan from basis metadata to target metadata.
/// `mkdir_empty` is sorted shallowest-first; `rmdir_empty` is sorted deepest-first.
#derive(Eq, Debug)
pub(all) struct DirMetadataPlan {
  chmod_exec : Array[String]
  chmod_nonexec : Array[String]
  mkdir_empty : Array[String]
  rmdir_empty : Array[String]
}

///|
fn dir_path_depth(path : String) -> Int32 {
  let mut depth = 1
  for c in path {
    if c == '/' {
      depth = depth + 1
    }
  }
  depth
}

///|
/// Validate empty directory paths while allowing nested empty directories (e.g.
/// `"a"` and `"a/b"`), rejecting exact or ASCII case-folded duplicates and any
/// ancestor casing mismatch (`"Dir/a"` vs `"dir/b"`).
fn validate_empty_dir_paths(
  paths : Array[String],
  collision_field : String,
) -> (Map[String, String], Map[String, String]) raise ManifestError {
  let seen_leaves : Map[String, String] = Map([])
  let seen_all_dirs : Map[String, String] = Map([])
  for path in paths {
    let lower = ascii_lower(path)
    guard !seen_leaves.contains(lower) else {
      raise ManifestError::InvalidField(collision_field)
    }
    seen_leaves[lower] = path
    let prefix = StringBuilder()
    for c in path {
      if c == '/' {
        let dir_path = prefix.to_string()
        let dir_lower = ascii_lower(dir_path)
        match seen_all_dirs.get(dir_lower) {
          Some(existing) =>
            if existing != dir_path {
              raise ManifestError::InvalidField(collision_field)
            }
          None => seen_all_dirs[dir_lower] = dir_path
        }
        prefix.write_char('/')
      } else {
        prefix.write_char(c)
      }
    }
    match seen_all_dirs.get(lower) {
      Some(existing) =>
        if existing != path {
          raise ManifestError::InvalidField(collision_field)
        }
      None => seen_all_dirs[lower] = path
    }
  }
  (seen_leaves, seen_all_dirs)
}

///|
fn validate_dir_metadata_lists(
  executable_paths : Array[String],
  empty_dirs : Array[String],
  limits : DirLimits,
  require_sorted~ : Bool,
) -> (
  Map[String, String],
  Map[String, String],
  Map[String, String],
  Map[String, String],
) raise ManifestError {
  limits.validate()
  let exec_len = executable_paths.length().to_int64()
  let empty_len = empty_dirs.length().to_int64()
  guard exec_len <= limits.max_entries &&
    empty_len <= limits.max_entries &&
    exec_len + empty_len <= limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  for i in 0..<executable_paths.length() {
    let p = executable_paths[i]
    validate_dir_path(p, limits)
    if require_sorted && i > 0 {
      guard lexical_path_compare(executable_paths[i - 1], p) < 0 else {
        raise ManifestError::InvalidField("path_order")
      }
    }
  }
  for i in 0..<empty_dirs.length() {
    let d = empty_dirs[i]
    validate_dir_path(d, limits)
    if require_sorted && i > 0 {
      guard lexical_path_compare(empty_dirs[i - 1], d) < 0 else {
        raise ManifestError::InvalidField("path_order")
      }
    }
  }
  let (exec_files, exec_anc_dirs) = validate_tree_paths(
    executable_paths, "path_collision",
  )
  let (empty_leaves, empty_all_dirs) = validate_empty_dir_paths(
    empty_dirs, "path_collision",
  )
  // Reject file-vs-dir collisions: an executable path cannot equal or be an
  // ancestor of an empty dir, nor can an empty dir be an ancestor of a file.
  for lower, _ in exec_files {
    guard !empty_all_dirs.contains(lower) else {
      raise ManifestError::InvalidField("path_collision")
    }
  }
  for lower, _ in empty_leaves {
    guard !exec_anc_dirs.contains(lower) else {
      raise ManifestError::InvalidField("path_collision")
    }
  }
  check_cross_tree_dir_case(exec_anc_dirs, empty_all_dirs, "path_collision")
  (exec_files, exec_anc_dirs, empty_leaves, empty_all_dirs)
}

///|
/// Validate POSIX-relative executable file paths and empty directory paths,
/// enforce limits and collision invariants, and return canonically UTF-8 sorted
/// `DirMetadata`.
pub fn create_dir_metadata(
  executable_paths : Array[String],
  empty_dirs : Array[String],
  limits : DirLimits,
) -> DirMetadata raise ManifestError {
  let _ = validate_dir_metadata_lists(
    executable_paths,
    empty_dirs,
    limits,
    require_sorted=false,
  )
  let sorted_exec = executable_paths.copy()
  sorted_exec.sort_by((a, b) => lexical_path_compare(a, b))
  let sorted_empty = empty_dirs.copy()
  sorted_empty.sort_by((a, b) => lexical_path_compare(a, b))
  { executable_paths: sorted_exec, empty_dirs: sorted_empty, }
}

///|
/// Revalidate and deterministically encode Schema 3 `moonlibsync-dir-metadata` JSON.
pub fn encode_dir_metadata(
  meta : DirMetadata,
  limits : DirLimits,
) -> Bytes raise ManifestError {
  let _ = validate_dir_metadata_lists(
    meta.executable_paths,
    meta.empty_dirs,
    limits,
    require_sorted=true,
  )
  let out = StringBuilder()
  out.write_string(
    "{\"schema\":3,\"kind\":\"moonlibsync-dir-metadata\",\"executable_paths\":[",
  )
  for i in 0..<meta.executable_paths.length() {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string("\"\{json_escape_string(meta.executable_paths[i])}\"")
  }
  out.write_string("],\"empty_dirs\":[")
  for i in 0..<meta.empty_dirs.length() {
    if i > 0 {
      out.write_char(',')
    }
    out.write_string("\"\{json_escape_string(meta.empty_dirs[i])}\"")
  }
  out.write_string("]}\n")
  let encoded = @utf8.encode(out.to_string())
  guard encoded.length().to_int64() <= limits.max_snapshot_bytes else {
    raise ManifestError::ResourceLimit("metadata_bytes")
  }
  encoded
}

///|
/// Strictly parse and validate a Schema 3 `moonlibsync-dir-metadata` JSON document.
pub fn parse_dir_metadata(
  bytes : Bytes,
  limits : DirLimits,
) -> DirMetadata raise ManifestError {
  limits.validate()
  let tree = dir_json_tree(
    bytes,
    limits.max_snapshot_bytes,
    "metadata_bytes",
    2,
  )
  let fields = manifest_object(tree, [
    "schema", "kind", "executable_paths", "empty_dirs",
  ])
  guard manifest_get(fields, "schema")
    is @json.Json::Number(3.0, repr=Some("3")) else {
    raise ManifestError::InvalidSchema
  }
  guard manifest_get(fields, "kind")
    is @json.Json::String("moonlibsync-dir-metadata") else {
    raise ManifestError::InvalidSchema
  }
  guard manifest_get(fields, "executable_paths") is @json.Json::Array(raw_exec) else {
    raise ManifestError::InvalidSchema
  }
  guard manifest_get(fields, "empty_dirs") is @json.Json::Array(raw_empty) else {
    raise ManifestError::InvalidSchema
  }
  guard raw_exec.length().to_int64() <= limits.max_entries &&
    raw_empty.length().to_int64() <= limits.max_entries &&
    raw_exec.length().to_int64() + raw_empty.length().to_int64() <=
    limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let executable_paths : Array[String] = Array(capacity=raw_exec.length())
  for item in raw_exec {
    executable_paths.push(manifest_string(item, "executable_paths"))
  }
  let empty_dirs : Array[String] = Array(capacity=raw_empty.length())
  for item in raw_empty {
    empty_dirs.push(manifest_string(item, "empty_dirs"))
  }
  let _ = validate_dir_metadata_lists(
    executable_paths,
    empty_dirs,
    limits,
    require_sorted=true,
  )
  { executable_paths, empty_dirs, }
}

///|
fn sorted_string_diff(
  basis : Array[String],
  target : Array[String],
) -> (Array[String], Array[String]) {
  let added : Array[String] = []
  let removed : Array[String] = []
  let mut i = 0
  let mut j = 0
  while i < basis.length() && j < target.length() {
    let cmp = lexical_path_compare(basis[i], target[j])
    if cmp < 0 {
      removed.push(basis[i])
      i = i + 1
    } else if cmp > 0 {
      added.push(target[j])
      j = j + 1
    } else {
      i = i + 1
      j = j + 1
    }
  }
  while i < basis.length() {
    removed.push(basis[i])
    i = i + 1
  }
  while j < target.length() {
    added.push(target[j])
    j = j + 1
  }
  (added, removed)
}

///|
/// Reconcile `basis` and `target` `DirMetadata` into a deterministic plan.
/// - `chmod_exec` / `chmod_nonexec`: UTF-8 lexical order.
/// - `mkdir_empty`: shallowest-first (then UTF-8 lexical order).
/// - `rmdir_empty`: deepest-first (then UTF-8 lexical order).
pub fn plan_dir_metadata(
  basis : DirMetadata,
  target : DirMetadata,
  limits : DirLimits,
) -> DirMetadataPlan raise ManifestError {
  let (b_exec, b_exec_dirs, _, b_empty_dirs) = validate_dir_metadata_lists(
    basis.executable_paths,
    basis.empty_dirs,
    limits,
    require_sorted=true,
  )
  let (t_exec, t_exec_dirs, _, t_empty_dirs) = validate_dir_metadata_lists(
    target.executable_paths,
    target.empty_dirs,
    limits,
    require_sorted=true,
  )
  // Reject cross-tree ASCII case-folding collisions across executable paths and directories.
  check_cross_tree_dir_case(b_exec, t_exec, "path_collision")
  check_cross_tree_dir_case(b_exec, t_exec_dirs, "path_collision")
  check_cross_tree_dir_case(t_exec, b_exec_dirs, "path_collision")
  check_cross_tree_dir_case(b_exec, t_empty_dirs, "path_collision")
  check_cross_tree_dir_case(t_exec, b_empty_dirs, "path_collision")
  check_cross_tree_dir_case(b_exec_dirs, t_exec_dirs, "path_collision")
  check_cross_tree_dir_case(b_empty_dirs, t_empty_dirs, "path_collision")
  check_cross_tree_dir_case(b_exec_dirs, t_empty_dirs, "path_collision")
  check_cross_tree_dir_case(b_empty_dirs, t_exec_dirs, "path_collision")

  let (chmod_exec, chmod_nonexec) = sorted_string_diff(
    basis.executable_paths,
    target.executable_paths,
  )
  let (mkdir_empty, raw_rmdir_empty) = sorted_string_diff(
    basis.empty_dirs,
    target.empty_dirs,
  )
  let rmdir_empty : Array[String] = []
  for d in raw_rmdir_empty {
    let lower = ascii_lower(d)
    if !t_empty_dirs.contains(lower) && !t_exec_dirs.contains(lower) {
      rmdir_empty.push(d)
    }
  }
  mkdir_empty.sort_by((a, b) => {
    let da = dir_path_depth(a)
    let db = dir_path_depth(b)
    if da < db {
      -1
    } else if da > db {
      1
    } else {
      lexical_path_compare(a, b)
    }
  })
  rmdir_empty.sort_by((a, b) => {
    let da = dir_path_depth(a)
    let db = dir_path_depth(b)
    if da > db {
      -1
    } else if da < db {
      1
    } else {
      lexical_path_compare(a, b)
    }
  })
  { chmod_exec, chmod_nonexec, mkdir_empty, rmdir_empty, }
}
