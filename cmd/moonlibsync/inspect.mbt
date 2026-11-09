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
async fn execute_inspection(plan : Plan, json : Bool) -> Unit {
  let limits = @lib.Limits::default()
  // Finish validation and formatting before the first stdout write.
  let text = try {
    limits.validate()
    match plan.operation {
      "inspect-signature" =>
        format_signature(
          @lib.inspect_signature(
            bounded_read(plan.inputs[0], limits.max_signature_bytes),
            limits,
          ),
          json,
        )
      "inspect-delta" =>
        format_delta(
          @lib.inspect_delta(
            bounded_read(plan.inputs[0], limits.max_delta_bytes),
            limits,
          ),
          json,
        )
      _ =>
        format_patch(
          check_patch_file(plan.inputs[0], plan.inputs[1], limits),
          json,
        )
    }
  } catch {
    error => {
      let detail = core_error_tag(error)
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
