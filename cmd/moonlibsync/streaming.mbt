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
        plan.operation + " for '" + output_path + "': \{cli_error_text(error)}",
      )
  }
}

///|
async fn stream_verify_basis_sha(
  basis_file : @fs.File,
  basis_path : String,
  expected : @lib.FileDigest,
  limits : @lib.Limits,
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
  stream_open_chunks(basis_file, basis_path, size, chunk => hasher.update(chunk))
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
) -> Unit {
  let old_file = open_regular_input(basis_path)
  defer old_file.close()
  let old_size = stream_verify_basis_sha(old_file, basis_path, m.basis, limits)
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
    stream_open_chunks(delta_file, delta_path, delta_size, chunk => {
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
async fn execute_streaming_write(plan : Plan, output_path : String) -> Unit {
  let limits = plan.limits
  try {
    limits.validate()
    match plan.operation {
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
        let hasher = @lib.SignatureHasher::new(
          { block_len: block, strong_sum_len: plan.options.strong_sum_len, },
          limits,
        )
        let output = prepare_output(output_path)
        publish_stream(output, tmp_file => {
          write_nonempty(tmp_file, hasher.take_ready()[:])
          stream_open_chunks(old_file, old_path, old_size, chunk => {
            hasher.update(chunk)
            write_nonempty(tmp_file, hasher.take_ready()[:])
          })
          write_nonempty(tmp_file, hasher.finish()[:])
        })
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
        publish_stream(output, tmp_file => {
          write_nonempty(tmp_file, scanner.take_ready()[:])
          stream_open_chunks(new_file, new_path, new_size, chunk => {
            scanner.feed(chunk)
            write_nonempty(tmp_file, scanner.take_ready()[:])
          })
          write_nonempty(tmp_file, scanner.finish()[:])
        })
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
        publish_stream(output, tmp_file => {
          stream_open_chunks(delta_file, delta_path, delta_size, chunk => {
            drive_streaming_patch(dec, chunk, old_file, old_path, copy_buf, view => {
              write_nonempty(tmp_file, view)
            })
          })
          guard old_file.size() == basis_len else {
            raise FileFailure("InputChanged: basis size changed: " + old_path)
          }
          let _ = dec.finish()
        })
      }
      "patch-verified" => {
        let manifest_bytes = bounded_read(plan.inputs[2], 65536L)
        let manifest = @lib.parse_update_manifest(manifest_bytes, limits)
        execute_verified_streaming_delta(
          plan.inputs[0],
          plan.inputs[1],
          output_path,
          manifest,
          limits,
        )
      }
      _ => {
        let manifest_bytes = bounded_read(plan.inputs[1], 65536L)
        let manifest = @lib.parse_transfer_manifest(manifest_bytes, limits)
        match manifest {
          @lib.TransferManifest::Delta(m) => {
            guard plan.basis_path is Some(bpath) else {
              raise Usage("Delta requires --basis OLD")
            }
            execute_verified_streaming_delta(
              bpath,
              plan.inputs[0],
              output_path,
              m,
              limits,
            )
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
            publish_stream(output, tmp_file => {
              stream_open_chunks(payload_file, payload_path, payload_size, chunk => {
                hasher.update(chunk)
                write_nonempty(tmp_file, chunk)
              })
              let actual = hasher.finish()
              guard actual.sha256 == payload_desc.sha256 else {
                raise @lib.ManifestError::BindingMismatch("payload_sha256")
              }
            })
          }
        }
      }
    }
  } catch {
    error => raise wrap_stream_error(plan, output_path, error)
  }
}
