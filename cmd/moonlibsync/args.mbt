// SPDX-License-Identifier: LGPL-2.1-or-later

///|
priv suberror CliError {
  Usage(String)
  FileFailure(String)
}

///|
priv enum RunMode {
  WriteFile(String)
  Inspect(Bool)
}

///|
priv enum BlockChoice {
  Explicit(Int64)
  Auto
}

///|
priv struct Plan {
  operation : String
  inputs : Array[String]
  mode : RunMode
  block_choice : BlockChoice
  min_savings : Int64
  basis_path : String?
  options : @lib.SignatureOptions
}

///|
let help_text : String =
  #|MoonLibSync 0.2.0; inspection, reusable signatures and integrity workflows since 0.2.0
  #|Usage:
  #|  moonlibsync signature OLD SIG [--block-size N|auto] [--sum-size N]
  #|  moonlibsync delta SIG NEW DELTA
  #|  moonlibsync patch OLD DELTA OUT
  #|  moonlibsync basis-info OLD SIG INFO
  #|  moonlibsync make-manifest INFO SIG NEW DELTA MANIFEST
  #|  moonlibsync patch-verified OLD DELTA MANIFEST OUT
  #|  moonlibsync inspect-signature SIG [--json]
  #|  moonlibsync inspect-delta DELTA [--json]
  #|  moonlibsync check-patch OLD DELTA [--json]
  #|  moonlibsync make-transfer-manifest INFO SIG NEW DELTA MANIFEST [--min-savings N]
  #|  moonlibsync apply-update PAYLOAD MANIFEST OUT [--basis OLD]
  #|  moonlibsync --help
  #|  moonlibsync --version
  #|Options may appear anywhere after the command before --; -- ends option parsing.
  #|--json is inspection-only. One schema_version=1 object; Int64 fields are decimal strings.
  #|Inspection never creates output files; check-patch queries OLD metadata only.
  #|Range checks do not authenticate basis identity or verify recovered content.
  #|After -- every argument is a path. A lone - is a literal filename, never a pipe.
  #|Defaults: block-size 2048, sum-size 32. Decimal digits only; block 1..1048576, sum 1..32.
  #|auto is explicit policy v1 (development source only, absent from registry 0.2.0).
  #|Selected block length is stored normally in SIG; inspect-signature shows it.
  #|Transfer options are development-only: min-savings is nonnegative Int64 (default 0).
  #|apply-update requires basis for Delta and forbids it for Full; no publisher authentication.
  #|Only stable regular input files are supported; leaf symlinks are rejected.
  #|Existing output entries (including links) are refused; no overwrite option.
  #|Exit codes: 0 success/help/version; 2 usage; 1 file or core error.

///|
fn positive_decimal(text : String, maximum : Int64) -> Int64 raise CliError {
  guard text.length() > 0 else { raise Usage("empty numeric option") }
  let mut value = 0L
  for c in text {
    guard c >= '0' && c <= '9' else { raise Usage("invalid decimal: " + text) }
    let digit = (c.to_int() - 48).to_int64()
    guard value <= (maximum - digit) / 10L else {
      raise Usage("numeric option out of range: " + text)
    }
    value = value * 10L + digit
    guard value <= maximum else {
      raise Usage("numeric option out of range: " + text)
    }
  }
  guard value > 0L else {
    raise Usage("numeric option must be positive: " + text)
  }
  value
}

///|
fn parse_plan(args : ArrayView[String]) -> Plan raise CliError {
  guard args.length() > 0 else { raise Usage("missing command") }
  let operation = args[0]
  let inspection = operation == "inspect-signature" ||
    operation == "inspect-delta" ||
    operation == "check-patch"
  guard inspection ||
    operation == "signature" ||
    operation == "delta" ||
    operation == "patch" ||
    operation == "basis-info" ||
    operation == "make-manifest" ||
    operation == "patch-verified" ||
    operation == "make-transfer-manifest" ||
    operation == "apply-update" else {
    raise Usage("unknown command: " + operation)
  }
  let limits = @lib.Limits::default()
  let needed = if inspection {
    if operation == "check-patch" {
      2
    } else {
      1
    }
  } else if operation == "make-manifest" ||
    operation == "make-transfer-manifest" {
    5
  } else if operation == "patch-verified" {
    4
  } else if operation == "signature" {
    2
  } else {
    3
  }
  let paths : Array[String] = []
  let mut block_choice : BlockChoice = Explicit(2048L)
  let mut min_savings = 0L
  let mut saw_savings = false
  let mut basis_path : String? = None
  let mut sum = 32L
  let mut saw_block = false
  let mut saw_sum = false
  let mut json = false
  let mut options = true
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if options && arg == "--" {
      options = false
    } else if options && arg == "--min-savings" {
      guard operation == "make-transfer-manifest" else {
        raise Usage("transfer-manifest-only option: " + arg)
      }
      guard !saw_savings && i + 1 < args.length() else {
        raise Usage("duplicate or missing --min-savings")
      }
      min_savings = nonnegative_decimal(args[i + 1])
      saw_savings = true
      i = i + 1
    } else if options && arg == "--basis" {
      guard operation == "apply-update" else {
        raise Usage("apply-update-only option: " + arg)
      }
      guard basis_path is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --basis")
      }
      basis_path = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--json" {
      guard inspection else { raise Usage("inspection-only option: --json") }
      guard !json else { raise Usage("duplicate option: --json") }
      json = true
    } else if options && (arg == "--block-size" || arg == "--sum-size") {
      guard operation == "signature" else {
        raise Usage("options are signature-only: " + arg)
      }
      guard i + 1 < args.length() else {
        raise Usage("missing value for " + arg)
      }
      if arg == "--block-size" {
        guard !saw_block else { raise Usage("duplicate option: " + arg) }
        block_choice = if args[i + 1] == "auto" {
          Auto
        } else {
          Explicit(positive_decimal(args[i + 1], limits.max_block_bytes))
        }
        saw_block = true
      } else {
        guard !saw_sum else { raise Usage("duplicate option: " + arg) }
        sum = positive_decimal(args[i + 1], 32L)
        saw_sum = true
      }
      i = i + 1
    } else {
      guard !(options && arg != "-" && arg.has_prefix("-")) else {
        raise Usage("unknown option: " + arg)
      }
      guard arg.length() > 0 else { raise Usage("empty path") }
      guard paths.length() < needed else {
        raise Usage("too many paths for " + operation)
      }
      paths.push(arg)
    }
    i = i + 1
  }
  guard paths.length() == needed else {
    raise Usage("wrong number of paths for " + operation)
  }
  {
    operation,
    inputs: if inspection {
      paths
    } else {
      paths[0:needed - 1].to_owned()
    },
    mode: if inspection {
      Inspect(json)
    } else {
      WriteFile(paths[needed - 1])
    },
    block_choice,
    min_savings,
    basis_path,
    // Keep legacy numeric options valid; Auto is represented only by its enum.
    // The execution path resolves it from the actual bounded-read Bytes.
    options: {
      block_len: match block_choice {
        Explicit(value) => value
        Auto => 2048L
      },
      strong_sum_len: sum,
    },
  }
}

///|
fn cli_error_text(error : Error) -> String {
  match error {
    Usage(message) | FileFailure(message) => message
    @os_error.OsError::OsError(_, raw_code~, context~) =>
      @os_error.OsError::from_errno(raw_code, context~).to_string()
    _ => "\{error}"
  }
}

///|
fn nonnegative_decimal(text : String) -> Int64 raise CliError {
  guard text.length() > 0 else { raise Usage("empty numeric option") }
  let mut n = 0L
  for c in text {
    guard c >= '0' && c <= '9' else { raise Usage("invalid decimal: " + text) }
    let digit = (c.to_int() - 48).to_int64()
    guard n <= (9223372036854775807L - digit) / 10L else {
      raise Usage("numeric option out of range")
    }
    n = n * 10L + digit
  }
  n
}
