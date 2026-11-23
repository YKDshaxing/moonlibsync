// SPDX-License-Identifier: LGPL-2.1-or-later

///|
let bash_completions : String =
  #|# Bash completion for moonlibsync 0.7.1
  #|_moonlibsync_completions() {
  #|  local cur prev cmd
  #|  COMPREPLY=()
  #|  cur="${COMP_WORDS[COMP_CWORD]}"
  #|  prev="${COMP_WORDS[COMP_CWORD-1]}"
  #|  local commands="signature delta patch reverse-delta compose-delta range-plan fetch-sync basis-info make-manifest patch-verified inspect-signature inspect-delta check-patch inspect-manifest inspect-bundle make-transfer-manifest apply-update compress decompress keygen x25519-keygen sign verify keyring-init sign-combine verify-quorum seal unseal dir-snapshot dir-plan dir-verify dir-signatures dir-pack dir-apply completions"
  #|  local limit_flags="--max-old-bytes --max-new-bytes --max-signature-bytes --max-signature-records --max-block-bytes --max-delta-bytes --max-output-bytes --max-instructions --max-match-work"
  #|  local dir_limit_flags="--max-entries --max-path-bytes --max-depth --max-snapshot-bytes --max-file-bytes"
  #|  if [[ ${COMP_CWORD} -eq 1 ]]; then
  #|    COMPREPLY=( $(compgen -W "${commands} --help --version" -- "${cur}") )
  #|    return 0
  #|  fi
  #|  cmd="${COMP_WORDS[1]}"
  #|  case "${prev}" in
  #|    --profile)
  #|      COMPREPLY=( $(compgen -W "rk-blake2 rollsum-blake2" -- "${cur}") )
  #|      return 0 ;;
  #|    --format)
  #|      COMPREPLY=( $(compgen -W "gzip zlib deflate" -- "${cur}") )
  #|      return 0 ;;
  #|    --block-size)
  #|      COMPREPLY=( $(compgen -W "auto 512 1024 2048 4096 8192 16384" -- "${cur}") )
  #|      return 0 ;;
  #|    --sum-size)
  #|      COMPREPLY=( $(compgen -W "8 16 32" -- "${cur}") )
  #|      return 0 ;;
  #|    --jobs)
  #|      COMPREPLY=( $(compgen -W "1 2 4 8 16" -- "${cur}") )
  #|      return 0 ;;
  #|    -o|--pub-out|--sig|--basis|--exclude-from|--verify-sig|--verify-key|--verify-bundle|--keyring|--pub-key|--save-rollback|--key-file|--passphrase-file|--recipient|--recipient-key|--trust|--meta-out|--meta)
  #|      COMPREPLY=( $(compgen -f -- "${cur}") )
  #|      return 0 ;;
  #|  esac
  #|  if [[ "${cmd}" == "completions" ]]; then
  #|    COMPREPLY=( $(compgen -W "bash zsh powershell" -- "${cur}") )
  #|    return 0
  #|  fi
  #|  if [[ "${cur}" == -* ]]; then
  #|    local flags=""
  #|    case "${cmd}" in
  #|      signature) flags="--profile --streaming --block-size --sum-size --progress ${limit_flags}" ;;
  #|      delta|patch|basis-info|make-manifest|sign) flags="--streaming --progress ${limit_flags}" ;;
  #|      compress|decompress) flags="--format --streaming --progress ${limit_flags}" ;;
  #|      reverse-delta) flags="--block-size --sum-size --streaming --progress ${limit_flags}" ;;
  #|      compose-delta) flags="-o --json --progress ${limit_flags}" ;;
  #|      range-plan) flags="-o --merge-gap --max-ranges --json --progress ${limit_flags}" ;;
  #|      fetch-sync) flags="--basis --sig --sig-url -o --target-length --merge-gap --max-ranges --verify-sig --verify-key --verify-bundle --keyring --json --progress ${limit_flags}" ;;
  #|      patch-verified) flags="--streaming --progress --verify-sig --verify-key ${limit_flags}" ;;
  #|      make-transfer-manifest) flags="--min-savings --streaming --progress ${limit_flags}" ;;
  #|      apply-update) flags="--basis --streaming --progress --verify-sig --verify-key ${limit_flags}" ;;
  #|      inspect-signature|inspect-manifest) flags="--json --progress ${limit_flags}" ;;
  #|      inspect-delta|check-patch) flags="--json --streaming --progress ${limit_flags}" ;;
  #|      inspect-bundle) flags="--gzip --json --progress ${limit_flags} ${dir_limit_flags}" ;;
  #|      verify) flags="--pub-key --json --streaming --progress ${limit_flags}" ;;
  #|      verify-quorum) flags="--keyring --json --streaming --progress ${limit_flags}" ;;
  #|      x25519-keygen) flags="-o --pub-out --json" ;;
  #|      keyring-init) flags="--trust --revoke --quorum -o --json" ;;
  #|      sign-combine) flags="-o --json" ;;
  #|      seal) flags="--key-file --passphrase-file --recipient --chunk-size --argon2-memory --argon2-passes --streaming --progress ${limit_flags}" ;;
  #|      unseal) flags="--key-file --passphrase-file --recipient-key --streaming --progress ${limit_flags}" ;;
  #|      dir-snapshot) flags="--exclude --exclude-from --jobs --meta-out --progress ${dir_limit_flags}" ;;
  #|      dir-plan) flags="--detect-moves --json --progress ${dir_limit_flags}" ;;
  #|      dir-verify) flags="--json --exclude --exclude-from --jobs --progress ${dir_limit_flags}" ;;
  #|      dir-signatures) flags="--profile --block-size --sum-size --jobs --streaming --progress ${limit_flags} ${dir_limit_flags}" ;;
  #|      dir-pack) flags="--detect-moves --archive --gzip --exclude --exclude-from --jobs --streaming --min-savings --progress ${limit_flags} ${dir_limit_flags}" ;;
  #|      dir-apply) flags="--archive --gzip --meta --streaming --progress --verify-sig --verify-key --verify-bundle --keyring --save-rollback ${limit_flags} ${dir_limit_flags}" ;;
  #|      keygen|completions) flags="" ;;
  #|    esac
  #|    COMPREPLY=( $(compgen -W "${flags}" -- "${cur}") )
  #|    return 0
  #|  fi
  #|  COMPREPLY=( $(compgen -f -- "${cur}") )
  #|}
  #|complete -F _moonlibsync_completions moonlibsync
  #|

///|
let zsh_completions : String =
  #|#compdef moonlibsync
  #|# Zsh completion for moonlibsync 0.7.1
  #|_moonlibsync() {
  #|  local -a commands
  #|  commands=(
  #|    'signature:Generate librsync signature for OLD'
  #|    'delta:Generate librsync delta from SIG and NEW'
  #|    'patch:Apply librsync DELTA to OLD'
  #|    'reverse-delta:Generate rollback delta reverting NEW to OLD'
  #|    'compose-delta:Compose sequential librsync deltas into one direct delta'
  #|    'range-plan:Plan client-pull HTTP Range sync from target signature'
  #|    'fetch-sync:Download and reconstruct file via HTTP Range requests'
  #|    'basis-info:Generate SHA-256 basis-info manifest'
  #|    'make-manifest:Generate verified update manifest'
  #|    'patch-verified:Verify and apply update manifest'
  #|    'inspect-signature:Inspect signature header and summary'
  #|    'inspect-delta:Inspect delta structure and summary'
  #|    'check-patch:Preflight delta COPY ranges against OLD'
  #|    'inspect-manifest:Validate and inspect schema1/schema2 manifest'
  #|    'inspect-bundle:Stream-inspect MLSBDL01 archive read-only'
  #|    'make-transfer-manifest:Plan delta-or-full transfer manifest'
  #|    'apply-update:Verify and apply transfer manifest'
  #|    'compress:Compress file with bounded gzip, zlib, or deflate'
  #|    'decompress:Decompress file with bounded gzip, zlib, or deflate'
  #|    'keygen:Generate Ed25519 signing keypair'
  #|    'x25519-keygen:Generate X25519 envelope encryption keypair'
  #|    'sign:Sign file with Ed25519 private key'
  #|    'verify:Verify Ed25519 publisher signature'
  #|    'keyring-init:Create Ed25519 trust keyring with revocation and quorum'
  #|    'sign-combine:Combine Ed25519 signatures into a multi-signer bundle'
  #|    'verify-quorum:Verify M-of-N Ed25519 signature bundle against keyring'
  #|    'seal:Encrypt file into MLSENC01 or MLSENC02 AEAD container'
  #|    'unseal:Decrypt and authenticate MLSENC01 or MLSENC02 AEAD container'
  #|    'dir-snapshot:Snapshot directory tree with SHA-256 digests'
  #|    'dir-plan:Plan directory sync between two snapshots'
  #|    'dir-verify:Verify directory tree against snapshot'
  #|    'dir-signatures:Generate remote signature set for directory'
  #|    'dir-pack:Pack directory incremental sync bundle or archive'
  #|    'dir-apply:Verify and apply directory bundle or archive'
  #|    'completions:Emit shell completion script'
  #|  )
  #|  local -a limit_opts dir_limit_opts
  #|  limit_opts=(
  #|    '--max-old-bytes[Max old bytes]:bytes:'
  #|    '--max-new-bytes[Max new bytes]:bytes:'
  #|    '--max-signature-bytes[Max signature bytes]:bytes:'
  #|    '--max-signature-records[Max signature records]:count:'
  #|    '--max-block-bytes[Max block bytes]:bytes:'
  #|    '--max-delta-bytes[Max delta bytes]:bytes:'
  #|    '--max-output-bytes[Max output bytes]:bytes:'
  #|    '--max-instructions[Max instructions]:count:'
  #|    '--max-match-work[Max match work]:count:'
  #|  )
  #|  dir_limit_opts=(
  #|    '--max-entries[Max directory entries]:count:'
  #|    '--max-path-bytes[Max relative path bytes]:bytes:'
  #|    '--max-depth[Max directory nesting depth]:depth:'
  #|    '--max-snapshot-bytes[Max snapshot JSON bytes]:bytes:'
  #|    '--max-file-bytes[Max per-file bytes]:bytes:'
  #|  )
  #|  if (( CURRENT == 2 )); then
  #|    _describe -t commands 'moonlibsync command' commands
  #|    compadd -- --help --version
  #|    return
  #|  fi
  #|  case "${words[2]}" in
  #|    signature)
  #|      _arguments '--profile[Signature profile]:profile:(rk-blake2 rollsum-blake2)' '--block-size[Block size]:size:(auto 512 1024 2048 4096 8192)' '--sum-size[Strong sum bytes]:size:(8 16 32)' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    reverse-delta)
  #|      _arguments '--block-size[Block size]:size:(auto 512 1024 2048 4096 8192)' '--sum-size[Strong sum bytes]:size:(8 16 32)' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    compose-delta)
  #|      _arguments '-o[Composed delta output]:file:_files' '--json[Output JSON]' '--progress[Emit progress to stderr]' $limit_opts '*:delta:_files' ;;
  #|    range-plan)
  #|      _arguments '-o[Range plan JSON output]:file:_files' '--merge-gap[Merge gap bytes]:bytes:' '--max-ranges[Max HTTP ranges]:count:' '--json[Output JSON]' '--progress[Emit progress to stderr]' $limit_opts '*:arg:_files' ;;
  #|    fetch-sync)
  #|      _arguments '--basis[Local basis file]:basis:_files' '--sig[Local target signature]:sig:_files' '--sig-url[Remote target signature URL]:url:' '-o[Reconstructed output file]:out:_files' '--target-length[Expected target byte length]:bytes:' '--merge-gap[Merge gap bytes]:bytes:' '--max-ranges[Max HTTP ranges]:count:' '--verify-sig[Signature JSON file]:sig:_files' '*--verify-key[Trusted public key file or hex]:key:_files' '--verify-bundle[Quorum signature bundle]:bundle:_files' '--keyring[Trust keyring JSON]:keyring:_files' '--json[Output JSON]' '--progress[Emit progress to stderr]' $limit_opts '*:url:' ;;
  #|    compress|decompress)
  #|      _arguments '--format[Compression format]:format:(gzip zlib deflate)' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    patch-verified)
  #|      _arguments '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' '--verify-sig[Signature JSON file]:sig:_files' '*--verify-key[Trusted public key file]:key:_files' $limit_opts '*:file:_files' ;;
  #|    apply-update)
  #|      _arguments '--basis[Basis file for delta mode]:basis:_files' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' '--verify-sig[Signature JSON file]:sig:_files' '*--verify-key[Trusted public key file]:key:_files' $limit_opts '*:file:_files' ;;
  #|    make-transfer-manifest)
  #|      _arguments '--min-savings[Minimum byte savings for delta]:bytes:' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    inspect-bundle)
  #|      _arguments '--gzip[Decompress gzip archive]' '--json[Output JSON]' '--progress[Emit progress to stderr]' $limit_opts $dir_limit_opts '*:archive:_files' ;;
  #|    verify)
  #|      _arguments '*--pub-key[Extra trusted public key file]:key:_files' '--json[Output JSON]' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    verify-quorum)
  #|      _arguments '--keyring[Trust keyring JSON]:keyring:_files' '--json[Output JSON]' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    x25519-keygen)
  #|      _arguments '-o[Secret key output file]:secret:_files' '--pub-out[Public key output file]:pub:_files' '--json[Output JSON]' ;;
  #|    keyring-init)
  #|      _arguments '*--trust[Trusted Ed25519 public key hex or file]:key:_files' '*--revoke[Revoked 16-hex key ID]:key_id:' '--quorum[Minimum quorum threshold]:count:' '-o[Keyring JSON output]:out:_files' '--json[Output JSON]' ;;
  #|    sign-combine)
  #|      _arguments '-o[Signature bundle output]:out:_files' '--json[Output JSON]' '*:sig:_files' ;;
  #|    seal)
  #|      _arguments '--key-file[Raw 32-byte hex key file]:file:_files' '--passphrase-file[Passphrase file]:file:_files' '*--recipient[X25519 recipient public key hex or file]:recipient:_files' '--chunk-size[AEAD chunk size]:bytes:' '--argon2-memory[Argon2id memory KiB]:kib:' '--argon2-passes[Argon2id passes]:passes:' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    unseal)
  #|      _arguments '--key-file[Raw 32-byte hex key file]:file:_files' '--passphrase-file[Passphrase file]:file:_files' '--recipient-key[X25519 recipient secret key file]:file:_files' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    dir-snapshot)
  #|      _arguments '*--exclude[Exclude glob pattern]:pattern:' '*--exclude-from[Exclude file]:file:_files' '--jobs[Parallel worker count]:jobs:(1 2 4 8)' '--meta-out[Directory metadata output JSON]:meta:_files' '--progress[Emit progress to stderr]' $dir_limit_opts '*:path:_files' ;;
  #|    dir-plan)
  #|      _arguments '--detect-moves[Detect moved/renamed files]' '--json[Output JSON]' '--progress[Emit progress to stderr]' $dir_limit_opts '*:snapshot:_files' ;;
  #|    dir-verify)
  #|      _arguments '--json[Output JSON]' '*--exclude[Exclude glob pattern]:pattern:' '*--exclude-from[Exclude file]:file:_files' '--jobs[Parallel worker count]:jobs:(1 2 4 8)' '--progress[Emit progress to stderr]' $dir_limit_opts '*:path:_files' ;;
  #|    dir-signatures)
  #|      _arguments '--profile[Signature profile]:profile:(rk-blake2 rollsum-blake2)' '--block-size[Block size]:size:(auto 512 1024 2048 4096 8192)' '--sum-size[Strong sum bytes]:size:(8 16 32)' '--jobs[Parallel worker count]:jobs:(1 2 4 8)' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts $dir_limit_opts '*:path:_files' ;;
  #|    dir-pack)
  #|      _arguments '--detect-moves[Detect moved/renamed files]' '--archive[Pack single-file MLSBDL01 archive]' '--gzip[Gzip-compress archive]' '*--exclude[Exclude glob pattern]:pattern:' '*--exclude-from[Exclude file]:file:_files' '--jobs[Parallel worker count]:jobs:(1 2 4 8)' '--min-savings[Minimum byte savings]:bytes:' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts $dir_limit_opts '*:path:_files' ;;
  #|    dir-apply)
  #|      _arguments '--archive[Apply single-file MLSBDL01 archive]' '--gzip[Decompress gzip archive]' '--meta[Directory metadata JSON]:meta:_files' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' '--verify-sig[Signature JSON file]:sig:_files' '*--verify-key[Trusted public key file]:key:_files' '--verify-bundle[Quorum signature bundle]:bundle:_files' '--keyring[Trust keyring JSON]:keyring:_files' '--save-rollback[Save .mbundle.gz rollback archive]:archive:_files' $limit_opts $dir_limit_opts '*:path:_files' ;;
  #|    completions)
  #|      _arguments '1:shell:(bash zsh powershell)' ;;
  #|    keygen)
  #|      _arguments '*:output:_files' ;;
  #|    delta|patch|basis-info|make-manifest|sign)
  #|      _arguments '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    inspect-signature|inspect-manifest)
  #|      _arguments '--json[Output JSON]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    inspect-delta|check-patch)
  #|      _arguments '--json[Output JSON]' '--streaming[Stream 64 KiB chunks]' '--progress[Emit progress to stderr]' $limit_opts '*:file:_files' ;;
  #|    *)
  #|      _arguments '*:file:_files' ;;
  #|  esac
  #|}
  #|if (( $+functions[compdef] )); then compdef _moonlibsync moonlibsync; fi
  #|

///|
let powershell_completions : String =
  #|# PowerShell completion for moonlibsync 0.7.1
  #|Register-ArgumentCompleter -Native -CommandName moonlibsync -ScriptBlock {
  #|  param($wordToComplete, $commandAst, $cursorPosition)
  #|  $commands = @(
  #|    'signature', 'delta', 'patch', 'reverse-delta', 'compose-delta', 'range-plan',
  #|    'fetch-sync', 'basis-info', 'make-manifest', 'patch-verified',
  #|    'inspect-signature', 'inspect-delta', 'check-patch', 'inspect-manifest',
  #|    'inspect-bundle', 'make-transfer-manifest', 'apply-update', 'compress',
  #|    'decompress', 'keygen', 'x25519-keygen', 'sign', 'verify', 'keyring-init',
  #|    'sign-combine', 'verify-quorum', 'seal', 'unseal', 'dir-snapshot',
  #|    'dir-plan', 'dir-verify', 'dir-signatures', 'dir-pack', 'dir-apply',
  #|    'completions'
  #|  )
  #|  $limitFlags = @(
  #|    '--max-old-bytes', '--max-new-bytes', '--max-signature-bytes',
  #|    '--max-signature-records', '--max-block-bytes', '--max-delta-bytes',
  #|    '--max-output-bytes', '--max-instructions', '--max-match-work'
  #|  )
  #|  $dirLimitFlags = @(
  #|    '--max-entries', '--max-path-bytes', '--max-depth',
  #|    '--max-snapshot-bytes', '--max-file-bytes'
  #|  )
  #|  $tokens = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
  #|  if ($tokens.Count -le 1 -or ($tokens.Count -eq 2 -and $wordToComplete -ne '')) {
  #|    ($commands + @('--help', '--version')) | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
  #|      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
  #|    }
  #|    return
  #|  }
  #|  $cmd = $tokens[1]
  #|  $prev = if ($tokens.Count -ge 2) { $tokens[$tokens.Count - 1] } else { '' }
  #|  if ($wordToComplete -ne '' -and $tokens.Count -ge 3) { $prev = $tokens[$tokens.Count - 2] }
  #|  if ($prev -eq '--profile') {
  #|    @('rk-blake2', 'rollsum-blake2') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
  #|      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
  #|    }
  #|    return
  #|  }
  #|  if ($prev -eq '--format') {
  #|    @('gzip', 'zlib', 'deflate') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
  #|      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
  #|    }
  #|    return
  #|  }
  #|  if ($cmd -eq 'completions') {
  #|    @('bash', 'zsh', 'powershell') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
  #|      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
  #|    }
  #|    return
  #|  }
  #|  if ($wordToComplete -like '-*') {
  #|    $flags = switch ($cmd) {
  #|      'signature' { @('--profile', '--block-size', '--sum-size', '--streaming', '--progress') + $limitFlags }
  #|      'reverse-delta' { @('--block-size', '--sum-size', '--streaming', '--progress') + $limitFlags }
  #|      'compose-delta' { @('-o', '--json', '--progress') + $limitFlags }
  #|      'range-plan' { @('-o', '--merge-gap', '--max-ranges', '--json', '--progress') + $limitFlags }
  #|      'fetch-sync' { @('--basis', '--sig', '--sig-url', '-o', '--target-length', '--merge-gap', '--max-ranges', '--verify-sig', '--verify-key', '--verify-bundle', '--keyring', '--json', '--progress') + $limitFlags }
  #|      'compress' { @('--format', '--streaming', '--progress') + $limitFlags }
  #|      'decompress' { @('--format', '--streaming', '--progress') + $limitFlags }
  #|      'patch-verified' { @('--streaming', '--progress', '--verify-sig', '--verify-key') + $limitFlags }
  #|      'apply-update' { @('--basis', '--streaming', '--progress', '--verify-sig', '--verify-key') + $limitFlags }
  #|      'make-transfer-manifest' { @('--min-savings', '--streaming', '--progress') + $limitFlags }
  #|      'inspect-signature' { @('--json', '--progress') + $limitFlags }
  #|      'inspect-manifest' { @('--json', '--progress') + $limitFlags }
  #|      'inspect-delta' { @('--json', '--streaming', '--progress') + $limitFlags }
  #|      'check-patch' { @('--json', '--streaming', '--progress') + $limitFlags }
  #|      'inspect-bundle' { @('--gzip', '--json', '--progress') + $limitFlags + $dirLimitFlags }
  #|      'verify' { @('--pub-key', '--json', '--streaming', '--progress') + $limitFlags }
  #|      'verify-quorum' { @('--keyring', '--json', '--streaming', '--progress') + $limitFlags }
  #|      'x25519-keygen' { @('-o', '--pub-out', '--json') }
  #|      'keyring-init' { @('--trust', '--revoke', '--quorum', '-o', '--json') }
  #|      'sign-combine' { @('-o', '--json') }
  #|      'seal' { @('--key-file', '--passphrase-file', '--recipient', '--chunk-size', '--argon2-memory', '--argon2-passes', '--streaming', '--progress') + $limitFlags }
  #|      'unseal' { @('--key-file', '--passphrase-file', '--recipient-key', '--streaming', '--progress') + $limitFlags }
  #|      'dir-snapshot' { @('--exclude', '--exclude-from', '--jobs', '--meta-out', '--progress') + $dirLimitFlags }
  #|      'dir-plan' { @('--detect-moves', '--json', '--progress') + $dirLimitFlags }
  #|      'dir-verify' { @('--json', '--exclude', '--exclude-from', '--jobs', '--progress') + $dirLimitFlags }
  #|      'dir-signatures' { @('--profile', '--block-size', '--sum-size', '--jobs', '--streaming', '--progress') + $limitFlags + $dirLimitFlags }
  #|      'dir-pack' { @('--detect-moves', '--archive', '--gzip', '--exclude', '--exclude-from', '--jobs', '--min-savings', '--streaming', '--progress') + $limitFlags + $dirLimitFlags }
  #|      'dir-apply' { @('--archive', '--gzip', '--meta', '--streaming', '--progress', '--verify-sig', '--verify-key', '--verify-bundle', '--keyring', '--save-rollback') + $limitFlags + $dirLimitFlags }
  #|      'keygen' { @() }
  #|      'completions' { @() }
  #|      default { @('--streaming', '--progress') + $limitFlags }
  #|    }
  #|    $flags | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
  #|      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_)
  #|    }
  #|  }
  #|}
  #|

///|
fn completion_script_for_shell(shell : String) -> String raise CliError {
  match shell {
    "bash" => bash_completions
    "zsh" => zsh_completions
    "powershell" => powershell_completions
    _ =>
      raise Usage(
        "unsupported shell: " + shell + " (expected bash, zsh, or powershell)",
      )
  }
}

///|
async fn execute_completions(
  plan : Plan,
  writer~ : async (Bytes) -> Unit = stdout_bytes,
) -> Unit {
  let script = completion_script_for_shell(plan.inputs[0])
  write_inspection(script, writer~) catch {
    error =>
      raise FileFailure(
        "stdout completions '" + plan.inputs[0] + "': " + cli_error_text(error),
      )
  }
}
