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
priv enum ExcludeSource {
  Pattern(String)
  File(String)
}

///|
priv enum CompressFormat {
  Gzip
  Zlib
  Deflate
}

///|
priv struct Plan {
  operation : String
  inputs : Array[String]
  mode : RunMode
  block_choice : BlockChoice
  sig_profile : @lib.SignatureProfile
  min_savings : Int64
  basis_path : String?
  streaming : Bool
  archive : Bool
  gzip : Bool
  progress : Bool
  detect_moves : Bool
  excludes : Array[String]
  exclude_sources : Array[ExcludeSource]
  verify_sig : String?
  verify_keys : Array[String]
  verify_bundle : String?
  keyring_file : String?
  save_rollback : String?
  key_file : String?
  passphrase_file : String?
  recipients : Array[String]
  recipient_key : String?
  trust_keys : Array[String]
  revoked_key_ids : Array[String]
  quorum : Int32
  pub_out : String?
  sig_file : String?
  sig_url : String?
  target_length : Int64?
  merge_gap_bytes : Int64
  max_ranges : Int64
  jobs : Int32
  meta_out : String?
  meta_file : String?
  compress_format : CompressFormat
  json : Bool
  seal_options : @crypto.SealOptions
  explicit_max_output : Bool
  options : @lib.SignatureOptions
  limits : @lib.Limits
  dir_limits : @lib.DirLimits
}

///|
let help_text : String =
  #|MoonLibSync 0.7.1; streaming pipelines, HTTP Range sync, delta composition, directory sync bundles/archives/metadata, deterministic parallelism, Ed25519 quorum signing, X25519 multi-recipient AEAD encryption, gzip/zlib/deflate framing, manifests and transfer workflows
  #|Usage:
  #|  moonlibsync signature OLD SIG [--profile rk-blake2|rollsum-blake2] [--streaming] [--block-size N|auto] [--sum-size N] [--progress] [LIMITS]
  #|  moonlibsync delta SIG NEW DELTA [--streaming] [--progress] [LIMITS]
  #|  moonlibsync patch OLD DELTA OUT [--streaming] [--progress] [LIMITS]
  #|  moonlibsync reverse-delta OLD NEW OUT_REV_DELTA [--block-size N|auto] [--sum-size N] [--streaming] [--progress] [LIMITS]
  #|  moonlibsync compose-delta DELTA1 DELTA2 [DELTA3...] -o OUT.delta [--json] [--progress] [LIMITS]
  #|  moonlibsync range-plan TARGET_SIG TARGET_LEN BASIS [-o PLAN.json] [--merge-gap BYTES] [--max-ranges N] [--json] [--progress] [LIMITS]
  #|  moonlibsync fetch-sync URL --basis OLD (--sig FILE | --sig-url URL) -o OUT [--target-length N] [--merge-gap BYTES] [--max-ranges N] [--verify-sig SIG_FILE --verify-key PUB_KEY... | --verify-bundle BUNDLE.json --keyring KEYRING.json] [--json] [--progress] [LIMITS]
  #|  moonlibsync basis-info OLD SIG INFO [--streaming] [--progress] [LIMITS]
  #|  moonlibsync make-manifest INFO SIG NEW DELTA MANIFEST [--streaming] [--progress] [LIMITS]
  #|  moonlibsync patch-verified OLD DELTA MANIFEST OUT [--streaming] [--progress] [--verify-sig SIG_FILE --verify-key PUB_KEY]... [LIMITS]
  #|  moonlibsync inspect-signature SIG [--json] [--progress] [LIMITS]
  #|  moonlibsync inspect-delta DELTA [--json] [--streaming] [--progress] [LIMITS]
  #|  moonlibsync check-patch OLD DELTA [--json] [--streaming] [--progress] [LIMITS]
  #|  moonlibsync inspect-manifest MANIFEST [--json] [--progress] [LIMITS]
  #|  moonlibsync inspect-bundle ARCHIVE [--gzip] [--json] [--progress] [LIMITS] [DIR_LIMITS]
  #|  moonlibsync make-transfer-manifest INFO SIG NEW DELTA MANIFEST [--min-savings N] [--streaming] [--progress] [LIMITS]
  #|  moonlibsync apply-update PAYLOAD MANIFEST OUT [--basis OLD] [--streaming] [--progress] [--verify-sig SIG_FILE --verify-key PUB_KEY]... [LIMITS]
  #|  moonlibsync compress IN OUT [--format gzip|zlib|deflate] [--streaming] [--progress] [LIMITS]
  #|  moonlibsync decompress IN OUT [--format gzip|zlib|deflate] [--streaming] [--progress] [LIMITS]
  #|  moonlibsync keygen OUT_PRIV OUT_PUB
  #|  moonlibsync x25519-keygen -o SECRET_OUT [--pub-out PUB_OUT] [--json]
  #|  moonlibsync sign IN PRIV_KEY OUT_SIG [--streaming] [--progress] [LIMITS]
  #|  moonlibsync verify IN SIG_FILE PUB_KEY [--pub-key EXTRA_PUB_KEY]... [--json] [--streaming] [--progress] [LIMITS]
  #|  moonlibsync keyring-init --trust PUB_HEX_OR_FILE [--trust ...] [--revoke KEY_ID...] --quorum M -o KEYRING.json [--json]
  #|  moonlibsync sign-combine SIG1.json [SIG2.json...] -o BUNDLE.json [--json]
  #|  moonlibsync verify-quorum PAYLOAD BUNDLE.json --keyring KEYRING.json [--json] [--streaming] [--progress] [LIMITS]
  #|  moonlibsync seal IN OUT (--key-file FILE | --passphrase-file FILE | --recipient PUB_HEX_OR_FILE...) [--chunk-size N] [--argon2-memory N] [--argon2-passes N] [--streaming] [--progress] [LIMITS]
  #|  moonlibsync unseal IN OUT (--key-file FILE | --passphrase-file FILE | --recipient-key SECRET_FILE) [--streaming] [--progress] [LIMITS]
  #|  moonlibsync dir-snapshot DIR OUT [--exclude PATTERN]... [--exclude-from FILE]... [--jobs N] [--meta-out META.json] [--progress] [DIR_LIMITS]
  #|  moonlibsync dir-plan BASIS_SNAP TARGET_SNAP [--detect-moves] [--json] [--progress] [DIR_LIMITS]
  #|  moonlibsync dir-verify DIR SNAPSHOT [--json] [--exclude PATTERN]... [--exclude-from FILE]... [--jobs N] [--progress] [DIR_LIMITS]
  #|  moonlibsync dir-signatures DIR SNAPSHOT SIG_DIR [--profile rk-blake2|rollsum-blake2] [--block-size N|auto] [--sum-size N] [--jobs N] [--streaming] [--progress] [LIMITS] [DIR_LIMITS]
  #|  moonlibsync dir-pack BASIS_SNAP SIG_DIR TARGET_DIR BUNDLE [--detect-moves] [--archive] [--gzip] [--exclude PATTERN]... [--exclude-from FILE]... [--jobs N] [--streaming] [--min-savings N] [--progress] [LIMITS] [DIR_LIMITS]
  #|  moonlibsync dir-apply BASIS_DIR BUNDLE OUT_DIR [--archive] [--gzip] [--meta META.json] [--streaming] [--progress] [--verify-sig SIG_FILE --verify-key PUB_KEY... | --verify-bundle BUNDLE.json --keyring KEYRING.json] [--save-rollback ROLLBACK_ARCHIVE] [LIMITS] [DIR_LIMITS]
  #|  moonlibsync completions bash|zsh|powershell
  #|  moonlibsync --help
  #|  moonlibsync --version
  #|Options may appear anywhere after the command before --; -- ends option parsing.
  #|--profile selects signature wire profile: rk-blake2 (0x72730147, default) or rollsum-blake2 (0x72730137).
  #|--format selects compression framing on compress/decompress: gzip (default, RFC 1952), zlib (RFC 1950), or deflate (RFC 1951).
  #|--jobs N (1..64, default 1) runs bounded deterministic concurrency on dir-snapshot, dir-signatures, dir-pack, and dir-verify.
  #|--meta-out META.json / --meta META.json records and restores sorted empty directories and POSIX executable permissions.
  #|--streaming uses bounded 64 KiB chunks (all streaming file/bundle/crypto commands; not supported for MLSENC02 --recipient/--recipient-key).
  #|--archive packs/applies a single-file MLSBDL01 .mbundle container (dir-pack and dir-apply only).
  #|--gzip wraps/unwraps a --archive bundle with bounded single-member RFC 1952 gzip (requires --archive on dir-pack/dir-apply; standalone on inspect-bundle).
  #|--detect-moves reuses identical moved/renamed basis files (0-byte copy-from-basis) and deltas moved+edited files (dir-plan and dir-pack).
  #|--exclude PATTERN skips matching POSIX paths/subtrees (repeatable up to 64; dir-snapshot, dir-pack, dir-verify).
  #|--exclude-from FILE reads ignore patterns from FILE (UTF-8 without BOM; repeatable; dir-snapshot, dir-pack, dir-verify).
  #|--verify-sig SIG_FILE --verify-key PUB_KEY verifies an Ed25519 publisher signature before applying (repeatable --verify-key; patch-verified, apply-update, dir-apply --archive, fetch-sync).
  #|--verify-bundle BUNDLE.json --keyring KEYRING.json verifies an M-of-N Ed25519 quorum bundle before applying (dir-apply --archive, fetch-sync).
  #|--save-rollback ROLLBACK_ARCHIVE atomically saves a .mbundle.gz rollback archive (OUT_DIR -> BASIS_DIR) on dir-apply.
  #|--progress emits throttled progress lines to stderr without polluting stdout (disabled by default).
  #|Optional [LIMITS] overrides (default Limits::default()):
  #|  --max-old-bytes N  --max-new-bytes N  --max-signature-bytes N
  #|  --max-signature-records N  --max-block-bytes N  --max-delta-bytes N
  #|  --max-output-bytes N  --max-instructions N  --max-match-work N
  #|Optional [DIR_LIMITS] overrides for dir-* and inspect-bundle commands (default DirLimits::default()):
  #|  --max-entries N  --max-path-bytes N  --max-depth N
  #|  --max-snapshot-bytes N  --max-file-bytes N
  #|--json outputs machine-readable JSON on inspection, range-plan, fetch-sync, compose-delta, x25519-keygen, keyring-init, sign-combine, and verify-quorum commands.
  #|inspect-manifest validates schema1/schema2 JSON structure without reading payload files.
  #|inspect-bundle streams and validates an MLSBDL01 archive (.mbundle / .mbundle.gz) read-only.
  #|compress/decompress use bounded single-member gzip/zlib/deflate (zip-bomb and trailing-data safe).
  #|seal/unseal support chunked MLSENC01 symmetric/Argon2id AEAD and MLSENC02 multi-recipient X25519 envelopes.
  #|dir-* commands reject all symlinks and unsafe/colliding paths; dir-apply never modifies BASIS_DIR.
  #|After -- every argument is a path. A lone - is a literal filename, never a pipe.
  #|Defaults: block-size 2048, sum-size 32, profile rk-blake2, format gzip, jobs 1, merge-gap 4096, max-ranges 256.
  #|Only stable regular input files are supported; leaf symlinks are rejected.
  #|Existing output entries (including links and directories) are refused; no overwrite option.
  #|Exit codes: 0 success/help/version; 2 usage; 1 file, network, verification mismatch, or core/crypto error.

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
  operation == "reverse-delta" ||
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
  operation == "dir-apply" ||
  operation == "sign" ||
  operation == "verify" ||
  operation == "verify-quorum" ||
  operation == "seal" ||
  operation == "unseal"
}

///|
fn parse_sig_profile(text : String) -> @lib.SignatureProfile raise CliError {
  match text {
    "rk-blake2" => @lib.SignatureProfile::RkBlake2
    "rollsum-blake2" => @lib.SignatureProfile::RollsumBlake2
    _ =>
      raise Usage(
        "unknown signature profile: " +
        text +
        " (expected rk-blake2 or rollsum-blake2)",
      )
  }
}

///|
fn parse_compress_format(text : String) -> CompressFormat raise CliError {
  match text {
    "gzip" => CompressFormat::Gzip
    "zlib" => CompressFormat::Zlib
    "deflate" => CompressFormat::Deflate
    _ =>
      raise Usage(
        "unknown compression format: " +
        text +
        " (expected gzip, zlib, or deflate)",
      )
  }
}

///|
fn validate_http_url(url : String, label : String) -> Unit raise CliError {
  let scheme_len = if url.has_prefix("https://") {
    8
  } else if url.has_prefix("http://") {
    7
  } else {
    raise Usage("invalid " + label + " (expected http:// or https://): " + url)
  }
  for c in url {
    let code = c.to_int()
    guard code >= 0x21 && code <= 0x7e else {
      raise Usage("invalid characters in " + label + ": " + url)
    }
  }
  let chars = url.to_array()
  let mut host_end = scheme_len
  while host_end < chars.length() &&
        chars[host_end] != '/' &&
        chars[host_end] != '?' &&
        chars[host_end] != '#' {
    host_end = host_end + 1
  }
  guard host_end > scheme_len else {
    raise Usage("invalid " + label + " (missing host): " + url)
  }
}

///|
fn parse_plan(args : ArrayView[String]) -> Plan raise CliError {
  guard args.length() > 0 else { raise Usage("missing command") }
  let operation = args[0]
  let dir_only_op = operation == "dir-snapshot" ||
    operation == "dir-plan" ||
    operation == "dir-verify"
  let dir_bundle_op = operation == "dir-signatures" ||
    operation == "dir-pack" ||
    operation == "dir-apply"
  let uses_output_flag = operation == "range-plan" ||
    operation == "fetch-sync" ||
    operation == "compose-delta" ||
    operation == "x25519-keygen" ||
    operation == "keyring-init" ||
    operation == "sign-combine"
  let accepts_dir_limits = dir_only_op ||
    dir_bundle_op ||
    operation == "inspect-bundle"
  let accepts_file_limits = !dir_only_op &&
    operation != "keygen" &&
    operation != "x25519-keygen" &&
    operation != "keyring-init" &&
    operation != "sign-combine" &&
    operation != "completions"
  let accepts_progress = operation != "keygen" &&
    operation != "x25519-keygen" &&
    operation != "keyring-init" &&
    operation != "sign-combine" &&
    operation != "completions"
  let inspection = operation == "inspect-signature" ||
    operation == "inspect-delta" ||
    operation == "check-patch" ||
    operation == "inspect-manifest" ||
    operation == "inspect-bundle" ||
    operation == "dir-plan" ||
    operation == "dir-verify" ||
    operation == "verify" ||
    operation == "verify-quorum"
  let accepts_json = inspection || uses_output_flag
  let is_completions = operation == "completions"
  guard inspection ||
    is_completions ||
    accepts_dir_limits ||
    uses_output_flag ||
    operation == "signature" ||
    operation == "delta" ||
    operation == "patch" ||
    operation == "reverse-delta" ||
    operation == "basis-info" ||
    operation == "make-manifest" ||
    operation == "patch-verified" ||
    operation == "make-transfer-manifest" ||
    operation == "apply-update" ||
    operation == "compress" ||
    operation == "decompress" ||
    operation == "keygen" ||
    operation == "sign" ||
    operation == "seal" ||
    operation == "unseal" else {
    raise Usage("unknown command: " + operation)
  }
  let mut limits = @lib.Limits::default()
  let mut dir_limits = @lib.DirLimits::default()
  let mut seal_options = @crypto.SealOptions::default()
  let seen_limits : Map[String, Bool] = Map([])
  let (min_paths, max_paths) = if operation == "x25519-keygen" ||
    operation == "keyring-init" {
    (0, 0)
  } else if operation == "fetch-sync" {
    (1, 1)
  } else if operation == "range-plan" {
    (3, 3)
  } else if operation == "compose-delta" {
    (2, 256)
  } else if operation == "sign-combine" {
    (1, 64)
  } else if operation == "verify-quorum" {
    (2, 2)
  } else if operation == "verify" {
    (3, 3)
  } else if operation == "dir-plan" ||
    operation == "dir-verify" ||
    operation == "check-patch" {
    (2, 2)
  } else if inspection || is_completions {
    (1, 1)
  } else if operation == "make-manifest" ||
    operation == "make-transfer-manifest" {
    (5, 5)
  } else if operation == "patch-verified" || operation == "dir-pack" {
    (4, 4)
  } else if operation == "signature" ||
    operation == "dir-snapshot" ||
    operation == "compress" ||
    operation == "decompress" ||
    operation == "keygen" ||
    operation == "seal" ||
    operation == "unseal" {
    (2, 2)
  } else {
    (3, 3)
  }
  let paths : Array[String] = []
  let excludes : Array[String] = []
  let exclude_sources : Array[ExcludeSource] = []
  let mut exclude_file_count = 0
  let verify_keys : Array[String] = []
  let mut verify_sig : String? = None
  let mut verify_bundle : String? = None
  let mut keyring_file : String? = None
  let mut save_rollback : String? = None
  let mut key_file : String? = None
  let mut passphrase_file : String? = None
  let recipients : Array[String] = []
  let mut recipient_key : String? = None
  let trust_keys : Array[String] = []
  let revoked_key_ids : Array[String] = []
  let mut quorum = 0
  let mut saw_quorum = false
  let mut output_flag : String? = None
  let mut pub_out : String? = None
  let mut sig_file : String? = None
  let mut sig_url : String? = None
  let mut target_length : Int64? = None
  let mut merge_gap_bytes = @lib.RangeFetchOptions::default().merge_gap_bytes
  let mut saw_merge_gap = false
  let mut max_ranges = @lib.RangeFetchOptions::default().max_ranges
  let mut saw_max_ranges = false
  let mut jobs = 1
  let mut saw_jobs = false
  let mut meta_out : String? = None
  let mut meta_file : String? = None
  let mut compress_format = CompressFormat::Gzip
  let mut saw_format = false
  let mut saw_chunk_size = false
  let mut saw_argon2_memory = false
  let mut saw_argon2_passes = false
  let mut block_choice : BlockChoice = Explicit(2048L)
  let mut sig_profile : @lib.SignatureProfile = RkBlake2
  let mut saw_profile = false
  let mut min_savings = 0L
  let mut saw_savings = false
  let mut basis_path : String? = None
  let mut streaming = false
  let mut archive = false
  let mut gzip = false
  let mut progress = false
  let mut detect_moves = false
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
    } else if options && arg == "-o" {
      guard uses_output_flag else {
        raise Usage("option -o is not supported for command: " + operation)
      }
      guard output_flag is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing -o output path")
      }
      output_flag = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--pub-out" {
      guard operation == "x25519-keygen" else {
        raise Usage("x25519-keygen-only option: --pub-out")
      }
      guard pub_out is None && i + 1 < args.length() && args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --pub-out")
      }
      pub_out = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--sig" {
      guard operation == "fetch-sync" else {
        raise Usage("fetch-sync-only option: --sig")
      }
      guard sig_file is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --sig")
      }
      sig_file = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--sig-url" {
      guard operation == "fetch-sync" else {
        raise Usage("fetch-sync-only option: --sig-url")
      }
      guard sig_url is None && i + 1 < args.length() && args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --sig-url")
      }
      validate_http_url(args[i + 1], "--sig-url")
      sig_url = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--target-length" {
      guard operation == "fetch-sync" else {
        raise Usage("fetch-sync-only option: --target-length")
      }
      guard target_length is None && i + 1 < args.length() else {
        raise Usage("duplicate or missing --target-length")
      }
      target_length = Some(bounded_decimal(args[i + 1], 0L, 2147483647L))
      i = i + 1
    } else if options && arg == "--merge-gap" {
      guard operation == "range-plan" || operation == "fetch-sync" else {
        raise Usage("range-plan/fetch-sync-only option: --merge-gap")
      }
      guard !saw_merge_gap && i + 1 < args.length() else {
        raise Usage("duplicate or missing --merge-gap")
      }
      merge_gap_bytes = bounded_decimal(args[i + 1], 0L, 2147483647L)
      saw_merge_gap = true
      i = i + 1
    } else if options && arg == "--max-ranges" {
      guard operation == "range-plan" || operation == "fetch-sync" else {
        raise Usage("range-plan/fetch-sync-only option: --max-ranges")
      }
      guard !saw_max_ranges && i + 1 < args.length() else {
        raise Usage("duplicate or missing --max-ranges")
      }
      max_ranges = positive_decimal(args[i + 1], 65536L)
      saw_max_ranges = true
      i = i + 1
    } else if options && arg == "--recipient" {
      guard operation == "seal" else {
        raise Usage("seal-only option: --recipient")
      }
      guard i + 1 < args.length() && args[i + 1].length() > 0 else {
        raise Usage("missing or empty --recipient")
      }
      guard recipients.length() < 64 else {
        raise Usage("too many --recipient values (max 64)")
      }
      recipients.push(args[i + 1])
      i = i + 1
    } else if options && arg == "--recipient-key" {
      guard operation == "unseal" else {
        raise Usage("unseal-only option: --recipient-key")
      }
      guard recipient_key is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --recipient-key")
      }
      recipient_key = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--trust" {
      guard operation == "keyring-init" else {
        raise Usage("keyring-init-only option: --trust")
      }
      guard i + 1 < args.length() && args[i + 1].length() > 0 else {
        raise Usage("missing or empty --trust")
      }
      guard trust_keys.length() < 64 else {
        raise Usage("too many --trust keys (max 64)")
      }
      trust_keys.push(args[i + 1])
      i = i + 1
    } else if options && arg == "--revoke" {
      guard operation == "keyring-init" else {
        raise Usage("keyring-init-only option: --revoke")
      }
      guard i + 1 < args.length() && args[i + 1].length() > 0 else {
        raise Usage("missing or empty --revoke")
      }
      guard revoked_key_ids.length() < 64 else {
        raise Usage("too many --revoke key IDs (max 64)")
      }
      revoked_key_ids.push(args[i + 1])
      i = i + 1
    } else if options && arg == "--quorum" {
      guard operation == "keyring-init" else {
        raise Usage("keyring-init-only option: --quorum")
      }
      guard !saw_quorum && i + 1 < args.length() else {
        raise Usage("duplicate or missing --quorum")
      }
      quorum = positive_decimal(args[i + 1], 64L).to_int()
      saw_quorum = true
      i = i + 1
    } else if options && arg == "--verify-bundle" {
      guard operation == "dir-apply" || operation == "fetch-sync" else {
        raise Usage("dir-apply/fetch-sync-only option: --verify-bundle")
      }
      guard verify_bundle is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --verify-bundle")
      }
      verify_bundle = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--keyring" {
      guard operation == "verify-quorum" ||
        operation == "dir-apply" ||
        operation == "fetch-sync" else {
        raise Usage("verify-quorum/dir-apply/fetch-sync-only option: --keyring")
      }
      guard keyring_file is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --keyring")
      }
      keyring_file = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--jobs" {
      guard operation == "dir-snapshot" ||
        operation == "dir-signatures" ||
        operation == "dir-pack" ||
        operation == "dir-verify" else {
        raise Usage(
          "dir-snapshot/dir-signatures/dir-pack/dir-verify-only option: --jobs",
        )
      }
      guard !saw_jobs && i + 1 < args.length() else {
        raise Usage("duplicate or missing --jobs")
      }
      jobs = positive_decimal(args[i + 1], 64L).to_int()
      saw_jobs = true
      i = i + 1
    } else if options && arg == "--meta-out" {
      guard operation == "dir-snapshot" else {
        raise Usage("dir-snapshot-only option: --meta-out")
      }
      guard meta_out is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --meta-out")
      }
      meta_out = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--meta" {
      guard operation == "dir-apply" else {
        raise Usage("dir-apply-only option: --meta")
      }
      guard meta_file is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --meta")
      }
      meta_file = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--format" {
      guard operation == "compress" || operation == "decompress" else {
        raise Usage("compress/decompress-only option: --format")
      }
      guard !saw_format && i + 1 < args.length() else {
        raise Usage("duplicate or missing --format")
      }
      compress_format = parse_compress_format(args[i + 1])
      saw_format = true
      i = i + 1
    } else if options && arg == "--streaming" {
      guard supports_streaming(operation) else {
        raise Usage("streaming is not supported for command: " + operation)
      }
      guard !streaming else { raise Usage("duplicate option: --streaming") }
      streaming = true
    } else if options && arg == "--archive" {
      guard operation == "dir-pack" || operation == "dir-apply" else {
        raise Usage("dir-pack/dir-apply-only option: --archive")
      }
      guard !archive else { raise Usage("duplicate option: --archive") }
      archive = true
    } else if options && arg == "--gzip" {
      guard operation == "dir-pack" ||
        operation == "dir-apply" ||
        operation == "inspect-bundle" else {
        raise Usage("dir-pack/dir-apply/inspect-bundle-only option: --gzip")
      }
      guard !gzip else { raise Usage("duplicate option: --gzip") }
      gzip = true
    } else if options && arg == "--detect-moves" {
      guard operation == "dir-plan" || operation == "dir-pack" else {
        raise Usage("dir-plan/dir-pack-only option: --detect-moves")
      }
      guard !detect_moves else {
        raise Usage("duplicate option: --detect-moves")
      }
      detect_moves = true
    } else if options && arg == "--exclude" {
      guard operation == "dir-snapshot" ||
        operation == "dir-pack" ||
        operation == "dir-verify" else {
        raise Usage("dir-snapshot/dir-pack/dir-verify-only option: --exclude")
      }
      guard i + 1 < args.length() && args[i + 1].length() > 0 else {
        raise Usage("missing or empty --exclude pattern")
      }
      guard excludes.length() < 64 else {
        raise Usage("too many --exclude patterns (max 64)")
      }
      excludes.push(args[i + 1])
      exclude_sources.push(Pattern(args[i + 1]))
      i = i + 1
    } else if options && arg == "--exclude-from" {
      guard operation == "dir-snapshot" ||
        operation == "dir-pack" ||
        operation == "dir-verify" else {
        raise Usage(
          "dir-snapshot/dir-pack/dir-verify-only option: --exclude-from",
        )
      }
      guard i + 1 < args.length() && args[i + 1].length() > 0 else {
        raise Usage("missing or empty --exclude-from path")
      }
      guard exclude_file_count < 64 else {
        raise Usage("too many --exclude-from files (max 64)")
      }
      exclude_file_count = exclude_file_count + 1
      exclude_sources.push(File(args[i + 1]))
      i = i + 1
    } else if options && arg == "--verify-sig" {
      guard operation == "dir-apply" ||
        operation == "patch-verified" ||
        operation == "apply-update" ||
        operation == "fetch-sync" else {
        raise Usage(
          "dir-apply/patch-verified/apply-update/fetch-sync-only option: --verify-sig",
        )
      }
      guard verify_sig is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --verify-sig")
      }
      verify_sig = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--verify-key" {
      guard operation == "dir-apply" ||
        operation == "patch-verified" ||
        operation == "apply-update" ||
        operation == "fetch-sync" else {
        raise Usage(
          "dir-apply/patch-verified/apply-update/fetch-sync-only option: --verify-key",
        )
      }
      guard i + 1 < args.length() && args[i + 1].length() > 0 else {
        raise Usage("missing or empty --verify-key")
      }
      guard verify_keys.length() < 64 else {
        raise Usage("too many --verify-key entries (max 64)")
      }
      verify_keys.push(args[i + 1])
      i = i + 1
    } else if options && arg == "--pub-key" {
      guard operation == "verify" else {
        raise Usage("verify-only option: --pub-key")
      }
      guard i + 1 < args.length() && args[i + 1].length() > 0 else {
        raise Usage("missing or empty --pub-key")
      }
      guard verify_keys.length() < 64 else {
        raise Usage("too many --pub-key files (max 64)")
      }
      verify_keys.push(args[i + 1])
      i = i + 1
    } else if options && arg == "--save-rollback" {
      guard operation == "dir-apply" else {
        raise Usage("dir-apply-only option: --save-rollback")
      }
      guard save_rollback is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --save-rollback")
      }
      save_rollback = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--key-file" {
      guard operation == "seal" || operation == "unseal" else {
        raise Usage("seal/unseal-only option: --key-file")
      }
      guard key_file is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --key-file")
      }
      key_file = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--passphrase-file" {
      guard operation == "seal" || operation == "unseal" else {
        raise Usage("seal/unseal-only option: --passphrase-file")
      }
      guard passphrase_file is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --passphrase-file")
      }
      passphrase_file = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--chunk-size" {
      guard operation == "seal" else {
        raise Usage("seal-only option: --chunk-size")
      }
      guard !saw_chunk_size && i + 1 < args.length() else {
        raise Usage("duplicate or missing --chunk-size")
      }
      let v = bounded_decimal(args[i + 1], 1024L, 1048576L).to_int()
      seal_options = { ..seal_options, chunk_size: v, }
      saw_chunk_size = true
      i = i + 1
    } else if options && arg == "--argon2-memory" {
      guard operation == "seal" else {
        raise Usage("seal-only option: --argon2-memory")
      }
      guard !saw_argon2_memory && i + 1 < args.length() else {
        raise Usage("duplicate or missing --argon2-memory")
      }
      let v = bounded_decimal(args[i + 1], 64L, 65536L).to_int()
      seal_options = { ..seal_options, argon2_memory_kib: v, }
      saw_argon2_memory = true
      i = i + 1
    } else if options && arg == "--argon2-passes" {
      guard operation == "seal" else {
        raise Usage("seal-only option: --argon2-passes")
      }
      guard !saw_argon2_passes && i + 1 < args.length() else {
        raise Usage("duplicate or missing --argon2-passes")
      }
      let v = bounded_decimal(args[i + 1], 1L, 8L).to_int()
      seal_options = { ..seal_options, argon2_passes: v, }
      saw_argon2_passes = true
      i = i + 1
    } else if options && arg == "--profile" {
      guard operation == "signature" || operation == "dir-signatures" else {
        raise Usage("signature-only option: --profile")
      }
      guard !saw_profile && i + 1 < args.length() else {
        raise Usage("duplicate or missing --profile")
      }
      sig_profile = parse_sig_profile(args[i + 1])
      saw_profile = true
      i = i + 1
    } else if options && arg == "--progress" {
      guard accepts_progress else {
        raise Usage("progress is not supported for command: " + operation)
      }
      guard !progress else { raise Usage("duplicate option: --progress") }
      progress = true
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
      guard operation == "apply-update" || operation == "fetch-sync" else {
        raise Usage("apply-update/fetch-sync-only option: " + arg)
      }
      guard basis_path is None &&
        i + 1 < args.length() &&
        args[i + 1].length() > 0 else {
        raise Usage("duplicate or missing --basis")
      }
      basis_path = Some(args[i + 1])
      i = i + 1
    } else if options && arg == "--json" {
      guard accepts_json else {
        raise Usage("option --json is not supported for command: " + operation)
      }
      guard !json else { raise Usage("duplicate option: --json") }
      json = true
    } else if options && (arg == "--block-size" || arg == "--sum-size") {
      guard operation == "signature" ||
        operation == "dir-signatures" ||
        operation == "reverse-delta" else {
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
      guard paths.length() < max_paths else {
        raise Usage("too many paths for " + operation)
      }
      paths.push(arg)
    }
    i = i + 1
  }
  if gzip && !archive && operation != "inspect-bundle" {
    raise Usage("--gzip requires --archive")
  }
  if operation == "dir-apply" ||
    operation == "patch-verified" ||
    operation == "apply-update" ||
    operation == "fetch-sync" {
    let has_sig = verify_sig is Some(_)
    let has_keys = verify_keys.length() > 0
    if has_sig != has_keys {
      raise Usage("--verify-sig and --verify-key must be provided together")
    }
    let has_bundle = verify_bundle is Some(_)
    let has_kr = keyring_file is Some(_)
    if has_bundle != has_kr {
      raise Usage("--verify-bundle and --keyring must be provided together")
    }
    if has_sig && has_bundle {
      raise Usage(
        "--verify-sig/--verify-key and --verify-bundle/--keyring are mutually exclusive",
      )
    }
    if operation == "dir-apply" && (has_sig || has_bundle) && !archive {
      raise Usage(
        "--verify-sig/--verify-bundle on dir-apply requires --archive",
      )
    }
  }
  if operation == "seal" {
    let mode_count = (if key_file is Some(_) { 1 } else { 0 }) +
      (if passphrase_file is Some(_) { 1 } else { 0 }) +
      (if recipients.length() > 0 { 1 } else { 0 })
    guard mode_count == 1 else {
      if mode_count == 0 {
        raise Usage(
          "seal requires --key-file, --passphrase-file, or --recipient",
        )
      } else {
        raise Usage(
          "--key-file, --passphrase-file, and --recipient are mutually exclusive",
        )
      }
    }
    if passphrase_file is None && (saw_argon2_memory || saw_argon2_passes) {
      raise Usage(
        "--argon2-memory and --argon2-passes require --passphrase-file",
      )
    }
    if recipients.length() > 0 && streaming {
      raise Usage("--streaming is not supported with --recipient")
    }
  } else if operation == "unseal" {
    let mode_count = (if key_file is Some(_) { 1 } else { 0 }) +
      (if passphrase_file is Some(_) { 1 } else { 0 }) +
      (if recipient_key is Some(_) { 1 } else { 0 })
    guard mode_count == 1 else {
      if mode_count == 0 {
        raise Usage(
          "unseal requires --key-file, --passphrase-file, or --recipient-key",
        )
      } else {
        raise Usage(
          "--key-file, --passphrase-file, and --recipient-key are mutually exclusive",
        )
      }
    }
    if recipient_key is Some(_) && streaming {
      raise Usage("--streaming is not supported with --recipient-key")
    }
  }
  if operation == "fetch-sync" {
    guard basis_path is Some(_) else {
      raise Usage("fetch-sync requires --basis OLD")
    }
    let has_sig_file = sig_file is Some(_)
    let has_sig_url = sig_url is Some(_)
    guard has_sig_file != has_sig_url else {
      raise Usage("fetch-sync requires exactly one of --sig or --sig-url")
    }
    guard output_flag is Some(_) else {
      raise Usage("fetch-sync requires -o OUT")
    }
  } else if operation == "compose-delta" ||
    operation == "x25519-keygen" ||
    operation == "keyring-init" ||
    operation == "sign-combine" {
    guard output_flag is Some(_) else {
      raise Usage(operation + " requires -o OUT")
    }
  }
  if operation == "keyring-init" {
    guard trust_keys.length() >= 1 else {
      raise Usage("keyring-init requires at least one --trust key")
    }
    guard saw_quorum else { raise Usage("keyring-init requires --quorum M") }
  }
  if operation == "verify-quorum" {
    guard keyring_file is Some(_) else {
      raise Usage("verify-quorum requires --keyring KEYRING.json")
    }
  }
  match block_choice {
    Explicit(value) =>
      if saw_block && value > limits.max_block_bytes {
        raise Usage("block-size exceeds max-block-bytes")
      }
    Auto => ()
  }
  guard paths.length() >= min_paths && paths.length() <= max_paths else {
    raise Usage("wrong number of paths for " + operation)
  }
  if operation == "range-plan" {
    target_length = Some(bounded_decimal(paths[1], 0L, 2147483647L))
  } else if operation == "fetch-sync" {
    validate_http_url(paths[0], "URL")
  }
  if is_completions {
    let shell = paths[0]
    guard shell == "bash" || shell == "zsh" || shell == "powershell" else {
      raise Usage(
        "unsupported shell: " + shell + " (expected bash, zsh, or powershell)",
      )
    }
  }
  let mode : RunMode = if operation == "range-plan" {
    match output_flag {
      Some(out) => WriteFile(out)
      None => Inspect(true)
    }
  } else if uses_output_flag {
    match output_flag {
      Some(out) => WriteFile(out)
      None => raise Usage(operation + " requires -o OUT")
    }
  } else if inspection {
    Inspect(json)
  } else if is_completions {
    Inspect(false)
  } else if dir_bundle_op && !(operation == "dir-pack" && archive) {
    WriteDir(paths[paths.length() - 1])
  } else {
    WriteFile(paths[paths.length() - 1])
  }
  let inputs : Array[String] = if inspection ||
    is_completions ||
    uses_output_flag {
    paths
  } else {
    paths[0:paths.length() - 1].to_owned()
  }
  {
    operation,
    inputs,
    mode,
    block_choice,
    sig_profile,
    min_savings,
    basis_path,
    streaming,
    archive,
    gzip,
    progress,
    detect_moves,
    excludes,
    exclude_sources,
    verify_sig,
    verify_keys,
    verify_bundle,
    keyring_file,
    save_rollback,
    key_file,
    passphrase_file,
    recipients,
    recipient_key,
    trust_keys,
    revoked_key_ids,
    quorum,
    pub_out,
    sig_file,
    sig_url,
    target_length,
    merge_gap_bytes,
    max_ranges,
    jobs,
    meta_out,
    meta_file,
    compress_format,
    json,
    seal_options,
    explicit_max_output: seen_limits.contains("--max-output-bytes"),
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
