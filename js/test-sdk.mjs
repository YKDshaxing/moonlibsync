// SPDX-License-Identifier: LGPL-2.1-or-later
import assert from 'node:assert/strict';
import {
  MoonLibSyncClient,
  MoonLibSyncError,
  createClient,
  loadMoonLibSync,
} from './index.js';

function assertSyncError(fn, expectedCode, label) {
  let caught = null;
  try {
    fn();
  } catch (err) {
    caught = err;
  }
  assert.ok(
    caught instanceof MoonLibSyncError,
    `${label}: expected MoonLibSyncError, got ${caught}`,
  );
  if (expectedCode instanceof RegExp) {
    assert.match(caught.code, expectedCode, `${label}: unexpected error code`);
  } else {
    assert.equal(caught.code, expectedCode, `${label}: unexpected error code`);
  }
}

const enc = new TextEncoder();
const client = await loadMoonLibSync();
assert.ok(client instanceof MoonLibSyncClient);

// Verify synchronous factory from raw exports.
const clientFromRaw = createClient(client.raw);
assert.ok(clientFromRaw instanceof MoonLibSyncClient);

// Construct deterministic 80 KiB OLD and modified NEW inputs.
const oldBytes = new Uint8Array(80000);
for (let i = 0; i < oldBytes.length; i++) {
  oldBytes[i] = (i * 73 + 19 + Math.floor(i / 512) * 11) % 256;
}
const patchBytes = enc.encode('MOONLIBSYNC-JS-SDK-050-PATCH-REPEATED-'.repeat(8));
const newBytes = new Uint8Array(oldBytes.length + patchBytes.length);
newBytes.set(oldBytes.subarray(0, 40000), 0);
newBytes.set(patchBytes, 40000);
newBytes.set(oldBytes.subarray(40000), 40000 + patchBytes.length);

// 1. Streaming sync pipeline + invalid option error handling.
const syncRes = client.runStreamingSync(oldBytes, newBytes, {
  blockLen: 0,
  strongSumLen: 16,
  chunkSize: 4096,
});
assert.equal(syncRes.ok, true);
assert.equal(syncRes.verified, true);
assert.equal(syncRes.restored_sha256, syncRes.new_sha256);
assert.ok(BigInt(syncRes.copy_bytes) >= 70000n);
assert.ok(BigInt(syncRes.delta_bytes) < BigInt(syncRes.new_bytes));
assert.ok(BigInt(syncRes.gzip_delta_bytes) < BigInt(syncRes.delta_bytes));

assertSyncError(
  () =>
    client.runStreamingSync(oldBytes.subarray(0, 32), newBytes.subarray(0, 32), {
      blockLen: 64,
      strongSumLen: 0,
      chunkSize: 16,
    }),
  /^InvalidOptions/,
  'runStreamingSync invalid strongSumLen',
);

// 2. Signature, delta, patch, SHA-256 roundtrip (including empty target edge case).
const sigBytes = client.createSignature(oldBytes, { blockLen: 0, strongSumLen: 16 });
const deltaBytes = client.createDelta(sigBytes, newBytes);
const restoredBytes = client.applyPatch(oldBytes, deltaBytes);
assert.equal(sigBytes.length, Number(syncRes.signature_bytes));
assert.equal(deltaBytes.length, Number(syncRes.delta_bytes));
assert.deepEqual(restoredBytes, newBytes);
assert.equal(client.sha256Hex(restoredBytes), syncRes.new_sha256);

const emptyDelta = client.createDelta(sigBytes, new Uint8Array(0));
const emptyRestored = client.applyPatch(oldBytes, emptyDelta);
assert.equal(emptyRestored.length, 0);

assertSyncError(
  () => client.createSignature(oldBytes, { strongSumLen: 0 }),
  'InvalidOptions:strong_sum_len',
  'createSignature invalid strongSumLen',
);
assertSyncError(
  () => client.createDelta(new Uint8Array([1, 2, 3, 4]), newBytes),
  'InvalidSignature',
  'createDelta invalid signature',
);
assertSyncError(
  () => client.applyPatch(oldBytes, new Uint8Array([0x72, 0x73, 0x02, 0x36])),
  'TruncatedInput',
  'applyPatch truncated delta',
);

// 3. Bounded Gzip roundtrip + Zip-Bomb LimitExceeded + TrailingData + TruncatedInput.
const gzDelta = client.compressGzip(deltaBytes, { level: 6 });
assert.equal(gzDelta.length, Number(syncRes.gzip_delta_bytes));
const ungzDelta = client.decompressGzip(gzDelta, { maxOutput: 1048576 });
assert.deepEqual(ungzDelta, deltaBytes);

const emptyGz = client.compressGzip(new Uint8Array(0), { level: 6 });
assert.equal(client.decompressGzip(emptyGz).length, 0);

const bombGz = client.compressGzip(new Uint8Array(262144), { level: 6 });
assertSyncError(
  () => client.decompressGzip(bombGz, { maxOutput: 4096 }),
  'LimitExceeded',
  'decompressGzip zip bomb',
);

const trailingGz = new Uint8Array(gzDelta.length + 1);
trailingGz.set(gzDelta, 0);
trailingGz[gzDelta.length] = 0x42;
assertSyncError(
  () => client.decompressGzip(trailingGz, { maxOutput: 1048576 }),
  'TrailingData',
  'decompressGzip trailing byte',
);

assertSyncError(
  () => client.decompressGzip(gzDelta.subarray(0, gzDelta.length - 1), { maxOutput: 1048576 }),
  'TruncatedInput',
  'decompressGzip truncated frame',
);

assertSyncError(
  () => client.applyPatch(oldBytes, gzDelta),
  'InvalidDelta',
  'applyPatch rejects gzip',
);

// 4. Detailed delta inspection (full & truncated).
const detailed = client.inspectDeltaDetailed(deltaBytes, { maxItems: 512 });
assert.equal(detailed.ok, true);
assert.equal(detailed.truncated, false);
assert.equal(detailed.summary.delta_bytes, String(deltaBytes.length));
assert.equal(detailed.summary.output_bytes, String(newBytes.length));
assert.ok(detailed.items.length >= 2);
assert.ok(detailed.items.some((item) => item.kind === 'copy'));
assert.ok(detailed.items.some((item) => item.kind === 'literal'));

const truncatedInspect = client.inspectDeltaDetailed(deltaBytes, { maxItems: 1 });
assert.equal(truncatedInspect.truncated, true);
assert.equal(truncatedInspect.items.length, 1);

// 5. Artifact auto-detection across binary and Schema 3 JSON artifacts.
const sigArtifact = client.inspectArtifact(sigBytes);
assert.equal(sigArtifact.artifact_kind, 'signature');
assert.equal(sigArtifact.summary.magic, '0x72730147');

const deltaArtifact = client.inspectArtifact(deltaBytes);
assert.equal(deltaArtifact.artifact_kind, 'delta');
assert.equal(deltaArtifact.summary.output_bytes, String(newBytes.length));

const gzArtifact = client.inspectArtifact(gzDelta);
assert.equal(gzArtifact.artifact_kind, 'gzip');
assert.equal(gzArtifact.uncompressed_bytes, String(deltaBytes.length));
assert.equal(gzArtifact.uncompressed_sha256, client.sha256Hex(deltaBytes));

assertSyncError(
  () => client.inspectArtifact(enc.encode('not-a-moonlibsync-artifact')),
  'UnsupportedArtifact',
  'inspectArtifact unsupported input',
);

// 6. Block-size benchmark report.
const bench = client.benchmarkBlockSizes(oldBytes, newBytes, { strongSumLen: 16 });
assert.equal(bench.ok, true);
assert.equal(bench.old_bytes, String(oldBytes.length));
assert.equal(bench.new_bytes, String(newBytes.length));
assert.deepEqual(
  bench.results.map((r) => r.label),
  ['auto', '256', '512', '2048', '4096'],
);

// 7. Schema 3 directory snapshot creation, excludes filtering, planning, and verification.
const makeEntry = (p, text) => {
  const b = enc.encode(text);
  return { path: p, byte_length: b.length, sha256: client.sha256Hex(b) };
};

const snapBasis = client.createDirSnapshot(
  [
    makeEntry('sub/b.bin', 'old-version'),
    makeEntry('.git/HEAD', 'ref: refs/heads/main'),
    makeEntry('debug.log', 'ignored log'),
    makeEntry('dist/bundle.js', 'ignored dist'),
    makeEntry('a.txt', 'hello'),
    makeEntry('old.bin', 'drop'),
  ],
  { excludes: ['.git', '*.log', 'dist/*'] },
);
assert.equal(snapBasis.schema_version, 3);
assert.equal(snapBasis.kind, 'moonlibsync-dir-snapshot');
assert.deepEqual(
  snapBasis.entries.map((e) => e.path),
  ['a.txt', 'old.bin', 'sub/b.bin'],
);

const snapTarget = client.createDirSnapshot([
  makeEntry('new.bin', 'added!!'),
  makeEntry('sub/b.bin', 'new-version-2'),
  makeEntry('a.txt', 'hello'),
]);
assert.deepEqual(
  snapTarget.entries.map((e) => e.path),
  ['a.txt', 'new.bin', 'sub/b.bin'],
);

const snapArtifact = client.inspectArtifact(enc.encode(JSON.stringify(snapBasis)));
assert.equal(snapArtifact.artifact_kind, 'moonlibsync-dir-snapshot');
assert.equal(snapArtifact.schema_version, 3);
assert.equal(snapArtifact.summary.entries, '3');

assertSyncError(
  () =>
    client.createDirSnapshot([
      makeEntry('Readme.md', 'a'),
      makeEntry('readme.md', 'b'),
    ]),
  /path_collision/,
  'createDirSnapshot case collision',
);

const planFromObjects = client.planDirSnapshots(snapBasis, snapTarget);
const planFromStrings = client.planDirSnapshots(
  JSON.stringify(snapBasis),
  JSON.stringify(snapTarget),
);
assert.deepEqual(planFromObjects, planFromStrings);
assert.equal(planFromObjects.schema_version, 3);
assert.equal(planFromObjects.kind, 'moonlibsync-dir-plan');
assert.equal(planFromObjects.summary.unchanged, '1');
assert.equal(planFromObjects.summary.add, '1');
assert.equal(planFromObjects.summary.update, '1');
assert.equal(planFromObjects.summary.delete, '1');

const planArtifact = client.inspectArtifact(enc.encode(JSON.stringify(planFromObjects)));
assert.equal(planArtifact.artifact_kind, 'moonlibsync-dir-plan');

const verifyMatch = client.verifyDirSnapshots(snapTarget, snapTarget);
assert.equal(verifyMatch.schema_version, 3);
assert.equal(verifyMatch.kind, 'moonlibsync-dir-verify');
assert.equal(verifyMatch.ok, true);
assert.equal(verifyMatch.summary.matched, '3');
assert.equal(verifyMatch.issues.length, 0);

const verifyDiff = client.verifyDirSnapshots(snapTarget, snapBasis);
assert.equal(verifyDiff.schema_version, 3);
assert.equal(verifyDiff.kind, 'moonlibsync-dir-verify');
assert.equal(verifyDiff.ok, false);
assert.equal(verifyDiff.summary.matched, '1');
assert.equal(verifyDiff.summary.modified, '1');
assert.equal(verifyDiff.summary.missing, '1');
assert.equal(verifyDiff.summary.extra, '1');
assert.equal(verifyDiff.issues.length, 3);

// 8. applyPatchOrGzip: raw delta, gzip delta, verified Schema 1 & Schema 2 manifests, and tampering check.
const patchedRaw = client.applyPatchOrGzip(oldBytes, deltaBytes);
assert.deepEqual(patchedRaw.bytes, newBytes);
assert.equal(patchedRaw.sha256, syncRes.new_sha256);
assert.equal(patchedRaw.decompressedGzip, false);
assert.equal(patchedRaw.verifiedManifest, false);

const patchedGz = client.applyPatchOrGzip(oldBytes, gzDelta);
assert.deepEqual(patchedGz.bytes, newBytes);
assert.equal(patchedGz.sha256, syncRes.new_sha256);
assert.equal(patchedGz.decompressedGzip, true);
assert.equal(patchedGz.verifiedManifest, false);

const schema1Manifest = {
  schema_version: 1,
  kind: 'librsync-delta',
  basis: { byte_length: String(oldBytes.length), sha256: syncRes.old_sha256 },
  signature: { byte_length: String(sigBytes.length), sha256: client.sha256Hex(sigBytes) },
  delta: { byte_length: String(deltaBytes.length), sha256: client.sha256Hex(deltaBytes) },
  result: { byte_length: String(newBytes.length), sha256: syncRes.new_sha256 },
};
const patchedVerified = client.applyPatchOrGzip(
  oldBytes,
  gzDelta,
  JSON.stringify(schema1Manifest),
);
assert.deepEqual(patchedVerified.bytes, newBytes);
assert.equal(patchedVerified.sha256, syncRes.new_sha256);
assert.equal(patchedVerified.decompressedGzip, true);
assert.equal(patchedVerified.verifiedManifest, true);

const tamperedManifest = {
  ...schema1Manifest,
  result: {
    byte_length: String(newBytes.length),
    sha256: '0'.repeat(64),
  },
};
assertSyncError(
  () => client.applyPatchOrGzip(oldBytes, gzDelta, JSON.stringify(tamperedManifest)),
  'BindingMismatch:result_sha256',
  'applyPatchOrGzip rejects tampered manifest',
);

const fullPayload = enc.encode('full-file replacement payload for schema 2 verification');
const fullPayloadGz = client.compressGzip(fullPayload, { level: 6 });
const fullDigest = {
  byte_length: String(fullPayload.length),
  sha256: client.sha256Hex(fullPayload),
};
const schema2FullManifest = {
  schema_version: 2,
  kind: 'full-file',
  payload: fullDigest,
  result: fullDigest,
};
const patchedFull = client.applyPatchOrGzip(
  oldBytes,
  fullPayloadGz,
  schema2FullManifest,
);
assert.deepEqual(patchedFull.bytes, fullPayload);
assert.equal(patchedFull.sha256, fullDigest.sha256);
assert.equal(patchedFull.decompressedGzip, true);
assert.equal(patchedFull.verifiedManifest, true);

console.log('JS_SDK_OK');
