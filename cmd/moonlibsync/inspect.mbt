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
  if json {
    "{\"schema_version\":1,\"command\":\"inspect-signature\",\"summary\":{\"magic\":\"0x72730147\",\"profile\":\"RS_RK_BLAKE2_SIG_MAGIC\",\"block_len\":\"\{s.block_len}\",\"strong_sum_len\":\"\{s.strong_sum_len}\",\"record_count\":\"\{s.record_count}\",\"signature_bytes\":\"\{s.signature_bytes}\"}}\n"
  } else {
    "inspect-signature\nmagic: 0x72730147\nprofile: RS_RK_BLAKE2_SIG_MAGIC\nblock_len: \{s.block_len} bytes\nstrong_sum_len: \{s.strong_sum_len} bytes\nrecord_count: \{s.record_count}\nsignature_bytes: \{s.signature_bytes} bytes\nActual basis and final-block lengths are not encoded.\n"
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
