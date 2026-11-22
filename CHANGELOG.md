# Changelog

All notable changes to **MoonLibSync** (`YKDshaxing/moonlibsync`) are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-11-22

### Added
- **Sans-IO async-ready `PatchDecoder` & streaming `Sha256Hasher`**:
  - `PatchDecoder` (`new`, `step -> (Int32, PatchStep)`, `has_pending_copy`, `finish`) yields zero-copy `EmitLiteral(BytesView)` and validated `CopyBasis(UInt64, Int32)` (`1..65536`-byte chunks) cleanly for synchronous `Bytes`, Native `async/fs`, and browser `File`/`Blob` callers (`stream_patch.mbt`). Existing `PatchApplier` delegates to `PatchDecoder` with 100% API compatibility.
  - `Sha256Hasher` (`new`, `update`, `finish -> FileDigest`) exposes O(1) bounded incremental SHA-256 via locked `mooncrypt@0.4.5` `@sha2.Hasher` (`Kind::Sha256`) with `0..2147483647` byte caps and fail-closed `errdefer` poisoning (`sha256.mbt`).
- **Native CLI `--streaming` 64 KiB pipelines (`cmd/moonlibsync/streaming.mbt`)**:
  - Explicit `--streaming` flag on `signature`, `delta`, `patch`, `patch-verified`, and `apply-update` processes inputs/outputs in bounded 64 KiB chunks while preserving leaf-symlink rejection, concurrent input-size/EOF verification, `fsync`, and atomic `rename(replace=false)`.
  - Verified on a synthetic **128 MiB** (`134,217,728`-byte) file pair on Windows Native `--release`: non-streaming is rejected under the 64 MiB default limit (`ReadLimitExceeded`), while `--streaming` with explicit `--max-* 200000000` completes `signature --block-size auto` (`18,444` B in `1.137 s`), `delta` (`266,757` B in `1.566 s`), `patch` (`0.392 s`), and single-pass `patch-verified` (`2.158 s`) with bit-exact SHA-256 recovery.
- **Zero-IO Directory Snapshots & Sync Planning (`dir_sync.mbt`, Schema 3, `docs/dir-sync.md`)**:
  - Added `DirLimits`, `DirEntry`, `DirSnapshot`, `DirActionKind`, `DirSyncAction`, `DirSyncPlan`, `create_dir_snapshot`, `encode_dir_snapshot`, `parse_dir_snapshot`, `plan_dir_sync`, `encode_dir_plan`, and `parse_dir_plan`.
  - Enforces strict POSIX-relative paths (rejecting `..`, `.`, leading/trailing `/`, `//`, `\`, `:`, control characters, trailing dots/spaces), UTF-8 bytewise lexicographical order, and single/cross-snapshot ASCII case-folding collision checks.
  - Added `dir-snapshot DIR OUT [DIR_LIMITS]` (strict `follow_symlink=false` traversal, atomic output) and read-only `dir-plan BASIS_SNAP TARGET_SNAP [--json] [DIR_LIMITS]` to `cmd/moonlibsync` (`cmd/moonlibsync/dir.mbt`).
- **Zero-backend static Browser Web Demo (`examples/web-demo/`)**:
  - Compiles pure MoonBit streaming sync & Schema 3 directory planning into a standard JS ES module (`run_streaming_sync_json`, `plan_dir_snapshots_json`) with a static `index.html` / `demo.mjs` UI and automated Node.js verification (`node examples/web-demo/test-node.mjs --rebuild`).
- **Verification**: 8 new core tests (`stream_patch_decoder_*`, `dir_sync_*` -> **218 tests × 3 targets**), 6 new Native CLI unit tests (`cmd/moonlibsync/v040_wbtest.mbt` -> **30 total**), and `scripts/cli_v040_cases.py` integrated into `scripts/cli_smoke.py`.

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
