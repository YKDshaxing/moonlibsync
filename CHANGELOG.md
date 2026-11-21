# Changelog

All notable changes to **MoonLibSync** (`YKDshaxing/moonlibsync`) are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
