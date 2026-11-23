// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn core_error_tag(error : Error) -> String {
  match error {
    @lib.SyncError::InvalidOptions(field) => "InvalidOptions:" + field
    @lib.SyncError::UnsupportedSignatureProfile => "UnsupportedSignatureProfile"
    @lib.SyncError::TruncatedInput => "TruncatedInput"
    @lib.SyncError::InvalidSignature => "InvalidSignature"
    @lib.SyncError::InvalidDelta => "InvalidDelta"
    @lib.SyncError::InvalidOpcode => "InvalidOpcode"
    @lib.SyncError::IntegerOutOfRange => "IntegerOutOfRange"
    @lib.SyncError::CopyOutOfBounds => "CopyOutOfBounds"
    @lib.SyncError::TrailingData => "TrailingData"
    @lib.SyncError::LimitExceeded => "LimitExceeded"
    _ => cli_error_text(error)
  }
}

///|
async fn execute(plan : Plan) -> Unit {
  match plan.mode {
    WriteFile(output) =>
      if plan.operation == "dir-snapshot" {
        execute_dir_snapshot(plan, output)
      } else if plan.operation == "dir-pack" {
        execute_dir_bundle_op(plan, output)
      } else if plan.operation == "compress" || plan.operation == "decompress" {
        execute_compress_op(plan, output)
      } else if plan.operation == "keygen" {
        execute_keygen(plan, output)
      } else if plan.operation == "x25519-keygen" {
        execute_x25519_keygen(plan, output)
      } else if plan.operation == "keyring-init" {
        execute_keyring_init(plan, output)
      } else if plan.operation == "sign-combine" {
        execute_sign_combine(plan, output)
      } else if plan.operation == "range-plan" {
        execute_range_plan(plan, Some(output))
      } else if plan.operation == "fetch-sync" {
        execute_fetch_sync(plan, output)
      } else if plan.operation == "compose-delta" {
        execute_compose_delta(plan, output)
      } else if plan.operation == "sign" {
        execute_sign(plan, output)
      } else if plan.operation == "seal" || plan.operation == "unseal" {
        execute_seal_op(plan, output)
      } else if plan.streaming {
        execute_streaming_write(plan, output)
      } else if plan.operation == "make-transfer-manifest" ||
        plan.operation == "apply-update" {
        execute_transfer_write(plan, output)
      } else if plan.operation == "basis-info" ||
        plan.operation == "make-manifest" ||
        plan.operation == "patch-verified" {
        execute_manifest_write(plan, output)
      } else {
        execute_write(plan, output)
      }
    WriteDir(output_dir) => execute_dir_bundle_op(plan, output_dir)
    Inspect(json) =>
      if plan.operation == "dir-plan" {
        execute_dir_plan(plan, json)
      } else if plan.operation == "dir-verify" {
        execute_dir_verify(plan, json)
      } else if plan.operation == "verify" {
        execute_verify(plan, json)
      } else if plan.operation == "verify-quorum" {
        execute_verify_quorum(plan, json)
      } else if plan.operation == "range-plan" {
        execute_range_plan(plan, None)
      } else if plan.operation == "inspect-bundle" {
        execute_inspect_bundle(plan, json)
      } else if plan.operation == "completions" {
        execute_completions(plan)
      } else {
        execute_inspection(plan, json)
      }
  }
}

///|
async fn execute_write(plan : Plan, output_path : String) -> Unit {
  let limits = plan.limits
  limits.validate()
  let output = prepare_output(output_path)
  let first_limit = if plan.operation == "delta" {
    limits.max_signature_bytes
  } else {
    limits.max_old_bytes
  }
  let first = bounded_read(plan.inputs[0], first_limit)
  let second = if plan.operation == "signature" {
    b""
  } else {
    bounded_read(
      plan.inputs[1],
      if plan.operation == "delta" || plan.operation == "reverse-delta" {
        limits.max_new_bytes
      } else {
        limits.max_delta_bytes
      },
    )
  }
  let data = try {
    match plan.operation {
      "signature" =>
        @lib.signature_with_profile(
          first,
          signature_options(plan, first, limits),
          plan.sig_profile,
          limits,
        )
      "delta" => @lib.delta(first, second, limits)
      "reverse-delta" => {
        let rev_limits : @lib.Limits = {
          ..limits,
          max_old_bytes: limits.max_new_bytes,
          max_new_bytes: limits.max_old_bytes,
        }
        @lib.create_reverse_delta(
          first,
          second,
          signature_options(plan, second, rev_limits),
          limits,
        )
      }
      _ => @lib.patch(first, second, limits)
    }
  } catch {
    error =>
      raise FileFailure(
        "core " +
        plan.operation +
        " for '" +
        output_path +
        "': " +
        core_error_tag(error),
      )
  }
  publish_output(output, data)
  emit_instant_progress(
    plan,
    if plan.operation == "signature" {
      first.length().to_int64()
    } else if plan.operation == "reverse-delta" {
      first.length().to_int64() + second.length().to_int64()
    } else {
      second.length().to_int64()
    },
  )
}

///|
async fn diagnose(text : String) -> Unit {
  @stdio.stderr.write(@utf8.encode("moonlibsync: " + text + "\n")) catch {
    _ => ()
  }
}

///|
async fn main {
  let args = @env.args()
  try {
    if args.length() == 2 && args[1] == "--help" {
      @stdio.stdout.write(@utf8.encode(help_text + "\n"))
    } else if args.length() == 2 && args[1] == "--version" {
      @stdio.stdout.write(b"MoonLibSync 0.7.1\n")
    } else {
      execute(parse_plan(args[1:]))
    }
  } catch {
    Usage(message) => {
      diagnose("usage: " + message + "; see --help")
      @env.exit(2)
    }
    FileFailure(message) => {
      diagnose(message)
      @env.exit(1)
    }
    error => {
      diagnose("file operation failed: \{cli_error_text(error)}")
      @env.exit(1)
    }
  }
}

///|
/// Use actual read bytes, never an earlier path stat; no zero sentinel enters API.
fn signature_options(
  plan : Plan,
  basis : Bytes,
  limits : @lib.Limits,
) -> @lib.SignatureOptions raise @lib.SyncError {
  let block = match plan.block_choice {
    Explicit(value) => value
    Auto =>
      @lib.recommend_block_len(
        basis.length().to_int64(),
        plan.options.strong_sum_len,
        limits,
      )
  }
  { block_len: block, strong_sum_len: plan.options.strong_sum_len, }
}
