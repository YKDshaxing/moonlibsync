// SPDX-License-Identifier: LGPL-2.1-or-later

///|
priv suberror CliError {
  Usage(String)
  FileFailure(String)
}

///|
priv struct Plan {
  operation : String
  inputs : Array[String]
  output : String
  options : @lib.SignatureOptions
}

///|
let help_text : String =
  #|MoonLibSync 0.1.0 (development; not released)
  #|Usage:
  #|  moonlibsync signature OLD SIG [--block-size N] [--sum-size N]
  #|  moonlibsync delta SIG NEW DELTA
  #|  moonlibsync patch OLD DELTA OUT
  #|  moonlibsync --help
  #|  moonlibsync --version
  #|Signature options may appear anywhere before --; -- ends option parsing.
  #|After -- every argument is a path. A lone - is a literal filename, never a pipe.
  #|Defaults: block-size 2048, sum-size 32. Decimal digits only; block 1..1048576, sum 1..32.
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
  guard operation == "signature" || operation == "delta" || operation == "patch" else {
    raise Usage("unknown command: " + operation)
  }
  let limits = @lib.Limits::default()
  let needed = if operation == "signature" { 2 } else { 3 }
  let paths : Array[String] = []
  let mut block = 2048L
  let mut sum = 32L
  let mut saw_block = false
  let mut saw_sum = false
  let mut options = true
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    if options && arg == "--" {
      options = false
    } else if options && (arg == "--block-size" || arg == "--sum-size") {
      guard operation == "signature" else {
        raise Usage("options are signature-only: " + arg)
      }
      guard i + 1 < args.length() else {
        raise Usage("missing value for " + arg)
      }
      if arg == "--block-size" {
        guard !saw_block else { raise Usage("duplicate option: " + arg) }
        block = positive_decimal(args[i + 1], limits.max_block_bytes)
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
    inputs: paths[0:needed - 1].to_owned(),
    output: paths[needed - 1],
    options: { block_len: block, strong_sum_len: sum, },
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
