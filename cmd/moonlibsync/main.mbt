// SPDX-License-Identifier: LGPL-2.1-or-later

///|
fn core_error_tag(error : @lib.SyncError) -> String {
  match error {
    InvalidOptions(field) => "InvalidOptions:" + field
    UnsupportedSignatureProfile => "UnsupportedSignatureProfile"
    TruncatedInput => "TruncatedInput"
    InvalidSignature => "InvalidSignature"
    InvalidDelta => "InvalidDelta"
    InvalidOpcode => "InvalidOpcode"
    IntegerOutOfRange => "IntegerOutOfRange"
    CopyOutOfBounds => "CopyOutOfBounds"
    TrailingData => "TrailingData"
    LimitExceeded => "LimitExceeded"
  }
}

///|
async fn execute(plan : Plan) -> Unit {
  let limits = @lib.Limits::default()
  limits.validate()
  let output = prepare_output(plan.output)
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
      if plan.operation == "delta" {
        limits.max_new_bytes
      } else {
        limits.max_delta_bytes
      },
    )
  }
  let data = try {
    match plan.operation {
      "signature" => @lib.signature(first, plan.options, limits)
      "delta" => @lib.delta(first, second, limits)
      _ => @lib.patch(first, second, limits)
    }
  } catch {
    error =>
      raise FileFailure(
        "core " +
        plan.operation +
        " for '" +
        plan.output +
        "': " +
        core_error_tag(error),
      )
  }
  publish_output(output, data)
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
      @stdio.stdout.write(b"MoonLibSync 0.1.0 (development; not released)\n")
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
