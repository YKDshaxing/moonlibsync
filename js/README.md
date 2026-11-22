# `@ykdshaxing/moonlibsync`

Pure MoonBit `librsync`-compatible binary delta, bounded RFC 1952 Gzip, and Schema 3 directory sync SDK for Node.js and browsers — zero C FFI, zero npm runtime dependencies, full TypeScript types.

## Features

- **Wire-compatible `librsync` delta sync** (`0x72730147` RK+BLAKE2b signatures, `0x72730236` deltas, streaming sync diagnostics, block-size benchmarking).
- **Bounded RFC 1952 Gzip framing** with deterministic zip-bomb (`LimitExceeded`), trailing-byte (`TrailingData`), and truncated-frame (`TruncatedInput`) protection.
- **Verified patch & auto-decompression** (`applyPatchOrGzip`) supporting raw `.delta`, `.delta.gz`, and Schema 1/2 SHA-256 manifest verification.
- **Schema 3 directory sync planning & verification** (`createDirSnapshot` with POSIX glob `excludes`, `planDirSnapshots`, `verifyDirSnapshots`).
- **Universal artifact inspection** (`inspectArtifact`, `inspectDeltaDetailed`) for `.sig`, `.delta`, `.gz`, `.mbundle`, and Schema 1/2/3 JSON documents.

## Quick Start (Node.js)

```js
import { loadMoonLibSync, MoonLibSyncError } from '@ykdshaxing/moonlibsync';

const sync = await loadMoonLibSync();
const enc = new TextEncoder();

const oldBytes = enc.encode('hello moonlibsync v1 '.repeat(512));
const newBytes = enc.encode('hello moonlibsync v2 '.repeat(512));

// 1. Signature -> Delta -> Patch
const sig = sync.createSignature(oldBytes, { blockLen: 0, strongSumLen: 16 });
const delta = sync.createDelta(sig, newBytes);
const restored = sync.applyPatch(oldBytes, delta);
console.log('SHA-256 match:', sync.sha256Hex(restored) === sync.sha256Hex(newBytes));

// 2. Bounded Gzip framing + verified patch
const deltaGz = sync.compressGzip(delta, { level: 6 });
const patched = sync.applyPatchOrGzip(oldBytes, deltaGz);
console.log('Decompressed gzip:', patched.decompressedGzip, 'sha256:', patched.sha256);

// 3. Zip-bomb rejection throws MoonLibSyncError('LimitExceeded')
try {
  const bomb = sync.compressGzip(new Uint8Array(262144));
  sync.decompressGzip(bomb, { maxOutput: 4096 });
} catch (err) {
  if (err instanceof MoonLibSyncError) {
    console.log('Blocked:', err.code); // "LimitExceeded"
  }
}
```

## Schema 3 Directory Sync & Verification

```js
import { loadMoonLibSync } from '@ykdshaxing/moonlibsync';

const sync = await loadMoonLibSync();
const enc = new TextEncoder();
const entry = (path, text) => {
  const bytes = enc.encode(text);
  return { path, byte_length: bytes.length, sha256: sync.sha256Hex(bytes) };
};

const basis = sync.createDirSnapshot(
  [entry('a.txt', 'v1'), entry('debug.log', 'temp'), entry('old.bin', 'x')],
  { excludes: ['.git', '*.log'] },
);
const target = sync.createDirSnapshot([
  entry('a.txt', 'v2'),
  entry('new.bin', 'added'),
]);

const plan = sync.planDirSnapshots(basis, target);
console.log(plan.summary); // { unchanged, add, update, delete, transfer_upper_bound_bytes }

const report = sync.verifyDirSnapshots(target, basis);
console.log('Directory matches:', report.ok, 'issues:', report.issues.length);
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
  type SyncResult,
} from '@ykdshaxing/moonlibsync';

const sync = await loadMoonLibSync();
const result: SyncResult = sync.runStreamingSync(oldBytes, newBytes, {
  blockLen: 0,
  strongSumLen: 16,
  chunkSize: 4096,
});
const artifact: ArtifactInspection = sync.inspectArtifact(deltaBytes);
const plan: DirSyncPlan = sync.planDirSnapshots(basisSnapshot, targetSnapshot);
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
