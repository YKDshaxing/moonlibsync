// SPDX-License-Identifier: LGPL-2.1-or-later

const REQUIRED_EXPORTS = Object.freeze([
  'run_streaming_sync_json',
  'create_signature_bytes',
  'create_delta_bytes',
  'apply_patch_bytes',
  'sha256_hex_bytes',
  'compress_gzip_bytes',
  'decompress_gzip_bytes',
  'decompress_gzip_check_json',
  'create_dir_snapshot_json',
  'plan_dir_snapshots_json',
  'inspect_delta_detailed_json',
  'inspect_artifact_json',
  'benchmark_block_sizes_json',
  'verify_dir_snapshots_json',
  'filter_dir_entries_json',
  'apply_verified_patch_json',
  'apply_patch_or_gzip_bytes',
]);

const INT32_MIN = -2147483648;
const INT32_MAX = 2147483647;
const DEFAULT_MAX_GZIP_OUTPUT = 67108864;

/**
 * Structured error thrown by MoonLibSync SDK operations.
 * Carries a stable `.code` string (e.g. `"LimitExceeded"`, `"TrailingData"`,
 * `"InvalidOptions:strong_sum_len"`, `"BindingMismatch:delta_sha256"`).
 */
export class MoonLibSyncError extends Error {
  /**
   * @param {string} code
   * @param {string} [message]
   * @param {ErrorOptions} [options]
   */
  constructor(code, message, options) {
    const normalizedCode =
      typeof code === 'string' && code.length > 0 ? code : 'UnexpectedError';
    super(message || normalizedCode, options);
    this.name = 'MoonLibSyncError';
    this.code = normalizedCode;
  }
}

function assertBytes(value, name) {
  if (!(value instanceof Uint8Array)) {
    throw new MoonLibSyncError(
      `InvalidOptions:${name}`,
      `Expected Uint8Array for "${name}"`,
    );
  }
  // Normalize Node.js Buffer or Uint8Array subclasses to a zero-copy Uint8Array view.
  return value.constructor === Uint8Array
    ? value
    : new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
}

function assertInt32(value, name) {
  if (
    typeof value !== 'number' ||
    !Number.isInteger(value) ||
    value < INT32_MIN ||
    value > INT32_MAX
  ) {
    throw new MoonLibSyncError(
      `InvalidOptions:${name}`,
      `Expected 32-bit integer for "${name}"`,
    );
  }
  return value;
}

function assertOptionsObject(options) {
  if (options === undefined || options === null) {
    return {};
  }
  if (typeof options !== 'object' || Array.isArray(options)) {
    throw new MoonLibSyncError(
      'InvalidOptions:options',
      'Expected options to be an object',
    );
  }
  return options;
}

function hasGzipMagic(bytes) {
  return bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;
}

function parseJsonStrict(rawText, label) {
  if (typeof rawText !== 'string') {
    throw new MoonLibSyncError(
      'InvalidJson',
      `${label} did not return a JSON string`,
    );
  }
  try {
    return JSON.parse(rawText);
  } catch (cause) {
    throw new MoonLibSyncError(
      'InvalidJson',
      `${label} returned malformed JSON`,
      { cause },
    );
  }
}

function isErrorEnvelope(value) {
  return (
    value !== null &&
    typeof value === 'object' &&
    value.ok === false &&
    typeof value.error === 'string' &&
    !('schema_version' in value)
  );
}

function parseOkJson(rawText, label) {
  const parsed = parseJsonStrict(rawText, label);
  if (isErrorEnvelope(parsed)) {
    throw new MoonLibSyncError(parsed.error, `${label} failed: ${parsed.error}`);
  }
  if (!parsed || typeof parsed !== 'object' || parsed.ok !== true) {
    throw new MoonLibSyncError(
      'UnexpectedError',
      `${label} returned an unexpected payload`,
    );
  }
  return parsed;
}

function parseSchema3Json(rawText, expectedKind, label) {
  const parsed = parseJsonStrict(rawText, label);
  if (isErrorEnvelope(parsed)) {
    throw new MoonLibSyncError(parsed.error, `${label} failed: ${parsed.error}`);
  }
  if (
    !parsed ||
    typeof parsed !== 'object' ||
    parsed.schema_version !== 3 ||
    parsed.kind !== expectedKind
  ) {
    throw new MoonLibSyncError(
      'InvalidSchema',
      `${label} returned an unexpected Schema 3 payload`,
    );
  }
  return parsed;
}

function serializeSnapshotInput(snapshot, name) {
  if (typeof snapshot === 'string') {
    return snapshot;
  }
  if (snapshot !== null && typeof snapshot === 'object' && !Array.isArray(snapshot)) {
    return JSON.stringify(snapshot);
  }
  throw new MoonLibSyncError(
    `InvalidOptions:${name}`,
    `Expected DirSnapshot object or JSON string for "${name}"`,
  );
}

function serializeDirEntriesInput(entries) {
  if (typeof entries === 'string') {
    return entries;
  }
  if (!Array.isArray(entries)) {
    throw new MoonLibSyncError(
      'InvalidOptions:entries',
      'Expected an array of directory entries or a JSON string',
    );
  }
  const normalized = entries.map((entry) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      return entry;
    }
    const len = entry.byte_length;
    if (typeof len === 'number' || typeof len === 'bigint') {
      return { ...entry, byte_length: String(len) };
    }
    return entry;
  });
  return JSON.stringify(normalized);
}

function serializeManifestInput(manifestJson) {
  if (manifestJson === undefined || manifestJson === null || manifestJson === '') {
    return '';
  }
  if (typeof manifestJson === 'string') {
    return manifestJson;
  }
  if (typeof manifestJson === 'object' && !Array.isArray(manifestJson)) {
    return JSON.stringify(manifestJson);
  }
  throw new MoonLibSyncError(
    'InvalidOptions:manifestJson',
    'Expected manifest JSON string or manifest object',
  );
}

function getMissingExports(mod) {
  if (!mod || typeof mod !== 'object') {
    return [...REQUIRED_EXPORTS];
  }
  return REQUIRED_EXPORTS.filter((name) => typeof mod[name] !== 'function');
}

function isNodeRuntime() {
  return (
    typeof process !== 'undefined' &&
    process !== null &&
    typeof process.versions === 'object' &&
    process.versions !== null &&
    typeof process.versions.node === 'string'
  );
}

function isUrlSpecifier(spec) {
  return /^[a-zA-Z][a-zA-Z\d+\-.]+:/.test(spec);
}

function isAbsoluteFsPath(spec) {
  return spec.startsWith('/') || /^[a-zA-Z]:[\\/]/.test(spec);
}

async function resolveSpecifierCandidates(modulePath) {
  if (modulePath instanceof URL) {
    return [modulePath.href];
  }
  if (typeof modulePath !== 'string' || modulePath.trim().length === 0) {
    throw new MoonLibSyncError(
      'InvalidOptions:modulePath',
      'Expected non-empty string or URL for "modulePath"',
    );
  }
  if (isUrlSpecifier(modulePath)) {
    return [modulePath];
  }
  if (isNodeRuntime()) {
    const [{ pathToFileURL }, pathMod] = await Promise.all([
      import('node:url'),
      import('node:path'),
    ]);
    if (isAbsoluteFsPath(modulePath)) {
      return [pathToFileURL(modulePath).href];
    }
    const urls = [];
    if (modulePath.startsWith('./') || modulePath.startsWith('../')) {
      urls.push(new URL(modulePath, import.meta.url).href);
    }
    urls.push(pathToFileURL(pathMod.resolve(modulePath)).href);
    return urls;
  }
  return [new URL(modulePath, import.meta.url).href];
}

async function buildDirCandidates(buildDir) {
  const relSuffixes = [
    ['js', 'release', 'build', 'examples', 'web-demo', 'web-demo.js'],
    ['js', 'debug', 'build', 'examples', 'web-demo', 'web-demo.js'],
    [
      'js',
      'release',
      'build',
      'YKDshaxing',
      'moonlibsync',
      'examples',
      'web-demo',
      'web-demo.js',
    ],
    [
      'js',
      'debug',
      'build',
      'YKDshaxing',
      'moonlibsync',
      'examples',
      'web-demo',
      'web-demo.js',
    ],
  ];

  if (isNodeRuntime()) {
    const [{ fileURLToPath, pathToFileURL }, pathMod] = await Promise.all([
      import('node:url'),
      import('node:path'),
    ]);
    const sdkDir = pathMod.dirname(fileURLToPath(import.meta.url));
    const repoRoot = pathMod.resolve(sdkDir, '..');
    const resolvedBase = pathMod.resolve(repoRoot, buildDir);
    return relSuffixes.map(
      (parts) => pathToFileURL(pathMod.join(resolvedBase, ...parts)).href,
    );
  }

  const cleanDir = buildDir.replaceAll('\\', '/').replace(/^\/+|\/+$/g, '');
  return relSuffixes.map(
    (parts) => new URL(`../${cleanDir}/${parts.join('/')}`, import.meta.url).href,
  );
}

/**
 * Strongly-typed ES Module client wrapping MoonLibSync's pure MoonBit JS core.
 */
export class MoonLibSyncClient {
  /**
   * @param {Record<string, Function>} rawModule
   */
  constructor(rawModule) {
    const missing = getMissingExports(rawModule);
    if (missing.length > 0) {
      throw new MoonLibSyncError(
        'InvalidModule',
        `MoonLibSync core module is missing required export(s): ${missing.join(', ')}`,
      );
    }
    this.raw = Object.freeze({ ...rawModule });
  }

  /**
   * Compute lowercase hex SHA-256 using MoonLibSync's bounded streaming hasher.
   * @param {Uint8Array} data
   * @returns {string}
   */
  sha256Hex(data) {
    const bytes = assertBytes(data, 'data');
    const hex = this.raw.sha256_hex_bytes(bytes);
    if (typeof hex !== 'string' || hex.length !== 64) {
      throw new MoonLibSyncError(
        'LimitExceeded',
        'Failed to compute SHA-256 digest (input exceeded limits)',
      );
    }
    return hex;
  }

  /**
   * Generate standard librsync 0x72730147 signature bytes (`blockLen = 0` selects auto).
   * @param {Uint8Array} oldBytes
   * @param {{ blockLen?: number, strongSumLen?: number }} [options]
   * @returns {Uint8Array}
   */
  createSignature(oldBytes, options = {}) {
    const basis = assertBytes(oldBytes, 'oldBytes');
    const opts = assertOptionsObject(options);
    const blockLen = assertInt32(opts.blockLen ?? 0, 'block_len');
    const strongSumLen = assertInt32(opts.strongSumLen ?? 32, 'strong_sum_len');
    if (blockLen < 0) {
      throw new MoonLibSyncError(
        'InvalidOptions:block_len',
        'blockLen must be 0 (auto) or a positive 32-bit integer',
      );
    }
    if (strongSumLen < 1 || strongSumLen > 32) {
      throw new MoonLibSyncError(
        'InvalidOptions:strong_sum_len',
        'strongSumLen must be an integer between 1 and 32',
      );
    }
    const sig = this.raw.create_signature_bytes(basis, blockLen, strongSumLen);
    if (!(sig instanceof Uint8Array) || sig.length === 0) {
      throw new MoonLibSyncError(
        'LimitExceeded',
        'Failed to create signature (invalid options or limit exceeded)',
      );
    }
    return sig;
  }

  /**
   * Generate standard librsync 0x72730236 delta bytes from signature and new target bytes.
   * @param {Uint8Array} sigBytes
   * @param {Uint8Array} newBytes
   * @returns {Uint8Array}
   */
  createDelta(sigBytes, newBytes) {
    const sig = assertBytes(sigBytes, 'sigBytes');
    const target = assertBytes(newBytes, 'newBytes');
    const delta = this.raw.create_delta_bytes(sig, target);
    if (!(delta instanceof Uint8Array) || delta.length === 0) {
      const probe = parseJsonStrict(
        this.raw.inspect_artifact_json(sig),
        'inspect_artifact_json',
      );
      if (isErrorEnvelope(probe)) {
        const code =
          probe.error === 'UnsupportedArtifact' ? 'InvalidSignature' : probe.error;
        throw new MoonLibSyncError(code, `Failed to create delta: ${code}`);
      }
      if (probe.artifact_kind !== 'signature') {
        throw new MoonLibSyncError(
          'InvalidSignature',
          `Expected signature artifact, received "${probe.artifact_kind}"`,
        );
      }
      throw new MoonLibSyncError(
        'LimitExceeded',
        'Failed to create delta (input or output exceeded limits)',
      );
    }
    return delta;
  }

  /**
   * Apply a raw standard librsync 0x72730236 delta to basis bytes.
   * @param {Uint8Array} oldBytes
   * @param {Uint8Array} deltaBytes
   * @returns {Uint8Array}
   */
  applyPatch(oldBytes, deltaBytes) {
    const basis = assertBytes(oldBytes, 'oldBytes');
    const delta = assertBytes(deltaBytes, 'deltaBytes');
    if (hasGzipMagic(delta)) {
      throw new MoonLibSyncError(
        'InvalidDelta',
        'Delta appears to be Gzip-compressed; use applyPatchOrGzip() instead',
      );
    }
    const restored = this.raw.apply_patch_bytes(basis, delta);
    if (!(restored instanceof Uint8Array)) {
      throw new MoonLibSyncError('UnexpectedError', 'apply_patch_bytes did not return Uint8Array');
    }
    if (restored.length === 0) {
      // Distinguish a legitimate 0-byte patched result from a patch failure.
      parseOkJson(
        this.raw.apply_verified_patch_json(basis, delta, ''),
        'apply_verified_patch_json',
      );
    }
    return restored;
  }

  /**
   * Apply a raw delta or RFC 1952 Gzip-wrapped delta with optional Schema 1/2 manifest verification.
   * @param {Uint8Array} oldBytes
   * @param {Uint8Array} deltaOrGzBytes
   * @param {string | Record<string, unknown>} [manifestJson='']
   * @returns {{ bytes: Uint8Array, sha256: string, decompressedGzip: boolean, verifiedManifest: boolean }}
   */
  applyPatchOrGzip(oldBytes, deltaOrGzBytes, manifestJson = '') {
    const basis = assertBytes(oldBytes, 'oldBytes');
    const payload = assertBytes(deltaOrGzBytes, 'deltaOrGzBytes');
    const manifestText = serializeManifestInput(manifestJson);

    const check = parseOkJson(
      this.raw.apply_verified_patch_json(basis, payload, manifestText),
      'apply_verified_patch_json',
    );

    const expectedLen = Number(check.output_bytes);
    let bytes;
    if (check.output_bytes === '0') {
      bytes = new Uint8Array(0);
    } else {
      bytes = this.raw.apply_patch_or_gzip_bytes(basis, payload);
      const patchMatches =
        bytes instanceof Uint8Array &&
        String(bytes.length) === check.output_bytes &&
        (!check.verified_manifest || this.raw.sha256_hex_bytes(bytes) === check.sha256);
      if (!patchMatches && check.verified_manifest === true) {
        // Schema 2 full-file TransferManifest: payload itself (after optional gzip) is the verified file.
        bytes = check.decompressed_gzip
          ? this.raw.decompress_gzip_bytes(payload, expectedLen)
          : payload.slice();
      }
      if (
        !(bytes instanceof Uint8Array) ||
        String(bytes.length) !== check.output_bytes ||
        (check.verified_manifest && this.raw.sha256_hex_bytes(bytes) !== check.sha256)
      ) {
        throw new MoonLibSyncError(
          'UnexpectedError',
          `Patched byte length or digest mismatch: expected ${check.output_bytes} bytes`,
        );
      }
    }

    return {
      bytes,
      sha256: check.sha256,
      decompressedGzip: Boolean(check.decompressed_gzip),
      verifiedManifest: Boolean(check.verified_manifest),
    };
  }

  /**
   * Run the full chunked streaming signature -> delta -> gzip -> patch -> SHA-256 pipeline.
   * @param {Uint8Array} oldBytes
   * @param {Uint8Array} newBytes
   * @param {{ blockLen?: number, strongSumLen?: number, chunkSize?: number }} [options]
   */
  runStreamingSync(oldBytes, newBytes, options = {}) {
    const basis = assertBytes(oldBytes, 'oldBytes');
    const target = assertBytes(newBytes, 'newBytes');
    const opts = assertOptionsObject(options);
    const blockLen = assertInt32(opts.blockLen ?? 0, 'block_len');
    const strongSumLen = assertInt32(opts.strongSumLen ?? 16, 'strong_sum_len');
    const chunkSize = assertInt32(opts.chunkSize ?? 4096, 'chunk_size');
    return parseOkJson(
      this.raw.run_streaming_sync_json(basis, target, blockLen, strongSumLen, chunkSize),
      'run_streaming_sync_json',
    );
  }

  /**
   * Compress bytes into a single-member RFC 1952 Gzip frame (`level` 0..=9).
   * @param {Uint8Array} data
   * @param {{ level?: number }} [options]
   * @returns {Uint8Array}
   */
  compressGzip(data, options = {}) {
    const bytes = assertBytes(data, 'data');
    const opts = assertOptionsObject(options);
    const level = assertInt32(opts.level ?? 6, 'level');
    if (level < 0 || level > 9) {
      throw new MoonLibSyncError(
        'InvalidOptions:level',
        'Gzip compression level must be an integer between 0 and 9',
      );
    }
    const out = this.raw.compress_gzip_bytes(bytes, level);
    if (!(out instanceof Uint8Array) || out.length === 0) {
      throw new MoonLibSyncError(
        'LimitExceeded',
        'Failed to compress Gzip payload (input or output exceeded limits)',
      );
    }
    return out;
  }

  /**
   * Decompress a bounded single-member RFC 1952 Gzip frame.
   * Rejects zip bombs (`LimitExceeded`), trailing bytes (`TrailingData`), and truncated frames (`TruncatedInput`).
   * @param {Uint8Array} data
   * @param {{ maxOutput?: number }} [options]
   * @returns {Uint8Array}
   */
  decompressGzip(data, options = {}) {
    const bytes = assertBytes(data, 'data');
    const opts = assertOptionsObject(options);
    const maxOutput = assertInt32(opts.maxOutput ?? DEFAULT_MAX_GZIP_OUTPUT, 'max_output');
    const check = parseOkJson(
      this.raw.decompress_gzip_check_json(bytes, maxOutput),
      'decompress_gzip_check_json',
    );
    if (check.byte_length === '0') {
      return new Uint8Array(0);
    }
    const out = this.raw.decompress_gzip_bytes(bytes, maxOutput);
    if (!(out instanceof Uint8Array) || String(out.length) !== check.byte_length) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        `Decompressed byte length mismatch: expected ${check.byte_length}`,
      );
    }
    return out;
  }

  /**
   * Validate a standard 0x72730236 delta and inspect ordered COPY/Literal instructions.
   * @param {Uint8Array} deltaBytes
   * @param {{ maxItems?: number }} [options]
   */
  inspectDeltaDetailed(deltaBytes, options = {}) {
    const delta = assertBytes(deltaBytes, 'deltaBytes');
    const opts = assertOptionsObject(options);
    const maxItems = assertInt32(opts.maxItems ?? 512, 'max_items');
    if (maxItems < 1) {
      throw new MoonLibSyncError(
        'InvalidOptions:max_items',
        'maxItems must be a positive 32-bit integer',
      );
    }
    return parseOkJson(
      this.raw.inspect_delta_detailed_json(delta, maxItems),
      'inspect_delta_detailed_json',
    );
  }

  /**
   * Auto-detect and validate any MoonLibSync binary artifact or Schema 1/2/3 JSON document.
   * @param {Uint8Array} data
   */
  inspectArtifact(data) {
    const bytes = assertBytes(data, 'data');
    return parseOkJson(
      this.raw.inspect_artifact_json(bytes),
      'inspect_artifact_json',
    );
  }

  /**
   * Benchmark `[auto, 256, 512, 2048, 4096]` block sizes in pure MoonBit.
   * @param {Uint8Array} oldBytes
   * @param {Uint8Array} newBytes
   * @param {{ strongSumLen?: number }} [options]
   */
  benchmarkBlockSizes(oldBytes, newBytes, options = {}) {
    const basis = assertBytes(oldBytes, 'oldBytes');
    const target = assertBytes(newBytes, 'newBytes');
    const opts = assertOptionsObject(options);
    const strongSumLen = assertInt32(opts.strongSumLen ?? 16, 'strong_sum_len');
    return parseOkJson(
      this.raw.benchmark_block_sizes_json(basis, target, strongSumLen),
      'benchmark_block_sizes_json',
    );
  }

  /**
   * Validate, optionally filter with exclude globs, sort, and emit a canonical Schema 3 `DirSnapshot`.
   * @param {Array<{ path: string, byte_length: string | number | bigint, sha256: string }> | string} entries
   * @param {{ excludes?: string[] }} [options]
   */
  createDirSnapshot(entries, options = {}) {
    const entriesJson = serializeDirEntriesInput(entries);
    const opts = assertOptionsObject(options);
    const excludes = opts.excludes ?? [];
    if (!Array.isArray(excludes)) {
      throw new MoonLibSyncError(
        'InvalidOptions:excludes',
        'Expected excludes to be an array of pattern strings',
      );
    }
    const rawJson =
      excludes.length > 0
        ? this.raw.filter_dir_entries_json(entriesJson, JSON.stringify(excludes))
        : this.raw.create_dir_snapshot_json(entriesJson);
    return parseSchema3Json(
      rawJson,
      'moonlibsync-dir-snapshot',
      excludes.length > 0 ? 'filter_dir_entries_json' : 'create_dir_snapshot_json',
    );
  }

  /**
   * Compute a deterministic Schema 3 `DirSyncPlan` from two directory snapshots.
   * @param {Record<string, unknown> | string} basisSnapshot
   * @param {Record<string, unknown> | string} targetSnapshot
   */
  planDirSnapshots(basisSnapshot, targetSnapshot) {
    const basisJson = serializeSnapshotInput(basisSnapshot, 'basisSnapshot');
    const targetJson = serializeSnapshotInput(targetSnapshot, 'targetSnapshot');
    return parseSchema3Json(
      this.raw.plan_dir_snapshots_json(basisJson, targetJson),
      'moonlibsync-dir-plan',
      'plan_dir_snapshots_json',
    );
  }

  /**
   * Compare expected vs actual Schema 3 directory snapshots and return a `DirVerifyReport`.
   * Note: a valid verification diff returns `{ ok: false, issues: [...] }` rather than throwing.
   * @param {Record<string, unknown> | string} expectedSnapshot
   * @param {Record<string, unknown> | string} actualSnapshot
   */
  verifyDirSnapshots(expectedSnapshot, actualSnapshot) {
    const expectedJson = serializeSnapshotInput(expectedSnapshot, 'expectedSnapshot');
    const actualJson = serializeSnapshotInput(actualSnapshot, 'actualSnapshot');
    return parseSchema3Json(
      this.raw.verify_dir_snapshots_json(expectedJson, actualJson),
      'moonlibsync-dir-verify',
      'verify_dir_snapshots_json',
    );
  }
}

/**
 * Synchronously create a `MoonLibSyncClient` from an already-imported core module.
 * @param {Record<string, Function>} rawModule
 * @returns {MoonLibSyncClient}
 */
export function createClient(rawModule) {
  return new MoonLibSyncClient(rawModule);
}

/**
 * Dynamically locate and load MoonLibSync's compiled MoonBit JS module
 * in either Node.js or browser environments.
 * @param {{ modulePath?: string | URL }} [options]
 * @returns {Promise<MoonLibSyncClient>}
 */
export async function loadMoonLibSync(options = {}) {
  const opts = assertOptionsObject(options);
  const candidateUrls = [];
  const seen = new Set();
  const pushUnique = (urls) => {
    for (const url of urls) {
      if (!seen.has(url)) {
        seen.add(url);
        candidateUrls.push(url);
      }
    }
  };

  if (opts.modulePath !== undefined) {
    pushUnique(await resolveSpecifierCandidates(opts.modulePath));
  }

  pushUnique([new URL('./moonlibsync-core.js', import.meta.url).href]);

  const envBuildDir =
    typeof process !== 'undefined' &&
    process !== null &&
    typeof process.env === 'object' &&
    process.env !== null &&
    typeof process.env.MOONLIBSYNC_BUILD_DIR === 'string' &&
    process.env.MOONLIBSYNC_BUILD_DIR.trim().length > 0
      ? process.env.MOONLIBSYNC_BUILD_DIR.trim()
      : null;

  if (envBuildDir !== null) {
    pushUnique(await buildDirCandidates(envBuildDir));
  }
  pushUnique(await buildDirCandidates('_build'));

  const failures = [];
  for (const specifier of candidateUrls) {
    try {
      const mod = await import(specifier);
      const missing = getMissingExports(mod);
      if (missing.length === 0) {
        return createClient(mod);
      }
      failures.push(`incompatible module (missing ${missing.length} export(s): ${missing.slice(0, 3).join(', ')})`);
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      failures.push(reason);
    }
  }

  throw new MoonLibSyncError(
    'ModuleLoadError',
    `Unable to load MoonLibSync compiled JS core module after ${candidateUrls.length} candidate(s). Run "npm run build" in js/ or "moon build examples/web-demo --target js --release". Last error: ${failures[failures.length - 1] || 'unknown'}`,
  );
}
