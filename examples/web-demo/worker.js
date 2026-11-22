// SPDX-License-Identifier: LGPL-2.1-or-later
const IS_REPO_LOCAL = self.location.pathname.includes('/examples/web-demo/');
const MODULE_PATHS = IS_REPO_LOCAL
  ? [
      '../../_build/js/release/build/examples/web-demo/web-demo.js',
      '../../_build/js/debug/build/examples/web-demo/web-demo.js',
      '../../_build/js/debug/build/YKDshaxing/moonlibsync/examples/web-demo/web-demo.js',
      './web-demo.js',
    ]
  : [
      './web-demo.js',
      '../../_build/js/release/build/examples/web-demo/web-demo.js',
      '../../_build/js/debug/build/examples/web-demo/web-demo.js',
      '../../_build/js/debug/build/YKDshaxing/moonlibsync/examples/web-demo/web-demo.js',
    ];

let coreMod = null;
let loadedPath = '';

async function loadCore() {
  if (coreMod) {
    return { loadedPath, exportCount: Object.keys(coreMod).length };
  }
  let lastErr = null;
  for (const path of MODULE_PATHS) {
    try {
      coreMod = await import(path);
      loadedPath = path;
      return { loadedPath, exportCount: Object.keys(coreMod).length };
    } catch (err) {
      lastErr = err;
    }
  }
  throw lastErr || new Error('Failed to load compiled MoonLibSync web-demo.js');
}

self.addEventListener('message', async (event) => {
  const msg = event.data || {};
  const id = msg.id;
  const method = msg.method;
  const args = Array.isArray(msg.args) ? msg.args : [];

  try {
    if (method === '__init__') {
      self.postMessage({ type: 'progress', id, phase: 'init', pct: 35 });
      const info = await loadCore();
      self.postMessage({ type: 'progress', id, phase: 'init', pct: 100 });
      self.postMessage({ id, ok: true, result: info });
      return;
    }

    await loadCore();
    const fn = coreMod[method];
    if (typeof fn !== 'function') {
      throw new Error(`Unknown MoonLibSync export: ${String(method)}`);
    }

    self.postMessage({ type: 'progress', id, phase: method, pct: 30 });
    const result = fn(...args);
    self.postMessage({ type: 'progress', id, phase: method, pct: 100 });
    self.postMessage({ id, ok: true, result });
  } catch (err) {
    self.postMessage({
      id,
      ok: false,
      error: err instanceof Error ? err.message : String(err),
    });
  }
});
