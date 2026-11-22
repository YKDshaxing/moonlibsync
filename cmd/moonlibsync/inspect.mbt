// SPDX-License-Identifier: LGPL-2.1-or-later

///|
/// Strictly controlled JSON: only constant keys/labels and typed integers.
/// No paths, user strings, floating-point conversions or raw binary payloads.
fn delta_json(s : @lib.DeltaSummary) -> String {
  "{\"delta_bytes\":\"\{s.delta_bytes}\",\"instruction_count\":\"\{s.instruction_count}\",\"literal_commands\":\"\{s.literal_commands}\",\"copy_commands\":\"\{s.copy_commands}\",\"literal_bytes\":\"\{s.literal_bytes}\",\"copy_bytes\":\"\{s.copy_bytes}\",\"output_bytes\":\"\{s.output_bytes}\"}"
}

///|
fn delta_text(s : @lib.DeltaSummary) -> String {
  "delta_bytes: \{s.delta_bytes} bytes\ninstruction_count: \{s.instruction_count}\nliteral_commands: \{s.literal_commands}\ncopy_commands: \{s.copy_commands}\nliteral_bytes: \{s.literal_bytes} bytes\ncopy_bytes: \{s.copy_bytes} bytes\noutput_bytes: \{s.output_bytes} bytes"
}

///|
fn format_signature(s : @lib.SignatureSummary, json : Bool) -> String {
  let (magic_hex, profile_name) = if s.magic == 0x72730137U {
    ("0x72730137", "RS_BLAKE2_SIG_MAGIC")
  } else {
    ("0x72730147", "RS_RK_BLAKE2_SIG_MAGIC")
  }
  if json {
    "{\"schema_version\":1,\"command\":\"inspect-signature\",\"summary\":{\"magic\":\"\{magic_hex}\",\"profile\":\"\{profile_name}\",\"block_len\":\"\{s.block_len}\",\"strong_sum_len\":\"\{s.strong_sum_len}\",\"record_count\":\"\{s.record_count}\",\"signature_bytes\":\"\{s.signature_bytes}\"}}\n"
  } else {
    "inspect-signature\nmagic: \{magic_hex}\nprofile: \{profile_name}\nblock_len: \{s.block_len} bytes\nstrong_sum_len: \{s.strong_sum_len} bytes\nrecord_count: \{s.record_count}\nsignature_bytes: \{s.signature_bytes} bytes\nActual basis and final-block lengths are not encoded.\n"
  }
}

///|
fn format_delta(s : @lib.DeltaSummary, json : Bool) -> String {
  if json {
    "{\"schema_version\":1,\"command\":\"inspect-delta\",\"summary\":\{delta_json(s)}}\n"
  } else {
    "inspect-delta\n\{delta_text(s)}\nFormat only; COPY ranges require a basis length.\n"
  }
}

///|
fn format_patch(s : @lib.PatchCheck, json : Bool) -> String {
  if json {
    "{\"schema_version\":1,\"command\":\"check-patch\",\"basis_bytes\":\"\{s.basis_bytes}\",\"summary\":\{delta_json(s.summary)}}\n"
  } else {
    "check-patch\nbasis_bytes: \{s.basis_bytes} bytes\n\{delta_text(s.summary)}\nFormat and length ranges only; no basis identity or recovered content verification.\n"
  }
}

///|
/// Metadata-only basis path: no read/read_at, buffer allocation or hashing.
/// The injectable reader receives only the delta path, never the basis path.
async fn check_open_basis(
  basis : @fs.File,
  basis_path : String,
  delta_path : String,
  limits : @lib.Limits,
  reader~ : async (String, Int64) -> Bytes = bounded_read,
) -> @lib.PatchCheck {
  guard basis.kind() is @fs.FileKind::Regular else {
    raise FileFailure("unsupported input kind: " + basis_path)
  }
  let length = basis.size()
  let delta = reader(delta_path, limits.max_delta_bytes)
  let result = @lib.check_patch(length, delta, limits)
  guard basis.size() == length else {
    raise FileFailure("InputChanged: basis size changed: " + basis_path)
  }
  result
}

///|
async fn check_patch_file(
  old : String,
  delta : String,
  limits : @lib.Limits,
) -> @lib.PatchCheck {
  let file = open_regular_input(old)
  defer file.close()
  check_open_basis(file, old, delta, limits)
}

///|
fn digest_json(d : @lib.FileDigest) -> String {
  "{\"byte_length\":\"\{d.byte_length}\",\"sha256\":\"\{d.sha256}\"}"
}

///|
fn digest_text(name : String, d : @lib.FileDigest) -> String {
  "\{name}.byte_length: \{d.byte_length} bytes\n\{name}.sha256: \{d.sha256}"
}

///|
priv enum ParsedManifest {
  Transfer(@lib.TransferManifest)
  Update(@lib.UpdateManifest)
  Basis(@lib.BasisInfo)
}

///|
fn parse_any_manifest(
  input : Bytes,
  limits : @lib.Limits,
) -> ParsedManifest raise @lib.ManifestError {
  Transfer(@lib.parse_transfer_manifest(input, limits)) catch {
    @lib.ManifestError::InvalidSchema =>
      Update(@lib.parse_update_manifest(input, limits)) catch {
        @lib.ManifestError::InvalidSchema =>
          Basis(@lib.parse_basis_info(input, limits))
        other => raise other
      }
    other => raise other
  }
}

///|
fn format_manifest(parsed : ParsedManifest, json : Bool) -> String {
  if json {
    let body = match parsed {
      Transfer(Delta(m)) =>
        "{\"manifest_schema_version\":2,\"kind\":\"librsync-delta\",\"basis\":\{digest_json(m.basis)},\"signature\":\{digest_json(m.signature)},\"payload\":\{digest_json(m.delta)},\"result\":\{digest_json(m.result)}}"
      Transfer(Full(p, r)) =>
        "{\"manifest_schema_version\":2,\"kind\":\"full-file\",\"payload\":\{digest_json(p)},\"result\":\{digest_json(r)}}"
      Update(m) =>
        "{\"manifest_schema_version\":1,\"kind\":\"librsync-delta\",\"basis\":\{digest_json(m.basis)},\"signature\":\{digest_json(m.signature)},\"delta\":\{digest_json(m.delta)},\"result\":\{digest_json(m.result)}}"
      Basis(b) =>
        "{\"manifest_schema_version\":1,\"kind\":\"moonlibsync-basis-info\",\"basis\":\{digest_json(b.basis)},\"signature\":\{digest_json(b.signature)}}"
    }
    "{\"schema_version\":1,\"command\":\"inspect-manifest\",\"manifest\":\{body}}\n"
  } else {
    let lines = match parsed {
      Transfer(Delta(m)) =>
        "manifest_schema_version: 2\nkind: librsync-delta\n\{digest_text("basis", m.basis)}\n\{digest_text("signature", m.signature)}\n\{digest_text("payload", m.delta)}\n\{digest_text("result", m.result)}"
      Transfer(Full(p, r)) =>
        "manifest_schema_version: 2\nkind: full-file\n\{digest_text("payload", p)}\n\{digest_text("result", r)}"
      Update(m) =>
        "manifest_schema_version: 1\nkind: librsync-delta\n\{digest_text("basis", m.basis)}\n\{digest_text("signature", m.signature)}\n\{digest_text("delta", m.delta)}\n\{digest_text("result", m.result)}"
      Basis(b) =>
        "manifest_schema_version: 1\nkind: moonlibsync-basis-info\n\{digest_text("basis", b.basis)}\n\{digest_text("signature", b.signature)}"
    }
    "inspect-manifest\n\{lines}\nFormat and limits only; actual referenced files were not read or authenticated.\n"
  }
}

///|
fn inspect_error_tag(error : Error) -> String {
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
        _ => core_error_tag(error)
      }
  }
}

///|
async fn stream_inspect_delta_file(
  delta_path : String,
  limits : @lib.Limits,
  progress~ : ProgressReporter? = None,
) -> @lib.DeltaSummary {
  let file = open_regular_input(delta_path)
  defer file.close()
  let size = check_open_regular_sized(file, delta_path, limits.max_delta_bytes)
  match progress {
    Some(p) => if p.total < 0L { p.total = size }
    None => ()
  }
  let dec = @lib.PatchDecoder::new_format_only(limits)
  stream_open_chunks(file, delta_path, size, progress~, chunk => {
    dec.feed_inspect(chunk)
  })
  dec.finish()
}

///|
async fn stream_check_patch_file(
  old_path : String,
  delta_path : String,
  limits : @lib.Limits,
  progress~ : ProgressReporter? = None,
) -> @lib.PatchCheck {
  let basis = open_regular_input(old_path)
  defer basis.close()
  guard basis.kind() is @fs.FileKind::Regular else {
    raise FileFailure("unsupported input kind: " + old_path)
  }
  let basis_len = basis.size()
  let dec = @lib.PatchDecoder::new(basis_len, limits)
  let delta_file = open_regular_input(delta_path)
  defer delta_file.close()
  let delta_size = check_open_regular_sized(
    delta_file,
    delta_path,
    limits.max_delta_bytes,
  )
  match progress {
    Some(p) => if p.total < 0L { p.total = delta_size }
    None => ()
  }
  stream_open_chunks(delta_file, delta_path, delta_size, progress~, chunk => {
    dec.feed_inspect(chunk)
  })
  let summary = dec.finish()
  guard basis.size() == basis_len else {
    raise FileFailure("InputChanged: basis size changed: " + old_path)
  }
  { basis_bytes: basis_len, summary, }
}

///|
async fn execute_inspection(plan : Plan, json : Bool) -> Unit {
  let limits = plan.limits
  let progress = make_progress(plan, -1L)
  // Finish validation and formatting before the first stdout write.
  let text = try {
    limits.validate()
    match plan.operation {
      "inspect-signature" => {
        let raw = bounded_read(plan.inputs[0], limits.max_signature_bytes)
        let formatted = format_signature(
          @lib.inspect_signature(raw, limits),
          json,
        )
        advance_progress(progress, raw.length().to_int64())
        formatted
      }
      "inspect-delta" =>
        if plan.streaming {
          format_delta(
            stream_inspect_delta_file(plan.inputs[0], limits, progress~),
            json,
          )
        } else {
          let raw = bounded_read(plan.inputs[0], limits.max_delta_bytes)
          let formatted = format_delta(@lib.inspect_delta(raw, limits), json)
          advance_progress(progress, raw.length().to_int64())
          formatted
        }
      "inspect-manifest" => {
        let raw = bounded_read(plan.inputs[0], 65536L)
        let formatted = format_manifest(parse_any_manifest(raw, limits), json)
        advance_progress(progress, raw.length().to_int64())
        formatted
      }
      _ =>
        if plan.streaming {
          format_patch(
            stream_check_patch_file(
              plan.inputs[0],
              plan.inputs[1],
              limits,
              progress~,
            ),
            json,
          )
        } else {
          let checked = check_patch_file(plan.inputs[0], plan.inputs[1], limits)
          advance_progress(progress, checked.summary.delta_bytes)
          format_patch(checked, json)
        }
    }
  } catch {
    error => {
      let detail = inspect_error_tag(error)
      raise FileFailure(
        plan.operation + " inputs '\{plan.inputs.join("', '")}': " + detail,
      )
    }
  }
  // Propagate write failures to main's exit=1 handler; stdout is not transactional.
  write_inspection(text) catch {
    error =>
      raise FileFailure(
        "stdout " +
        plan.operation +
        " inputs '\{plan.inputs.join("', '")}': " +
        cli_error_text(error),
      )
  }
  finish_progress(progress)
}

///|
async fn stdout_bytes(data : Bytes) -> Unit {
  @stdio.stdout.write(data)
}

///|
async fn write_inspection(
  text : String,
  writer~ : async (Bytes) -> Unit = stdout_bytes,
) -> Unit {
  writer(@utf8.encode(text))
}

///|
fn format_inspect_bundle(
  manifest : @lib.DirBundleManifest,
  archive_size : Int64,
  gzip : Bool,
  dir_limits : @lib.DirLimits,
  limits : @lib.Limits,
  json : Bool,
) -> String raise @lib.ManifestError {
  if json {
    let encoded = @lib.encode_dir_bundle_manifest(manifest, dir_limits, limits)
    let raw_str = @utf8.decode(encoded, ignore_bom=false) catch {
      _ => raise @lib.ManifestError::InvalidUtf8
    }
    let manifest_json = trim_trailing_newline(raw_str)
    "{\"schema_version\":1,\"command\":\"inspect-bundle\",\"archive_bytes\":\"\{archive_size}\",\"gzip\":\{gzip},\"manifest\":\{manifest_json}}\n"
  } else {
    let out = StringBuilder()
    out.write_string("inspect-bundle\n")
    out.write_string("archive_bytes: \{archive_size} bytes\n")
    out.write_string("gzip: \{gzip}\n")
    out.write_string("unchanged: \{manifest.unchanged_count}\n")
    out.write_string("add_full: \{manifest.add_full_count}\n")
    out.write_string("update_delta: \{manifest.update_delta_count}\n")
    out.write_string("update_full: \{manifest.update_full_count}\n")
    out.write_string("delete: \{manifest.delete_count}\n")
    out.write_string("copy_from_basis: \{manifest.copy_from_basis_count}\n")
    out.write_string(
      "total_payload_bytes: \{manifest.total_payload_bytes} bytes\n",
    )
    out.write_string("entries: \{manifest.entries.length()}\n")
    for entry in manifest.entries {
      match entry.action {
        Unchanged(_) => out.write_string("  unchanged: \{entry.path}\n")
        AddFull(_, _) => out.write_string("  add-full: \{entry.path}\n")
        UpdateDelta(_, _) => out.write_string("  update-delta: \{entry.path}\n")
        UpdateFull(_, _, _) =>
          out.write_string("  update-full: \{entry.path}\n")
        Delete(_) => out.write_string("  delete: \{entry.path}\n")
        CopyFromBasis(src, _) =>
          out.write_string("  copy-from-basis: \{entry.path} <- \{src}\n")
        UpdateDeltaFrom(src, _, _) =>
          out.write_string("  update-delta-from: \{entry.path} <- \{src}\n")
      }
    }
    out.write_string(
      "Read-only bundle archive inspection; no filesystem entries were modified.\n",
    )
    out.to_string()
  }
}

///|
async fn execute_inspect_bundle(
  plan : Plan,
  json : Bool,
  writer~ : async (Bytes) -> Unit = stdout_bytes,
) -> Unit {
  let limits = plan.limits
  let dir_limits = plan.dir_limits
  let progress = make_progress(plan, -1L)
  let text = try {
    limits.validate()
    dir_limits.validate()
    let archive_path = plan.inputs[0]
    let archive_file = open_regular_input(archive_path)
    defer archive_file.close()
    let archive_size = check_open_regular_sized(
      archive_file, archive_path, 2147483647L,
    )
    match progress {
      Some(p) => if p.total < 0L { p.total = archive_size }
      None => ()
    }
    let arch_dec = @lib.BundleArchiveDecoder::new(dir_limits, limits)
    let expected_digests : Map[String, @lib.FileDigest] = Map([])
    let mut active_hasher : @lib.Sha256Hasher? = None
    let mut active_expected : @lib.FileDigest? = None
    let mut active_path = ""
    fn feed_archive(view : BytesView) -> Unit raise @lib.ManifestError {
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
            guard active_hasher is None else {
              raise @lib.ManifestError::InvalidSchema
            }
            let exp = match expected_digests.get(rel_payload) {
              Some(d) => d
              None =>
                raise @lib.ManifestError::BindingMismatch(
                  "archive_payload_path",
                )
            }
            guard exp.byte_length == payload_len else {
              raise @lib.ManifestError::BindingMismatch(
                "archive_payload_length",
              )
            }
            active_hasher = Some(@lib.Sha256Hasher::new(payload_len))
            active_expected = Some(exp)
            active_path = rel_payload
          }
          PayloadChunk(data_view) =>
            match active_hasher {
              Some(h) => h.update(data_view)
              None => raise @lib.ManifestError::InvalidSchema
            }
          EndPayload(rel_payload) => {
            guard rel_payload == active_path else {
              raise @lib.ManifestError::InvalidSchema
            }
            match (active_hasher, active_expected) {
              (Some(h), Some(exp)) => {
                active_hasher = None
                active_expected = None
                active_path = ""
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
        feed_archive(chunk)
      })
    }
    if arch_dec.has_pending_event() {
      feed_archive(b""[:])
    }
    let manifest = arch_dec.finish()
    guard active_hasher is None else { raise @lib.ManifestError::InvalidSchema }
    format_inspect_bundle(
      manifest,
      archive_size,
      plan.gzip,
      dir_limits,
      limits,
      json,
    )
  } catch {
    error => {
      let detail = inspect_error_tag(error)
      raise FileFailure(
        "inspect-bundle inputs '\{plan.inputs.join("', '")}': " + detail,
      )
    }
  }
  write_inspection(text, writer~) catch {
    error =>
      raise FileFailure(
        "stdout inspect-bundle inputs '\{plan.inputs.join("', '")}': " +
        cli_error_text(error),
      )
  }
  finish_progress(progress)
}
