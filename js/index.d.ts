// SPDX-License-Identifier: LGPL-2.1-or-later

/**
 * Low-level synchronous 27-export contract of MoonLibSync's pure MoonBit JS core module.
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

export type ArtifactInspection =
  | SignatureArtifactInspection
  | DeltaArtifactInspection
  | GzipArtifactInspection
  | BundleArchiveArtifactInspection
  | SealArtifactInspection
  | PublisherSignatureInspection
  | TransferDeltaArtifactInspection
  | TransferFullArtifactInspection
  | UpdateManifestArtifactInspection
  | BasisInfoArtifactInspection
  | DirSnapshotArtifactInspection
  | DirPlanArtifactInspection
  | DirSignaturesArtifactInspection
  | DirBundleArtifactInspection
  | DirVerifyArtifactInspection;

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
}

export function createClient(rawModule: MoonLibSyncRawModule): MoonLibSyncClient;

export function loadMoonLibSync(
  options?: LoadMoonLibSyncOptions,
): Promise<MoonLibSyncClient>;
