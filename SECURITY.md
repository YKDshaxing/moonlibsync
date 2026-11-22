# Security Policy

## Supported Versions

Security fixes are maintained for the latest `0.6.x` release line:

| Version | Supported |
| --- | --- |
| `0.6.x` | Yes |
| `< 0.6.0` | No (please upgrade to `0.6.x`) |

## Security Model & Boundaries

MoonLibSync is designed to handle **untrusted binary inputs** (signatures, deltas, gzip streams, bundle archives, JSON manifests, Ed25519 envelopes, and AEAD ciphertexts) defensively under explicit resource limits (`Limits`, `DirLimits`, `SealLimits`), while keeping cryptographic and filesystem boundaries explicit:

1. **Standard librsync signatures & deltas do NOT authenticate identity**:
   - Standard `signature` / `delta` / `patch` (both `0x72730147` RK+BLAKE2b and `0x72730137` Rollsum+BLAKE2b) confirm checksum prefixes for block matching only; they do not prove whole-file basis identity or output integrity.
   - Use `verified_patch` (schema 1), `apply_update` (schema 2), or `dir-apply` (schema 3) when whole-file SHA-256 verification is required.
2. **Optional Ed25519 publisher authentication & AEAD confidentiality (`YKDshaxing/moonlibsync/crypto`, 0.6.0+)**:
   - Unsigned `BasisInfo`, `UpdateManifest`, `TransferManifest`, and `DirBundleManifest` documents provide SHA-256 integrity only and still require a trusted channel unless paired with an Ed25519 `PublisherSignature` (`moonlibsync sign` / `verify`, or `--verify-sig` + `--verify-key` on `patch-verified`, `apply-update`, and `dir-apply --archive`).
   - Ed25519 verification enforces strict RFC 8032 §5.1.3 canonical on-curve point decoding, small-order point rejection, domain separation (`"moonlibsync-ed25519-v1\x00"`), and constant-time trusted-key matching (`@spec.eq`).
   - `MLSENC01` (`.menc`) streaming chunked AEAD (`moonlibsync seal` / `unseal`) uses ChaCha20-Poly1305 (RFC 8439) with per-chunk nonces, full 56-byte header + chunk index + `is_final` AAD binding, strict Argon2id cost bounds (`SealLimits`), and atomic no-overwrite publication only after final-chunk authentication succeeds.
   - Users remain responsible for protecting Ed25519 private key files, raw AEAD keys, and passphrases, and for pinning trusted public keys out of band.
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
