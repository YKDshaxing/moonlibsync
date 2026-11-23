// SPDX-License-Identifier: LGPL-2.1-or-later

/**
 * Low-level synchronous 37-export contract of MoonLibSync's pure MoonBit JS core module.
 */
export interface MoonLibSyncRawModule {
  run_streaming_sync_json(
    oldBytes: Uint8Array,
    newBytes: Uint8Array,
    blockLen: number,
    strongSumLen: number,
    chunkSize: number,
  ): string;
  create_signature_bytes(
    oldBytes: Uint8Array,
    blockLen: number,
    strongSumLen: number,
  ): Uint8Array;
  create_signature_with_profile_bytes(
    basis: Uint8Array,
    blockLen: number,
    strongSumLen: number,
    profile: string,
  ): Uint8Array;
  create_delta_bytes(sigBytes: Uint8Array, newBytes: Uint8Array): Uint8Array;
  create_reverse_delta_bytes(
    oldBytes: Uint8Array,
    newBytes: Uint8Array,
    blockLen: number,
    strongSumLen: number,
  ): Uint8Array;
  apply_patch_bytes(oldBytes: Uint8Array, deltaBytes: Uint8Array): Uint8Array;
  sha256_hex_bytes(data: Uint8Array): string;
  compress_gzip_bytes(data: Uint8Array, level: number): Uint8Array;
  decompress_gzip_bytes(data: Uint8Array, maxOutput: number): Uint8Array;
  decompress_gzip_check_json(data: Uint8Array, maxOutput: number): string;
  create_dir_snapshot_json(entriesJson: string): string;
  plan_dir_snapshots_json(basisJson: string, targetJson: string): string;
  plan_dir_snapshots_with_options_json(
    basisEntriesJson: string,
    targetEntriesJson: string,
    detectMoves: boolean,
  ): string;
  pack_dir_bundle_archive_json(
    basisFilesJson: string,
    targetFilesJson: string,
    detectMoves: boolean,
    gzipCompress: boolean,
  ): string;
  unpack_dir_bundle_archive_json(
    basisFilesJson: string,
    archiveBytes: Uint8Array,
  ): string;
  inspect_delta_detailed_json(deltaBytes: Uint8Array, maxItems: number): string;
  inspect_artifact_json(data: Uint8Array): string;
  benchmark_block_sizes_json(
    oldBytes: Uint8Array,
    newBytes: Uint8Array,
    strongSumLen: number,
  ): string;
  verify_dir_snapshots_json(expectedJson: string, actualJson: string): string;
  filter_dir_entries_json(entriesJson: string, patternsJson: string): string;
  apply_verified_patch_json(
    oldBytes: Uint8Array,
    deltaOrGz: Uint8Array,
    manifestJson: string,
  ): string;
  apply_patch_or_gzip_bytes(
    oldBytes: Uint8Array,
    deltaOrGz: Uint8Array,
  ): Uint8Array;
  ed25519_keypair_from_seed_json(seed: Uint8Array): string;
  ed25519_sign_bytes_json(seed: Uint8Array, payload: Uint8Array): string;
  ed25519_verify_bytes_json(
    sigJson: string,
    trustedPubkeysJson: string,
    payload: Uint8Array,
  ): string;
  seal_bytes_json(
    plain: Uint8Array,
    secret: Uint8Array,
    usePassphrase: boolean,
    salt16: Uint8Array,
    noncePrefix12: Uint8Array,
    chunkSize: number,
    argon2MemoryKib: number,
    argon2Passes: number,
  ): string;
  unseal_bytes_json(
    cipher: Uint8Array,
    secret: Uint8Array,
    usePassphrase: boolean,
  ): string;
  plan_range_fetch_json(
    targetSig: Uint8Array,
    targetLength: number,
    basis: Uint8Array,
    mergeGapBytes: number,
    maxRanges: number,
  ): string;
  apply_range_fetch_json(
    targetSig: Uint8Array,
    targetLength: number,
    basis: Uint8Array,
    mergeGapBytes: number,
    maxRanges: number,
    slicesJson: string,
  ): string;
  compose_deltas_json(deltasJson: string): string;
  compress_zlib_bytes(
    input: Uint8Array,
    maxInput: number,
    maxOutput: number,
    level: number,
  ): Uint8Array;
  decompress_zlib_check_json(
    input: Uint8Array,
    maxInput: number,
    maxOutput: number,
  ): string;
  x25519_keypair_from_secret_json(secretHex: string): string;
  seal_envelope_json(
    plaintext: Uint8Array,
    recipientPubsJson: string,
    ephemeralSecretHex: string,
    contentKeyHex: string,
    noncePrefixHex: string,
    chunkSize: number,
  ): string;
  unseal_envelope_json(
    ciphertext: Uint8Array,
    recipientSecretHex: string,
  ): string;
  create_trust_keyring_json(
    trustedKeysJson: string,
    revokedIdsJson: string,
    minQuorum: number,
  ): string;
  verify_quorum_bytes_json(
    signaturesJson: string,
    keyringJson: string,
    payload: Uint8Array,
  ): string;
}

/**
 * Structured error thrown by MoonLibSync SDK operations.
 */
export class MoonLibSyncError extends Error {
  readonly code: string;
  constructor(code: string, message?: string, options?: ErrorOptions);
}

export interface LoadMoonLibSyncOptions {
  /**
   * Optional explicit path or URL to the compiled MoonBit ES module (`moonlibsync-core.js` / `web-demo.js`).
   */
  modulePath?: string | URL;
}

/**
 * Supported modern librsync BLAKE2 signature weak-checksum profiles.
 * - `'rk-blake2'`: `RS_RK_BLAKE2_SIG_MAGIC` (`0x72730147`, Rabin-Karp + BLAKE2b)
 * - `'rollsum-blake2'`: `RS_BLAKE2_SIG_MAGIC` (`0x72730137`, Adler-style Rollsum + BLAKE2b)
 */
export type SignatureProfile = 'rk-blake2' | 'rollsum-blake2';

export interface SignatureOptions {
  /**
   * Fixed signature block length in bytes, or `0` for automatic recommendation. Default: `0`.
   */
  blockLen?: number;
  /**
   * BLAKE2b strong checksum length in bytes (`1..32`). Default: `32`.
   */
  strongSumLen?: number;
  /**
   * Weak checksum signature profile. Default: `'rk-blake2'` (`0x72730147`).
   */
  profile?: SignatureProfile;
}

export interface ReverseDeltaOptions {
  /**
   * Fixed signature block length in bytes, or `0` for automatic recommendation. Default: `0`.
   */
  blockLen?: number;
  /**
   * BLAKE2b strong checksum length in bytes (`1..32`). Default: `16`.
   */
  strongSumLen?: number;
}

export interface StreamingSyncOptions {
  /**
   * Fixed signature block length in bytes, or `0` for automatic recommendation. Default: `0`.
   */
  blockLen?: number;
  /**
   * BLAKE2b strong checksum length in bytes (`1..32`). Default: `16`.
   */
  strongSumLen?: number;
  /**
   * Streaming feed chunk size in bytes (`> 0`). Default: `4096`.
   */
  chunkSize?: number;
}

export interface CompressGzipOptions {
  /**
   * RFC 1952 Gzip / DEFLATE compression level (`0..9`). Default: `6`.
   */
  level?: number;
}

export interface DecompressGzipOptions {
  /**
   * Maximum allowed decompressed output size in bytes. Default: `67108864` (64 MiB).
   */
  maxOutput?: number;
}

export interface InspectDeltaOptions {
  /**
   * Maximum number of COPY/Literal instructions to emit (clamped to `1..2048` by core). Default: `512`.
   */
  maxItems?: number;
}

export interface BenchmarkBlockSizesOptions {
  /**
   * BLAKE2b strong checksum length in bytes (`1..32`). Default: `16`.
   */
  strongSumLen?: number;
}

export interface CreateDirSnapshotOptions {
  /**
   * Optional POSIX glob exclusion patterns (e.g. `[".git", "node_modules", "*.log", "dist/*"]`).
   */
  excludes?: readonly string[];
}

export interface PlanDirSnapshotsOptions {
  /**
   * Enable content-digest move/rename detection (`copy-from-basis` 0-byte transfers). Default: `false`.
   */
  detectMoves?: boolean;
}

export interface PackDirBundleOptions {
  /**
   * Enable move/rename detection (`copy-from-basis` & `update-delta-from`). Default: `false`.
   */
  detectMoves?: boolean;
  /**
   * Wrap the `.mbundle` container in single-member RFC 1952 Gzip framing (`.mbundle.gz`). Default: `false`.
   */
  gzip?: boolean;
}

export interface FileDigest {
  byte_length: string;
  sha256: string;
}

export interface UpdateManifest {
  schema_version: 1;
  kind: 'librsync-delta';
  basis: FileDigest;
  signature: FileDigest;
  delta: FileDigest;
  result: FileDigest;
}

export interface TransferDeltaManifest {
  schema_version: 2;
  kind: 'librsync-delta';
  basis: FileDigest;
  signature: FileDigest;
  payload: FileDigest;
  result: FileDigest;
}

export interface TransferFullManifest {
  schema_version: 2;
  kind: 'full-file';
  payload: FileDigest;
  result: FileDigest;
}

export type TransferManifest = TransferDeltaManifest | TransferFullManifest;
export type PatchManifestInput = string | UpdateManifest | TransferManifest;

export interface ApplyPatchOrGzipResult {
  bytes: Uint8Array;
  sha256: string;
  decompressedGzip: boolean;
  verifiedManifest: boolean;
}

export interface SyncResult {
  ok: true;
  block_len: string;
  strong_sum_len: string;
  old_bytes: string;
  new_bytes: string;
  signature_bytes: string;
  delta_bytes: string;
  gzip_delta_bytes: string;
  copy_bytes: string;
  literal_bytes: string;
  instruction_count: string;
  copy_commands: string;
  literal_commands: string;
  old_sha256: string;
  new_sha256: string;
  restored_sha256: string;
  verified: boolean;
}

export interface DeltaSummary {
  delta_bytes: string;
  instruction_count: string;
  literal_commands: string;
  copy_commands: string;
  literal_bytes: string;
  copy_bytes: string;
  output_bytes: string;
}

export type DeltaInstructionKind = 'copy' | 'literal';

export interface DeltaInstructionItem {
  index?: number;
  kind: DeltaInstructionKind;
  offset: string;
  length: string;
  output_offset: string;
  preview_hex?: string;
  preview_utf8?: string;
  preview_truncated?: boolean;
}

export type DeltaCommandInfo = DeltaInstructionItem;

export interface DeltaDetailedInspection {
  ok: true;
  summary: DeltaSummary;
  total_commands?: string;
  truncated: boolean;
  items: DeltaCommandInfo[];
}

export interface SignatureArtifactSummary {
  magic: '0x72730147' | '0x72730137';
  profile?: SignatureProfile | string;
  block_len: string;
  strong_sum_len: string;
  record_count: string;
  signature_bytes: string;
}

export interface SignatureArtifactInspection {
  ok: true;
  artifact_kind: 'signature';
  summary: SignatureArtifactSummary;
}

export interface DeltaArtifactInspection {
  ok: true;
  artifact_kind: 'delta';
  summary: DeltaSummary;
}

export interface GzipArtifactInspection {
  ok: true;
  artifact_kind: 'gzip';
  compressed_bytes: string;
  uncompressed_bytes: string;
  uncompressed_sha256: string;
}

export interface DirBundleSummary {
  unchanged: string;
  add_full: string;
  update_delta: string;
  update_full: string;
  delete: string;
  copy_from_basis?: string;
  total_payload_bytes: string;
}

export interface BundleArchiveArtifactInspection {
  ok: true;
  artifact_kind: 'bundle-archive';
  archive_bytes: string;
  summary: DirBundleSummary;
}

export type SealKdfMode = 'raw-key' | 'argon2id';

export interface SealArtifactSummary {
  kdf_mode: number;
  kdf_name: SealKdfMode;
  chunk_size: number;
  argon2_memory_kib: number;
  argon2_passes: number;
  argon2_lanes: number;
  salt_hex: string;
  nonce_prefix_hex: string;
  byte_length: string | number;
  header_hex: string;
}

export interface SealArtifactInspection {
  ok: true;
  artifact_kind: 'seal-archive';
  artifact_type: 'seal-archive';
  kdf_mode: number;
  kdf_name: SealKdfMode;
  chunk_size: number;
  argon2_memory_kib: number;
  argon2_passes: number;
  argon2_lanes: number;
  salt_hex: string;
  nonce_prefix_hex: string;
  byte_length: number;
  header_hex: string;
  summary?: SealArtifactSummary;
}

export interface PublisherSignatureSummary {
  algorithm: 'ed25519';
  key_id: string;
  public_key: string;
  payload_length: string;
  payload_sha256: string;
  signature: string;
}

export interface PublisherSignatureInspection {
  ok: true;
  artifact_kind: 'publisher-signature';
  artifact_type: 'publisher-signature';
  schema_version?: 1;
  algorithm: 'ed25519';
  key_id: string;
  public_key: string;
  payload_length: string;
  payload_sha256: string;
  signature: string;
  summary?: PublisherSignatureSummary;
}

export interface TransferDeltaArtifactInspection {
  ok: true;
  artifact_kind: 'librsync-delta';
  schema_version: 2;
  summary: {
    mode: 'delta';
    basis_bytes: string;
    signature_bytes: string;
    payload_bytes: string;
    result_bytes: string;
    result_sha256: string;
  };
}

export interface TransferFullArtifactInspection {
  ok: true;
  artifact_kind: 'full-file';
  schema_version: 2;
  summary: {
    mode: 'full';
    payload_bytes: string;
    result_bytes: string;
    result_sha256: string;
  };
}

export interface UpdateManifestArtifactInspection {
  ok: true;
  artifact_kind: 'librsync-delta';
  schema_version: 1;
  summary: {
    basis_bytes: string;
    signature_bytes: string;
    delta_bytes: string;
    result_bytes: string;
    result_sha256: string;
  };
}

export interface BasisInfoArtifactInspection {
  ok: true;
  artifact_kind: 'moonlibsync-basis-info';
  schema_version: 1;
  summary: {
    basis_bytes: string;
    basis_sha256: string;
    signature_bytes: string;
    signature_sha256: string;
  };
}

export interface DirSnapshotArtifactInspection {
  ok: true;
  artifact_kind: 'moonlibsync-dir-snapshot';
  schema_version: 3;
  summary: {
    entries: string;
    total_bytes: string;
  };
}

export interface DirPlanArtifactInspection {
  ok: true;
  artifact_kind: 'moonlibsync-dir-plan';
  schema_version: 3;
  summary: DirSyncPlanSummary;
}

export interface DirSignaturesArtifactInspection {
  ok: true;
  artifact_kind: 'moonlibsync-dir-signatures';
  schema_version: 3;
  summary: {
    entries: string;
    total_basis_bytes: string;
    total_signature_bytes: string;
  };
}

export interface DirBundleArtifactInspection {
  ok: true;
  artifact_kind: 'moonlibsync-dir-bundle';
  schema_version: 3;
  summary: DirBundleSummary;
}

export interface DirVerifyArtifactInspection {
  ok: true;
  artifact_kind: 'moonlibsync-dir-verify';
  schema_version: 3;
  summary: {
    ok: boolean;
    matched: string;
    modified: string;
    missing: string;
    extra: string;
  };
}

export interface ZlibArtifactInspection {
  ok: true;
  artifact_kind: 'zlib';
  compressed_bytes: string;
  uncompressed_bytes: string;
  uncompressed_sha256: string;
}

export interface EnvelopeArtifactSummary {
  magic: 'MLSENC02';
  version: 2;
  recipient_count: number;
  recipient_key_ids: string[];
  chunk_size: number;
  nonce_prefix_hex: string;
  ephemeral_public_key_hex: string;
  byte_length: string;
}

export interface EnvelopeArchiveArtifactInspection {
  ok: true;
  artifact_kind: 'envelope-archive';
  byte_length: string;
  summary: EnvelopeArtifactSummary;
}

export interface DirMetadataArtifactInspection {
  ok: true;
  artifact_kind: 'moonlibsync-dir-metadata';
  schema_version: 3;
  summary: {
    executable_count: number;
    empty_dir_count: number;
    executable_paths: string[];
    empty_dirs: string[];
  };
}

export interface RangePlanArtifactInspection {
  ok: true;
  artifact_kind: 'moonlibsync-range-plan';
  schema_version: 3;
  summary: {
    target_length: string;
    block_len: string;
    profile: SignatureProfile;
    reused_bytes: string;
    fetch_bytes: string;
    request_bytes: string;
    range_count: number;
  };
}

export interface TrustKeyringArtifactInspection {
  ok: true;
  artifact_kind: 'moonlibsync-keyring';
  schema_version: 4;
  summary: {
    trusted_count: number;
    revoked_count: number;
    min_quorum: number;
    key_ids: string[];
    revoked_key_ids: string[];
  };
}

export interface SignatureBundleArtifactInspection {
  ok: true;
  artifact_kind: 'moonlibsync-signature-bundle';
  schema_version: 4;
  summary: {
    signature_count: number;
    signer_key_ids: string[];
    payload_length: string;
    payload_sha256: string;
  };
}

export type ArtifactInspection =
  | SignatureArtifactInspection
  | DeltaArtifactInspection
  | GzipArtifactInspection
  | ZlibArtifactInspection
  | BundleArchiveArtifactInspection
  | SealArtifactInspection
  | EnvelopeArchiveArtifactInspection
  | PublisherSignatureInspection
  | TrustKeyringArtifactInspection
  | SignatureBundleArtifactInspection
  | TransferDeltaArtifactInspection
  | TransferFullArtifactInspection
  | UpdateManifestArtifactInspection
  | BasisInfoArtifactInspection
  | DirSnapshotArtifactInspection
  | DirPlanArtifactInspection
  | DirSignaturesArtifactInspection
  | DirBundleArtifactInspection
  | DirVerifyArtifactInspection
  | DirMetadataArtifactInspection
  | RangePlanArtifactInspection;

export type BlockBenchmarkLabel = 'auto' | '256' | '512' | '2048' | '4096';

export interface BlockBenchmarkRow {
  label: BlockBenchmarkLabel;
  block_len: string;
  signature_bytes: string;
  delta_bytes: string;
  gzip_delta_bytes: string;
  copy_bytes: string;
  literal_bytes: string;
  instruction_count: string;
}

export interface BlockBenchmarkReport {
  ok: true;
  old_bytes: string;
  new_bytes: string;
  results: BlockBenchmarkRow[];
}

export interface DirEntryInput {
  path: string;
  byte_length: string | number | bigint;
  sha256: string;
}

export interface DirEntry {
  path: string;
  byte_length: string;
  sha256: string;
}

export interface DirSnapshot {
  schema_version: 3;
  kind: 'moonlibsync-dir-snapshot';
  entries: DirEntry[];
}

export type DirActionKind =
  | 'unchanged'
  | 'add-full'
  | 'update-candidate'
  | 'delete'
  | 'copy-from-basis';

export type DirSyncAction =
  | {
      path: string;
      kind: 'unchanged';
      basis: FileDigest;
      target: FileDigest;
    }
  | {
      path: string;
      kind: 'add-full';
      target: FileDigest;
    }
  | {
      path: string;
      kind: 'update-candidate';
      basis: FileDigest;
      target: FileDigest;
    }
  | {
      path: string;
      kind: 'delete';
      basis: FileDigest;
    }
  | {
      path: string;
      kind: 'copy-from-basis';
      source_path: string;
      target: FileDigest;
    };

export interface DirSyncPlanSummary {
  unchanged: string;
  add: string;
  update: string;
  delete: string;
  copy_from_basis?: string;
  transfer_upper_bound_bytes: string;
}

export interface DirSyncPlan {
  schema_version: 3;
  kind: 'moonlibsync-dir-plan';
  summary: DirSyncPlanSummary;
  actions: DirSyncAction[];
}

export type DirBundleActionKind =
  | 'unchanged'
  | 'add-full'
  | 'update-delta'
  | 'update-full'
  | 'delete'
  | 'copy-from-basis'
  | 'update-delta-from';

export type DirBundleAction =
  | {
      path: string;
      kind: 'unchanged';
      basis: FileDigest;
    }
  | {
      path: string;
      kind: 'add-full';
      payload_path: string;
      target: FileDigest;
    }
  | {
      path: string;
      kind: 'update-delta';
      payload_path: string;
      basis: FileDigest;
      signature: FileDigest;
      delta: FileDigest;
      result: FileDigest;
    }
  | {
      path: string;
      kind: 'update-full';
      payload_path: string;
      basis: FileDigest;
      target: FileDigest;
    }
  | {
      path: string;
      kind: 'delete';
      basis: FileDigest;
    }
  | {
      path: string;
      kind: 'copy-from-basis';
      source_path: string;
      target: FileDigest;
    }
  | {
      path: string;
      kind: 'update-delta-from';
      source_path: string;
      payload_path: string;
      basis: FileDigest;
      signature: FileDigest;
      delta: FileDigest;
      result: FileDigest;
    };

export type DirBundleEntry = DirBundleAction;

export interface DirBundleManifest {
  schema_version: 3;
  kind: 'moonlibsync-dir-bundle';
  summary: DirBundleSummary;
  entries: DirBundleAction[];
}

export interface DirFileInput {
  path: string;
  bytes: Uint8Array;
}

export interface PackedBundleArchive {
  gzip: boolean;
  rawBytes: number;
  archiveBytes: number;
  archive: Uint8Array;
  manifest: DirBundleManifest;
  summary: DirBundleSummary;
}

export interface UnpackedBundleFile {
  path: string;
  byteLength: number;
  sha256: string;
  bytes: Uint8Array;
}

export interface UnpackedBundleArchive {
  wasGzip: boolean;
  fileCount: number;
  manifest: DirBundleManifest;
  files: UnpackedBundleFile[];
}

export type DirVerifyDiffKind = 'modified' | 'missing' | 'extra';

export type DirVerifyIssue =
  | {
      path: string;
      kind: 'modified';
      expected: FileDigest;
      actual: FileDigest;
    }
  | {
      path: string;
      kind: 'missing';
      expected: FileDigest;
    }
  | {
      path: string;
      kind: 'extra';
      actual: FileDigest;
    };

export interface DirVerifySummary {
  matched: string;
  modified: string;
  missing: string;
  extra: string;
}

export interface DirVerifyReport {
  schema_version: 3;
  kind: 'moonlibsync-dir-verify';
  ok: boolean;
  summary: DirVerifySummary;
  issues: DirVerifyIssue[];
}

export interface Ed25519Keypair {
  seedHex: string;
  publicKeyHex: string;
  publicKey: Uint8Array;
  keyId: string;
}

export interface PublisherSignature {
  schema_version?: 1;
  kind?: 'moonlibsync-signature';
  algorithm: 'ed25519';
  key_id: string;
  public_key: string;
  payload_length: string;
  payload_sha256: string;
  signature: string;
}

export interface Ed25519SignResult {
  signatureJson: string;
  signature: PublisherSignature;
}

export interface Ed25519VerifyResult {
  verified: true;
  keyId: string;
  publicKeyHex: string;
  payloadLength: number;
  payloadSha256: string;
}

export interface SealBaseOptions {
  /**
   * Optional 16-byte salt. Auto-generated via `globalThis.crypto.getRandomValues` when omitted.
   */
  salt16?: Uint8Array;
  /**
   * Optional 12-byte nonce prefix whose trailing 4 bytes must be `0x00, 0x00, 0x00, 0x00`.
   * Auto-generated via `globalThis.crypto.getRandomValues` (8 random bytes + 4 zero bytes) when omitted.
   */
  noncePrefix12?: Uint8Array;
  /**
   * AEAD chunk size in bytes (`1024..1048576`). Default: `65536`.
   */
  chunkSize?: number;
  /**
   * Argon2id memory cost in KiB (`64..65536` under default limits). Default: `16384`.
   */
  argon2MemoryKib?: number;
  /**
   * Argon2id pass count (`1..8` under default limits). Default: `2`.
   */
  argon2Passes?: number;
}

export interface SealKeySecret {
  /**
   * Raw 32-byte ChaCha20-Poly1305 encryption key (`kdf_mode = "raw-key"`).
   */
  key: Uint8Array;
  passphrase?: never;
}

export interface SealPassphraseSecret {
  /**
   * Passphrase string (UTF-8 encoded) or raw bytes derived via Argon2id (`kdf_mode = "argon2id"`).
   */
  passphrase: string | Uint8Array;
  key?: never;
}

export type SealInputOptions = SealBaseOptions & (SealKeySecret | SealPassphraseSecret);
export type UnsealInputOptions = SealKeySecret | SealPassphraseSecret;

export interface SealResult {
  kdfMode: SealKdfMode;
  plainBytes: number;
  cipherBytes: number;
  chunkSize: number;
  cipher: Uint8Array;
}

export interface UnsealResult {
  kdfMode: SealKdfMode;
  chunkSize: number;
  plainBytes: number;
  plainSha256: string;
  plain: Uint8Array;
}

export interface RangeFetchOptions {
  /**
   * Maximum byte gap between adjacent remote spans to coalesce into one HTTP Range. Default: `4096`.
   */
  mergeGapBytes?: number;
  /**
   * Maximum number of coalesced HTTP Range requests allowed (`1..65536`). Default: `256`.
   */
  maxRanges?: number;
}

export interface ByteRangeSpec {
  start: number;
  length: number;
  http_range: string;
}

export type RangePlanOpKind = 'copy_local' | 'fetch_remote';

export interface RangePlanOp {
  op: RangePlanOpKind;
  offset: number;
  length: number;
}

export interface RangeFetchPlan {
  schema: 3;
  kind: 'moonlibsync-range-plan';
  target_length: number;
  block_len: number;
  profile: SignatureProfile;
  reused_bytes: number;
  fetch_bytes: number;
  request_bytes: number;
  ranges: ByteRangeSpec[];
  ops: RangePlanOp[];
}

export interface RangeFetchApplyResult {
  restored: Uint8Array;
  restoredBytes: number;
  restoredSha256: string;
  reusedBytes: number;
  fetchBytes: number;
  requestBytes: number;
  rangeCount: number;
}

export interface ComposedDeltaResult {
  composed: Uint8Array;
  composedBytes: number;
  composedSha256: string;
  inputTotalBytes: number;
  instructionCount: number;
  copyCount: number;
  literalCount: number;
  copyBytes: number;
  literalBytes: number;
  outputBytes: number;
}

export interface CompressZlibOptions {
  /**
   * Maximum allowed input byte length (`0..2147483647`). Default: `67108864` (64 MiB).
   */
  maxInput?: number;
  /**
   * Maximum allowed compressed output byte length (`0..2147483647`). Default: `67108864` (64 MiB).
   */
  maxOutput?: number;
  /**
   * RFC 1950 zlib / DEFLATE compression level (`0..9`). Default: `6`.
   */
  level?: number;
}

export interface DecompressZlibOptions {
  /**
   * Maximum allowed compressed input byte length (`0..2147483647`). Default: `67108864` (64 MiB).
   */
  maxInput?: number;
  /**
   * Maximum allowed decompressed output byte length (`0..2147483647`). Default: `67108864` (64 MiB).
   */
  maxOutput?: number;
}

export interface ZlibDecompressOk {
  ok: true;
  data: Uint8Array;
  inputBytes: number;
  outputBytes: number;
  outputSha256: string;
}

export interface ZlibDecompressErr {
  ok: false;
  error: string;
}

export type ZlibDecompressResult = ZlibDecompressOk | ZlibDecompressErr;

export interface X25519KeyPair {
  secretKeyHex: string;
  publicKeyHex: string;
  secretKey: Uint8Array;
  publicKey: Uint8Array;
  keyId: string;
}

export interface SealEnvelopeOptions {
  /**
   * AEAD chunk size in bytes (`1024..1048576`). Default: `65536`.
   */
  chunkSize?: number;
  /**
   * Optional 32-byte (64 lowercase hex chars) ephemeral X25519 secret scalar.
   * Auto-generated via `globalThis.crypto.getRandomValues` when omitted.
   */
  ephemeralSecretHex?: string;
  /**
   * Optional 32-byte (64 lowercase hex chars) content encryption key (CEK).
   * Auto-generated via `globalThis.crypto.getRandomValues` when omitted.
   */
  contentKeyHex?: string;
  /**
   * Optional 4-byte (8 lowercase hex chars) `MLSENC02` nonce prefix.
   * Auto-generated via `globalThis.crypto.getRandomValues` when omitted.
   */
  noncePrefixHex?: string;
}

export interface SealEnvelopeResult {
  ciphertext: Uint8Array;
  ciphertextBytes: number;
  ciphertextSha256: string;
  recipientCount: number;
  recipientKeyIds: string[];
  ephemeralPublicKeyHex: string;
  chunkSize: number;
}

export interface UnsealEnvelopeResult {
  plaintext: Uint8Array;
  plaintextBytes: number;
  plaintextSha256: string;
  recipientCount: number;
  recipientKeyIds: string[];
  ephemeralPublicKeyHex: string;
}

export interface CreateTrustKeyringOptions {
  /**
   * Optional list of 16-hex revoked Ed25519 key IDs. Default: `[]`.
   */
  revokedKeyIds?: readonly string[];
  /**
   * Minimum number of distinct non-revoked trusted signers required (`1..activeCount`). Default: `1`.
   */
  minQuorum?: number;
}

export interface TrustKeyringDocument {
  schema: 4;
  kind: 'moonlibsync-keyring';
  min_quorum: number;
  trusted_keys_hex: string[];
  revoked_key_ids: string[];
}

export interface TrustKeyringResult {
  keyringJson: string;
  trustedCount: number;
  revokedCount: number;
  minQuorum: number;
  keyIds: string[];
}

export interface SignatureBundleEntry {
  algorithm: 'ed25519';
  key_id: string;
  public_key: string;
  payload_length: string;
  payload_sha256: string;
  signature: string;
}

export interface SignatureBundle {
  schema: 4;
  kind: 'moonlibsync-signature-bundle';
  payload_length: string;
  payload_sha256: string;
  signatures: SignatureBundleEntry[];
}

export type QuorumSignatureInput =
  | string
  | readonly (string | PublisherSignature | SignatureBundleEntry | Record<string, unknown>)[];

export interface QuorumVerifyResult {
  bundleJson: string;
  verifiedKeyIds: string[];
  rejectedKeyIds: string[];
  revokedHits: string[];
  requiredQuorum: number;
}

export class MoonLibSyncClient {
  readonly raw: Readonly<MoonLibSyncRawModule>;
  constructor(rawModule: MoonLibSyncRawModule);

  sha256Hex(data: Uint8Array): string;
  createSignature(oldBytes: Uint8Array, options?: SignatureOptions): Uint8Array;
  createSignatureWithProfile(
    oldBytes: Uint8Array,
    options?: SignatureOptions,
  ): Uint8Array;
  createDelta(sigBytes: Uint8Array, newBytes: Uint8Array): Uint8Array;
  createReverseDelta(
    oldBytes: Uint8Array,
    newBytes: Uint8Array,
    options?: ReverseDeltaOptions,
  ): Uint8Array;
  applyPatch(oldBytes: Uint8Array, deltaBytes: Uint8Array): Uint8Array;
  applyPatchOrGzip(
    oldBytes: Uint8Array,
    deltaOrGzBytes: Uint8Array,
    manifestJson?: PatchManifestInput,
  ): ApplyPatchOrGzipResult;
  runStreamingSync(
    oldBytes: Uint8Array,
    newBytes: Uint8Array,
    options?: StreamingSyncOptions,
  ): SyncResult;
  compressGzip(data: Uint8Array, options?: CompressGzipOptions): Uint8Array;
  decompressGzip(data: Uint8Array, options?: DecompressGzipOptions): Uint8Array;
  inspectDeltaDetailed(
    deltaBytes: Uint8Array,
    options?: InspectDeltaOptions,
  ): DeltaDetailedInspection;
  inspectArtifact(data: Uint8Array): ArtifactInspection;
  benchmarkBlockSizes(
    oldBytes: Uint8Array,
    newBytes: Uint8Array,
    options?: BenchmarkBlockSizesOptions,
  ): BlockBenchmarkReport;
  createDirSnapshot(
    entries: readonly DirEntryInput[] | string,
    options?: CreateDirSnapshotOptions,
  ): DirSnapshot;
  planDirSnapshots(
    basisSnapshot: DirSnapshot | string,
    targetSnapshot: DirSnapshot | string,
    options?: PlanDirSnapshotsOptions,
  ): DirSyncPlan;
  verifyDirSnapshots(
    expectedSnapshot: DirSnapshot | string,
    actualSnapshot: DirSnapshot | string,
  ): DirVerifyReport;
  packDirBundleArchive(
    basisFiles: readonly DirFileInput[],
    targetFiles: readonly DirFileInput[],
    options?: PackDirBundleOptions,
  ): PackedBundleArchive;
  unpackDirBundleArchive(
    basisFiles: readonly DirFileInput[],
    archive: Uint8Array,
  ): UnpackedBundleArchive;
  ed25519KeypairFromSeed(seed: Uint8Array): Ed25519Keypair;
  ed25519Sign(seed: Uint8Array, payload: Uint8Array): Ed25519SignResult;
  ed25519Verify(
    signatureJson: string | PublisherSignature,
    trustedPublicKeys: readonly (string | Uint8Array)[],
    payload: Uint8Array,
  ): Ed25519VerifyResult;
  seal(plain: Uint8Array, options: SealInputOptions): SealResult;
  unseal(cipher: Uint8Array, options: UnsealInputOptions): UnsealResult;
  planRangeFetch(
    targetSignature: Uint8Array,
    targetLength: number,
    basis: Uint8Array,
    options?: RangeFetchOptions,
  ): RangeFetchPlan;
  applyRangeFetch(
    targetSignature: Uint8Array,
    targetLength: number,
    basis: Uint8Array,
    fetchedSlices: readonly (Uint8Array | string)[],
    options?: RangeFetchOptions,
  ): RangeFetchApplyResult;
  composeDeltas(deltas: readonly (Uint8Array | string)[]): ComposedDeltaResult;
  compressZlib(input: Uint8Array, options?: CompressZlibOptions): Uint8Array;
  decompressZlib(
    input: Uint8Array,
    options?: DecompressZlibOptions,
  ): ZlibDecompressResult;
  x25519KeypairFromSecret(secretHex?: string): X25519KeyPair;
  sealEnvelope(
    plaintext: Uint8Array,
    recipientPublicKeysHex: readonly string[],
    options?: SealEnvelopeOptions,
  ): SealEnvelopeResult;
  unsealEnvelope(
    ciphertext: Uint8Array,
    recipientSecretHex: string,
  ): UnsealEnvelopeResult;
  createTrustKeyring(
    trustedPublicKeysHex: readonly string[],
    options?: CreateTrustKeyringOptions,
  ): TrustKeyringResult;
  verifyQuorum(
    signatures: QuorumSignatureInput,
    keyringJson: string,
    payload: Uint8Array,
  ): QuorumVerifyResult;
}

export function createClient(rawModule: MoonLibSyncRawModule): MoonLibSyncClient;

export function loadMoonLibSync(
  options?: LoadMoonLibSyncOptions,
): Promise<MoonLibSyncClient>;
