// SPDX-License-Identifier: LGPL-2.1-or-later
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const buildDir = process.env.MOONLIBSYNC_BUILD_DIR || '_build';
const resolvedBuildDir = path.resolve(root, buildDir);
const rebuild = process.argv.includes('--rebuild');
const candidates = [
  path.join(resolvedBuildDir, 'js', 'debug', 'build', 'examples', 'web-demo', 'web-demo.js'),
  path.join(
    resolvedBuildDir,
    'js',
    'debug',
    'build',
    'YKDshaxing',
    'moonlibsync',
    'examples',
    'web-demo',
    'web-demo.js',
  ),
];

let moduleJs = candidates.find((p) => fs.existsSync(p));
if (rebuild || !moduleJs) {
  const build = spawnSync(
    'moon',
    ['--target-dir', resolvedBuildDir, 'build', 'examples/web-demo', '--target', 'js'],
    { cwd: root, encoding: 'utf8' },
  );
  if (build.stdout) process.stdout.write(build.stdout);
  if (build.stderr) process.stderr.write(build.stderr);
  if (build.error) throw build.error;
  if (build.status !== 0) process.exit(build.status ?? 1);
  moduleJs = candidates.find((p) => fs.existsSync(p));
}
if (!moduleJs) {
  throw new Error('Compiled web-demo.js not found in expected paths: ' + candidates.join(', '));
}

const wasmSync = await import(pathToFileURL(moduleJs).href);

// 1. Streaming > 64 KiB roundtrip with chunk splits, --block-size auto (0), and gzip size reporting.
const oldBytes = new Uint8Array(80000);
for (let i = 0; i < oldBytes.length; i++) {
  oldBytes[i] = (i * 73 + 19 + Math.floor(i / 512) * 11) % 256;
}
const patch = new TextEncoder().encode('WEB-DEMO-STREAMING-050-PATCH-REPEATED-'.repeat(8));
const newBytes = new Uint8Array(oldBytes.length + patch.length);
newBytes.set(oldBytes.subarray(0, 40000), 0);
newBytes.set(patch, 40000);
newBytes.set(oldBytes.subarray(40000), 40000 + patch.length);

const res = JSON.parse(wasmSync.run_streaming_sync_json(oldBytes, newBytes, 0, 16, 4096));
if (!res.ok || res.verified !== true) {
  throw new Error('Streaming sync failed verification: ' + JSON.stringify(res));
}
if (BigInt(res.copy_bytes) < 70000n || BigInt(res.delta_bytes) >= BigInt(res.new_bytes)) {
  throw new Error('Unexpected delta ratio: ' + JSON.stringify(res));
}
if (BigInt(res.gzip_delta_bytes) <= 0n || BigInt(res.gzip_delta_bytes) >= BigInt(res.delta_bytes)) {
  throw new Error('Expected gzip to shrink repetitive delta: ' + JSON.stringify(res));
}
if (res.restored_sha256 !== res.new_sha256) {
  throw new Error('SHA-256 mismatch: ' + JSON.stringify(res));
}

// 2. Binary export helpers (.sig / .delta / .delta.gz / restored NEW / SHA-256) + zip-bomb rejection.
const sigBytes = wasmSync.create_signature_bytes(oldBytes, 0, 16);
const deltaBytes = wasmSync.create_delta_bytes(sigBytes, newBytes);
const restoredBytes = wasmSync.apply_patch_bytes(oldBytes, deltaBytes);
const gzDelta = wasmSync.compress_gzip_bytes(deltaBytes, 6);
const ungzDelta = wasmSync.decompress_gzip_bytes(gzDelta, 1048576);
if (
  sigBytes.length !== Number(res.signature_bytes) ||
  deltaBytes.length !== Number(res.delta_bytes) ||
  gzDelta.length !== Number(res.gzip_delta_bytes) ||
  ungzDelta.length !== deltaBytes.length ||
  wasmSync.sha256_hex_bytes(restoredBytes) !== res.new_sha256 ||
  wasmSync.sha256_hex_bytes(ungzDelta) !== wasmSync.sha256_hex_bytes(deltaBytes)
) {
  throw new Error('Binary export roundtrip mismatch');
}

// Zip bomb check + trailing data rejection via decompress_gzip_check_json
const zeros = new Uint8Array(262144);
const bombGz = wasmSync.compress_gzip_bytes(zeros, 6);
const bombCheck = JSON.parse(wasmSync.decompress_gzip_check_json(bombGz, 4096));
if (bombCheck.ok !== false || bombCheck.error !== 'LimitExceeded') {
  throw new Error('Expected LimitExceeded for zip bomb: ' + JSON.stringify(bombCheck));
}
const trailingGz = new Uint8Array(gzDelta.length + 1);
trailingGz.set(gzDelta, 0);
trailingGz[gzDelta.length] = 0x42;
const trailCheck = JSON.parse(wasmSync.decompress_gzip_check_json(trailingGz, 1048576));
if (trailCheck.ok !== false || trailCheck.error !== 'TrailingData') {
  throw new Error('Expected TrailingData rejection: ' + JSON.stringify(trailCheck));
}

// 3. Invalid strong_sum_len cleanly returns structured JSON error instead of throwing uncaught.
const errRes = JSON.parse(
  wasmSync.run_streaming_sync_json(oldBytes.subarray(0, 32), newBytes.subarray(0, 32), 64, 0, 16),
);
if (errRes.ok !== false || !String(errRes.error).includes('InvalidOptions')) {
  throw new Error('Expected structured InvalidOptions error: ' + JSON.stringify(errRes));
}

// 4. Schema 3 directory snapshot creation (unsorted input -> canonical) + diff planning.
const enc = new TextEncoder();
const makeEntry = (p, text) => {
  const b = enc.encode(text);
  return { path: p, byte_length: String(b.length), sha256: wasmSync.sha256_hex_bytes(b) };
};
const snap1 = wasmSync.create_dir_snapshot_json(
  JSON.stringify([
    makeEntry('sub/b.bin', 'old-version'),
    makeEntry('a.txt', 'hello'),
    makeEntry('old.bin', 'drop'),
  ]),
);
const snap2 = wasmSync.create_dir_snapshot_json(
  JSON.stringify([
    makeEntry('new.bin', 'added!!'),
    makeEntry('sub/b.bin', 'new-version-2'),
    makeEntry('a.txt', 'hello'),
  ]),
);
const planText = wasmSync.plan_dir_snapshots_json(snap1, snap2);
const plan = JSON.parse(planText);
if (
  plan.schema_version !== 3 ||
  plan.summary.unchanged !== '1' ||
  plan.summary.add !== '1' ||
  plan.summary.update !== '1' ||
  plan.summary.delete !== '1'
) {
  throw new Error('Unexpected dir plan: ' + JSON.stringify(plan));
}

// Case-folding collision rejected by create_dir_snapshot_json
const coll = JSON.parse(
  wasmSync.create_dir_snapshot_json(
    JSON.stringify([makeEntry('Readme.md', 'a'), makeEntry('readme.md', 'b')]),
  ),
);
if (coll.ok !== false || !String(coll.error).includes('path_collision')) {
  throw new Error('Expected path_collision error: ' + JSON.stringify(coll));
}

// 5. NEW (0.5.0): inspect_delta_detailed_json (spans + truncation + invalid delta rejection).
const detailed = JSON.parse(wasmSync.inspect_delta_detailed_json(deltaBytes, 1024));
if (
  !detailed.ok ||
  detailed.truncated !== false ||
  detailed.summary.delta_bytes !== String(deltaBytes.length) ||
  detailed.summary.output_bytes !== String(newBytes.length) ||
  detailed.items.length !== Number(detailed.summary.instruction_count)
) {
  throw new Error('Unexpected inspect_delta_detailed_json output: ' + JSON.stringify(detailed));
}
let cursorOut = 0n;
let seenCopy = false;
let seenLit = false;
for (const item of detailed.items) {
  if (BigInt(item.output_offset) !== cursorOut) {
    throw new Error('Non-contiguous output_offset in detailed delta: ' + JSON.stringify(item));
  }
  cursorOut += BigInt(item.length);
  if (item.kind === 'copy') seenCopy = true;
  if (item.kind === 'literal') seenLit = true;
}
if (cursorOut !== BigInt(newBytes.length) || !seenCopy || !seenLit) {
  throw new Error('Detailed delta spans mismatch output bytes or missing copy/literal');
}
const detailedTrunc = JSON.parse(wasmSync.inspect_delta_detailed_json(deltaBytes, 10));
if (!detailedTrunc.ok || detailedTrunc.items.length !== 10 || detailedTrunc.truncated !== true) {
  throw new Error('Expected truncated=true with max_items=10: ' + JSON.stringify(detailedTrunc));
}
const detailedClamped = JSON.parse(wasmSync.inspect_delta_detailed_json(deltaBytes, 0));
if (!detailedClamped.ok || detailedClamped.items.length !== 1 || detailedClamped.truncated !== true) {
  throw new Error('Expected max_items=0 to clamp to 1: ' + JSON.stringify(detailedClamped));
}
const badDeltaDetail = JSON.parse(wasmSync.inspect_delta_detailed_json(new Uint8Array([1, 2, 3, 4]), 10));
if (badDeltaDetail.ok !== false) {
  throw new Error('Expected invalid delta failure: ' + JSON.stringify(badDeltaDetail));
}

// 6. NEW (0.5.0): inspect_artifact_json across sig, delta, gzip, bundle-archive, manifests, snapshots, plans, verify reports.
const insSig = JSON.parse(wasmSync.inspect_artifact_json(sigBytes));
if (
  !insSig.ok ||
  insSig.artifact_kind !== 'signature' ||
  insSig.summary.magic !== '0x72730147' ||
  insSig.summary.signature_bytes !== String(sigBytes.length)
) {
  throw new Error('inspect_artifact_json(sig) failed: ' + JSON.stringify(insSig));
}

const insDelta = JSON.parse(wasmSync.inspect_artifact_json(deltaBytes));
if (
  !insDelta.ok ||
  insDelta.artifact_kind !== 'delta' ||
  insDelta.summary.delta_bytes !== String(deltaBytes.length)
) {
  throw new Error('inspect_artifact_json(delta) failed: ' + JSON.stringify(insDelta));
}

const insGz = JSON.parse(wasmSync.inspect_artifact_json(gzDelta));
if (
  !insGz.ok ||
  insGz.artifact_kind !== 'gzip' ||
  insGz.compressed_bytes !== String(gzDelta.length) ||
  insGz.uncompressed_bytes !== String(deltaBytes.length) ||
  insGz.uncompressed_sha256 !== wasmSync.sha256_hex_bytes(deltaBytes)
) {
  throw new Error('inspect_artifact_json(gzip) failed: ' + JSON.stringify(insGz));
}

// Build valid Schema 1 UpdateManifest, Schema 1 BasisInfo, Schema 2 TransferManifest (Delta + Full)
const sigSha = wasmSync.sha256_hex_bytes(sigBytes);
const deltaSha = wasmSync.sha256_hex_bytes(deltaBytes);
const basisInfoJson = JSON.stringify({
  schema_version: 1,
  kind: 'moonlibsync-basis-info',
  basis: { byte_length: String(oldBytes.length), sha256: res.old_sha256 },
  signature: { byte_length: String(sigBytes.length), sha256: sigSha },
});
const updateManifestJson = JSON.stringify({
  schema_version: 1,
  kind: 'librsync-delta',
  basis: { byte_length: String(oldBytes.length), sha256: res.old_sha256 },
  signature: { byte_length: String(sigBytes.length), sha256: sigSha },
  delta: { byte_length: String(deltaBytes.length), sha256: deltaSha },
  result: { byte_length: String(newBytes.length), sha256: res.new_sha256 },
});
const transferDeltaJson = JSON.stringify({
  schema_version: 2,
  kind: 'librsync-delta',
  basis: { byte_length: String(oldBytes.length), sha256: res.old_sha256 },
  signature: { byte_length: String(sigBytes.length), sha256: sigSha },
  payload: { byte_length: String(deltaBytes.length), sha256: deltaSha },
  result: { byte_length: String(newBytes.length), sha256: res.new_sha256 },
});
const transferFullJson = JSON.stringify({
  schema_version: 2,
  kind: 'full-file',
  payload: { byte_length: String(newBytes.length), sha256: res.new_sha256 },
  result: { byte_length: String(newBytes.length), sha256: res.new_sha256 },
});

const insBasis = JSON.parse(wasmSync.inspect_artifact_json(enc.encode(basisInfoJson)));
if (!insBasis.ok || insBasis.artifact_kind !== 'moonlibsync-basis-info' || insBasis.schema_version !== 1) {
  throw new Error('inspect_artifact_json(basis-info) failed: ' + JSON.stringify(insBasis));
}
const insUm = JSON.parse(wasmSync.inspect_artifact_json(enc.encode(updateManifestJson)));
if (!insUm.ok || insUm.artifact_kind !== 'librsync-delta' || insUm.schema_version !== 1) {
  throw new Error('inspect_artifact_json(schema1-manifest) failed: ' + JSON.stringify(insUm));
}
const insTmDelta = JSON.parse(wasmSync.inspect_artifact_json(enc.encode(transferDeltaJson)));
if (!insTmDelta.ok || insTmDelta.artifact_kind !== 'librsync-delta' || insTmDelta.schema_version !== 2) {
  throw new Error('inspect_artifact_json(schema2-delta) failed: ' + JSON.stringify(insTmDelta));
}
const insTmFull = JSON.parse(wasmSync.inspect_artifact_json(enc.encode(transferFullJson)));
if (!insTmFull.ok || insTmFull.artifact_kind !== 'full-file' || insTmFull.schema_version !== 2) {
  throw new Error('inspect_artifact_json(schema2-full) failed: ' + JSON.stringify(insTmFull));
}
const insSnap = JSON.parse(wasmSync.inspect_artifact_json(enc.encode(snap1)));
if (
  !insSnap.ok ||
  insSnap.artifact_kind !== 'moonlibsync-dir-snapshot' ||
  insSnap.schema_version !== 3 ||
  insSnap.summary.entries !== '3'
) {
  throw new Error('inspect_artifact_json(snapshot) failed: ' + JSON.stringify(insSnap));
}
const insPlan = JSON.parse(wasmSync.inspect_artifact_json(enc.encode(planText)));
if (!insPlan.ok || insPlan.artifact_kind !== 'moonlibsync-dir-plan' || insPlan.schema_version !== 3) {
  throw new Error('inspect_artifact_json(plan) failed: ' + JSON.stringify(insPlan));
}

// Construct a valid minimal MLSBDL01 .mbundle archive and verify inspect_artifact_json decodes it.
const payloadData = enc.encode('hello-bundle-payload');
const payloadPath = 'payloads/hello.txt';
const bundleManifestJson = JSON.stringify({
  schema_version: 3,
  kind: 'moonlibsync-dir-bundle',
  summary: {
    unchanged: '0',
    add_full: '1',
    update_delta: '0',
    update_full: '0',
    delete: '0',
    total_payload_bytes: String(payloadData.length),
  },
  entries: [
    {
      path: 'hello.txt',
      kind: 'add-full',
      payload_path: payloadPath,
      target: { byte_length: String(payloadData.length), sha256: wasmSync.sha256_hex_bytes(payloadData) },
    },
  ],
}) + '\n';
const bundleManifestBytes = enc.encode(bundleManifestJson);
const payloadPathBytes = enc.encode(payloadPath);
const u32be = (n) => new Uint8Array([(n >>> 24) & 0xff, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff]);
const u64be = (n) => {
  const b = BigInt(n);
  const out = new Uint8Array(8);
  for (let i = 0; i < 8; i++) out[7 - i] = Number((b >> BigInt(i * 8)) & 0xffn);
  return out;
};
const concatBytes = (...arrs) => {
  const total = arrs.reduce((acc, a) => acc + a.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const a of arrs) {
    out.set(a, off);
    off += a.length;
  }
  return out;
};
const mbundleBytes = concatBytes(
  enc.encode('MLSBDL01'),
  u32be(bundleManifestBytes.length),
  bundleManifestBytes,
  u32be(1),
  u32be(payloadPathBytes.length),
  payloadPathBytes,
  u64be(payloadData.length),
  payloadData,
);
const insBundle = JSON.parse(wasmSync.inspect_artifact_json(mbundleBytes));
if (
  !insBundle.ok ||
  insBundle.artifact_kind !== 'bundle-archive' ||
  insBundle.archive_bytes !== String(mbundleBytes.length) ||
  insBundle.summary.add_full !== '1' ||
  insBundle.summary.total_payload_bytes !== String(payloadData.length)
) {
  throw new Error('inspect_artifact_json(bundle-archive) failed: ' + JSON.stringify(insBundle));
}

const insUnknown = JSON.parse(wasmSync.inspect_artifact_json(enc.encode('totally-unknown-payload')));
if (insUnknown.ok !== false || !insUnknown.error) {
  throw new Error('Expected failure on unknown artifact: ' + JSON.stringify(insUnknown));
}

// 7. NEW (0.5.0): benchmark_block_sizes_json across [auto, 256, 512, 2048, 4096].
const bench = JSON.parse(wasmSync.benchmark_block_sizes_json(oldBytes, newBytes, 16));
const expectedLabels = ['auto', '256', '512', '2048', '4096'];
if (
  !bench.ok ||
  bench.old_bytes !== String(oldBytes.length) ||
  bench.new_bytes !== String(newBytes.length) ||
  bench.results.length !== 5
) {
  throw new Error('benchmark_block_sizes_json failed: ' + JSON.stringify(bench));
}
for (let i = 0; i < expectedLabels.length; i++) {
  const row = bench.results[i];
  if (
    row.label !== expectedLabels[i] ||
    BigInt(row.block_len) <= 0n ||
    BigInt(row.signature_bytes) < 12n ||
    BigInt(row.delta_bytes) < 5n ||
    BigInt(row.gzip_delta_bytes) <= 0n ||
    BigInt(row.copy_bytes) + BigInt(row.literal_bytes) !== BigInt(newBytes.length)
  ) {
    throw new Error('Invalid benchmark row: ' + JSON.stringify(row));
  }
}
const badBench = JSON.parse(wasmSync.benchmark_block_sizes_json(oldBytes, newBytes, 0));
if (badBench.ok !== false || !String(badBench.error).includes('InvalidOptions')) {
  throw new Error('Expected InvalidOptions from bad benchmark: ' + JSON.stringify(badBench));
}

// 8. NEW (0.5.0): verify_dir_snapshots_json (clean match + drift detection + inspect_artifact_json on verify report).
const verifyOkText = wasmSync.verify_dir_snapshots_json(snap1, snap1);
const verifyOk = JSON.parse(verifyOkText);
if (
  verifyOk.schema_version !== 3 ||
  verifyOk.kind !== 'moonlibsync-dir-verify' ||
  verifyOk.ok !== true ||
  verifyOk.summary.matched !== '3' ||
  verifyOk.issues.length !== 0
) {
  throw new Error('verify_dir_snapshots_json(clean) failed: ' + JSON.stringify(verifyOk));
}
const verifyDriftText = wasmSync.verify_dir_snapshots_json(snap1, snap2);
const verifyDrift = JSON.parse(verifyDriftText);
if (
  verifyDrift.schema_version !== 3 ||
  verifyDrift.kind !== 'moonlibsync-dir-verify' ||
  verifyDrift.ok !== false ||
  verifyDrift.summary.matched !== '1' ||
  verifyDrift.summary.modified !== '1' ||
  verifyDrift.summary.missing !== '1' ||
  verifyDrift.summary.extra !== '1' ||
  verifyDrift.issues.length !== 3
) {
  throw new Error('verify_dir_snapshots_json(drift) failed: ' + JSON.stringify(verifyDrift));
}
const insVerify = JSON.parse(wasmSync.inspect_artifact_json(enc.encode(verifyDriftText)));
if (
  !insVerify.ok ||
  insVerify.artifact_kind !== 'moonlibsync-dir-verify' ||
  insVerify.schema_version !== 3 ||
  insVerify.summary.ok !== false
) {
  throw new Error('inspect_artifact_json(verify-report) failed: ' + JSON.stringify(insVerify));
}

// 9. NEW (0.5.0): filter_dir_entries_json (glob filtering + upfront invalid pattern rejection).
const rawEntries = [
  makeEntry('.git/HEAD', 'ref: refs/heads/main'),
  makeEntry('node_modules/pkg/index.js', 'module.exports = 1'),
  makeEntry('cache/scratch.tmp', 'temp'),
  makeEntry('src/main.mbt', 'fn main {}'),
  makeEntry('README.md', '# Hello'),
];
const filteredSnap = JSON.parse(
  wasmSync.filter_dir_entries_json(
    JSON.stringify(rawEntries),
    JSON.stringify(['.git', 'node_modules', '*.tmp']),
  ),
);
if (
  filteredSnap.schema_version !== 3 ||
  filteredSnap.kind !== 'moonlibsync-dir-snapshot' ||
  filteredSnap.entries.length !== 2 ||
  filteredSnap.entries[0].path !== 'README.md' ||
  filteredSnap.entries[1].path !== 'src/main.mbt'
) {
  throw new Error('filter_dir_entries_json filtering mismatch: ' + JSON.stringify(filteredSnap));
}
const badPatternRes = JSON.parse(
  wasmSync.filter_dir_entries_json('[]', JSON.stringify(['../escape'])),
);
if (badPatternRes.ok !== false || !String(badPatternRes.error).includes('InvalidOptions:exclude')) {
  throw new Error('Expected upfront invalid exclude pattern error: ' + JSON.stringify(badPatternRes));
}

// 10. NEW (0.5.0): apply_verified_patch_json & apply_patch_or_gzip_bytes.
const patchRawRes = JSON.parse(wasmSync.apply_verified_patch_json(oldBytes, deltaBytes, ''));
if (
  !patchRawRes.ok ||
  patchRawRes.decompressed_gzip !== false ||
  patchRawRes.verified_manifest !== false ||
  patchRawRes.output_bytes !== String(newBytes.length) ||
  patchRawRes.sha256 !== res.new_sha256
) {
  throw new Error('apply_verified_patch_json(raw) failed: ' + JSON.stringify(patchRawRes));
}
const patchGzRes = JSON.parse(wasmSync.apply_verified_patch_json(oldBytes, gzDelta, '   '));
if (
  !patchGzRes.ok ||
  patchGzRes.decompressed_gzip !== true ||
  patchGzRes.verified_manifest !== false ||
  patchGzRes.sha256 !== res.new_sha256
) {
  throw new Error('apply_verified_patch_json(gz) failed: ' + JSON.stringify(patchGzRes));
}
const patchS1Res = JSON.parse(
  wasmSync.apply_verified_patch_json(oldBytes, gzDelta, updateManifestJson),
);
if (
  !patchS1Res.ok ||
  patchS1Res.decompressed_gzip !== true ||
  patchS1Res.verified_manifest !== true ||
  patchS1Res.sha256 !== res.new_sha256
) {
  throw new Error('apply_verified_patch_json(schema1) failed: ' + JSON.stringify(patchS1Res));
}
const patchS2Res = JSON.parse(
  wasmSync.apply_verified_patch_json(oldBytes, gzDelta, transferDeltaJson),
);
if (
  !patchS2Res.ok ||
  patchS2Res.decompressed_gzip !== true ||
  patchS2Res.verified_manifest !== true ||
  patchS2Res.sha256 !== res.new_sha256
) {
  throw new Error('apply_verified_patch_json(schema2) failed: ' + JSON.stringify(patchS2Res));
}
const tamperedManifest = updateManifestJson.replace(
  res.new_sha256,
  '0'.repeat(64),
);
const patchTampered = JSON.parse(
  wasmSync.apply_verified_patch_json(oldBytes, gzDelta, tamperedManifest),
);
if (patchTampered.ok !== false || !String(patchTampered.error).includes('BindingMismatch')) {
  throw new Error('Expected BindingMismatch for tampered manifest: ' + JSON.stringify(patchTampered));
}

const restoredFromRaw = wasmSync.apply_patch_or_gzip_bytes(oldBytes, deltaBytes);
const restoredFromGz = wasmSync.apply_patch_or_gzip_bytes(oldBytes, gzDelta);
const restoredInvalid = wasmSync.apply_patch_or_gzip_bytes(oldBytes, new Uint8Array([0x1f, 0x8b, 0x00]));
if (
  wasmSync.sha256_hex_bytes(restoredFromRaw) !== res.new_sha256 ||
  wasmSync.sha256_hex_bytes(restoredFromGz) !== res.new_sha256 ||
  restoredInvalid.length !== 0
) {
  throw new Error('apply_patch_or_gzip_bytes roundtrip or error fallback failed');
}

// =========================================================================
// 0.6.0 Tests: Verify all 27 exports & every new capability
// =========================================================================
const expectedExports = [
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
  'create_signature_with_profile_bytes',
  'create_reverse_delta_bytes',
  'plan_dir_snapshots_with_options_json',
  'pack_dir_bundle_archive_json',
  'unpack_dir_bundle_archive_json',
  'ed25519_keypair_from_seed_json',
  'ed25519_sign_bytes_json',
  'ed25519_verify_bytes_json',
  'seal_bytes_json',
  'unseal_bytes_json',
];
for (const name of expectedExports) {
  if (typeof wasmSync[name] !== 'function') {
    throw new Error(`Missing expected 0.6.0 export: ${name}`);
  }
}

const bytesToHex = (b) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
const hexToBytes = (h) => {
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
  return out;
};

// 11. NEW (0.6.0): Literal preview_hex / preview_utf8 / preview_truncated in inspect_delta_detailed_json.
const litItems = detailed.items.filter((it) => it.kind === 'literal');
if (litItems.length === 0) {
  throw new Error('Expected at least one literal command in detailed delta');
}
for (const lit of litItems) {
  if (
    typeof lit.index !== 'number' ||
    typeof lit.preview_hex !== 'string' ||
    typeof lit.preview_utf8 !== 'string' ||
    typeof lit.preview_truncated !== 'boolean'
  ) {
    throw new Error('Missing 0.6.0 literal preview fields: ' + JSON.stringify(lit));
  }
  const expectedPreviewBytes = Math.min(Number(lit.length), 64);
  if (
    lit.preview_hex.length !== expectedPreviewBytes * 2 ||
    lit.preview_utf8.length !== expectedPreviewBytes ||
    lit.preview_truncated !== (Number(lit.length) > 64)
  ) {
    throw new Error('Literal preview length/truncation mismatch: ' + JSON.stringify(lit));
  }
}
// Explicit short literal with control/high bytes + quote + backslash escaping
const litOld = enc.encode('A'.repeat(2048));
const litPayload = new Uint8Array([0x00, 0x22, 0x5c, 0x48, 0x69, 0x7f, 0xff]); // \0 "\Hi \x7f \xff
const litNew = new Uint8Array(litOld.length + litPayload.length);
litNew.set(litOld, 0);
litNew.set(litPayload, litOld.length);
const litDelta = wasmSync.create_delta_bytes(wasmSync.create_signature_bytes(litOld, 512, 16), litNew);
const litDetail = JSON.parse(wasmSync.inspect_delta_detailed_json(litDelta, 64));
const shortLit = litDetail.items.find((it) => it.kind === 'literal');
if (
  !shortLit ||
  shortLit.preview_hex !== '00225c48697fff' ||
  shortLit.preview_utf8 !== '."\\Hi..' ||
  shortLit.preview_truncated !== false
) {
  throw new Error('Unexpected short literal preview encoding: ' + JSON.stringify(shortLit));
}

// 12. NEW (0.6.0): create_signature_with_profile_bytes (0x72730137 Rollsum+BLAKE2b + 0x72730147 RK+BLAKE2b).
const rollsumSig = wasmSync.create_signature_with_profile_bytes(oldBytes, 0, 16, 'rollsum-blake2');
const rkSig = wasmSync.create_signature_with_profile_bytes(oldBytes, 0, 16, 'rk-blake2');
if (
  rollsumSig[0] !== 0x72 ||
  rollsumSig[1] !== 0x73 ||
  rollsumSig[2] !== 0x01 ||
  rollsumSig[3] !== 0x37 ||
  rkSig[3] !== 0x47
) {
  throw new Error('Signature profile magic bytes mismatch');
}
const insRollsum = JSON.parse(wasmSync.inspect_artifact_json(rollsumSig));
if (
  !insRollsum.ok ||
  insRollsum.artifact_kind !== 'signature' ||
  insRollsum.summary.magic !== '0x72730137' ||
  insRollsum.summary.profile !== 'rollsum-blake2'
) {
  throw new Error('inspect_artifact_json(rollsum sig) failed: ' + JSON.stringify(insRollsum));
}
const rollsumDelta = wasmSync.create_delta_bytes(rollsumSig, newBytes);
const rollsumRestored = wasmSync.apply_patch_bytes(oldBytes, rollsumDelta);
if (wasmSync.sha256_hex_bytes(rollsumRestored) !== res.new_sha256) {
  throw new Error('Rollsum signature delta/patch roundtrip mismatch');
}

// 13. NEW (0.6.0): create_reverse_delta_bytes (NEW -> OLD rollback delta).
const revDelta = wasmSync.create_reverse_delta_bytes(oldBytes, newBytes, 0, 0);
if (revDelta.length < 5) {
  throw new Error('create_reverse_delta_bytes returned empty/short delta');
}
const rolledBack = wasmSync.apply_patch_bytes(newBytes, revDelta);
if (
  rolledBack.length !== oldBytes.length ||
  wasmSync.sha256_hex_bytes(rolledBack) !== res.old_sha256
) {
  throw new Error('Reverse delta rollback verification failed');
}

// 14. NEW (0.6.0): plan_dir_snapshots_with_options_json (detect_moves=true vs false).
const movedBody = 'IDENTICAL-MOVED-CONTENT-BLOCK-'.repeat(40);
const moveSnapBasis = wasmSync.create_dir_snapshot_json(
  JSON.stringify([
    makeEntry('keep.txt', 'same'),
    makeEntry('old/moved.txt', movedBody),
  ]),
);
const moveSnapTarget = wasmSync.create_dir_snapshot_json(
  JSON.stringify([
    makeEntry('keep.txt', 'same'),
    makeEntry('new/moved.txt', movedBody),
  ]),
);
const movePlanOnText = wasmSync.plan_dir_snapshots_with_options_json(moveSnapBasis, moveSnapTarget, true);
const movePlanOn = JSON.parse(movePlanOnText);
const movePlanOff = JSON.parse(
  wasmSync.plan_dir_snapshots_with_options_json(moveSnapBasis, moveSnapTarget, false),
);
if (
  movePlanOn.schema_version !== 3 ||
  movePlanOn.summary.copy_from_basis !== '1' ||
  movePlanOn.summary.add !== '0' ||
  movePlanOn.summary.transfer_upper_bound_bytes !== '0' ||
  !movePlanOn.actions.some((a) => a.path === 'new/moved.txt' && a.kind === 'copy-from-basis' && a.source_path === 'old/moved.txt')
) {
  throw new Error('detect_moves=true plan mismatch: ' + JSON.stringify(movePlanOn));
}
if (
  movePlanOff.summary.add !== '1' ||
  movePlanOff.summary.delete !== '1' ||
  Number(movePlanOff.summary.transfer_upper_bound_bytes) !== enc.encode(movedBody).length
) {
  throw new Error('detect_moves=false plan mismatch: ' + JSON.stringify(movePlanOff));
}
const insMovePlan = JSON.parse(wasmSync.inspect_artifact_json(enc.encode(movePlanOnText)));
if (!insMovePlan.ok || insMovePlan.summary.copy_from_basis !== '1') {
  throw new Error('inspect_artifact_json(move plan) failed: ' + JSON.stringify(insMovePlan));
}

// 15. NEW (0.6.0): pack_dir_bundle_archive_json & unpack_dir_bundle_archive_json (.mbundle.gz + raw .mbundle).
const makeHexFile = (p, text) => ({ path: p, content_hex: bytesToHex(enc.encode(text)) });
const bigBase = 'LINE-UNCHANGED-BLOCK-DATA-0123456789\n'.repeat(180);
const bigMovedEditedBase = 'CHANGELOG-ENTRY-LINE-ABCDEF\n'.repeat(120);
const packBasisFiles = [
  makeHexFile('README.md', '# Unchanged'),
  makeHexFile('assets/manual-v1.txt', movedBody),
  makeHexFile('src/app.mbt', bigBase),
  makeHexFile('tiny.txt', 'v1'),
  makeHexFile('legacy/changelog.md', bigMovedEditedBase),
  makeHexFile('drop.txt', 'delete me'),
];
const packTargetFiles = [
  makeHexFile('README.md', '# Unchanged'),
  makeHexFile('docs/manual.txt', movedBody),
  makeHexFile('src/app.mbt', bigBase + '// patched v0.6.0\n'),
  makeHexFile('tiny.txt', 'v2-full'),
  makeHexFile('docs/changelog.md', bigMovedEditedBase + '+ moved and edited v0.6.0\n'),
  makeHexFile('added.txt', 'brand new file'),
];
const packGz = JSON.parse(
  wasmSync.pack_dir_bundle_archive_json(
    JSON.stringify(packBasisFiles),
    JSON.stringify(packTargetFiles),
    true,
    true,
  ),
);
if (
  !packGz.ok ||
  packGz.gzip !== true ||
  packGz.archive_bytes >= packGz.raw_bytes ||
  packGz.summary.copy_from_basis !== '1' ||
  packGz.summary.unchanged !== '1' ||
  packGz.summary.delete !== '3' ||
  packGz.summary.update_full !== '1' ||
  packGz.summary.add_full !== '1' ||
  Number(packGz.summary.update_delta) !== 2 ||
  !packGz.manifest.entries.some((e) => e.path === 'docs/manual.txt' && e.kind === 'copy-from-basis') ||
  !packGz.manifest.entries.some((e) => e.path === 'docs/changelog.md' && e.kind === 'update-delta-from')
) {
  throw new Error('pack_dir_bundle_archive_json(gzip) failed: ' + JSON.stringify(packGz));
}
const archiveGzBytes = hexToBytes(packGz.archive_hex);
const unpackedGz = JSON.parse(
  wasmSync.unpack_dir_bundle_archive_json(JSON.stringify(packBasisFiles), archiveGzBytes),
);
if (!unpackedGz.ok || unpackedGz.was_gzip !== true || unpackedGz.file_count !== packTargetFiles.length) {
  throw new Error('unpack_dir_bundle_archive_json(gzip) failed: ' + JSON.stringify(unpackedGz));
}
const unpackedByPath = new Map(unpackedGz.files.map((f) => [f.path, f]));
for (const expected of packTargetFiles) {
  const got = unpackedByPath.get(expected.path);
  if (!got || got.content_hex !== expected.content_hex) {
    throw new Error(`Unpacked file mismatch for ${expected.path}`);
  }
}
// Raw (non-gzip) pack + inspect_artifact_json + unpack + basis tamper rejection
const packRaw = JSON.parse(
  wasmSync.pack_dir_bundle_archive_json(
    JSON.stringify(packBasisFiles),
    JSON.stringify(packTargetFiles),
    true,
    false,
  ),
);
const archiveRawBytes = hexToBytes(packRaw.archive_hex);
const insRawBundle = JSON.parse(wasmSync.inspect_artifact_json(archiveRawBytes));
if (!insRawBundle.ok || insRawBundle.artifact_kind !== 'bundle-archive' || insRawBundle.summary.copy_from_basis !== '1') {
  throw new Error('inspect_artifact_json(packed raw bundle) failed: ' + JSON.stringify(insRawBundle));
}
const unpackedRaw = JSON.parse(
  wasmSync.unpack_dir_bundle_archive_json(JSON.stringify(packBasisFiles), archiveRawBytes),
);
if (!unpackedRaw.ok || unpackedRaw.was_gzip !== false || unpackedRaw.file_count !== packTargetFiles.length) {
  throw new Error('unpack_dir_bundle_archive_json(raw) failed: ' + JSON.stringify(unpackedRaw));
}
const tamperedBasis = packBasisFiles.map((f) =>
  f.path === 'assets/manual-v1.txt' ? { ...f, content_hex: bytesToHex(enc.encode('CORRUPTED')) } : f,
);
const unpackTampered = JSON.parse(
  wasmSync.unpack_dir_bundle_archive_json(JSON.stringify(tamperedBasis), archiveGzBytes),
);
if (unpackTampered.ok !== false || !String(unpackTampered.error).includes('BindingMismatch')) {
  throw new Error('Expected BindingMismatch on tampered basis unpack: ' + JSON.stringify(unpackTampered));
}

// 16. NEW (0.6.0): Ed25519 keygen, sign, verify, 1-byte tamper, untrusted key + inspect_artifact_json.
const seed1 = new Uint8Array(32);
const seed2 = new Uint8Array(32);
for (let i = 0; i < 32; i++) {
  seed1[i] = (i * 13 + 7) & 0xff;
  seed2[i] = (i * 29 + 3) & 0xff;
}
const kp1 = JSON.parse(wasmSync.ed25519_keypair_from_seed_json(seed1));
const kp2 = JSON.parse(wasmSync.ed25519_keypair_from_seed_json(seed2));
if (
  !kp1.ok ||
  kp1.seed_hex !== bytesToHex(seed1) ||
  kp1.public_key_hex.length !== 64 ||
  kp1.key_id.length !== 16
) {
  throw new Error('ed25519_keypair_from_seed_json failed: ' + JSON.stringify(kp1));
}
const badKp = JSON.parse(wasmSync.ed25519_keypair_from_seed_json(new Uint8Array(16)));
if (badKp.ok !== false || !String(badKp.error).includes('InvalidKey')) {
  throw new Error('Expected InvalidKey for 16-byte seed: ' + JSON.stringify(badKp));
}
const signPayload = enc.encode('MoonLibSync 0.6.0 signed release manifest payload');
const signed = JSON.parse(wasmSync.ed25519_sign_bytes_json(seed1, signPayload));
if (!signed.ok || !signed.signature_json || signed.signature.key_id !== kp1.key_id) {
  throw new Error('ed25519_sign_bytes_json failed: ' + JSON.stringify(signed));
}
const insPubSig = JSON.parse(wasmSync.inspect_artifact_json(enc.encode(signed.signature_json)));
if (
  !insPubSig.ok ||
  insPubSig.artifact_kind !== 'publisher-signature' ||
  insPubSig.summary.algorithm !== 'ed25519' ||
  insPubSig.summary.key_id !== kp1.key_id ||
  insPubSig.summary.public_key !== kp1.public_key_hex ||
  insPubSig.summary.payload_length !== String(signPayload.length) ||
  insPubSig.summary.payload_sha256 !== wasmSync.sha256_hex_bytes(signPayload) ||
  insPubSig.summary.signature.length !== 128
) {
  throw new Error('inspect_artifact_json(publisher-signature) failed: ' + JSON.stringify(insPubSig));
}
const verifyOkEd = JSON.parse(
  wasmSync.ed25519_verify_bytes_json(signed.signature_json, JSON.stringify([kp1.public_key_hex]), signPayload),
);
if (!verifyOkEd.ok || verifyOkEd.verified !== true || verifyOkEd.key_id !== kp1.key_id) {
  throw new Error('ed25519_verify_bytes_json(valid) failed: ' + JSON.stringify(verifyOkEd));
}
const tamperedPayload = new Uint8Array(signPayload);
tamperedPayload[0] ^= 0x01;
const verifyTamperEd = JSON.parse(
  wasmSync.ed25519_verify_bytes_json(signed.signature_json, JSON.stringify([kp1.public_key_hex]), tamperedPayload),
);
if (
  verifyTamperEd.ok !== false ||
  verifyTamperEd.verified !== false ||
  !String(verifyTamperEd.error).includes('DigestMismatch')
) {
  throw new Error('Expected DigestMismatch on tampered payload: ' + JSON.stringify(verifyTamperEd));
}
const verifyUntrustedEd = JSON.parse(
  wasmSync.ed25519_verify_bytes_json(signed.signature_json, JSON.stringify([kp2.public_key_hex]), signPayload),
);
if (
  verifyUntrustedEd.ok !== false ||
  verifyUntrustedEd.verified !== false ||
  !String(verifyUntrustedEd.error).includes('UntrustedKey')
) {
  throw new Error('Expected UntrustedKey for wrong pubkey: ' + JSON.stringify(verifyUntrustedEd));
}

// 17. NEW (0.6.0): MLSENC01 AEAD seal / unseal (raw-key & Argon2id) + tamper + inspect_artifact_json.
const aeadPlain = enc.encode('Confidential MoonLibSync 0.6.0 release bundle payload '.repeat(25));
const aeadKey = new Uint8Array(32);
const aeadSalt = new Uint8Array(16);
const aeadNonce = new Uint8Array(12);
for (let i = 0; i < 32; i++) aeadKey[i] = (i * 11 + 5) & 0xff;
for (let i = 0; i < 16; i++) aeadSalt[i] = (i * 17 + 1) & 0xff;
for (let i = 0; i < 8; i++) aeadNonce[i] = (i * 23 + 9) & 0xff; // bytes 8..11 stay 0

const sealedRaw = JSON.parse(
  wasmSync.seal_bytes_json(aeadPlain, aeadKey, false, aeadSalt, aeadNonce, 0, 0, 0),
);
if (!sealedRaw.ok || sealedRaw.kdf_mode !== 'raw-key' || sealedRaw.plain_bytes !== aeadPlain.length) {
  throw new Error('seal_bytes_json(raw-key) failed: ' + JSON.stringify(sealedRaw));
}
const cipherRaw = hexToBytes(sealedRaw.cipher_hex);
const insSealRaw = JSON.parse(wasmSync.inspect_artifact_json(cipherRaw));
if (
  !insSealRaw.ok ||
  insSealRaw.artifact_kind !== 'seal-archive' ||
  insSealRaw.summary.kdf_mode !== 0 ||
  insSealRaw.summary.kdf_name !== 'raw-key' ||
  insSealRaw.summary.chunk_size !== 65536 ||
  insSealRaw.summary.salt_hex !== bytesToHex(aeadSalt) ||
  insSealRaw.summary.nonce_prefix_hex !== bytesToHex(aeadNonce) ||
  insSealRaw.summary.header_hex.length !== 112
) {
  throw new Error('inspect_artifact_json(seal raw-key) failed: ' + JSON.stringify(insSealRaw));
}
const unsealedRaw = JSON.parse(wasmSync.unseal_bytes_json(cipherRaw, aeadKey, false));
if (
  !unsealedRaw.ok ||
  unsealedRaw.kdf_mode !== 'raw-key' ||
  unsealedRaw.plain_hex !== bytesToHex(aeadPlain) ||
  unsealedRaw.plain_sha256 !== wasmSync.sha256_hex_bytes(aeadPlain)
) {
  throw new Error('unseal_bytes_json(raw-key) failed: ' + JSON.stringify(unsealedRaw));
}
const tamperedCipher = new Uint8Array(cipherRaw);
tamperedCipher[tamperedCipher.length - 1] ^= 0x01;
const unsealTampered = JSON.parse(wasmSync.unseal_bytes_json(tamperedCipher, aeadKey, false));
if (unsealTampered.ok !== false || unsealTampered.error !== 'AuthenticationFailed') {
  throw new Error('Expected AuthenticationFailed on tampered ciphertext: ' + JSON.stringify(unsealTampered));
}

// Argon2id passphrase mode
const passphraseBytes = enc.encode('moonlibsync-060-test-passphrase');
const sealedArgon = JSON.parse(
  wasmSync.seal_bytes_json(aeadPlain, passphraseBytes, true, aeadSalt, aeadNonce, 4096, 1024, 1),
);
if (!sealedArgon.ok || sealedArgon.kdf_mode !== 'argon2id' || sealedArgon.chunk_size !== 4096) {
  throw new Error('seal_bytes_json(argon2id) failed: ' + JSON.stringify(sealedArgon));
}
const cipherArgon = hexToBytes(sealedArgon.cipher_hex);
const insSealArgon = JSON.parse(wasmSync.inspect_artifact_json(cipherArgon));
if (
  !insSealArgon.ok ||
  insSealArgon.artifact_kind !== 'seal-archive' ||
  insSealArgon.summary.kdf_mode !== 1 ||
  insSealArgon.summary.kdf_name !== 'argon2id' ||
  insSealArgon.summary.argon2_memory_kib !== 1024 ||
  insSealArgon.summary.argon2_passes !== 1 ||
  insSealArgon.summary.argon2_lanes !== 1
) {
  throw new Error('inspect_artifact_json(seal argon2id) failed: ' + JSON.stringify(insSealArgon));
}
const unsealedArgon = JSON.parse(wasmSync.unseal_bytes_json(cipherArgon, passphraseBytes, true));
if (
  !unsealedArgon.ok ||
  unsealedArgon.kdf_mode !== 'argon2id' ||
  unsealedArgon.plain_hex !== bytesToHex(aeadPlain) ||
  unsealedArgon.plain_sha256 !== wasmSync.sha256_hex_bytes(aeadPlain)
) {
  throw new Error('unseal_bytes_json(argon2id) failed: ' + JSON.stringify(unsealedArgon));
}
const wrongPassUnseal = JSON.parse(
  wasmSync.unseal_bytes_json(cipherArgon, enc.encode('wrong-passphrase'), true),
);
if (wrongPassUnseal.ok !== false || wrongPassUnseal.error !== 'AuthenticationFailed') {
  throw new Error('Expected AuthenticationFailed on wrong passphrase: ' + JSON.stringify(wrongPassUnseal));
}

console.log(
  `WEB_DEMO_OK sig=${res.signature_bytes} delta=${res.delta_bytes} delta_gz=${res.gzip_delta_bytes} copy=${res.copy_bytes} exports=27 verified=true`,
);
