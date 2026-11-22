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

// 1. Streaming > 64 KiB roundtrip with chunk splits and --block-size auto (0).
const oldBytes = new Uint8Array(80000);
for (let i = 0; i < oldBytes.length; i++) {
  oldBytes[i] = (i * 73 + 19 + Math.floor(i / 512) * 11) % 256;
}
const newBytes = new Uint8Array(oldBytes.length + 32);
newBytes.set(oldBytes.subarray(0, 40000), 0);
const patch = new TextEncoder().encode('WEB-DEMO-STREAMING-040-PATCH!!');
newBytes.set(patch, 40000);
newBytes.set(oldBytes.subarray(40000), 40000 + patch.length);

const res = JSON.parse(wasmSync.run_streaming_sync_json(oldBytes, newBytes, 0, 16, 4096));
if (!res.ok || res.verified !== true) {
  throw new Error('Streaming sync failed verification: ' + JSON.stringify(res));
}
if (BigInt(res.copy_bytes) < 70000n || BigInt(res.delta_bytes) >= BigInt(res.new_bytes)) {
  throw new Error('Unexpected delta ratio: ' + JSON.stringify(res));
}
if (res.restored_sha256 !== res.new_sha256) {
  throw new Error('SHA-256 mismatch: ' + JSON.stringify(res));
}

// 2. Invalid strong_sum_len cleanly returns structured JSON error instead of throwing uncaught.
const errRes = JSON.parse(wasmSync.run_streaming_sync_json(oldBytes.subarray(0, 32), newBytes.subarray(0, 32), 64, 0, 16));
if (errRes.ok !== false || !String(errRes.error).includes('InvalidOptions')) {
  throw new Error('Expected structured InvalidOptions error: ' + JSON.stringify(errRes));
}

// 3. Schema 3 directory snapshot diff planning via exported MoonBit engine.
const shaA = '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
const shaB1 = '486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7';
const shaB2 = '8254c3d3f4a19949334d3982124c6fd89c9f08402122666e5666e770c4765249';
const snap1 = JSON.stringify({
  schema_version: 3,
  kind: 'moonlibsync-dir-snapshot',
  entries: [
    { path: 'a.txt', byte_length: '5', sha256: shaA },
    { path: 'sub/b.bin', byte_length: '10', sha256: shaB1 },
    { path: 'old.bin', byte_length: '4', sha256: shaA },
  ].sort((x, y) => (x.path < y.path ? -1 : x.path > y.path ? 1 : 0)),
});
const snap2 = JSON.stringify({
  schema_version: 3,
  kind: 'moonlibsync-dir-snapshot',
  entries: [
    { path: 'a.txt', byte_length: '5', sha256: shaA },
    { path: 'new.bin', byte_length: '7', sha256: shaA },
    { path: 'sub/b.bin', byte_length: '12', sha256: shaB2 },
  ].sort((x, y) => (x.path < y.path ? -1 : x.path > y.path ? 1 : 0)),
});
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

console.log(
  `WEB_DEMO_OK sig=${res.signature_bytes} delta=${res.delta_bytes} copy=${res.copy_bytes} verified=true`,
);
