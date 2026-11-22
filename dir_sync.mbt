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
fn validate_snapshot_entries(
  entries : Array[DirEntry],
  limits : DirLimits,
  require_sorted~ : Bool,
) -> Map[String, String] raise ManifestError {
  limits.validate()
  guard entries.length().to_int64() <= limits.max_entries else {
    raise ManifestError::ResourceLimit("dir_entries")
  }
  let seen_lower : Map[String, String] = Map([])
  for i in 0..<entries.length() {
    let entry = entries[i]
    validate_dir_path(entry.path, limits)
    validate_file_digest(entry.digest, 0L, limits.max_file_bytes, "entry")
    let lower = ascii_lower(entry.path)
    guard !seen_lower.contains(lower) else {
      raise ManifestError::InvalidField("path_collision")
    }
    seen_lower[lower] = entry.path
    if require_sorted && i > 0 {
      guard lexical_path_compare(entries[i - 1].path, entry.path) < 0 else {
        raise ManifestError::InvalidField("path_order")
      }
    }
  }
  seen_lower
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
  let mut unchanged = 0L
  let mut add = 0L
  let mut update = 0L
  let mut del = 0L
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
        unchanged = unchanged + 1L
      }
      AddFull => {
        guard action.basis is None && action.target is Some(t) else {
          raise ManifestError::InvalidField("action")
        }
        validate_file_digest(t, 0L, limits.max_file_bytes, "target")
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
        update = update + 1L
        transfer_upper = checked_add_i64(transfer_upper, t.byte_length)
      }
      Delete => {
        guard action.basis is Some(b) && action.target is None else {
          raise ManifestError::InvalidField("action")
        }
        validate_file_digest(b, 0L, limits.max_file_bytes, "basis")
        del = del + 1L
      }
    }
  }
  guard plan.unchanged_count == unchanged &&
    plan.add_count == add &&
    plan.update_count == update &&
    plan.delete_count == del &&
    plan.transfer_upper_bound_bytes == transfer_upper else {
    raise ManifestError::BindingMismatch("plan_summary")
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
  let basis_lower = validate_snapshot_entries(
    basis.entries,
    limits,
    require_sorted=true,
  )
  let _ = validate_snapshot_entries(target.entries, limits, require_sorted=true)
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
  let actions : Array[DirSyncAction] = []
  let mut unchanged_count = 0L
  let mut add_count = 0L
  let mut update_count = 0L
  let mut delete_count = 0L
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
    j = j + 1
  }
  {
    actions,
    unchanged_count,
    add_count,
    update_count,
    delete_count,
    transfer_upper_bound_bytes,
  }
}

///|
fn action_kind_label(kind : DirActionKind) -> String {
  match kind {
    Unchanged => "unchanged"
    AddFull => "add-full"
    UpdateCandidate => "update-candidate"
    Delete => "delete"
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
    "{\"schema_version\":3,\"kind\":\"moonlibsync-dir-plan\",\"summary\":{\"unchanged\":\"\{plan.unchanged_count}\",\"add\":\"\{plan.add_count}\",\"update\":\"\{plan.update_count}\",\"delete\":\"\{plan.delete_count}\",\"transfer_upper_bound_bytes\":\"\{plan.transfer_upper_bound_bytes}\"},\"actions\":[",
  )
  for i in 0..<plan.actions.length() {
    if i > 0 {
      out.write_char(',')
    }
    let a = plan.actions[i]
    out.write_string(
      "{\"path\":\"\{json_escape_string(a.path)}\",\"kind\":\"\{action_kind_label(a.kind)}\"",
    )
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
  let sum_fields = manifest_object(manifest_get(fields, "summary"), [
    "unchanged", "add", "update", "delete", "transfer_upper_bound_bytes",
  ])
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
    transfer_upper_bound_bytes,
  }
  validate_sync_plan(plan, limits)
  plan
}
