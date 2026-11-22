// SPDX-License-Identifier: LGPL-2.1-or-later
const MODULE_PATHS = [
  '../../_build/js/debug/build/examples/web-demo/web-demo.js',
  '../../_build/js/debug/build/YKDshaxing/moonlibsync/examples/web-demo/web-demo.js',
];

const statusEl = document.getElementById('status');
const resultsEl = document.getElementById('results');
const oldInput = document.getElementById('oldFile');
const newInput = document.getElementById('newFile');
const blockSelect = document.getElementById('blockLen');
const chunkSelect = document.getElementById('chunkSize');
const sampleBtn = document.getElementById('runSample');
const runFilesBtn = document.getElementById('runFiles');

let engine = null;

async function loadEngine() {
  if (engine) return engine;
  let lastErr = null;
  for (const path of MODULE_PATHS) {
    try {
      engine = await import(path);
      statusEl.textContent = 'MoonBit pure-JS engine ready (zero backend, zero C FFI).';
      statusEl.className = 'status ok';
      return engine;
    } catch (err) {
      lastErr = err;
    }
  }
  statusEl.innerHTML =
    'Built JS module not found at <code>' +
    MODULE_PATHS[0] +
    '</code>. Run <code>moon build examples/web-demo --target js</code> and serve repository root over HTTP (e.g. <code>python -m http.server</code>).';
  statusEl.className = 'status warn';
  throw lastErr;
}

function renderResult(data, elapsedMs) {
  if (!data.ok) {
    resultsEl.innerHTML = `<div class="card err">Error: <code>${data.error}</code></div>`;
    return;
  }
  const newBytes = Number(data.new_bytes);
  const deltaBytes = Number(data.delta_bytes);
  const copyBytes = Number(data.copy_bytes);
  const copyPct = newBytes > 0 ? ((copyBytes / newBytes) * 100).toFixed(1) : '100.0';
  const wirePct = newBytes > 0 ? ((deltaBytes / newBytes) * 100).toFixed(2) : '0.00';

  resultsEl.innerHTML = `
    <div class="grid">
      <div class="stat"><div class="label">OLD Bytes</div><div class="value">${Number(data.old_bytes).toLocaleString()}</div></div>
      <div class="stat"><div class="label">NEW Bytes</div><div class="value">${newBytes.toLocaleString()}</div></div>
      <div class="stat"><div class="label">Signature Bytes (block=${data.block_len})</div><div class="value">${Number(data.signature_bytes).toLocaleString()}</div></div>
      <div class="stat"><div class="label">Delta Bytes (${wirePct}% of NEW)</div><div class="value">${deltaBytes.toLocaleString()}</div></div>
      <div class="stat"><div class="label">COPY Reuse (${copyPct}%)</div><div class="value">${copyBytes.toLocaleString()} B (${data.copy_commands} cmds)</div></div>
      <div class="stat"><div class="label">Literal Bytes / Time</div><div class="value">${Number(data.literal_bytes).toLocaleString()} B (${elapsedMs.toFixed(1)} ms)</div></div>
    </div>
    <div class="bar-wrap"><div class="bar-copy" style="width:${Math.min(100, Number(copyPct))}%">COPY ${copyPct}%</div></div>
    <div class="card">
      <div><strong>OLD SHA-256:</strong> <code>${data.old_sha256}</code></div>
      <div><strong>NEW SHA-256:</strong> <code>${data.new_sha256}</code></div>
      <div><strong>Restored SHA-256:</strong> <code>${data.restored_sha256}</code></div>
      <div><strong>Verified Bit-Exact Match:</strong> <span class="badge">${data.verified ? 'VERIFIED' : 'MISMATCH'}</span></div>
    </div>
  `;
}

async function runSync(oldBuf, newBuf) {
  const mod = await loadEngine();
  const blockLen = Number(blockSelect.value);
  const chunkSize = Number(chunkSelect.value);
  const t0 = performance.now();
  const json = mod.run_streaming_sync_json(oldBuf, newBuf, blockLen, 16, chunkSize);
  const elapsed = performance.now() - t0;
  renderResult(JSON.parse(json), elapsed);
}

sampleBtn.addEventListener('click', async () => {
  const oldBuf = new Uint8Array(131072);
  for (let i = 0; i < oldBuf.length; i++) {
    oldBuf[i] = (i * 73 + 19 + Math.floor(i / 2048) * 11) % 256;
  }
  const newBuf = new Uint8Array(oldBuf.length);
  newBuf.set(oldBuf);
  const patch = new TextEncoder().encode('MOONLIBSYNC-BROWSER-CHUNKED-PATCH');
  newBuf.set(patch, 65536);
  await runSync(oldBuf, newBuf);
});

runFilesBtn.addEventListener('click', async () => {
  const oldFile = oldInput.files?.[0];
  const newFile = newInput.files?.[0];
  if (!oldFile || !newFile) {
    resultsEl.innerHTML = '<div class="card warn">Please select both OLD and NEW files first.</div>';
    return;
  }
  const [oldArr, newArr] = await Promise.all([oldFile.arrayBuffer(), newFile.arrayBuffer()]);
  await runSync(new Uint8Array(oldArr), new Uint8Array(newArr));
});

loadEngine().catch(() => {});
