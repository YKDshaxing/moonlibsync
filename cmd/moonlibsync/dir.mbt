// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn dir_ascii_lower(text : String) -> String {
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
async fn stream_hash_regular_file(
  path : String,
  max_file_bytes : Int64,
  progress~ : ProgressReporter? = None,
) -> @lib.FileDigest {
  let file = open_regular_input(path)
  defer file.close()
  let size = check_open_regular_sized(file, path, max_file_bytes)
  let hasher = @lib.Sha256Hasher::new(max_file_bytes)
  stream_open_chunks(file, path, size, progress~, chunk => hasher.update(chunk))
  hasher.finish()
}

///|
fn validate_excludes(excludes : Array[String]) -> Unit raise @lib.ManifestError {
  for pattern in excludes {
    let _ = @lib.match_dir_exclude("a", pattern)
  }
}

///|
fn is_excluded(
  rel_path : String,
  excludes : Array[String],
) -> Bool raise @lib.ManifestError {
  for pattern in excludes {
    if @lib.match_dir_exclude(rel_path, pattern) {
      return true
    }
  }
  false
}

///|
fn validate_rel_posix_path(
  rel_path : String,
  limits : @lib.DirLimits,
) -> Unit raise @lib.ManifestError {
  let zero_digest : @lib.FileDigest = {
    byte_length: 0L,
    sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  }
  let _ = @lib.create_dir_snapshot([{ path: rel_path, digest: zero_digest, }], {
    ..limits,
    max_entries: 1L,
  })
}

///|
async fn collect_dir_entries(
  dir_path : String,
  rel_prefix : String,
  depth : Int64,
  limits : @lib.DirLimits,
  seen_lower : Map[String, String],
  entries : Array[@lib.DirEntry],
  excludes~ : Array[String] = [],
  progress~ : ProgressReporter? = None,
) -> Unit {
  let names = @fs.readdir(
    dir_path,
    include_hidden=true,
    include_special=false,
    sort=true,
  )
  for name in names {
    guard name != "." && name != ".." && name.length() > 0 else {
      raise @lib.ManifestError::InvalidField("path")
    }
    let child_path = @path.Path(dir_path).join(@path.Path(name)).to_string()
    let rel_path = if rel_prefix == "" { name } else { rel_prefix + "/" + name }
    if excludes.length() > 0 && is_excluded(rel_path, excludes) {
      continue
    }
    guard depth <= limits.max_depth else {
      raise @lib.ManifestError::ResourceLimit("path_depth")
    }
    validate_rel_posix_path(rel_path, limits)
    let lower = dir_ascii_lower(rel_path)
    guard !seen_lower.contains(lower) else {
      raise @lib.ManifestError::InvalidField("path_collision")
    }
    let kind = @fs.kind(child_path, follow_symlink=false)
    match kind {
      @fs.FileKind::Regular => {
        guard entries.length().to_int64() < limits.max_entries else {
          raise @lib.ManifestError::ResourceLimit("dir_entries")
        }
        seen_lower[lower] = rel_path
        let digest = stream_hash_regular_file(
          child_path,
          limits.max_file_bytes,
          progress~,
        )
        entries.push({ path: rel_path, digest, })
      }
      @fs.FileKind::Directory => {
        seen_lower[lower] = rel_path
        collect_dir_entries(
          child_path,
          rel_path,
          depth + 1L,
          limits,
          seen_lower,
          entries,
          excludes~,
          progress~,
        )
      }
      _ =>
        raise FileFailure(
          "unsupported directory entry kind or symlink: " + child_path,
        )
    }
  }
}

///|
async fn execute_dir_snapshot(plan : Plan, output_path : String) -> Unit {
  try {
    plan.dir_limits.validate()
    validate_excludes(plan.excludes)
    let root_dir = plan.inputs[0]
    guard @fs.kind(root_dir, follow_symlink=false) is @fs.FileKind::Directory else {
      raise FileFailure(
        "unsupported input kind or symlink directory: " + root_dir,
      )
    }
    let output = prepare_output(output_path)
    let progress = make_progress(plan, -1L)
    let seen_lower : Map[String, String] = Map([])
    let entries : Array[@lib.DirEntry] = []
    collect_dir_entries(
      root_dir,
      "",
      1L,
      plan.dir_limits,
      seen_lower,
      entries,
      excludes=plan.excludes,
      progress~,
    )
    let snapshot = @lib.create_dir_snapshot(entries, plan.dir_limits)
    let encoded = @lib.encode_dir_snapshot(snapshot, plan.dir_limits)
    publish_output(output, encoded)
    finish_progress(progress)
  } catch {
    error =>
      match error {
        FileFailure(msg) => raise FileFailure(msg)
        Usage(msg) => raise Usage(msg)
        @lib.ManifestError::Core(_)
        | @lib.ManifestError::BindingMismatch(_)
        | @lib.ManifestError::InvalidField(_)
        | @lib.ManifestError::ResourceLimit(_)
        | @lib.ManifestError::InvalidUtf8
        | @lib.ManifestError::InvalidJson
        | @lib.ManifestError::InvalidSchema
        | @lib.ManifestError::HashFailure =>
          raise FileFailure("dir-snapshot: " + manifest_error_tag(error))
        _ =>
          raise FileFailure(
            "dir-snapshot '" + plan.inputs[0] + "': \{cli_error_text(error)}",
          )
      }
  }
}

///|
fn dir_action_text_tag(kind : @lib.DirActionKind) -> String {
  match kind {
    Unchanged => "unchanged"
    AddFull => "add-full"
    UpdateCandidate => "update-candidate"
    Delete => "delete"
  }
}

///|
fn format_dir_plan(
  plan : @lib.DirSyncPlan,
  limits : @lib.DirLimits,
  json : Bool,
) -> String raise @lib.ManifestError {
  if json {
    @utf8.decode(@lib.encode_dir_plan(plan, limits)) catch {
      _ => raise @lib.ManifestError::InvalidUtf8
    }
  } else {
    let out = StringBuilder()
    out.write_string("dir-plan\n")
    out.write_string("unchanged: \{plan.unchanged_count}\n")
    out.write_string("add: \{plan.add_count}\n")
    out.write_string("update: \{plan.update_count}\n")
    out.write_string("delete: \{plan.delete_count}\n")
    out.write_string(
      "transfer_upper_bound_bytes: \{plan.transfer_upper_bound_bytes} bytes\n",
    )
    for a in plan.actions {
      out.write_string("  \{dir_action_text_tag(a.kind)}: \{a.path}\n")
    }
    out.write_string(
      "Read-only directory sync plan; no filesystem entries were modified.\n",
    )
    out.to_string()
  }
}

///|
async fn execute_dir_plan(plan : Plan, json : Bool) -> Unit {
  let limits = plan.dir_limits
  let (text, bytes_read) = try {
    limits.validate()
    let basis_raw = bounded_read(plan.inputs[0], limits.max_snapshot_bytes)
    let target_raw = bounded_read(plan.inputs[1], limits.max_snapshot_bytes)
    let basis = @lib.parse_dir_snapshot(basis_raw, limits)
    let target = @lib.parse_dir_snapshot(target_raw, limits)
    let dir_plan = @lib.plan_dir_sync(basis, target, limits)
    (
      format_dir_plan(dir_plan, limits, json),
      basis_raw.length().to_int64() + target_raw.length().to_int64(),
    )
  } catch {
    error => {
      let detail = inspect_error_tag(error)
      raise FileFailure(
        "dir-plan inputs '\{plan.inputs.join("', '")}': " + detail,
      )
    }
  }
  write_inspection(text) catch {
    error =>
      raise FileFailure(
        "stdout dir-plan inputs '\{plan.inputs.join("', '")}': " +
        cli_error_text(error),
      )
  }
  emit_instant_progress(plan, bytes_read)
}

///|
fn dir_verify_kind_tag(kind : @lib.DirVerifyDiffKind) -> String {
  match kind {
    Modified => "modified"
    Missing => "missing"
    Extra => "extra"
  }
}

///|
fn format_dir_verify(
  report : @lib.DirVerifyReport,
  limits : @lib.DirLimits,
  json : Bool,
) -> String raise @lib.ManifestError {
  if json {
    @utf8.decode(@lib.encode_dir_verify_report(report, limits)) catch {
      _ => raise @lib.ManifestError::InvalidUtf8
    }
  } else {
    let out = StringBuilder()
    out.write_string("dir-verify\n")
    out.write_string("ok: \{report.ok}\n")
    out.write_string("matched: \{report.matched_count}\n")
    out.write_string("modified: \{report.modified_count}\n")
    out.write_string("missing: \{report.missing_count}\n")
    out.write_string("extra: \{report.extra_count}\n")
    for item in report.issues {
      out.write_string("  \{dir_verify_kind_tag(item.kind)}: \{item.path}\n")
    }
    out.write_string(
      "Read-only directory verification; no filesystem entries were modified.\n",
    )
    out.to_string()
  }
}

///|
async fn execute_dir_verify(
  plan : Plan,
  json : Bool,
  writer~ : async (Bytes) -> Unit = stdout_bytes,
) -> Unit {
  let limits = plan.dir_limits
  let progress = make_progress(plan, -1L)
  let (report, text) = try {
    limits.validate()
    validate_excludes(plan.excludes)
    let root_dir = plan.inputs[0]
    guard @fs.kind(root_dir, follow_symlink=false) is @fs.FileKind::Directory else {
      raise FileFailure(
        "unsupported input kind or symlink directory: " + root_dir,
      )
    }
    let snap_raw = bounded_read(plan.inputs[1], limits.max_snapshot_bytes)
    let expected = @lib.parse_dir_snapshot(snap_raw, limits)
    let seen_lower : Map[String, String] = Map([])
    let entries : Array[@lib.DirEntry] = []
    collect_dir_entries(
      root_dir,
      "",
      1L,
      limits,
      seen_lower,
      entries,
      excludes=plan.excludes,
      progress~,
    )
    let actual = @lib.create_dir_snapshot(entries, limits)
    let report = @lib.verify_dir_snapshot(expected, actual, limits)
    (report, format_dir_verify(report, limits, json))
  } catch {
    error => {
      let detail = inspect_error_tag(error)
      raise FileFailure(
        "dir-verify inputs '\{plan.inputs.join("', '")}': " + detail,
      )
    }
  }
  write_inspection(text, writer~) catch {
    error =>
      raise FileFailure(
        "stdout dir-verify inputs '\{plan.inputs.join("', '")}': " +
        cli_error_text(error),
      )
  }
  finish_progress(progress)
  if !report.ok {
    raise FileFailure(
      "dir-verify mismatch: modified=\{report.modified_count} missing=\{report.missing_count} extra=\{report.extra_count}",
    )
  }
}
