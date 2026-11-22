// SPDX-License-Identifier: LGPL-2.1-or-later
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const buildDir = process.env.MOONLIBSYNC_BUILD_DIR || '_build';
const rebuild = process.argv.includes('--rebuild');
const candidates = [
  path.join(root, buildDir, 'js', 'debug', 'build', 'examples', 'web-demo', 'web-demo.js'),
  path.join(
    root,
    buildDir,
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
    ['--target-dir', buildDir, 'build', 'examples/web-demo', '--target', 'js'],
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
const patch = new TextEncoder().encode('WEB-DEMO-STREAMING-040-PATCH-REPEATED-'.repeat(8));
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
const plan = JSON.parse(wasmSync.plan_dir_snapshots_json(snap1, snap2));
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

console.log(
  `WEB_DEMO_OK sig=${res.signature_bytes} delta=${res.delta_bytes} delta_gz=${res.gzip_delta_bytes} copy=${res.copy_bytes} verified=true`,
);
