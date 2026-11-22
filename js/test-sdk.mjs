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
const patchBytes = enc.encode('MOONLIBSYNC-JS-SDK-060-PATCH-REPEATED-'.repeat(8));
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

// 4. Detailed delta inspection (full, truncated, and 0.6.0 literal preview fields).
const detailed = client.inspectDeltaDetailed(deltaBytes, { maxItems: 512 });
assert.equal(detailed.ok, true);
assert.equal(detailed.truncated, false);
assert.equal(detailed.summary.delta_bytes, String(deltaBytes.length));
assert.equal(detailed.summary.output_bytes, String(newBytes.length));
assert.ok(detailed.items.length >= 2);
assert.ok(detailed.items.some((item) => item.kind === 'copy'));
const literalItem = detailed.items.find((item) => item.kind === 'literal');
assert.ok(literalItem, 'expected at least one literal item');
if (literalItem.preview_hex !== undefined) {
  assert.equal(typeof literalItem.preview_hex, 'string');
  assert.ok(literalItem.preview_hex.length > 0);
}
if (literalItem.preview_utf8 !== undefined) {
  assert.equal(typeof literalItem.preview_utf8, 'string');
}
if (literalItem.preview_truncated !== undefined) {
  assert.equal(typeof literalItem.preview_truncated, 'boolean');
}

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

// 9. [0.6.0] Signature profiles: Rollsum+BLAKE2b (0x72730137) & explicit createSignatureWithProfile.
const rollsumSig = client.createSignature(oldBytes, {
  blockLen: 512,
  strongSumLen: 16,
  profile: 'rollsum-blake2',
});
assert.deepEqual(Array.from(rollsumSig.subarray(0, 4)), [0x72, 0x73, 0x01, 0x37]);
const rollsumSigExplicit = client.createSignatureWithProfile(oldBytes, {
  blockLen: 512,
  strongSumLen: 16,
  profile: 'rollsum-blake2',
});
assert.deepEqual(rollsumSigExplicit, rollsumSig);

const rkSigExplicit = client.createSignatureWithProfile(oldBytes, {
  blockLen: 512,
  strongSumLen: 16,
  profile: 'rk-blake2',
});
assert.deepEqual(Array.from(rkSigExplicit.subarray(0, 4)), [0x72, 0x73, 0x01, 0x47]);

const rollsumArtifact = client.inspectArtifact(rollsumSig);
assert.equal(rollsumArtifact.artifact_kind, 'signature');
assert.equal(rollsumArtifact.summary.magic, '0x72730137');

const rollsumDelta = client.createDelta(rollsumSig, newBytes);
const rollsumRestored = client.applyPatch(oldBytes, rollsumDelta);
assert.deepEqual(rollsumRestored, newBytes);

assertSyncError(
  () => client.createSignature(oldBytes, { profile: /** @type {never} */ ('md4-legacy') }),
  'InvalidOptions:profile',
  'createSignature invalid profile',
);

// 10. [0.6.0] Reverse delta (NEW -> OLD rollback).
const revDelta = client.createReverseDelta(oldBytes, newBytes, {
  blockLen: 0,
  strongSumLen: 16,
});
assert.deepEqual(Array.from(revDelta.subarray(0, 4)), [0x72, 0x73, 0x02, 0x36]);
const rolledBack = client.applyPatch(newBytes, revDelta);
assert.deepEqual(rolledBack, oldBytes);
assert.equal(client.sha256Hex(rolledBack), syncRes.old_sha256);

assertSyncError(
  () => client.createReverseDelta(oldBytes, newBytes, { strongSumLen: 0 }),
  'InvalidOptions:strong_sum_len',
  'createReverseDelta invalid strongSumLen',
);

// 11. [0.6.0] Schema 3 directory planning with detectMoves (copy-from-basis 0-byte move).
const moveBasis = client.createDirSnapshot([
  makeEntry('keep.txt', 'constant content'),
  makeEntry('legacy/archive.bin', 'large-moved-payload-content-0123456789'),
]);
const moveTarget = client.createDirSnapshot([
  makeEntry('keep.txt', 'constant content'),
  makeEntry('relocated/archive.bin', 'large-moved-payload-content-0123456789'),
]);

const planNoMoves = client.planDirSnapshots(moveBasis, moveTarget, { detectMoves: false });
assert.equal(planNoMoves.summary.add, '1');
assert.equal(planNoMoves.summary.delete, '1');

const planWithMoves = client.planDirSnapshots(moveBasis, moveTarget, { detectMoves: true });
assert.equal(planWithMoves.schema_version, 3);
assert.equal(planWithMoves.kind, 'moonlibsync-dir-plan');
assert.equal(planWithMoves.summary.copy_from_basis, '1');
assert.equal(planWithMoves.summary.add, '0');
assert.equal(planWithMoves.summary.transfer_upper_bound_bytes, '0');
const copyAction = planWithMoves.actions.find((a) => a.path === 'relocated/archive.bin');
assert.ok(copyAction && copyAction.kind === 'copy-from-basis');
assert.equal(copyAction.source_path, 'legacy/archive.bin');

// 12. [0.6.0] .mbundle & .mbundle.gz pack/unpack with detectMoves and tamper rejection.
const largeBase = new Uint8Array(12288);
for (let i = 0; i < largeBase.length; i++) {
  largeBase[i] = (i * 31 + 7) % 256;
}
const largeEdited = largeBase.slice();
largeEdited.set(enc.encode('EDITED-MIDDLE-BLOCK-060'), 6000);

const movedBase = new Uint8Array(8192);
for (let i = 0; i < movedBase.length; i++) {
  movedBase[i] = (i * 17 + 3) % 256;
}
const movedAndEdited = movedBase.slice();
movedAndEdited.set(enc.encode('MOVED-AND-EDITED-060'), 4096);

const bundleBasisFiles = [
  { path: 'keep.txt', bytes: enc.encode('unchanged-file') },
  { path: 'data/app.bin', bytes: largeBase },
  { path: 'old/exact.bin', bytes: enc.encode('exact-move-payload-'.repeat(64)) },
  { path: 'old/shifted.bin', bytes: movedBase },
  { path: 'obsolete.txt', bytes: enc.encode('delete-me') },
];

const bundleTargetFiles = [
  { path: 'keep.txt', bytes: enc.encode('unchanged-file') },
  { path: 'data/app.bin', bytes: largeEdited },
  { path: 'new/exact.bin', bytes: enc.encode('exact-move-payload-'.repeat(64)) },
  { path: 'new/shifted.bin', bytes: movedAndEdited },
  { path: 'added.txt', bytes: enc.encode('brand-new-file') },
  { path: 'empty.txt', bytes: new Uint8Array(0) },
];

const packedRaw = client.packDirBundleArchive(bundleBasisFiles, bundleTargetFiles, {
  detectMoves: true,
  gzip: false,
});
assert.equal(packedRaw.gzip, false);
assert.equal(packedRaw.archive.length, packedRaw.archiveBytes);
assert.equal(new TextDecoder().decode(packedRaw.archive.subarray(0, 8)), 'MLSBDL01');
assert.equal(packedRaw.manifest.schema_version, 3);
assert.equal(packedRaw.manifest.kind, 'moonlibsync-dir-bundle');
assert.ok(
  packedRaw.manifest.entries.some(
    (e) =>
      e.path === 'new/exact.bin' &&
      e.kind === 'copy-from-basis' &&
      e.source_path === 'old/exact.bin',
  ),
  'expected copy-from-basis entry for renamed identical file',
);
assert.ok(
  packedRaw.manifest.entries.some(
    (e) =>
      e.path === 'new/shifted.bin' &&
      e.kind === 'update-delta-from' &&
      e.source_path === 'old/shifted.bin',
  ),
  'expected update-delta-from entry for renamed and edited file',
);

const bundleArtifact = client.inspectArtifact(packedRaw.archive);
assert.equal(bundleArtifact.artifact_kind, 'bundle-archive');

const unpackedRaw = client.unpackDirBundleArchive(bundleBasisFiles, packedRaw.archive);
assert.equal(unpackedRaw.wasGzip, false);
assert.equal(unpackedRaw.fileCount, bundleTargetFiles.length);
assert.equal(unpackedRaw.files.length, bundleTargetFiles.length);
const targetByPath = new Map(bundleTargetFiles.map((f) => [f.path, f.bytes]));
for (const file of unpackedRaw.files) {
  const expected = targetByPath.get(file.path);
  assert.ok(expected !== undefined, `unexpected unpacked path: ${file.path}`);
  assert.equal(file.byteLength, expected.length);
  assert.equal(file.sha256, client.sha256Hex(expected));
  assert.deepEqual(file.bytes, expected);
}

const packedGz = client.packDirBundleArchive(bundleBasisFiles, bundleTargetFiles, {
  detectMoves: true,
  gzip: true,
});
assert.equal(packedGz.gzip, true);
assert.equal(packedGz.archive[0], 0x1f);
assert.equal(packedGz.archive[1], 0x8b);
assert.equal(packedGz.archive.length, packedGz.archiveBytes);

const unpackedGz = client.unpackDirBundleArchive(bundleBasisFiles, packedGz.archive);
assert.equal(unpackedGz.wasGzip, true);
assert.equal(unpackedGz.fileCount, bundleTargetFiles.length);
for (const file of unpackedGz.files) {
  assert.deepEqual(file.bytes, targetByPath.get(file.path));
}

const tamperedBundle = packedRaw.archive.slice();
tamperedBundle[tamperedBundle.length - 1] ^= 0xff;
assertSyncError(
  () => client.unpackDirBundleArchive(bundleBasisFiles, tamperedBundle),
  /.+/,
  'unpackDirBundleArchive rejects tampered archive',
);

// 13. [0.6.0] Ed25519 publisher signing, inspection, verification, and tamper rejections.
const seedA = new Uint8Array(32);
const seedB = new Uint8Array(32);
for (let i = 0; i < 32; i++) {
  seedA[i] = (i * 9 + 1) & 0xff;
  seedB[i] = (i * 13 + 7) & 0xff;
}

const kpA = client.ed25519KeypairFromSeed(seedA);
const kpB = client.ed25519KeypairFromSeed(seedB);
assert.equal(kpA.seedHex.length, 64);
assert.equal(kpA.publicKeyHex.length, 64);
assert.equal(kpA.publicKey.length, 32);
assert.equal(kpA.keyId.length, 16);
assert.notEqual(kpA.publicKeyHex, kpB.publicKeyHex);

const signedPayload = packedGz.archive;
const signed = client.ed25519Sign(seedA, signedPayload);
assert.equal(typeof signed.signatureJson, 'string');
assert.equal(signed.signature.algorithm, 'ed25519');
assert.equal(signed.signature.key_id, kpA.keyId);
assert.equal(signed.signature.public_key, kpA.publicKeyHex);
assert.equal(signed.signature.payload_sha256, client.sha256Hex(signedPayload));

const pubSigArtifact = client.inspectArtifact(enc.encode(signed.signatureJson));
assert.equal(pubSigArtifact.artifact_kind, 'publisher-signature');
assert.equal(pubSigArtifact.artifact_type, 'publisher-signature');
assert.equal(pubSigArtifact.algorithm, 'ed25519');
assert.equal(pubSigArtifact.key_id, kpA.keyId);
assert.equal(pubSigArtifact.public_key, kpA.publicKeyHex);
assert.equal(pubSigArtifact.payload_sha256, client.sha256Hex(signedPayload));

const verifyByHex = client.ed25519Verify(
  signed.signatureJson,
  [kpA.publicKeyHex],
  signedPayload,
);
assert.equal(verifyByHex.verified, true);
assert.equal(verifyByHex.keyId, kpA.keyId);
assert.equal(verifyByHex.publicKeyHex, kpA.publicKeyHex);
assert.equal(verifyByHex.payloadLength, signedPayload.length);
assert.equal(verifyByHex.payloadSha256, client.sha256Hex(signedPayload));

const verifyByBytes = client.ed25519Verify(
  signed.signatureJson,
  [kpB.publicKey, kpA.publicKey],
  signedPayload,
);
assert.equal(verifyByBytes.verified, true);
assert.equal(verifyByBytes.keyId, kpA.keyId);

assertSyncError(
  () => client.ed25519Verify(signed.signatureJson, [kpB.publicKeyHex], signedPayload),
  /^UntrustedKey(:|$)/,
  'ed25519Verify rejects untrusted key',
);

const tamperedPayload = signedPayload.slice();
tamperedPayload[0] ^= 0x01;
assertSyncError(
  () => client.ed25519Verify(signed.signatureJson, [kpA.publicKeyHex], tamperedPayload),
  /^DigestMismatch(:|$)/,
  'ed25519Verify rejects modified payload',
);

const parsedSigObj = JSON.parse(signed.signatureJson);
const flippedFirstHex = parsedSigObj.signature[0] === '0' ? '1' : '0';
const tamperedSigJson = JSON.stringify({
  ...parsedSigObj,
  signature: flippedFirstHex + parsedSigObj.signature.slice(1),
});
assertSyncError(
  () => client.ed25519Verify(tamperedSigJson, [kpA.publicKeyHex], signedPayload),
  /^InvalidSignature(:|$)/,
  'ed25519Verify rejects forged signature',
);

assertSyncError(
  () => client.ed25519KeypairFromSeed(new Uint8Array(16)),
  /^InvalidKey(:|$)/,
  'ed25519KeypairFromSeed rejects wrong seed length',
);

// 14. [0.6.0] AEAD MLSENC01 ChaCha20-Poly1305 & Argon2id seal/unseal + header inspection + tamper checks.
const rawKey = new Uint8Array(32);
const wrongKey = new Uint8Array(32);
for (let i = 0; i < 32; i++) {
  rawKey[i] = (i * 5 + 3) & 0xff;
  wrongKey[i] = (i * 5 + 4) & 0xff;
}

const secretPlain = new Uint8Array(3500); // > 3 chunks at chunkSize=1024
for (let i = 0; i < secretPlain.length; i++) {
  secretPlain[i] = (i * 41 + 17) & 0xff;
}

const sealedKey = client.seal(secretPlain, {
  key: rawKey,
  chunkSize: 1024,
});
assert.equal(sealedKey.kdfMode, 'raw-key');
assert.equal(sealedKey.plainBytes, secretPlain.length);
assert.equal(sealedKey.cipherBytes, sealedKey.cipher.length);
assert.equal(sealedKey.chunkSize, 1024);
assert.equal(new TextDecoder().decode(sealedKey.cipher.subarray(0, 8)), 'MLSENC01');
assert.deepEqual(Array.from(sealedKey.cipher.subarray(52, 56)), [0, 0, 0, 0]);

const sealKeyArtifact = client.inspectArtifact(sealedKey.cipher);
assert.equal(sealKeyArtifact.artifact_kind, 'seal-archive');
assert.equal(sealKeyArtifact.artifact_type, 'seal-archive');
assert.equal(sealKeyArtifact.kdf_mode, 0);
assert.equal(sealKeyArtifact.kdf_name, 'raw-key');
assert.equal(sealKeyArtifact.chunk_size, 1024);
assert.equal(sealKeyArtifact.byte_length, sealedKey.cipher.length);
assert.ok(sealKeyArtifact.nonce_prefix_hex.endsWith('00000000'));

const unsealedKey = client.unseal(sealedKey.cipher, { key: rawKey });
assert.equal(unsealedKey.kdfMode, 'raw-key');
assert.equal(unsealedKey.chunkSize, 1024);
assert.equal(unsealedKey.plainBytes, secretPlain.length);
assert.equal(unsealedKey.plainSha256, client.sha256Hex(secretPlain));
assert.deepEqual(unsealedKey.plain, secretPlain);

const sealedPass = client.seal(secretPlain, {
  passphrase: 'moonlibsync-060-test-passphrase',
  chunkSize: 1024,
  argon2MemoryKib: 64,
  argon2Passes: 1,
});
assert.equal(sealedPass.kdfMode, 'argon2id');
const sealPassArtifact = client.inspectArtifact(sealedPass.cipher);
assert.equal(sealPassArtifact.artifact_kind, 'seal-archive');
assert.equal(sealPassArtifact.artifact_type, 'seal-archive');
assert.equal(sealPassArtifact.kdf_mode, 1);
assert.equal(sealPassArtifact.kdf_name, 'argon2id');
assert.equal(sealPassArtifact.argon2_memory_kib, 64);
assert.equal(sealPassArtifact.argon2_passes, 1);

const unsealedPass = client.unseal(sealedPass.cipher, {
  passphrase: 'moonlibsync-060-test-passphrase',
});
assert.equal(unsealedPass.kdfMode, 'argon2id');
assert.deepEqual(unsealedPass.plain, secretPlain);

const unsealedPassBytes = client.unseal(sealedPass.cipher, {
  passphrase: enc.encode('moonlibsync-060-test-passphrase'),
});
assert.deepEqual(unsealedPassBytes.plain, secretPlain);

const tamperedCipherBody = sealedKey.cipher.slice();
tamperedCipherBody[tamperedCipherBody.length - 1] ^= 0x01;
assertSyncError(
  () => client.unseal(tamperedCipherBody, { key: rawKey }),
  'AuthenticationFailed',
  'unseal rejects tampered ciphertext body',
);

const tamperedCipherHeader = sealedKey.cipher.slice();
tamperedCipherHeader[30] ^= 0x01; // flips salt byte bound into AAD
assertSyncError(
  () => client.unseal(tamperedCipherHeader, { key: rawKey }),
  'AuthenticationFailed',
  'unseal rejects tampered header AAD',
);

assertSyncError(
  () => client.unseal(sealedKey.cipher, { key: wrongKey }),
  'AuthenticationFailed',
  'unseal rejects wrong raw key',
);

assertSyncError(
  () => client.unseal(sealedPass.cipher, { passphrase: 'wrong-passphrase' }),
  'AuthenticationFailed',
  'unseal rejects wrong passphrase',
);

assertSyncError(
  () => client.unseal(sealedKey.cipher.subarray(0, sealedKey.cipher.length - 5), { key: rawKey }),
  'TruncatedInput',
  'unseal rejects truncated ciphertext',
);

const trailingCipher = new Uint8Array(sealedKey.cipher.length + 1);
trailingCipher.set(sealedKey.cipher, 0);
trailingCipher[sealedKey.cipher.length] = 0x99;
assertSyncError(
  () => client.unseal(trailingCipher, { key: rawKey }),
  'TrailingData',
  'unseal rejects trailing ciphertext byte',
);

const badNoncePrefix = new Uint8Array(12);
badNoncePrefix[11] = 1;
assertSyncError(
  () => client.seal(secretPlain, { key: rawKey, noncePrefix12: badNoncePrefix }),
  /^InvalidOptions(:|$)/,
  'seal rejects non-zero trailing 4 bytes in noncePrefix12',
);

assertSyncError(
  () =>
    client.seal(secretPlain, /** @type {never} */ ({
      key: rawKey,
      passphrase: 'both-should-fail',
    })),
  'InvalidOptions:secret',
  'seal rejects simultaneous key and passphrase',
);

// 15. [Red-Team Audit #3] Adversarial hardening regression tests.
// 15a. client.seal rejects explicit 0 or negative chunkSize / argon2MemoryKib / argon2Passes.
assertSyncError(
  () => client.seal(secretPlain, { key: rawKey, chunkSize: 0 }),
  /^InvalidOptions(:|$)/,
  'seal rejects chunkSize: 0',
);
assertSyncError(
  () => client.seal(secretPlain, { key: rawKey, chunkSize: -1 }),
  /^InvalidOptions(:|$)/,
  'seal rejects chunkSize: -1',
);
assertSyncError(
  () => client.seal(secretPlain, { passphrase: 'pw', argon2MemoryKib: 0 }),
  /^InvalidOptions(:|$)/,
  'seal rejects argon2MemoryKib: 0',
);
assertSyncError(
  () => client.seal(secretPlain, { passphrase: 'pw', argon2MemoryKib: -1 }),
  /^InvalidOptions(:|$)/,
  'seal rejects argon2MemoryKib: -1',
);
assertSyncError(
  () => client.seal(secretPlain, { passphrase: 'pw', argon2Passes: 0 }),
  /^InvalidOptions(:|$)/,
  'seal rejects argon2Passes: 0',
);
assertSyncError(
  () => client.seal(secretPlain, { passphrase: 'pw', argon2Passes: -1 }),
  /^InvalidOptions(:|$)/,
  'seal rejects argon2Passes: -1',
);

// 15b. Explicit modulePath must NOT silently fall back to _build when missing.
await assert.rejects(
  () => loadMoonLibSync({ modulePath: './definitely-missing-module.js' }),
  (err) => {
    assert.ok(err instanceof MoonLibSyncError, 'expected MoonLibSyncError');
    assert.equal(err.code, 'LoadFailed');
    assert.match(err.message, /definitely-missing-module\.js/);
    return true;
  },
);

// 15c. createDirSnapshot rejects file-vs-dir prefix, intermediate dir case collision, and Windows reserved names.
assertSyncError(
  () =>
    client.createDirSnapshot([
      makeEntry('dir', 'file-content'),
      makeEntry('dir/child.txt', 'child-content'),
    ]),
  /path_collision/,
  'createDirSnapshot rejects file-vs-dir ancestor collision',
);
assertSyncError(
  () =>
    client.createDirSnapshot([
      makeEntry('DIR/b.txt', 'b'),
      makeEntry('dir/a.txt', 'a'),
    ]),
  /path_collision/,
  'createDirSnapshot rejects intermediate dir case-folding collision',
);
assertSyncError(
  () => client.createDirSnapshot([makeEntry('NUL', 'reserved')]),
  /InvalidField:path/,
  'createDirSnapshot rejects Windows reserved device name NUL',
);

// 15d. applyPatchOrGzip succeeds on a Schema 2 full-file TransferManifest whose target IS a .gz file.
const gzTargetPayload = client.compressGzip(
  enc.encode('schema2-full-file-target-is-itself-gzip-'.repeat(24)),
  { level: 6 },
);
const gzTargetDigest = {
  byte_length: String(gzTargetPayload.length),
  sha256: client.sha256Hex(gzTargetPayload),
};
const schema2FullGzTargetManifest = {
  schema_version: 2,
  kind: 'full-file',
  payload: gzTargetDigest,
  result: gzTargetDigest,
};
const patchedFullGzTarget = client.applyPatchOrGzip(
  oldBytes,
  gzTargetPayload,
  schema2FullGzTargetManifest,
);
assert.deepEqual(patchedFullGzTarget.bytes, gzTargetPayload);
assert.equal(patchedFullGzTarget.sha256, gzTargetDigest.sha256);
assert.equal(patchedFullGzTarget.decompressedGzip, false);
assert.equal(patchedFullGzTarget.verifiedManifest, true);

// 15e. inspectDeltaDetailed decodes true UTF-8 multi-byte text ("你好") in preview_utf8.
const utf8Basis = enc.encode('Z'.repeat(2048));
const utf8Literal = enc.encode('你好世界-utf8');
const utf8Target = new Uint8Array(utf8Basis.length + utf8Literal.length);
utf8Target.set(utf8Basis, 0);
utf8Target.set(utf8Literal, utf8Basis.length);
const utf8Sig = client.createSignature(utf8Basis, { blockLen: 512, strongSumLen: 16 });
const utf8Delta = client.createDelta(utf8Sig, utf8Target);
const utf8Detailed = client.inspectDeltaDetailed(utf8Delta, { maxItems: 64 });
const utf8LitItem = utf8Detailed.items.find((it) => it.kind === 'literal');
assert.ok(utf8LitItem, 'expected literal item in UTF-8 delta');
assert.ok(
  typeof utf8LitItem.preview_utf8 === 'string' && utf8LitItem.preview_utf8.includes('你好'),
  `expected preview_utf8 to contain "你好", got ${JSON.stringify(utf8LitItem.preview_utf8)}`,
);
assert.equal(utf8LitItem.preview_utf8, '你好世界-utf8');

// 15f. Circular objects / BigInt passed into SDK JSON serializers throw MoonLibSyncError('InvalidOptions:...').
const circularObj = /** @type {Record<string, unknown>} */ ({});
circularObj.self = circularObj;
assertSyncError(
  () => client.planDirSnapshots(circularObj, snapTarget),
  /^InvalidOptions(:|$)/,
  'planDirSnapshots wraps circular JSON.stringify TypeError',
);
assertSyncError(
  () => client.applyPatchOrGzip(oldBytes, deltaBytes, /** @type {never} */ ({ big: 1n })),
  /^InvalidOptions(:|$)/,
  'applyPatchOrGzip wraps BigInt JSON.stringify TypeError',
);

console.log('JS_SDK_OK');
