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
fn posix_basename(rel_posix : String) -> String {
  let segs = split_posix_segments(rel_posix)
  if segs.length() == 0 {
    rel_posix
  } else {
    segs[segs.length() - 1]
  }
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
    @fs.mkdir(cur_str, permission=0o700, recursive=false, allow_existing=true)
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
  @fs.mkdir(staging, permission=0o700, recursive=false, allow_existing=false)
  try {
    builder(staging)
    @fs.rename(staging, final_path, replace=false)
  } catch {
    error => {
      let detail = stream_error_detail(error)
      @fs.remove(staging, recursive=true, allow_missing=true) catch {
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
  progress~ : ProgressReporter? = None,
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
  stream_open_chunks(src_file, src_path, size, progress~, chunk => {
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
  progress~ : ProgressReporter? = None,
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
    let sig_hasher = @lib.SignatureHasher::new_with_profile(
      opts,
      plan.sig_profile,
      limits,
    ) catch {
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
    stream_open_chunks(src_file, src_path, size, progress~, chunk => {
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
    let sig = @lib.signature_with_profile(old, opts, plan.sig_profile, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let sig_sha = @lib.Sha256Hasher::new(limits.max_signature_bytes)
    sig_sha.update(sig[:])
    let sig_digest = sig_sha.finish()
    @fs.write_binary(sig_dst, sig[:], create_mode=CreateNew, permission=0o600)
    advance_progress(progress, old.length().to_int64())
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
  let mut total_basis = 0L
  for item in snapshot.entries {
    total_basis = total_basis + item.digest.byte_length
  }
  let progress = make_progress(plan, total_basis)
  publish_dir("dir-signatures", sig_dir, staging => {
    let sigs_dir = @path.Path(staging).join(@path.Path("sigs")).to_string()
    @fs.mkdir(sigs_dir, permission=0o700, recursive=false, allow_existing=false)
    let entries : Array[@lib.DirSignatureEntry] = if plan.jobs <= 1 ||
      snapshot.entries.length() <= 1 {
      let arr : Array[@lib.DirSignatureEntry] = Array(
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
          progress~,
        )
        arr.push({
          path: item.path,
          basis: item.digest,
          signature_path: sig_rel,
          signature: sig_digest,
        })
      }
      arr
    } else {
      let tasks : Array[async () -> @lib.DirSignatureEntry] = Array(
        capacity=snapshot.entries.length(),
      )
      for i in 0..<snapshot.entries.length() {
        let item = snapshot.entries[i]
        let sig_rel = "sigs/" + zero_pad6(i) + ".sig"
        let sig_dst = join_rel_posix(staging, sig_rel)
        tasks.push(async fn() {
          let src_path = resolve_safe_regular_under(root_dir, item.path)
          let sig_digest = write_single_dir_signature(
            plan,
            src_path,
            sig_dst,
            item.digest,
            limits,
            progress~,
          )
          {
            path: item.path,
            basis: item.digest,
            signature_path: sig_rel,
            signature: sig_digest,
          }
        })
      }
      @async.all(tasks, max_concurrency=plan.jobs)
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
  finish_progress(progress)
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
  progress~ : ProgressReporter? = None,
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
    stream_open_chunks(target_file, target_src, new_size, progress~, chunk => {
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
      stream_copy_verified_file(
        target_src,
        full_dst,
        target,
        max_new,
        "target",
        progress~,
      )
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
    advance_progress(progress, new_bytes.length().to_int64())
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
async fn pack_moved_update_or_add(
  plan : Plan,
  sig_dir : String,
  source_path : String,
  target_src : String,
  staging : String,
  payload_idx : Int32,
  target : @lib.FileDigest,
  sig_entry : @lib.DirSignatureEntry,
  progress~ : ProgressReporter? = None,
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
    let dec = @lib.PatchDecoder::new(sig_entry.basis.byte_length, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let out_file = @fs.open(
      delta_dst,
      mode=WriteOnly,
      create_mode=CreateNew,
      permission=0o600,
    )
    let mut opened = true
    let mut limit_fallback = false
    try {
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
      stream_open_chunks(target_file, target_src, new_size, progress~, chunk => {
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
    } catch {
      @lib.ManifestError::Core(@lib.SyncError::LimitExceeded)
      | @lib.ManifestError::ResourceLimit(_) => {
        if opened {
          out_file.close()
          opened = false
        }
        let _ = @fs.remove(delta_dst, allow_missing=true) catch { _ => () }
        limit_fallback = true
      }
      error => {
        if opened {
          out_file.close()
        }
        raise error
      }
    }
    if limit_fallback {
      stream_copy_verified_file(
        target_src,
        full_dst,
        target,
        max_new,
        "target",
        progress~,
      )
      return AddFull(full_rel, target)
    }
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
      UpdateDeltaFrom(source_path, delta_rel, {
        basis: sig_entry.basis,
        signature: sig_entry.signature,
        delta: delta_digest,
        result: target,
      })
    } else {
      @fs.remove(delta_dst, allow_missing=false)
      stream_copy_verified_file(
        target_src,
        full_dst,
        target,
        max_new,
        "target",
        progress~,
      )
      AddFull(full_rel, target)
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
    advance_progress(progress, new_bytes.length().to_int64())
    let cand_opt : Bytes? = Some(prepared.delta(new_bytes, limits)) catch {
      @lib.SyncError::LimitExceeded => None
      error => raise @lib.ManifestError::Core(error)
    }
    match cand_opt {
      Some(cand) => {
        let um_opt : @lib.UpdateManifest? = Some(
          @lib.create_update_manifest(
            { basis: sig_entry.basis, signature: sig_entry.signature, },
            sig_bytes,
            new_bytes,
            cand,
            limits,
          ),
        ) catch {
          @lib.ManifestError::ResourceLimit(_)
          | @lib.ManifestError::Core(@lib.SyncError::LimitExceeded) => None
          error => raise error
        }
        match um_opt {
          Some(um) => {
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
              return UpdateDeltaFrom(source_path, delta_rel, um)
            }
          }
          None => ()
        }
      }
      None => ()
    }
    @fs.write_binary(
      full_dst,
      new_bytes[:],
      create_mode=CreateNew,
      permission=0o600,
    )
    AddFull(full_rel, target)
  }
}

///|
priv enum PackActionTask {
  StaticEntry(@lib.DirBundleEntry)
  PackAddFull(String, @lib.FileDigest, Int32)
  PackMovedUpdate(
    String,
    String,
    @lib.FileDigest,
    @lib.DirSignatureEntry,
    Int32,
  )
  PackUpdate(
    String,
    @lib.FileDigest,
    @lib.FileDigest,
    @lib.DirSignatureEntry,
    Int32,
  )
}

///|
async fn build_staged_bundle(
  plan : Plan,
  staging : String,
  sig_dir : String,
  target_dir : String,
  sync_plan : @lib.DirSyncPlan,
  sig_map : Map[String, @lib.DirSignatureEntry],
  progress : ProgressReporter?,
) -> @lib.DirBundleManifest {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
  let max_new = if dir_limits.max_file_bytes < limits.max_new_bytes {
    dir_limits.max_file_bytes
  } else {
    limits.max_new_bytes
  }
  let payloads_dir = @path.Path(staging)
    .join(@path.Path("payloads"))
    .to_string()
  @fs.mkdir(
    payloads_dir,
    permission=0o700,
    recursive=false,
    allow_existing=false,
  )
  let deleted_paths : Array[String] = []
  let deleted_by_basename : Map[String, Array[String]] = Map([])
  if plan.detect_moves {
    for act in sync_plan.actions {
      if act.kind is Delete && sig_map.contains(act.path) {
        deleted_paths.push(act.path)
        let base = posix_basename(act.path)
        match deleted_by_basename.get(base) {
          Some(arr) => arr.push(act.path)
          None => deleted_by_basename[base] = [act.path]
        }
      }
    }
  }
  let work_items : Array[PackActionTask] = Array(
    capacity=sync_plan.actions.length(),
  )
  let mut payload_idx = 0
  for act in sync_plan.actions {
    match act.kind {
      Unchanged => {
        guard act.basis is Some(b) else {
          raise @lib.ManifestError::InvalidField("action")
        }
        work_items.push(StaticEntry({ path: act.path, action: Unchanged(b), }))
      }
      Delete => {
        guard act.basis is Some(b) else {
          raise @lib.ManifestError::InvalidField("action")
        }
        work_items.push(StaticEntry({ path: act.path, action: Delete(b), }))
      }
      CopyFromBasis(src_path) => {
        guard act.target is Some(t) else {
          raise @lib.ManifestError::InvalidField("action")
        }
        work_items.push(
          StaticEntry({ path: act.path, action: CopyFromBasis(src_path, t), }),
        )
      }
      AddFull => {
        guard act.target is Some(t) else {
          raise @lib.ManifestError::InvalidField("action")
        }
        let assigned_idx = payload_idx
        payload_idx = payload_idx + 1
        let candidate_src : String? = if plan.detect_moves {
          match deleted_by_basename.get(posix_basename(act.path)) {
            Some(matches) if matches.length() > 0 => Some(matches[0])
            _ =>
              if deleted_paths.length() == 1 {
                Some(deleted_paths[0])
              } else {
                None
              }
          }
        } else {
          None
        }
        match candidate_src {
          Some(src_path) =>
            match sig_map.get(src_path) {
              Some(sig_entry) if src_path != act.path &&
                (
                  sig_entry.basis.byte_length != t.byte_length ||
                  sig_entry.basis.sha256 != t.sha256
                ) =>
                work_items.push(
                  PackMovedUpdate(
                    act.path,
                    src_path,
                    t,
                    sig_entry,
                    assigned_idx,
                  ),
                )
              _ => work_items.push(PackAddFull(act.path, t, assigned_idx))
            }
          None => work_items.push(PackAddFull(act.path, t, assigned_idx))
        }
      }
      UpdateCandidate => {
        guard act.basis is Some(b) && act.target is Some(t) else {
          raise @lib.ManifestError::InvalidField("action")
        }
        let sig_entry = match sig_map.get(act.path) {
          Some(se) => se
          None => raise @lib.ManifestError::BindingMismatch("signature_index")
        }
        let assigned_idx = payload_idx
        payload_idx = payload_idx + 1
        work_items.push(PackUpdate(act.path, b, t, sig_entry, assigned_idx))
      }
    }
  }
  async fn run_pack_item(item : PackActionTask) -> @lib.DirBundleEntry {
    match item {
      StaticEntry(e) => e
      PackAddFull(path, t, assigned_idx) => {
        let target_src = resolve_safe_regular_under(target_dir, path)
        let payload_rel = "payloads/" + zero_pad6(assigned_idx) + ".full"
        let dst = join_rel_posix(staging, payload_rel)
        stream_copy_verified_file(
          target_src,
          dst,
          t,
          max_new,
          "target",
          progress~,
        )
        { path, action: AddFull(payload_rel, t), }
      }
      PackMovedUpdate(path, src_path, t, sig_entry, assigned_idx) => {
        let target_src = resolve_safe_regular_under(target_dir, path)
        let action = pack_moved_update_or_add(
          plan,
          sig_dir,
          src_path,
          target_src,
          staging,
          assigned_idx,
          t,
          sig_entry,
          progress~,
        )
        { path, action, }
      }
      PackUpdate(path, b, t, sig_entry, assigned_idx) => {
        let target_src = resolve_safe_regular_under(target_dir, path)
        let action = pack_update_candidate(
          plan,
          sig_dir,
          target_src,
          staging,
          assigned_idx,
          b,
          t,
          sig_entry,
          progress~,
        )
        { path, action, }
      }
    }
  }
  let bundle_entries : Array[@lib.DirBundleEntry] = if plan.jobs <= 1 ||
    work_items.length() <= 1 {
    let arr : Array[@lib.DirBundleEntry] = Array(capacity=work_items.length())
    for item in work_items {
      arr.push(run_pack_item(item))
    }
    arr
  } else {
    let tasks : Array[async () -> @lib.DirBundleEntry] = Array(
      capacity=work_items.length(),
    )
    for item in work_items {
      tasks.push(async fn() { run_pack_item(item) })
    }
    @async.all(tasks, max_concurrency=plan.jobs)
  }
  @lib.create_dir_bundle_manifest(bundle_entries, dir_limits, limits)
}

///|
async fn write_bundle_archive_into_open_file(
  gzip : Bool,
  dir_limits : @lib.DirLimits,
  limits : @lib.Limits,
  staging : String,
  manifest : @lib.DirBundleManifest,
  tmp_file : @fs.File,
  progress : ProgressReporter?,
) -> Unit {
  let preamble = @lib.encode_bundle_archive_preamble(
    manifest, dir_limits, limits,
  )
  let expected = @lib.bundle_expected_payloads(manifest)
  if gzip {
    let enc = @compress.GzipEncoder::new(2147483647L, 2147483647L)
    let out_buf = FixedArray::make(65536, b'\x00')
    async fn write_gz(view : BytesView) -> Unit {
      let mut pos = 0
      while pos < view.length() {
        let step = enc.step(view[pos:], out_buf, finish=false)
        pos = pos + step.consumed
        if step.produced > 0 {
          write_nonempty(
            tmp_file,
            Bytes::from_array(out_buf[0:step.produced])[:],
          )
        }
        match step.status {
          NeedMoreOutput => continue
          NeedMoreInput => if pos >= view.length() { break }
          Done => break
        }
      }
    }
    write_gz(preamble[:])
    for pair in expected {
      let (payload_rel, payload_len) = pair
      let hdr = @lib.encode_bundle_payload_header(
        payload_rel, payload_len, dir_limits,
      )
      write_gz(hdr[:])
      let ppath = join_rel_posix(staging, payload_rel)
      let pfile = open_regular_input(ppath)
      defer pfile.close()
      let psize = check_open_regular_sized(pfile, ppath, 2147483647L)
      guard psize == payload_len else {
        raise @lib.ManifestError::BindingMismatch("archive_payload_length")
      }
      stream_open_chunks(pfile, ppath, psize, progress~, chunk => {
        write_gz(chunk)
      })
    }
    while true {
      let step = enc.step(b""[:], out_buf, finish=true)
      if step.produced > 0 {
        write_nonempty(tmp_file, Bytes::from_array(out_buf[0:step.produced])[:])
      }
      if step.status is Done {
        break
      }
    }
    let _ = enc.summary()
  } else {
    write_nonempty(tmp_file, preamble[:])
    for pair in expected {
      let (payload_rel, payload_len) = pair
      let hdr = @lib.encode_bundle_payload_header(
        payload_rel, payload_len, dir_limits,
      )
      write_nonempty(tmp_file, hdr[:])
      let ppath = join_rel_posix(staging, payload_rel)
      let pfile = open_regular_input(ppath)
      defer pfile.close()
      let psize = check_open_regular_sized(pfile, ppath, 2147483647L)
      guard psize == payload_len else {
        raise @lib.ManifestError::BindingMismatch("archive_payload_length")
      }
      stream_open_chunks(pfile, ppath, psize, progress~, chunk => {
        write_nonempty(tmp_file, chunk)
      })
    }
  }
}

///|
async fn write_bundle_archive_stream(
  plan : Plan,
  staging : String,
  manifest : @lib.DirBundleManifest,
  final_path : String,
  progress : ProgressReporter?,
) -> Unit {
  publish_stream(final_path, tmp_file => {
    write_bundle_archive_into_open_file(
      plan.gzip,
      plan.dir_limits,
      plan.limits,
      staging,
      manifest,
      tmp_file,
      progress,
    )
  })
}

///|
async fn execute_dir_pack(plan : Plan, bundle_out : String) -> Unit {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
  limits.validate()
  dir_limits.validate()
  let effective_excludes = resolve_excludes(plan)
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
  let progress = make_progress(plan, -1L)
  let seen_lower : Map[String, String] = Map([])
  let target_entries : Array[@lib.DirEntry] = []
  collect_dir_entries(
    target_dir,
    "",
    1L,
    dir_limits,
    seen_lower,
    target_entries,
    excludes=effective_excludes,
    progress~,
    jobs=plan.jobs,
  )
  let target_snap = @lib.create_dir_snapshot(target_entries, dir_limits)
  let sync_plan = @lib.plan_dir_sync_with_options(
    basis_snap,
    target_snap,
    { detect_moves: plan.detect_moves, },
    dir_limits,
  )
  if plan.archive {
    let final_path = prepare_output(bundle_out)
    let staging = unique_temp_path(final_path)
    @fs.mkdir(staging, permission=0o700, recursive=false, allow_existing=false)
    try {
      let manifest = build_staged_bundle(
        plan, staging, sig_dir, target_dir, sync_plan, sig_map, progress,
      )
      write_bundle_archive_stream(plan, staging, manifest, final_path, progress)
    } catch {
      error => {
        let detail = stream_error_detail(error)
        @fs.remove(staging, recursive=true, allow_missing=true) catch {
          cleanup_error =>
            raise FileFailure(
              "dir-pack '" +
              bundle_out +
              "': " +
              detail +
              "; cleanup failed '" +
              staging +
              "': \{cli_error_text(cleanup_error)}",
            )
        }
        raise FileFailure("dir-pack '" + bundle_out + "': " + detail)
      }
    }
    @fs.remove(staging, recursive=true, allow_missing=true)
    finish_progress(progress)
  } else {
    publish_dir("dir-pack", bundle_out, staging => {
      let manifest = build_staged_bundle(
        plan, staging, sig_dir, target_dir, sync_plan, sig_map, progress,
      )
      let encoded = @lib.encode_dir_bundle_manifest(
        manifest, dir_limits, limits,
      )
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
    finish_progress(progress)
  }
}

///|
async fn unpack_bundle_archive(
  plan : Plan,
  archive_path : String,
  unpack_dir : String,
  progress : ProgressReporter?,
  expected_archive_digest~ : @lib.FileDigest? = None,
) -> @lib.DirBundleManifest {
  let archive_file = open_regular_input(archive_path)
  defer archive_file.close()
  let archive_size = check_open_regular_sized(
    archive_file, archive_path, 2147483647L,
  )
  let raw_sha : @lib.Sha256Hasher? = match expected_archive_digest {
    Some(exp) => {
      guard archive_size == exp.byte_length else {
        raise @crypto.CryptoError::DigestMismatch("payload_length")
      }
      Some(@lib.Sha256Hasher::new(2147483647L))
    }
    None => None
  }
  let arch_dec = @lib.BundleArchiveDecoder::new(plan.dir_limits, plan.limits)
  let expected_digests : Map[String, @lib.FileDigest] = Map([])
  let mut active_file : @fs.File? = None
  let mut active_hasher : @lib.Sha256Hasher? = None
  let mut active_expected : @lib.FileDigest? = None
  let mut active_path = ""
  errdefer (match active_file {
    Some(f) => f.close()
    None => ()
  })
  async fn feed_archive(view : BytesView) -> Unit {
    let mut pos = 0
    while pos < view.length() || arch_dec.has_pending_event() {
      let (consumed, step) = arch_dec.step(view[pos:])
      pos = pos + consumed
      match step {
        NeedInput => ()
        Manifest(m) =>
          for entry in m.entries {
            match entry.action {
              Unchanged(_) | Delete(_) | CopyFromBasis(_, _) => ()
              AddFull(p, target) => expected_digests[p] = target
              UpdateFull(p, _, target) => expected_digests[p] = target
              UpdateDelta(p, um) | UpdateDeltaFrom(_, p, um) =>
                expected_digests[p] = um.delta
            }
          }
        BeginPayload(rel_payload, payload_len) => {
          guard active_file is None else {
            raise @lib.ManifestError::InvalidSchema
          }
          let exp = match expected_digests.get(rel_payload) {
            Some(d) => d
            None =>
              raise @lib.ManifestError::BindingMismatch("archive_payload_path")
          }
          guard exp.byte_length == payload_len else {
            raise @lib.ManifestError::BindingMismatch("archive_payload_length")
          }
          ensure_staged_parent_dirs(unpack_dir, rel_payload)
          let dst = join_rel_posix(unpack_dir, rel_payload)
          let f = @fs.open(
            dst,
            mode=WriteOnly,
            create_mode=CreateNew,
            permission=0o600,
          )
          active_file = Some(f)
          active_hasher = Some(@lib.Sha256Hasher::new(payload_len))
          active_expected = Some(exp)
          active_path = rel_payload
        }
        PayloadChunk(data_view) =>
          match (active_file, active_hasher) {
            (Some(f), Some(h)) => {
              h.update(data_view)
              write_nonempty(f, data_view)
            }
            _ => raise @lib.ManifestError::InvalidSchema
          }
        EndPayload(rel_payload) => {
          guard rel_payload == active_path else {
            raise @lib.ManifestError::InvalidSchema
          }
          match (active_file, active_hasher, active_expected) {
            (Some(f), Some(h), Some(exp)) => {
              sync_content(f)
              active_file = None
              active_hasher = None
              active_expected = None
              active_path = ""
              f.close()
              let actual = h.finish()
              guard actual.byte_length == exp.byte_length else {
                raise @lib.ManifestError::BindingMismatch("payload_length")
              }
              guard actual.sha256 == exp.sha256 else {
                raise @lib.ManifestError::BindingMismatch("payload_sha256")
              }
            }
            _ => raise @lib.ManifestError::InvalidSchema
          }
        }
      }
    }
  }
  if plan.gzip {
    let gz_dec = @compress.GzipDecoder::new(2147483647L, 2147483647L)
    let out_buf = FixedArray::make(65536, b'\x00')
    stream_open_chunks(archive_file, archive_path, archive_size, progress~, chunk => {
      match raw_sha {
        Some(h) => h.update(chunk)
        None => ()
      }
      let mut pos = 0
      while true {
        let step = gz_dec.step(chunk[pos:], out_buf)
        pos = pos + step.consumed
        if step.produced > 0 {
          let plain = Bytes::from_array(out_buf[0:step.produced])
          feed_archive(plain[:])
        }
        match step.status {
          NeedMoreOutput => continue
          NeedMoreInput => if pos >= chunk.length() { break }
          Done => break
        }
      }
    })
    let _ = gz_dec.finish()
  } else {
    stream_open_chunks(archive_file, archive_path, archive_size, progress~, chunk => {
      match raw_sha {
        Some(h) => h.update(chunk)
        None => ()
      }
      feed_archive(chunk)
    })
  }
  if arch_dec.has_pending_event() {
    feed_archive(b""[:])
  }
  let manifest = arch_dec.finish()
  guard active_file is None else { raise @lib.ManifestError::InvalidSchema }
  match (expected_archive_digest, raw_sha) {
    (Some(exp), Some(h)) => {
      let actual = h.finish()
      guard actual.byte_length == exp.byte_length && actual.sha256 == exp.sha256 else {
        raise @crypto.CryptoError::DigestMismatch("payload_sha256")
      }
    }
    _ => ()
  }
  manifest
}

///|
async fn apply_verified_bundle_delta(
  plan : Plan,
  basis_dir : String,
  basis_rel_path : String,
  payload_root : String,
  payload_path : String,
  staging : String,
  target_rel_path : String,
  m : @lib.UpdateManifest,
  max_old : Int64,
  progress : ProgressReporter?,
) -> Unit {
  let limits = plan.limits
  let old_src = resolve_safe_regular_under(basis_dir, basis_rel_path)
  let delta_src = resolve_safe_regular_under(payload_root, payload_path)
  ensure_staged_parent_dirs(staging, target_rel_path)
  let dst = join_rel_posix(staging, target_rel_path)
  if plan.streaming {
    execute_verified_streaming_delta(
      old_src,
      delta_src,
      dst,
      m,
      limits,
      progress~,
    )
  } else {
    let old = bounded_read(old_src, max_old)
    let delta = bounded_read(delta_src, limits.max_delta_bytes)
    let restored = @lib.verified_patch(old, delta, m, limits)
    let dst_file = @fs.open(
      dst,
      mode=WriteOnly,
      create_mode=CreateNew,
      permission=0o600,
    )
    let mut opened = true
    errdefer (if opened { dst_file.close() })
    write_content(dst_file, restored)
    sync_content(dst_file)
    dst_file.close()
    opened = false
    advance_progress(
      progress,
      old.length().to_int64() + delta.length().to_int64(),
    )
  }
}

///|
async fn apply_bundle_entries(
  plan : Plan,
  basis_dir : String,
  payload_root : String,
  staging : String,
  bundle : @lib.DirBundleManifest,
  progress : ProgressReporter?,
) -> Unit {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
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
  for entry in bundle.entries {
    match entry.action {
      Delete(_) => ()
      Unchanged(expected) => {
        let src = resolve_safe_regular_under(basis_dir, entry.path)
        ensure_staged_parent_dirs(staging, entry.path)
        let dst = join_rel_posix(staging, entry.path)
        stream_copy_verified_file(
          src,
          dst,
          expected,
          max_old,
          "basis",
          progress~,
        )
      }
      CopyFromBasis(source_path, expected) => {
        let src = resolve_safe_regular_under(basis_dir, source_path)
        ensure_staged_parent_dirs(staging, entry.path)
        let dst = join_rel_posix(staging, entry.path)
        stream_copy_verified_file(
          src,
          dst,
          expected,
          max_old,
          "basis",
          progress~,
        )
      }
      AddFull(payload_path, expected) | UpdateFull(payload_path, _, expected) => {
        let src = resolve_safe_regular_under(payload_root, payload_path)
        ensure_staged_parent_dirs(staging, entry.path)
        let dst = join_rel_posix(staging, entry.path)
        stream_copy_verified_file(
          src,
          dst,
          expected,
          max_new,
          "payload",
          progress~,
        )
      }
      UpdateDelta(payload_path, m) =>
        apply_verified_bundle_delta(
          plan,
          basis_dir,
          entry.path,
          payload_root,
          payload_path,
          staging,
          entry.path,
          m,
          max_old,
          progress,
        )
      UpdateDeltaFrom(source_path, payload_path, m) =>
        apply_verified_bundle_delta(
          plan,
          basis_dir,
          source_path,
          payload_root,
          payload_path,
          staging,
          entry.path,
          m,
          max_old,
          progress,
        )
    }
  }
}

///|
async fn pack_rollback_update(
  plan : Plan,
  new_src : String,
  old_src : String,
  rb_staging : String,
  payload_idx : Int32,
  new_digest : @lib.FileDigest,
  old_digest : @lib.FileDigest,
) -> @lib.DirBundleAction {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
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
  let delta_rel = "payloads/" + zero_pad6(payload_idx) + ".delta"
  let full_rel = "payloads/" + zero_pad6(payload_idx) + ".full"
  let delta_dst = join_rel_posix(rb_staging, delta_rel)
  let full_dst = join_rel_posix(rb_staging, full_rel)
  let block_len = @lib.recommend_block_len(new_digest.byte_length, 32L, limits) catch {
    error => raise @lib.ManifestError::Core(error)
  }
  let opts : @lib.SignatureOptions = { block_len, strong_sum_len: 32L, }
  if plan.streaming {
    let new_file = open_regular_input(new_src)
    defer new_file.close()
    let new_size = check_open_regular_sized(new_file, new_src, max_old)
    guard new_size == new_digest.byte_length else {
      raise @lib.ManifestError::BindingMismatch("basis_length")
    }
    let sig_hasher = @lib.SignatureHasher::new(opts, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let new_sha = @lib.Sha256Hasher::new(max_old)
    let sig_buf = @buffer.Buffer(capacity=256)
    sig_buf.write_bytes(sig_hasher.take_ready())
    stream_open_chunks(new_file, new_src, new_size, chunk => {
      new_sha.update(chunk)
      sig_hasher.update(chunk) catch {
        error => raise @lib.ManifestError::Core(error)
      }
      sig_buf.write_bytes(sig_hasher.take_ready())
    })
    sig_buf.write_bytes(
      sig_hasher.finish() catch {
        error => raise @lib.ManifestError::Core(error)
      },
    )
    guard new_sha.finish().sha256 == new_digest.sha256 else {
      raise @lib.ManifestError::BindingMismatch("basis_sha256")
    }
    let sig_bytes = sig_buf.to_bytes()
    let sig_sha = @lib.Sha256Hasher::new(limits.max_signature_bytes)
    sig_sha.update(sig_bytes[:])
    let sig_digest = sig_sha.finish()
    let prepared = @lib.prepare_signature(sig_bytes, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let old_file = open_regular_input(old_src)
    defer old_file.close()
    let old_size = check_open_regular_sized(old_file, old_src, max_new)
    guard old_size == old_digest.byte_length else {
      raise @lib.ManifestError::BindingMismatch("target_length")
    }
    let scanner = @lib.DeltaScanner::new(prepared, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let old_sha = @lib.Sha256Hasher::new(max_new)
    let delta_sha = @lib.Sha256Hasher::new(limits.max_delta_bytes)
    let dec = @lib.PatchDecoder::new(new_digest.byte_length, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let out_file = @fs.open(
      delta_dst,
      mode=WriteOnly,
      create_mode=CreateNew,
      permission=0o600,
    )
    let mut opened = true
    let mut limit_fallback = false
    try {
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
      stream_open_chunks(old_file, old_src, old_size, chunk => {
        old_sha.update(chunk)
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
    } catch {
      @lib.ManifestError::Core(@lib.SyncError::LimitExceeded)
      | @lib.ManifestError::ResourceLimit(_) => {
        if opened {
          out_file.close()
          opened = false
        }
        let _ = @fs.remove(delta_dst, allow_missing=true) catch { _ => () }
        limit_fallback = true
      }
      error => {
        if opened {
          out_file.close()
        }
        raise error
      }
    }
    if limit_fallback {
      stream_copy_verified_file(old_src, full_dst, old_digest, max_new, "basis")
      return UpdateFull(full_rel, new_digest, old_digest)
    }
    guard old_sha.finish().sha256 == old_digest.sha256 else {
      raise @lib.ManifestError::BindingMismatch("target_sha256")
    }
    let summary = dec.finish() catch {
      error => raise @lib.ManifestError::Core(error)
    }
    guard summary.output_bytes == old_digest.byte_length else {
      raise @lib.ManifestError::BindingMismatch("result_length")
    }
    let delta_digest = delta_sha.finish()
    if delta_digest.byte_length < old_digest.byte_length {
      UpdateDelta(delta_rel, {
        basis: new_digest,
        signature: sig_digest,
        delta: delta_digest,
        result: old_digest,
      })
    } else {
      @fs.remove(delta_dst, allow_missing=false)
      stream_copy_verified_file(old_src, full_dst, old_digest, max_new, "basis")
      UpdateFull(full_rel, new_digest, old_digest)
    }
  } else {
    let new_bytes = bounded_read(new_src, max_old)
    let old_bytes = bounded_read(old_src, max_new)
    let sig_bytes = @lib.signature(new_bytes, opts, limits) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    let info = @lib.create_basis_info(new_bytes, sig_bytes, limits)
    let cand_opt : Bytes? = Some(@lib.delta(sig_bytes, old_bytes, limits)) catch {
      @lib.SyncError::LimitExceeded => None
      error => raise @lib.ManifestError::Core(error)
    }
    match cand_opt {
      Some(cand) => {
        let um_opt : @lib.UpdateManifest? = Some(
          @lib.create_update_manifest(info, sig_bytes, old_bytes, cand, limits),
        ) catch {
          @lib.ManifestError::ResourceLimit(_)
          | @lib.ManifestError::Core(@lib.SyncError::LimitExceeded) => None
          error => raise error
        }
        match um_opt {
          Some(um) =>
            if um.delta.byte_length < um.result.byte_length {
              @fs.write_binary(
                delta_dst,
                cand[:],
                create_mode=CreateNew,
                permission=0o600,
              )
              return UpdateDelta(delta_rel, um)
            }
          None => ()
        }
      }
      None => ()
    }
    @fs.write_binary(
      full_dst,
      old_bytes[:],
      create_mode=CreateNew,
      permission=0o600,
    )
    UpdateFull(full_rel, new_digest, old_digest)
  }
}

///|
async fn try_resolve_safe_regular_under(
  root_dir : String,
  rel_posix : String,
) -> String? {
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
    let kind_opt : @fs.FileKind? = Some(@fs.kind(cur_str, follow_symlink=false)) catch {
      @os_error.OsError::OsError(NotFound, ..) => None
      error => raise error
    }
    match kind_opt {
      None => return None
      Some(kind) =>
        if i + 1 < segs.length() {
          if !(kind is @fs.FileKind::Directory) {
            return None
          }
        } else if kind is @fs.FileKind::Regular {
          return Some(cur_str)
        } else {
          return None
        }
    }
  }
  None
}

///|
fn record_basis_digest(
  seen_basis : Map[String, @lib.FileDigest],
  path : String,
  digest : @lib.FileDigest,
) -> Unit raise @lib.ManifestError {
  match seen_basis.get(path) {
    Some(existing) =>
      if existing.byte_length != digest.byte_length ||
        existing.sha256 != digest.sha256 {
        raise @lib.ManifestError::BindingMismatch("basis_digest")
      }
    None => seen_basis[path] = digest
  }
}

///|
async fn build_rollback_archive_to_temp(
  plan : Plan,
  staging_out : String,
  basis_dir : String,
  applied_manifest : @lib.DirBundleManifest,
  rb_final : String,
) -> String {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
  let max_new = if dir_limits.max_file_bytes < limits.max_new_bytes {
    dir_limits.max_file_bytes
  } else {
    limits.max_new_bytes
  }
  let seen_new : Map[String, String] = Map([])
  let new_entries : Array[@lib.DirEntry] = []
  collect_dir_entries(staging_out, "", 1L, dir_limits, seen_new, new_entries)
  let new_snap = @lib.create_dir_snapshot(new_entries, dir_limits)
  let seen_basis : Map[String, @lib.FileDigest] = Map([])
  for entry in applied_manifest.entries {
    match entry.action {
      Unchanged(d) => record_basis_digest(seen_basis, entry.path, d)
      UpdateDelta(_, m) => record_basis_digest(seen_basis, entry.path, m.basis)
      UpdateFull(_, b, _) => record_basis_digest(seen_basis, entry.path, b)
      Delete(b) => record_basis_digest(seen_basis, entry.path, b)
      CopyFromBasis(src, target_d) =>
        record_basis_digest(seen_basis, src, target_d)
      UpdateDeltaFrom(src, _, m) =>
        record_basis_digest(seen_basis, src, m.basis)
      AddFull(_, _) => ()
    }
  }
  for entry in applied_manifest.entries {
    match entry.action {
      CopyFromBasis(_, _) | UpdateDeltaFrom(_, _, _) =>
        if !seen_basis.contains(entry.path) {
          match try_resolve_safe_regular_under(basis_dir, entry.path) {
            Some(existing_path) => {
              let actual = stream_hash_regular_file(
                existing_path,
                dir_limits.max_file_bytes,
              )
              record_basis_digest(seen_basis, entry.path, actual)
            }
            None => ()
          }
        }
      _ => ()
    }
  }
  let old_entries : Array[@lib.DirEntry] = Array(capacity=seen_basis.length())
  for path, digest in seen_basis {
    old_entries.push({ path, digest, })
  }
  let old_snap = @lib.create_dir_snapshot(old_entries, dir_limits)
  let rev_plan = @lib.plan_dir_sync_with_options(
    new_snap,
    old_snap,
    { detect_moves: true, },
    dir_limits,
  )
  let rb_staging = unique_temp_path(rb_final)
  let rb_tmp = unique_temp_path(rb_final)
  @fs.mkdir(rb_staging, permission=0o700, recursive=false, allow_existing=false)
  let mut tmp_created = false
  errdefer {
    let _ = @fs.remove(rb_staging, recursive=true, allow_missing=true) catch {
      _ => ()
    }
    if tmp_created {
      let _ = @fs.remove(rb_tmp, allow_missing=true) catch { _ => () }
    }
  }
  let payloads_dir = @path.Path(rb_staging)
    .join(@path.Path("payloads"))
    .to_string()
  @fs.mkdir(
    payloads_dir,
    permission=0o700,
    recursive=false,
    allow_existing=false,
  )
  let rb_entries : Array[@lib.DirBundleEntry] = Array(
    capacity=rev_plan.actions.length(),
  )
  let mut payload_idx = 0
  for act in rev_plan.actions {
    match act.kind {
      Unchanged => {
        guard act.basis is Some(b) else {
          raise @lib.ManifestError::InvalidField("action")
        }
        rb_entries.push({ path: act.path, action: Unchanged(b), })
      }
      Delete => {
        guard act.basis is Some(b) else {
          raise @lib.ManifestError::InvalidField("action")
        }
        rb_entries.push({ path: act.path, action: Delete(b), })
      }
      CopyFromBasis(src) => {
        guard act.target is Some(t) else {
          raise @lib.ManifestError::InvalidField("action")
        }
        rb_entries.push({ path: act.path, action: CopyFromBasis(src, t), })
      }
      AddFull => {
        guard act.target is Some(t) else {
          raise @lib.ManifestError::InvalidField("action")
        }
        let old_src = resolve_safe_regular_under(basis_dir, act.path)
        let payload_rel = "payloads/" + zero_pad6(payload_idx) + ".full"
        payload_idx = payload_idx + 1
        let dst = join_rel_posix(rb_staging, payload_rel)
        stream_copy_verified_file(old_src, dst, t, max_new, "basis")
        rb_entries.push({ path: act.path, action: AddFull(payload_rel, t), })
      }
      UpdateCandidate => {
        guard act.basis is Some(b) && act.target is Some(t) else {
          raise @lib.ManifestError::InvalidField("action")
        }
        let new_src = resolve_safe_regular_under(staging_out, act.path)
        let old_src = resolve_safe_regular_under(basis_dir, act.path)
        let action = pack_rollback_update(
          plan, new_src, old_src, rb_staging, payload_idx, b, t,
        )
        payload_idx = payload_idx + 1
        rb_entries.push({ path: act.path, action, })
      }
    }
  }
  let rb_manifest = @lib.create_dir_bundle_manifest(
    rb_entries, dir_limits, limits,
  )
  let rb_file = @fs.open(
    rb_tmp,
    mode=WriteOnly,
    create_mode=CreateNew,
    permission=0o600,
  )
  tmp_created = true
  let mut opened = true
  errdefer (if opened { rb_file.close() })
  write_bundle_archive_into_open_file(
    true,
    dir_limits,
    limits,
    rb_staging,
    rb_manifest,
    rb_file,
    None,
  )
  sync_content(rb_file)
  rb_file.close()
  opened = false
  @fs.remove(rb_staging, recursive=true, allow_missing=true)
  rb_tmp
}

///|
async fn publish_dir_apply_tx(
  plan : Plan,
  basis_dir : String,
  out_dir : String,
  rb_final_opt : String?,
  builder : async (String) -> @lib.DirBundleManifest,
) -> Unit {
  let final_path = prepare_output(out_dir)
  match rb_final_opt {
    Some(rb_final) => {
      let same = if @path.sep != '/' {
        dir_ascii_lower(rb_final) == dir_ascii_lower(final_path)
      } else {
        rb_final == final_path
      }
      guard !same else {
        raise FileFailure(
          "rollback archive path collides with output directory: " + out_dir,
        )
      }
    }
    None => ()
  }
  let staging = unique_temp_path(final_path)
  @fs.mkdir(staging, permission=0o700, recursive=false, allow_existing=false)
  let mut rb_tmp_opt : String? = None
  let mut out_committed = false
  try {
    let applied_manifest = builder(staging)
    match rb_final_opt {
      Some(rb_final) =>
        rb_tmp_opt = Some(
          build_rollback_archive_to_temp(
            plan, staging, basis_dir, applied_manifest, rb_final,
          ),
        )
      None => ()
    }
    @fs.rename(staging, final_path, replace=false)
    out_committed = true
    match (rb_final_opt, rb_tmp_opt) {
      (Some(rb_final), Some(rb_tmp)) => {
        @fs.rename(rb_tmp, rb_final, replace=false)
        rb_tmp_opt = None
      }
      _ => ()
    }
  } catch {
    error => {
      let detail = stream_error_detail(error)
      match rb_tmp_opt {
        Some(rb_tmp) => {
          let _ = @fs.remove(rb_tmp, allow_missing=true) catch { _ => () }
        }
        None => ()
      }
      if out_committed {
        let _ = @fs.remove(final_path, recursive=true, allow_missing=true) catch {
          _ => ()
        }
      } else {
        @fs.remove(staging, recursive=true, allow_missing=true) catch {
          cleanup_error =>
            raise FileFailure(
              "dir-apply '" +
              out_dir +
              "': " +
              detail +
              "; cleanup failed '" +
              staging +
              "': \{cli_error_text(cleanup_error)}",
            )
        }
      }
      raise FileFailure("dir-apply '" + out_dir + "': " + detail)
    }
  }
}

///|
fn validate_dir_metadata_against_manifest(
  manifest : @lib.DirBundleManifest,
  meta : @lib.DirMetadata,
) -> Unit raise CliError {
  let active_files : Map[String, String] = Map([])
  let active_anc_dirs : Map[String, String] = Map([])
  for entry in manifest.entries {
    match entry.action {
      Delete(_) => ()
      _ => {
        let lower = dir_ascii_lower(entry.path)
        active_files[lower] = entry.path
        let segs = split_posix_segments(entry.path)
        let prefix = StringBuilder()
        for i in 0..<(segs.length() - 1) {
          if i > 0 {
            prefix.write_char('/')
          }
          prefix.write_string(segs[i])
          let anc = prefix.to_string()
          active_anc_dirs[dir_ascii_lower(anc)] = anc
        }
      }
    }
  }
  for exec_path in meta.executable_paths {
    match active_files.get(dir_ascii_lower(exec_path)) {
      Some(actual) =>
        if actual != exec_path {
          raise FileFailure("metadata path_collision: " + exec_path)
        }
      None =>
        raise FileFailure(
          "metadata executable_path absent from applied bundle: " + exec_path,
        )
    }
  }
  for empty_dir in meta.empty_dirs {
    let segs = split_posix_segments(empty_dir)
    let prefix = StringBuilder()
    for i in 0..<segs.length() {
      if i > 0 {
        prefix.write_char('/')
      }
      prefix.write_string(segs[i])
      let anc = prefix.to_string()
      let anc_lower = dir_ascii_lower(anc)
      guard !active_files.contains(anc_lower) else {
        raise FileFailure("metadata empty_dir collides with file: " + empty_dir)
      }
      match active_anc_dirs.get(anc_lower) {
        Some(actual_dir) => {
          guard actual_dir == anc else {
            raise FileFailure("metadata path_collision: " + empty_dir)
          }
          if i == segs.length() - 1 {
            raise FileFailure(
              "metadata empty_dir is non-empty directory: " + empty_dir,
            )
          }
        }
        None => ()
      }
    }
  }
}

///|
async fn apply_dir_metadata_staged(
  staging : String,
  manifest : @lib.DirBundleManifest,
  meta : @lib.DirMetadata,
) -> Unit {
  validate_dir_metadata_against_manifest(manifest, meta)
  for empty_dir in meta.empty_dirs {
    let segs = split_posix_segments(empty_dir)
    let mut cur = @path.Path(staging)
    for seg in segs {
      guard seg.length() > 0 && seg != "." && seg != ".." else {
        raise @lib.ManifestError::InvalidField("path")
      }
      cur = cur.join(@path.Path(seg))
      let cur_str = cur.to_string()
      @fs.mkdir(cur_str, permission=0o700, recursive=false, allow_existing=true)
      guard @fs.kind(cur_str, follow_symlink=false) is @fs.FileKind::Directory else {
        raise FileFailure("metadata empty_dir collides with file: " + empty_dir)
      }
    }
  }
  for exec_path in meta.executable_paths {
    let target_file = resolve_safe_regular_under(staging, exec_path)
    if @path.sep == '/' {
      guard @fs.kind(target_file, follow_symlink=false) is @fs.FileKind::Regular else {
        raise FileFailure(
          "unsupported directory entry kind or symlink: " + target_file,
        )
      }
      @fs.chmod(target_file, 0o700)
    }
  }
}

///|
async fn execute_dir_apply(plan : Plan, out_dir : String) -> Unit {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
  limits.validate()
  dir_limits.validate()
  let basis_dir = plan.inputs[0]
  let bundle_input = plan.inputs[1]
  guard @fs.kind(basis_dir, follow_symlink=false) is @fs.FileKind::Directory else {
    raise FileFailure(
      "unsupported input kind or symlink directory: " + basis_dir,
    )
  }
  let meta_opt : @lib.DirMetadata? = match plan.meta_file {
    Some(meta_path) => {
      let meta_bytes = bounded_read(meta_path, dir_limits.max_snapshot_bytes)
      Some(@lib.parse_dir_metadata(meta_bytes, dir_limits))
    }
    None => None
  }
  let rb_final_opt : String? = match plan.save_rollback {
    Some(rb_path) => Some(prepare_output(rb_path))
    None => None
  }
  if plan.archive {
    guard @fs.kind(bundle_input, follow_symlink=false) is @fs.FileKind::Regular else {
      raise FileFailure(
        "unsupported input kind or leaf symlink: " + bundle_input,
      )
    }
    let verified_digest = verify_attached_signature_file(
      plan, bundle_input, 2147483647L,
    )
    let progress = make_progress(plan, -1L)
    publish_dir_apply_tx(plan, basis_dir, out_dir, rb_final_opt, staging => {
      let unpack_dir = unique_temp_path(staging)
      @fs.mkdir(
        unpack_dir,
        permission=0o700,
        recursive=false,
        allow_existing=false,
      )
      try {
        let manifest = unpack_bundle_archive(
          plan,
          bundle_input,
          unpack_dir,
          progress,
          expected_archive_digest=verified_digest,
        )
        apply_bundle_entries(
          plan, basis_dir, unpack_dir, staging, manifest, progress,
        )
        match meta_opt {
          Some(meta) => apply_dir_metadata_staged(staging, manifest, meta)
          None => ()
        }
        @fs.remove(unpack_dir, recursive=true, allow_missing=true)
        manifest
      } catch {
        error => {
          let detail = stream_error_detail(error)
          @fs.remove(unpack_dir, recursive=true, allow_missing=true) catch {
            cleanup_error =>
              raise FileFailure(
                detail +
                "; unpack cleanup failed '" +
                unpack_dir +
                "': \{cli_error_text(cleanup_error)}",
              )
          }
          raise FileFailure(detail)
        }
      }
    })
    finish_progress(progress)
  } else {
    let bundle_json_path = resolve_safe_regular_under(
      bundle_input, "bundle.json",
    )
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
    let mut total_bytes = 0L
    for entry in bundle.entries {
      match entry.action {
        Delete(_) => ()
        Unchanged(expected) | CopyFromBasis(_, expected) =>
          total_bytes = total_bytes + expected.byte_length
        AddFull(_, expected) | UpdateFull(_, _, expected) =>
          total_bytes = total_bytes + expected.byte_length
        UpdateDelta(_, m) | UpdateDeltaFrom(_, _, m) =>
          total_bytes = total_bytes + m.basis.byte_length + m.delta.byte_length
      }
    }
    let progress = make_progress(plan, total_bytes)
    publish_dir_apply_tx(plan, basis_dir, out_dir, rb_final_opt, staging => {
      apply_bundle_entries(
        plan, basis_dir, bundle_input, staging, bundle, progress,
      )
      match meta_opt {
        Some(meta) => apply_dir_metadata_staged(staging, bundle, meta)
        None => ()
      }
      bundle
    })
    finish_progress(progress)
  }
}

///|
async fn execute_dir_bundle_op(plan : Plan, output_path : String) -> Unit {
  try {
    match plan.operation {
      "dir-signatures" => execute_dir_signatures(plan, output_path)
      "dir-pack" => execute_dir_pack(plan, output_path)
      _ => execute_dir_apply(plan, output_path)
    }
  } catch {
    error => raise wrap_stream_error(plan, output_path, error)
  }
}
