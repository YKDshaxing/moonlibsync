# Security Policy

## Supported Versions

Security fixes are maintained for the latest `0.3.x` release line:

| Version | Supported |
| --- | --- |
| `0.3.x` | Yes |
| `< 0.3.0` | No (please upgrade to `0.3.x`) |

## Security Model & Boundaries

MoonLibSync is designed to handle **untrusted binary inputs** (signatures, deltas, JSON manifests) defensively under explicit resource limits (`Limits`), but callers must respect these clear cryptographic and filesystem boundaries:

1. **Standard librsync signatures & deltas do NOT authenticate identity**:
   - Standard `signature` / `delta` / `patch` confirm checksum prefixes for block matching only; they do not prove whole-file basis identity or output integrity.
   - Use `verified_patch` (schema 1) or `apply_update` (schema 2) when whole-file SHA-256 verification is required.
2. **Manifests provide integrity, NOT publisher authentication**:
   - `BasisInfo`, `UpdateManifest`, and `TransferManifest` bind lengths and SHA-256 digests, not digital signatures. Applications MUST obtain manifests over an authenticated/trusted channel (e.g., HTTPS/TLS, signed release metadata).
3. **Resource limits are logical bounds, not process-wide OOM guarantees**:
   - `Limits` bounds logical input/output sizes, record counts, instruction counts, and metered matching work (`MatchWork`). Full-buffer operations hold inputs and intermediate structures in memory; see [docs/resources.md](docs/resources.md).
4. **CLI filesystem guarantees**:
   - Regular-file bounded reads reject leaf symlinks, directories, FIFOs, and concurrent file growth/shrinkage; outputs are never overwritten (`CreateNew` temporary + `sync` + `rename(replace=false)`).
   - Validated on Windows/NTFS and Linux/ext4. Filesystems without atomic no-replace rename (such as WSL DrvFS) fail explicitly rather than falling back to overwrite.

## Reporting a Vulnerability

If you discover a security issue (e.g., bounds-check bypass, integer overflow, memory exhaustion bypassing `Limits`, manifest validation bypass, or CLI path/overwrite bug):

- **Preferred**: Open a private [GitHub Security Advisory](https://github.com/YKDshaxing/moonlibsync/security/advisories/new) on `YKDshaxing/moonlibsync`.
- **Alternative**: Email the maintainer directly at `1602373938@qq.com` with reproduction steps, affected version, and target (`native` / `js` / `wasm-gc` / CLI).

Please avoid posting unpatched exploits in public issues before a fix is released.
