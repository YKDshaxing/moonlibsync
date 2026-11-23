# Security Policy

## Supported Versions

Security fixes are maintained for the latest `0.7.x` release line:

| Version | Supported |
| --- | --- |
| `0.7.x` | Yes |
| `< 0.7.0` | No (please upgrade to `0.7.x`) |

## Security Model & Boundaries

MoonLibSync is designed to handle **untrusted binary inputs** (signatures, deltas, gzip streams, bundle archives, JSON manifests, Ed25519 envelopes, and AEAD ciphertexts) defensively under explicit resource limits (`Limits`, `DirLimits`, `SealLimits`), while keeping cryptographic and filesystem boundaries explicit:

1. **Standard librsync signatures & deltas do NOT authenticate identity**:
   - Standard `signature` / `delta` / `patch` (both `0x72730147` RK+BLAKE2b and `0x72730137` Rollsum+BLAKE2b) confirm checksum prefixes for block matching only; they do not prove whole-file basis identity or output integrity.
   - Use `verified_patch` (schema 1), `apply_update` (schema 2), or `dir-apply` (schema 3) when whole-file SHA-256 verification is required.
2. **Optional Ed25519 publisher authentication, quorum keyring & AEAD / X25519 confidentiality (`YKDshaxing/moonlibsync/crypto`, 0.6.0–0.7.0+)**:
   - Unsigned `BasisInfo`, `UpdateManifest`, `TransferManifest`, `DirBundleManifest`, and `RangeFetchPlan` documents provide structural/hash integrity only and still require a trusted channel unless paired with an Ed25519 `PublisherSignature` (`moonlibsync sign` / `verify`, `--verify-sig` + `--verify-key`) or an `M-of-N` `SignatureBundle` + `TrustKeyring` (`keyring-init` / `sign-combine` / `verify-quorum`, `--verify-bundle` + `--keyring` on `dir-apply --archive` and `fetch-sync`).
   - Ed25519 verification enforces strict RFC 8032 §5.1.3 canonical on-curve point decoding, small-order point rejection, domain separation (`"moonlibsync-ed25519-v1\x00"`), and constant-time trusted-key matching (`@spec.eq`). `verify_quorum_*` checks `TrustKeyring.revoked_key_ids` before counting any signer toward `min_quorum` and rejects duplicate signers.
   - `MLSENC01` (`.menc`) streaming chunked AEAD (`moonlibsync seal` / `unseal`) uses ChaCha20-Poly1305 (RFC 8439) with per-chunk nonces, full 56-byte header + chunk index + `is_final` AAD binding, strict Argon2id cost bounds (`SealLimits`), and atomic no-overwrite publication only after final-chunk authentication succeeds.
   - `MLSENC02` multi-recipient X25519 envelope encryption (`moonlibsync seal --recipient` / `unseal --recipient-key`) derives per-recipient wrapping keys via X25519 + HKDF-SHA256 (`moonlibsync-mlsenc02-wrap-v1`), enforces canonical RFC 7748 public-key encodings (`MSB = 0`, `u < 2^255 - 19`), rejects all-zero/low-order public keys and all-zero content encryption keys, and binds all payload chunks to the SHA-256 of the entire preamble + recipient-slot table. Keyrings (`TrustKeyring`) cap trusted keys (`<= 64`) and revoked key IDs (`<= 256`).
   - HTTP `Range` static incremental pull (`moonlibsync fetch-sync`) validates canonical `http://`/`https://` URLs with non-empty host, follows bounded safe `3xx` HTTP redirects (at most 5 hops, blocking `https:// -> http://` downgrades and non-HTTP schemes), rejects compressed/non-`identity` `Content-Encoding` responses, requires strict canonical `Content-Range` headers on `206 Partial Content` responses, caps `target_length` by `min(max_new_bytes, max_output_bytes)` before scheduling range downloads, bounds HTTP I/O with a 60 s per-request timeout, reconstructs the complete target, always recomputes and verifies block checksums against the remote `.sig` before optional Ed25519 signature/quorum verification, and commits only via atomic no-overwrite rename.
   - Users remain responsible for protecting Ed25519/X25519 private key files, raw AEAD keys, and passphrases, and for pinning trusted public keys / keyrings out of band. Note also that CLI `--verify-sig` / `--verify-bundle` cover `.mbundle` / archive bytes, whereas `--meta` sidecar files live outside that payload digest and should be signed separately when authenticated directory metadata is required.
3. **Resource limits are logical bounds, not process-wide OOM guarantees**:
   - `Limits` bounds logical input/output sizes, record counts, instruction counts, and metered matching work (`MatchWork`). Full-buffer operations hold inputs and intermediate structures in memory; see [docs/resources.md](docs/resources.md).
4. **CLI filesystem guarantees**:
   - Regular-file bounded reads reject leaf symlinks, directories, FIFOs, and concurrent file growth/shrinkage; outputs are never overwritten (`CreateNew` temporary + `sync` + `rename(replace=false)`). CLI 64-hex inline key parsing enforces literal inline hex priority over same-named CWD files, and optional `--meta` directory metadata sidecars cross-validate `empty_dirs`/`executable_paths` against the applied manifest and enforce `0o700` owner-only permissions on non-Windows targets.
   - Validated on Windows/NTFS and Linux/ext4. Filesystems without atomic no-replace rename (such as WSL DrvFS) fail explicitly rather than falling back to overwrite.

## Reporting a Vulnerability

If you discover a security issue (e.g., bounds-check bypass, integer overflow, memory exhaustion bypassing `Limits`, manifest validation bypass, or CLI path/overwrite bug):

- **Preferred**: Open a private [GitHub Security Advisory](https://github.com/YKDshaxing/moonlibsync/security/advisories/new) on `YKDshaxing/moonlibsync`.
- **Alternative**: Email the maintainer directly at `1602373938@qq.com` with reproduction steps, affected version, and target (`native` / `js` / `wasm-gc` / CLI).

Please avoid posting unpatched exploits in public issues before a fix is released.
