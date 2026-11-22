// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn split_posix_segments(rel_posix : String) -> Array[String] {
  let parts : Array[String] = []
  let cur = StringBuilder()
  for c in rel_posix {
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
fn join_rel_posix(root : String, rel_posix : String) -> String {
  let mut p = @path.Path(root)
  for seg in split_posix_segments(rel_posix) {
    p = p.join(@path.Path(seg))
  }
  p.to_string()
}

///|
fn zero_pad6(index : Int32) -> String {
  let s = index.to_string()
  if s.length() >= 6 {
    s
  } else {
    let out = StringBuilder()
    for _ in 0..<(6 - s.length()) {
      out.write_char('0')
    }
    out.write_string(s)
    out.to_string()
  }
}

///|
/// Verify `root_dir` and every intermediate segment of `rel_posix` are real
/// directories (no symlinks), and that the leaf is a real regular file.
async fn resolve_safe_regular_under(
  root_dir : String,
  rel_posix : String,
) -> String {
  guard @fs.kind(root_dir, follow_symlink=false) is @fs.FileKind::Directory else {
    raise FileFailure("unsupported directory or symlink root: " + root_dir)
  }
  let segs = split_posix_segments(rel_posix)
  let mut cur = @path.Path(root_dir)
  for i in 0..<segs.length() {
    let seg = segs[i]
    guard seg.length() > 0 && seg != "." && seg != ".." else {
      raise @lib.ManifestError::InvalidField("path")
    }
    cur = cur.join(@path.Path(seg))
    let cur_str = cur.to_string()
    let kind = @fs.kind(cur_str, follow_symlink=false)
    if i + 1 < segs.length() {
      guard kind is @fs.FileKind::Directory else {
        raise FileFailure("non-directory or symlink path segment: " + cur_str)
      }
    } else {
      guard kind is @fs.FileKind::Regular else {
        raise FileFailure("unsupported file kind or symlink: " + cur_str)
      }
    }
  }
  cur.to_string()
}

///|
async fn ensure_staged_parent_dirs(
  staging_root : String,
  rel_posix : String,
) -> Unit {
  let segs = split_posix_segments(rel_posix)
  let mut cur = @path.Path(staging_root)
  for i in 0..<(segs.length() - 1) {
    cur = cur.join(@path.Path(segs[i]))
    let cur_str = cur.to_string()
    @fs.mkdir(cur_str, permission=0o700, recursive=false, allow_exist=true)
    guard @fs.kind(cur_str, follow_symlink=false) is @fs.FileKind::Directory else {
      raise FileFailure("staging parent is not a directory: " + cur_str)
    }
  }
}

///|
/// Create an isolated staging directory in `output_dir`'s parent, run `builder`,
/// and atomically rename into `output_dir` with `replace=false`.
/// Refuses existing `output_dir` and cleans up staging on any failure.
async fn publish_dir(
  operation : String,
  output_dir : String,
  builder : async (String) -> Unit,
) -> Unit {
  let final_path = prepare_output(output_dir)
  let staging = unique_temp_path(final_path)
  @fs.mkdir(staging, permission=0o700, recursive=false, allow_exist=false)
  try {
    builder(staging)
    @fs.rename(staging, final_path, replace=false)
  } catch {
    error => {
      let detail = stream_error_detail(error)
      @fs.rmdir(staging, recursive=true, allow_missing=true) catch {
        cleanup_error =>
          raise FileFailure(
            operation +
            " '" +
            output_dir +
            "': " +
            detail +
            "; cleanup failed '" +
            staging +
            "': \{cli_error_text(cleanup_error)}",
          )
      }
      raise FileFailure(operation + " '" + output_dir + "': " + detail)
    }
  }
}

///|
async fn stream_copy_verified_file(
  src_path : String,
  dst_path : String,
  expected : @lib.FileDigest,
  max_bytes : Int64,
  field_prefix : String,
) -> Unit {
  let src_file = open_regular_input(src_path)
  defer src_file.close()
  let size = check_open_regular_sized(src_file, src_path, max_bytes)
  guard size == expected.byte_length else {
    raise @lib.ManifestError::BindingMismatch(field_prefix + "_length")
  }
  let hasher = @lib.Sha256Hasher::new(max_bytes)
  let dst_file = @fs.open(
    dst_path,
    mode=WriteOnly,
    create_mode=CreateNew,
    permission=0o600,
  )
  let mut opened = true
  errdefer (if opened { dst_file.close() })
  stream_open_chunks(src_file, src_path, size, chunk => {
    hasher.update(chunk)
    write_nonempty(dst_file, chunk)
  })
  sync_content(dst_file)
  dst_file.close()
  opened = false
  let actual = hasher.finish()
  guard actual.sha256 == expected.sha256 else {
    raise @lib.ManifestError::BindingMismatch(field_prefix + "_sha256")
  }
}

///|
fn resolve_file_sig_options(
  plan : Plan,
  file_size : Int64,
  limits : @lib.Limits,
) -> @lib.SignatureOptions raise @lib.SyncError {
  let block = match plan.block_choice {
    Explicit(v) => v
    Auto =>
      @lib.recommend_block_len(file_size, plan.options.strong_sum_len, limits)
  }
  { block_len: block, strong_sum_len: plan.options.strong_sum_len, }
}

///|
async fn write_single_dir_signature(
  plan : Plan,
  src_path : String,
  sig_dst : String,
  expected_basis : @lib.FileDigest,
  limits : @lib.Limits,
) -> @lib.FileDigest {
  let max_old = if plan.dir_limits.max_file_bytes < limits.max_old_bytes {
    plan.dir_limits.max_file_bytes
  } else {
    limits.max_old_bytes
  }
  if plan.streaming {
    let src_file = open_regular_input(src_path)
    defer src_file.close()
    let size = check_open_regular_sized(src_file, src_path, max_old)
    guard size == expected_basis.byte_length else {
      raise @lib.ManifestError::BindingMismatch("basis_length")
    }
    let opts = resolve_file_sig_options(plan, size, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let sig_hasher = @lib.SignatureHasher::new(opts, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let basis_sha = @lib.Sha256Hasher::new(max_old)
    let sig_sha = @lib.Sha256Hasher::new(limits.max_signature_bytes)
    let out_file = @fs.open(
      sig_dst,
      mode=WriteOnly,
      create_mode=CreateNew,
      permission=0o600,
    )
    let mut opened = true
    errdefer (if opened { out_file.close() })
    async fn emit(data : Bytes) -> Unit {
      if data.length() > 0 {
        sig_sha.update(data[:])
        out_file.write(data[:])
      }
    }
    emit(sig_hasher.take_ready())
    stream_open_chunks(src_file, src_path, size, chunk => {
      basis_sha.update(chunk)
      sig_hasher.update(chunk) catch {
        error => raise @lib.ManifestError::Core(error)
      }
      emit(sig_hasher.take_ready())
    })
    let tail = sig_hasher.finish() catch {
      error => raise @lib.ManifestError::Core(error)
    }
    emit(tail)
    sync_content(out_file)
    out_file.close()
    opened = false
    let actual_basis = basis_sha.finish()
    guard actual_basis.sha256 == expected_basis.sha256 else {
      raise @lib.ManifestError::BindingMismatch("basis_sha256")
    }
    sig_sha.finish()
  } else {
    let old = bounded_read(src_path, max_old)
    guard old.length().to_int64() == expected_basis.byte_length else {
      raise @lib.ManifestError::BindingMismatch("basis_length")
    }
    let basis_sha = @lib.Sha256Hasher::new(max_old)
    basis_sha.update(old[:])
    let actual_basis = basis_sha.finish()
    guard actual_basis.sha256 == expected_basis.sha256 else {
      raise @lib.ManifestError::BindingMismatch("basis_sha256")
    }
    let opts = resolve_file_sig_options(plan, actual_basis.byte_length, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let sig = @lib.signature(old, opts, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let sig_sha = @lib.Sha256Hasher::new(limits.max_signature_bytes)
    sig_sha.update(sig[:])
    let sig_digest = sig_sha.finish()
    @fs.write_binary(sig_dst, sig[:], create_mode=CreateNew, permission=0o600)
    sig_digest
  }
}

///|
async fn execute_dir_signatures(plan : Plan, sig_dir : String) -> Unit {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
  limits.validate()
  dir_limits.validate()
  let root_dir = plan.inputs[0]
  let snap_path = plan.inputs[1]
  guard @fs.kind(root_dir, follow_symlink=false) is @fs.FileKind::Directory else {
    raise FileFailure(
      "unsupported input kind or symlink directory: " + root_dir,
    )
  }
  let snap_bytes = bounded_read(snap_path, dir_limits.max_snapshot_bytes)
  let snapshot = @lib.parse_dir_snapshot(snap_bytes, dir_limits)
  publish_dir("dir-signatures", sig_dir, staging => {
    let sigs_dir = @path.Path(staging).join(@path.Path("sigs")).to_string()
    @fs.mkdir(sigs_dir, permission=0o700, recursive=false, allow_exist=false)
    let entries : Array[@lib.DirSignatureEntry] = Array(
      capacity=snapshot.entries.length(),
    )
    for i in 0..<snapshot.entries.length() {
      let item = snapshot.entries[i]
      let src_path = resolve_safe_regular_under(root_dir, item.path)
      let sig_rel = "sigs/" + zero_pad6(i) + ".sig"
      let sig_dst = join_rel_posix(staging, sig_rel)
      let sig_digest = write_single_dir_signature(
        plan,
        src_path,
        sig_dst,
        item.digest,
        limits,
      )
      entries.push({
        path: item.path,
        basis: item.digest,
        signature_path: sig_rel,
        signature: sig_digest,
      })
    }
    let index = @lib.create_dir_signature_index(entries, dir_limits, limits)
    let encoded = @lib.encode_dir_signature_index(index, dir_limits, limits)
    let index_dst = @path.Path(staging)
      .join(@path.Path("signatures.json"))
      .to_string()
    @fs.write_binary(
      index_dst,
      encoded[:],
      create_mode=CreateNew,
      permission=0o600,
    )
  })
}

///|
async fn pack_update_candidate(
  plan : Plan,
  sig_dir : String,
  target_src : String,
  staging : String,
  payload_idx : Int32,
  basis : @lib.FileDigest,
  target : @lib.FileDigest,
  sig_entry : @lib.DirSignatureEntry,
) -> @lib.DirBundleAction {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
  let max_new = if dir_limits.max_file_bytes < limits.max_new_bytes {
    dir_limits.max_file_bytes
  } else {
    limits.max_new_bytes
  }
  let sig_path = resolve_safe_regular_under(sig_dir, sig_entry.signature_path)
  let sig_bytes = bounded_read(sig_path, limits.max_signature_bytes)
  guard sig_bytes.length().to_int64() == sig_entry.signature.byte_length else {
    raise @lib.ManifestError::BindingMismatch("signature_length")
  }
  let sig_sha = @lib.Sha256Hasher::new(limits.max_signature_bytes)
  sig_sha.update(sig_bytes[:])
  let actual_sig = sig_sha.finish()
  guard actual_sig.sha256 == sig_entry.signature.sha256 else {
    raise @lib.ManifestError::BindingMismatch("signature_sha256")
  }
  let prepared = @lib.prepare_signature(sig_bytes, limits) catch {
    error => raise @lib.ManifestError::Core(error)
  }
  let delta_rel = "payloads/" + zero_pad6(payload_idx) + ".delta"
  let full_rel = "payloads/" + zero_pad6(payload_idx) + ".full"
  let delta_dst = join_rel_posix(staging, delta_rel)
  let full_dst = join_rel_posix(staging, full_rel)
  if plan.streaming {
    let target_file = open_regular_input(target_src)
    defer target_file.close()
    let new_size = check_open_regular_sized(target_file, target_src, max_new)
    guard new_size <= limits.max_output_bytes else {
      raise @lib.ManifestError::ResourceLimit("result")
    }
    guard new_size == target.byte_length else {
      raise @lib.ManifestError::BindingMismatch("target_length")
    }
    let scanner = @lib.DeltaScanner::new(prepared, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let new_sha = @lib.Sha256Hasher::new(max_new)
    let delta_sha = @lib.Sha256Hasher::new(limits.max_delta_bytes)
    let dec = @lib.PatchDecoder::new(basis.byte_length, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let out_file = @fs.open(
      delta_dst,
      mode=WriteOnly,
      create_mode=CreateNew,
      permission=0o600,
    )
    let mut opened = true
    errdefer (if opened { out_file.close() })
    async fn emit(data : Bytes) -> Unit {
      if data.length() > 0 {
        delta_sha.update(data[:])
        dec.feed_inspect(data[:]) catch {
          error => raise @lib.ManifestError::Core(error)
        }
        out_file.write(data[:])
      }
    }
    emit(scanner.take_ready())
    stream_open_chunks(target_file, target_src, new_size, chunk => {
      new_sha.update(chunk)
      scanner.feed(chunk) catch {
        error => raise @lib.ManifestError::Core(error)
      }
      emit(scanner.take_ready())
    })
    let tail = scanner.finish() catch {
      error => raise @lib.ManifestError::Core(error)
    }
    emit(tail)
    sync_content(out_file)
    out_file.close()
    opened = false
    let actual_new = new_sha.finish()
    guard actual_new.sha256 == target.sha256 else {
      raise @lib.ManifestError::BindingMismatch("target_sha256")
    }
    let summary = dec.finish() catch {
      error => raise @lib.ManifestError::Core(error)
    }
    guard summary.output_bytes == target.byte_length else {
      raise @lib.ManifestError::BindingMismatch("result_length")
    }
    let delta_digest = delta_sha.finish()
    let smaller = delta_digest.byte_length < target.byte_length
    let savings = if smaller {
      target.byte_length - delta_digest.byte_length
    } else {
      0L
    }
    if smaller && savings >= plan.min_savings {
      UpdateDelta(delta_rel, {
        basis,
        signature: sig_entry.signature,
        delta: delta_digest,
        result: target,
      })
    } else {
      @fs.remove(delta_dst, allow_missing=false)
      stream_copy_verified_file(target_src, full_dst, target, max_new, "target")
      UpdateFull(full_rel, basis, target)
    }
  } else {
    let new_bytes = bounded_read(target_src, max_new)
    guard new_bytes.length().to_int64() == target.byte_length else {
      raise @lib.ManifestError::BindingMismatch("target_length")
    }
    let new_sha = @lib.Sha256Hasher::new(max_new)
    new_sha.update(new_bytes[:])
    guard new_sha.finish().sha256 == target.sha256 else {
      raise @lib.ManifestError::BindingMismatch("target_sha256")
    }
    let cand = prepared.delta(new_bytes, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let um = @lib.create_update_manifest(
      { basis, signature: sig_entry.signature, },
      sig_bytes,
      new_bytes,
      cand,
      limits,
    )
    let smaller = um.delta.byte_length < um.result.byte_length
    let savings = if smaller {
      um.result.byte_length - um.delta.byte_length
    } else {
      0L
    }
    if smaller && savings >= plan.min_savings {
      @fs.write_binary(
        delta_dst,
        cand[:],
        create_mode=CreateNew,
        permission=0o600,
      )
      UpdateDelta(delta_rel, um)
    } else {
      @fs.write_binary(
        full_dst,
        new_bytes[:],
        create_mode=CreateNew,
        permission=0o600,
      )
      UpdateFull(full_rel, basis, target)
    }
  }
}

///|
async fn execute_dir_pack(plan : Plan, bundle_dir : String) -> Unit {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
  limits.validate()
  dir_limits.validate()
  let basis_snap_path = plan.inputs[0]
  let sig_dir = plan.inputs[1]
  let target_dir = plan.inputs[2]
  let basis_snap = @lib.parse_dir_snapshot(
    bounded_read(basis_snap_path, dir_limits.max_snapshot_bytes),
    dir_limits,
  )
  let sig_index_path = resolve_safe_regular_under(sig_dir, "signatures.json")
  let sig_index_cap = if dir_limits.max_snapshot_bytes * 4L > 67108864L {
    67108864L
  } else {
    dir_limits.max_snapshot_bytes * 4L
  }
  let sig_index = @lib.parse_dir_signature_index(
    bounded_read(sig_index_path, sig_index_cap),
    dir_limits,
    limits,
  )
  let sig_map : Map[String, @lib.DirSignatureEntry] = Map([])
  for e in sig_index.entries {
    sig_map[e.path] = e
  }
  for b in basis_snap.entries {
    match sig_map.get(b.path) {
      Some(se) => {
        guard se.basis.byte_length == b.digest.byte_length &&
          se.basis.sha256 == b.digest.sha256 else {
          raise @lib.ManifestError::BindingMismatch("signature_index")
        }
      }
      None => raise @lib.ManifestError::BindingMismatch("signature_index")
    }
  }
  guard @fs.kind(target_dir, follow_symlink=false) is @fs.FileKind::Directory else {
    raise FileFailure(
      "unsupported input kind or symlink directory: " + target_dir,
    )
  }
  let seen_lower : Map[String, String] = Map([])
  let target_entries : Array[@lib.DirEntry] = []
  collect_dir_entries(
    target_dir, "", 1L, dir_limits, seen_lower, target_entries,
  )
  let target_snap = @lib.create_dir_snapshot(target_entries, dir_limits)
  let sync_plan = @lib.plan_dir_sync(basis_snap, target_snap, dir_limits)

  let max_new = if dir_limits.max_file_bytes < limits.max_new_bytes {
    dir_limits.max_file_bytes
  } else {
    limits.max_new_bytes
  }
  publish_dir("dir-pack", bundle_dir, staging => {
    let payloads_dir = @path.Path(staging)
      .join(@path.Path("payloads"))
      .to_string()
    @fs.mkdir(
      payloads_dir,
      permission=0o700,
      recursive=false,
      allow_exist=false,
    )
    let bundle_entries : Array[@lib.DirBundleEntry] = Array(
      capacity=sync_plan.actions.length(),
    )
    let mut payload_idx = 0
    for act in sync_plan.actions {
      match act.kind {
        Unchanged => {
          guard act.basis is Some(b) else {
            raise @lib.ManifestError::InvalidField("action")
          }
          bundle_entries.push({ path: act.path, action: Unchanged(b), })
        }
        Delete => {
          guard act.basis is Some(b) else {
            raise @lib.ManifestError::InvalidField("action")
          }
          bundle_entries.push({ path: act.path, action: Delete(b), })
        }
        AddFull => {
          guard act.target is Some(t) else {
            raise @lib.ManifestError::InvalidField("action")
          }
          let target_src = resolve_safe_regular_under(target_dir, act.path)
          let payload_rel = "payloads/" + zero_pad6(payload_idx) + ".full"
          payload_idx = payload_idx + 1
          let dst = join_rel_posix(staging, payload_rel)
          stream_copy_verified_file(target_src, dst, t, max_new, "target")
          bundle_entries.push({
            path: act.path,
            action: AddFull(payload_rel, t),
          })
        }
        UpdateCandidate => {
          guard act.basis is Some(b) && act.target is Some(t) else {
            raise @lib.ManifestError::InvalidField("action")
          }
          let sig_entry = match sig_map.get(act.path) {
            Some(se) => se
            None => raise @lib.ManifestError::BindingMismatch("signature_index")
          }
          let target_src = resolve_safe_regular_under(target_dir, act.path)
          let action = pack_update_candidate(
            plan, sig_dir, target_src, staging, payload_idx, b, t, sig_entry,
          )
          payload_idx = payload_idx + 1
          bundle_entries.push({ path: act.path, action, })
        }
      }
    }
    let manifest = @lib.create_dir_bundle_manifest(
      bundle_entries, dir_limits, limits,
    )
    let encoded = @lib.encode_dir_bundle_manifest(manifest, dir_limits, limits)
    let bundle_json = @path.Path(staging)
      .join(@path.Path("bundle.json"))
      .to_string()
    @fs.write_binary(
      bundle_json,
      encoded[:],
      create_mode=CreateNew,
      permission=0o600,
    )
  })
}

///|
async fn execute_dir_apply(plan : Plan, out_dir : String) -> Unit {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
  limits.validate()
  dir_limits.validate()
  let basis_dir = plan.inputs[0]
  let bundle_dir = plan.inputs[1]
  guard @fs.kind(basis_dir, follow_symlink=false) is @fs.FileKind::Directory else {
    raise FileFailure(
      "unsupported input kind or symlink directory: " + basis_dir,
    )
  }
  let bundle_json_path = resolve_safe_regular_under(bundle_dir, "bundle.json")
  let bundle_cap = if dir_limits.max_snapshot_bytes * 8L > 67108864L {
    67108864L
  } else {
    dir_limits.max_snapshot_bytes * 8L
  }
  let bundle = @lib.parse_dir_bundle_manifest(
    bounded_read(bundle_json_path, bundle_cap),
    dir_limits,
    limits,
  )
  let max_old = if dir_limits.max_file_bytes < limits.max_old_bytes {
    dir_limits.max_file_bytes
  } else {
    limits.max_old_bytes
  }
  let max_new = if dir_limits.max_file_bytes < limits.max_new_bytes {
    dir_limits.max_file_bytes
  } else {
    limits.max_new_bytes
  }
  publish_dir("dir-apply", out_dir, staging => {
    for entry in bundle.entries {
      match entry.action {
        Delete(_) => ()
        Unchanged(expected) => {
          let src = resolve_safe_regular_under(basis_dir, entry.path)
          ensure_staged_parent_dirs(staging, entry.path)
          let dst = join_rel_posix(staging, entry.path)
          stream_copy_verified_file(src, dst, expected, max_old, "basis")
        }
        AddFull(payload_path, expected)
        | UpdateFull(payload_path, _, expected) => {
          let src = resolve_safe_regular_under(bundle_dir, payload_path)
          ensure_staged_parent_dirs(staging, entry.path)
          let dst = join_rel_posix(staging, entry.path)
          stream_copy_verified_file(src, dst, expected, max_new, "payload")
        }
        UpdateDelta(payload_path, m) => {
          let old_src = resolve_safe_regular_under(basis_dir, entry.path)
          let delta_src = resolve_safe_regular_under(bundle_dir, payload_path)
          ensure_staged_parent_dirs(staging, entry.path)
          let dst = join_rel_posix(staging, entry.path)
          if plan.streaming {
            execute_verified_streaming_delta(old_src, delta_src, dst, m, limits)
          } else {
            let old = bounded_read(old_src, max_old)
            let delta = bounded_read(delta_src, limits.max_delta_bytes)
            let restored = @lib.verified_patch(old, delta, m, limits)
            @fs.write_binary(
              dst,
              restored[:],
              create_mode=CreateNew,
              permission=0o600,
            )
          }
        }
      }
    }
  })
}

///|
async fn execute_dir_bundle_op(plan : Plan, output_dir : String) -> Unit {
  try {
    match plan.operation {
      "dir-signatures" => execute_dir_signatures(plan, output_dir)
      "dir-pack" => execute_dir_pack(plan, output_dir)
      _ => execute_dir_apply(plan, output_dir)
    }
  } catch {
    error => raise wrap_stream_error(plan, output_dir, error)
  }
}
