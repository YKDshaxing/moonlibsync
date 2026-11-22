// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn unique_temp_path(output : String) -> String raise CliError {
  let random = match @env.rand(16) {
    Some(value) => @hex.encode(value)
    None => raise FileFailure("temporary name randomness unavailable")
  }
  let parent = @path.Path(output).dirname()
  parent.join(@path.Path(".moonlibsync-" + random + ".tmp")).to_string()
}

///|
fn stream_error_detail(error : Error) -> String {
  match crypto_error_tag_of(error) {
    Some(tag) => tag
    None =>
      match error {
        @lib.ManifestError::Core(_)
        | @lib.ManifestError::BindingMismatch(_)
        | @lib.ManifestError::InvalidField(_)
        | @lib.ManifestError::ResourceLimit(_)
        | @lib.ManifestError::InvalidUtf8
        | @lib.ManifestError::InvalidJson
        | @lib.ManifestError::InvalidSchema
        | @lib.ManifestError::HashFailure => manifest_error_tag(error)
        @lib.SyncError::InvalidOptions(_)
        | @lib.SyncError::UnsupportedSignatureProfile
        | @lib.SyncError::TruncatedInput
        | @lib.SyncError::InvalidSignature
        | @lib.SyncError::InvalidDelta
        | @lib.SyncError::InvalidOpcode
        | @lib.SyncError::IntegerOutOfRange
        | @lib.SyncError::CopyOutOfBounds
        | @lib.SyncError::TrailingData
        | @lib.SyncError::LimitExceeded => core_error_tag(error)
        _ => cli_error_text(error)
      }
  }
}

///|
async fn publish_stream_at(
  temporary : String,
  output : String,
  producer : async (@fs.File) -> Unit,
  syncer~ : async (@fs.File) -> Unit = sync_content,
  before_commit~ : async () -> Unit = no_hook,
  cleanup~ : async (String) -> Unit = remove_owned,
) -> Unit {
  // Exclusive creation before writing; failed CreateNew never grants cleanup ownership.
  let file = @fs.open(
    temporary,
    mode=WriteOnly,
    create_mode=CreateNew,
    permission=0o600,
  )
  let mut opened = true
  try {
    producer(file)
    syncer(file)
    file.close()
    opened = false
    before_commit()
    @fs.rename(temporary, output, replace=false)
  } catch {
    error => {
      if opened {
        file.close()
      }
      let detail = stream_error_detail(error)
      cleanup(temporary) catch {
        cleanup_error =>
          raise FileFailure(
            "write/commit '" +
            output +
            "': " +
            detail +
            "; cleanup failed '" +
            temporary +
            "': \{cli_error_text(cleanup_error)}",
          )
      }
      raise FileFailure("write/commit '" + output + "': " + detail)
    }
  }
}

///|
async fn publish_stream(
  output : String,
  producer : async (@fs.File) -> Unit,
) -> Unit {
  let temporary = unique_temp_path(output)
  publish_stream_at(temporary, output, producer)
}

///|
async fn check_open_regular_sized(
  file : @fs.File,
  path : String,
  maximum : Int64,
) -> Int64 {
  guard file.kind() is @fs.FileKind::Regular else {
    raise FileFailure("unsupported input kind: " + path)
  }
  let size = file.size()
  guard size >= 0L && maximum >= 0L && maximum <= 2147483647L && size <= maximum else {
    raise FileFailure(
      "ReadLimitExceeded: " + path + " size=\{size} limit=\{maximum}",
    )
  }
  size
}

///|
async fn verify_stream_eof(
  file : @fs.File,
  path : String,
  expected_size : Int64,
) -> Unit {
  let sentinel = FixedArray::make(1, b'\x00')
  guard file.read_at(sentinel, position=expected_size, len=1) == 0 &&
    file.size() == expected_size else {
    raise FileFailure("InputChanged: file grew or changed size: " + path)
  }
}

///|
async fn stream_open_chunks(
  file : @fs.File,
  path : String,
  size : Int64,
  after_start~ : async () -> Unit = no_hook,
  progress~ : ProgressReporter? = None,
  on_chunk : async (BytesView) -> Unit,
) -> Unit {
  after_start()
  let buf = FixedArray::make(65536, b'\x00')
  let mut pos = 0L
  while pos < size {
    let remaining = size - pos
    let take = if remaining < 65536L { remaining.to_int() } else { 65536 }
    let count = file.read_at(buf, position=pos, offset=0, len=take)
    guard count > 0 && count <= take else {
      raise FileFailure("InputChanged: short read: " + path)
    }
    let slice = Bytes::from_array(buf[0:count])
    on_chunk(slice[:])
    advance_progress(progress, count.to_int64())
    pos = pos + count.to_int64()
  }
  verify_stream_eof(file, path, size)
}

///|
async fn write_nonempty(file : @fs.File, view : BytesView) -> Unit {
  if view.length() > 0 {
    file.write(view)
  }
}

///|
async fn stream_copy_from_basis(
  basis_file : @fs.File,
  basis_path : String,
  copy_buf : FixedArray[Byte],
  offset : UInt64,
  len : Int32,
  on_output : async (BytesView) -> Unit,
) -> Unit {
  let pos = offset.reinterpret_as_int64()
  let mut got = 0
  while got < len {
    let n = basis_file.read_at(
      copy_buf,
      position=pos + got.to_int64(),
      offset=got,
      len=len - got,
    )
    guard n > 0 && n <= len - got else {
      raise FileFailure("InputChanged: short basis read: " + basis_path)
    }
    got = got + n
  }
  let copied = Bytes::from_array(copy_buf[0:len])
  on_output(copied[:])
}

///|
async fn drive_streaming_patch(
  dec : @lib.PatchDecoder,
  delta_chunk : BytesView,
  basis_file : @fs.File,
  basis_path : String,
  copy_buf : FixedArray[Byte],
  on_output : async (BytesView) -> Unit,
) -> Unit {
  let mut pos = 0
  while pos < delta_chunk.length() || dec.has_pending_copy() {
    let (consumed, step) = dec.step(delta_chunk[pos:])
    pos = pos + consumed
    match step {
      NeedInput => ()
      EmitLiteral(view) => on_output(view)
      CopyBasis(offset, len) =>
        stream_copy_from_basis(
          basis_file, basis_path, copy_buf, offset, len, on_output,
        )
    }
  }
}

///|
fn wrap_stream_error(
  plan : Plan,
  output_path : String,
  error : Error,
) -> CliError {
  match crypto_error_tag_of(error) {
    Some(tag) => FileFailure(plan.operation + ": " + tag)
    None =>
      match error {
        Usage(msg) => Usage(msg)
        FileFailure(msg) => FileFailure(msg)
        @lib.ManifestError::Core(_)
        | @lib.ManifestError::BindingMismatch(_)
        | @lib.ManifestError::InvalidField(_)
        | @lib.ManifestError::ResourceLimit(_)
        | @lib.ManifestError::InvalidUtf8
        | @lib.ManifestError::InvalidJson
        | @lib.ManifestError::InvalidSchema
        | @lib.ManifestError::HashFailure =>
          FileFailure(plan.operation + ": " + manifest_error_tag(error))
        @lib.SyncError::InvalidOptions(_)
        | @lib.SyncError::UnsupportedSignatureProfile
        | @lib.SyncError::TruncatedInput
        | @lib.SyncError::InvalidSignature
        | @lib.SyncError::InvalidDelta
        | @lib.SyncError::InvalidOpcode
        | @lib.SyncError::IntegerOutOfRange
        | @lib.SyncError::CopyOutOfBounds
        | @lib.SyncError::TrailingData
        | @lib.SyncError::LimitExceeded =>
          FileFailure(
            "core " +
            plan.operation +
            " for '" +
            output_path +
            "': " +
            core_error_tag(error),
          )
        _ =>
          FileFailure(
            plan.operation +
            " for '" +
            output_path +
            "': \{cli_error_text(error)}",
          )
      }
  }
}

///|
async fn stream_verify_basis_sha(
  basis_file : @fs.File,
  basis_path : String,
  expected : @lib.FileDigest,
  limits : @lib.Limits,
  progress~ : ProgressReporter? = None,
) -> Int64 {
  let size = check_open_regular_sized(
    basis_file,
    basis_path,
    limits.max_old_bytes,
  )
  guard size == expected.byte_length else {
    raise @lib.ManifestError::BindingMismatch("basis_length")
  }
  let hasher = @lib.Sha256Hasher::new(limits.max_old_bytes)
  stream_open_chunks(basis_file, basis_path, size, progress~, chunk => {
    hasher.update(chunk)
  })
  let actual = hasher.finish()
  guard actual.sha256 == expected.sha256 else {
    raise @lib.ManifestError::BindingMismatch("basis_sha256")
  }
  size
}

///|
async fn execute_verified_streaming_delta(
  basis_path : String,
  delta_path : String,
  output_path : String,
  m : @lib.UpdateManifest,
  limits : @lib.Limits,
  progress~ : ProgressReporter? = None,
) -> Unit {
  let old_file = open_regular_input(basis_path)
  defer old_file.close()
  let old_size = stream_verify_basis_sha(
    old_file,
    basis_path,
    m.basis,
    limits,
    progress~,
  )
  let delta_file = open_regular_input(delta_path)
  defer delta_file.close()
  let delta_size = check_open_regular_sized(
    delta_file,
    delta_path,
    limits.max_delta_bytes,
  )
  guard delta_size == m.delta.byte_length else {
    raise @lib.ManifestError::BindingMismatch("delta_length")
  }
  guard delta_size >= 5L else { raise @lib.SyncError::TruncatedInput }
  let output = prepare_output(output_path)
  let delta_hasher = @lib.Sha256Hasher::new(limits.max_delta_bytes)
  let result_hasher = @lib.Sha256Hasher::new(limits.max_output_bytes)
  let dec = @lib.PatchDecoder::new(old_size, limits)
  let copy_buf = FixedArray::make(65536, b'\x00')
  publish_stream(output, tmp_file => {
    stream_open_chunks(delta_file, delta_path, delta_size, progress~, chunk => {
      delta_hasher.update(chunk)
      drive_streaming_patch(dec, chunk, old_file, basis_path, copy_buf, view => {
        result_hasher.update(view)
        write_nonempty(tmp_file, view)
      })
    })
    guard old_file.size() == old_size else {
      raise FileFailure("InputChanged: basis size changed: " + basis_path)
    }
    let actual_delta = delta_hasher.finish()
    guard actual_delta.sha256 == m.delta.sha256 else {
      raise @lib.ManifestError::BindingMismatch("delta_sha256")
    }
    let _ = dec.finish()
    let actual_result = result_hasher.finish()
    guard actual_result.byte_length == m.result.byte_length else {
      raise @lib.ManifestError::BindingMismatch("result_length")
    }
    guard actual_result.sha256 == m.result.sha256 else {
      raise @lib.ManifestError::BindingMismatch("result_sha256")
    }
  })
}

///|
async fn streaming_create_basis_info(
  old_path : String,
  sig_path : String,
  limits : @lib.Limits,
  progress~ : ProgressReporter? = None,
) -> @lib.BasisInfo {
  let old_file = open_regular_input(old_path)
  defer old_file.close()
  let old_size = check_open_regular_sized(
    old_file,
    old_path,
    limits.max_old_bytes,
  )
  match progress {
    Some(p) => if p.total < 0L { p.total = old_size }
    None => ()
  }
  let sig = bounded_read(sig_path, limits.max_signature_bytes)
  let sig_summary = @lib.inspect_signature(sig, limits) catch {
    error => raise @lib.ManifestError::Core(error)
  }
  let sig_profile = if sig_summary.magic == 0x72730137U {
    @lib.SignatureProfile::RollsumBlake2
  } else {
    @lib.SignatureProfile::RkBlake2
  }
  let sig_hasher = @lib.SignatureHasher::new_with_profile(
    {
      block_len: sig_summary.block_len,
      strong_sum_len: sig_summary.strong_sum_len,
    },
    sig_profile,
    limits,
  ) catch {
    error => raise @lib.ManifestError::Core(error)
  }
  let old_sha = @lib.Sha256Hasher::new(limits.max_old_bytes)
  let mut sig_pos = 0
  let check_slice = (emitted : Bytes) => {
    guard emitted.length() <= sig.length() - sig_pos else {
      raise @lib.ManifestError::BindingMismatch("basis_signature")
    }
    guard sig[sig_pos:sig_pos + emitted.length()] == emitted[:] else {
      raise @lib.ManifestError::BindingMismatch("basis_signature")
    }
    sig_pos = sig_pos + emitted.length()
  }
  check_slice(sig_hasher.take_ready())
  stream_open_chunks(old_file, old_path, old_size, progress~, chunk => {
    old_sha.update(chunk)
    sig_hasher.update(chunk) catch {
      error => raise @lib.ManifestError::Core(error)
    }
    check_slice(sig_hasher.take_ready())
  })
  let tail = sig_hasher.finish() catch {
    error => raise @lib.ManifestError::Core(error)
  }
  check_slice(tail)
  guard sig_pos == sig.length() else {
    raise @lib.ManifestError::BindingMismatch("basis_signature")
  }
  let basis_digest = old_sha.finish()
  let sig_sha = @lib.Sha256Hasher::new(limits.max_signature_bytes)
  sig_sha.update(sig[:])
  let sig_digest = sig_sha.finish()
  { basis: basis_digest, signature: sig_digest, }
}

///|
async fn streaming_create_update_manifest(
  info_path : String,
  sig_path : String,
  new_path : String,
  delta_path : String,
  limits : @lib.Limits,
  progress~ : ProgressReporter? = None,
) -> @lib.UpdateManifest {
  let info = @lib.parse_basis_info(bounded_read(info_path, 65536L), limits)
  let sig = bounded_read(sig_path, limits.max_signature_bytes)
  guard sig.length().to_int64() >= 12L else {
    raise @lib.ManifestError::InvalidField("signature.byte_length")
  }
  guard sig.length().to_int64() == info.signature.byte_length else {
    raise @lib.ManifestError::BindingMismatch("signature_length")
  }
  let _ = @lib.inspect_signature(sig, limits) catch {
    error => raise @lib.ManifestError::Core(error)
  }
  let sig_sha = @lib.Sha256Hasher::new(limits.max_signature_bytes)
  sig_sha.update(sig[:])
  let sig_digest = sig_sha.finish()
  guard sig_digest.sha256 == info.signature.sha256 else {
    raise @lib.ManifestError::BindingMismatch("signature_sha256")
  }
  let new_file = open_regular_input(new_path)
  defer new_file.close()
  let new_size = check_open_regular_sized(
    new_file,
    new_path,
    limits.max_new_bytes,
  )
  guard new_size <= limits.max_output_bytes else {
    raise @lib.ManifestError::ResourceLimit("result")
  }
  let delta_file = open_regular_input(delta_path)
  defer delta_file.close()
  let delta_size = check_open_regular_sized(
    delta_file,
    delta_path,
    limits.max_delta_bytes,
  )
  guard delta_size >= 5L else {
    raise @lib.ManifestError::InvalidField("delta.byte_length")
  }
  match progress {
    Some(p) => if p.total < 0L { p.total = new_size + delta_size }
    None => ()
  }
  let new_sha = @lib.Sha256Hasher::new(limits.max_new_bytes)
  stream_open_chunks(new_file, new_path, new_size, progress~, chunk => {
    new_sha.update(chunk)
  })
  let result_digest = new_sha.finish()

  let delta_sha = @lib.Sha256Hasher::new(limits.max_delta_bytes)
  let dec = @lib.PatchDecoder::new(info.basis.byte_length, limits) catch {
    error => raise @lib.ManifestError::Core(error)
  }
  stream_open_chunks(delta_file, delta_path, delta_size, progress~, chunk => {
    delta_sha.update(chunk)
    dec.feed_inspect(chunk) catch {
      error => raise @lib.ManifestError::Core(error)
    }
  })
  let summary = dec.finish() catch {
    error => raise @lib.ManifestError::Core(error)
  }
  guard summary.output_bytes == result_digest.byte_length else {
    raise @lib.ManifestError::BindingMismatch("result_length")
  }
  let delta_digest = delta_sha.finish()
  {
    basis: info.basis,
    signature: sig_digest,
    delta: delta_digest,
    result: result_digest,
  }
}

///|
async fn execute_streaming_write(plan : Plan, output_path : String) -> Unit {
  let limits = plan.limits
  try {
    limits.validate()
    match plan.operation {
      "basis-info" => {
        let output = prepare_output(output_path)
        let progress = make_progress(plan, -1L)
        let info = streaming_create_basis_info(
          plan.inputs[0],
          plan.inputs[1],
          limits,
          progress~,
        )
        publish_output(output, @lib.encode_basis_info(info, limits))
        finish_progress(progress)
      }
      "make-manifest" => {
        let output = prepare_output(output_path)
        let progress = make_progress(plan, -1L)
        let um = streaming_create_update_manifest(
          plan.inputs[0],
          plan.inputs[1],
          plan.inputs[2],
          plan.inputs[3],
          limits,
          progress~,
        )
        publish_output(output, @lib.encode_update_manifest(um, limits))
        finish_progress(progress)
      }
      "make-transfer-manifest" => {
        let output = prepare_output(output_path)
        let progress = make_progress(plan, -1L)
        let um = streaming_create_update_manifest(
          plan.inputs[0],
          plan.inputs[1],
          plan.inputs[2],
          plan.inputs[3],
          limits,
          progress~,
        )
        let smaller = um.delta.byte_length < um.result.byte_length
        let savings = if smaller {
          um.result.byte_length - um.delta.byte_length
        } else {
          0L
        }
        let tm : @lib.TransferManifest = if smaller &&
          savings >= plan.min_savings {
          Delta(um)
        } else {
          Full(um.result, um.result)
        }
        publish_output(output, @lib.encode_transfer_manifest(tm, limits))
        finish_progress(progress)
      }
      "signature" => {
        let old_path = plan.inputs[0]
        let old_file = open_regular_input(old_path)
        defer old_file.close()
        let old_size = check_open_regular_sized(
          old_file,
          old_path,
          limits.max_old_bytes,
        )
        let block = match plan.block_choice {
          Explicit(v) => v
          Auto =>
            @lib.recommend_block_len(
              old_size,
              plan.options.strong_sum_len,
              limits,
            )
        }
        let hasher = @lib.SignatureHasher::new_with_profile(
          { block_len: block, strong_sum_len: plan.options.strong_sum_len, },
          plan.sig_profile,
          limits,
        )
        let output = prepare_output(output_path)
        let progress = make_progress(plan, old_size)
        publish_stream(output, tmp_file => {
          write_nonempty(tmp_file, hasher.take_ready()[:])
          stream_open_chunks(old_file, old_path, old_size, progress~, chunk => {
            hasher.update(chunk)
            write_nonempty(tmp_file, hasher.take_ready()[:])
          })
          write_nonempty(tmp_file, hasher.finish()[:])
        })
        finish_progress(progress)
      }
      "delta" => {
        let sig = bounded_read(plan.inputs[0], limits.max_signature_bytes)
        let prepared = @lib.prepare_signature(sig, limits)
        let new_path = plan.inputs[1]
        let new_file = open_regular_input(new_path)
        defer new_file.close()
        let new_size = check_open_regular_sized(
          new_file,
          new_path,
          limits.max_new_bytes,
        )
        guard new_size <= limits.max_output_bytes else {
          raise @lib.SyncError::LimitExceeded
        }
        let scanner = @lib.DeltaScanner::new(prepared, limits)
        let output = prepare_output(output_path)
        let progress = make_progress(plan, new_size)
        publish_stream(output, tmp_file => {
          write_nonempty(tmp_file, scanner.take_ready()[:])
          stream_open_chunks(new_file, new_path, new_size, progress~, chunk => {
            scanner.feed(chunk)
            write_nonempty(tmp_file, scanner.take_ready()[:])
          })
          write_nonempty(tmp_file, scanner.finish()[:])
        })
        finish_progress(progress)
      }
      "patch" => {
        let old_path = plan.inputs[0]
        let delta_path = plan.inputs[1]
        let old_file = open_regular_input(old_path)
        defer old_file.close()
        let basis_len = check_open_regular_sized(
          old_file,
          old_path,
          limits.max_old_bytes,
        )
        let delta_file = open_regular_input(delta_path)
        defer delta_file.close()
        let delta_size = check_open_regular_sized(
          delta_file,
          delta_path,
          limits.max_delta_bytes,
        )
        guard delta_size >= 5L else { raise @lib.SyncError::TruncatedInput }
        let dec = @lib.PatchDecoder::new(basis_len, limits)
        let copy_buf = FixedArray::make(65536, b'\x00')
        let output = prepare_output(output_path)
        let progress = make_progress(plan, delta_size)
        publish_stream(output, tmp_file => {
          stream_open_chunks(delta_file, delta_path, delta_size, progress~, chunk => {
            drive_streaming_patch(dec, chunk, old_file, old_path, copy_buf, view => {
              write_nonempty(tmp_file, view)
            })
          })
          guard old_file.size() == basis_len else {
            raise FileFailure("InputChanged: basis size changed: " + old_path)
          }
          let _ = dec.finish()
        })
        finish_progress(progress)
      }
      "reverse-delta" => {
        let old_path = plan.inputs[0]
        let new_path = plan.inputs[1]
        let rev_limits : @lib.Limits = {
          ..limits,
          max_old_bytes: limits.max_new_bytes,
          max_new_bytes: limits.max_old_bytes,
        }
        let old_file = open_regular_input(old_path)
        defer old_file.close()
        let old_size = check_open_regular_sized(
          old_file,
          old_path,
          limits.max_old_bytes,
        )
        let new_file = open_regular_input(new_path)
        defer new_file.close()
        let new_size = check_open_regular_sized(
          new_file,
          new_path,
          limits.max_new_bytes,
        )
        let block = match plan.block_choice {
          Explicit(v) => v
          Auto =>
            @lib.recommend_block_len(
              new_size,
              plan.options.strong_sum_len,
              rev_limits,
            )
        }
        guard old_size <= limits.max_output_bytes else {
          raise @lib.SyncError::LimitExceeded
        }
        let output = prepare_output(output_path)
        let progress = make_progress(plan, new_size + old_size)
        let sig_hasher = @lib.SignatureHasher::new(
          { block_len: block, strong_sum_len: plan.options.strong_sum_len, },
          rev_limits,
        )
        let sig_buf = @buffer.Buffer(size_hint=256)
        sig_buf.write_bytes(sig_hasher.take_ready())
        stream_open_chunks(new_file, new_path, new_size, progress~, chunk => {
          sig_hasher.update(chunk)
          sig_buf.write_bytes(sig_hasher.take_ready())
        })
        sig_buf.write_bytes(sig_hasher.finish())
        let prepared = @lib.prepare_signature(sig_buf.to_bytes(), rev_limits)
        let scanner = @lib.DeltaScanner::new(prepared, rev_limits)
        publish_stream(output, tmp_file => {
          write_nonempty(tmp_file, scanner.take_ready()[:])
          stream_open_chunks(old_file, old_path, old_size, progress~, chunk => {
            scanner.feed(chunk)
            write_nonempty(tmp_file, scanner.take_ready()[:])
          })
          write_nonempty(tmp_file, scanner.finish()[:])
        })
        finish_progress(progress)
      }
      "patch-verified" => {
        let manifest_bytes = bounded_read(plan.inputs[2], 65536L)
        verify_attached_signature_bytes(plan, manifest_bytes)
        let manifest = @lib.parse_update_manifest(manifest_bytes, limits)
        let progress = make_progress(
          plan,
          manifest.basis.byte_length + manifest.delta.byte_length,
        )
        execute_verified_streaming_delta(
          plan.inputs[0],
          plan.inputs[1],
          output_path,
          manifest,
          limits,
          progress~,
        )
        finish_progress(progress)
      }
      _ => {
        let manifest_bytes = bounded_read(plan.inputs[1], 65536L)
        verify_attached_signature_bytes(plan, manifest_bytes)
        let manifest = @lib.parse_transfer_manifest(manifest_bytes, limits)
        match manifest {
          @lib.TransferManifest::Delta(m) => {
            guard plan.basis_path is Some(bpath) else {
              raise Usage("Delta requires --basis OLD")
            }
            let progress = make_progress(
              plan,
              m.basis.byte_length + m.delta.byte_length,
            )
            execute_verified_streaming_delta(
              bpath,
              plan.inputs[0],
              output_path,
              m,
              limits,
              progress~,
            )
            finish_progress(progress)
          }
          @lib.TransferManifest::Full(payload_desc, _) => {
            guard plan.basis_path is None else {
              raise Usage("Full forbids --basis")
            }
            let payload_path = plan.inputs[0]
            let payload_file = open_regular_input(payload_path)
            defer payload_file.close()
            let payload_size = check_open_regular_sized(
              payload_file,
              payload_path,
              limits.max_new_bytes,
            )
            guard payload_size <= limits.max_output_bytes else {
              raise @lib.SyncError::LimitExceeded
            }
            guard payload_size == payload_desc.byte_length else {
              raise @lib.ManifestError::BindingMismatch("payload_length")
            }
            let hasher = @lib.Sha256Hasher::new(limits.max_new_bytes)
            let output = prepare_output(output_path)
            let progress = make_progress(plan, payload_size)
            publish_stream(output, tmp_file => {
              stream_open_chunks(
                payload_file,
                payload_path,
                payload_size,
                progress~,
                chunk => {
                  hasher.update(chunk)
                  write_nonempty(tmp_file, chunk)
                },
              )
              let actual = hasher.finish()
              guard actual.sha256 == payload_desc.sha256 else {
                raise @lib.ManifestError::BindingMismatch("payload_sha256")
              }
            })
            finish_progress(progress)
          }
        }
      }
    }
  } catch {
    error => raise wrap_stream_error(plan, output_path, error)
  }
}
