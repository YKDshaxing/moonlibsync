// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Resource limits for pure zero-IO directory snapshots and sync planning.
/// All defaults remain conservatively bounded across native, JS, and Wasm-GC.
pub(all) struct DirLimits {
  max_entries : Int64
  max_path_bytes : Int64
  max_depth : Int64
  max_snapshot_bytes : Int64
  max_file_bytes : Int64
}

///|
pub fn DirLimits::default() -> DirLimits {
  {
    max_entries: 4096L,
    max_path_bytes: 1024L,
    max_depth: 32L,
    max_snapshot_bytes: 1048576L,
    max_file_bytes: 67108864L,
  }
}

///|
fn validate_dir_limit(
  name : String,
  value : Int64,
  minimum : Int64,
  maximum : Int64,
) -> Unit raise ManifestError {
  guard value >= minimum && value <= maximum else {
    raise ManifestError::Core(InvalidOptions(name))
  }
}

///|
pub fn DirLimits::validate(self : DirLimits) -> Unit raise ManifestError {
  validate_dir_limit("max_entries", self.max_entries, 0L, 65536L)
  validate_dir_limit("max_path_bytes", self.max_path_bytes, 1L, 4096L)
  validate_dir_limit("max_depth", self.max_depth, 1L, 64L)
  validate_dir_limit(
    "max_snapshot_bytes",
    self.max_snapshot_bytes,
    64L,
    16777216L,
  )
  validate_dir_limit("max_file_bytes", self.max_file_bytes, 0L, 2147483647L)
}

///|
/// Normalized POSIX-relative regular file entry inside a `DirSnapshot`.
pub(all) struct DirEntry {
  path : String
  digest : FileDigest
}

///|
/// Deterministically sorted, collision-free directory file digest snapshot.
pub(all) struct DirSnapshot {
  entries : Array[DirEntry]
}

///|
/// Planned action category when reconciling a basis snapshot to a target snapshot.
pub(all) enum DirActionKind {
  Unchanged
  AddFull
  UpdateCandidate
  Delete
  /// Reuse identical content already present at `source_path` inside `basis` (0-byte transfer).
  CopyFromBasis(String)
}

///|
/// Options controlling directory sync planning behavior.
pub(all) struct DirPlanOptions {
  detect_moves : Bool
}

///|
pub fn DirPlanOptions::default() -> DirPlanOptions {
  { detect_moves: false, }
}

///|
pub(all) struct DirSyncAction {
  path : String
  kind : DirActionKind
  basis : FileDigest?
  target : FileDigest?
}

///|
/// Deterministic reconciliation plan from `basis` snapshot to `target` snapshot.
pub(all) struct DirSyncPlan {
  actions : Array[DirSyncAction]
  unchanged_count : Int64
  add_count : Int64
  update_count : Int64
  delete_count : Int64
  copy_from_basis_count : Int64
  transfer_upper_bound_bytes : Int64
}

///|
fn ascii_lower(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    let code = c.to_int()
    if code >= 65 && code <= 90 {
      out.write_char((code + 32).unsafe_to_char())
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Lexicographical UTF-8 byte comparison (Unicode scalar order, never shortlex).
fn lexical_path_compare(a : String, b : String) -> Int32 {
  let ba = @utf8.encode(a)
  let bb = @utf8.encode(b)
  let la = ba.length()
  let lb = bb.length()
  let min_len = if la < lb { la } else { lb }
  for i in 0..<min_len {
    let xa = ba[i].to_int()
    let xb = bb[i].to_int()
    if xa < xb {
      return -1
    } else if xa > xb {
      return 1
    }
  }
  if la < lb {
    -1
  } else if la > lb {
    1
  } else {
    0
  }
}

///|
fn json_escape_string(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    if c == '"' {
      out.write_string("\\\"")
    } else if c == '\\' {
      out.write_string("\\\\")
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn is_windows_reserved_segment(seg : String) -> Bool {
  let raw : Array[Char] = []
  for c in seg {
    if c == '.' {
      break
    }
    raw.push(c)
  }
  let mut trimmed_len = raw.length()
  while trimmed_len > 0 && raw[trimmed_len - 1] == ' ' {
    trimmed_len = trimmed_len - 1
  }
  let stem_buf = StringBuilder()
  for i in 0..<trimmed_len {
    stem_buf.write_char(raw[i])
  }
  match ascii_lower(stem_buf.to_string()) {
    "con"
    | "prn"
    | "aux"
    | "nul"
    | "com0"
    | "com1"
    | "com2"
    | "com3"
    | "com4"
    | "com5"
    | "com6"
    | "com7"
    | "com8"
    | "com9"
    | "com\u{00b9}"
    | "com\u{00b2}"
    | "com\u{00b3}"
    | "lpt0"
    | "lpt1"
    | "lpt2"
    | "lpt3"
    | "lpt4"
    | "lpt5"
    | "lpt6"
    | "lpt7"
    | "lpt8"
    | "lpt9"
    | "lpt\u{00b9}"
    | "lpt\u{00b2}"
    | "lpt\u{00b3}" => true
    _ => false
  }
}

///|
fn validate_dir_path(
  path : String,
  limits : DirLimits,
) -> Unit raise ManifestError {
  guard path.length() > 0 else { raise ManifestError::InvalidField("path") }
  let utf8_len = @utf8.encode(path).length().to_int64()
  guard utf8_len > 0L && utf8_len <= limits.max_path_bytes else {
    raise ManifestError::ResourceLimit("path_bytes")
  }
  guard !path.has_prefix("/") &&
    !path.has_suffix("/") &&
    !path.contains("//") &&
    !path.contains("\\") &&
    !path.contains(":") else {
    raise ManifestError::InvalidField("path")
  }
  let mut segments = 1L
  let seg = StringBuilder()
  let check_seg = (s : String) => {
    guard s.length() > 0 && s != "." && s != ".." else {
      raise ManifestError::InvalidField("path")
    }
    guard !s.has_suffix(".") && !s.has_suffix(" ") else {
      raise ManifestError::InvalidField("path")
    }
    guard !is_windows_reserved_segment(s) else {
      raise ManifestError::InvalidField("path")
    }
  }
  for c in path {
    let code = c.to_int()
    guard code >= 32 && code != 127 else {
      raise ManifestError::InvalidField("path")
    }
    if c == '/' {
      check_seg(seg.to_string())
      seg.reset()
      segments = segments + 1L
      guard segments <= limits.max_depth else {
        raise ManifestError::ResourceLimit("path_depth")
      }
    } else {
      seg.write_char(c)
    }
  }
  check_seg(seg.to_string())
}

///|
/// Validate a single filesystem tree's paths against:
/// 1) exact and ASCII case-folded leaf duplicates,
/// 2) intermediate directory ASCII case-folding collisions (`DIR/a` vs `dir/b`),
/// 3) exact and ASCII case-folded file-vs-directory ancestor prefix collisions (`foo` vs `foo/bar`).
fn validate_tree_paths(
  paths : Array[String],
  collision_field : String,
) -> (Map[String, String], Map[String, String]) raise ManifestError {
  let seen_files : Map[String, String] = Map([])
  let seen_dirs : Map[String, String] = Map([])
  for path in paths {
    let lower = ascii_lower(path)
    guard !seen_files.contains(lower) else {
      raise ManifestError::InvalidField(collision_field)
    }
    seen_files[lower] = path
    let prefix = StringBuilder()
    for c in path {
      if c == '/' {
        let dir_path = prefix.to_string()
        let dir_lower = ascii_lower(dir_path)
        match seen_dirs.get(dir_lower) {
          Some(existing) =>
            if existing != dir_path {
              raise ManifestError::InvalidField(collision_field)
            }
          None => seen_dirs[dir_lower] = dir_path
        }
        prefix.write_char('/')
      } else {
        prefix.write_char(c)
      }
    }
  }
  for lower, _ in seen_files {
    guard !seen_dirs.contains(lower) else {
      raise ManifestError::InvalidField(collision_field)
    }
  }
  (seen_files, seen_dirs)
}

///|
fn check_cross_tree_dir_case(
  a_dirs : Map[String, String],
  b_dirs : Map[String, String],
  collision_field : String,
) -> Unit raise ManifestError {
  for lower, b_exact in b_dirs {
    match a_dirs.get(lower) {
      Some(a_exact) =>
        if a_exact != b_exact {
          raise ManifestError::InvalidField(collision_field)
        }
      None => ()
    }
  }
}

///|
fn validate_snapshot_entries(
  entries : Array[DirEntry],
  limits : DirLimits,
  require_sorted~ : Bool,
) -> (Map[String, String], Map[String, String]) raise ManifestError {
  limits.validate()
  guard entries.length().to_int64() <= limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let paths : Array[String] = Array(capacity=entries.length())
  for i in 0..<entries.length() {
    let entry = entries[i]
    validate_dir_path(entry.path, limits)
    validate_file_digest(entry.digest, 0L, limits.max_file_bytes, "entry")
    if require_sorted && i > 0 {
      guard lexical_path_compare(entries[i - 1].path, entry.path) < 0 else {
        raise ManifestError::InvalidField("path_order")
      }
    }
    paths.push(entry.path)
  }
  validate_tree_paths(paths, "path_collision")
}

///|
/// Validate POSIX-relative paths, enforce strict file/entry budgets, reject
/// exact and ASCII-case duplicates, and return a canonically sorted snapshot.
pub fn create_dir_snapshot(
  entries : Array[DirEntry],
  limits : DirLimits,
) -> DirSnapshot raise ManifestError {
  let _ = validate_snapshot_entries(entries, limits, require_sorted=false)
  let sorted = entries.copy()
  sorted.sort_by((a, b) => lexical_path_compare(a.path, b.path))
  { entries: sorted, }
}

///|
/// Revalidate snapshot invariants and encode deterministic Schema 3 JSON.
pub fn encode_dir_snapshot(
  snapshot : DirSnapshot,
  limits : DirLimits,
) -> Bytes raise ManifestError {
  let _ = validate_snapshot_entries(
    snapshot.entries,
    limits,
    require_sorted=true,
  )
  let out = StringBuilder()
  out.write_string(
    "{\"schema_version\":3,\"kind\":\"moonlibsync-dir-snapshot\",\"entries\":[",
  )
  for i in 0..<snapshot.entries.length() {
    if i > 0 {
      out.write_char(',')
    }
    let e = snapshot.entries[i]
    out.write_string(
      "{\"path\":\"\{json_escape_string(e.path)}\",\"byte_length\":\"\{e.digest.byte_length}\",\"sha256\":\"\{e.digest.sha256}\"}",
    )
  }
  out.write_string("]}\n")
  let encoded = @utf8.encode(out.to_string())
  guard encoded.length().to_int64() <= limits.max_snapshot_bytes else {
    raise ManifestError::ResourceLimit("snapshot_bytes")
  }
  encoded
}

///|
fn dir_json_tree(
  input : Bytes,
  maximum : Int64,
  limit_name : String,
  max_depth : Int32,
) -> @json.Json raise ManifestError {
  guard input.length().to_int64() <= maximum else {
    raise ManifestError::ResourceLimit(limit_name)
  }
  let text = @utf8.decode(input, ignore_bom=false) catch {
    _ => raise ManifestError::InvalidUtf8
  }
  guard !(input.length() >= 3 &&
    input[0] == b'\xef' &&
    input[1] == b'\xbb' &&
    input[2] == b'\xbf') else {
    raise ManifestError::InvalidJson
  }
  @json.parse(
    text,
    max_nesting_depth=max_depth,
    reject_duplicate_keys=true,
    preserve_number_repr=true,
  ) catch {
    @json.ParseError::DepthLimitExceeded =>
      raise ManifestError::ResourceLimit("manifest_depth")
    _ => raise ManifestError::InvalidJson
  }
}

///|
fn dir_schema3_header(
  fields : Map[String, @json.Json],
  expected_kind : String,
) -> Unit raise ManifestError {
  guard manifest_get(fields, "schema_version")
    is @json.Json::Number(3.0, repr=Some("3")) else {
    raise ManifestError::InvalidSchema
  }
  guard manifest_get(fields, "kind") is @json.Json::String(actual) &&
    actual == expected_kind else {
    raise ManifestError::InvalidSchema
  }
}

///|
/// Parse and strictly validate a Schema 3 `moonlibsync-dir-snapshot` JSON document.
pub fn parse_dir_snapshot(
  input : Bytes,
  limits : DirLimits,
) -> DirSnapshot raise ManifestError {
  limits.validate()
  let tree = dir_json_tree(
    input,
    limits.max_snapshot_bytes,
    "snapshot_bytes",
    3,
  )
  let fields = manifest_object(tree, ["schema_version", "kind", "entries"])
  dir_schema3_header(fields, "moonlibsync-dir-snapshot")
  guard manifest_get(fields, "entries") is @json.Json::Array(raw_entries) else {
    raise ManifestError::InvalidSchema
  }
  guard raw_entries.length().to_int64() <= limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let entries : Array[DirEntry] = Array(capacity=raw_entries.length())
  for item in raw_entries {
    let f = manifest_object(item, ["path", "byte_length", "sha256"])
    entries.push({
      path: manifest_string(manifest_get(f, "path"), "path"),
      digest: {
        byte_length: manifest_decimal(
          manifest_string(manifest_get(f, "byte_length"), "byte_length"),
        ),
        sha256: manifest_string(manifest_get(f, "sha256"), "sha256"),
      },
    })
  }
  let _ = validate_snapshot_entries(entries, limits, require_sorted=true)
  { entries, }
}

///|
fn same_digest(a : FileDigest, b : FileDigest) -> Bool {
  a.byte_length == b.byte_length && a.sha256 == b.sha256
}

///|
fn checked_add_i64(a : Int64, b : Int64) -> Int64 raise ManifestError {
  guard a >= 0L && b >= 0L && a <= 9223372036854775807L - b else {
    raise ManifestError::Core(IntegerOutOfRange)
  }
  a + b
}

///|
fn plan_json_budget(limits : DirLimits) -> Int64 {
  let scaled = limits.max_snapshot_bytes * 4L
  if scaled > 67108864L {
    67108864L
  } else {
    scaled
  }
}

///|
fn validate_sync_plan(
  plan : DirSyncPlan,
  limits : DirLimits,
) -> Unit raise ManifestError {
  limits.validate()
  let max_actions = limits.max_entries * 2L
  guard plan.actions.length().to_int64() <= max_actions else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let seen_lower : Map[String, String] = Map([])
  let basis_paths : Array[String] = []
  let target_paths : Array[String] = []
  let mut unchanged = 0L
  let mut add = 0L
  let mut update = 0L
  let mut del = 0L
  let mut copy_from_basis = 0L
  let mut transfer_upper = 0L
  for i in 0..<plan.actions.length() {
    let action = plan.actions[i]
    validate_dir_path(action.path, limits)
    let lower = ascii_lower(action.path)
    guard !seen_lower.contains(lower) else {
      raise ManifestError::InvalidField("path_collision")
    }
    seen_lower[lower] = action.path
    if i > 0 {
      guard lexical_path_compare(plan.actions[i - 1].path, action.path) < 0 else {
        raise ManifestError::InvalidField("path_order")
      }
    }
    match action.kind {
      Unchanged => {
        guard action.basis is Some(b) && action.target is Some(t) else {
          raise ManifestError::InvalidField("action")
        }
        validate_file_digest(b, 0L, limits.max_file_bytes, "basis")
        validate_file_digest(t, 0L, limits.max_file_bytes, "target")
        guard same_digest(b, t) else {
          raise ManifestError::BindingMismatch("unchanged_digest")
        }
        basis_paths.push(action.path)
        target_paths.push(action.path)
        unchanged = unchanged + 1L
      }
      AddFull => {
        guard action.basis is None && action.target is Some(t) else {
          raise ManifestError::InvalidField("action")
        }
        validate_file_digest(t, 0L, limits.max_file_bytes, "target")
        target_paths.push(action.path)
        add = add + 1L
        transfer_upper = checked_add_i64(transfer_upper, t.byte_length)
      }
      UpdateCandidate => {
        guard action.basis is Some(b) && action.target is Some(t) else {
          raise ManifestError::InvalidField("action")
        }
        validate_file_digest(b, 0L, limits.max_file_bytes, "basis")
        validate_file_digest(t, 0L, limits.max_file_bytes, "target")
        guard !same_digest(b, t) else {
          raise ManifestError::BindingMismatch("update_digest")
        }
        basis_paths.push(action.path)
        target_paths.push(action.path)
        update = update + 1L
        transfer_upper = checked_add_i64(transfer_upper, t.byte_length)
      }
      Delete => {
        guard action.basis is Some(b) && action.target is None else {
          raise ManifestError::InvalidField("action")
        }
        validate_file_digest(b, 0L, limits.max_file_bytes, "basis")
        basis_paths.push(action.path)
        del = del + 1L
      }
      CopyFromBasis(source_path) => {
        guard action.target is Some(t) else {
          raise ManifestError::InvalidField("action")
        }
        validate_dir_path(source_path, limits)
        guard ascii_lower(source_path) != ascii_lower(action.path) else {
          raise ManifestError::InvalidField("source_path")
        }
        validate_file_digest(t, 0L, limits.max_file_bytes, "target")
        match action.basis {
          Some(b) => {
            validate_file_digest(b, 0L, limits.max_file_bytes, "basis")
            guard !same_digest(b, t) else {
              raise ManifestError::BindingMismatch("update_digest")
            }
            basis_paths.push(action.path)
          }
          None => ()
        }
        target_paths.push(action.path)
        copy_from_basis = copy_from_basis + 1L
      }
    }
  }
  guard basis_paths.length().to_int64() <= limits.max_entries &&
    target_paths.length().to_int64() <= limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let (_, basis_dirs) = validate_tree_paths(basis_paths, "path_collision")
  let (_, target_dirs) = validate_tree_paths(target_paths, "path_collision")
  check_cross_tree_dir_case(basis_dirs, target_dirs, "path_collision")
  guard plan.unchanged_count == unchanged &&
    plan.add_count == add &&
    plan.update_count == update &&
    plan.delete_count == del &&
    plan.copy_from_basis_count == copy_from_basis &&
    plan.transfer_upper_bound_bytes == transfer_upper else {
    raise ManifestError::BindingMismatch("plan_summary")
  }
}

///|
fn digest_lookup_key(d : FileDigest) -> String {
  "\{d.byte_length}:\{d.sha256}"
}

///|
/// Reconcile two validated snapshots in O(N + M) sorted order with optional
/// content-digest move/copy detection (`CopyFromBasis` for 0-byte transfers,
/// including cyclic swaps; callers applying plans must materialize into a fresh
/// staging directory rather than mutating `basis` in place).
pub fn plan_dir_sync_with_options(
  basis : DirSnapshot,
  target : DirSnapshot,
  options : DirPlanOptions,
  limits : DirLimits,
) -> DirSyncPlan raise ManifestError {
  let (basis_lower, basis_dirs) = validate_snapshot_entries(
    basis.entries,
    limits,
    require_sorted=true,
  )
  let (_, target_dirs) = validate_snapshot_entries(
    target.entries,
    limits,
    require_sorted=true,
  )
  check_cross_tree_dir_case(basis_dirs, target_dirs, "path_collision")
  for entry in target.entries {
    let lower = ascii_lower(entry.path)
    match basis_lower.get(lower) {
      Some(bpath) =>
        if bpath != entry.path {
          raise ManifestError::InvalidField("path_collision")
        }
      None => ()
    }
  }
  let basis_by_digest : Map[String, String] = Map([])
  if options.detect_moves {
    for entry in basis.entries {
      let key = digest_lookup_key(entry.digest)
      if !basis_by_digest.contains(key) {
        basis_by_digest[key] = entry.path
      }
    }
  }
  let actions : Array[DirSyncAction] = []
  let mut unchanged_count = 0L
  let mut add_count = 0L
  let mut update_count = 0L
  let mut delete_count = 0L
  let mut copy_from_basis_count = 0L
  let mut transfer_upper_bound_bytes = 0L
  let mut i = 0
  let mut j = 0
  while i < basis.entries.length() && j < target.entries.length() {
    let b = basis.entries[i]
    let t = target.entries[j]
    let cmp = lexical_path_compare(b.path, t.path)
    if cmp < 0 {
      actions.push({
        path: b.path,
        kind: Delete,
        basis: Some(b.digest),
        target: None,
      })
      delete_count = delete_count + 1L
      i = i + 1
    } else if cmp > 0 {
      match basis_by_digest.get(digest_lookup_key(t.digest)) {
        Some(src_path) if options.detect_moves &&
          ascii_lower(src_path) != ascii_lower(t.path) => {
          actions.push({
            path: t.path,
            kind: CopyFromBasis(src_path),
            basis: None,
            target: Some(t.digest),
          })
          copy_from_basis_count = copy_from_basis_count + 1L
        }
        _ => {
          actions.push({
            path: t.path,
            kind: AddFull,
            basis: None,
            target: Some(t.digest),
          })
          add_count = add_count + 1L
          transfer_upper_bound_bytes = checked_add_i64(
            transfer_upper_bound_bytes,
            t.digest.byte_length,
          )
        }
      }
      j = j + 1
    } else {
      if same_digest(b.digest, t.digest) {
        actions.push({
          path: t.path,
          kind: Unchanged,
          basis: Some(b.digest),
          target: Some(t.digest),
        })
        unchanged_count = unchanged_count + 1L
      } else {
        match basis_by_digest.get(digest_lookup_key(t.digest)) {
          Some(src_path) if options.detect_moves &&
            ascii_lower(src_path) != ascii_lower(t.path) => {
            actions.push({
              path: t.path,
              kind: CopyFromBasis(src_path),
              basis: Some(b.digest),
              target: Some(t.digest),
            })
            copy_from_basis_count = copy_from_basis_count + 1L
          }
          _ => {
            actions.push({
              path: t.path,
              kind: UpdateCandidate,
              basis: Some(b.digest),
              target: Some(t.digest),
            })
            update_count = update_count + 1L
            transfer_upper_bound_bytes = checked_add_i64(
              transfer_upper_bound_bytes,
              t.digest.byte_length,
            )
          }
        }
      }
      i = i + 1
      j = j + 1
    }
  }
  while i < basis.entries.length() {
    let b = basis.entries[i]
    actions.push({
      path: b.path,
      kind: Delete,
      basis: Some(b.digest),
      target: None,
    })
    delete_count = delete_count + 1L
    i = i + 1
  }
  while j < target.entries.length() {
    let t = target.entries[j]
    match basis_by_digest.get(digest_lookup_key(t.digest)) {
      Some(src_path) if options.detect_moves &&
        ascii_lower(src_path) != ascii_lower(t.path) => {
        actions.push({
          path: t.path,
          kind: CopyFromBasis(src_path),
          basis: None,
          target: Some(t.digest),
        })
        copy_from_basis_count = copy_from_basis_count + 1L
      }
      _ => {
        actions.push({
          path: t.path,
          kind: AddFull,
          basis: None,
          target: Some(t.digest),
        })
        add_count = add_count + 1L
        transfer_upper_bound_bytes = checked_add_i64(
          transfer_upper_bound_bytes,
          t.digest.byte_length,
        )
      }
    }
    j = j + 1
  }
  {
    actions,
    unchanged_count,
    add_count,
    update_count,
    delete_count,
    copy_from_basis_count,
    transfer_upper_bound_bytes,
  }
}

///|
/// Reconcile two validated snapshots in O(N + M) sorted order, rejecting any
/// cross-snapshot ASCII case-folding collision before emitting a deterministic plan.
pub fn plan_dir_sync(
  basis : DirSnapshot,
  target : DirSnapshot,
  limits : DirLimits,
) -> DirSyncPlan raise ManifestError {
  plan_dir_sync_with_options(basis, target, DirPlanOptions::default(), limits)
}

///|
fn action_kind_label(kind : DirActionKind) -> String {
  match kind {
    Unchanged => "unchanged"
    AddFull => "add-full"
    UpdateCandidate => "update-candidate"
    Delete => "delete"
    CopyFromBasis(_) => "copy-from-basis"
  }
}

///|
/// Revalidate and deterministically encode a Schema 3 `moonlibsync-dir-plan`.
pub fn encode_dir_plan(
  plan : DirSyncPlan,
  limits : DirLimits,
) -> Bytes raise ManifestError {
  validate_sync_plan(plan, limits)
  let out = StringBuilder()
  out.write_string(
    "{\"schema_version\":3,\"kind\":\"moonlibsync-dir-plan\",\"summary\":{\"unchanged\":\"\{plan.unchanged_count}\",\"add\":\"\{plan.add_count}\",\"update\":\"\{plan.update_count}\",\"delete\":\"\{plan.delete_count}\"",
  )
  if plan.copy_from_basis_count > 0L {
    out.write_string(",\"copy_from_basis\":\"\{plan.copy_from_basis_count}\"")
  }
  out.write_string(
    ",\"transfer_upper_bound_bytes\":\"\{plan.transfer_upper_bound_bytes}\"},\"actions\":[",
  )
  for i in 0..<plan.actions.length() {
    if i > 0 {
      out.write_char(',')
    }
    let a = plan.actions[i]
    out.write_string(
      "{\"path\":\"\{json_escape_string(a.path)}\",\"kind\":\"\{action_kind_label(a.kind)}\"",
    )
    match a.kind {
      CopyFromBasis(source_path) =>
        out.write_string(
          ",\"source_path\":\"\{json_escape_string(source_path)}\"",
        )
      _ => ()
    }
    match a.basis {
      Some(b) => out.write_string(",\"basis\":\{file_digest_json(b)}")
      None => ()
    }
    match a.target {
      Some(t) => out.write_string(",\"target\":\{file_digest_json(t)}")
      None => ()
    }
    out.write_char('}')
  }
  out.write_string("]}\n")
  let encoded = @utf8.encode(out.to_string())
  guard encoded.length().to_int64() <= plan_json_budget(limits) else {
    raise ManifestError::ResourceLimit("plan_bytes")
  }
  encoded
}

///|
/// Parse and strictly validate a Schema 3 `moonlibsync-dir-plan` JSON document.
pub fn parse_dir_plan(
  input : Bytes,
  limits : DirLimits,
) -> DirSyncPlan raise ManifestError {
  limits.validate()
  let tree = dir_json_tree(input, plan_json_budget(limits), "plan_bytes", 4)
  let fields = manifest_object(tree, [
    "schema_version", "kind", "summary", "actions",
  ])
  dir_schema3_header(fields, "moonlibsync-dir-plan")
  let raw_sum = manifest_get(fields, "summary")
  guard raw_sum is @json.Json::Object(raw_sum_map) else {
    raise ManifestError::InvalidSchema
  }
  let has_cfb = raw_sum_map.contains("copy_from_basis")
  let sum_fields = if has_cfb {
    manifest_object(raw_sum, [
      "unchanged", "add", "update", "delete", "copy_from_basis", "transfer_upper_bound_bytes",
    ])
  } else {
    manifest_object(raw_sum, [
      "unchanged", "add", "update", "delete", "transfer_upper_bound_bytes",
    ])
  }
  let unchanged_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "unchanged"), "unchanged"),
  )
  let add_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "add"), "add"),
  )
  let update_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "update"), "update"),
  )
  let delete_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "delete"), "delete"),
  )
  let copy_from_basis_count = if has_cfb {
    manifest_decimal(
      manifest_string(
        manifest_get(sum_fields, "copy_from_basis"),
        "copy_from_basis",
      ),
    )
  } else {
    0L
  }
  let transfer_upper_bound_bytes = manifest_decimal(
    manifest_string(
      manifest_get(sum_fields, "transfer_upper_bound_bytes"),
      "transfer_upper_bound_bytes",
    ),
  )
  guard manifest_get(fields, "actions") is @json.Json::Array(raw_actions) else {
    raise ManifestError::InvalidSchema
  }
  guard raw_actions.length().to_int64() <= limits.max_entries * 2L else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let actions : Array[DirSyncAction] = Array(capacity=raw_actions.length())
  for item in raw_actions {
    guard item is @json.Json::Object(af) else {
      raise ManifestError::InvalidSchema
    }
    let kind_str = manifest_string(manifest_get(af, "kind"), "kind")
    let path = manifest_string(manifest_get(af, "path"), "path")
    let (kind, basis, target) = if kind_str == "unchanged" {
      let f = manifest_object(item, ["path", "kind", "basis", "target"])
      (
        DirActionKind::Unchanged,
        Some(parse_file_digest(manifest_get(f, "basis"))),
        Some(parse_file_digest(manifest_get(f, "target"))),
      )
    } else if kind_str == "update-candidate" {
      let f = manifest_object(item, ["path", "kind", "basis", "target"])
      (
        DirActionKind::UpdateCandidate,
        Some(parse_file_digest(manifest_get(f, "basis"))),
        Some(parse_file_digest(manifest_get(f, "target"))),
      )
    } else if kind_str == "add-full" {
      let f = manifest_object(item, ["path", "kind", "target"])
      (
        DirActionKind::AddFull,
        None,
        Some(parse_file_digest(manifest_get(f, "target"))),
      )
    } else if kind_str == "delete" {
      let f = manifest_object(item, ["path", "kind", "basis"])
      (
        DirActionKind::Delete,
        Some(parse_file_digest(manifest_get(f, "basis"))),
        None,
      )
    } else if kind_str == "copy-from-basis" {
      if af.contains("basis") {
        let f = manifest_object(item, [
          "path", "kind", "source_path", "basis", "target",
        ])
        (
          DirActionKind::CopyFromBasis(
            manifest_string(manifest_get(f, "source_path"), "source_path"),
          ),
          Some(parse_file_digest(manifest_get(f, "basis"))),
          Some(parse_file_digest(manifest_get(f, "target"))),
        )
      } else {
        let f = manifest_object(item, ["path", "kind", "source_path", "target"])
        (
          DirActionKind::CopyFromBasis(
            manifest_string(manifest_get(f, "source_path"), "source_path"),
          ),
          None,
          Some(parse_file_digest(manifest_get(f, "target"))),
        )
      }
    } else {
      raise ManifestError::InvalidSchema
    }
    actions.push({ path, kind, basis, target, })
  }
  let plan : DirSyncPlan = {
    actions,
    unchanged_count,
    add_count,
    update_count,
    delete_count,
    copy_from_basis_count,
    transfer_upper_bound_bytes,
  }
  validate_sync_plan(plan, limits)
  plan
}

///|
/// Single file entry inside a Schema 3 `moonlibsync-dir-signatures` index.
/// Binds a normalized relative path to both its basis digest and remote `.sig` file digest.
pub(all) struct DirSignatureEntry {
  path : String
  basis : FileDigest
  signature_path : String
  signature : FileDigest
}

///|
/// Canonically sorted Schema 3 index of remote file signatures for a directory snapshot.
pub(all) struct DirSignatureIndex {
  entries : Array[DirSignatureEntry]
}

///|
/// Per-file action inside a self-contained Schema 3 `moonlibsync-dir-bundle`.
pub(all) enum DirBundleAction {
  Unchanged(FileDigest)
  AddFull(String, FileDigest)
  UpdateDelta(String, UpdateManifest)
  UpdateFull(String, FileDigest, FileDigest)
  Delete(FileDigest)
  /// Reuse identical bytes already present at `source_path` in `BASIS_DIR` (0-byte payload).
  CopyFromBasis(String, FileDigest)
  /// Apply a librsync delta against a different `source_path` in `BASIS_DIR` (moved + edited file).
  UpdateDeltaFrom(String, String, UpdateManifest)
}

///|
pub(all) struct DirBundleEntry {
  path : String
  action : DirBundleAction
}

///|
/// Deterministic Schema 3 directory incremental sync bundle manifest.
pub(all) struct DirBundleManifest {
  entries : Array[DirBundleEntry]
  unchanged_count : Int64
  add_full_count : Int64
  update_delta_count : Int64
  update_full_count : Int64
  delete_count : Int64
  copy_from_basis_count : Int64
  total_payload_bytes : Int64
}

///|
fn bundle_json_budget(limits : DirLimits) -> Int64 {
  let scaled = limits.max_snapshot_bytes * 8L
  if scaled > 67108864L {
    67108864L
  } else {
    scaled
  }
}

///|
fn validate_scoped_rel_path(
  rel_path : String,
  prefix : String,
  field : String,
  limits : DirLimits,
  seen_lower : Map[String, String],
  collision_field : String,
) -> Unit raise ManifestError {
  validate_dir_path(rel_path, limits)
  guard rel_path.has_prefix(prefix) else {
    raise ManifestError::InvalidField(field)
  }
  let lower = ascii_lower(rel_path)
  guard !seen_lower.contains(lower) else {
    raise ManifestError::InvalidField(collision_field)
  }
  seen_lower[lower] = rel_path
}

///|
fn validate_dir_signature_entries(
  entries : Array[DirSignatureEntry],
  dir_limits : DirLimits,
  limits : Limits,
  require_sorted~ : Bool,
) -> Unit raise ManifestError {
  dir_limits.validate()
  manifest_limits(limits)
  guard entries.length().to_int64() <= dir_limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let seen_sig : Map[String, String] = Map([])
  let entry_paths : Array[String] = Array(capacity=entries.length())
  let sig_paths : Array[String] = Array(capacity=entries.length())
  for i in 0..<entries.length() {
    let entry = entries[i]
    validate_dir_path(entry.path, dir_limits)
    if require_sorted && i > 0 {
      guard lexical_path_compare(entries[i - 1].path, entry.path) < 0 else {
        raise ManifestError::InvalidField("path_order")
      }
    }
    validate_scoped_rel_path(
      entry.signature_path,
      "sigs/",
      "signature_path",
      dir_limits,
      seen_sig,
      "signature_path_collision",
    )
    validate_file_digest(entry.basis, 0L, dir_limits.max_file_bytes, "basis")
    validate_file_digest(entry.basis, 0L, limits.max_old_bytes, "basis")
    validate_file_digest(
      entry.signature,
      12L,
      limits.max_signature_bytes,
      "signature",
    )
    entry_paths.push(entry.path)
    sig_paths.push(entry.signature_path)
  }
  let _ = validate_tree_paths(entry_paths, "path_collision")
  let _ = validate_tree_paths(sig_paths, "signature_path_collision")
}

///|
/// Validate and canonically sort a Schema 3 `DirSignatureIndex`.
pub fn create_dir_signature_index(
  entries : Array[DirSignatureEntry],
  dir_limits : DirLimits,
  limits : Limits,
) -> DirSignatureIndex raise ManifestError {
  validate_dir_signature_entries(
    entries,
    dir_limits,
    limits,
    require_sorted=false,
  )
  let sorted = entries.copy()
  sorted.sort_by((a, b) => lexical_path_compare(a.path, b.path))
  { entries: sorted, }
}

///|
/// Revalidate and encode a deterministic Schema 3 `moonlibsync-dir-signatures` JSON document.
pub fn encode_dir_signature_index(
  index : DirSignatureIndex,
  dir_limits : DirLimits,
  limits : Limits,
) -> Bytes raise ManifestError {
  validate_dir_signature_entries(
    index.entries,
    dir_limits,
    limits,
    require_sorted=true,
  )
  let out = StringBuilder()
  out.write_string(
    "{\"schema_version\":3,\"kind\":\"moonlibsync-dir-signatures\",\"entries\":[",
  )
  for i in 0..<index.entries.length() {
    if i > 0 {
      out.write_char(',')
    }
    let e = index.entries[i]
    out.write_string(
      "{\"path\":\"\{json_escape_string(e.path)}\",\"basis\":\{file_digest_json(e.basis)},\"signature_path\":\"\{json_escape_string(e.signature_path)}\",\"signature\":\{file_digest_json(e.signature)}}",
    )
  }
  out.write_string("]}\n")
  let encoded = @utf8.encode(out.to_string())
  guard encoded.length().to_int64() <= plan_json_budget(dir_limits) else {
    raise ManifestError::ResourceLimit("signatures_bytes")
  }
  encoded
}

///|
/// Parse and strictly validate a Schema 3 `moonlibsync-dir-signatures` JSON document.
pub fn parse_dir_signature_index(
  input : Bytes,
  dir_limits : DirLimits,
  limits : Limits,
) -> DirSignatureIndex raise ManifestError {
  dir_limits.validate()
  manifest_limits(limits)
  let tree = dir_json_tree(
    input,
    plan_json_budget(dir_limits),
    "signatures_bytes",
    5,
  )
  let fields = manifest_object(tree, ["schema_version", "kind", "entries"])
  dir_schema3_header(fields, "moonlibsync-dir-signatures")
  guard manifest_get(fields, "entries") is @json.Json::Array(raw_entries) else {
    raise ManifestError::InvalidSchema
  }
  guard raw_entries.length().to_int64() <= dir_limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let entries : Array[DirSignatureEntry] = Array(capacity=raw_entries.length())
  for item in raw_entries {
    let f = manifest_object(item, [
      "path", "basis", "signature_path", "signature",
    ])
    entries.push({
      path: manifest_string(manifest_get(f, "path"), "path"),
      basis: parse_file_digest(manifest_get(f, "basis")),
      signature_path: manifest_string(
        manifest_get(f, "signature_path"),
        "signature_path",
      ),
      signature: parse_file_digest(manifest_get(f, "signature")),
    })
  }
  validate_dir_signature_entries(
    entries,
    dir_limits,
    limits,
    require_sorted=true,
  )
  { entries, }
}

///|
fn validate_dir_bundle_entries(
  entries : Array[DirBundleEntry],
  dir_limits : DirLimits,
  limits : Limits,
  require_sorted~ : Bool,
) -> (Int64, Int64, Int64, Int64, Int64, Int64, Int64) raise ManifestError {
  dir_limits.validate()
  manifest_limits(limits)
  guard entries.length().to_int64() <= dir_limits.max_entries * 2L else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let seen_path : Map[String, String] = Map([])
  let seen_payload : Map[String, String] = Map([])
  let basis_paths : Array[String] = []
  let target_paths : Array[String] = []
  let payload_paths : Array[String] = []
  let mut unchanged = 0L
  let mut add_full = 0L
  let mut update_delta = 0L
  let mut update_full = 0L
  let mut del = 0L
  let mut copy_from_basis = 0L
  let mut total_payload = 0L
  for i in 0..<entries.length() {
    let entry = entries[i]
    validate_dir_path(entry.path, dir_limits)
    let lower = ascii_lower(entry.path)
    guard !seen_path.contains(lower) else {
      raise ManifestError::InvalidField("path_collision")
    }
    seen_path[lower] = entry.path
    if require_sorted && i > 0 {
      guard lexical_path_compare(entries[i - 1].path, entry.path) < 0 else {
        raise ManifestError::InvalidField("path_order")
      }
    }
    match entry.action {
      Unchanged(d) => {
        validate_file_digest(d, 0L, dir_limits.max_file_bytes, "basis")
        validate_file_digest(d, 0L, limits.max_old_bytes, "basis")
        validate_file_digest(d, 0L, limits.max_output_bytes, "result")
        basis_paths.push(entry.path)
        target_paths.push(entry.path)
        unchanged = unchanged + 1L
      }
      AddFull(payload_path, target) => {
        validate_scoped_rel_path(
          payload_path, "payloads/", "payload_path", dir_limits, seen_payload, "payload_path_collision",
        )
        validate_file_digest(target, 0L, dir_limits.max_file_bytes, "target")
        validate_file_digest(target, 0L, limits.max_new_bytes, "target")
        validate_file_digest(target, 0L, limits.max_output_bytes, "result")
        target_paths.push(entry.path)
        payload_paths.push(payload_path)
        add_full = add_full + 1L
        total_payload = checked_add_i64(total_payload, target.byte_length)
      }
      UpdateDelta(payload_path, m) => {
        validate_scoped_rel_path(
          payload_path, "payloads/", "payload_path", dir_limits, seen_payload, "payload_path_collision",
        )
        validate_update_manifest(m, limits)
        validate_file_digest(m.basis, 0L, dir_limits.max_file_bytes, "basis")
        validate_file_digest(m.result, 0L, dir_limits.max_file_bytes, "result")
        guard !same_digest(m.basis, m.result) else {
          raise ManifestError::BindingMismatch("update_digest")
        }
        basis_paths.push(entry.path)
        target_paths.push(entry.path)
        payload_paths.push(payload_path)
        update_delta = update_delta + 1L
        total_payload = checked_add_i64(total_payload, m.delta.byte_length)
      }
      UpdateFull(payload_path, basis, target) => {
        validate_scoped_rel_path(
          payload_path, "payloads/", "payload_path", dir_limits, seen_payload, "payload_path_collision",
        )
        validate_file_digest(basis, 0L, dir_limits.max_file_bytes, "basis")
        validate_file_digest(basis, 0L, limits.max_old_bytes, "basis")
        validate_file_digest(target, 0L, dir_limits.max_file_bytes, "target")
        validate_file_digest(target, 0L, limits.max_new_bytes, "target")
        validate_file_digest(target, 0L, limits.max_output_bytes, "result")
        guard !same_digest(basis, target) else {
          raise ManifestError::BindingMismatch("update_digest")
        }
        basis_paths.push(entry.path)
        target_paths.push(entry.path)
        payload_paths.push(payload_path)
        update_full = update_full + 1L
        total_payload = checked_add_i64(total_payload, target.byte_length)
      }
      Delete(basis) => {
        validate_file_digest(basis, 0L, dir_limits.max_file_bytes, "basis")
        validate_file_digest(basis, 0L, limits.max_old_bytes, "basis")
        basis_paths.push(entry.path)
        del = del + 1L
      }
      CopyFromBasis(source_path, target) => {
        validate_dir_path(source_path, dir_limits)
        guard ascii_lower(source_path) != ascii_lower(entry.path) else {
          raise ManifestError::InvalidField("source_path")
        }
        validate_file_digest(target, 0L, dir_limits.max_file_bytes, "target")
        validate_file_digest(target, 0L, limits.max_old_bytes, "basis")
        validate_file_digest(target, 0L, limits.max_output_bytes, "result")
        target_paths.push(entry.path)
        copy_from_basis = copy_from_basis + 1L
      }
      UpdateDeltaFrom(source_path, payload_path, m) => {
        validate_dir_path(source_path, dir_limits)
        guard ascii_lower(source_path) != ascii_lower(entry.path) else {
          raise ManifestError::InvalidField("source_path")
        }
        validate_scoped_rel_path(
          payload_path, "payloads/", "payload_path", dir_limits, seen_payload, "payload_path_collision",
        )
        validate_update_manifest(m, limits)
        validate_file_digest(m.basis, 0L, dir_limits.max_file_bytes, "basis")
        validate_file_digest(m.result, 0L, dir_limits.max_file_bytes, "result")
        guard !same_digest(m.basis, m.result) else {
          raise ManifestError::BindingMismatch("update_digest")
        }
        target_paths.push(entry.path)
        payload_paths.push(payload_path)
        update_delta = update_delta + 1L
        total_payload = checked_add_i64(total_payload, m.delta.byte_length)
      }
    }
  }
  guard basis_paths.length().to_int64() <= dir_limits.max_entries &&
    target_paths.length().to_int64() <= dir_limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let (_, basis_dirs) = validate_tree_paths(basis_paths, "path_collision")
  let (_, target_dirs) = validate_tree_paths(target_paths, "path_collision")
  check_cross_tree_dir_case(basis_dirs, target_dirs, "path_collision")
  let _ = validate_tree_paths(payload_paths, "payload_path_collision")
  (
    unchanged, add_full, update_delta, update_full, del, copy_from_basis, total_payload,
  )
}

///|
/// Validate entries, compute exact summary counts and payload bytes, and sort
/// entries canonically into a Schema 3 `DirBundleManifest`.
pub fn create_dir_bundle_manifest(
  entries : Array[DirBundleEntry],
  dir_limits : DirLimits,
  limits : Limits,
) -> DirBundleManifest raise ManifestError {
  let (
    unchanged_count,
    add_full_count,
    update_delta_count,
    update_full_count,
    delete_count,
    copy_from_basis_count,
    total_payload_bytes,
  ) = validate_dir_bundle_entries(
    entries,
    dir_limits,
    limits,
    require_sorted=false,
  )
  let sorted = entries.copy()
  sorted.sort_by((a, b) => lexical_path_compare(a.path, b.path))
  {
    entries: sorted,
    unchanged_count,
    add_full_count,
    update_delta_count,
    update_full_count,
    delete_count,
    copy_from_basis_count,
    total_payload_bytes,
  }
}

///|
fn validate_dir_bundle_manifest(
  bundle : DirBundleManifest,
  dir_limits : DirLimits,
  limits : Limits,
) -> Unit raise ManifestError {
  let (
    unchanged,
    add_full,
    update_delta,
    update_full,
    del,
    copy_from_basis,
    total_payload,
  ) = validate_dir_bundle_entries(
    bundle.entries,
    dir_limits,
    limits,
    require_sorted=true,
  )
  guard bundle.unchanged_count == unchanged &&
    bundle.add_full_count == add_full &&
    bundle.update_delta_count == update_delta &&
    bundle.update_full_count == update_full &&
    bundle.delete_count == del &&
    bundle.copy_from_basis_count == copy_from_basis &&
    bundle.total_payload_bytes == total_payload else {
    raise ManifestError::BindingMismatch("bundle_summary")
  }
}

///|
/// Revalidate and deterministically encode a Schema 3 `moonlibsync-dir-bundle` JSON document.
pub fn encode_dir_bundle_manifest(
  bundle : DirBundleManifest,
  dir_limits : DirLimits,
  limits : Limits,
) -> Bytes raise ManifestError {
  validate_dir_bundle_manifest(bundle, dir_limits, limits)
  let out = StringBuilder()
  out.write_string(
    "{\"schema_version\":3,\"kind\":\"moonlibsync-dir-bundle\",\"summary\":{\"unchanged\":\"\{bundle.unchanged_count}\",\"add_full\":\"\{bundle.add_full_count}\",\"update_delta\":\"\{bundle.update_delta_count}\",\"update_full\":\"\{bundle.update_full_count}\",\"delete\":\"\{bundle.delete_count}\"",
  )
  if bundle.copy_from_basis_count > 0L {
    out.write_string(",\"copy_from_basis\":\"\{bundle.copy_from_basis_count}\"")
  }
  out.write_string(
    ",\"total_payload_bytes\":\"\{bundle.total_payload_bytes}\"},\"entries\":[",
  )
  for i in 0..<bundle.entries.length() {
    if i > 0 {
      out.write_char(',')
    }
    let e = bundle.entries[i]
    let p = json_escape_string(e.path)
    match e.action {
      Unchanged(d) =>
        out.write_string(
          "{\"path\":\"\{p}\",\"kind\":\"unchanged\",\"basis\":\{file_digest_json(d)}}",
        )
      AddFull(payload_path, target) =>
        out.write_string(
          "{\"path\":\"\{p}\",\"kind\":\"add-full\",\"payload_path\":\"\{json_escape_string(payload_path)}\",\"target\":\{file_digest_json(target)}}",
        )
      UpdateDelta(payload_path, m) =>
        out.write_string(
          "{\"path\":\"\{p}\",\"kind\":\"update-delta\",\"payload_path\":\"\{json_escape_string(payload_path)}\",\"basis\":\{file_digest_json(m.basis)},\"signature\":\{file_digest_json(m.signature)},\"delta\":\{file_digest_json(m.delta)},\"result\":\{file_digest_json(m.result)}}",
        )
      UpdateFull(payload_path, basis, target) =>
        out.write_string(
          "{\"path\":\"\{p}\",\"kind\":\"update-full\",\"payload_path\":\"\{json_escape_string(payload_path)}\",\"basis\":\{file_digest_json(basis)},\"target\":\{file_digest_json(target)}}",
        )
      Delete(basis) =>
        out.write_string(
          "{\"path\":\"\{p}\",\"kind\":\"delete\",\"basis\":\{file_digest_json(basis)}}",
        )
      CopyFromBasis(source_path, target) =>
        out.write_string(
          "{\"path\":\"\{p}\",\"kind\":\"copy-from-basis\",\"source_path\":\"\{json_escape_string(source_path)}\",\"target\":\{file_digest_json(target)}}",
        )
      UpdateDeltaFrom(source_path, payload_path, m) =>
        out.write_string(
          "{\"path\":\"\{p}\",\"kind\":\"update-delta-from\",\"source_path\":\"\{json_escape_string(source_path)}\",\"payload_path\":\"\{json_escape_string(payload_path)}\",\"basis\":\{file_digest_json(m.basis)},\"signature\":\{file_digest_json(m.signature)},\"delta\":\{file_digest_json(m.delta)},\"result\":\{file_digest_json(m.result)}}",
        )
    }
  }
  out.write_string("]}\n")
  let encoded = @utf8.encode(out.to_string())
  guard encoded.length().to_int64() <= bundle_json_budget(dir_limits) else {
    raise ManifestError::ResourceLimit("bundle_bytes")
  }
  encoded
}

///|
/// Parse and strictly validate a Schema 3 `moonlibsync-dir-bundle` JSON document.
pub fn parse_dir_bundle_manifest(
  input : Bytes,
  dir_limits : DirLimits,
  limits : Limits,
) -> DirBundleManifest raise ManifestError {
  dir_limits.validate()
  manifest_limits(limits)
  let tree = dir_json_tree(
    input,
    bundle_json_budget(dir_limits),
    "bundle_bytes",
    5,
  )
  let fields = manifest_object(tree, [
    "schema_version", "kind", "summary", "entries",
  ])
  dir_schema3_header(fields, "moonlibsync-dir-bundle")
  let raw_sum = manifest_get(fields, "summary")
  guard raw_sum is @json.Json::Object(raw_sum_map) else {
    raise ManifestError::InvalidSchema
  }
  let has_cfb = raw_sum_map.contains("copy_from_basis")
  let sum_fields = if has_cfb {
    manifest_object(raw_sum, [
      "unchanged", "add_full", "update_delta", "update_full", "delete", "copy_from_basis",
      "total_payload_bytes",
    ])
  } else {
    manifest_object(raw_sum, [
      "unchanged", "add_full", "update_delta", "update_full", "delete", "total_payload_bytes",
    ])
  }
  let unchanged_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "unchanged"), "unchanged"),
  )
  let add_full_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "add_full"), "add_full"),
  )
  let update_delta_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "update_delta"), "update_delta"),
  )
  let update_full_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "update_full"), "update_full"),
  )
  let delete_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "delete"), "delete"),
  )
  let copy_from_basis_count = if has_cfb {
    manifest_decimal(
      manifest_string(
        manifest_get(sum_fields, "copy_from_basis"),
        "copy_from_basis",
      ),
    )
  } else {
    0L
  }
  let total_payload_bytes = manifest_decimal(
    manifest_string(
      manifest_get(sum_fields, "total_payload_bytes"),
      "total_payload_bytes",
    ),
  )
  guard manifest_get(fields, "entries") is @json.Json::Array(raw_entries) else {
    raise ManifestError::InvalidSchema
  }
  guard raw_entries.length().to_int64() <= dir_limits.max_entries * 2L else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let entries : Array[DirBundleEntry] = Array(capacity=raw_entries.length())
  for item in raw_entries {
    guard item is @json.Json::Object(ef) else {
      raise ManifestError::InvalidSchema
    }
    let kind_str = manifest_string(manifest_get(ef, "kind"), "kind")
    let path = manifest_string(manifest_get(ef, "path"), "path")
    let action : DirBundleAction = if kind_str == "unchanged" {
      let f = manifest_object(item, ["path", "kind", "basis"])
      Unchanged(parse_file_digest(manifest_get(f, "basis")))
    } else if kind_str == "add-full" {
      let f = manifest_object(item, ["path", "kind", "payload_path", "target"])
      AddFull(
        manifest_string(manifest_get(f, "payload_path"), "payload_path"),
        parse_file_digest(manifest_get(f, "target")),
      )
    } else if kind_str == "update-delta" {
      let f = manifest_object(item, [
        "path", "kind", "payload_path", "basis", "signature", "delta", "result",
      ])
      UpdateDelta(
        manifest_string(manifest_get(f, "payload_path"), "payload_path"),
        {
          basis: parse_file_digest(manifest_get(f, "basis")),
          signature: parse_file_digest(manifest_get(f, "signature")),
          delta: parse_file_digest(manifest_get(f, "delta")),
          result: parse_file_digest(manifest_get(f, "result")),
        },
      )
    } else if kind_str == "update-full" {
      let f = manifest_object(item, [
        "path", "kind", "payload_path", "basis", "target",
      ])
      UpdateFull(
        manifest_string(manifest_get(f, "payload_path"), "payload_path"),
        parse_file_digest(manifest_get(f, "basis")),
        parse_file_digest(manifest_get(f, "target")),
      )
    } else if kind_str == "delete" {
      let f = manifest_object(item, ["path", "kind", "basis"])
      Delete(parse_file_digest(manifest_get(f, "basis")))
    } else if kind_str == "copy-from-basis" {
      let f = manifest_object(item, ["path", "kind", "source_path", "target"])
      CopyFromBasis(
        manifest_string(manifest_get(f, "source_path"), "source_path"),
        parse_file_digest(manifest_get(f, "target")),
      )
    } else if kind_str == "update-delta-from" {
      let f = manifest_object(item, [
        "path", "kind", "source_path", "payload_path", "basis", "signature", "delta",
        "result",
      ])
      UpdateDeltaFrom(
        manifest_string(manifest_get(f, "source_path"), "source_path"),
        manifest_string(manifest_get(f, "payload_path"), "payload_path"),
        {
          basis: parse_file_digest(manifest_get(f, "basis")),
          signature: parse_file_digest(manifest_get(f, "signature")),
          delta: parse_file_digest(manifest_get(f, "delta")),
          result: parse_file_digest(manifest_get(f, "result")),
        },
      )
    } else {
      raise ManifestError::InvalidSchema
    }
    entries.push({ path, action, })
  }
  let bundle : DirBundleManifest = {
    entries,
    unchanged_count,
    add_full_count,
    update_delta_count,
    update_full_count,
    delete_count,
    copy_from_basis_count,
    total_payload_bytes,
  }
  validate_dir_bundle_manifest(bundle, dir_limits, limits)
  bundle
}

///|
fn split_posix_path(path : String) -> Array[String] {
  let parts : Array[String] = []
  let cur = StringBuilder()
  for c in path {
    if c == '/' {
      parts.push(cur.to_string())
      cur.reset()
    } else {
      cur.write_char(c)
    }
  }
  parts.push(cur.to_string())
  parts
}

///|
fn validate_exclude_pattern(pattern : String) -> Unit raise ManifestError {
  let utf8_len = @utf8.encode(pattern).length()
  guard utf8_len > 0 && utf8_len <= 256 else {
    raise ManifestError::Core(InvalidOptions("exclude"))
  }
  guard !pattern.has_prefix("/") &&
    !pattern.has_suffix("/") &&
    !pattern.contains("//") &&
    !pattern.contains("\\") &&
    !pattern.contains(":") else {
    raise ManifestError::Core(InvalidOptions("exclude"))
  }
  for c in pattern {
    let code = c.to_int()
    guard code >= 32 && code != 127 else {
      raise ManifestError::Core(InvalidOptions("exclude"))
    }
  }
  for seg in split_posix_path(pattern) {
    guard seg.length() > 0 && seg != "." && seg != ".." else {
      raise ManifestError::Core(InvalidOptions("exclude"))
    }
  }
}

///|
/// Iterative bounded single-segment glob matcher supporting `*` and `?`
/// without recursion or exponential backtracking.
fn glob_match_segment(text : String, pat : String) -> Bool {
  let t = text.to_array()
  let p = pat.to_array()
  let mut ti = 0
  let mut pi = 0
  let mut star_pi = -1
  let mut star_ti = 0
  while ti < t.length() {
    if pi < p.length() && (p[pi] == '?' || p[pi] == t[ti]) {
      ti = ti + 1
      pi = pi + 1
    } else if pi < p.length() && p[pi] == '*' {
      star_pi = pi
      star_ti = ti
      pi = pi + 1
    } else if star_pi >= 0 {
      pi = star_pi + 1
      star_ti = star_ti + 1
      ti = star_ti
    } else {
      return false
    }
  }
  while pi < p.length() && p[pi] == '*' {
    pi = pi + 1
  }
  pi == p.length()
}

///|
/// Parse a `.moonlibsyncignore`-style exclude file (UTF-8 without BOM, bounded by
/// `max_snapshot_bytes`, ignoring blank lines and `#` comments, validating every
/// pattern with `validate_exclude_pattern`).
pub fn parse_dir_exclude_file(
  input : Bytes,
  limits : DirLimits,
) -> Array[String] raise ManifestError {
  limits.validate()
  guard input.length().to_int64() <= limits.max_snapshot_bytes else {
    raise ManifestError::ResourceLimit("exclude_file_bytes")
  }
  if input.length() >= 3 &&
    input[0] == b'\xef' &&
    input[1] == b'\xbb' &&
    input[2] == b'\xbf' {
    raise ManifestError::InvalidField("exclude_file_bom")
  }
  let text = @utf8.decode(input[:]) catch {
    _ => raise ManifestError::InvalidField("exclude_file_utf8")
  }
  let patterns : Array[String] = []
  let line_buf = StringBuilder()
  let mut idx = 0
  let chars = text.to_array()
  while idx <= chars.length() {
    let at_end = idx == chars.length()
    if at_end || chars[idx] == '\n' {
      let raw_line = line_buf.to_string()
      line_buf.reset()
      let line_chars = raw_line.to_array()
      let mut s = 0
      let mut e = line_chars.length()
      if e > 0 && line_chars[e - 1] == '\r' {
        e = e - 1
      }
      while s < e && (line_chars[s] == ' ' || line_chars[s] == '\t') {
        s = s + 1
      }
      while e > s && (line_chars[e - 1] == ' ' || line_chars[e - 1] == '\t') {
        e = e - 1
      }
      if s < e && line_chars[s] != '#' {
        let pat_buf = StringBuilder()
        for k in s..<e {
          pat_buf.write_char(line_chars[k])
        }
        let pat = pat_buf.to_string()
        validate_exclude_pattern(pat)
        guard patterns.length() < 4096 else {
          raise ManifestError::ResourceLimit("exclude_patterns")
        }
        patterns.push(pat)
      }
    } else {
      line_buf.write_char(chars[idx])
    }
    idx = idx + 1
  }
  patterns
}

///|
/// Match a POSIX relative path against an exclude pattern.
/// Single-segment patterns (for example `.git`, `node_modules`, `*.log`) match
/// any segment along `rel_posix`; multi-segment patterns (for example `dist/*`)
/// match prefix segments from the root. Rejects invalid patterns with
/// `ManifestError::Core(InvalidOptions("exclude"))`.
pub fn match_dir_exclude(
  rel_posix : String,
  pattern : String,
) -> Bool raise ManifestError {
  validate_exclude_pattern(pattern)
  guard rel_posix.length() > 0 else { return false }
  let rsegs = split_posix_path(rel_posix)
  let psegs = split_posix_path(pattern)
  if psegs.length() == 1 {
    let p = psegs[0]
    for seg in rsegs {
      if glob_match_segment(seg, p) {
        return true
      }
    }
    false
  } else {
    if rsegs.length() < psegs.length() {
      return false
    }
    for i in 0..<psegs.length() {
      if !glob_match_segment(rsegs[i], psegs[i]) {
        return false
      }
    }
    true
  }
}

///|
/// Mismatch category reported by `verify_dir_snapshot`.
pub(all) enum DirVerifyDiffKind {
  Modified
  Missing
  Extra
}

///|
pub(all) struct DirVerifyIssue {
  path : String
  kind : DirVerifyDiffKind
  expected : FileDigest?
  actual : FileDigest?
}

///|
/// Deterministic Schema 3 directory verification report comparing an expected
/// snapshot against an observed snapshot.
pub(all) struct DirVerifyReport {
  ok : Bool
  matched_count : Int64
  modified_count : Int64
  missing_count : Int64
  extra_count : Int64
  issues : Array[DirVerifyIssue]
}

///|
fn validate_dir_verify_report(
  report : DirVerifyReport,
  limits : DirLimits,
) -> Unit raise ManifestError {
  limits.validate()
  guard report.matched_count >= 0L && report.matched_count <= limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  guard report.issues.length().to_int64() <= limits.max_entries * 2L else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let seen_lower : Map[String, String] = Map([])
  let expected_paths : Array[String] = []
  let actual_paths : Array[String] = []
  let mut modified = 0L
  let mut missing = 0L
  let mut extra = 0L
  for i in 0..<report.issues.length() {
    let item = report.issues[i]
    validate_dir_path(item.path, limits)
    let lower = ascii_lower(item.path)
    guard !seen_lower.contains(lower) else {
      raise ManifestError::InvalidField("path_collision")
    }
    seen_lower[lower] = item.path
    if i > 0 {
      guard lexical_path_compare(report.issues[i - 1].path, item.path) < 0 else {
        raise ManifestError::InvalidField("path_order")
      }
    }
    match item.kind {
      Modified => {
        guard item.expected is Some(e) && item.actual is Some(a) else {
          raise ManifestError::InvalidField("issue")
        }
        validate_file_digest(e, 0L, limits.max_file_bytes, "expected")
        validate_file_digest(a, 0L, limits.max_file_bytes, "actual")
        guard !same_digest(e, a) else {
          raise ManifestError::BindingMismatch("verify_digest")
        }
        expected_paths.push(item.path)
        actual_paths.push(item.path)
        modified = modified + 1L
      }
      Missing => {
        guard item.expected is Some(e) && item.actual is None else {
          raise ManifestError::InvalidField("issue")
        }
        validate_file_digest(e, 0L, limits.max_file_bytes, "expected")
        expected_paths.push(item.path)
        missing = missing + 1L
      }
      Extra => {
        guard item.expected is None && item.actual is Some(a) else {
          raise ManifestError::InvalidField("issue")
        }
        validate_file_digest(a, 0L, limits.max_file_bytes, "actual")
        actual_paths.push(item.path)
        extra = extra + 1L
      }
    }
  }
  let (_, exp_dirs) = validate_tree_paths(expected_paths, "path_collision")
  let (_, act_dirs) = validate_tree_paths(actual_paths, "path_collision")
  check_cross_tree_dir_case(exp_dirs, act_dirs, "path_collision")
  guard report.matched_count + modified + missing <= limits.max_entries &&
    report.matched_count + modified + extra <= limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let expected_ok = modified == 0L && missing == 0L && extra == 0L
  guard report.ok == expected_ok &&
    report.modified_count == modified &&
    report.missing_count == missing &&
    report.extra_count == extra else {
    raise ManifestError::BindingMismatch("verify_summary")
  }
}

///|
/// Compare an observed directory snapshot (`actual`) against an expected
/// snapshot (`expected`) in deterministic sorted order.
pub fn verify_dir_snapshot(
  expected : DirSnapshot,
  actual : DirSnapshot,
  limits : DirLimits,
) -> DirVerifyReport raise ManifestError {
  let plan = plan_dir_sync(expected, actual, limits)
  let issues : Array[DirVerifyIssue] = []
  let mut matched_count = 0L
  let mut modified_count = 0L
  let mut missing_count = 0L
  let mut extra_count = 0L
  for act in plan.actions {
    match act.kind {
      Unchanged => matched_count = matched_count + 1L
      UpdateCandidate => {
        issues.push({
          path: act.path,
          kind: Modified,
          expected: act.basis,
          actual: act.target,
        })
        modified_count = modified_count + 1L
      }
      Delete => {
        issues.push({
          path: act.path,
          kind: Missing,
          expected: act.basis,
          actual: None,
        })
        missing_count = missing_count + 1L
      }
      AddFull | CopyFromBasis(_) => {
        issues.push({
          path: act.path,
          kind: Extra,
          expected: None,
          actual: act.target,
        })
        extra_count = extra_count + 1L
      }
    }
  }
  {
    ok: issues.length() == 0,
    matched_count,
    modified_count,
    missing_count,
    extra_count,
    issues,
  }
}

///|
fn verify_kind_label(kind : DirVerifyDiffKind) -> String {
  match kind {
    Modified => "modified"
    Missing => "missing"
    Extra => "extra"
  }
}

///|
/// Revalidate and deterministically encode a Schema 3 `moonlibsync-dir-verify` JSON document.
pub fn encode_dir_verify_report(
  report : DirVerifyReport,
  limits : DirLimits,
) -> Bytes raise ManifestError {
  validate_dir_verify_report(report, limits)
  let out = StringBuilder()
  out.write_string(
    "{\"schema_version\":3,\"kind\":\"moonlibsync-dir-verify\",\"ok\":\{report.ok},\"summary\":{\"matched\":\"\{report.matched_count}\",\"modified\":\"\{report.modified_count}\",\"missing\":\"\{report.missing_count}\",\"extra\":\"\{report.extra_count}\"},\"issues\":[",
  )
  for i in 0..<report.issues.length() {
    if i > 0 {
      out.write_char(',')
    }
    let item = report.issues[i]
    out.write_string(
      "{\"path\":\"\{json_escape_string(item.path)}\",\"kind\":\"\{verify_kind_label(item.kind)}\"",
    )
    match item.expected {
      Some(e) => out.write_string(",\"expected\":\{file_digest_json(e)}")
      None => ()
    }
    match item.actual {
      Some(a) => out.write_string(",\"actual\":\{file_digest_json(a)}")
      None => ()
    }
    out.write_char('}')
  }
  out.write_string("]}\n")
  let encoded = @utf8.encode(out.to_string())
  guard encoded.length().to_int64() <= plan_json_budget(limits) else {
    raise ManifestError::ResourceLimit("verify_bytes")
  }
  encoded
}

///|
/// Parse and strictly validate a Schema 3 `moonlibsync-dir-verify` JSON document.
pub fn parse_dir_verify_report(
  input : Bytes,
  limits : DirLimits,
) -> DirVerifyReport raise ManifestError {
  limits.validate()
  let tree = dir_json_tree(input, plan_json_budget(limits), "verify_bytes", 4)
  let fields = manifest_object(tree, [
    "schema_version", "kind", "ok", "summary", "issues",
  ])
  dir_schema3_header(fields, "moonlibsync-dir-verify")
  let ok = match manifest_get(fields, "ok") {
    @json.Json::True => true
    @json.Json::False => false
    _ => raise ManifestError::InvalidSchema
  }
  let sum_fields = manifest_object(manifest_get(fields, "summary"), [
    "matched", "modified", "missing", "extra",
  ])
  let matched_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "matched"), "matched"),
  )
  let modified_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "modified"), "modified"),
  )
  let missing_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "missing"), "missing"),
  )
  let extra_count = manifest_decimal(
    manifest_string(manifest_get(sum_fields, "extra"), "extra"),
  )
  guard manifest_get(fields, "issues") is @json.Json::Array(raw_issues) else {
    raise ManifestError::InvalidSchema
  }
  guard raw_issues.length().to_int64() <= limits.max_entries * 2L else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let issues : Array[DirVerifyIssue] = Array(capacity=raw_issues.length())
  for item in raw_issues {
    guard item is @json.Json::Object(obj) else {
      raise ManifestError::InvalidSchema
    }
    let kind_str = manifest_string(manifest_get(obj, "kind"), "kind")
    let path = manifest_string(manifest_get(obj, "path"), "path")
    let (kind, expected, actual) = if kind_str == "modified" {
      let f = manifest_object(item, ["path", "kind", "expected", "actual"])
      (
        DirVerifyDiffKind::Modified,
        Some(parse_file_digest(manifest_get(f, "expected"))),
        Some(parse_file_digest(manifest_get(f, "actual"))),
      )
    } else if kind_str == "missing" {
      let f = manifest_object(item, ["path", "kind", "expected"])
      (
        DirVerifyDiffKind::Missing,
        Some(parse_file_digest(manifest_get(f, "expected"))),
        None,
      )
    } else if kind_str == "extra" {
      let f = manifest_object(item, ["path", "kind", "actual"])
      (
        DirVerifyDiffKind::Extra,
        None,
        Some(parse_file_digest(manifest_get(f, "actual"))),
      )
    } else {
      raise ManifestError::InvalidSchema
    }
    issues.push({ path, kind, expected, actual, })
  }
  let report : DirVerifyReport = {
    ok,
    matched_count,
    modified_count,
    missing_count,
    extra_count,
    issues,
  }
  validate_dir_verify_report(report, limits)
  report
}
