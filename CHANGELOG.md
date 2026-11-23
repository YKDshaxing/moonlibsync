# Changelog

All notable changes to **MoonLibSync** (`YKDshaxing/moonlibsync`) are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.1] - 2026-11-23

### Security & Hardening
- **`fetch-sync` Mandatory Remote `.sig` Block Verification & Bounded Safe `3xx` Redirects (`cmd/moonlibsync/range_cli.mbt`)**:
  - `execute_fetch_sync` now always recomputes `@lib.signature_with_profile` over reconstructed bytes and requires exact equality against `target_sig` before publishing — preventing corrupted/raced range responses from writing silently even when `--verify-sig` / `--verify-bundle` is omitted.
  - Added bounded HTTP `3xx` (`301`/`302`/`303`/`307`/`308`) redirect following (at most `5` hops) across both `HEAD` and `GET`, enforcing strict canonical `http(s)://` URLs with non-empty host and explicitly rejecting `https:// -> http://` downgrades and non-HTTP schemes (`file://`, `ftp://`, etc.).
- **CLI Examples, Release Notes Automation & Documentation Fixes**:
  - Fixed `README.md` / `README.zh-CN.md` Section 7 CLI quick-start commands (`seal`/`unseal` positional `IN OUT` arguments instead of `-o`, and default-budget `range-plan` 1 MiB target example).
  - Fixed Web Studio (`examples/web-demo/demo.js`) copied CLI hints for `dir-apply` (`--archive --gzip`) and `dir-verify` (`./actual expected.snap.json --json > verify-report.json`).
  - Added `0.7.1 / 0.7.0` sections to `docs/design.md`, clarified `0.6.1` / `0.6.0` status in `CHANGELOG.md`, and updated `.github/workflows/release.yml` to generate GitHub Release notes directly from `CHANGELOG.md` + `SHA256SUMS.txt`.
- **Verification**: **252** core + **13** compress + **20** crypto tests × 3 targets, **58** Native CLI unit tests, **788** Windows/NTFS CLI integration cases (**812** on Linux/ext4 with `0 unsupported`), `WEB_DEMO_OK exports=37`, and `JS_SDK_OK`.

## [0.7.0] - 2026-11-23

### Added
- **Static HTTP `Range` (`zsync`) Incremental Pull (`range_sync.mbt`, `cmd/moonlibsync/range_cli.mbt`)**:
  - Added pure zero-IO `RangeFetchOptions`, `ByteRange` (`http_range_spec`), `RangePlanOp`, `RangeFetchPlan`, `plan_range_fetch`, `apply_range_fetch`, and `encode_range_plan_json` (Schema 3 `moonlibsync-range-plan`), matching local basis files against remote target `.sig` headers across both `RkBlake2` (`0x72730147`) and `RollsumBlake2` (`0x72730137`) profiles, coalescing small gaps (`merge_gap_bytes`) under bounded `max_ranges`.
  - Added Native CLI `range-plan` and `fetch-sync` (via `moonbitlang/core/async/http`): `HEAD` length discovery, bounded `206 Partial Content` `Range` fetches with strict `Content-Range` & length validation (`200 OK` fallback bounded by `max_new_bytes`), optional pre-commit `--verify-sig` / `--verify-bundle --keyring`, and atomic no-overwrite commits.
- **Standard `librsync 0x72730236` Delta-Chain Composition (`compose_delta.mbt`, `cmd/moonlibsync/range_cli.mbt`)**:
  - Added pure zero-IO `compose_deltas` and `compose_delta_chain` (`v1 -> v2 + v2 -> v3 => v1 -> v3`) without requiring `v1`/`v2`/`v3` payloads, binary-searching `first`'s output spans, coalescing adjacent `Copy` and `Literal` instructions, and emitting valid standard `0x72730236` bytes.
  - Added Native CLI `compose-delta DELTA1 DELTA2 [DELTA3...] -o OUT.delta [--json]`.
- **X25519 Multi-Recipient Envelope Encryption (`MLSENC02`) & Ed25519 Keyring / `M-of-N` Threshold Quorum (`crypto/x25519_envelope.mbt`, `crypto/keyring.mbt`, `cmd/moonlibsync/crypto_cli.mbt`)**:
  - Reuses locked `mooncrypt@0.4.5` (`kex/x25519`, `kdf/hkdf`, `aead/chachapoly`, `sign/ed25519`) in zero-IO, zero-experimental `YKDshaxing/moonlibsync/crypto`: added `X25519KeyPair`, `EnvelopeHeader`, `x25519_keypair_from_secret`, `x25519_public_from_secret`, `x25519_key_id`, `inspect_envelope_header`, `seal_envelope`, `unseal_envelope` (1–64 recipients with RFC 7748 low-order point checks and full-header SHA-256 AAD binding), plus `TrustKeyring`, `SignatureBundle`, `QuorumVerifyReport`, `create/encode/parse_trust_keyring`, `create/encode/parse_signature_bundle`, and `verify_quorum_{digest,bytes}` with explicit key revocation.
  - Added Native CLI `x25519-keygen`, `keyring-init`, `sign-combine`, `verify-quorum`, `seal --recipient` (repeatable), `unseal --recipient-key`, and `--verify-bundle BUNDLE --keyring KEYRING` on `dir-apply --archive` and `fetch-sync`.
- **Bounded RFC 1950 Zlib & Raw DEFLATE (`compress/zlib.mbt`), Concurrent Directory Engine (`--jobs N`), & `DirMetadata` (`dir_metadata.mbt`)**:
  - Added `ZlibEncoder`/`ZlibDecoder`, `DeflateEncoder`/`DeflateDecoder`, `compress_zlib`/`decompress_zlib`, and `compress_deflate`/`decompress_deflate` to `YKDshaxing/moonlibsync/compress`; extended CLI `compress`/`decompress` with `--format gzip|zlib|deflate`.
  - Added `DirMetadata` & `plan_dir_metadata` (`Schema 3` `moonlibsync-dir-metadata`), `--meta-out` (`dir-snapshot`), `--meta` (`dir-apply`, cross-platform empty dirs + POSIX `+x` mode on non-Windows), and `--jobs N` (`1..=64` via `@async.all` concurrency keeping 100% deterministic sorted output) across `dir-snapshot`, `dir-signatures`, `dir-pack`, and `dir-verify`.
  - Upgraded Native CLI to **35 subcommands** and updated `bash` / `zsh` / `powershell` completions.
- **Web Studio 0.7.0 (`examples/web-demo/`, 37 JS ESM Exports) & `@ykdshaxing/moonlibsync@0.7.0` SDK (`js/`)**:
  - Expanded Web Studio to 37 exports with interactive HTTP `Range` pull simulator & live CORS fetch, multi-hop delta-chain composer, Zlib/Gzip security toggle, X25519 multi-recipient envelope lab, Ed25519 `2-of-3` keyring quorum lab, and expanded Universal Artifact Inspector (`MLSENC02`, `zlib`, `keyring`, `signature-bundle`, `dir-metadata`, `moonlibsync-range-plan`).
  - Upgraded `@ykdshaxing/moonlibsync@0.7.0` to 33 zero-`any` typed `MoonLibSyncClient` methods + updated tests and documentation.

### Red-Team Adversarial Hardening
- **Core (`range_sync.mbt`, `dir_metadata.mbt`, `dir_sync.mbt`)**: Enforced `max_instructions` / `max_ranges` / `max_block_bytes` and strictly sorted disjoint `plan.ranges` in `apply_range_fetch` (eliminating `O(|ops|*|ranges|)` fallback); bounded `plan_range_fetch` output/instruction limits and non-positive `ByteRange::http_range_spec()`; prevented `plan_dir_metadata` from generating unsafe `rmdir_empty` steps on surviving/executable parents and detected case-folded collisions against `executable_paths`; expanded Windows reserved-name checks (`COM0`/`LPT0`, trailing spaces, superscript digits).
- **Crypto (`crypto/keyring.mbt`, `crypto/x25519_envelope.mbt`, `crypto/ed25519.mbt`)**: Enforced `TrustKeyring` caps (`<= 64` trusted keys, `<= 256` revoked key IDs) and single-pass `O(K + S)` quorum verification without per-signature keyring re-validation; enforced canonical RFC 7748 X25519 public keys (`MSB = 0`, `u < p`), rejected all-zero content encryption keys, and guarded `Int32` capacity overflow in `seal_envelope`.
- **Native CLI (`cmd/moonlibsync/`)**: Prevented CWD files from shadowing literal 64-hex inline Ed25519/X25519 keys; prevented `--exclude` filters from misclassifying excluded-only directories as empty; re-checked regular-file kind before POSIX `+x` probing/`chmod` and tightened applied executable/empty-dir permissions to `0o700` with manifest cross-validation on `--meta`; enforced mandatory `Content-Range` + strict canonical totals, `identity` `Content-Encoding`, `min(max_new_bytes, max_output_bytes)` cap before Range downloads, 60 s HTTP I/O timeouts, empty-host URL rejection, and `compdef` availability guards in `zsh` completions.
- **Web Studio & JS/TS SDK (`examples/web-demo/`, `js/`)**: Gated JSON artifact sniffing cleanly ahead of `.zlib` decompression so > 1 MiB `.zlib` streams inspect cleanly; added `0x78 0x5e` zlib error preservation and Schema 3 `moonlibsync-range-plan` inspection (with matching `RangePlanArtifactInspection` types); hardened live CORS HTTP `206` probing, `Content-Range` checks, 64 MiB cap, and full `.sig` BLAKE2b recomputation; corrected CLI snippet (`moonlibsync fetch-sync`), stacked bar widths, quorum error cleanup, ZH/EN dropzone state preservation; normalized hex outputs and removed weak CSPRNG fallback in `js/index.js`.
- **Verification**: **252** core + **13** compress + **20** crypto tests × 3 targets, **57** Native CLI unit tests, **784** Windows/NTFS CLI integration cases (**808** on Linux/ext4 with `0 unsupported`), `WEB_DEMO_OK exports=37`, and `JS_SDK_OK`.

## [0.6.1] - 2026-11-22

### Fixed
- **MoonBit `0.10.22+124d61d05` / `mooncakes.io` Core Compatibility**:
  - Updated [toolchain.lock.json](toolchain.lock.json) from `0.10.20+65efd5b93` (`2026-11-05`) to official `0.10.22+124d61d05` (`2026-11-19`, `moon 0.1.20261119`), matching the live Mooncakes documentation builder and current upstream `moonbitlang/core`.
  - Adapted [compress/gzip.mbt](compress/gzip.mbt) to the breaking `@moonbitlang/core/compress/gzip.Decoder` API change (`@gzip.Decoder()` is now single-member by default and never consumes past the member trailer, replacing removed `multistream=false` and `unused_input()` while preserving strict `TrailingData` and zip-bomb `LimitExceeded` enforcement).
  - Adapted Native CLI filesystem calls in [cmd/moonlibsync/dir_bundle.mbt](cmd/moonlibsync/dir_bundle.mbt), [cmd/moonlibsync/files.mbt](cmd/moonlibsync/files.mbt), [cmd/moonlibsync/streaming.mbt](cmd/moonlibsync/streaming.mbt), and [cmd/moonlibsync/files_wbtest.mbt](cmd/moonlibsync/files_wbtest.mbt) to `0.10.22` `moonbitlang/core/async/fs` (`allow_existing=`, `@fs.remove`, and positioned `file.at(pos).read_into(...)`).
  - Cleared all `0.10.22` compiler warnings across all 4 targets (`native`, `wasm-gc`, `wasm`, `js`): migrated `@buffer.Buffer(size_hint=...)` to `capacity=`, replaced `BigInt::from_string` in `crypto/ed25519.mbt` with native `BigInt` hex literals (`0x...N`), and removed unused `"moonbitlang/core/async"` imports from `probes/*/moon.pkg`.
- **Compatibility**: Zero public API (`.mbti`) changes; protected `_build/release-0.6.0` as read-only evidence in `scripts/release_check.py`. Version `0.6.1` supersedes `0.6.0` on Mooncakes (fixing `0.10.22` online documentation generation).

## [0.6.0] - 2026-11-22

### Added
- **Pure Zero-IO Cryptography Subpackage `YKDshaxing/moonlibsync/crypto` (`crypto/`, zero new third-party dependencies, zero `allow-experimental-packages`)**:
  - **Ed25519 Publisher Signing & Verification (`crypto/ed25519.mbt`)**: Reuses locked `mooncrypt@0.4.5` (`sign/ed25519`) across `native`, `js`, and `wasm-gc`, enforcing RFC 8032 §5.1.3 canonical on-curve point decoding, small-order point rejection, domain-separated digest signing (`"moonlibsync-ed25519-v1\x00"`), constant-time trusted-key comparison (`@spec.eq`), and bounded Schema 4 JSON (`kind: "moonlibsync-signature"`, `encode/parse_publisher_signature`).
  - **Streaming Chunked AEAD Encryption `MLSENC01` (`.menc`, `crypto/aead.mbt`)**: Reuses locked `mooncrypt@0.4.5` (`aead/chachapoly` + `kdf/argon2`), providing 56-byte header-bound per-chunk ChaCha20-Poly1305 encryption (`raw-key` or `Argon2id` passphrase with strict `SealLimits` anti-DoS bounds), one-shot `seal/unseal_with_{key,passphrase}`, and fail-closed Sans-IO `SealEncoder` / `SealDecoder` with `@spec.wipe` on pending encoder plaintext.
- **Dual Modern `librsync` BLAKE2 Signature Profiles (`rollsum.mbt`, `api.mbt`, `signature.mbt`, `stream_*.mbt`)**:
  - Added scalar `Rollsum` (`RS_BLAKE2_SIG_MAGIC` `0x72730137`) alongside `RS_RK_BLAKE2_SIG_MAGIC` (`0x72730147`), exposed via `SignatureProfile::{RkBlake2, RollsumBlake2}`, `signature_with_profile`, and `SignatureHasher::new_with_profile`; `inspect_signature`, `prepare_signature`, `delta`, `DeltaScanner`, and Schema 1/2 manifests handle both profiles automatically.
- **Directory Move/Copy 0-Byte Reuse (`--detect-moves`), `.moonlibsyncignore` (`--exclude-from`), and Reverse Rollback (`--save-rollback`, `reverse-delta`)**:
  - Added `DirPlanOptions { detect_moves }`, `plan_dir_sync_with_options`, `DirActionKind::CopyFromBasis(String)` (0-byte transfer), `DirBundleAction::{CopyFromBasis, UpdateDeltaFrom}` (cross-path delta for moved+edited files), `parse_dir_exclude_file`, and `create_reverse_delta` / `create_reverse_delta_auto` (`NEW -> OLD`).
- **Native CLI Expanded to 28 Subcommands (`cmd/moonlibsync/crypto_cli.mbt`, `completions.mbt`)**:
  - Added 8 new subcommands: `keygen`, `sign`, `verify`, `seal`, `unseal`, `reverse-delta`, `inspect-bundle` (read-only streaming `MLSBDL01` / `.mbundle.gz` validator), and `completions (bash|zsh|powershell)`.
  - Extended existing commands with `--profile rk-blake2|rollsum-blake2` (`signature`, `dir-signatures`), `--detect-moves` (`dir-plan`, `dir-pack`), `--exclude-from FILE` (`dir-snapshot`, `dir-pack`, `dir-verify`), `--verify-sig` / `--verify-key` (`patch-verified`, `apply-update`, `dir-apply --archive` with TOCTOU SHA-256 re-verification), and `--save-rollback OUT.mbundle.gz` (`dir-apply`).
  - Real Windows Native `--release` acceptance: a `1,179,648`-byte directory (1 MiB moved file + 128 KiB moved & edited file) packed via `--detect-moves --archive --gzip --exclude-from` into **`1,057` B** (`0.069 s`), Ed25519-signed and Argon2id/ChaCha20-Poly1305 sealed into **`1,134` B** (`0.094 s`), rejected 1-byte tamper (`AuthenticationFailed`) and untrusted key (`UntrustedKey`), applied with `--verify-sig --verify-key --save-rollback` (`0.301 s`), and rolled back `v2 -> v1` (`1,921` B `.mbundle.gz`, `0.134 s`) with full `dir-verify` passing bit-for-bit.
- **Web Studio 0.6.0 (`examples/web-demo/`, 27 JS ESM Exports) & `@ykdshaxing/moonlibsync@0.6.0` SDK (`js/`)**:
  - Added zero-dependency module **Web Worker (`examples/web-demo/worker.js`)** with animated progress bar and main-thread fallback, **Literal Hexdump + UTF-8 Preview** inside the Interactive Delta Block Reuse Heatmap, Rollsum `0x72730137` + `rollback.delta` download, `--detect-moves` & **In-Browser `.mbundle.gz` Pack & Roundtrip Unpack/Verify**, and upgraded Tab 5 (**Security & Crypto Lab**) with live **Ed25519** & **AEAD `.menc`** drills.
  - Upgraded `@ykdshaxing/moonlibsync` (`js/`) to `0.6.0` covering all 27 core exports and 23 typed client methods with zero `any` in `js/index.d.ts` and expanded `js/test-sdk.mjs`.
- **Red-Team Adversarial Hardening**:
  - Fixed `GzipEncoder::step(..., finish=true)` partial-consumption handling on chunks > 16,642 B (eliminating silent truncation when `@flate` requests output space before EOF);
  - Hardened `dir_sync.mbt` against Windows DOS reserved device names (`CON`/`PRN`/`AUX`/`NUL`/`COM1..9`/`LPT1..9`), exact & ASCII case-folded file-vs-directory prefix collisions (`foo` vs `foo/bar.txt`), intermediate directory case collisions (`DIR/b.txt` vs `dir/a.txt`), case-folded `CopyFromBasis`/`UpdateDeltaFrom` self-references, and aggregate `DirVerifyReport` count overflows; added cyclic swap (`a <-> b`) 0-byte move detection and streaming SHA-256 verification inside pure `encode/parse_bundle_archive` & `BundleArchiveDecoder`;
  - Hardened CLI `dir-apply --save-rollback` to reconstruct tracked basis snapshots strictly from the applied manifest (zero excluded-file leaks or excluded-symlink/oversized crashes), preserved `SealLimits::default()` 80 MiB ceiling in `seal`, synced non-streaming delta writes, aligned `reverse-delta` `max_old_bytes`/`max_new_bytes`, and fixed `zsh` completion flag scoping;
  - Hardened Web Studio & JS SDK (`hexToBytes` strict nibble validation, real UTF-8 decoding in Literal previews, Schema 2 `full-file` `.gz` target passthrough, strict negative-option/profile rejection, Worker crash recovery & ref-counted progress, explicit `modulePath` fail-closed loading, and `pages.yml` release-bundle smoke check).
- **Verification**: **233** core tests × 3 targets, **4** `compress` tests × 3 targets, **13** `crypto` tests × 3 targets, **46** Native CLI unit tests (`cmd/moonlibsync/v060_wbtest.mbt`), **685** Windows/NTFS CLI integration cases (**709** on Linux/ext4 with symlinks & FIFOs), plus `release_check.py --clean` (`dirty=False`, `git_blob_byte_identity_verified: True`).

### Compatibility
- 100% backward-compatible with `0.1.0`–`0.5.0` public APIs, `librsync` wire interoperability, Schema 1/2/3 formats, `Limits::default()`, and CLI no-overwrite atomic commits. Protected `_build/release-0.5.0` evidence as read-only in `scripts/release_check.py`.

## [0.5.0] - 2026-11-22

### Added
- **Deterministic Single-File Directory Bundle Archive (`MLSBDL01` `.mbundle` & optional `.mbundle.gz`, `bundle_archive.mbt`)**:
  - Pure zero-IO binary container format (`MLSBDL01` magic + big-endian `u32` manifest length + canonical Schema 3 `DirBundleManifest` JSON + payload stream in strict manifest order with `u16` path length + UTF-8 path + `u64` payload length + payload bytes) targeting `native`, `js`, and `wasm-gc` with zero new third-party dependencies and keeping root `YKDshaxing/moonlibsync` free of `allow-experimental-packages`.
  - Exposes one-shot `encode_bundle_archive` / `parse_bundle_archive` plus streaming Sans-IO `BundleArchiveDecoder` (`new`, `has_pending_event`, `step -> (Int32, BundleArchiveStep)`, `finish`) and `encode_bundle_archive_preamble` / `encode_bundle_payload_header`.
  - Native CLI `dir-pack` and `dir-apply` add `--archive` (single `.mbundle` file) and `--archive --gzip` (single RFC 1952 `.mbundle.gz` stream with bounded zip-bomb protection) using atomic no-overwrite publication and zero modification of `BASIS_DIR`.
- **Directory Verification (`dir-verify`) & Pre-Descent `--exclude` Glob Filtering (`dir_sync.mbt`, `cmd/moonlibsync/dir.mbt`)**:
  - Added pure zero-IO `match_dir_exclude`, `DirVerifyDiffKind`, `DirVerifyIssue`, `DirVerifyReport`, `verify_dir_snapshot`, `encode_dir_verify_report`, and `parse_dir_verify_report` (Schema 3 `kind: "moonlibsync-dir-verify"`).
  - Added Native CLI subcommand `moonlibsync dir-verify DIR SNAPSHOT [--json] [--exclude PATTERN]... [DIR_LIMITS]` (total **20** CLI subcommands): exits `0` when directory matches snapshot bit-for-bit (`ok: true`), exits `1` on any missing/extra/modified file while still emitting the structured report (`--json` or human text).
  - Added repeatable `--exclude PATTERN` on `dir-snapshot`, `dir-pack`, and `dir-verify`, pruning matched directories (e.g. `.git`, `node_modules`) before descending so excluded symlinks or build artifacts never block scanning.
- **Throttled Live CLI Progress (`--progress`, `cmd/moonlibsync/progress.mbt`)**:
  - Added opt-in `--progress` across all 15 streaming/transfer commands, writing throttled (~150 ms via `@async.now()`) byte/percentage/MiB/s/ETA lines exclusively to `stderr` (`[moonlibsync] <phase> ...`) with guaranteed `0`-byte `stdout` pollution (even when paired with `--json`).
  - Real Windows Native `--release` acceptance run on a **128 MiB** (`134,217,728`-byte) pair: `signature --streaming --progress --block-size auto` (`1.259 s`, `104.48 MiB/s`, `18,444` B), `delta --streaming --progress` (`1.674 s`, `77.71 MiB/s`, `1,048,703` B), `patch --streaming --progress` (`0.463 s`, bit-exact SHA-256), plus `dir-pack --archive --gzip --exclude` (`0.054 s`, `950` B `.mbundle.gz` from `4,259` B `MLSBDL01`) -> `dir-apply --archive --gzip` (`0.090 s`) -> `dir-verify --json` (clean pass & 1-byte tamper detection).
- **Interactive 5-Tab Pure-JS Web Demo Studio (`examples/web-demo/`)**:
  - Expanded MoonBit JS ESM bundle to **17** exported functions (`inspect_delta_detailed_json`, `inspect_artifact_json`, `benchmark_block_sizes_json`, `verify_dir_snapshots_json`, `filter_dir_entries_json`, `apply_verified_patch_json`, `apply_patch_or_gzip_bytes`).
  - Added **Interactive Delta Block Reuse Heatmap** (`COPY` emerald / `Literal` amber with clickable instruction inspector), **Multi-Block-Size Benchmark Chart** (`auto` vs `256` / `512` / `2048` / `4096`), **Split-Role Online `rdiff` Tools** (`.sig` / `.delta`+`.delta.gz` / auto-gunzip + optional Schema 1/2 manifest verified `patch`), **Universal Artifact Inspector** (`.sig`, `.delta`, `.delta.gz`, `.mbundle`, Schema 1/2/3 JSON), and **`dir-verify` & `--exclude` mode** in the Directory tab — plus aligned `36px` bilingual header buttons in both Chinese and English, Light and Dark mode.
- **Standalone Zero-Dependency Typed JS/TS SDK (`js/`, `@ykdshaxing/moonlibsync@0.5.0`)**:
  - Added universal Node.js + Browser ES module wrapper (`js/index.js`), strict zero-`any` TypeScript definitions (`js/index.d.ts`), release bundle builder (`js/build-dist.mjs`), package metadata (`js/package.json`), standalone documentation (`js/README.md`), and end-to-end test suite (`js/test-sdk.mjs`) wired into `scripts/check.py` and `scripts/release_check.py`.
- **Verification**: 4 new core test suites (`bundle_archive_test.mbt` + `dir_sync_test.mbt` -> **224 tests × 3 targets**), 3 cross-target compression tests (**3 tests × 3 targets**), 4 new Native CLI unit tests (`cmd/moonlibsync/v050_wbtest.mbt` -> **36 total**), and 56 new CLI integration cases (`scripts/cli_v050_cases.py` -> **529** total in `scripts/cli_smoke.py`).

### Compatibility
- 100% backward-compatible with `0.3.x` / `0.4.0` public APIs, `librsync` (`0x72730147` / `0x72730236`) wire interoperability, schema 1/2/3 manifests, `Limits::default()`, `MatchWork` v2 accounting, and CLI no-overwrite atomic commits. Protected `_build/release-0.4.0` evidence as read-only in `scripts/release_check.py`.

## [0.4.0] - 2026-11-22

### Added
- **Sans-IO async-ready `PatchDecoder` & streaming `Sha256Hasher`**:
  - `PatchDecoder` (`new`, `new_format_only`, `step -> (Int32, PatchStep)`, `feed_inspect`, `has_pending_copy`, `finish`) yields zero-copy `EmitLiteral(BytesView)` and validated `CopyBasis(UInt64, Int32)` (`1..65536`-byte chunks) for synchronous `Bytes`, Native `async/fs`, and browser JS callers, plus O(1)-memory streaming inspection (`stream_patch.mbt`). Existing `PatchApplier` delegates to `PatchDecoder` with 100% API compatibility.
  - `Sha256Hasher` (`new`, `update`, `finish -> FileDigest`) exposes O(1) bounded incremental SHA-256 via locked `mooncrypt@0.4.5` `@sha2.Hasher` (`Kind::Sha256`) with `0..2147483647` byte caps and fail-closed `errdefer` poisoning (`sha256.mbt`).
- **Complete Native CLI `--streaming` 64 KiB pipelines (`cmd/moonlibsync/streaming.mbt`, `inspect.mbt`)**:
  - Explicit `--streaming` flag across all 15 applicable commands (`signature`, `delta`, `patch`, `basis-info`, `make-manifest`, `patch-verified`, `inspect-delta`, `check-patch`, `make-transfer-manifest`, `apply-update`, `compress`, `decompress`, `dir-signatures`, `dir-pack`, `dir-apply`) while preserving leaf-symlink rejection, concurrent input-size/EOF verification, `fsync`, and atomic `rename(replace=false)`.
  - Verified on a synthetic **128 MiB** (`134,217,728`-byte) file pair end-to-end purely inside Windows Native `--release` CLI (`--max-* 200000000 --max-match-work 2000000000`): `signature --streaming --block-size auto` (`2.579 s`, `18,444` B), `basis-info --streaming` (`1.881 s`), `delta --streaming` (`1.722 s`, `791,039` B, `99.41%` COPY reuse), `inspect-delta --streaming` (`0.027 s`), `check-patch --streaming` (`0.033 s`), `compress --streaming` (`0.145 s`, shrinking delta to `5,950` B), `decompress --streaming` (`0.038 s`), `make-transfer-manifest --streaming` (`1.030 s`), and `apply-update --streaming` (`2.219 s`) with bit-exact SHA-256 recovery.
- **Zero-IO Directory Snapshots, Sync Planning & End-to-End Incremental Bundles (`dir_sync.mbt`, Schema 3, `docs/dir-sync.md`)**:
  - Added `DirLimits`, `DirEntry`, `DirSnapshot`, `DirActionKind`, `DirSyncAction`, `DirSyncPlan`, `DirSignatureEntry`, `DirSignatureIndex`, `DirBundleAction`, `DirBundleEntry`, `DirBundleManifest`, and canonical `create/encode/parse_*` codecs plus `plan_dir_sync`.
  - Enforces strict POSIX-relative paths, UTF-8 bytewise lexicographical order, single/cross-snapshot ASCII case-folding collision checks, and `sigs/` / `payloads/` scoped collision-free paths.
  - Added 5 Native CLI directory commands (`cmd/moonlibsync/dir.mbt`, `dir_bundle.mbt`): `dir-snapshot`, `dir-plan`, `dir-signatures`, `dir-pack` (remote-signature-only sender with per-file Delta vs Full selection), and `dir-apply` (per-file SHA-256 verification, transactional staging directory rename, zero symlinks, never mutating `BASIS_DIR` or overwriting existing output directories).
- **Dedicated Pure Zero-IO Bounded Gzip Subpackage `compress/` + CLI `compress` / `decompress`**:
  - Added cross-target (`native`, `js`, `wasm-gc`) `YKDshaxing/moonlibsync/compress` (`compress/gzip.mbt`: `compress_gzip`, `decompress_gzip`, streaming `GzipEncoder`, `GzipDecoder`, `GzipStatus`, `GzipStep`, `GzipSummary`) wrapping locked stdlib `moonbitlang/core/compress/{gzip,flate}` (zero new third-party dependencies, keeping root `YKDshaxing/moonlibsync` 100% free of `allow-experimental-packages`).
  - Built-in zip-bomb guard (`LimitExceeded`), strict single-member framing rejecting trailing bytes (`TrailingData`), truncated streams (`TruncatedInput`), and corrupt headers/CRCs (`InvalidDelta`).
  - Added `moonlibsync compress IN OUT [--streaming] [LIMITS]` and `moonlibsync decompress IN OUT [--streaming] [LIMITS]` (`cmd/moonlibsync/compress_cli.mbt`).
- **Upgraded Static Browser Web Demo (`examples/web-demo/`) & GitHub Pages Workflow (`.github/workflows/pages.yml`)**:
  - Added binary exports (`create_signature_bytes`, `create_delta_bytes`, `apply_patch_bytes`, `sha256_hex_bytes`, `compress_gzip_bytes`, `decompress_gzip_bytes`, `decompress_gzip_check_json`, `create_dir_snapshot_json`) alongside `run_streaming_sync_json` and `plan_dir_snapshots_json`.
  - Upgraded static `index.html` / `demo.js` with a bilingual (EN/中文) Light/Dark studio UI, drag-and-drop file zones, visual bandwidth comparison bars, downloadable `.sig` / `.delta` / `.delta.gz` / restored `NEW` artifacts, and an interactive Schema 3 folder diff tab (`<input webkitdirectory>` + filterable table + downloadable `plan.json`), plus `.github/workflows/pages.yml` for GitHub Pages deployment and automated `node examples/web-demo/test-node.mjs` verification.
- **Verification**: 10 new core tests (`stream_patch_decoder_*`, `dir_sync_*` -> **220 tests × 3 targets**), 3 cross-target compression tests (`compress/compress_test.mbt` -> **3 tests × 3 targets**), 8 new Native CLI unit tests (`cmd/moonlibsync/v040_wbtest.mbt` -> **32 total**), and expanded `scripts/cli_v040_cases.py` (**473** integration cases in `scripts/cli_smoke.py`).

### Compatibility
- 100% backward-compatible with `0.3.x` public APIs, `librsync` (`0x72730147` / `0x72730236`) wire interoperability, schema 1/2 manifests, `Limits::default()`, `MatchWork` v2 accounting, and CLI no-overwrite atomic commits. Protected `_build/release-0.3.2` evidence as read-only in `scripts/release_check.py`.

## [0.3.2] - 2026-11-22

### Performance & `MatchWork` v2
- **O(n)-space O(1)-lookup weak-checksum hash table (`index.mbt`)**: Added linear open-addressed hash arrays (`bucket_weak`, `bucket_start`, capacity `M = next_pow2(max(2, 2 * u))`, load factor `<= 0.50`, never allocating `2^32` entries) pointing directly to sorted record groups while preserving 100% deterministic earliest-ordinal block selection on collisions and duplicate weak checksums.
- **Pending Literal Run & deferred window slicing (`delta.mbt`, `index.mbt`)**: Replaced per-byte `BytesView` slicing on misses in `scan_signature_delta` with an integer span (`lit_start`, `lit_len`, `lit_cap`) flushed only on matches, length-class encoding boundaries, or EOF, plus zero-view `match_signature_at` weak probing (constructing a `BytesView` and running BLAKE2b only on weak-hash hits).
- **`MatchWork` v2 accounting**: Precharges `2 * M` before hash table allocation plus `1` per insertion probe, charges `1` per open-addressed lookup probe, and meters pending literal miss appends (`1`) separately from flushed instruction emissions (`docs/matching.md`, `docs/resources.md`, `resources_wbtest.mbt`).
- **Local Windows Native `--release` micro-benchmark (`v0.3.1` vs `0.3.2`, 1 warmup + 5 formal runs, median)**:
  - `1 MiB` all-different one-shot `delta` (`block_len=2048, strong_sum_len=32`): `94.18 ms -> 17.44 ms` (**5.40x speedup**; byte-identical `1,048,586`-byte output).
  - `1 MiB` all-different `PreparedSignature::delta`: `97.10 ms -> 17.33 ms` (**5.60x speedup**).
  - `K=16` `PreparedSignature` reuse on an `8192`-record signature (`block_len=128, strong_sum_len=16`, `64 KiB` targets in `0.3.2`): `47.35 ms` one-shot total vs `16.41 ms` prepared total (`1.99 ms` prepare) (**2.89x speedup**).

### Added
- **Pure zero-IO streaming state machines (Native / JS / Wasm-GC)**:
  - `SignatureHasher` (`new`, `update`, `take_ready`, `finish`) using streaming `@blake2.Hasher` (`mooncrypt@0.4.5`) with O(1) hash state and atomic preflight checks (`stream_signature.mbt`).
  - `DeltaScanner` (`new`, `feed`, `take_ready`, `finish`) reusing immutable `PreparedSignature` with O(`block_len`) sliding window buffer, 64 KiB (`65536`-byte) pending literal flush, cross-chunk COPY coalescing, EOF rollout, and fail-closed `errdefer { self.failed = true }` poisoning (`stream_delta.mbt`).
  - `BasisReader` (`pub(open) trait`, plus `pub impl BasisReader for Bytes`) and `PatchApplier` (`new`, `feed`, `finish -> DeltaSummary`) with byte-by-byte delta parsing, UInt64 bounds checks before `read_at`, `<= 65536`-byte COPY chunks, strict `END`/`TrailingData`/`TruncatedInput`, and `errdefer` poisoning (`stream_patch.mbt`).
- **Native CLI enhancements (`cmd/moonlibsync`)**:
  - Read-only `inspect-manifest MANIFEST [--json] [LIMITS]` supporting all four schema 1/2 manifest variants (`BasisInfo`, `UpdateManifest`, `TransferManifest::Delta`, `TransferManifest::Full`) with 64 KiB metadata cap and exit codes `0`/`1`/`2`.
  - All 9 optional `--max-*` `Limits` override flags (`--max-old-bytes`, `--max-new-bytes`, `--max-signature-bytes`, `--max-signature-records`, `--max-block-bytes`, `--max-delta-bytes`, `--max-output-bytes`, `--max-instructions`, `--max-match-work`), keeping `Limits::default()` unchanged when omitted and supporting order independence with `--block-size`.
- **Cross-target streaming example & JS runner**: `examples/streaming/main.mbt`, `examples/streaming/moon.pkg`, `examples/streaming/run-node.mjs`.
- **Verification**: 10 new core tests (`index_hash_wbtest.mbt`, `stream_test.mbt`, `stream_wbtest.mbt` -> **210 tests × 3 targets**), 5 new Native CLI unit tests (`cmd/moonlibsync/v032_wbtest.mbt` -> **24 total**), and `scripts/cli_v032_cases.py` integrated into `scripts/cli_smoke.py`.

### Compatibility
- 100% backward-compatible with `0.3.0`/`0.3.1` public APIs, `librsync` (`0x72730147` / `0x72730236`) wire interoperability, schema 1/2 manifests, `Limits::default()`, and CLI no-overwrite atomic commits. Protected `_build/release-0.3.1` evidence as read-only in `scripts/release_check.py`.

## [0.3.1] - 2026-11-21

### Added
- `PreparedSignature::summary(self) -> SignatureSummary`: O(1) metadata inspection for an already prepared signature without retaining or re-parsing the original signature bytes.
- `PreparedSignature::plan_update(self, new_bytes, options, limits) -> UpdatePlan raise SyncError`: Delta vs. Full update planning directly reusing a prepared signature index.
- Automated GitHub Release workflow (`.github/workflows/release.yml`) for building and publishing verified Native CLI binaries (`moonlibsync-linux-x86_64`, `moonlibsync-windows-x86_64.exe`, and `SHA256SUMS.txt`) on `v*` tags.
- Bilingual `README.md` (English) and `README.zh-CN.md` (Simplified Chinese) with top language-switcher buttons, plus `CHANGELOG.md` and `SECURITY.md`.
- 6 new core unit/whitebox tests (`prepared_extensions_test.mbt`, `prepared_extensions_wbtest.mbt`), bringing the root suite to **200 tests × 3 targets** (`native`, `js`, `wasm-gc`).

### Performance (100% backward-compatible, unchanged error precedence & `MatchWork` accounting)
- **Zero-allocation O(1) `inspect_signature`**: validates signature headers, profile, alignment, limits, and greatest nominal offset directly via `parse_signature_header`, eliminating O(n) record-array and per-digest allocations (also speeding up `create_basis_info` and `create_update_manifest`).
- **Faster `RabinKarp` hashing**: computes `mult` once in `O(log n)` via binary exponentiation in `RabinKarp::update` instead of multiplying per byte, and uses a direct multiplier-free `rabinkarp_digest` path in `signature()`.
- **Cache-friendly signature lookup**: stores a contiguous `sorted_weaks : FixedArray[UInt32]` array inside `SignatureIndex`, eliminating double indirect array/struct dereferences in the hot binary-search loop.
- **Bulk memory copy**: replaces byte-by-byte copy loops in `execute_patch_commands`, `encode_delta`, and `write_signature_record` with safe core `FixedArray::blit_from_bytes` / `blit_from_bytesview` primitives.

### Changed & Cleaned
- Normalized local machine absolute paths in `docs/benchmarks-prepared.md` and `docs/probes.md` to repository-relative paths.
- Updated top-level status headers in `docs/design.md`, `docs/contest-acceptance.md`, `docs/compatibility.md`, `docs/resources.md`, and `docs/cli.md` from `0.2.0`/`0.3.0` to `0.3.1` while preserving all historical release evidence.
- Cleaned stale development-stage comments and redundant `#warnings` directives in core `.mbt` modules.
- Protected historical `_build/release-0.3.0` evidence as read-only in `scripts/release_check.py`.

## [0.3.0] - 2026-11-11

Published on [Mooncakes (`YKDshaxing/moonlibsync@0.3.0`)](https://mooncakes.io/docs/YKDshaxing/moonlibsync@0.3.0) from source commit `35b2225e56747c0d7568dd117017c25e6c658146` (tag `v0.3.0`). Verified on Windows/NTFS and Linux/ext4 via clean-cache registry consumption across Native, JS, and Wasm-GC. See [docs/release-0.3.0.md](docs/release-0.3.0.md).

### Added
- Explicit automatic signature block sizing: `recommend_block_len(basis_len, strong_sum_len, limits)` (policy v1) and CLI `signature OLD SIG --block-size auto`.
- Update payload planning and schema 2 transfer manifests: `plan_update`, `UpdateOptions`, `UpdatePayload`, `UpdateDecision`, `UpdatePlan`, `TransferManifest`, `create/parse/encode_transfer_manifest`, and `apply_update`.
- Single-output CLI transfer commands: `make-transfer-manifest` and `apply-update`.
- Runnable public examples `examples/auto` and `examples/transfer`.

## [0.2.0] - 2026-11-10

Published on [Mooncakes (`YKDshaxing/moonlibsync@0.2.0`)](https://mooncakes.io/docs/YKDshaxing/moonlibsync@0.2.0) from source commit `069c126e2ea67c52a5759478edf480afa68f31a4` (tag `v0.2.0`). See [docs/release-0.2.0.md](docs/release-0.2.0.md).

### Added
- Read-only inspection and patch preflight APIs & CLI commands (`--json` schema 1): `inspect_signature`, `inspect_delta`, `check_patch`.
- Opaque reusable signature index: `prepare_signature` and `PreparedSignature::delta`.
- Bounded out-of-band integrity manifests (schema 1, SHA-256): `BasisInfo`, `UpdateManifest`, `FileDigest`, `ManifestError`, `create/parse/encode_*`, and `verified_patch`.
- CLI manifest commands: `basis-info`, `make-manifest`, and `patch-verified`.
- Runnable public examples `examples/prepared` and `examples/verified`.

## [0.1.0] - 2026-11-09

Initial release published on [Mooncakes (`YKDshaxing/moonlibsync@0.1.0`)](https://mooncakes.io/docs/YKDshaxing/moonlibsync@0.1.0) from source commit `f62958eceda9deecc4eae8a14007f5be76c59b0e` (tag `v0.1.0`). See [docs/release.md](docs/release.md).

### Added
- Pure MoonBit librsync-compatible (`RS_RK_BLAKE2_SIG_MAGIC` `0x72730147`, delta `0x72730236`) byte-buffer core (`signature`, `delta`, `patch`) targeting Native, JS, and Wasm-GC.
- Explicit resource bounds (`Limits`, `MatchWork`) and checked unsigned integer wire codecs.
- Native single-file CLI (`cmd/moonlibsync`) with bounded file reading, symlink rejection, fsync, and atomic no-overwrite publication.
- Bidirectional interoperability test suite verified against pinned upstream `librsync v2.3.4` (`3968` matrix recoveries).
