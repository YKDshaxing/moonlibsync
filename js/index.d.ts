// SPDX-License-Identifier: LGPL-2.1-or-later

/**
 * Low-level synchronous export contract of MoonLibSync's pure MoonBit JS core module.
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
  create_delta_bytes(sigBytes: Uint8Array, newBytes: Uint8Array): Uint8Array;
  apply_patch_bytes(oldBytes: Uint8Array, deltaBytes: Uint8Array): Uint8Array;
  sha256_hex_bytes(data: Uint8Array): string;
  compress_gzip_bytes(data: Uint8Array, level: number): Uint8Array;
  decompress_gzip_bytes(data: Uint8Array, maxOutput: number): Uint8Array;
  decompress_gzip_check_json(data: Uint8Array, maxOutput: number): string;
  create_dir_snapshot_json(entriesJson: string): string;
  plan_dir_snapshots_json(basisJson: string, targetJson: string): string;
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

export interface SignatureOptions {
  /**
   * Fixed signature block length in bytes, or `0` for automatic recommendation. Default: `0`.
   */
  blockLen?: number;
  /**
   * BLAKE2b strong checksum length in bytes (`1..32`). Default: `32`.
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
  kind: DeltaInstructionKind;
  offset: string;
  length: string;
  output_offset: string;
}

export interface DeltaDetailedInspection {
  ok: true;
  summary: DeltaSummary;
  truncated: boolean;
  items: DeltaInstructionItem[];
}

export interface SignatureArtifactSummary {
  magic: '0x72730147';
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
  total_payload_bytes: string;
}

export interface BundleArchiveArtifactInspection {
  ok: true;
  artifact_kind: 'bundle-archive';
  archive_bytes: string;
  summary: DirBundleSummary;
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
  | 'delete';

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
    };

export interface DirSyncPlanSummary {
  unchanged: string;
  add: string;
  update: string;
  delete: string;
  transfer_upper_bound_bytes: string;
}

export interface DirSyncPlan {
  schema_version: 3;
  kind: 'moonlibsync-dir-plan';
  summary: DirSyncPlanSummary;
  actions: DirSyncAction[];
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

export class MoonLibSyncClient {
  readonly raw: Readonly<MoonLibSyncRawModule>;
  constructor(rawModule: MoonLibSyncRawModule);

  sha256Hex(data: Uint8Array): string;
  createSignature(oldBytes: Uint8Array, options?: SignatureOptions): Uint8Array;
  createDelta(sigBytes: Uint8Array, newBytes: Uint8Array): Uint8Array;
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
  ): DirSyncPlan;
  verifyDirSnapshots(
    expectedSnapshot: DirSnapshot | string,
    actualSnapshot: DirSnapshot | string,
  ): DirVerifyReport;
}

export function createClient(rawModule: MoonLibSyncRawModule): MoonLibSyncClient;

export function loadMoonLibSync(
  options?: LoadMoonLibSyncOptions,
): Promise<MoonLibSyncClient>;
