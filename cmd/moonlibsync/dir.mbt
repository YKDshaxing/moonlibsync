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
async fn resolve_excludes(plan : Plan) -> Array[String] {
  if plan.exclude_sources.length() == plan.excludes.length() {
    for pat in plan.excludes {
      let _ = @lib.match_dir_exclude("a", pat)
    }
    return plan.excludes
  }
  let merged : Array[String] = []
  for src in plan.exclude_sources {
    match src {
      Pattern(pat) => {
        let _ = @lib.match_dir_exclude("a", pat)
        guard merged.length() < 4096 else {
          raise @lib.ManifestError::ResourceLimit("exclude_patterns")
        }
        merged.push(pat)
      }
      File(path) => {
        let raw = bounded_read(path, plan.dir_limits.max_snapshot_bytes)
        let parsed = @lib.parse_dir_exclude_file(raw, plan.dir_limits)
        for pat in parsed {
          guard merged.length() < 4096 else {
            raise @lib.ManifestError::ResourceLimit("exclude_patterns")
          }
          merged.push(pat)
        }
      }
    }
  }
  merged
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
async fn walk_dir_candidates(
  dir_path : String,
  rel_prefix : String,
  depth : Int64,
  limits : @lib.DirLimits,
  seen_lower : Map[String, String],
  pending_files : Array[(String, String)],
  excludes : Array[String],
  empty_dirs : Array[String]?,
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
        guard pending_files.length().to_int64() < limits.max_entries else {
          raise @lib.ManifestError::ResourceLimit("dir_entries")
        }
        seen_lower[lower] = rel_path
        pending_files.push((child_path, rel_path))
      }
      @fs.FileKind::Directory => {
        seen_lower[lower] = rel_path
        walk_dir_candidates(
          child_path,
          rel_path,
          depth + 1L,
          limits,
          seen_lower,
          pending_files,
          excludes,
          empty_dirs,
        )
      }
      _ =>
        raise FileFailure(
          "unsupported directory entry kind or symlink: " + child_path,
        )
    }
  }
  if names.length() == 0 && rel_prefix != "" {
    match empty_dirs {
      Some(ed) => {
        guard ed.length().to_int64() < limits.max_entries else {
          raise @lib.ManifestError::ResourceLimit("dir_entries")
        }
        ed.push(rel_prefix)
      }
      None => ()
    }
  }
}

///|
async fn is_posix_executable(path : String) -> Bool {
  if @path.sep != '/' {
    false
  } else {
    guard @fs.kind(path, follow_symlink=false) is @fs.FileKind::Regular else {
      raise FileFailure("unsupported directory entry kind or symlink: " + path)
    }
    @fs.can_execute(path)
  }
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
  jobs~ : Int32 = 1,
  empty_dirs~ : Array[String]? = None,
  executable_paths~ : Array[String]? = None,
) -> Unit {
  let pending_files : Array[(String, String)] = []
  walk_dir_candidates(
    dir_path, rel_prefix, depth, limits, seen_lower, pending_files, excludes, empty_dirs,
  )
  let check_exec = executable_paths is Some(_)
  if jobs <= 1 || pending_files.length() <= 1 {
    for item in pending_files {
      let (child_path, rel_path) = item
      let digest = stream_hash_regular_file(
        child_path,
        limits.max_file_bytes,
        progress~,
      )
      entries.push({ path: rel_path, digest, })
      if check_exec && is_posix_executable(child_path) {
        match executable_paths {
          Some(ep) => ep.push(rel_path)
          None => ()
        }
      }
    }
  } else {
    let tasks : Array[async () -> (@lib.DirEntry, Bool)] = Array(
      capacity=pending_files.length(),
    )
    for item in pending_files {
      let (child_path, rel_path) = item
      tasks.push(async fn() {
        let digest = stream_hash_regular_file(
          child_path,
          limits.max_file_bytes,
          progress~,
        )
        let is_exec = if check_exec {
          is_posix_executable(child_path)
        } else {
          false
        }
        ({ path: rel_path, digest, }, is_exec)
      })
    }
    let hashed = @async.all(tasks, max_concurrency=jobs)
    for pair in hashed {
      let (entry, is_exec) = pair
      entries.push(entry)
      if is_exec {
        match executable_paths {
          Some(ep) => ep.push(entry.path)
          None => ()
        }
      }
    }
  }
}

///|
async fn execute_dir_snapshot(plan : Plan, output_path : String) -> Unit {
  try {
    plan.dir_limits.validate()
    let effective_excludes = resolve_excludes(plan)
    let root_dir = plan.inputs[0]
    guard @fs.kind(root_dir, follow_symlink=false) is @fs.FileKind::Directory else {
      raise FileFailure(
        "unsupported input kind or symlink directory: " + root_dir,
      )
    }
    let output = prepare_output(output_path)
    let meta_final_opt : String? = match plan.meta_out {
      Some(mp) => {
        let mf = prepare_output(mp)
        let same_path = if @path.sep != '/' {
          dir_ascii_lower(output) == dir_ascii_lower(mf)
        } else {
          output == mf
        }
        guard !same_path else {
          raise FileFailure(
            "dir-snapshot --meta-out collides with output path: " + mp,
          )
        }
        Some(mf)
      }
      None => None
    }
    let progress = make_progress(plan, -1L)
    let seen_lower : Map[String, String] = Map([])
    let entries : Array[@lib.DirEntry] = []
    let empty_dirs_arr : Array[String] = []
    let exec_paths_arr : Array[String] = []
    collect_dir_entries(
      root_dir,
      "",
      1L,
      plan.dir_limits,
      seen_lower,
      entries,
      excludes=effective_excludes,
      progress~,
      jobs=plan.jobs,
      empty_dirs=match meta_final_opt {
        Some(_) => Some(empty_dirs_arr)
        None => None
      },
      executable_paths=match meta_final_opt {
        Some(_) => Some(exec_paths_arr)
        None => None
      },
    )
    let snapshot = @lib.create_dir_snapshot(entries, plan.dir_limits)
    let encoded = @lib.encode_dir_snapshot(snapshot, plan.dir_limits)
    match meta_final_opt {
      Some(meta_final) => {
        let meta = @lib.create_dir_metadata(
          exec_paths_arr,
          empty_dirs_arr,
          plan.dir_limits,
        )
        let meta_encoded = @lib.encode_dir_metadata(meta, plan.dir_limits)
        let snap_tmp = unique_temp_path(output)
        let meta_tmp = unique_temp_path(meta_final)
        write_temp_file_synced(snap_tmp, encoded)
        let mut snap_committed = false
        errdefer {
          if !snap_committed {
            let _ = @fs.remove(snap_tmp, allow_missing=true) catch { _ => () }
          } else {
            let _ = @fs.remove(output, allow_missing=true) catch { _ => () }
          }
          let _ = @fs.remove(meta_tmp, allow_missing=true) catch { _ => () }
        }
        write_temp_file_synced(meta_tmp, meta_encoded)
        @fs.rename(snap_tmp, output, replace=false)
        snap_committed = true
        @fs.rename(meta_tmp, meta_final, replace=false)
      }
      None => publish_output(output, encoded)
    }
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
    CopyFromBasis(_) => "copy-from-basis"
  }
}

///|
fn format_dir_plan(
  plan : @lib.DirSyncPlan,
  limits : @lib.DirLimits,
  json : Bool,
  show_copy_from_basis~ : Bool = false,
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
    if show_copy_from_basis || plan.copy_from_basis_count > 0L {
      out.write_string("copy_from_basis: \{plan.copy_from_basis_count}\n")
    }
    out.write_string(
      "transfer_upper_bound_bytes: \{plan.transfer_upper_bound_bytes} bytes\n",
    )
    for a in plan.actions {
      match a.kind {
        CopyFromBasis(src) =>
          out.write_string("  copy-from-basis: \{a.path} <- \{src}\n")
        _ => out.write_string("  \{dir_action_text_tag(a.kind)}: \{a.path}\n")
      }
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
    let dir_plan = @lib.plan_dir_sync_with_options(
      basis,
      target,
      { detect_moves: plan.detect_moves, },
      limits,
    )
    (
      format_dir_plan(
        dir_plan,
        limits,
        json,
        show_copy_from_basis=plan.detect_moves,
      ),
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
    let effective_excludes = resolve_excludes(plan)
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
      excludes=effective_excludes,
      progress~,
      jobs=plan.jobs,
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
