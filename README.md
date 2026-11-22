<div align="center">

# MoonLibSync

**Pure MoonBit, librsync-compatible binary delta library and Native single-file CLI.**

<p>
  <a href="README.md"><img src="https://img.shields.io/badge/English-Current-2563eb?style=for-the-badge" alt="English"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-%E5%88%87%E6%8D%A2%E4%B8%AD%E6%96%87-4b5563?style=for-the-badge" alt="简体中文"></a>
</p>

<p>
  <a href="https://github.com/YKDshaxing/moonlibsync/actions/workflows/ci.yml"><img src="https://github.com/YKDshaxing/moonlibsync/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://mooncakes.io/docs/YKDshaxing/moonlibsync"><img src="https://img.shields.io/badge/mooncakes-YKDshaxing%2Fmoonlibsync-7c3aed" alt="Mooncakes"></a>
  <a href="https://github.com/YKDshaxing/moonlibsync/releases"><img src="https://img.shields.io/badge/version-0.4.0-0ea5e9" alt="Version 0.4.0"></a>
  <img src="https://img.shields.io/badge/targets-Native%20%7C%20JS%20%7C%20Wasm--GC-10b981" alt="Targets">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-LGPL--2.1--or--later-orange" alt="License"></a>
</p>

</div>

---

**MoonLibSync** implements the standard [`librsync`](https://github.com/librsync/librsync) (`v2.3.4`) binary delta protocol in pure MoonBit — with zero C FFI dependencies — compiling cleanly to **Native**, **JavaScript**, and **Wasm-GC**. Alongside wire-compatible `signature` / `delta` / `patch`, it provides O(1) inspection, reusable prepared signature indexes, explicit auto block sizing, SHA-256 integrity manifests, Delta-vs-Full transfer planning, and a defensive Native CLI with bounded reads and atomic no-overwrite commits.

## Features

| Layer | Public Entry Points | Purpose |
| --- | --- | --- |
| **Core Binary Delta** | `signature`, `delta`, `patch` | Wire-compatible with `librsync` (`RS_RK_BLAKE2_SIG_MAGIC` `0x72730147`, delta `0x72730236`); O(1) open-addressed weak-hash lookup (`<= 0.50` load) and Pending Literal Run |
| **Streaming & Sans-IO** | `SignatureHasher`, `DeltaScanner`, `PatchApplier`, `PatchDecoder`, `Sha256Hasher` | Pure zero-IO chunked pipelines + Sans-IO step decoder (`PatchStep`) & streaming SHA-256 bridging sync `Bytes`, Native `async/fs`, and browser JS |
| **Directory Sync Planning** | `DirLimits`, `create/parse/encode_dir_snapshot`, `plan_dir_sync`, `create/parse/encode_dir_plan` | Schema 3 deterministic POSIX-relative snapshots & sync planning rejecting traversal, unsafe names, and ASCII case collisions |
| **Inspection & Preflight** | `inspect_signature`, `inspect_delta`, `check_patch` | O(1) zero-record-allocation signature metadata inspection, delta statistics, and COPY range preflight |
| **Reusable Prepared Index** | `prepare_signature`, `PreparedSignature::{delta, summary, plan_update}` | Parse and index a signature once; reuse across multiple targets with per-call `Limits` re-checks and independent work budgets |
| **Auto Block Sizing** | `recommend_block_len`, `signature --block-size auto` | Explicit integer policy v1 (targeting ~512 records, power-of-two rounding, bounded by `Limits`) |
| **Integrity Manifests** | `create/parse/encode_basis_info`, `create/parse/encode_update_manifest`, `verified_patch` | Strict bounded JSON (schema 1) binding `OLD`, `SIG`, `DELTA`, and `RESULT` via SHA-256 before returning or committing output |
| **Transfer Planning** | `plan_update`, `create/parse/encode_transfer_manifest`, `apply_update` | Schema 2 `Delta` vs. `Full` payload selection (chooses `Delta` only when strictly smaller and meeting `min_savings_bytes`) |
| **Native Single-File CLI** | `cmd/moonlibsync` (14 subcommands) | Bounded reads + `--streaming` 64 KiB pipelines (> 64 MiB files), `dir-snapshot`/`dir-plan`, `inspect-manifest`, `--max-*`, symlink refusal, `fsync`, and `rename(replace=false)` |

## Quick Start

### 1. Install from Mooncakes

Add `YKDshaxing/moonlibsync` to your `moon.mod` (published on [Mooncakes](https://mooncakes.io/docs/YKDshaxing/moonlibsync)):

```moonbit
// moon.mod
import {
  "YKDshaxing/moonlibsync@0.3.0", // or latest 0.3.x once published
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
- [examples/web-demo](examples/web-demo/index.html) — zero-backend static browser UI + ES module (`node examples/web-demo/test-node.mjs --rebuild`) running pure MoonBit streaming sync & dir-plan in JS

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

# 5. Streaming 64 KiB pipelines for > 64 MiB files (explicit --max-* + --streaming)
moonlibsync signature large-old.bin large.sig --streaming --block-size auto --max-old-bytes 200000000
moonlibsync patch large-old.bin large.delta restored.bin --streaming --max-old-bytes 200000000 --max-delta-bytes 200000000 --max-output-bytes 200000000

# 6. Deterministic directory snapshots & read-only sync planning (Schema 3)
moonlibsync dir-snapshot ./v1 v1.snapshot.json
moonlibsync dir-plan v1.snapshot.json v2.snapshot.json --json
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

MoonLibSync pins its toolchain in [toolchain.lock.json](toolchain.lock.json) (`moonc v0.10.20+65efd5b93`, `moon 0.1.20261104`) and its dependency closure in [dependencies.lock.json](dependencies.lock.json) (`mooncrypt 0.4.5`). The installer writes only into `.toolchain/` inside this repository.

<details>
<summary>Windows PowerShell setup & checks</summary>

```powershell
python scripts/install_toolchain.py
if ($LASTEXITCODE -ne 0) { throw 'Toolchain installation failed' }
$env:MOON_HOME = (Resolve-Path '.toolchain/selected').Path
$env:PATH = "$env:MOON_HOME\bin;$env:PATH"

python scripts/check.py            # Format, deps, 218 core tests × 3 targets, 6 examples, web-demo ESM, mbti guard
python scripts/verify_fixtures.py  # Reference & opcode fixture integrity
python scripts/failure_gates.py    # Isolated corruption & assertion failure gates
./scripts/cli-smoke.ps1            # 30 Native helper tests + Windows CLI integration suite
node examples/streaming/run-node.mjs --rebuild
node examples/web-demo/test-node.mjs --rebuild
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

- **Wire profile**: Supports `RS_RK_BLAKE2_SIG_MAGIC` (`0x72730147`, BLAKE2b-256 truncated to `1..32` bytes, default `2048/32`) and full standard delta opcodes (`0x72730236`, 1/2/4/8-byte parameters, strict `END` with no trailing data). Other signature magics return `UnsupportedSignatureProfile`.
- **Full-buffer & streaming memory models**: One-shot operations work on bounded in-memory `Bytes` buffers (`Limits::default()` caps `OLD`/`NEW` at 64 MiB, `SIG` at 16 MiB, `DELTA` at 80 MiB), while streaming `SignatureHasher`, `DeltaScanner`, and `PatchApplier` keep internal buffers O(1) / O(`block_len`) + 64 KiB across chunks. Limits are logical bounds, not process-wide RSS guarantees.
- **Integrity vs. authentication**: Standard `delta`/`patch` do not verify basis identity; `verified_patch` / `apply_update` verify SHA-256 digests against a **trusted** manifest (no built-in publisher signing). See [SECURITY.md](SECURITY.md).
- **Filesystems**: CLI atomic no-overwrite publication is validated on Windows/NTFS and Linux/ext4. WSL DrvFS (`/mnt/*`) lacks atomic no-replace rename and fails explicitly without falling back to overwrite (set `MOONLIBSYNC_CLI_TMP_PARENT=/tmp` for positive Linux CLI smoke runs under WSL).

## Documentation Index

- [CHANGELOG.md](CHANGELOG.md) — Version history (`0.4.0`, `0.3.2`, `0.3.1`, `0.3.0`, `0.2.0`, `0.1.0`)
- [SECURITY.md](SECURITY.md) — Security boundaries and vulnerability reporting
- [docs/design.md](docs/design.md) — Architecture and API design
- [docs/cli.md](docs/cli.md) — Native CLI reference (`--streaming`, `dir-snapshot`/`dir-plan`, `--max-*`), JSON schemas, and filesystem guarantees
- [docs/dir-sync.md](docs/dir-sync.md) — Schema 3 directory snapshots, POSIX path safety rules, and `DirLimits`
- [docs/compatibility.md](docs/compatibility.md) — Protocol compatibility and version contracts
- [docs/matching.md](docs/matching.md) — Open-addressed weak-hash index, Pending Literal Run, and `MatchWork` v2 metering
- [docs/resources.md](docs/resources.md) — `Limits`, `MatchWork` v2, and streaming/full-buffer memory contracts
- [docs/auto-block.md](docs/auto-block.md) — Auto block sizing (`policy v1`) rules and volume comparisons
- [docs/updates.md](docs/updates.md) — Delta vs. Full update planning and schema 2 specification
- [docs/manifests.md](docs/manifests.md) — Schema 1 integrity manifest specification
- [docs/benchmarks.md](docs/benchmarks.md) & [docs/benchmarks-prepared.md](docs/benchmarks-prepared.md) — Measured process-level & prepared-index benchmarks
- [docs/release-0.3.0.md](docs/release-0.3.0.md) / [docs/release-0.2.0.md](docs/release-0.2.0.md) / [docs/release.md](docs/release.md) — Historical Mooncakes release verification evidence

## License

Licensed under **LGPL-2.1-or-later**. See [LICENSE](LICENSE), [COPYING.LESSER](COPYING.LESSER), [COPYING](COPYING), [SOURCES.md](SOURCES.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full license texts and upstream attributions.
