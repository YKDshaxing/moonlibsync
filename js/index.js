// SPDX-License-Identifier: LGPL-2.1-or-later

const REQUIRED_EXPORTS = Object.freeze([
  'run_streaming_sync_json',
  'create_signature_bytes',
  'create_signature_with_profile_bytes',
  'create_delta_bytes',
  'create_reverse_delta_bytes',
  'apply_patch_bytes',
  'sha256_hex_bytes',
  'compress_gzip_bytes',
  'decompress_gzip_bytes',
  'decompress_gzip_check_json',
  'create_dir_snapshot_json',
  'plan_dir_snapshots_json',
  'plan_dir_snapshots_with_options_json',
  'pack_dir_bundle_archive_json',
  'unpack_dir_bundle_archive_json',
  'inspect_delta_detailed_json',
  'inspect_artifact_json',
  'benchmark_block_sizes_json',
  'verify_dir_snapshots_json',
  'filter_dir_entries_json',
  'apply_verified_patch_json',
  'apply_patch_or_gzip_bytes',
  'ed25519_keypair_from_seed_json',
  'ed25519_sign_bytes_json',
  'ed25519_verify_bytes_json',
  'seal_bytes_json',
  'unseal_bytes_json',
  'plan_range_fetch_json',
  'apply_range_fetch_json',
  'compose_deltas_json',
  'compress_zlib_bytes',
  'decompress_zlib_check_json',
  'x25519_keypair_from_secret_json',
  'seal_envelope_json',
  'unseal_envelope_json',
  'create_trust_keyring_json',
  'verify_quorum_bytes_json',
]);

const INT32_MIN = -2147483648;
const INT32_MAX = 2147483647;
const DEFAULT_MAX_GZIP_OUTPUT = 67108864;
const DEFAULT_MAX_ZLIB_INPUT = 67108864;
const DEFAULT_MAX_ZLIB_OUTPUT = 67108864;
const DEFAULT_RANGE_MERGE_GAP_BYTES = 4096;
const DEFAULT_RANGE_MAX_RANGES = 256;
const MAX_RANGE_FETCH_RANGES = 65536;
const MIN_SEAL_CHUNK_SIZE = 1024;
const MAX_SEAL_CHUNK_SIZE = 1048576;
const MAX_ENVELOPE_RECIPIENTS = 64;
const DEFAULT_SEAL_CHUNK_SIZE = 65536;
const DEFAULT_ARGON2_MEMORY_KIB = 16384;
const DEFAULT_ARGON2_PASSES = 2;

const UTF8_ENCODER = new TextEncoder();
const HEX_LUT = Object.freeze(
  Array.from({ length: 256 }, (_, i) => i.toString(16).padStart(2, '0')),
);

/**
 * Structured error thrown by MoonLibSync SDK operations.
 * Carries a stable `.code` string (e.g. `"LimitExceeded"`, `"TrailingData"`,
 * `"InvalidOptions:strong_sum_len"`, `"BindingMismatch:delta_sha256"`,
 * `"UntrustedKey"`, `"DigestMismatch"`, `"InvalidSignature"`, `"AuthenticationFailed"`).
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

function assertBoolean(value, name) {
  if (typeof value !== 'boolean') {
    throw new MoonLibSyncError(
      `InvalidOptions:${name}`,
      `Expected boolean for "${name}"`,
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

function assertSignatureProfile(profile) {
  if (profile === undefined) {
    return 'rk-blake2';
  }
  if (profile !== 'rk-blake2' && profile !== 'rollsum-blake2') {
    throw new MoonLibSyncError(
      'InvalidOptions:profile',
      'Signature profile must be "rk-blake2" or "rollsum-blake2"',
    );
  }
  return profile;
}

function bytesToHex(bytes) {
  const parts = new Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    parts[i] = HEX_LUT[bytes[i]];
  }
  return parts.join('');
}

function hexNibble(code) {
  if (code >= 0x30 && code <= 0x39) return code - 0x30;
  if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
  if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10;
  return -1;
}

function hexToBytes(hex, label) {
  if (typeof hex !== 'string' || (hex.length & 1) !== 0) {
    throw new MoonLibSyncError(
      'InvalidHex',
      `Expected even-length hexadecimal string for "${label}"`,
    );
  }
  const out = new Uint8Array(hex.length >>> 1);
  for (let i = 0, j = 0; i < hex.length; i += 2, j++) {
    const hi = hexNibble(hex.charCodeAt(i));
    const lo = hexNibble(hex.charCodeAt(i + 1));
    if (hi < 0 || lo < 0) {
      throw new MoonLibSyncError(
        'InvalidHex',
        `Invalid hexadecimal character in "${label}"`,
      );
    }
    out[j] = (hi << 4) | lo;
  }
  return out;
}

function assertHexBytesString(value, name, expectedByteLen, lengthErrorCode) {
  if (typeof value !== 'string') {
    throw new MoonLibSyncError(
      `InvalidOptions:${name}`,
      `Expected hexadecimal string for "${name}"`,
    );
  }
  if ((value.length & 1) !== 0) {
    throw new MoonLibSyncError(
      'InvalidHex',
      `Expected even-length hexadecimal string for "${name}"`,
    );
  }
  for (let i = 0; i < value.length; i++) {
    if (hexNibble(value.charCodeAt(i)) < 0) {
      throw new MoonLibSyncError(
        'InvalidHex',
        `Invalid hexadecimal character in "${name}"`,
      );
    }
  }
  if (expectedByteLen !== undefined && value.length !== expectedByteLen * 2) {
    throw new MoonLibSyncError(
      lengthErrorCode || `InvalidOptions:${name}`,
      `Expected ${expectedByteLen}-byte (${expectedByteLen * 2}-hex-char) string for "${name}"`,
    );
  }
  return value.toLowerCase();
}

function assertNonNegInt32(value, name) {
  const n = assertInt32(value, name);
  if (n < 0) {
    throw new MoonLibSyncError(
      `InvalidOptions:${name}`,
      `Expected non-negative 32-bit integer for "${name}"`,
    );
  }
  return n;
}

function randomBytes(length) {
  const cryptoObj = globalThis.crypto;
  if (!cryptoObj || typeof cryptoObj.getRandomValues !== 'function') {
    throw new MoonLibSyncError(
      'CryptoUnavailable',
      'globalThis.crypto.getRandomValues is required to generate random cryptographic bytes',
    );
  }
  const out = new Uint8Array(length);
  cryptoObj.getRandomValues(out);
  return out;
}

function randomNonZeroBytes(length) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const out = randomBytes(length);
    for (let i = 0; i < out.length; i++) {
      if (out[i] !== 0) {
        return out;
      }
    }
  }
  throw new MoonLibSyncError(
    'CryptoUnavailable',
    'CSPRNG failed to produce non-zero key bytes',
  );
}

function generateNoncePrefix12() {
  const out = new Uint8Array(12);
  out.set(randomBytes(8), 0);
  // Last 4 bytes must be 0x00, 0x00, 0x00, 0x00 for the 32-bit big-endian chunk counter.
  out[8] = 0;
  out[9] = 0;
  out[10] = 0;
  out[11] = 0;
  return out;
}

function resolveSealSecret(options) {
  const opts = assertOptionsObject(options);
  const hasKey = opts.key !== undefined;
  const hasPassphrase = opts.passphrase !== undefined;
  if ((hasKey && hasPassphrase) || (!hasKey && !hasPassphrase)) {
    throw new MoonLibSyncError(
      'InvalidOptions:secret',
      'Specify exactly one of "key" (32-byte Uint8Array) or "passphrase" (string | Uint8Array)',
    );
  }
  if (hasKey) {
    return {
      secret: assertBytes(opts.key, 'key'),
      usePassphrase: false,
      opts,
    };
  }
  if (typeof opts.passphrase === 'string') {
    return {
      secret: UTF8_ENCODER.encode(opts.passphrase),
      usePassphrase: true,
      opts,
    };
  }
  if (opts.passphrase instanceof Uint8Array) {
    return {
      secret: assertBytes(opts.passphrase, 'passphrase'),
      usePassphrase: true,
      opts,
    };
  }
  throw new MoonLibSyncError(
    'InvalidOptions:passphrase',
    'Expected string or Uint8Array for "passphrase"',
  );
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

function errorEnvelopeMessage(parsed, label) {
  return typeof parsed.message === 'string' && parsed.message.length > 0
    ? parsed.message
    : `${label} failed: ${parsed.error}`;
}

function parseOkJson(rawText, label) {
  const parsed = parseJsonStrict(rawText, label);
  if (isErrorEnvelope(parsed)) {
    throw new MoonLibSyncError(parsed.error, errorEnvelopeMessage(parsed, label));
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
    throw new MoonLibSyncError(parsed.error, errorEnvelopeMessage(parsed, label));
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

function toSafeIntIfDecimal(value) {
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string' && /^(0|[1-9]\d*)$/.test(value)) {
    const n = Number(value);
    if (Number.isSafeInteger(n)) {
      return n;
    }
  }
  return value;
}

function normalizeArtifactInspection(parsed) {
  const kind =
    typeof parsed.artifact_kind === 'string'
      ? parsed.artifact_kind
      : typeof parsed.artifact_type === 'string'
        ? parsed.artifact_type
        : null;

  if (kind === 'seal-archive') {
    const src =
      parsed.summary &&
      typeof parsed.summary === 'object' &&
      !Array.isArray(parsed.summary)
        ? { ...parsed.summary, ...parsed }
        : { ...parsed };
    return {
      ...src,
      ok: true,
      artifact_kind: 'seal-archive',
      artifact_type: 'seal-archive',
      kdf_mode: toSafeIntIfDecimal(src.kdf_mode),
      chunk_size: toSafeIntIfDecimal(src.chunk_size),
      argon2_memory_kib: toSafeIntIfDecimal(src.argon2_memory_kib),
      argon2_passes: toSafeIntIfDecimal(src.argon2_passes),
      argon2_lanes: toSafeIntIfDecimal(src.argon2_lanes),
      byte_length: toSafeIntIfDecimal(src.byte_length),
    };
  }

  if (kind === 'publisher-signature') {
    const src =
      parsed.summary &&
      typeof parsed.summary === 'object' &&
      !Array.isArray(parsed.summary)
        ? { ...parsed.summary, ...parsed }
        : { ...parsed };
    return {
      ...src,
      ok: true,
      artifact_kind: 'publisher-signature',
      artifact_type: 'publisher-signature',
      payload_length:
        src.payload_length !== undefined
          ? String(src.payload_length)
          : src.payload_length,
    };
  }

  if (
    typeof parsed.artifact_kind !== 'string' &&
    typeof parsed.artifact_type === 'string'
  ) {
    return { ...parsed, artifact_kind: parsed.artifact_type };
  }

  return parsed;
}

function stringifyJsonStrict(value, name) {
  try {
    const text = JSON.stringify(value);
    if (typeof text !== 'string') {
      throw new TypeError(`Value for "${name}" is not JSON-serializable`);
    }
    return text;
  } catch (cause) {
    throw new MoonLibSyncError(
      `InvalidOptions:${name}`,
      `Failed to serialize "${name}" to JSON: ${cause instanceof Error ? cause.message : String(cause)}`,
      { cause },
    );
  }
}

function serializeSnapshotInput(snapshot, name) {
  if (typeof snapshot === 'string') {
    return snapshot;
  }
  if (snapshot !== null && typeof snapshot === 'object' && !Array.isArray(snapshot)) {
    return stringifyJsonStrict(snapshot, name);
  }
  throw new MoonLibSyncError(
    `InvalidOptions:${name}`,
    `Expected DirSnapshot object or JSON string for "${name}"`,
  );
}

function extractDirSnapshotEntriesJson(jsonText) {
  let obj;
  try {
    obj = JSON.parse(jsonText);
  } catch {
    return null;
  }
  if (
    obj === null ||
    typeof obj !== 'object' ||
    Array.isArray(obj) ||
    obj.schema_version !== 3 ||
    obj.kind !== 'moonlibsync-dir-snapshot' ||
    !Array.isArray(obj.entries) ||
    Object.keys(obj).length !== 3
  ) {
    return null;
  }
  return stringifyJsonStrict(obj.entries, 'entries');
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
  return stringifyJsonStrict(normalized, 'entries');
}

function serializeDirFilesInput(files, name) {
  if (!Array.isArray(files)) {
    throw new MoonLibSyncError(
      `InvalidOptions:${name}`,
      `Expected an array of { path, bytes } entries for "${name}"`,
    );
  }
  const out = new Array(files.length);
  for (let i = 0; i < files.length; i++) {
    const item = files[i];
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      throw new MoonLibSyncError(
        `InvalidOptions:${name}`,
        `Expected object { path, bytes } at ${name}[${i}]`,
      );
    }
    if (typeof item.path !== 'string') {
      throw new MoonLibSyncError(
        `InvalidOptions:${name}`,
        `Expected string "path" at ${name}[${i}]`,
      );
    }
    const bytes = assertBytes(item.bytes, `${name}[${i}].bytes`);
    out[i] = { path: item.path, content_hex: bytesToHex(bytes) };
  }
  return stringifyJsonStrict(out, name);
}

function serializeManifestInput(manifestJson) {
  if (manifestJson === undefined || manifestJson === null || manifestJson === '') {
    return '';
  }
  if (typeof manifestJson === 'string') {
    return manifestJson;
  }
  if (typeof manifestJson === 'object' && !Array.isArray(manifestJson)) {
    return stringifyJsonStrict(manifestJson, 'manifestJson');
  }
  throw new MoonLibSyncError(
    'InvalidOptions:manifestJson',
    'Expected manifest JSON string or manifest object',
  );
}

function serializeSignatureJsonInput(signatureJson) {
  if (typeof signatureJson === 'string') {
    return signatureJson;
  }
  if (
    signatureJson !== null &&
    typeof signatureJson === 'object' &&
    !Array.isArray(signatureJson)
  ) {
    return stringifyJsonStrict(signatureJson, 'signatureJson');
  }
  throw new MoonLibSyncError(
    'InvalidOptions:signatureJson',
    'Expected signature JSON string or PublisherSignature object',
  );
}

function serializeTrustedPublicKeys(trustedPublicKeys) {
  if (!Array.isArray(trustedPublicKeys)) {
    throw new MoonLibSyncError(
      'InvalidOptions:trustedPublicKeys',
      'Expected an array of hex public key strings or 32-byte Uint8Arrays',
    );
  }
  const normalized = new Array(trustedPublicKeys.length);
  for (let i = 0; i < trustedPublicKeys.length; i++) {
    const key = trustedPublicKeys[i];
    if (typeof key === 'string') {
      normalized[i] = key;
    } else if (key instanceof Uint8Array) {
      normalized[i] = bytesToHex(assertBytes(key, `trustedPublicKeys[${i}]`));
    } else {
      throw new MoonLibSyncError(
        'InvalidOptions:trustedPublicKeys',
        `Expected hex string or Uint8Array at trustedPublicKeys[${i}]`,
      );
    }
  }
  return stringifyJsonStrict(normalized, 'trustedPublicKeys');
}

function resolveRangeFetchOptions(options) {
  const opts = assertOptionsObject(options);
  const mergeGapBytes = assertNonNegInt32(
    opts.mergeGapBytes ?? DEFAULT_RANGE_MERGE_GAP_BYTES,
    'merge_gap_bytes',
  );
  const maxRanges = assertInt32(
    opts.maxRanges ?? DEFAULT_RANGE_MAX_RANGES,
    'max_ranges',
  );
  if (maxRanges < 1 || maxRanges > MAX_RANGE_FETCH_RANGES) {
    throw new MoonLibSyncError(
      'InvalidOptions:max_ranges',
      `maxRanges must be an integer between 1 and ${MAX_RANGE_FETCH_RANGES}`,
    );
  }
  return { mergeGapBytes, maxRanges };
}

function serializeBytesOrHexArray(items, name, allowEmpty) {
  if (!Array.isArray(items)) {
    throw new MoonLibSyncError(
      `InvalidOptions:${name}`,
      `Expected an array of Uint8Array or hex string items for "${name}"`,
    );
  }
  if (!allowEmpty && items.length === 0) {
    throw new MoonLibSyncError(
      `InvalidOptions:${name}`,
      `Expected a non-empty array for "${name}"`,
    );
  }
  const normalized = new Array(items.length);
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (item instanceof Uint8Array) {
      normalized[i] = bytesToHex(assertBytes(item, `${name}[${i}]`));
    } else if (typeof item === 'string') {
      normalized[i] = assertHexBytesString(item, `${name}[${i}]`).toLowerCase();
    } else {
      throw new MoonLibSyncError(
        `InvalidOptions:${name}`,
        `Expected Uint8Array or hex string at ${name}[${i}]`,
      );
    }
  }
  return stringifyJsonStrict(normalized, name);
}

function serializeHexStringArray(
  items,
  name,
  expectedByteLen,
  lengthErrorCode,
  minLen,
  maxLen,
  countErrorCode,
) {
  if (!Array.isArray(items)) {
    throw new MoonLibSyncError(
      countErrorCode || `InvalidOptions:${name}`,
      `Expected an array of hexadecimal strings for "${name}"`,
    );
  }
  if (items.length < minLen || (maxLen !== undefined && items.length > maxLen)) {
    const rangeDesc =
      maxLen !== undefined
        ? `between ${minLen} and ${maxLen}`
        : `at least ${minLen}`;
    throw new MoonLibSyncError(
      countErrorCode || `InvalidOptions:${name}`,
      `Expected ${rangeDesc} item(s) for "${name}"`,
    );
  }
  const normalized = new Array(items.length);
  for (let i = 0; i < items.length; i++) {
    normalized[i] = assertHexBytesString(
      items[i],
      `${name}[${i}]`,
      expectedByteLen,
      lengthErrorCode,
    );
  }
  return stringifyJsonStrict(normalized, name);
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function serializeQuorumSignatures(signatures) {
  if (typeof signatures === 'string') {
    if (signatures.trim().length === 0) {
      throw new MoonLibSyncError(
        'InvalidOptions:signatures',
        'Expected non-empty SignatureBundle JSON string or signatures array',
      );
    }
    return signatures;
  }
  if (!Array.isArray(signatures)) {
    throw new MoonLibSyncError(
      'InvalidOptions:signatures',
      'Expected a SignatureBundle JSON string or an array of publisher signatures',
    );
  }
  if (signatures.length === 0) {
    throw new MoonLibSyncError(
      'InvalidOptions:signature_count',
      'Expected a non-empty array of signatures',
    );
  }
  const normalized = new Array(signatures.length);
  for (let i = 0; i < signatures.length; i++) {
    const item = signatures[i];
    if (typeof item === 'string') {
      if (item.trim().length === 0) {
        throw new MoonLibSyncError(
          'InvalidOptions:signatures',
          `Expected non-empty signature string at signatures[${i}]`,
        );
      }
      normalized[i] = item;
    } else if (isPlainObject(item)) {
      normalized[i] = item;
    } else {
      throw new MoonLibSyncError(
        'InvalidOptions:signatures',
        `Expected signature JSON string or object at signatures[${i}]`,
      );
    }
  }
  return stringifyJsonStrict(normalized, 'signatures');
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
   * Generate standard librsync signature bytes (`blockLen = 0` selects auto).
   * Defaults to `rk-blake2` (`0x72730147`); pass `{ profile: 'rollsum-blake2' }`
   * for `RS_BLAKE2_SIG_MAGIC` (`0x72730137`).
   * @param {Uint8Array} oldBytes
   * @param {{ blockLen?: number, strongSumLen?: number, profile?: 'rk-blake2' | 'rollsum-blake2' }} [options]
   * @returns {Uint8Array}
   */
  createSignature(oldBytes, options = {}) {
    const basis = assertBytes(oldBytes, 'oldBytes');
    const opts = assertOptionsObject(options);
    const blockLen = assertInt32(opts.blockLen ?? 0, 'block_len');
    const strongSumLen = assertInt32(opts.strongSumLen ?? 32, 'strong_sum_len');
    const profile = assertSignatureProfile(opts.profile);
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
    const sig =
      profile === 'rollsum-blake2'
        ? this.raw.create_signature_with_profile_bytes(
            basis,
            blockLen,
            strongSumLen,
            profile,
          )
        : this.raw.create_signature_bytes(basis, blockLen, strongSumLen);
    if (!(sig instanceof Uint8Array) || sig.length === 0) {
      throw new MoonLibSyncError(
        'LimitExceeded',
        'Failed to create signature (invalid options or limit exceeded)',
      );
    }
    return sig;
  }

  /**
   * Explicitly generate librsync signature bytes with a chosen weak-sum profile
   * (`'rk-blake2'` = `0x72730147` or `'rollsum-blake2'` = `0x72730137`).
   * @param {Uint8Array} oldBytes
   * @param {{ blockLen?: number, strongSumLen?: number, profile?: 'rk-blake2' | 'rollsum-blake2' }} [options]
   * @returns {Uint8Array}
   */
  createSignatureWithProfile(oldBytes, options = {}) {
    const basis = assertBytes(oldBytes, 'oldBytes');
    const opts = assertOptionsObject(options);
    const blockLen = assertInt32(opts.blockLen ?? 0, 'block_len');
    const strongSumLen = assertInt32(opts.strongSumLen ?? 32, 'strong_sum_len');
    const profile = assertSignatureProfile(opts.profile);
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
    const sig = this.raw.create_signature_with_profile_bytes(
      basis,
      blockLen,
      strongSumLen,
      profile,
    );
    if (!(sig instanceof Uint8Array) || sig.length === 0) {
      throw new MoonLibSyncError(
        'LimitExceeded',
        'Failed to create signature with profile (invalid options or limit exceeded)',
      );
    }
    return sig;
  }

  /**
   * Generate standard librsync 0x72730236 delta bytes from signature (`0x72730147` or `0x72730137`)
   * and new target bytes.
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
      const detectedKind = probe.artifact_kind ?? probe.artifact_type ?? 'unknown';
      if (detectedKind !== 'signature') {
        throw new MoonLibSyncError(
          'InvalidSignature',
          `Expected signature artifact, received "${detectedKind}"`,
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
   * Generate a rollback delta (`NEW -> OLD`) that reverts `newBytes` back to `oldBytes`
   * when applied with `applyPatch(newBytes, reverseDelta)`.
   * @param {Uint8Array} oldBytes
   * @param {Uint8Array} newBytes
   * @param {{ blockLen?: number, strongSumLen?: number }} [options]
   * @returns {Uint8Array}
   */
  createReverseDelta(oldBytes, newBytes, options = {}) {
    const basis = assertBytes(oldBytes, 'oldBytes');
    const target = assertBytes(newBytes, 'newBytes');
    const opts = assertOptionsObject(options);
    const blockLen = assertInt32(opts.blockLen ?? 0, 'block_len');
    const strongSumLen = assertInt32(opts.strongSumLen ?? 16, 'strong_sum_len');
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
    const delta = this.raw.create_reverse_delta_bytes(
      basis,
      target,
      blockLen,
      strongSumLen,
    );
    if (!(delta instanceof Uint8Array) || delta.length === 0) {
      throw new MoonLibSyncError(
        'LimitExceeded',
        'Failed to create reverse delta (invalid options or limit exceeded)',
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
      throw new MoonLibSyncError(
        'UnexpectedError',
        'apply_patch_bytes did not return Uint8Array',
      );
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
      let isFullManifest = false;
      if (check.verified_manifest === true && manifestText.trim().length > 0) {
        try {
          const parsedManifest = JSON.parse(manifestText);
          if (
            parsedManifest !== null &&
            typeof parsedManifest === 'object' &&
            parsedManifest.schema_version === 2 &&
            parsedManifest.kind === 'full-file'
          ) {
            isFullManifest = true;
          }
        } catch {
          // Manifest was already parsed and verified by the MoonBit core.
        }
      }
      if (isFullManifest) {
        // Schema 2 full-file TransferManifest: payload itself (after optional gzip) is the verified file.
        bytes = check.decompressed_gzip
          ? this.raw.decompress_gzip_bytes(payload, expectedLen)
          : payload.slice();
      } else {
        bytes = this.raw.apply_patch_or_gzip_bytes(basis, payload);
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
   * Validate a standard 0x72730236 delta and inspect ordered COPY/Literal instructions
   * (including optional literal preview hex/UTF-8 metadata).
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
   * Auto-detect and validate any MoonLibSync binary artifact (`.sig`, `.delta`, `.gz`,
   * `.mbundle`, `.menc`) or Schema 1/2/3/4 JSON document (including publisher signatures).
   * @param {Uint8Array} data
   */
  inspectArtifact(data) {
    const bytes = assertBytes(data, 'data');
    const parsed = parseOkJson(
      this.raw.inspect_artifact_json(bytes),
      'inspect_artifact_json',
    );
    return normalizeArtifactInspection(parsed);
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
        ? this.raw.filter_dir_entries_json(
            entriesJson,
            stringifyJsonStrict(excludes, 'excludes'),
          )
        : this.raw.create_dir_snapshot_json(entriesJson);
    return parseSchema3Json(
      rawJson,
      'moonlibsync-dir-snapshot',
      excludes.length > 0 ? 'filter_dir_entries_json' : 'create_dir_snapshot_json',
    );
  }

  /**
   * Compute a deterministic Schema 3 `DirSyncPlan` from two directory snapshots.
   * Pass `{ detectMoves: true }` to emit 0-byte `copy-from-basis` actions for moved/renamed files.
   * @param {Record<string, unknown> | string} basisSnapshot
   * @param {Record<string, unknown> | string} targetSnapshot
   * @param {{ detectMoves?: boolean }} [options]
   */
  planDirSnapshots(basisSnapshot, targetSnapshot, options = {}) {
    const basisJson = serializeSnapshotInput(basisSnapshot, 'basisSnapshot');
    const targetJson = serializeSnapshotInput(targetSnapshot, 'targetSnapshot');
    const opts = assertOptionsObject(options);
    const detectMoves = assertBoolean(opts.detectMoves ?? false, 'detectMoves');

    if (!detectMoves) {
      return parseSchema3Json(
        this.raw.plan_dir_snapshots_json(basisJson, targetJson),
        'moonlibsync-dir-plan',
        'plan_dir_snapshots_json',
      );
    }

    const label = 'plan_dir_snapshots_with_options_json';
    let parsed = parseJsonStrict(
      this.raw.plan_dir_snapshots_with_options_json(basisJson, targetJson, true),
      label,
    );
    if (isErrorEnvelope(parsed) && parsed.error === 'InvalidSchema') {
      const basisEntries = extractDirSnapshotEntriesJson(basisJson);
      const targetEntries = extractDirSnapshotEntriesJson(targetJson);
      if (basisEntries !== null && targetEntries !== null) {
        parsed = parseJsonStrict(
          this.raw.plan_dir_snapshots_with_options_json(basisEntries, targetEntries, true),
          label,
        );
      }
    }
    if (isErrorEnvelope(parsed)) {
      throw new MoonLibSyncError(parsed.error, errorEnvelopeMessage(parsed, label));
    }
    if (
      parsed &&
      typeof parsed === 'object' &&
      parsed.ok === true &&
      parsed.plan &&
      typeof parsed.plan === 'object' &&
      parsed.plan.schema_version === 3 &&
      parsed.plan.kind === 'moonlibsync-dir-plan'
    ) {
      return parsed.plan;
    }
    if (parsed && typeof parsed === 'object' && parsed.ok === true && typeof parsed.plan_json === 'string') {
      return parseSchema3Json(parsed.plan_json, 'moonlibsync-dir-plan', label);
    }
    if (
      parsed &&
      typeof parsed === 'object' &&
      parsed.schema_version === 3 &&
      parsed.kind === 'moonlibsync-dir-plan'
    ) {
      return parsed;
    }
    throw new MoonLibSyncError(
      'InvalidSchema',
      `${label} returned an unexpected DirSyncPlan payload`,
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

  /**
   * Pack an in-memory directory diff into a deterministic `MLSBDL01` `.mbundle` (or `.mbundle.gz`)
   * archive with optional move/rename detection (`copy-from-basis` & `update-delta-from`).
   * @param {ReadonlyArray<{ path: string, bytes: Uint8Array }>} basisFiles
   * @param {ReadonlyArray<{ path: string, bytes: Uint8Array }>} targetFiles
   * @param {{ detectMoves?: boolean, gzip?: boolean }} [options]
   */
  packDirBundleArchive(basisFiles, targetFiles, options = {}) {
    const basisJson = serializeDirFilesInput(basisFiles, 'basisFiles');
    const targetJson = serializeDirFilesInput(targetFiles, 'targetFiles');
    const opts = assertOptionsObject(options);
    const detectMoves = assertBoolean(opts.detectMoves ?? false, 'detectMoves');
    const gzip = assertBoolean(opts.gzip ?? false, 'gzip');
    const res = parseOkJson(
      this.raw.pack_dir_bundle_archive_json(basisJson, targetJson, detectMoves, gzip),
      'pack_dir_bundle_archive_json',
    );
    const archive = hexToBytes(res.archive_hex, 'archive_hex');
    return {
      gzip: Boolean(res.gzip),
      rawBytes: Number(res.raw_bytes),
      archiveBytes: Number(res.archive_bytes),
      archive,
      manifest: res.manifest,
      summary: res.summary ?? (res.manifest ? res.manifest.summary : undefined),
    };
  }

  /**
   * Unpack and SHA-256-verify a `.mbundle` or `.mbundle.gz` archive against in-memory basis files.
   * @param {ReadonlyArray<{ path: string, bytes: Uint8Array }>} basisFiles
   * @param {Uint8Array} archive
   */
  unpackDirBundleArchive(basisFiles, archive) {
    const basisJson = serializeDirFilesInput(basisFiles, 'basisFiles');
    const archiveBytes = assertBytes(archive, 'archive');
    const res = parseOkJson(
      this.raw.unpack_dir_bundle_archive_json(basisJson, archiveBytes),
      'unpack_dir_bundle_archive_json',
    );
    if (!Array.isArray(res.files)) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        'unpack_dir_bundle_archive_json returned malformed files array',
      );
    }
    const files = res.files.map((item, idx) => ({
      path: String(item.path),
      byteLength: Number(item.byte_length),
      sha256: String(item.sha256),
      bytes: hexToBytes(item.content_hex, `files[${idx}].content_hex`),
    }));
    return {
      wasGzip: Boolean(res.was_gzip),
      fileCount: Number(res.file_count ?? files.length),
      manifest: res.manifest,
      files,
    };
  }

  /**
   * Derive an RFC 8032 Ed25519 key pair and 16-char SHA-256 key ID from a 32-byte seed.
   * @param {Uint8Array} seed
   */
  ed25519KeypairFromSeed(seed) {
    const seedBytes = assertBytes(seed, 'seed');
    const res = parseOkJson(
      this.raw.ed25519_keypair_from_seed_json(seedBytes),
      'ed25519_keypair_from_seed_json',
    );
    const publicKey = hexToBytes(res.public_key_hex, 'public_key_hex');
    return {
      seedHex: String(res.seed_hex),
      publicKeyHex: String(res.public_key_hex),
      publicKey,
      keyId: String(res.key_id),
    };
  }

  /**
   * Sign payload bytes with a 32-byte Ed25519 seed and emit a canonical Schema 4
   * `moonlibsync-signature` JSON document.
   * @param {Uint8Array} seed
   * @param {Uint8Array} payload
   */
  ed25519Sign(seed, payload) {
    const seedBytes = assertBytes(seed, 'seed');
    const payloadBytes = assertBytes(payload, 'payload');
    const res = parseOkJson(
      this.raw.ed25519_sign_bytes_json(seedBytes, payloadBytes),
      'ed25519_sign_bytes_json',
    );
    return {
      signatureJson: String(res.signature_json),
      signature: res.signature,
    };
  }

  /**
   * Verify a Schema 4 Ed25519 publisher signature against trusted public keys and payload bytes.
   * Throws `MoonLibSyncError` (e.g. `UntrustedKey`, `DigestMismatch`, `InvalidSignature`) on failure.
   * @param {string | Record<string, unknown>} signatureJson
   * @param {ReadonlyArray<string | Uint8Array>} trustedPublicKeys
   * @param {Uint8Array} payload
   */
  ed25519Verify(signatureJson, trustedPublicKeys, payload) {
    const sigText = serializeSignatureJsonInput(signatureJson);
    const keysJson = serializeTrustedPublicKeys(trustedPublicKeys);
    const payloadBytes = assertBytes(payload, 'payload');
    const res = parseOkJson(
      this.raw.ed25519_verify_bytes_json(sigText, keysJson, payloadBytes),
      'ed25519_verify_bytes_json',
    );
    if (res.verified !== true) {
      throw new MoonLibSyncError(
        'InvalidSignature',
        'Ed25519 signature verification failed',
      );
    }
    return {
      verified: true,
      keyId: String(res.key_id),
      publicKeyHex: String(res.public_key),
      payloadLength: Number(res.payload_length),
      payloadSha256: String(res.payload_sha256),
    };
  }

  /**
   * Encrypt and authenticate bytes into an `MLSENC01` ChaCha20-Poly1305 chunked container
   * using either a raw 32-byte key (`{ key }`) or an Argon2id-derived passphrase (`{ passphrase }`).
   * Auto-generates CSPRNG `salt16` and `noncePrefix12` (with trailing `0x00,0x00,0x00,0x00`) when omitted.
   * @param {Uint8Array} plain
   * @param {{ key?: Uint8Array, passphrase?: string | Uint8Array, salt16?: Uint8Array, noncePrefix12?: Uint8Array, chunkSize?: number, argon2MemoryKib?: number, argon2Passes?: number }} options
   */
  seal(plain, options) {
    const plainBytes = assertBytes(plain, 'plain');
    const { secret, usePassphrase, opts } = resolveSealSecret(options);
    const salt16 =
      opts.salt16 !== undefined ? assertBytes(opts.salt16, 'salt16') : randomBytes(16);
    const noncePrefix12 =
      opts.noncePrefix12 !== undefined
        ? assertBytes(opts.noncePrefix12, 'noncePrefix12')
        : generateNoncePrefix12();
    const chunkSize =
      opts.chunkSize !== undefined
        ? assertInt32(opts.chunkSize, 'chunk_size')
        : DEFAULT_SEAL_CHUNK_SIZE;
    if (chunkSize <= 0) {
      throw new MoonLibSyncError(
        'InvalidOptions:chunk_size',
        'chunkSize must be a positive 32-bit integer',
      );
    }
    const argon2MemoryKib =
      opts.argon2MemoryKib !== undefined
        ? assertInt32(opts.argon2MemoryKib, 'argon2_memory_kib')
        : DEFAULT_ARGON2_MEMORY_KIB;
    if (argon2MemoryKib <= 0) {
      throw new MoonLibSyncError(
        'InvalidOptions:argon2_memory_kib',
        'argon2MemoryKib must be a positive 32-bit integer',
      );
    }
    const argon2Passes =
      opts.argon2Passes !== undefined
        ? assertInt32(opts.argon2Passes, 'argon2_passes')
        : DEFAULT_ARGON2_PASSES;
    if (argon2Passes <= 0) {
      throw new MoonLibSyncError(
        'InvalidOptions:argon2_passes',
        'argon2Passes must be a positive 32-bit integer',
      );
    }
    const res = parseOkJson(
      this.raw.seal_bytes_json(
        plainBytes,
        secret,
        usePassphrase,
        salt16,
        noncePrefix12,
        chunkSize,
        argon2MemoryKib,
        argon2Passes,
      ),
      'seal_bytes_json',
    );
    const cipher = hexToBytes(res.cipher_hex, 'cipher_hex');
    return {
      kdfMode: res.kdf_mode,
      plainBytes: Number(res.plain_bytes),
      cipherBytes: Number(res.cipher_bytes),
      chunkSize: Number(res.chunk_size),
      cipher,
    };
  }

  /**
   * Decrypt and authenticate an `MLSENC01` ChaCha20-Poly1305 container using `{ key }` or `{ passphrase }`.
   * Throws `MoonLibSyncError('AuthenticationFailed', ...)` on tampering or wrong key/passphrase.
   * @param {Uint8Array} cipher
   * @param {{ key?: Uint8Array, passphrase?: string | Uint8Array }} options
   */
  unseal(cipher, options) {
    const cipherBytes = assertBytes(cipher, 'cipher');
    const { secret, usePassphrase } = resolveSealSecret(options);
    const res = parseOkJson(
      this.raw.unseal_bytes_json(cipherBytes, secret, usePassphrase),
      'unseal_bytes_json',
    );
    const plain = hexToBytes(res.plain_hex, 'plain_hex');
    return {
      kdfMode: res.kdf_mode,
      chunkSize: Number(res.chunk_size),
      plainBytes: Number(res.plain_bytes),
      plainSha256: String(res.plain_sha256),
      plain,
    };
  }

  /**
   * Compute a deterministic zsync-style HTTP Range fetch plan (`schema: 3`,
   * `kind: "moonlibsync-range-plan"`) from a remote librsync signature (`0x72730147`
   * or `0x72730137`), remote `targetLength`, and local `basis` bytes.
   * @param {Uint8Array} targetSignature
   * @param {number} targetLength
   * @param {Uint8Array} basis
   * @param {{ mergeGapBytes?: number, maxRanges?: number }} [options]
   */
  planRangeFetch(targetSignature, targetLength, basis, options = {}) {
    const sig = assertBytes(targetSignature, 'targetSignature');
    const tLen = assertNonNegInt32(targetLength, 'target_length');
    const basisBytes = assertBytes(basis, 'basis');
    const { mergeGapBytes, maxRanges } = resolveRangeFetchOptions(options);
    const res = parseOkJson(
      this.raw.plan_range_fetch_json(sig, tLen, basisBytes, mergeGapBytes, maxRanges),
      'plan_range_fetch_json',
    );
    const plan = res.plan;
    if (
      !isPlainObject(plan) ||
      plan.schema !== 3 ||
      plan.kind !== 'moonlibsync-range-plan' ||
      !Array.isArray(plan.ranges) ||
      !Array.isArray(plan.ops)
    ) {
      throw new MoonLibSyncError(
        'InvalidSchema',
        'plan_range_fetch_json returned an unexpected RangeFetchPlan payload',
      );
    }
    return plan;
  }

  /**
   * Reconstruct remote target bytes from local `basis` and fetched HTTP range slices
   * corresponding to `planRangeFetch(targetSignature, targetLength, basis, options).ranges`.
   * @param {Uint8Array} targetSignature
   * @param {number} targetLength
   * @param {Uint8Array} basis
   * @param {ReadonlyArray<Uint8Array | string>} fetchedSlices
   * @param {{ mergeGapBytes?: number, maxRanges?: number }} [options]
   */
  applyRangeFetch(targetSignature, targetLength, basis, fetchedSlices, options = {}) {
    const sig = assertBytes(targetSignature, 'targetSignature');
    const tLen = assertNonNegInt32(targetLength, 'target_length');
    const basisBytes = assertBytes(basis, 'basis');
    const { mergeGapBytes, maxRanges } = resolveRangeFetchOptions(options);
    const slicesJson = serializeBytesOrHexArray(fetchedSlices, 'fetchedSlices', true);
    const res = parseOkJson(
      this.raw.apply_range_fetch_json(
        sig,
        tLen,
        basisBytes,
        mergeGapBytes,
        maxRanges,
        slicesJson,
      ),
      'apply_range_fetch_json',
    );
    const restored = hexToBytes(res.restored_hex, 'restored_hex');
    const restoredBytes = Number(res.restored_bytes);
    if (restored.length !== restoredBytes) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        `Range-fetch restored length mismatch: expected ${restoredBytes} bytes`,
      );
    }
    return {
      restored,
      restoredBytes,
      restoredSha256: String(res.restored_sha256),
      reusedBytes: Number(res.reused_bytes),
      fetchBytes: Number(res.fetch_bytes),
      requestBytes: Number(res.request_bytes),
      rangeCount: Number(res.range_count),
    };
  }

  /**
   * Compose a non-empty chain of standard `librsync 0x72730236` deltas
   * `[v0->v1, v1->v2, ..., v(k-1)->vk]` into a single direct `v0->vk` delta
   * without materializing intermediate versions.
   * @param {ReadonlyArray<Uint8Array | string>} deltas
   */
  composeDeltas(deltas) {
    const deltasJson = serializeBytesOrHexArray(deltas, 'deltas', false);
    const res = parseOkJson(
      this.raw.compose_deltas_json(deltasJson),
      'compose_deltas_json',
    );
    const composed = hexToBytes(res.composed_hex, 'composed_hex');
    const composedBytes = Number(res.composed_bytes);
    if (composed.length !== composedBytes) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        `Composed delta length mismatch: expected ${composedBytes} bytes`,
      );
    }
    return {
      composed,
      composedBytes,
      composedSha256: String(res.composed_sha256),
      inputTotalBytes: Number(res.input_total_bytes),
      instructionCount: Number(res.instruction_count),
      copyCount: Number(res.copy_count),
      literalCount: Number(res.literal_count),
      copyBytes: Number(res.copy_bytes),
      literalBytes: Number(res.literal_bytes),
      outputBytes: Number(res.output_bytes),
    };
  }

  /**
   * Compress bytes into a bounded RFC 1950 zlib stream (`level` 0..=9).
   * @param {Uint8Array} input
   * @param {{ maxInput?: number, maxOutput?: number, level?: number }} [options]
   * @returns {Uint8Array}
   */
  compressZlib(input, options = {}) {
    const bytes = assertBytes(input, 'input');
    const opts = assertOptionsObject(options);
    const maxInput = assertNonNegInt32(
      opts.maxInput ?? DEFAULT_MAX_ZLIB_INPUT,
      'max_input',
    );
    const maxOutput = assertNonNegInt32(
      opts.maxOutput ?? DEFAULT_MAX_ZLIB_OUTPUT,
      'max_output',
    );
    const level = assertInt32(opts.level ?? 6, 'level');
    if (level < 0 || level > 9) {
      throw new MoonLibSyncError(
        'InvalidOptions:level',
        'Zlib compression level must be an integer between 0 and 9',
      );
    }
    const out = this.raw.compress_zlib_bytes(bytes, maxInput, maxOutput, level);
    if (!(out instanceof Uint8Array) || out.length === 0) {
      throw new MoonLibSyncError(
        'LimitExceeded',
        'Failed to compress zlib payload (input or output exceeded limits)',
      );
    }
    return out;
  }

  /**
   * Decompress a bounded RFC 1950 zlib stream with zip-bomb (`LimitExceeded`),
   * trailing-byte (`TrailingData`), truncated-frame (`TruncatedInput`), and
   * checksum/corrupt-stream (`InvalidDelta`) detection.
   * Returns `{ ok: true, data, inputBytes, outputBytes, outputSha256 }` or `{ ok: false, error }`.
   * @param {Uint8Array} input
   * @param {{ maxInput?: number, maxOutput?: number }} [options]
   */
  decompressZlib(input, options = {}) {
    const bytes = assertBytes(input, 'input');
    const opts = assertOptionsObject(options);
    const maxInput = assertNonNegInt32(
      opts.maxInput ?? DEFAULT_MAX_ZLIB_INPUT,
      'max_input',
    );
    const maxOutput = assertNonNegInt32(
      opts.maxOutput ?? DEFAULT_MAX_ZLIB_OUTPUT,
      'max_output',
    );
    const parsed = parseJsonStrict(
      this.raw.decompress_zlib_check_json(bytes, maxInput, maxOutput),
      'decompress_zlib_check_json',
    );
    if (isErrorEnvelope(parsed)) {
      return {
        ok: false,
        error: parsed.error,
      };
    }
    if (!isPlainObject(parsed) || parsed.ok !== true) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        'decompress_zlib_check_json returned an unexpected payload',
      );
    }
    const data = hexToBytes(parsed.output_hex, 'output_hex');
    const outputBytes = Number(parsed.output_bytes);
    if (data.length !== outputBytes) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        `Decompressed zlib length mismatch: expected ${outputBytes} bytes`,
      );
    }
    return {
      ok: true,
      data,
      inputBytes: Number(parsed.input_bytes),
      outputBytes,
      outputSha256: String(parsed.output_sha256),
    };
  }

  /**
   * Derive an RFC 7748 X25519 key pair and 16-hex SHA-256 key ID from a 32-byte
   * hex secret scalar. Auto-generates 32 CSPRNG bytes via `globalThis.crypto.getRandomValues`
   * when `secretHex` is omitted.
   * @param {string} [secretHex]
   */
  x25519KeypairFromSecret(secretHex) {
    const resolvedSecretHex =
      secretHex === undefined
        ? bytesToHex(randomNonZeroBytes(32))
        : assertHexBytesString(
            secretHex,
            'secretHex',
            32,
            'InvalidKey:x25519_secret',
          );
    const res = parseOkJson(
      this.raw.x25519_keypair_from_secret_json(resolvedSecretHex),
      'x25519_keypair_from_secret_json',
    );
    const secretKey = hexToBytes(res.secret_key_hex, 'secret_key_hex');
    const publicKey = hexToBytes(res.public_key_hex, 'public_key_hex');
    return {
      secretKeyHex: String(res.secret_key_hex),
      publicKeyHex: String(res.public_key_hex),
      secretKey,
      publicKey,
      keyId: String(res.key_id),
    };
  }

  /**
   * Seal `plaintext` into a multi-recipient `MLSENC02` X25519 + HKDF-SHA256 +
   * ChaCha20-Poly1305 authenticated envelope for 1..=64 recipients.
   * Auto-generates CSPRNG `ephemeralSecretHex` (32 bytes), `contentKeyHex` (32 bytes),
   * and `noncePrefixHex` (4 bytes) via `globalThis.crypto.getRandomValues` when omitted.
   * @param {Uint8Array} plaintext
   * @param {ReadonlyArray<string>} recipientPublicKeysHex
   * @param {{ chunkSize?: number, ephemeralSecretHex?: string, contentKeyHex?: string, noncePrefixHex?: string }} [options]
   */
  sealEnvelope(plaintext, recipientPublicKeysHex, options = {}) {
    const plainBytes = assertBytes(plaintext, 'plaintext');
    const recipientPubsJson = serializeHexStringArray(
      recipientPublicKeysHex,
      'recipientPublicKeysHex',
      32,
      'InvalidKey:recipient_public_key',
      1,
      MAX_ENVELOPE_RECIPIENTS,
      'InvalidOptions:recipient_count',
    );
    const opts = assertOptionsObject(options);
    const chunkSize = assertInt32(
      opts.chunkSize ?? DEFAULT_SEAL_CHUNK_SIZE,
      'chunk_size',
    );
    if (chunkSize < MIN_SEAL_CHUNK_SIZE || chunkSize > MAX_SEAL_CHUNK_SIZE) {
      throw new MoonLibSyncError(
        'InvalidOptions:chunk_size',
        `chunkSize must be an integer between ${MIN_SEAL_CHUNK_SIZE} and ${MAX_SEAL_CHUNK_SIZE}`,
      );
    }
    const ephemeralSecretHex =
      opts.ephemeralSecretHex !== undefined
        ? assertHexBytesString(
            opts.ephemeralSecretHex,
            'ephemeralSecretHex',
            32,
            'InvalidKey:x25519_secret',
          )
        : bytesToHex(randomNonZeroBytes(32));
    const contentKeyHex =
      opts.contentKeyHex !== undefined
        ? assertHexBytesString(
            opts.contentKeyHex,
            'contentKeyHex',
            32,
            'InvalidKey:content_key',
          )
        : bytesToHex(randomBytes(32));
    const noncePrefixHex =
      opts.noncePrefixHex !== undefined
        ? assertHexBytesString(
            opts.noncePrefixHex,
            'noncePrefixHex',
            4,
            'InvalidOptions:nonce_prefix',
          )
        : bytesToHex(randomBytes(4));

    const res = parseOkJson(
      this.raw.seal_envelope_json(
        plainBytes,
        recipientPubsJson,
        ephemeralSecretHex,
        contentKeyHex,
        noncePrefixHex,
        chunkSize,
      ),
      'seal_envelope_json',
    );
    const ciphertext = hexToBytes(res.ciphertext_hex, 'ciphertext_hex');
    const ciphertextBytes = Number(res.ciphertext_bytes);
    if (ciphertext.length !== ciphertextBytes) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        `Envelope ciphertext length mismatch: expected ${ciphertextBytes} bytes`,
      );
    }
    if (!Array.isArray(res.recipient_key_ids)) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        'seal_envelope_json returned malformed recipient_key_ids',
      );
    }
    return {
      ciphertext,
      ciphertextBytes,
      ciphertextSha256: String(res.ciphertext_sha256),
      recipientCount: Number(res.recipient_count),
      recipientKeyIds: res.recipient_key_ids.map((id) => String(id)),
      ephemeralPublicKeyHex: String(res.ephemeral_public_key_hex),
      chunkSize: Number(res.chunk_size),
    };
  }

  /**
   * Unseal and authenticate a multi-recipient `MLSENC02` X25519 envelope using
   * one recipient's 32-byte (64-hex) X25519 secret key.
   * Throws `MoonLibSyncError('AuthenticationFailed', ...)` on unauthorized keys or tampering.
   * @param {Uint8Array} ciphertext
   * @param {string} recipientSecretHex
   */
  unsealEnvelope(ciphertext, recipientSecretHex) {
    const cipherBytes = assertBytes(ciphertext, 'ciphertext');
    const secretHex = assertHexBytesString(
      recipientSecretHex,
      'recipientSecretHex',
      32,
      'InvalidKey:x25519_secret',
    );
    const res = parseOkJson(
      this.raw.unseal_envelope_json(cipherBytes, secretHex),
      'unseal_envelope_json',
    );
    const plaintext = hexToBytes(res.plaintext_hex, 'plaintext_hex');
    const plaintextBytes = Number(res.plaintext_bytes);
    if (plaintext.length !== plaintextBytes) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        `Envelope plaintext length mismatch: expected ${plaintextBytes} bytes`,
      );
    }
    if (!Array.isArray(res.recipient_key_ids)) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        'unseal_envelope_json returned malformed recipient_key_ids',
      );
    }
    return {
      plaintext,
      plaintextBytes,
      plaintextSha256: String(res.plaintext_sha256),
      recipientCount: Number(res.recipient_count),
      recipientKeyIds: res.recipient_key_ids.map((id) => String(id)),
      ephemeralPublicKeyHex: String(res.ephemeral_public_key_hex),
    };
  }

  /**
   * Construct and validate a canonical Schema 4 Ed25519 `TrustKeyring` JSON document
   * with optional revoked 16-hex key IDs and an M-of-N `minQuorum` threshold.
   * @param {ReadonlyArray<string>} trustedPublicKeysHex
   * @param {{ revokedKeyIds?: ReadonlyArray<string>, minQuorum?: number }} [options]
   */
  createTrustKeyring(trustedPublicKeysHex, options = {}) {
    const trustedKeysJson = serializeHexStringArray(
      trustedPublicKeysHex,
      'trustedPublicKeysHex',
      32,
      'InvalidKey:trusted_public_key',
      1,
      undefined,
      'InvalidOptions:trustedPublicKeysHex',
    );
    const opts = assertOptionsObject(options);
    const revokedIdsJson = serializeHexStringArray(
      opts.revokedKeyIds ?? [],
      'revokedKeyIds',
      8,
      'InvalidFormat:revoked_key_id',
      0,
      undefined,
      'InvalidOptions:revokedKeyIds',
    );
    const minQuorum = assertInt32(opts.minQuorum ?? 1, 'min_quorum');
    if (minQuorum < 1) {
      throw new MoonLibSyncError(
        'InvalidOptions:min_quorum',
        'minQuorum must be a positive 32-bit integer',
      );
    }
    const res = parseOkJson(
      this.raw.create_trust_keyring_json(trustedKeysJson, revokedIdsJson, minQuorum),
      'create_trust_keyring_json',
    );
    if (!Array.isArray(res.key_ids)) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        'create_trust_keyring_json returned malformed key_ids',
      );
    }
    return {
      keyringJson: String(res.keyring_json),
      trustedCount: Number(res.trusted_count),
      revokedCount: Number(res.revoked_count),
      minQuorum: Number(res.min_quorum),
      keyIds: res.key_ids.map((id) => String(id)),
    };
  }

  /**
   * Verify an M-of-N Ed25519 signature bundle (or array of publisher signatures)
   * against a Schema 4 `TrustKeyring` JSON document and payload bytes, enforcing revocations.
   * @param {ReadonlyArray<string | Record<string, unknown>> | string} signatures
   * @param {string} keyringJson
   * @param {Uint8Array} payload
   */
  verifyQuorum(signatures, keyringJson, payload) {
    if (typeof keyringJson !== 'string' || keyringJson.trim().length === 0) {
      throw new MoonLibSyncError(
        'InvalidOptions:keyringJson',
        'Expected non-empty trust keyring JSON string for "keyringJson"',
      );
    }
    const payloadBytes = assertBytes(payload, 'payload');
    const signaturesJson = serializeQuorumSignatures(signatures);
    const res = parseOkJson(
      this.raw.verify_quorum_bytes_json(signaturesJson, keyringJson, payloadBytes),
      'verify_quorum_bytes_json',
    );
    if (
      !Array.isArray(res.verified_key_ids) ||
      !Array.isArray(res.rejected_key_ids) ||
      !Array.isArray(res.revoked_hits)
    ) {
      throw new MoonLibSyncError(
        'UnexpectedError',
        'verify_quorum_bytes_json returned malformed key ID arrays',
      );
    }
    return {
      bundleJson: String(res.bundle_json),
      verifiedKeyIds: res.verified_key_ids.map((id) => String(id)),
      rejectedKeyIds: res.rejected_key_ids.map((id) => String(id)),
      revokedHits: res.revoked_hits.map((id) => String(id)),
      requiredQuorum: Number(res.required_quorum),
    };
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
  const explicitModulePath = opts.modulePath !== undefined;
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

  if (explicitModulePath) {
    pushUnique(await resolveSpecifierCandidates(opts.modulePath));
  } else {
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
  }

  const failures = [];
  for (const specifier of candidateUrls) {
    try {
      const mod = await import(specifier);
      const missing = getMissingExports(mod);
      if (missing.length === 0) {
        return createClient(mod);
      }
      failures.push(
        `incompatible module (missing ${missing.length} export(s): ${missing.slice(0, 3).join(', ')})`,
      );
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      failures.push(reason);
    }
  }

  if (explicitModulePath) {
    const requestedPath =
      opts.modulePath instanceof URL ? opts.modulePath.href : String(opts.modulePath);
    throw new MoonLibSyncError(
      'LoadFailed',
      `Failed to load MoonLibSync module from explicit modulePath "${requestedPath}": ${failures[failures.length - 1] || 'unknown'}`,
    );
  }

  throw new MoonLibSyncError(
    'ModuleLoadError',
    `Unable to load MoonLibSync compiled JS core module after ${candidateUrls.length} candidate(s). Run "npm run build" in js/ or "moon build examples/web-demo --target js --release". Last error: ${failures[failures.length - 1] || 'unknown'}`,
  );
}
