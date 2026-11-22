// SPDX-License-Identifier: LGPL-2.1-or-later

///|
priv suberror CliError {
  Usage(String)
  FileFailure(String)
}

///|
priv enum RunMode {
  WriteFile(String)
  WriteDir(String)
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
  streaming : Bool
  options : @lib.SignatureOptions
  limits : @lib.Limits
  dir_limits : @lib.DirLimits
}

///|
let help_text : String =
  #|MoonLibSync 0.4.0; streaming pipelines, directory sync bundles, gzip framing, manifests and transfer workflows
  #|Usage:
  #|  moonlibsync signature OLD SIG [--streaming] [--block-size N|auto] [--sum-size N] [LIMITS]
  #|  moonlibsync delta SIG NEW DELTA [--streaming] [LIMITS]
  #|  moonlibsync patch OLD DELTA OUT [--streaming] [LIMITS]
  #|  moonlibsync basis-info OLD SIG INFO [--streaming] [LIMITS]
  #|  moonlibsync make-manifest INFO SIG NEW DELTA MANIFEST [--streaming] [LIMITS]
  #|  moonlibsync patch-verified OLD DELTA MANIFEST OUT [--streaming] [LIMITS]
  #|  moonlibsync inspect-signature SIG [--json] [LIMITS]
  #|  moonlibsync inspect-delta DELTA [--json] [--streaming] [LIMITS]
  #|  moonlibsync check-patch OLD DELTA [--json] [--streaming] [LIMITS]
  #|  moonlibsync inspect-manifest MANIFEST [--json] [LIMITS]
  #|  moonlibsync make-transfer-manifest INFO SIG NEW DELTA MANIFEST [--min-savings N] [--streaming] [LIMITS]
  #|  moonlibsync apply-update PAYLOAD MANIFEST OUT [--basis OLD] [--streaming] [LIMITS]
  #|  moonlibsync compress IN OUT [--streaming] [LIMITS]
  #|  moonlibsync decompress IN OUT [--streaming] [LIMITS]
  #|  moonlibsync dir-snapshot DIR OUT [DIR_LIMITS]
  #|  moonlibsync dir-plan BASIS_SNAP TARGET_SNAP [--json] [DIR_LIMITS]
  #|  moonlibsync dir-signatures DIR SNAPSHOT SIG_DIR [--block-size N|auto] [--sum-size N] [--streaming] [LIMITS] [DIR_LIMITS]
  #|  moonlibsync dir-pack BASIS_SNAP SIG_DIR TARGET_DIR BUNDLE_DIR [--streaming] [--min-savings N] [LIMITS] [DIR_LIMITS]
  #|  moonlibsync dir-apply BASIS_DIR BUNDLE_DIR OUT_DIR [--streaming] [LIMITS] [DIR_LIMITS]
  #|  moonlibsync --help
  #|  moonlibsync --version
  #|Options may appear anywhere after the command before --; -- ends option parsing.
  #|--streaming uses bounded 64 KiB chunks (all file/bundle commands except inspect-signature, inspect-manifest, dir-snapshot, dir-plan).
  #|Optional [LIMITS] overrides (default Limits::default()):
  #|  --max-old-bytes N  --max-new-bytes N  --max-signature-bytes N
  #|  --max-signature-records N  --max-block-bytes N  --max-delta-bytes N
  #|  --max-output-bytes N  --max-instructions N  --max-match-work N
  #|Optional [DIR_LIMITS] overrides for dir-* commands (default DirLimits::default()):
  #|  --max-entries N  --max-path-bytes N  --max-depth N
  #|  --max-snapshot-bytes N  --max-file-bytes N
  #|--json is inspection-only (inspect-* and dir-plan). Int64 fields are decimal strings.
  #|inspect-manifest validates schema1/schema2 JSON structure without reading payload files.
  #|compress/decompress use bounded single-member RFC 1952 gzip (zip-bomb and trailing-data safe).
  #|dir-* commands reject all symlinks and unsafe/colliding paths; dir-apply never modifies BASIS_DIR.
  #|After -- every argument is a path. A lone - is a literal filename, never a pipe.
  #|Defaults: block-size 2048, sum-size 32. Decimal digits only; block 1..max-block-bytes, sum 1..32.
  #|Only stable regular input files are supported; leaf symlinks are rejected.
  #|Existing output entries (including links and directories) are refused; no overwrite option.
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
fn is_limit_flag(flag : String) -> Bool {
  flag == "--max-old-bytes" ||
  flag == "--max-new-bytes" ||
  flag == "--max-signature-bytes" ||
  flag == "--max-signature-records" ||
  flag == "--max-block-bytes" ||
  flag == "--max-delta-bytes" ||
  flag == "--max-output-bytes" ||
  flag == "--max-instructions" ||
  flag == "--max-match-work"
}

///|
fn is_dir_limit_flag(flag : String) -> Bool {
  flag == "--max-entries" ||
  flag == "--max-path-bytes" ||
  flag == "--max-depth" ||
  flag == "--max-snapshot-bytes" ||
  flag == "--max-file-bytes"
}

///|
fn bounded_decimal(
  text : String,
  minimum : Int64,
  maximum : Int64,
) -> Int64 raise CliError {
  let n = nonnegative_decimal(text)
  guard n >= minimum && n <= maximum else {
    raise Usage("numeric option out of range: " + text)
  }
  n
}

///|
fn parse_limit_value(flag : String, text : String) -> Int64 raise CliError {
  if flag == "--max-block-bytes" {
    positive_decimal(text, 2147483647L)
  } else {
    bounded_decimal(text, 0L, 2147483647L)
  }
}

///|
fn apply_limit_flag(
  limits : @lib.Limits,
  flag : String,
  value : Int64,
) -> @lib.Limits raise CliError {
  match flag {
    "--max-old-bytes" => { ..limits, max_old_bytes: value, }
    "--max-new-bytes" => { ..limits, max_new_bytes: value, }
    "--max-signature-bytes" => { ..limits, max_signature_bytes: value, }
    "--max-signature-records" => { ..limits, max_signature_records: value, }
    "--max-block-bytes" => { ..limits, max_block_bytes: value, }
    "--max-delta-bytes" => { ..limits, max_delta_bytes: value, }
    "--max-output-bytes" => { ..limits, max_output_bytes: value, }
    "--max-instructions" => { ..limits, max_instructions: value, }
    "--max-match-work" => { ..limits, max_match_work: value, }
    _ => raise Usage("unknown option: " + flag)
  }
}

///|
fn parse_dir_limit_value(flag : String, text : String) -> Int64 raise CliError {
  match flag {
    "--max-entries" => bounded_decimal(text, 0L, 65536L)
    "--max-path-bytes" => bounded_decimal(text, 1L, 4096L)
    "--max-depth" => bounded_decimal(text, 1L, 64L)
    "--max-snapshot-bytes" => bounded_decimal(text, 64L, 16777216L)
    "--max-file-bytes" => bounded_decimal(text, 0L, 2147483647L)
    _ => raise Usage("unknown option: " + flag)
  }
}

///|
fn apply_dir_limit_flag(
  limits : @lib.DirLimits,
  flag : String,
  value : Int64,
) -> @lib.DirLimits raise CliError {
  match flag {
    "--max-entries" => { ..limits, max_entries: value, }
    "--max-path-bytes" => { ..limits, max_path_bytes: value, }
    "--max-depth" => { ..limits, max_depth: value, }
    "--max-snapshot-bytes" => { ..limits, max_snapshot_bytes: value, }
    "--max-file-bytes" => { ..limits, max_file_bytes: value, }
    _ => raise Usage("unknown option: " + flag)
  }
}

///|
fn supports_streaming(operation : String) -> Bool {
  operation == "signature" ||
  operation == "delta" ||
  operation == "patch" ||
  operation == "basis-info" ||
  operation == "make-manifest" ||
  operation == "patch-verified" ||
  operation == "inspect-delta" ||
  operation == "check-patch" ||
  operation == "make-transfer-manifest" ||
  operation == "apply-update" ||
  operation == "compress" ||
  operation == "decompress" ||
  operation == "dir-signatures" ||
  operation == "dir-pack" ||
  operation == "dir-apply"
}

///|
fn parse_plan(args : ArrayView[String]) -> Plan raise CliError {
  guard args.length() > 0 else { raise Usage("missing command") }
  let operation = args[0]
  let dir_only_op = operation == "dir-snapshot" || operation == "dir-plan"
  let dir_bundle_op = operation == "dir-signatures" ||
    operation == "dir-pack" ||
    operation == "dir-apply"
  let accepts_dir_limits = dir_only_op || dir_bundle_op
  let accepts_file_limits = !dir_only_op
  let inspection = operation == "inspect-signature" ||
    operation == "inspect-delta" ||
    operation == "check-patch" ||
    operation == "inspect-manifest" ||
    operation == "dir-plan"
  guard inspection ||
    accepts_dir_limits ||
    operation == "signature" ||
    operation == "delta" ||
    operation == "patch" ||
    operation == "basis-info" ||
    operation == "make-manifest" ||
    operation == "patch-verified" ||
    operation == "make-transfer-manifest" ||
    operation == "apply-update" ||
    operation == "compress" ||
    operation == "decompress" else {
    raise Usage("unknown command: " + operation)
  }
  let mut limits = @lib.Limits::default()
  let mut dir_limits = @lib.DirLimits::default()
  let seen_limits : Map[String, Bool] = Map([])
  let needed = if operation == "dir-plan" || operation == "check-patch" {
    2
  } else if inspection {
    1
  } else if operation == "make-manifest" ||
    operation == "make-transfer-manifest" {
    5
  } else if operation == "patch-verified" || operation == "dir-pack" {
    4
  } else if operation == "signature" ||
    operation == "dir-snapshot" ||
    operation == "compress" ||
    operation == "decompress" {
    2
  } else {
    3
  }
  let paths : Array[String] = []
  let mut block_choice : BlockChoice = Explicit(2048L)
  let mut min_savings = 0L
  let mut saw_savings = false
  let mut basis_path : String? = None
  let mut streaming = false
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
    } else if options && arg == "--streaming" {
      guard supports_streaming(operation) else {
        raise Usage("streaming is not supported for command: " + operation)
      }
      guard !streaming else { raise Usage("duplicate option: --streaming") }
      streaming = true
    } else if options && is_limit_flag(arg) {
      guard accepts_file_limits else {
        raise Usage("file-only limit option: " + arg)
      }
      guard !seen_limits.contains(arg) && i + 1 < args.length() else {
        raise Usage("duplicate or missing value for " + arg)
      }
      let value = parse_limit_value(arg, args[i + 1])
      limits = apply_limit_flag(limits, arg, value)
      seen_limits[arg] = true
      i = i + 1
    } else if options && is_dir_limit_flag(arg) {
      guard accepts_dir_limits else {
        raise Usage("directory-only limit option: " + arg)
      }
      guard !seen_limits.contains(arg) && i + 1 < args.length() else {
        raise Usage("duplicate or missing value for " + arg)
      }
      let value = parse_dir_limit_value(arg, args[i + 1])
      dir_limits = apply_dir_limit_flag(dir_limits, arg, value)
      seen_limits[arg] = true
      i = i + 1
    } else if options && arg == "--min-savings" {
      guard operation == "make-transfer-manifest" || operation == "dir-pack" else {
        raise Usage("transfer-manifest/dir-pack-only option: " + arg)
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
      guard operation == "signature" || operation == "dir-signatures" else {
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
          Explicit(positive_decimal(args[i + 1], 2147483647L))
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
  match block_choice {
    Explicit(value) =>
      if saw_block && value > limits.max_block_bytes {
        raise Usage("block-size exceeds max-block-bytes")
      }
    Auto => ()
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
    } else if dir_bundle_op {
      WriteDir(paths[needed - 1])
    } else {
      WriteFile(paths[needed - 1])
    },
    block_choice,
    min_savings,
    basis_path,
    streaming,
    // Keep legacy numeric options valid; Auto is represented only by its enum.
    // The execution path resolves it from the actual bounded file size.
    options: {
      block_len: match block_choice {
        Explicit(value) => value
        Auto => 2048L
      },
      strong_sum_len: sum,
    },
    limits,
    dir_limits,
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
