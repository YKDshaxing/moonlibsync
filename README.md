<div align="center">

# MoonLibSync

**Pure MoonBit, librsync-compatible binary delta library and Native single-file CLI.**

<p>
  <a href="README.md"><img src="https://img.shields.io/badge/English-Current-2563eb?style=for-the-badge" alt="English"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-%E5%88%87%E6%8D%A2%E4%B8%AD%E6%96%87-4b5563?style=for-the-badge" alt="简体中文"></a>
</p>

<p>
  <a href="https://github.com/YKDshaxing/moonlibsync/actions/workflows/ci.yml"><img src="https://github.com/YKDshaxing/moonlibsync/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://ykdshaxing.github.io/moonlibsync/"><img src="https://img.shields.io/badge/Live%20Demo-GitHub%20Pages-0f766e" alt="Live Web Demo"></a>
  <a href="https://mooncakes.io/docs/YKDshaxing/moonlibsync"><img src="https://img.shields.io/badge/mooncakes-YKDshaxing%2Fmoonlibsync-7c3aed" alt="Mooncakes"></a>
  <a href="https://github.com/YKDshaxing/moonlibsync/releases"><img src="https://img.shields.io/badge/version-0.7.1-0ea5e9" alt="Version 0.7.1"></a>
  <img src="https://img.shields.io/badge/targets-Native%20%7C%20JS%20%7C%20Wasm--GC-10b981" alt="Targets">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-LGPL--2.1--or--later-orange" alt="License"></a>
</p>

</div>

---

**MoonLibSync** implements the standard [`librsync`](https://github.com/librsync/librsync) (`v2.3.4`) binary delta protocol in pure MoonBit — with zero C FFI dependencies — compiling cleanly to **Native**, **JavaScript**, and **Wasm-GC**. Alongside wire-compatible `signature` / `delta` / `patch`, it provides O(1) inspection, reusable prepared signature indexes, explicit auto block sizing, SHA-256 integrity manifests, Delta-vs-Full transfer planning, and a defensive Native CLI with bounded reads and atomic no-overwrite commits.

## Features

| Layer | Public Entry Points | Purpose |
| --- | --- | --- |
| **Core Binary Delta & Compose** | `signature`, `signature_with_profile`, `delta`, `patch`, `compose_deltas`, `compose_delta_chain`, `create_reverse_delta*` | Wire-compatible with `librsync` dual BLAKE2 profiles (`0x72730147` RK+BLAKE2b & `0x72730137` Rollsum+BLAKE2b, delta `0x72730236`); O(1) open-addressed weak-hash lookup, `v1→v2 + v2→v3 ⇒ v1→v3` lossless delta squashing, and rollback deltas |
| **HTTP Range (`zsync`) Pull** | `plan_range_fetch`, `apply_range_fetch`, `encode_range_plan_json`, `RangeFetchOptions` | Pure zero-IO static CDN / S3 / Nginx incremental pull planner: matches local basis blocks against remote target signatures and coalesces minimal RFC 9110 `bytes=` ranges (`fetch-sync` / `range-plan`) |
| **Streaming & Sans-IO** | `SignatureHasher`, `DeltaScanner`, `PatchApplier`, `PatchDecoder`, `Sha256Hasher` | Pure zero-IO chunked pipelines + Sans-IO step decoder (`PatchStep`) & streaming SHA-256 bridging sync `Bytes`, Native `async/fs`, and browser JS/Workers |
| **Directory Sync, Moves, Jobs & Metadata** | `DirSnapshot`, `plan_dir_sync_with_options`, `DirBundleManifest`, `DirVerifyReport`, `DirMetadata`, `plan_dir_metadata`, `BundleArchiveDecoder` | Schema 3 deterministic snapshots, `--jobs N` concurrent scanning/packing, `empty_dirs` & POSIX `+x` metadata, `--detect-moves` 0-byte `CopyFromBasis` & `UpdateDeltaFrom`, `dir-verify`, `--exclude`/`--exclude-from`, and `MLSBDL01` `.mbundle`/`.mbundle.gz` archives |
| **Publisher Signing, Quorum & AEAD / X25519** | `YKDshaxing/moonlibsync/crypto`: `keypair_from_seed`, `sign_*`, `verify_quorum_*`, `seal_*`, `x25519_keypair_from_secret`, `seal_envelope`, `unseal_envelope` | Pure zero-IO Ed25519 signatures & `M-of-N` Keyring threshold verification with revocation, `MLSENC01` ChaCha20-Poly1305/Argon2id streaming encryption, and `MLSENC02` multi-recipient X25519 + HKDF-SHA256 envelopes |
| **Bounded Gzip / Zlib / Raw DEFLATE** | `YKDshaxing/moonlibsync/compress`: `compress_gzip`, `decompress_gzip`, `compress_zlib`, `decompress_zlib`, `compress_deflate`, `decompress_deflate`, `{Gzip,Zlib,Deflate}{Encoder,Decoder}` | Optional cross-target zero-IO single-member RFC 1952 Gzip, RFC 1950 Zlib, and RFC 1951 Raw DEFLATE with zip-bomb (`LimitExceeded`) and `TrailingData` guards |
| **Inspection & Preflight** | `inspect_signature`, `inspect_delta`, `check_patch` | O(1) zero-record-allocation signature metadata inspection, delta statistics, and COPY range preflight |
| **Reusable Prepared Index** | `prepare_signature`, `PreparedSignature::{delta, summary, plan_update}` | Parse and index a signature once; reuse across multiple targets with per-call `Limits` re-checks and independent work budgets |
| **Auto Block Sizing** | `recommend_block_len`, `signature --block-size auto` | Explicit integer policy v1 (targeting ~512 records, power-of-two rounding, bounded by `Limits`) |
| **Integrity Manifests** | `create/parse/encode_basis_info`, `create/parse/encode_update_manifest`, `verified_patch` | Strict bounded JSON (schema 1) binding `OLD`, `SIG`, `DELTA`, and `RESULT` via SHA-256 before returning or committing output |
| **Transfer Planning** | `plan_update`, `create/parse/encode_transfer_manifest`, `apply_update` | Schema 2 `Delta` vs. `Full` payload selection (chooses `Delta` only when strictly smaller and meeting `min_savings_bytes`) |
| **Native Single-File CLI** | `cmd/moonlibsync` (35 subcommands) | Full `--streaming` 64 KiB pipelines, `fetch-sync` / `range-plan` (HTTP `Range`), `compose-delta`, `--jobs N`, `--meta-out`/`--meta`, `--format gzip|zlib|deflate`, `x25519-keygen`, `keyring-init` / `sign-combine` / `verify-quorum`, `seal --recipient`, `--verify-bundle`, `completions`, symlink refusal & atomic commits |
| **Zero-Dep JS/TS SDK & Web Studio** | `js/` (`@ykdshaxing/moonlibsync@0.7.1`) & `examples/web-demo/` | Zero-runtime-dependency Node.js + Browser ES module (37 core exports, 33 typed methods, zero `any`), plus a 5-tab Web Worker Studio (HTTP `Range` pull, Delta-chain composer, Literal Hexdump Heatmap, `.mbundle.gz` Pack/Unpack, Gzip/Zlib + Ed25519/Quorum + X25519/AEAD Crypto Lab) |

## Quick Start

### 1. Install from Mooncakes

Add `YKDshaxing/moonlibsync` to your `moon.mod` (published on [Mooncakes](https://mooncakes.io/docs/YKDshaxing/moonlibsync)):

```moonbit
// moon.mod
import {
  "YKDshaxing/moonlibsync@0.7.1",
}
```

Import the root package in `moon.pkg`:

```moonbit
// moon.pkg
import {
  "YKDshaxing/moonlibsync" @lib,
}
```

### 2. Minimal Library Example

```moonbit
fn sync_demo() -> Unit raise {
  let limits = @lib.Limits::default()
  let old = Bytes::makei(512, i => (0x10 + i / 64).to_byte())
  let new_bytes = old[0:256].to_owned() + b"\x00\x80\xff" + old[256:].to_owned()

  // Receiver generates a signature from OLD
  let sig = @lib.signature(old, { block_len: 64L, strong_sum_len: 32L, }, limits)

  // Sender only needs SIG and NEW (never OLD)
  let prepared = @lib.prepare_signature(sig, limits)
  let plan = prepared.plan_update(new_bytes, @lib.UpdateOptions::default(), limits)

  // Receiver applies the delta to OLD and recovers NEW
  match plan.payload {
    Delta(delta_bytes) => assert_eq(@lib.patch(old, delta_bytes, limits), new_bytes)
    Full(full_bytes) => assert_eq(full_bytes, new_bytes)
  }
}
```

More runnable examples (all verified on `native`, `js`, and `wasm-gc`):
- [examples/basic](examples/basic/main.mbt) — core `signature` / `delta` / `patch`
- [examples/prepared](examples/prepared/main.mbt) — reusable `PreparedSignature` across multiple targets
- [examples/verified](examples/verified/main.mbt) — schema 1 integrity manifests & `verified_patch`
- [examples/auto](examples/auto/main.mbt) — explicit `recommend_block_len`
- [examples/transfer](examples/transfer/main.mbt) — schema 2 `Delta` vs. `Full` transfer workflow
- [examples/streaming](examples/streaming/main.mbt) — zero-IO streaming `SignatureHasher`, `DeltaScanner`, and `PatchApplier` (plus zero-dependency JS runner: `node examples/streaming/run-node.mjs`)
- [examples/web-demo](examples/web-demo/index.html) — 5-tab zero-backend static browser Web Worker Studio + 37-export ES module (`node examples/web-demo/test-node.mjs --rebuild`): HTTP `Range` pull simulator & live CORS fetch, Delta chain composer, Literal Hexdump Heatmap, Multi-Block Benchmark, Split-Role `rdiff`, Universal Artifact Inspector, `.mbundle.gz` Pack/Unpack + `--detect-moves`, and Gzip/Zlib + Ed25519 Quorum + X25519/AEAD Crypto Lab
- [js/README.md](js/README.md) — standalone zero-dependency typed JS/TS ES module SDK (`@ykdshaxing/moonlibsync`, verified with `node js/test-sdk.mjs`)

## Native Single-File CLI

Build from source (requires the locked MoonBit toolchain and a Native C/C++ compiler — MSVC Build Tools on Windows or GCC on Linux):

```bash
moon build cmd/moonlibsync --target native --release
```

> Note: On Linux, `moon build --target native` produces a native ELF executable that retains a `.exe` suffix under `_build/native/release/build/cmd/moonlibsync/moonlibsync.exe`. GitHub Release packages normalize the Linux binary name to `moonlibsync-linux-x86_64`.

### Core & Inspection Commands

```bash
# 1. Generate signature (fixed 2048/32 default, or explicit --block-size auto)
moonlibsync signature old.bin old.sig --block-size 64 --sum-size 32
moonlibsync signature old.bin auto.sig --block-size auto

# 2. Generate delta using only SIG + NEW
moonlibsync delta old.sig new.bin update.delta

# 3. Apply delta to OLD -> OUT (never overwrites existing files)
moonlibsync patch old.bin update.delta restored.bin

# 4. Read-only inspection & patch range preflight (human text or --json)
moonlibsync inspect-signature old.sig --json
moonlibsync inspect-delta update.delta --json
moonlibsync check-patch old.bin update.delta --json
moonlibsync inspect-manifest manifest.json --json

# 5. End-to-end streaming 64 KiB pipeline for > 64 MiB files (explicit --max-* + --streaming + --progress + gzip)
moonlibsync signature large-old.bin large.sig --streaming --progress --block-size auto --max-old-bytes 200000000
moonlibsync basis-info large-old.bin large.sig basis.json --streaming --max-old-bytes 200000000
moonlibsync delta large.sig large-new.bin large.delta --streaming --progress --max-new-bytes 200000000 --max-output-bytes 200000000 --max-match-work 2000000000
moonlibsync compress large.delta large.delta.gz --streaming --progress --max-new-bytes 200000000 --max-output-bytes 200000000
moonlibsync decompress large.delta.gz large.delta.raw --streaming --progress --max-delta-bytes 200000000 --max-output-bytes 200000000
moonlibsync make-transfer-manifest basis.json large.sig large-new.bin large.delta.raw transfer.json --streaming --max-old-bytes 200000000 --max-new-bytes 200000000 --max-delta-bytes 200000000 --max-output-bytes 200000000
moonlibsync apply-update large.delta.raw transfer.json restored.bin --basis large-old.bin --streaming --progress --max-old-bytes 200000000 --max-delta-bytes 200000000 --max-output-bytes 200000000

# 6. End-to-end signed, AEAD-sealed, move-aware directory archive sync + rollback (0.6.0)
moonlibsync keygen publisher.priv publisher.pub
moonlibsync dir-snapshot ./v1 v1.snapshot.json --exclude-from .moonlibsyncignore
moonlibsync dir-signatures ./v1 v1.snapshot.json ./v1-sigs --profile rollsum-blake2 --block-size auto --streaming --progress
moonlibsync dir-pack v1.snapshot.json ./v1-sigs ./v2 ./v1-to-v2.mbundle.gz --detect-moves --archive --gzip --exclude-from .moonlibsyncignore --streaming --progress
moonlibsync inspect-bundle ./v1-to-v2.mbundle.gz --gzip --json
moonlibsync sign ./v1-to-v2.mbundle.gz publisher.priv ./v1-to-v2.msig.json --streaming
moonlibsync seal ./v1-to-v2.mbundle.gz ./v1-to-v2.mbundle.gz.menc --passphrase-file pass.txt --streaming --progress
moonlibsync unseal ./v1-to-v2.mbundle.gz.menc ./unsealed.mbundle.gz --passphrase-file pass.txt --streaming --progress
moonlibsync dir-apply ./v1 ./unsealed.mbundle.gz ./v2-restored --archive --gzip --verify-sig ./v1-to-v2.msig.json --verify-key publisher.pub --save-rollback ./rollback-v2-to-v1.mbundle.gz --streaming --progress
moonlibsync dir-verify ./v2-restored v2.snapshot.json --json --exclude-from .moonlibsyncignore
moonlibsync completions powershell > moonlibsync-completions.ps1

# 7. Static HTTP Range (zsync) pull, delta-chain compose, X25519 multi-recipient & M-of-N quorum (0.7.x)
moonlibsync range-plan release-v2.sig 1048576 release-v1.bin --merge-gap 4096 --json
moonlibsync fetch-sync https://cdn.example.com/release-v2.bin --basis release-v1.bin --sig-url https://cdn.example.com/release-v2.sig --verify-bundle release-v2.sigbundle.json --keyring org.keyring.json -o release-v2.bin --json
moonlibsync compose-delta v1-to-v2.delta v2-to-v3.delta -o v1-to-v3.delta --json
moonlibsync x25519-keygen -o alice.x25519.sec --pub-out alice.x25519.pub
moonlibsync x25519-keygen -o bob.x25519.sec --pub-out bob.x25519.pub
moonlibsync seal payload.tar payload.menv --recipient alice.x25519.pub --recipient bob.x25519.pub
moonlibsync unseal payload.menv payload.restored.tar --recipient-key bob.x25519.sec
moonlibsync keyring-init --trust pub1.pub --trust pub2.pub --trust pub3.pub --quorum 2 -o org.keyring.json
moonlibsync sign-combine sig1.json sig2.json -o bundle.sig.json
moonlibsync verify-quorum artifact.bin bundle.sig.json --keyring org.keyring.json --json
moonlibsync dir-snapshot ./v2 v2.snap.json --jobs 4 --meta-out v2.meta.json
moonlibsync compress artifact.bin artifact.zlib --format zlib --streaming
```

### Integrity & Transfer Workflows

```bash
# Schema 1: SHA-256 verified delta workflow
moonlibsync basis-info old.bin old.sig basis.json
moonlibsync make-manifest basis.json old.sig new.bin update.delta manifest.json
moonlibsync patch-verified old.bin update.delta manifest.json restored.bin

# Schema 2: Delta-or-Full transfer workflow
moonlibsync make-transfer-manifest basis.json old.sig new.bin update.delta transfer.json --min-savings 64
moonlibsync apply-update update.delta transfer.json restored.bin --basis old.bin
```

**Exit codes**: `0` success / `--help` / `--version`, `2` CLI usage error, `1` file, limit, or core error. See [docs/cli.md](docs/cli.md) for full CLI semantics, `--` separator rules, and JSON schemas.

## Development & Verification

MoonLibSync pins its toolchain in [toolchain.lock.json](toolchain.lock.json) (`moonc v0.10.22+124d61d05`, `moon 0.1.20261119`) and its dependency closure in [dependencies.lock.json](dependencies.lock.json) (`mooncrypt 0.4.5`). The installer writes only into `.toolchain/` inside this repository.

<details>
<summary>Windows PowerShell setup & checks</summary>

```powershell
python scripts/install_toolchain.py
if ($LASTEXITCODE -ne 0) { throw 'Toolchain installation failed' }
$env:MOON_HOME = (Resolve-Path '.toolchain/selected').Path
$env:PATH = "$env:MOON_HOME\bin;$env:PATH"

python scripts/check.py            # Format, deps, 252 core + 13 compress + 20 crypto tests × 3 targets, 6 examples, web-demo ESM, JS/TS SDK, mbti guard
python scripts/verify_fixtures.py  # Reference & opcode fixture integrity
python scripts/failure_gates.py    # Isolated corruption & assertion failure gates
./scripts/cli-smoke.ps1            # 58 Native helper tests + 788 Windows CLI integration cases (812 on Linux/ext4)
node examples/streaming/run-node.mjs --rebuild
node examples/web-demo/test-node.mjs --rebuild
node js/test-sdk.mjs
python scripts/release_check.py --clean
```

</details>

<details>
<summary>Linux Bash setup & reference rdiff interoperability</summary>

```bash
set -euo pipefail
python3 scripts/install_toolchain.py
export MOON_HOME="$PWD/.toolchain/selected"
export PATH="$MOON_HOME/bin:$PATH"

python3 scripts/check.py
python3 scripts/verify_fixtures.py
python3 scripts/failure_gates.py
bash scripts/cli-smoke.sh

# Bidirectional interoperability against pinned librsync v2.3.4 (requires build-essential cmake libpopt-dev)
bash scripts/rebuild-reference.sh
python3 scripts/consume_signature.py
python3 scripts/consume_delta.py
bash scripts/interop.sh            # 274 input pairs, 496 parameter cases, 3968 recoveries
python3 scripts/file_exchange.py
```

</details>

## Compatibility, Security & Boundaries

- **Wire profiles**: Supports both modern BLAKE2 `librsync` profiles — `RS_RK_BLAKE2_SIG_MAGIC` (`0x72730147`, default `2048/32`) and `RS_BLAKE2_SIG_MAGIC` (`0x72730137` Rollsum + BLAKE2b) — plus full standard delta opcodes (`0x72730236`, 1/2/4/8-byte parameters, strict `END` with no trailing data). Legacy MD4 profiles (`0x72730136`, `0x72730146`) return `UnsupportedSignatureProfile`.
- **Full-buffer & streaming memory models**: One-shot operations work on bounded in-memory `Bytes` buffers (`Limits::default()` caps `OLD`/`NEW` at 64 MiB, `SIG` at 16 MiB, `DELTA` at 80 MiB), while streaming `SignatureHasher`, `DeltaScanner`, `PatchApplier`/`PatchDecoder`, `BundleArchiveDecoder`, `GzipEncoder`/`GzipDecoder`, and `SealEncoder`/`SealDecoder` keep internal buffers bounded across chunks. Limits are logical bounds, not process-wide RSS guarantees.
- **Integrity, publisher authentication & confidentiality**: Standard `delta`/`patch` do not verify basis identity; `verified_patch` / `apply_update` / `dir-apply` verify SHA-256 digests, and `YKDshaxing/moonlibsync/crypto` adds optional Ed25519 signing (`sign`/`verify`/`--verify-sig`), `M-of-N` quorum keyrings with revocation (`verify-quorum`/`--verify-bundle --keyring`), `MLSENC01` ChaCha20-Poly1305/Argon2id encryption (`seal`/`unseal`), and `MLSENC02` X25519 multi-recipient envelopes (`--recipient`/`--recipient-key`). Optional `--meta` directory metadata sidecars are cross-validated against the bundle manifest but reside outside `--verify-sig`/`--verify-bundle` payload digests. See [SECURITY.md](SECURITY.md).
- **Filesystems & distribution boundaries**: CLI atomic no-overwrite publication is validated on Windows/NTFS and Linux/ext4 (WSL DrvFS fails explicitly without fallback overwrite; set `MOONLIBSYNC_CLI_TMP_PARENT=/tmp` under WSL). HTTP `Range` (`fetch-sync`) is validated against loopback HTTP servers and the browser simulator (`js/` SDK is provided in-repo without npm registry publication).

## Documentation Index

- [CHANGELOG.md](CHANGELOG.md) — Version history (`0.7.1`, `0.7.0`, `0.6.1`, `0.6.0`, `0.5.0`, `0.4.0`, `0.3.2`, `0.3.1`, `0.3.0`, `0.2.0`, `0.1.0`)
- [js/README.md](js/README.md) — Zero-dependency in-repo Node.js & Browser JS/TS SDK (`@ykdshaxing/moonlibsync@0.7.1`)
- [SECURITY.md](SECURITY.md) — Security boundaries and vulnerability reporting
- [docs/design.md](docs/design.md) — Architecture and API design
- [docs/cli.md](docs/cli.md) — Native CLI reference (35 subcommands, `--streaming`, `fetch-sync`, `compose-delta`, `--jobs`, `x25519`/`quorum`, `--max-*`), JSON schemas, and filesystem guarantees
- [docs/dir-sync.md](docs/dir-sync.md) — Schema 3 directory snapshots, `DirMetadata` (`--meta-out`/`--meta`), `--jobs`, `MLSBDL01`, POSIX path safety rules, and `DirLimits`
- [docs/compatibility.md](docs/compatibility.md) — Protocol compatibility (`0.7.1` and historical contracts)
- [docs/matching.md](docs/matching.md) — Open-addressed weak-hash index, Pending Literal Run, and `MatchWork` v2 metering
- [docs/resources.md](docs/resources.md) — `Limits`, `SealLimits`, `TrustKeyring`, HTTP `Range` bounds, and memory contracts
- [docs/auto-block.md](docs/auto-block.md) — Auto block sizing (`policy v1`) rules and volume comparisons
- [docs/updates.md](docs/updates.md) — Delta vs. Full update planning and schema 2 specification
- [docs/manifests.md](docs/manifests.md) — Schema 1 integrity manifest specification
- [docs/benchmarks.md](docs/benchmarks.md) & [docs/benchmarks-prepared.md](docs/benchmarks-prepared.md) — Historical `0.1.0` (Commit 15/20) Linux process-level & prepared-index benchmarks
- [docs/release-0.7.0.md](docs/release-0.7.0.md) & [docs/contest-acceptance.md](docs/contest-acceptance.md) — `0.7.x` release acceptance matrix and `0.7.0` Mooncakes publication record ([0.3.0](docs/release-0.3.0.md) / [0.2.0](docs/release-0.2.0.md) / [0.1.0](docs/release.md))

## License

Licensed under **LGPL-2.1-or-later**. See [LICENSE](LICENSE), [COPYING.LESSER](COPYING.LESSER), [COPYING](COPYING), [SOURCES.md](SOURCES.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full license texts and upstream attributions.
