// SPDX-License-Identifier: LGPL-2.1-or-later
const IS_REPO_LOCAL = window.location.pathname.includes('/examples/web-demo/');
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

const I18N = {
  zh: {
    subtitle: '纯 MoonBit 编译的浏览器零后端二进制差分、有界 Gzip 压缩与 Schema 3 目录同步工作台',
    tabFile: '文件增量差分 & Gzip',
    tabDir: '目录同步规划（Schema 3）',
    tabLab: 'Gzip 安全防线实验室',
    fileCardTitle: '流式签名 · 差分 · Gzip 二次压缩 · 校验还原',
    blockSize: '块长',
    chunkSize: '流式分块',
    sumSize: '强校验',
    runSample: '运行内置 128 KiB 二进制示例',
    runLogSample: '运行 64 KiB 日志差分示例（高压缩率）',
    oldLabel: 'OLD 基准文件（旧版本）',
    newLabel: 'NEW 目标文件（新版本）',
    dropHint: '点击选择或拖拽任意本地文件至此',
    localPrivacy: '100% 本地浏览器内计算，绝不上传任何文件数据；导出的 .sig / .delta 与 librsync rdiff 及 CLI 完全兼容。',
    runFiles: '对比所选文件并验证还原',
    dirCardTitle: '浏览器端 Schema 3 目录快照与增量同步规划',
    runDirSample: '运行内置目录变更示例',
    basisDirLabel: 'BASIS 基准目录（旧目录）',
    targetDirLabel: 'TARGET 目标目录（新目录）',
    pickDirHint: '点击选择本地文件夹',
    dirHint: '自动执行 POSIX 路径安全校验、UTF-8 字典序排序与跨平台 ASCII 大小写冲突检测。',
    runDirDiff: '生成 Schema 3 同步计划',
    engineReady: 'MoonBit 纯 JS 引擎已就绪（零后端 · 零 C FFI · librsync + 有界 Gzip + Schema 3）',
    engineMissing: '未找到已编译模块 web-demo.js。请先在仓库根目录运行 moon build examples/web-demo --target js 并通过本地 HTTP 服务访问。',
    pickBothWarn: '请先选择 OLD 和 NEW 两个文件，或直接点击上方「运行内置示例」。',
    pickDirWarn: '请至少选择一个本地目录（BASIS 或 TARGET），或直接点击「运行内置目录变更示例」。',
    savedLabel: '带宽节省（Delta + Gzip）',
    verifiedBadge: 'SHA-256 逐字节校验通过',
    mismatchBadge: 'SHA-256 不一致',
    bandwidthTitle: '传输体积对比 & 块复用率',
    fullBar: '全量传输 NEW',
    deltaBar: '标准 librsync Delta',
    gzBar: 'Delta + RFC 1952 Gzip',
    copyBarLabel: 'COPY 块复用占比',
    downloadsTitle: '导出标准产物 & SHA-256 完整性凭证',
    dlSig: '下载 .sig',
    dlDelta: '下载 .delta',
    dlDeltaGz: '下载 .delta.gz',
    dlRestored: '下载还原后的 NEW',
    wireInspect: '展开查看标准线缆头部十六进制（Hex Preview）',
    copyBtn: '复制',
    copiedBtn: '已复制 ✓',
    allFilter: '全部',
    searchPlaceholder: '按 POSIX 路径过滤...',
    pathCol: 'POSIX 相对路径',
    actionCol: '同步动作',
    basisCol: '旧文件大小',
    targetCol: '新文件大小',
    emptyDir: '空目录（无文件条目）',
    filesSelected: (n, b) => `已选择 ${n} 个文件（${b}）`,
    cliFileTitle: '等价 Native CLI 命令（支持 > 64 MiB 流式管道）',
    cliDirTitle: '等价 Native CLI 端到端目录增量分发闭环',
    labTitle: '有界 RFC 1952 Gzip 安全防线实测（Zip-Bomb · 尾随数据 · 截断流）',
    runAllLab: '一键运行全部 3 项安全演练',
    labBombTitle: '1. Zip-Bomb 解压炸弹拦截',
    labBombDesc: '现场生成 256 KiB 零字节高压缩炸弹（仅约 300 B），以 4 KiB 解压上限执行有界解压，验证引擎在超出预算瞬间中断并报 LimitExceeded。',
    labBombBtn: '触发 Zip-Bomb 测试',
    labTrailTitle: '2. 尾随垃圾字节拒绝',
    labTrailDesc: '在合法单流 Gzip 尾部追加 1 字节多余载荷（0x42），验证单流严格帧校验立刻返回 TrailingData。',
    labTrailBtn: '触发 TrailingData 测试',
    labTruncTitle: '3. 截断流 / 尾部缺失拒绝',
    labTruncDesc: '截去 RFC 1952 尾部 CRC32/ISIZE 校验的最后 1 字节，验证解码器严格报 TruncatedInput，绝不静默返回不完整数据。',
    labTruncBtn: '触发 TruncatedInput 测试',
    labCustomTitle: '自定义文本有界 Gzip 往返实验室',
    labLevel: '压缩级别',
    labMaxOut: '解压上限 (B)',
    labRunCustom: '压缩并有界解压测试',
  },
  en: {
    subtitle: 'Pure-MoonBit zero-backend browser studio for librsync binary deltas, bounded Gzip framing, and Schema 3 directory sync',
    tabFile: 'File Sync & Gzip',
    tabDir: 'Directory Sync Planner (Schema 3)',
    tabLab: 'Gzip Security Lab',
    fileCardTitle: 'Streaming Signature · Delta · Gzip Framing · Verified Patch',
    blockSize: 'Block',
    chunkSize: 'Chunk',
    sumSize: 'Strong Sum',
    runSample: 'Run Built-in 128 KiB Binary Sample',
    runLogSample: 'Run 64 KiB Log Delta Sample (High Gzip Ratio)',
    oldLabel: 'OLD Basis File',
    newLabel: 'NEW Target File',
    dropHint: 'Click to browse or drag & drop a local file',
    localPrivacy: '100% local in-browser execution with zero uploads. Exported .sig / .delta files are wire-compatible with librsync rdiff and CLI.',
    runFiles: 'Diff & Verify Selected Files',
    dirCardTitle: 'In-Browser Schema 3 Directory Snapshot & Sync Planner',
    runDirSample: 'Run Built-in Sample Folder Pair',
    basisDirLabel: 'BASIS Folder (Old)',
    targetDirLabel: 'TARGET Folder (New)',
    pickDirHint: 'Click to select a local folder',
    dirHint: 'Enforces POSIX path hygiene, deterministic UTF-8 byte sorting, and cross-platform ASCII case-folding collision detection.',
    runDirDiff: 'Generate Schema 3 Sync Plan',
    engineReady: 'MoonBit pure-JS engine ready (zero backend · zero C FFI · librsync + bounded Gzip + Schema 3)',
    engineMissing: 'Compiled web-demo.js not found. Run "moon build examples/web-demo --target js" and serve the repo root over HTTP.',
    pickBothWarn: 'Please select both OLD and NEW files, or click a built-in sample button above.',
    pickDirWarn: 'Select at least one folder (BASIS or TARGET), or click "Run Built-in Sample Folder Pair".',
    savedLabel: 'Bandwidth Saved (Delta + Gzip)',
    verifiedBadge: 'Bit-Exact SHA-256 Verified',
    mismatchBadge: 'SHA-256 Mismatch',
    bandwidthTitle: 'Wire Size Comparison & Block Reuse',
    fullBar: 'Full NEW Transfer',
    deltaBar: 'Standard librsync Delta',
    gzBar: 'Delta + RFC 1952 Gzip',
    copyBarLabel: 'COPY Block Reuse',
    downloadsTitle: 'Download Standard Artifacts & SHA-256 Integrity Digests',
    dlSig: 'Download .sig',
    dlDelta: 'Download .delta',
    dlDeltaGz: 'Download .delta.gz',
    dlRestored: 'Download Restored NEW',
    wireInspect: 'Inspect Standard Wire Headers (Hex Preview)',
    copyBtn: 'Copy',
    copiedBtn: 'Copied ✓',
    allFilter: 'All',
    searchPlaceholder: 'Filter by POSIX path...',
    pathCol: 'POSIX Relative Path',
    actionCol: 'Action',
    basisCol: 'Basis Size',
    targetCol: 'Target Size',
    emptyDir: 'Empty directories (no entries)',
    filesSelected: (n, b) => `${n} file(s) selected (${b})`,
    cliFileTitle: 'Equivalent Native CLI Commands (Supports > 64 MiB --streaming)',
    cliDirTitle: 'Equivalent Native CLI End-to-End Directory Bundle Pipeline',
    labTitle: 'Bounded RFC 1952 Gzip Security Defense Lab (Zip-Bomb · Trailing · Truncated)',
    runAllLab: 'Run All 3 Security Drills',
    labBombTitle: '1. Zip-Bomb Decompression Guard',
    labBombDesc: 'Compresses 256 KiB of zeros (~300 B gzip bomb) live in-browser and decompresses under a 4 KiB cap, proving immediate LimitExceeded cutoff.',
    labBombBtn: 'Run Zip-Bomb Drill',
    labTrailTitle: '2. Trailing Garbage Rejection',
    labTrailDesc: 'Appends 1 extra byte (0x42) after a valid single-member RFC 1952 gzip trailer, proving strict TrailingData rejection.',
    labTrailBtn: 'Run TrailingData Drill',
    labTruncTitle: '3. Truncated Trailer Rejection',
    labTruncDesc: 'Removes the final byte of the CRC32/ISIZE trailer, proving TruncatedInput rejection with zero silent partial output.',
    labTruncBtn: 'Run TruncatedInput Drill',
    labCustomTitle: 'Custom Text Bounded Gzip Round-Trip Playground',
    labLevel: 'Level',
    labMaxOut: 'Max Output (B)',
    labRunCustom: 'Compress & Bounded Decompress',
  },
};

let lang = (navigator.language || '').toLowerCase().startsWith('zh') ? 'zh' : 'en';
let theme = window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
let engine = null;
let lastResultState = null;
let lastArtifacts = null;
let lastDirState = null;
let currentDirFilter = 'all';
let currentDirSearch = '';

const statusBar = document.getElementById('statusBar');
const statusText = document.getElementById('statusText');
const statusAction = document.getElementById('statusAction');
const resultsEl = document.getElementById('results');
const dirResultsEl = document.getElementById('dirResults');
const oldInput = document.getElementById('oldFile');
const newInput = document.getElementById('newFile');
const oldMeta = document.getElementById('oldMeta');
const newMeta = document.getElementById('newMeta');
const oldDrop = document.getElementById('oldDrop');
const newDrop = document.getElementById('newDrop');
const blockSelect = document.getElementById('blockLen');
const chunkSelect = document.getElementById('chunkSize');
const sumSelect = document.getElementById('sumLen');
const sampleBtn = document.getElementById('runSample');
const logSampleBtn = document.getElementById('runLogSample');
const runFilesBtn = document.getElementById('runFiles');
const basisDirInput = document.getElementById('basisDir');
const targetDirInput = document.getElementById('targetDir');
const basisDirMeta = document.getElementById('basisDirMeta');
const targetDirMeta = document.getElementById('targetDirMeta');
const runDirSampleBtn = document.getElementById('runDirSample');
const runDirDiffBtn = document.getElementById('runDirDiff');
const langToggle = document.getElementById('langToggle');
const themeToggle = document.getElementById('themeToggle');

let droppedOldFile = null;
let droppedNewFile = null;

function t(key) {
  return I18N[lang][key];
}

function escapeHtml(text) {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function fmtBytes(n) {
  const v = Number(n);
  if (v < 1024) return `${v.toLocaleString()} B`;
  if (v < 1048576) return `${(v / 1024).toFixed(1)} KiB`;
  return `${(v / 1048576).toFixed(2)} MiB`;
}

function toHexPreview(bytes, maxLen = 28) {
  const n = Math.min(bytes.length, maxLen);
  const parts = [];
  for (let i = 0; i < n; i++) {
    parts.push(bytes[i].toString(16).padStart(2, '0'));
  }
  return parts.join(' ') + (bytes.length > maxLen ? ' ...' : '');
}

function downloadBlob(bytes, filename, mime = 'application/octet-stream') {
  const blob = new Blob([bytes], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const ICON_SUN = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/></svg>';
const ICON_MOON = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79Z"/></svg>';

function applyTheme() {
  document.documentElement.setAttribute('data-theme', theme);
  themeToggle.innerHTML = theme === 'dark' ? ICON_SUN : ICON_MOON;
}

function applyI18n() {
  document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
  for (const el of document.querySelectorAll('[data-i18n]')) {
    const key = el.getAttribute('data-i18n');
    if (I18N[lang][key]) el.textContent = I18N[lang][key];
  }
  langToggle.textContent = lang === 'zh' ? 'English' : '简体中文';
  if (engine) {
    statusText.textContent = t('engineReady');
  }
  if (droppedOldFile || oldInput.files?.[0]) {
    const f = droppedOldFile || oldInput.files[0];
    oldMeta.textContent = `${f.name} (${fmtBytes(f.size)})`;
    oldMeta.classList.add('selected');
  }
  if (droppedNewFile || newInput.files?.[0]) {
    const f = droppedNewFile || newInput.files[0];
    newMeta.textContent = `${f.name} (${fmtBytes(f.size)})`;
    newMeta.classList.add('selected');
  }
  if (lastResultState) renderResult(lastResultState.data, lastResultState.elapsedMs);
  if (lastDirState) renderDirPlan(lastDirState);
}

langToggle.addEventListener('click', () => {
  lang = lang === 'zh' ? 'en' : 'zh';
  applyI18n();
});

themeToggle.addEventListener('click', () => {
  theme = theme === 'dark' ? 'light' : 'dark';
  applyTheme();
});

for (const btn of document.querySelectorAll('.tab-btn')) {
  btn.addEventListener('click', () => {
    const tab = btn.dataset.tab;
    for (const b of document.querySelectorAll('.tab-btn')) {
      b.classList.toggle('active', b === btn);
    }
    for (const p of document.querySelectorAll('.panel')) {
      p.classList.toggle('active', p.id === 'tab-' + tab);
    }
  });
}

function wireDropzone(zoneEl, inputEl, metaEl, onFile) {
  const showFile = (file) => {
    if (!file) return;
    onFile(file);
    metaEl.textContent = `${file.name} (${fmtBytes(file.size)})`;
    metaEl.classList.add('selected');
  };
  inputEl.addEventListener('change', () => showFile(inputEl.files?.[0]));
  zoneEl.addEventListener('dragover', (e) => {
    e.preventDefault();
    zoneEl.classList.add('dragover');
  });
  zoneEl.addEventListener('dragleave', () => zoneEl.classList.remove('dragover'));
  zoneEl.addEventListener('drop', (e) => {
    e.preventDefault();
    zoneEl.classList.remove('dragover');
    const file = e.dataTransfer?.files?.[0];
    if (file) showFile(file);
  });
}

wireDropzone(oldDrop, oldInput, oldMeta, (f) => { droppedOldFile = f; });
wireDropzone(newDrop, newInput, newMeta, (f) => { droppedNewFile = f; });

function updateFolderMeta(inputEl, metaEl) {
  const list = Array.from(inputEl.files || []);
  if (!list.length) return;
  const total = list.reduce((acc, f) => acc + f.size, 0);
  metaEl.textContent = I18N[lang].filesSelected(list.length, fmtBytes(total));
  metaEl.classList.add('selected');
}
basisDirInput.addEventListener('change', () => updateFolderMeta(basisDirInput, basisDirMeta));
targetDirInput.addEventListener('change', () => updateFolderMeta(targetDirInput, targetDirMeta));

async function loadEngine() {
  if (engine) return engine;
  let lastErr = null;
  for (const path of MODULE_PATHS) {
    try {
      engine = await import(path);
      statusBar.className = 'status-bar ok';
      statusText.textContent = t('engineReady');
      statusAction.innerHTML = '';
      return engine;
    } catch (err) {
      lastErr = err;
    }
  }
  statusBar.className = 'status-bar warn';
  statusText.textContent = t('engineMissing');
  throw lastErr;
}

function renderResult(data, elapsedMs) {
  if (!data.ok) {
    resultsEl.innerHTML = `<div class="card err-card"><strong>Error:</strong> <code>${escapeHtml(data.error)}</code></div>`;
    return;
  }
  const oldBytes = Number(data.old_bytes);
  const newBytes = Number(data.new_bytes);
  const sigBytes = Number(data.signature_bytes);
  const deltaBytes = Number(data.delta_bytes);
  const gzBytes = Number(data.gzip_delta_bytes);
  const copyBytes = Number(data.copy_bytes);
  const litBytes = Number(data.literal_bytes);
  const copyPct = newBytes > 0 ? ((copyBytes / newBytes) * 100).toFixed(1) : '100.0';
  const deltaPct = newBytes > 0 ? ((deltaBytes / newBytes) * 100).toFixed(2) : '0.00';
  const gzPct = newBytes > 0 ? ((gzBytes / newBytes) * 100).toFixed(2) : '0.00';
  const savedPct = newBytes > 0 ? Math.max(0, (1 - gzBytes / newBytes) * 100).toFixed(2) : '0.00';
  const gzGain = gzBytes > 0 ? (deltaBytes / gzBytes).toFixed(2) : '1.00';

  const hexSection = lastArtifacts
    ? `
      <details class="wire-box">
        <summary>${escapeHtml(t('wireInspect'))}</summary>
        <div class="hex-grid">
          <div class="hex-card"><div class="hex-title">.sig (0x72730147 · ${sigBytes} B)</div>${escapeHtml(toHexPreview(lastArtifacts.sig))}</div>
          <div class="hex-card"><div class="hex-title">.delta (0x72730236 · ${deltaBytes} B)</div>${escapeHtml(toHexPreview(lastArtifacts.delta))}</div>
          <div class="hex-card"><div class="hex-title">.delta.gz (RFC 1952 · ${gzBytes} B)</div>${escapeHtml(toHexPreview(lastArtifacts.deltaGz))}</div>
        </div>
      </details>
    `
    : '';

  const blockArg = Number(blockSelect.value) === 0 ? 'auto' : String(blockSelect.value);
  const sumArg = String(sumSelect.value);
  const oldName = (lastArtifacts?.baseName || 'old.bin').replaceAll('"', '');
  const newName = (lastArtifacts?.newName || 'new.bin').replaceAll('"', '');
  const cliCmd = [
    `moonlibsync signature "${oldName}" "${oldName}.sig" --streaming --block-size ${blockArg} --sum-size ${sumArg}`,
    `moonlibsync delta "${oldName}.sig" "${newName}" "${oldName}.delta" --streaming`,
    `moonlibsync compress "${oldName}.delta" "${oldName}.delta.gz" --streaming`,
    `moonlibsync decompress "${oldName}.delta.gz" "${oldName}.delta.raw" --streaming`,
    `moonlibsync patch "${oldName}" "${oldName}.delta.raw" "restored-${newName}" --streaming`,
  ].join('\n');

  resultsEl.innerHTML = `
    <div class="result-hero">
      <div class="hero-metric">
        <span class="hero-pct">${savedPct}%</span>
        <span class="hero-desc">${escapeHtml(t('savedLabel'))} · ${fmtBytes(newBytes)} → ${fmtBytes(gzBytes)} (${elapsedMs.toFixed(1)} ms)</span>
      </div>
      <span class="verified-pill ${data.verified ? '' : 'fail'}">
        ${data.verified ? '✓ ' + escapeHtml(t('verifiedBadge')) : '✕ ' + escapeHtml(t('mismatchBadge'))}
      </span>
    </div>

    <div class="pipeline">
      <div class="pipe-step done">
        <div class="pipe-num">Stage 1 · Receiver</div>
        <div class="pipe-name">SignatureHasher</div>
        <div class="pipe-val">${fmtBytes(oldBytes)} → ${fmtBytes(sigBytes)} .sig</div>
      </div>
      <div class="pipe-step done">
        <div class="pipe-num">Stage 2 · Sender</div>
        <div class="pipe-name">DeltaScanner</div>
        <div class="pipe-val">COPY ${copyPct}% → ${fmtBytes(deltaBytes)}</div>
      </div>
      <div class="pipe-step done">
        <div class="pipe-num">Stage 3 · Wire Frame</div>
        <div class="pipe-name">Bounded Gzip</div>
        <div class="pipe-val">${fmtBytes(deltaBytes)} → ${fmtBytes(gzBytes)} (${gzGain}×)</div>
      </div>
      <div class="pipe-step done">
        <div class="pipe-num">Stage 4 · Verify</div>
        <div class="pipe-name">PatchDecoder + SHA-256</div>
        <div class="pipe-val">${fmtBytes(newBytes)} · ${data.verified ? 'MATCH ✓' : 'FAIL'}</div>
      </div>
    </div>

    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-label">OLD Basis</div>
        <div class="stat-value">${fmtBytes(oldBytes)}</div>
        <div class="stat-sub">${oldBytes.toLocaleString()} B</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">NEW Target</div>
        <div class="stat-value">${fmtBytes(newBytes)}</div>
        <div class="stat-sub">${newBytes.toLocaleString()} B</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Signature (.sig)</div>
        <div class="stat-value">${fmtBytes(sigBytes)}</div>
        <div class="stat-sub">block=${escapeHtml(data.block_len)} B · sum=${escapeHtml(data.strong_sum_len)} B</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Delta (.delta)</div>
        <div class="stat-value">${fmtBytes(deltaBytes)}</div>
        <div class="stat-sub">${deltaPct}% of NEW</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Delta + Gzip</div>
        <div class="stat-value">${fmtBytes(gzBytes)}</div>
        <div class="stat-sub">${gzPct}% of NEW (${gzGain}× vs delta)</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Instructions</div>
        <div class="stat-value">${Number(data.instruction_count).toLocaleString()}</div>
        <div class="stat-sub">${escapeHtml(data.copy_commands)} COPY · ${escapeHtml(data.literal_commands)} Literal</div>
      </div>
    </div>

    <div class="card">
      <div class="card-header"><h3 class="card-title">${escapeHtml(t('bandwidthTitle'))}</h3></div>
      <div class="bars-stack">
        <div>
          <div class="bar-item-head"><span>${escapeHtml(t('fullBar'))}</span><span>${newBytes.toLocaleString()} B (100%)</span></div>
          <div class="bar-track"><div class="bar-fill bar-full" style="width:100%"></div></div>
        </div>
        <div>
          <div class="bar-item-head"><span>${escapeHtml(t('deltaBar'))}</span><span>${deltaBytes.toLocaleString()} B (${deltaPct}%)</span></div>
          <div class="bar-track"><div class="bar-fill bar-delta" style="width:${Math.min(100, Math.max(1.5, Number(deltaPct)))}%"></div></div>
        </div>
        <div>
          <div class="bar-item-head"><span>${escapeHtml(t('gzBar'))}</span><span>${gzBytes.toLocaleString()} B (${gzPct}%)</span></div>
          <div class="bar-track"><div class="bar-fill bar-gz" style="width:${Math.min(100, Math.max(1.2, Number(gzPct)))}%"></div></div>
        </div>
        <div>
          <div class="bar-item-head"><span>${escapeHtml(t('copyBarLabel'))}</span><span>COPY ${copyBytes.toLocaleString()} B (${copyPct}%) · Literal ${litBytes.toLocaleString()} B</span></div>
          <div class="bar-copy-track"><div class="bar-copy-fill" style="width:${Math.min(100, Number(copyPct))}%">COPY ${copyPct}%</div></div>
        </div>
      </div>
    </div>

    <div class="card">
      <div class="card-header">
        <h3 class="card-title">${escapeHtml(t('downloadsTitle'))}</h3>
        <div class="controls-row">
          <button id="dlSig" class="btn btn-teal btn-sm" type="button">${escapeHtml(t('dlSig'))}</button>
          <button id="dlDelta" class="btn btn-teal btn-sm" type="button">${escapeHtml(t('dlDelta'))}</button>
          <button id="dlDeltaGz" class="btn btn-teal btn-sm" type="button">${escapeHtml(t('dlDeltaGz'))}</button>
          <button id="dlRestored" class="btn btn-secondary btn-sm" type="button">${escapeHtml(t('dlRestored'))}</button>
        </div>
      </div>
      <div class="hash-list">
        <div class="hash-row">
          <span class="hash-key">OLD SHA-256</span>
          <span class="hash-val">${escapeHtml(data.old_sha256)}</span>
          <button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(data.old_sha256)}" type="button">${escapeHtml(t('copyBtn'))}</button>
        </div>
        <div class="hash-row">
          <span class="hash-key">NEW SHA-256</span>
          <span class="hash-val">${escapeHtml(data.new_sha256)}</span>
          <button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(data.new_sha256)}" type="button">${escapeHtml(t('copyBtn'))}</button>
        </div>
        <div class="hash-row">
          <span class="hash-key">Restored SHA-256</span>
          <span class="hash-val">${escapeHtml(data.restored_sha256)}</span>
          <button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(data.restored_sha256)}" type="button">${escapeHtml(t('copyBtn'))}</button>
        </div>
      </div>
      ${hexSection}
      <div class="cli-wrap">
        <div class="cli-head">
          <span>${escapeHtml(t('cliFileTitle'))}</span>
          <button id="copyFileCli" class="btn btn-secondary btn-sm" type="button">${escapeHtml(t('copyBtn'))}</button>
        </div>
        <pre class="cli-pre">${escapeHtml(cliCmd)}</pre>
      </div>
    </div>
  `;

  document.getElementById('copyFileCli').addEventListener('click', (e) => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(cliCmd);
      e.target.textContent = t('copiedBtn');
      setTimeout(() => { e.target.textContent = t('copyBtn'); }, 1200);
    }
  });

  document.getElementById('dlSig').addEventListener('click', () => {
    if (lastArtifacts) downloadBlob(lastArtifacts.sig, lastArtifacts.baseName + '.sig');
  });
  document.getElementById('dlDelta').addEventListener('click', () => {
    if (lastArtifacts) downloadBlob(lastArtifacts.delta, lastArtifacts.baseName + '.delta');
  });
  document.getElementById('dlDeltaGz').addEventListener('click', () => {
    if (lastArtifacts) {
      downloadBlob(lastArtifacts.deltaGz, lastArtifacts.baseName + '.delta.gz', 'application/gzip');
    }
  });
  document.getElementById('dlRestored').addEventListener('click', () => {
    if (lastArtifacts) downloadBlob(lastArtifacts.restored, 'restored-' + lastArtifacts.newName);
  });
  for (const btn of resultsEl.querySelectorAll('.copy-hash')) {
    btn.addEventListener('click', () => {
      if (navigator.clipboard) {
        navigator.clipboard.writeText(btn.dataset.hash || '');
        btn.textContent = t('copiedBtn');
        setTimeout(() => { btn.textContent = t('copyBtn'); }, 1200);
      }
    });
  }
}

async function runSync(oldBuf, newBuf, baseName = 'sample', newName = 'new.bin') {
  const mod = await loadEngine();
  const blockLen = Number(blockSelect.value);
  const chunkSize = Number(chunkSelect.value);
  const sumLen = Number(sumSelect.value);
  const t0 = performance.now();
  const json = mod.run_streaming_sync_json(oldBuf, newBuf, blockLen, sumLen, chunkSize);
  const elapsed = performance.now() - t0;
  const parsed = JSON.parse(json);
  if (parsed.ok) {
    const sig = mod.create_signature_bytes(oldBuf, blockLen, sumLen);
    const delta = mod.create_delta_bytes(sig, newBuf);
    const deltaGz = mod.compress_gzip_bytes(delta, 6);
    const restored = mod.apply_patch_bytes(oldBuf, delta);
    lastArtifacts = { sig, delta, deltaGz, restored, baseName, newName };
  } else {
    lastArtifacts = null;
  }
  lastResultState = { data: parsed, elapsedMs: elapsed };
  renderResult(parsed, elapsed);
}

async function runBuiltInBinarySample() {
  const oldBuf = new Uint8Array(131072);
  for (let i = 0; i < oldBuf.length; i++) {
    oldBuf[i] = (i * 73 + 19 + Math.floor(i / 2048) * 11) % 256;
  }
  const newBuf = new Uint8Array(oldBuf.length);
  newBuf.set(oldBuf);
  const patch = new TextEncoder().encode(
    'MOONLIBSYNC-BROWSER-CHUNKED-PATCH-REPEATED-LOG-LINE '.repeat(12),
  );
  newBuf.set(patch, 65536);
  await runSync(oldBuf, newBuf, 'sample-128k', 'sample-new.bin');
}

sampleBtn.addEventListener('click', runBuiltInBinarySample);

logSampleBtn.addEventListener('click', async () => {
  const enc = new TextEncoder();
  const lines = [];
  for (let i = 0; i < 800; i++) {
    lines.push(`2026-11-22T08:${String(i % 60).padStart(2, '0')}:00Z INFO moonlibsync-worker block=${i} status=ok latency_ms=1.2\n`);
  }
  const oldText = lines.join('');
  lines.splice(400, 0,
    ...Array.from({ length: 40 }, (_, k) =>
      `2026-11-22T09:15:${String(k).padStart(2, '0')}Z WARN moonlibsync-worker retry=1 node=edge-${k % 4} action=delta-sync\n`,
    ),
  );
  const newText = lines.join('');
  await runSync(enc.encode(oldText), enc.encode(newText), 'service-log', 'service-log-v2.log');
});

runFilesBtn.addEventListener('click', async () => {
  const oldFile = droppedOldFile || oldInput.files?.[0];
  const newFile = droppedNewFile || newInput.files?.[0];
  if (!oldFile || !newFile) {
    resultsEl.innerHTML = `<div class="card err-card">${escapeHtml(t('pickBothWarn'))}</div>`;
    return;
  }
  const [oldArr, newArr] = await Promise.all([oldFile.arrayBuffer(), newFile.arrayBuffer()]);
  await runSync(new Uint8Array(oldArr), new Uint8Array(newArr), oldFile.name, newFile.name);
});

function normalizeRelativeFolderFiles(fileList) {
  const files = Array.from(fileList || []);
  return files.map((file) => {
    const raw = (file.webkitRelativePath || file.name).replaceAll('\\', '/');
    const slash = raw.indexOf('/');
    const rel = slash >= 0 ? raw.slice(slash + 1) : raw;
    return { rel, file };
  });
}

function badgeClassForKind(kind) {
  if (kind === 'unchanged') return 'badge badge-unchanged';
  if (kind === 'add-full') return 'badge badge-add';
  if (kind === 'update-candidate') return 'badge badge-update';
  return 'badge badge-delete';
}

function renderDirPlan(state) {
  const { planText, basisSnapText, targetSnapText, elapsedMs } = state;
  const plan = JSON.parse(planText);
  if (plan.ok === false) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Directory plan error:</strong> <code>${escapeHtml(plan.error)}</code></div>`;
    return;
  }
  const s = plan.summary;
  const q = currentDirSearch.trim().toLowerCase();
  const filtered = plan.actions.filter((a) => {
    if (currentDirFilter !== 'all' && a.kind !== currentDirFilter) return false;
    if (q && !a.path.toLowerCase().includes(q)) return false;
    return true;
  });

  const rows = filtered
    .map((a) => {
      const bLen = a.basis ? fmtBytes(a.basis.byte_length) : '—';
      const tLen = a.target ? fmtBytes(a.target.byte_length) : '—';
      return `<tr>
        <td><code>${escapeHtml(a.path)}</code></td>
        <td><span class="${badgeClassForKind(a.kind)}">${escapeHtml(a.kind)}</span></td>
        <td>${bLen}</td>
        <td>${tLen}</td>
      </tr>`;
    })
    .join('');

  const filterKinds = [
    ['all', `${t('allFilter')} (${plan.actions.length})`],
    ['unchanged', `unchanged (${s.unchanged})`],
    ['add-full', `add-full (${s.add})`],
    ['update-candidate', `update-candidate (${s.update})`],
    ['delete', `delete (${s.delete})`],
  ];
  const pillsHtml = filterKinds
    .map(
      ([k, label]) =>
        `<button class="filter-pill ${currentDirFilter === k ? 'active' : ''}" data-kind="${k}" type="button">${escapeHtml(label)}</button>`,
    )
    .join('');

  dirResultsEl.innerHTML = `
    <div class="stats-grid cols-5">
      <div class="stat-card"><div class="stat-label">Unchanged</div><div class="stat-value">${escapeHtml(s.unchanged)}</div></div>
      <div class="stat-card"><div class="stat-label">Add Full</div><div class="stat-value" style="color:var(--emerald-text)">${escapeHtml(s.add)}</div></div>
      <div class="stat-card"><div class="stat-label">Update Candidate</div><div class="stat-value" style="color:var(--amber-text)">${escapeHtml(s.update)}</div></div>
      <div class="stat-card"><div class="stat-label">Delete</div><div class="stat-value" style="color:var(--rose-text)">${escapeHtml(s.delete)}</div></div>
      <div class="stat-card"><div class="stat-label">Transfer Upper Bound</div><div class="stat-value">${fmtBytes(s.transfer_upper_bound_bytes)}</div><div class="stat-sub">${elapsedMs.toFixed(1)} ms</div></div>
    </div>

    <div class="card">
      <div class="card-header">
        <h3 class="card-title">Schema 3 Sync Plan</h3>
        <div class="controls-row">
          <button id="dlPlan" class="btn btn-teal btn-sm" type="button">Download plan.json</button>
          <button id="dlBasisSnap" class="btn btn-secondary btn-sm" type="button">basis-snapshot.json</button>
          <button id="dlTargetSnap" class="btn btn-secondary btn-sm" type="button">target-snapshot.json</button>
        </div>
      </div>

      <div class="filter-bar">
        <div class="pill-group">${pillsHtml}</div>
        <input id="dirSearch" class="search-input" type="search" value="${escapeHtml(currentDirSearch)}" placeholder="${escapeHtml(t('searchPlaceholder'))}" />
      </div>

      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>${escapeHtml(t('pathCol'))}</th>
              <th>${escapeHtml(t('actionCol'))}</th>
              <th>${escapeHtml(t('basisCol'))}</th>
              <th>${escapeHtml(t('targetCol'))}</th>
            </tr>
          </thead>
          <tbody>${rows || `<tr><td colspan="4" style="text-align:center;color:var(--text-subtle)">${escapeHtml(t('emptyDir'))}</td></tr>`}</tbody>
        </table>
      </div>
      <div class="cli-wrap">
        <div class="cli-head">
          <span>${escapeHtml(t('cliDirTitle'))}</span>
          <button id="copyDirCli" class="btn btn-secondary btn-sm" type="button">${escapeHtml(t('copyBtn'))}</button>
        </div>
        <pre class="cli-pre">moonlibsync dir-snapshot ./basis basis.snap.json
moonlibsync dir-signatures ./basis basis.snap.json ./basis-sigs --block-size auto --streaming
moonlibsync dir-pack basis.snap.json ./basis-sigs ./target ./bundle --streaming
moonlibsync dir-apply ./basis ./bundle ./restored --streaming</pre>
      </div>
    </div>
  `;

  document.getElementById('copyDirCli').addEventListener('click', (e) => {
    const dirCli = [
      'moonlibsync dir-snapshot ./basis basis.snap.json',
      'moonlibsync dir-signatures ./basis basis.snap.json ./basis-sigs --block-size auto --streaming',
      'moonlibsync dir-pack basis.snap.json ./basis-sigs ./target ./bundle --streaming',
      'moonlibsync dir-apply ./basis ./bundle ./restored --streaming',
    ].join('\n');
    if (navigator.clipboard) {
      navigator.clipboard.writeText(dirCli);
      e.target.textContent = t('copiedBtn');
      setTimeout(() => { e.target.textContent = t('copyBtn'); }, 1200);
    }
  });

  document.getElementById('dlPlan').addEventListener('click', () => {
    downloadBlob(planText, 'dir-plan.json', 'application/json');
  });
  document.getElementById('dlBasisSnap').addEventListener('click', () => {
    downloadBlob(basisSnapText, 'basis-snapshot.json', 'application/json');
  });
  document.getElementById('dlTargetSnap').addEventListener('click', () => {
    downloadBlob(targetSnapText, 'target-snapshot.json', 'application/json');
  });
  for (const pill of dirResultsEl.querySelectorAll('.filter-pill')) {
    pill.addEventListener('click', () => {
      currentDirFilter = pill.dataset.kind;
      renderDirPlan(lastDirState);
    });
  }
  const searchEl = document.getElementById('dirSearch');
  searchEl.addEventListener('input', () => {
    currentDirSearch = searchEl.value;
    renderDirPlan(lastDirState);
    const nextSearch = document.getElementById('dirSearch');
    if (nextSearch) {
      nextSearch.focus();
      nextSearch.setSelectionRange(currentDirSearch.length, currentDirSearch.length);
    }
  });
}

async function buildSnapshotFromFiles(mod, fileList) {
  const entries = [];
  for (const { rel, file } of normalizeRelativeFolderFiles(fileList)) {
    const bytes = new Uint8Array(await file.arrayBuffer());
    const sha256 = mod.sha256_hex_bytes(bytes);
    entries.push({ path: rel, byte_length: String(bytes.length), sha256 });
  }
  return mod.create_dir_snapshot_json(JSON.stringify(entries));
}

runDirSampleBtn.addEventListener('click', async () => {
  const mod = await loadEngine();
  const enc = new TextEncoder();
  const entryOf = (rel, text) => {
    const b = enc.encode(text);
    return { path: rel, byte_length: String(b.length), sha256: mod.sha256_hex_bytes(b) };
  };
  const t0 = performance.now();
  const basisSnap = mod.create_dir_snapshot_json(
    JSON.stringify([
      entryOf('README.md', '# MoonLibSync\n'),
      entryOf('assets/logo.svg', '<svg viewBox="0 0 28 28">v1</svg>'),
      entryOf('src/engine.mbt', 'pub fn delta() { ... }\n'.repeat(180)),
      entryOf('legacy/deprecated.txt', 'old legacy file'),
    ]),
  );
  const targetSnap = mod.create_dir_snapshot_json(
    JSON.stringify([
      entryOf('README.md', '# MoonLibSync\n'),
      entryOf('assets/logo.svg', '<svg viewBox="0 0 28 28">v2-updated-vector</svg>'),
      entryOf('src/engine.mbt', 'pub fn delta() { ... }\n'.repeat(180) + '// v0.4.0 streaming\n'),
      entryOf('docs/dir-sync.md', '# Schema 3 Directory Sync Guide\n'.repeat(40)),
      entryOf('compress/gzip.mbt', 'pub fn compress_gzip() {}\n'.repeat(30)),
    ]),
  );
  const planText = mod.plan_dir_snapshots_json(basisSnap, targetSnap);
  currentDirFilter = 'all';
  currentDirSearch = '';
  lastDirState = { planText, basisSnapText: basisSnap, targetSnapText: targetSnap, elapsedMs: performance.now() - t0 };
  renderDirPlan(lastDirState);
});

runDirDiffBtn.addEventListener('click', async () => {
  const mod = await loadEngine();
  if (!basisDirInput.files?.length && !targetDirInput.files?.length) {
    dirResultsEl.innerHTML = `<div class="card err-card">${escapeHtml(t('pickDirWarn'))}</div>`;
    return;
  }
  const t0 = performance.now();
  const basisSnap = await buildSnapshotFromFiles(mod, basisDirInput.files);
  const parsedBasis = JSON.parse(basisSnap);
  if (parsedBasis.ok === false) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>BASIS snapshot error:</strong> <code>${escapeHtml(parsedBasis.error)}</code></div>`;
    return;
  }
  const targetSnap = await buildSnapshotFromFiles(mod, targetDirInput.files);
  const parsedTarget = JSON.parse(targetSnap);
  if (parsedTarget.ok === false) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>TARGET snapshot error:</strong> <code>${escapeHtml(parsedTarget.error)}</code></div>`;
    return;
  }
  const planText = mod.plan_dir_snapshots_json(basisSnap, targetSnap);
  currentDirFilter = 'all';
  currentDirSearch = '';
  lastDirState = { planText, basisSnapText: basisSnap, targetSnapText: targetSnap, elapsedMs: performance.now() - t0 };
  renderDirPlan(lastDirState);
});

// Tab 3: Gzip Security Defense Lab
const runAllLabBtn = document.getElementById('runAllLab');
const runBombBtn = document.getElementById('runBombBtn');
const runTrailBtn = document.getElementById('runTrailBtn');
const runTruncBtn = document.getElementById('runTruncBtn');
const labBombOut = document.getElementById('labBombOut');
const labTrailOut = document.getElementById('labTrailOut');
const labTruncOut = document.getElementById('labTruncOut');
const labLevelEl = document.getElementById('labLevel');
const labMaxOutEl = document.getElementById('labMaxOut');
const labInputEl = document.getElementById('labInput');
const runCustomGzipBtn = document.getElementById('runCustomGzip');
const labCustomOut = document.getElementById('labCustomOut');

async function runBombDrill() {
  const mod = await loadEngine();
  const raw = new Uint8Array(262144);
  const gz = mod.compress_gzip_bytes(raw, 6);
  const res = JSON.parse(mod.decompress_gzip_check_json(gz, 4096));
  const ratio = (raw.length / gz.length).toFixed(0);
  labBombOut.className = 'lab-out ' + (!res.ok && res.error === 'LimitExceeded' ? 'blocked' : '');
  labBombOut.textContent = !res.ok
    ? `✓ BLOCKED (${res.error}) — 256 KiB → ${gz.length} B bomb (${ratio}×) stopped at 4,096 B cap`
    : `Unexpected pass: ${JSON.stringify(res)}`;
}

async function runTrailingDrill() {
  const mod = await loadEngine();
  const sample = new TextEncoder().encode('moonlibsync-strict-framing-check');
  const gz = mod.compress_gzip_bytes(sample, 6);
  const forged = new Uint8Array(gz.length + 1);
  forged.set(gz, 0);
  forged[gz.length] = 0x42;
  const res = JSON.parse(mod.decompress_gzip_check_json(forged, 65536));
  labTrailOut.className = 'lab-out ' + (!res.ok && res.error === 'TrailingData' ? 'blocked' : '');
  labTrailOut.textContent = !res.ok
    ? `✓ BLOCKED (${res.error}) — ${gz.length} B valid frame + 1 rogue byte rejected`
    : `Unexpected pass: ${JSON.stringify(res)}`;
}

async function runTruncatedDrill() {
  const mod = await loadEngine();
  const sample = new TextEncoder().encode('moonlibsync-strict-trailer-check');
  const gz = mod.compress_gzip_bytes(sample, 6);
  const trunc = gz.subarray(0, gz.length - 1);
  const res = JSON.parse(mod.decompress_gzip_check_json(trunc, 65536));
  labTruncOut.className = 'lab-out ' + (!res.ok && res.error === 'TruncatedInput' ? 'blocked' : '');
  labTruncOut.textContent = !res.ok
    ? `✓ BLOCKED (${res.error}) — ${trunc.length}/${gz.length} B truncated trailer rejected`
    : `Unexpected pass: ${JSON.stringify(res)}`;
}

async function runCustomGzipDrill() {
  const mod = await loadEngine();
  const raw = new TextEncoder().encode(labInputEl.value || '');
  const level = Number(labLevelEl.value);
  const cap = Math.max(0, Number(labMaxOutEl.value) || 0);
  const gz = mod.compress_gzip_bytes(raw, level);
  const check = JSON.parse(mod.decompress_gzip_check_json(gz, cap));
  if (check.ok) {
    const pct = raw.length > 0 ? ((gz.length / raw.length) * 100).toFixed(1) : '100.0';
    labCustomOut.className = 'lab-out blocked';
    labCustomOut.textContent =
      `✓ OK — raw=${raw.length} B → gzip=${gz.length} B (${pct}%, level=${level}) · decompressed=${check.byte_length} B · sha256=${check.sha256.slice(0, 16)}... · hex=${toHexPreview(gz, 14)}`;
  } else {
    labCustomOut.className = 'lab-out blocked';
    labCustomOut.textContent =
      `✓ GUARD TRIGGERED (${check.error}) — raw=${raw.length} B, gzip=${gz.length} B, max_output cap=${cap} B`;
  }
}

runBombBtn.addEventListener('click', runBombDrill);
runTrailBtn.addEventListener('click', runTrailingDrill);
runTruncBtn.addEventListener('click', runTruncatedDrill);
runCustomGzipBtn.addEventListener('click', runCustomGzipDrill);
runAllLabBtn.addEventListener('click', async () => {
  await runBombDrill();
  await runTrailingDrill();
  await runTruncatedDrill();
  await runCustomGzipDrill();
});

applyTheme();
applyI18n();
loadEngine()
  .then(() => runBuiltInBinarySample())
  .catch(() => {});
