# `@ykdshaxing/moonlibsync`

Pure MoonBit `librsync`-compatible binary delta (Rabin-Karp & Rollsum), reverse delta, bounded RFC 1952 Gzip, Schema 3 directory sync & `.mbundle` archives, Ed25519 publisher signing, and ChaCha20-Poly1305/Argon2id AEAD sealing SDK for Node.js and browsers — zero C FFI, zero npm runtime dependencies, full strict TypeScript types.

## Features

- **Wire-compatible `librsync` delta sync** (`0x72730147` Rabin-Karp+BLAKE2b and `0x72730137` Rollsum+BLAKE2b signatures via `createSignature` / `createSignatureWithProfile`, `0x72730236` forward deltas, `createReverseDelta` rollback deltas, streaming sync diagnostics, and block-size benchmarking).
- **Bounded RFC 1952 Gzip framing** with deterministic zip-bomb (`LimitExceeded`), trailing-byte (`TrailingData`), and truncated-frame (`TruncatedInput`) protection.
- **Verified patch & auto-decompression** (`applyPatchOrGzip`) supporting raw `.delta`, `.delta.gz`, and Schema 1/2 SHA-256 manifest verification.
- **Schema 3 directory sync & `.mbundle` / `.mbundle.gz` archives** (`createDirSnapshot` with POSIX glob `excludes`, `planDirSnapshots` with `detectMoves`, `packDirBundleArchive`, `unpackDirBundleArchive`, `verifyDirSnapshots`).
- **Ed25519 publisher signing & trust verification** (`ed25519KeypairFromSeed`, `ed25519Sign`, `ed25519Verify`) producing and verifying canonical Schema 4 `moonlibsync-signature` documents.
- **Chunked AEAD authenticated encryption (`MLSENC01`)** (`seal`, `unseal`) with ChaCha20-Poly1305 and raw 32-byte keys or Argon2id passphrases, automatic CSPRNG salt/nonce generation, header AAD binding, and fail-closed tamper rejection.
- **Universal artifact & delta inspection** (`inspectArtifact`, `inspectDeltaDetailed` with literal previews) for `.sig` (`0x72730147` & `0x72730137`), `.delta`, `.gz`, `.mbundle`, `.menc` (`seal-archive`), Schema 1/2/3 manifests, and Schema 4 `publisher-signature` JSON.

## Quick Start (Node.js)

```js
import { loadMoonLibSync, MoonLibSyncError } from '@ykdshaxing/moonlibsync';

const sync = await loadMoonLibSync();
const enc = new TextEncoder();

const oldBytes = enc.encode('hello moonlibsync v1 '.repeat(512));
const newBytes = enc.encode('hello moonlibsync v2 '.repeat(512));

// 1. Signature -> Delta -> Patch (default 0x72730147 RK+BLAKE2b)
const sig = sync.createSignature(oldBytes, { blockLen: 0, strongSumLen: 16 });
const delta = sync.createDelta(sig, newBytes);
const restored = sync.applyPatch(oldBytes, delta);
console.log('SHA-256 match:', sync.sha256Hex(restored) === sync.sha256Hex(newBytes));

// 2. Rollsum+BLAKE2b (0x72730137) profile + Reverse Delta (NEW -> OLD rollback)
const rollsumSig = sync.createSignature(oldBytes, {
  blockLen: 512,
  strongSumLen: 16,
  profile: 'rollsum-blake2',
});
const rollsumDelta = sync.createDelta(rollsumSig, newBytes);
const reverseDelta = sync.createReverseDelta(oldBytes, newBytes, {
  blockLen: 0,
  strongSumLen: 16,
});
const rolledBack = sync.applyPatch(newBytes, reverseDelta);
console.log('Rollback match:', sync.sha256Hex(rolledBack) === sync.sha256Hex(oldBytes));

// 3. Bounded Gzip framing + verified patch + zip-bomb rejection
const deltaGz = sync.compressGzip(delta, { level: 6 });
const patched = sync.applyPatchOrGzip(oldBytes, deltaGz);
console.log('Decompressed gzip:', patched.decompressedGzip, 'sha256:', patched.sha256);

try {
  const bomb = sync.compressGzip(new Uint8Array(262144));
  sync.decompressGzip(bomb, { maxOutput: 4096 });
} catch (err) {
  if (err instanceof MoonLibSyncError) {
    console.log('Blocked:', err.code); // "LimitExceeded"
  }
}
```

## Directory Sync, Move Detection & `.mbundle.gz` Pack/Unpack

```js
import { loadMoonLibSync } from '@ykdshaxing/moonlibsync';

const sync = await loadMoonLibSync();
const enc = new TextEncoder();
const entry = (path, text) => {
  const bytes = enc.encode(text);
  return { path, byte_length: bytes.length, sha256: sync.sha256Hex(bytes) };
};

// Snapshot planning with move/rename detection (0-byte copy-from-basis)
const basisSnap = sync.createDirSnapshot(
  [entry('legacy/doc.txt', 'hello'), entry('debug.log', 'ignored')],
  { excludes: ['.git', '*.log'] },
);
const targetSnap = sync.createDirSnapshot([entry('renamed/doc.txt', 'hello')]);

const plan = sync.planDirSnapshots(basisSnap, targetSnap, { detectMoves: true });
console.log(plan.summary); // copy_from_basis: "1", transfer_upper_bound_bytes: "0"

// Single-file .mbundle.gz pack & verified unpack
const basisFiles = [
  { path: 'legacy/doc.txt', bytes: enc.encode('hello world '.repeat(256)) },
  { path: 'config.json', bytes: enc.encode('{"version":1}') },
];
const targetFiles = [
  { path: 'renamed/doc.txt', bytes: enc.encode('hello world '.repeat(256)) },
  { path: 'config.json', bytes: enc.encode('{"version":2}') },
  { path: 'added.txt', bytes: enc.encode('new file') },
];

const packed = sync.packDirBundleArchive(basisFiles, targetFiles, {
  detectMoves: true,
  gzip: true,
});
console.log('Packed .mbundle.gz bytes:', packed.archiveBytes, 'raw:', packed.rawBytes);

const unpacked = sync.unpackDirBundleArchive(basisFiles, packed.archive);
console.log('Restored files:', unpacked.fileCount, 'wasGzip:', unpacked.wasGzip);
```

## Ed25519 Publisher Signing & Verification

```js
import { loadMoonLibSync, MoonLibSyncError } from '@ykdshaxing/moonlibsync';

const sync = await loadMoonLibSync();
const seed = crypto.getRandomValues(new Uint8Array(32));
const keypair = sync.ed25519KeypairFromSeed(seed);
const payload = new TextEncoder().encode('signed release bundle payload');

// Sign payload -> canonical Schema 4 moonlibsync-signature JSON
const { signatureJson, signature } = sync.ed25519Sign(seed, payload);
console.log('Signed by key_id:', signature.key_id);

// Verify against trusted publisher public keys (hex strings or 32-byte Uint8Arrays)
const verified = sync.ed25519Verify(signatureJson, [keypair.publicKeyHex], payload);
console.log('Verified:', verified.verified, 'sha256:', verified.payloadSha256);

// Tampering or untrusted keys throw MoonLibSyncError ("DigestMismatch", "UntrustedKey", "InvalidSignature")
try {
  sync.ed25519Verify(signatureJson, [keypair.publicKey], new Uint8Array([0]));
} catch (err) {
  if (err instanceof MoonLibSyncError) {
    console.log('Rejected:', err.code);
  }
}
```

## AEAD Sealing & Unsealing (`MLSENC01` ChaCha20-Poly1305 + Argon2id)

```js
import { loadMoonLibSync, MoonLibSyncError } from '@ykdshaxing/moonlibsync';

const sync = await loadMoonLibSync();
const plaintext = new TextEncoder().encode('confidential delta artifact');

// Option A: Raw 32-byte key (auto-generates CSPRNG salt16 + noncePrefix12 with 00000000 counter tail)
const key = crypto.getRandomValues(new Uint8Array(32));
const sealed = sync.seal(plaintext, { key, chunkSize: 65536 });
const opened = sync.unseal(sealed.cipher, { key });
console.log('Raw-key roundtrip:', sync.sha256Hex(opened.plain) === opened.plainSha256);

// Option B: Argon2id passphrase mode
const sealedPass = sync.seal(plaintext, {
  passphrase: 'correct-horse-battery-staple',
  argon2MemoryKib: 16384,
  argon2Passes: 2,
});
const info = sync.inspectArtifact(sealedPass.cipher);
console.log('Container:', info.artifact_type, info.kdf_name, 'chunks:', info.chunk_size);

const openedPass = sync.unseal(sealedPass.cipher, {
  passphrase: 'correct-horse-battery-staple',
});
console.log('Decrypted bytes:', openedPass.plainBytes);

// Any byte flip throws MoonLibSyncError('AuthenticationFailed')
try {
  const tampered = sealed.cipher.slice();
  tampered[tampered.length - 1] ^= 0x01;
  sync.unseal(tampered, { key });
} catch (err) {
  if (err instanceof MoonLibSyncError) {
    console.log('Tamper rejected:', err.code); // "AuthenticationFailed"
  }
}
```

## Browser Usage

`index.js` uses zero Node.js static imports and works natively in modern browsers as an ES module:

```js
import { loadMoonLibSync, createClient } from './index.js';

// Option A: automatic resolution relative to index.js (or pass an explicit URL)
const sync = await loadMoonLibSync({ modulePath: './moonlibsync-core.js' });

// Option B: wrap an already-imported core bundle synchronously
import * as core from './moonlibsync-core.js';
const syncFromCore = createClient(core);
```

## TypeScript

Strict TypeScript declarations (`index.d.ts`, zero `any`) are bundled with the package:

```ts
import {
  loadMoonLibSync,
  type ArtifactInspection,
  type DirSyncPlan,
  type PackedBundleArchive,
  type SealResult,
  type SyncResult,
} from '@ykdshaxing/moonlibsync';

const sync = await loadMoonLibSync();
const result: SyncResult = sync.runStreamingSync(oldBytes, newBytes, {
  blockLen: 0,
  strongSumLen: 16,
  chunkSize: 4096,
});
const artifact: ArtifactInspection = sync.inspectArtifact(deltaBytes);
const plan: DirSyncPlan = sync.planDirSnapshots(basisSnapshot, targetSnapshot, {
  detectMoves: true,
});
const bundle: PackedBundleArchive = sync.packDirBundleArchive(basisFiles, targetFiles, {
  detectMoves: true,
  gzip: true,
});
const sealed: SealResult = sync.seal(bundle.archive, { key });
```

## Building & Testing in This Repository

Generate the self-contained release bundle `js/moonlibsync-core.js` before packaging (`npm pack`):

```bash
cd js
npm run build
npm test
```

`loadMoonLibSync()` automatically resolves the compiled MoonBit JS module in order:

1. `options?.modulePath` (if provided)
2. `./moonlibsync-core.js` (published distribution bundle)
3. `MOONLIBSYNC_BUILD_DIR` (when set in Node.js) and `../_build/js/{release,debug}/build/.../web-demo.js`

## License

`LGPL-2.1-or-later` — see repository `COPYING.LESSER`, `LICENSE`, and `THIRD_PARTY_NOTICES.md`.
