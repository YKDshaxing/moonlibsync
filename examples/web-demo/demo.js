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
    subtitle: '纯 MoonBit 编译的浏览器零后端二进制差分、块复用热力图、独立 rdiff、通用产物剖析与 Schema 3 目录同步巡检工作台',
    tabFile: '文件差分 & Gzip',
    tabRdiff: '独立角色在线工具',
    tabInspect: '通用产物剖析器',
    tabDir: '目录同步规划 & 巡检',
    tabLab: 'Gzip 安全防线实验室',
    fileCardTitle: '流式签名 · 差分 · Gzip 二次压缩 · 块复用热力图 · 多块长对比',
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
    heatmapTitle: 'Delta 块复用热力图（Interactive Block Reuse Heatmap）',
    heatmapHint: '悬停或点击上方任意色块，查看对应 COPY / Literal 指令的基线偏移、长度与输出位置',
    heatmapTruncated: (shown, total) => `已展示前 ${shown} / ${total} 条指令`,
    heatmapTableToggle: (n) => `展开指令明细表（前 ${n} 条）`,
    benchTitle: '多块长策略对比（auto / 256 / 512 / 2048 / 4096）',
    benchBtn: '运行多块长对比 (auto / 256 / 512 / 2048 / 4096)',
    benchHint: '在纯 MoonBit 引擎内一次性对比 5 种块长的 .sig、.delta 与 .delta.gz 线缆体积，自动标出最小传输开销。',
    benchBest: '最小线缆体积',
    rdiffSigTitle: '生成标准签名 (.sig)',
    rdiffSigOldLabel: 'OLD 本地旧文件',
    rdiffSigHint: '接收方只需上传轻量 .sig 签名文件给发送方，无需暴露完整旧文件。',
    rdiffGenSigBtn: '生成 .sig 签名',
    rdiffDeltaTitle: '生成增量差分 (.delta / .delta.gz)',
    rdiffDeltaSigLabel: '远端 .sig 签名文件',
    rdiffDeltaNewLabel: 'NEW 本地新文件',
    rdiffDeltaHint: '发送方仅凭 .sig 与 NEW 文件即可算出标准 librsync .delta 与压缩后的 .delta.gz。',
    rdiffGenDeltaBtn: '生成 .delta & .delta.gz',
    rdiffPatchTitle: '应用补丁并校验还原 (自动解压 .delta.gz + 可选 Manifest 校验)',
    rdiffClearManifest: '清除可选 Manifest',
    rdiffPatchOldLabel: 'OLD 旧基准文件',
    rdiffPatchDeltaLabel: '.delta 或 .delta.gz 补丁',
    rdiffPatchManifestLabel: '可选 manifest.json (Schema 1/2)',
    rdiffOptionalHint: '可选：拖入以启用端到端 SHA-256 绑定校验',
    rdiffPatchHint: '自动识别 RFC 1952 Gzip 帧并执行有界解压；提供 Schema 1/2 manifest 时将严格验证 basis / delta / result 三方 SHA-256。',
    rdiffApplyPatchBtn: '应用补丁并校验还原',
    rdiffPickOld: '请先选择 OLD 旧文件。',
    rdiffPickSigNew: '请先同时选择 .sig 签名文件与 NEW 目标文件。',
    rdiffPickOldDelta: '请先同时选择 OLD 旧文件与 .delta / .delta.gz 补丁文件。',
    inspectCardTitle: '通用产物剖析器（.sig · .delta · .delta.gz · .mbundle · Schema 1/2/3 JSON）',
    inspectSampleDelta: '剖析示例 .delta（含热力图）',
    inspectSampleSig: '剖析示例 .sig',
    inspectDropLabel: '拖入任意 MoonLibSync 二进制或 JSON 产物自动剖析',
    inspectDropHint: '支持 .sig / .delta / .delta.gz / .mbundle / manifest.json / snapshot / plan / bundle / verify-report',
    inspectRawJson: '展开原始剖析 JSON 响应',
    inspectInnerDelta: '检测到 Gzip 内层为标准 0x72730236 Delta，已自动展开块复用热力图',
    dirCardTitle: '浏览器端 Schema 3 目录快照、同步规划与完整性巡检',
    dirModePlan: '同步规划 (dir-plan)',
    dirModeVerify: '完整性巡检 (dir-verify)',
    runDirSample: '运行内置目录变更示例',
    runDirVerifyCleanSample: '巡检一致示例 (OK)',
    basisDirLabel: 'BASIS 基准目录（旧目录 / Expected 预期基线）',
    targetDirLabel: 'TARGET 目标目录（新目录 / Actual 实测目录）',
    pickDirHint: '点击选择本地文件夹',
    dirExcludeLabel: '--exclude 排除规则（逗号分隔）',
    fillExcludePreset: '填入常用忽略',
    dirHint: '自动执行 --exclude 匹配、POSIX 路径安全校验、UTF-8 字典序排序与跨平台 ASCII 大小写冲突检测。',
    runDirDiff: '生成 Schema 3 同步计划',
    runDirVerify: '执行 dir-verify 巡检',
    verifyOkBadge: 'VERIFIED OK · 目录完全一致',
    verifyDriftBadge: 'DRIFT DETECTED · 检测到目录漂移',
    verifyNoIssues: '零漂移：所有文件长度与 SHA-256 与预期基线完全匹配。',
    expectedCol: '预期基线 (Expected)',
    actualCol: '实测目录 (Actual)',
    issueKindCol: '漂移类型',
    engineReady: 'MoonBit 纯 JS 引擎已就绪（v0.5.0 · 零后端 · 零 C FFI · 17 项核心导出）',
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
    cliVerifyTitle: '等价 Native CLI 目录完整性巡检命令',
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
    subtitle: 'Pure-MoonBit zero-backend browser studio for librsync binary deltas, block reuse heatmaps, split-role rdiff, universal artifact inspection, and Schema 3 directory sync & verify',
    tabFile: 'File Sync & Gzip',
    tabRdiff: 'Split-Role rdiff',
    tabInspect: 'Artifact Inspector',
    tabDir: 'Dir Plan & Verify',
    tabLab: 'Gzip Security Lab',
    fileCardTitle: 'Streaming Signature · Delta · Gzip Framing · Block Heatmap · Multi-Block Benchmark',
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
    heatmapTitle: 'Interactive Delta Block Reuse Heatmap',
    heatmapHint: 'Hover or click any segment above to inspect COPY / Literal basis offset, length, and output offset',
    heatmapTruncated: (shown, total) => `Showing first ${shown} of ${total} instructions`,
    heatmapTableToggle: (n) => `Show ordered instruction table (top ${n})`,
    benchTitle: 'Multi-Block-Size Benchmark (auto / 256 / 512 / 2048 / 4096)',
    benchBtn: 'Run Multi-Block-Size Benchmark (auto / 256 / 512 / 2048 / 4096)',
    benchHint: 'Evaluate 5 block sizes in pure MoonBit to compare .sig, .delta, and .delta.gz wire overhead and highlight the smallest wire size.',
    benchBest: 'Smallest Wire',
    rdiffSigTitle: 'Generate Standard Signature (.sig)',
    rdiffSigOldLabel: 'OLD Local Basis File',
    rdiffSigHint: 'Receiver generates a compact .sig file to send to the sender without exposing the full basis file.',
    rdiffGenSigBtn: 'Generate .sig',
    rdiffDeltaTitle: 'Generate Binary Delta (.delta / .delta.gz)',
    rdiffDeltaSigLabel: 'Remote .sig Signature File',
    rdiffDeltaNewLabel: 'NEW Local Target File',
    rdiffDeltaHint: 'Sender computes wire-compatible librsync .delta and bounded RFC 1952 .delta.gz from .sig + NEW.',
    rdiffGenDeltaBtn: 'Generate .delta & .delta.gz',
    rdiffPatchTitle: 'Apply Patch & Verify (Auto .delta.gz Decompress + Optional Manifest)',
    rdiffClearManifest: 'Clear Optional Manifest',
    rdiffPatchOldLabel: 'OLD Basis File',
    rdiffPatchDeltaLabel: '.delta or .delta.gz Patch',
    rdiffPatchManifestLabel: 'Optional manifest.json (Schema 1/2)',
    rdiffOptionalHint: 'Optional: drop a Schema 1/2 manifest for strict end-to-end SHA-256 verification',
    rdiffPatchHint: 'Auto-detects RFC 1952 Gzip framing with bounded decompression; verifies basis/delta/result SHA-256 when a manifest is provided.',
    rdiffApplyPatchBtn: 'Apply Patch & Verify',
    rdiffPickOld: 'Please select an OLD basis file first.',
    rdiffPickSigNew: 'Please select both a .sig signature file and a NEW target file.',
    rdiffPickOldDelta: 'Please select both an OLD basis file and a .delta / .delta.gz file.',
    inspectCardTitle: 'Universal Artifact Inspector (.sig · .delta · .delta.gz · .mbundle · Schema 1/2/3 JSON)',
    inspectSampleDelta: 'Inspect Sample .delta (+ Heatmap)',
    inspectSampleSig: 'Inspect Sample .sig',
    inspectDropLabel: 'Drop any MoonLibSync binary or JSON artifact to inspect',
    inspectDropHint: 'Supports .sig / .delta / .delta.gz / .mbundle / manifest.json / snapshot / plan / bundle / verify-report',
    inspectRawJson: 'Show Raw Inspector JSON',
    inspectInnerDelta: 'Inner Gzip payload is a standard 0x72730236 delta — Block Reuse Heatmap rendered below',
    dirCardTitle: 'In-Browser Schema 3 Directory Snapshot, Sync Planner & Integrity Audit',
    dirModePlan: 'Sync Plan (dir-plan)',
    dirModeVerify: 'Integrity Audit (dir-verify)',
    runDirSample: 'Run Built-in Sample Folder Pair',
    runDirVerifyCleanSample: 'Run Clean Verify Sample (OK)',
    basisDirLabel: 'BASIS Folder (Old / Expected Baseline)',
    targetDirLabel: 'TARGET Folder (New / Actual Observed)',
    pickDirHint: 'Click to select a local folder',
    dirExcludeLabel: '--exclude patterns (comma-separated)',
    fillExcludePreset: 'Fill Common Preset',
    dirHint: 'Applies --exclude globs, POSIX path hygiene, deterministic UTF-8 byte sorting, and cross-platform ASCII case-folding collision detection.',
    runDirDiff: 'Generate Schema 3 Sync Plan',
    runDirVerify: 'Run dir-verify Audit',
    verifyOkBadge: 'VERIFIED OK · Exact Directory Match',
    verifyDriftBadge: 'DRIFT DETECTED · Integrity Differences Found',
    verifyNoIssues: 'Zero drift: every file length and SHA-256 matches the expected baseline snapshot.',
    expectedCol: 'Expected Baseline',
    actualCol: 'Actual Observed',
    issueKindCol: 'Drift Kind',
    engineReady: 'MoonBit pure-JS engine ready (v0.5.0 · zero backend · zero C FFI · 17 core exports)',
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
    cliVerifyTitle: 'Equivalent Native CLI Directory Integrity Audit Command',
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

// Tab 1 state
let lastResultState = null;
let lastArtifacts = null;
let lastInputs = null;
let lastDetailState = null;
let lastBenchmarkState = null;

// Tab 3 state
let lastInspectState = null;

// Tab 4 state
let dirMode = 'plan'; // 'plan' | 'verify'
let lastDirState = null;
let currentDirFilter = 'all';
let currentDirSearch = '';

const statusBar = document.getElementById('statusBar');
const statusText = document.getElementById('statusText');
const statusAction = document.getElementById('statusAction');
const resultsEl = document.getElementById('results');
const inspectResultsEl = document.getElementById('inspectResults');
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
const dirExcludeInput = document.getElementById('dirExcludeInput');
const fillExcludePresetBtn = document.getElementById('fillExcludePreset');
const dirModePlanBtn = document.getElementById('dirModePlan');
const dirModeVerifyBtn = document.getElementById('dirModeVerify');
const runDirSampleBtn = document.getElementById('runDirSample');
const runDirVerifyCleanSampleBtn = document.getElementById('runDirVerifyCleanSample');
const runDirDiffBtn = document.getElementById('runDirDiff');
const runDirVerifyBtn = document.getElementById('runDirVerify');
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

function bindCopyButtons(rootEl) {
  for (const btn of rootEl.querySelectorAll('.copy-hash')) {
    btn.addEventListener('click', () => {
      if (navigator.clipboard) {
        navigator.clipboard.writeText(btn.dataset.hash || '');
        btn.textContent = t('copiedBtn');
        setTimeout(() => { btn.textContent = t('copyBtn'); }, 1200);
      }
    });
  }
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
    if (typeof I18N[lang][key] === 'string') el.textContent = I18N[lang][key];
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
  if (lastInspectState) renderInspectResult(lastInspectState);
  if (lastDirState) {
    if (lastDirState.mode === 'verify') renderDirVerify(lastDirState);
    else renderDirPlan(lastDirState);
  }
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

// =========================================================================
// Shared Component: Interactive Delta Block Reuse Heatmap
// =========================================================================
function buildHeatmapCardHtml(detail, prefix) {
  if (!detail || !detail.ok) return '';
  const s = detail.summary;
  const items = detail.items || [];
  const totalOut = Math.max(1, Number(s.output_bytes));
  const minW = items.length > 120 ? '1px' : '3px';

  const displayedBytes = items.reduce((acc, it) => acc + Number(it.length), 0);
  const remBytes = Math.max(0, totalOut - displayedBytes);
  const tailHtml =
    detail.truncated && remBytes > 0
      ? `<div style="flex:${remBytes} 0 auto;min-width:8px;background:repeating-linear-gradient(45deg,var(--border),var(--border) 4px,var(--surface-muted) 4px,var(--surface-muted) 8px);" title="+${remBytes.toLocaleString()} B remaining (truncated)"></div>`
      : '';

  const segsHtml = items.length === 0
    ? `<div style="width:100%;display:grid;place-items:center;font-size:0.78rem;color:var(--text-subtle);">Empty delta (0 B output)</div>`
    : items
        .map((it, idx) => {
          const len = Number(it.length);
          const pct = ((len / totalOut) * 100).toFixed(2);
          const isCopy = it.kind === 'copy';
          const tip = isCopy
            ? `#${idx} COPY | basis_offset=${it.offset} | length=${it.length} B (${pct}%) | out_offset=${it.output_offset}`
            : `#${idx} Literal | length=${it.length} B (${pct}%) | out_offset=${it.output_offset}`;
          return `<button type="button" class="hm-seg ${isCopy ? 'copy' : 'literal'}" data-hm="${prefix}" data-idx="${idx}" style="flex:${Math.max(1, len)} 0 auto;min-width:${minW};" title="${escapeHtml(tip)}" aria-label="${escapeHtml(tip)}"></button>`;
        })
        .join('') + tailHtml;

  const rowsHtml = items
    .map((it, idx) => {
      const isCopy = it.kind === 'copy';
      return `<tr>
        <td><code>#${idx}</code></td>
        <td><span class="badge ${isCopy ? 'badge-add' : 'badge-update'}">${isCopy ? 'COPY' : 'Literal'}</span></td>
        <td><code>${isCopy ? Number(it.offset).toLocaleString() : '—'}</code></td>
        <td><code>${Number(it.length).toLocaleString()} B</code> (${fmtBytes(it.length)})</td>
        <td><code>${Number(it.output_offset).toLocaleString()}</code></td>
      </tr>`;
    })
    .join('');

  const truncBadge = detail.truncated
    ? `<span class="badge badge-info">${escapeHtml(I18N[lang].heatmapTruncated(items.length, s.instruction_count))}</span>`
    : '';

  return `
    <div class="card">
      <div class="card-header">
        <h3 class="card-title">${escapeHtml(t('heatmapTitle'))}</h3>
        ${truncBadge}
      </div>
      <div class="hm-legend">
        <span><span class="hm-dot copy"></span><strong>COPY</strong>: ${Number(s.copy_commands).toLocaleString()} cmds · ${fmtBytes(s.copy_bytes)}</span>
        <span><span class="hm-dot lit"></span><strong>Literal</strong>: ${Number(s.literal_commands).toLocaleString()} cmds · ${fmtBytes(s.literal_bytes)}</span>
        <span>Output: <code>${Number(s.output_bytes).toLocaleString()} B</code></span>
      </div>
      <div class="heatmap-track" role="region" aria-label="Delta block reuse heatmap">${segsHtml}</div>
      <div id="${prefix}-tip" class="heatmap-tooltip">${escapeHtml(t('heatmapHint'))}</div>
      <details class="wire-box">
        <summary>${escapeHtml(I18N[lang].heatmapTableToggle(items.length))}</summary>
        <div class="table-wrap" style="margin-top:0.65rem;max-height:280px;overflow:auto;">
          <table>
            <thead>
              <tr>
                <th>#</th>
                <th>Kind</th>
                <th>Basis Offset</th>
                <th>Length</th>
                <th>Output Offset</th>
              </tr>
            </thead>
            <tbody>${rowsHtml || '<tr><td colspan="5" style="text-align:center;color:var(--text-subtle);">No instructions</td></tr>'}</tbody>
          </table>
        </div>
      </details>
    </div>
  `;
}

function wireHeatmapEvents(rootEl, detail, prefix) {
  if (!detail || !detail.ok) return;
  const tipEl = rootEl.querySelector(`#${prefix}-tip`);
  if (!tipEl) return;
  const items = detail.items || [];
  const totalOut = Math.max(1, Number(detail.summary.output_bytes));
  const showItem = (idx, btn) => {
    const it = items[idx];
    if (!it) return;
    for (const s of rootEl.querySelectorAll(`.hm-seg[data-hm="${prefix}"]`)) {
      s.classList.toggle('active', s === btn);
    }
    const isCopy = it.kind === 'copy';
    const len = Number(it.length);
    const outStart = Number(it.output_offset);
    const outEnd = outStart + len;
    const pct = ((len / totalOut) * 100).toFixed(2);
    tipEl.innerHTML = `
      <span class="badge ${isCopy ? 'badge-add' : 'badge-update'}">#${idx} ${isCopy ? 'COPY' : 'Literal'}</span>
      ${isCopy ? `<span>offset=<strong>${Number(it.offset).toLocaleString()}</strong></span>` : '<span>offset=<strong>—</strong></span>'}
      <span>length=<strong>${len.toLocaleString()} B</strong> (${fmtBytes(len)}, ${pct}%)</span>
      <span>output_offset=<strong>${outStart.toLocaleString()}..${outEnd.toLocaleString()}</strong></span>
    `;
  };
  for (const btn of rootEl.querySelectorAll(`.hm-seg[data-hm="${prefix}"]`)) {
    const idx = Number(btn.dataset.idx);
    btn.addEventListener('mouseenter', () => showItem(idx, btn));
    btn.addEventListener('focus', () => showItem(idx, btn));
    btn.addEventListener('click', () => showItem(idx, btn));
  }
}

// =========================================================================
// Tab 1: File Sync, Heatmap & Multi-Block-Size Benchmark
// =========================================================================
function buildBenchmarkContentHtml(bench) {
  if (!bench) return '';
  if (!bench.ok) {
    return `<div class="card err-card" style="margin-top:0.8rem;margin-bottom:0;"><strong>Benchmark Error:</strong> <code>${escapeHtml(bench.error)}</code></div>`;
  }
  const rows = bench.results || [];
  const newBytes = Math.max(1, Number(bench.new_bytes));
  let bestIdx = 0;
  let maxBar = 1;
  rows.forEach((r, idx) => {
    maxBar = Math.max(maxBar, Number(r.signature_bytes), Number(r.delta_bytes), Number(r.gzip_delta_bytes));
    const curBest = rows[bestIdx];
    const gz = Number(r.gzip_delta_bytes);
    const bestGz = Number(curBest.gzip_delta_bytes);
    if (
      gz < bestGz ||
      (gz === bestGz && Number(r.delta_bytes) < Number(curBest.delta_bytes)) ||
      (gz === bestGz && Number(r.delta_bytes) === Number(curBest.delta_bytes) && Number(r.signature_bytes) < Number(curBest.signature_bytes))
    ) {
      bestIdx = idx;
    }
  });

  const trHtml = rows
    .map((r, idx) => {
      const isBest = idx === bestIdx;
      const sigB = Number(r.signature_bytes);
      const delB = Number(r.delta_bytes);
      const gzB = Number(r.gzip_delta_bytes);
      const copyPct = ((Number(r.copy_bytes) / newBytes) * 100).toFixed(1);
      const sigW = Math.max(2, (sigB / maxBar) * 100).toFixed(1);
      const delW = Math.max(2, (delB / maxBar) * 100).toFixed(1);
      const gzW = Math.max(2, (gzB / maxBar) * 100).toFixed(1);
      return `<tr class="${isBest ? 'bench-row-best' : ''}">
        <td>
          <strong>${escapeHtml(r.label)}</strong>
          ${isBest ? `<span class="badge badge-add" style="margin-left:0.35rem;">${escapeHtml(t('benchBest'))}</span>` : ''}
        </td>
        <td><code>${Number(r.block_len).toLocaleString()} B</code></td>
        <td><code>${fmtBytes(sigB)}</code></td>
        <td><code>${fmtBytes(delB)}</code></td>
        <td><strong><code>${fmtBytes(gzB)}</code></strong></td>
        <td>${copyPct}%</td>
        <td><code>${Number(r.instruction_count).toLocaleString()}</code></td>
        <td>
          <div class="mini-bars">
            <div class="mini-bar-line"><span style="width:28px;">.sig</span><div class="mini-bar-track"><div class="bar-fill bar-sig" style="width:${sigW}%"></div></div></div>
            <div class="mini-bar-line"><span style="width:28px;">.dlt</span><div class="mini-bar-track"><div class="bar-fill bar-delta" style="width:${delW}%"></div></div></div>
            <div class="mini-bar-line"><span style="width:28px;">.gz</span><div class="mini-bar-track"><div class="bar-fill bar-gz" style="width:${gzW}%"></div></div></div>
          </div>
        </td>
      </tr>`;
    })
    .join('');

  return `
    <div class="table-wrap" style="margin-top:0.85rem;">
      <table>
        <thead>
          <tr>
            <th>Profile</th>
            <th>Block Size</th>
            <th>.sig</th>
            <th>.delta</th>
            <th>.delta.gz</th>
            <th>COPY %</th>
            <th>Instructions</th>
            <th>Relative Wire Size</th>
          </tr>
        </thead>
        <tbody>${trHtml}</tbody>
      </table>
    </div>
  `;
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

  const heatmapHtml = buildHeatmapCardHtml(lastDetailState, 'file-hm');
  const benchBodyHtml = buildBenchmarkContentHtml(lastBenchmarkState);

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

    ${heatmapHtml}

    <div class="card">
      <div class="card-header">
        <h3 class="card-title">${escapeHtml(t('benchTitle'))}</h3>
        <button id="runBenchmarkBtn" class="btn btn-primary btn-sm" type="button">${escapeHtml(t('benchBtn'))}</button>
      </div>
      <p class="hint" style="margin:0;">${escapeHtml(t('benchHint'))}</p>
      <div id="benchmarkOut">${benchBodyHtml}</div>
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

  wireHeatmapEvents(resultsEl, lastDetailState, 'file-hm');
  bindCopyButtons(resultsEl);

  document.getElementById('runBenchmarkBtn').addEventListener('click', async () => {
    if (!lastInputs) return;
    const mod = await loadEngine();
    const raw = mod.benchmark_block_sizes_json(lastInputs.oldBuf, lastInputs.newBuf, Number(sumSelect.value));
    lastBenchmarkState = JSON.parse(raw);
    const outEl = document.getElementById('benchmarkOut');
    if (outEl) outEl.innerHTML = buildBenchmarkContentHtml(lastBenchmarkState);
  });

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
  lastInputs = { oldBuf, newBuf, baseName, newName };
  lastBenchmarkState = null;
  if (parsed.ok) {
    const sig = mod.create_signature_bytes(oldBuf, blockLen, sumLen);
    const delta = mod.create_delta_bytes(sig, newBuf);
    const deltaGz = mod.compress_gzip_bytes(delta, 6);
    const restored = mod.apply_patch_bytes(oldBuf, delta);
    lastArtifacts = { sig, delta, deltaGz, restored, baseName, newName };
    lastDetailState = JSON.parse(mod.inspect_delta_detailed_json(delta, 512));
  } else {
    lastArtifacts = null;
    lastDetailState = null;
  }
  lastResultState = { data: parsed, elapsedMs: elapsed };
  renderResult(parsed, elapsed);
}

function makeBuiltInBinaryPair() {
  const oldBuf = new Uint8Array(131072);
  for (let i = 0; i < oldBuf.length; i++) {
    oldBuf[i] = (i * 73 + 19 + Math.floor(i / 128) * 17 + Math.floor(i / 2048) * 11) % 256;
  }
  const newBuf = new Uint8Array(oldBuf.length);
  newBuf.set(oldBuf);
  const patchA = new TextEncoder().encode('MOONLIBSYNC-050-HEADER-EDIT-SEGMENT '.repeat(6));
  const patchB = new TextEncoder().encode(
    'MOONLIBSYNC-BROWSER-CHUNKED-PATCH-REPEATED-LOG-LINE '.repeat(12),
  );
  newBuf.set(patchA, 20480);
  newBuf.set(patchB, 65536);
  return { oldBuf, newBuf };
}

async function runBuiltInBinarySample() {
  const { oldBuf, newBuf } = makeBuiltInBinaryPair();
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

// =========================================================================
// Tab 2: Split-Role rdiff (Generate .sig / Generate .delta / Apply & Verify)
// =========================================================================
const rdiffSigBlock = document.getElementById('rdiffSigBlock');
const rdiffSigSum = document.getElementById('rdiffSigSum');
const rdiffSigOldDrop = document.getElementById('rdiffSigOldDrop');
const rdiffSigOldFile = document.getElementById('rdiffSigOldFile');
const rdiffSigOldMeta = document.getElementById('rdiffSigOldMeta');
const rdiffGenSigBtn = document.getElementById('rdiffGenSigBtn');
const rdiffSigOut = document.getElementById('rdiffSigOut');

const rdiffDeltaSigDrop = document.getElementById('rdiffDeltaSigDrop');
const rdiffDeltaSigFile = document.getElementById('rdiffDeltaSigFile');
const rdiffDeltaSigMeta = document.getElementById('rdiffDeltaSigMeta');
const rdiffDeltaNewDrop = document.getElementById('rdiffDeltaNewDrop');
const rdiffDeltaNewFile = document.getElementById('rdiffDeltaNewFile');
const rdiffDeltaNewMeta = document.getElementById('rdiffDeltaNewMeta');
const rdiffGenDeltaBtn = document.getElementById('rdiffGenDeltaBtn');
const rdiffDeltaOut = document.getElementById('rdiffDeltaOut');

const rdiffPatchOldDrop = document.getElementById('rdiffPatchOldDrop');
const rdiffPatchOldFile = document.getElementById('rdiffPatchOldFile');
const rdiffPatchOldMeta = document.getElementById('rdiffPatchOldMeta');
const rdiffPatchDeltaDrop = document.getElementById('rdiffPatchDeltaDrop');
const rdiffPatchDeltaFile = document.getElementById('rdiffPatchDeltaFile');
const rdiffPatchDeltaMeta = document.getElementById('rdiffPatchDeltaMeta');
const rdiffPatchManifestDrop = document.getElementById('rdiffPatchManifestDrop');
const rdiffPatchManifestFile = document.getElementById('rdiffPatchManifestFile');
const rdiffPatchManifestMeta = document.getElementById('rdiffPatchManifestMeta');
const rdiffClearManifestBtn = document.getElementById('rdiffClearManifestBtn');
const rdiffApplyPatchBtn = document.getElementById('rdiffApplyPatchBtn');
const rdiffPatchOut = document.getElementById('rdiffPatchOut');

let rdiffFiles = {
  sigOld: null,
  deltaSig: null,
  deltaNew: null,
  patchOld: null,
  patchDelta: null,
  patchManifest: null,
};

wireDropzone(rdiffSigOldDrop, rdiffSigOldFile, rdiffSigOldMeta, (f) => { rdiffFiles.sigOld = f; });
wireDropzone(rdiffDeltaSigDrop, rdiffDeltaSigFile, rdiffDeltaSigMeta, (f) => { rdiffFiles.deltaSig = f; });
wireDropzone(rdiffDeltaNewDrop, rdiffDeltaNewFile, rdiffDeltaNewMeta, (f) => { rdiffFiles.deltaNew = f; });
wireDropzone(rdiffPatchOldDrop, rdiffPatchOldFile, rdiffPatchOldMeta, (f) => { rdiffFiles.patchOld = f; });
wireDropzone(rdiffPatchDeltaDrop, rdiffPatchDeltaFile, rdiffPatchDeltaMeta, (f) => { rdiffFiles.patchDelta = f; });
wireDropzone(rdiffPatchManifestDrop, rdiffPatchManifestFile, rdiffPatchManifestMeta, (f) => { rdiffFiles.patchManifest = f; });

rdiffClearManifestBtn.addEventListener('click', () => {
  rdiffFiles.patchManifest = null;
  rdiffPatchManifestFile.value = '';
  rdiffPatchManifestMeta.textContent = t('rdiffOptionalHint');
  rdiffPatchManifestMeta.classList.remove('selected');
});

rdiffGenSigBtn.addEventListener('click', async () => {
  const file = rdiffFiles.sigOld || rdiffSigOldFile.files?.[0];
  if (!file) {
    rdiffSigOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;">${escapeHtml(t('rdiffPickOld'))}</div>`;
    return;
  }
  const mod = await loadEngine();
  const oldBytes = new Uint8Array(await file.arrayBuffer());
  const blockLen = Number(rdiffSigBlock.value);
  const sumLen = Number(rdiffSigSum.value);
  const t0 = performance.now();
  const sigBytes = mod.create_signature_bytes(oldBytes, blockLen, sumLen);
  const elapsed = performance.now() - t0;
  if (!sigBytes.length) {
    rdiffSigOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Error:</strong> failed to generate signature (check size limits)</div>`;
    return;
  }
  const inspected = JSON.parse(mod.inspect_artifact_json(sigBytes));
  const sigSha = mod.sha256_hex_bytes(sigBytes);
  const oldSha = mod.sha256_hex_bytes(oldBytes);
  const s = inspected.summary || {};
  rdiffSigOut.innerHTML = `
    <div class="stats-grid">
      <div class="stat-card"><div class="stat-label">.sig Size</div><div class="stat-value">${fmtBytes(sigBytes.length)}</div><div class="stat-sub">${sigBytes.length.toLocaleString()} B · ${elapsed.toFixed(1)} ms</div></div>
      <div class="stat-card"><div class="stat-label">Block Size</div><div class="stat-value">${escapeHtml(s.block_len || String(blockLen))} B</div><div class="stat-sub">sum=${escapeHtml(s.strong_sum_len || String(sumLen))} B</div></div>
      <div class="stat-card"><div class="stat-label">Records</div><div class="stat-value">${Number(s.record_count || 0).toLocaleString()}</div><div class="stat-sub">magic ${escapeHtml(s.magic || '0x72730147')}</div></div>
    </div>
    <div class="hash-list" style="margin-bottom:0.75rem;">
      <div class="hash-row"><span class="hash-key">.sig SHA-256</span><span class="hash-val">${escapeHtml(sigSha)}</span><button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(sigSha)}" type="button">${escapeHtml(t('copyBtn'))}</button></div>
      <div class="hash-row"><span class="hash-key">OLD SHA-256</span><span class="hash-val">${escapeHtml(oldSha)}</span><button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(oldSha)}" type="button">${escapeHtml(t('copyBtn'))}</button></div>
    </div>
    <button id="rdiffDlSig" class="btn btn-teal btn-sm" type="button">${escapeHtml(t('dlSig'))} (${escapeHtml(file.name)}.sig)</button>
  `;
  bindCopyButtons(rdiffSigOut);
  document.getElementById('rdiffDlSig').addEventListener('click', () => {
    downloadBlob(sigBytes, file.name + '.sig');
  });
});

rdiffGenDeltaBtn.addEventListener('click', async () => {
  const sigFile = rdiffFiles.deltaSig || rdiffDeltaSigFile.files?.[0];
  const newFile = rdiffFiles.deltaNew || rdiffDeltaNewFile.files?.[0];
  if (!sigFile || !newFile) {
    rdiffDeltaOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;">${escapeHtml(t('rdiffPickSigNew'))}</div>`;
    return;
  }
  const mod = await loadEngine();
  const [sigArr, newArr] = await Promise.all([sigFile.arrayBuffer(), newFile.arrayBuffer()]);
  const sigBytes = new Uint8Array(sigArr);
  const newBytes = new Uint8Array(newArr);
  const sigCheck = JSON.parse(mod.inspect_artifact_json(sigBytes));
  if (!sigCheck.ok || sigCheck.artifact_kind !== 'signature') {
    rdiffDeltaOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Invalid .sig:</strong> <code>${escapeHtml(sigCheck.error || sigCheck.artifact_kind || 'InvalidSignature')}</code></div>`;
    return;
  }
  const t0 = performance.now();
  const deltaBytes = mod.create_delta_bytes(sigBytes, newBytes);
  const gzBytes = deltaBytes.length ? mod.compress_gzip_bytes(deltaBytes, 6) : new Uint8Array(0);
  const elapsed = performance.now() - t0;
  if (!deltaBytes.length) {
    rdiffDeltaOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Error:</strong> failed to generate delta</div>`;
    return;
  }
  const detail = JSON.parse(mod.inspect_delta_detailed_json(deltaBytes, 64));
  const sum = detail.summary || {};
  const copyPct = newBytes.length > 0 ? ((Number(sum.copy_bytes || 0) / newBytes.length) * 100).toFixed(1) : '100.0';
  const deltaSha = mod.sha256_hex_bytes(deltaBytes);
  rdiffDeltaOut.innerHTML = `
    <div class="stats-grid">
      <div class="stat-card"><div class="stat-label">.delta Size</div><div class="stat-value">${fmtBytes(deltaBytes.length)}</div><div class="stat-sub">${deltaBytes.length.toLocaleString()} B · ${elapsed.toFixed(1)} ms</div></div>
      <div class="stat-card"><div class="stat-label">.delta.gz Size</div><div class="stat-value">${fmtBytes(gzBytes.length)}</div><div class="stat-sub">${gzBytes.length.toLocaleString()} B</div></div>
      <div class="stat-card"><div class="stat-label">COPY Reuse</div><div class="stat-value">${copyPct}%</div><div class="stat-sub">${escapeHtml(sum.instruction_count || '0')} instructions</div></div>
    </div>
    <div class="hash-list" style="margin-bottom:0.75rem;">
      <div class="hash-row"><span class="hash-key">.delta SHA-256</span><span class="hash-val">${escapeHtml(deltaSha)}</span><button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(deltaSha)}" type="button">${escapeHtml(t('copyBtn'))}</button></div>
    </div>
    <div class="controls-row">
      <button id="rdiffDlDelta" class="btn btn-teal btn-sm" type="button">${escapeHtml(t('dlDelta'))}</button>
      <button id="rdiffDlDeltaGz" class="btn btn-primary btn-sm" type="button">${escapeHtml(t('dlDeltaGz'))}</button>
    </div>
  `;
  bindCopyButtons(rdiffDeltaOut);
  document.getElementById('rdiffDlDelta').addEventListener('click', () => {
    downloadBlob(deltaBytes, newFile.name + '.delta');
  });
  document.getElementById('rdiffDlDeltaGz').addEventListener('click', () => {
    downloadBlob(gzBytes, newFile.name + '.delta.gz', 'application/gzip');
  });
});

rdiffApplyPatchBtn.addEventListener('click', async () => {
  const oldFile = rdiffFiles.patchOld || rdiffPatchOldFile.files?.[0];
  const deltaFile = rdiffFiles.patchDelta || rdiffPatchDeltaFile.files?.[0];
  const manifestFile = rdiffFiles.patchManifest || rdiffPatchManifestFile.files?.[0] || null;
  if (!oldFile || !deltaFile) {
    rdiffPatchOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;">${escapeHtml(t('rdiffPickOldDelta'))}</div>`;
    return;
  }
  const mod = await loadEngine();
  const [oldArr, deltaArr, manifestText] = await Promise.all([
    oldFile.arrayBuffer(),
    deltaFile.arrayBuffer(),
    manifestFile ? manifestFile.text() : Promise.resolve(''),
  ]);
  const oldBytes = new Uint8Array(oldArr);
  const deltaOrGz = new Uint8Array(deltaArr);
  const t0 = performance.now();
  const res = JSON.parse(mod.apply_verified_patch_json(oldBytes, deltaOrGz, manifestText));
  const elapsed = performance.now() - t0;
  if (!res.ok) {
    rdiffPatchOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Patch / Verify Failed:</strong> <code>${escapeHtml(res.error)}</code></div>`;
    return;
  }

  let isFullManifest = false;
  if (res.verified_manifest && manifestText.trim()) {
    try {
      const mObj = JSON.parse(manifestText);
      if (mObj && mObj.kind === 'full-file') isFullManifest = true;
    } catch (_) {}
  }
  const restoredBytes = isFullManifest
    ? (res.decompressed_gzip ? mod.decompress_gzip_bytes(deltaOrGz, 67108864) : deltaOrGz)
    : mod.apply_patch_or_gzip_bytes(oldBytes, deltaOrGz);

  const badgeText = res.verified_manifest
    ? '✓ Manifest SHA-256 Verified'
    : '✓ Patch Applied (No Manifest)';
  rdiffPatchOut.innerHTML = `
    <div class="result-hero" style="margin-bottom:0.8rem;">
      <div class="hero-metric">
        <span class="hero-pct" style="font-size:1.35rem;">${fmtBytes(res.output_bytes)}</span>
        <span class="hero-desc">${Number(res.output_bytes).toLocaleString()} B · ${elapsed.toFixed(1)} ms</span>
      </div>
      <div class="controls-row">
        ${res.decompressed_gzip ? '<span class="verified-pill info">Gzip Auto-Decompressed</span>' : ''}
        <span class="verified-pill">${escapeHtml(badgeText)}</span>
      </div>
    </div>
    <div class="hash-list" style="margin-bottom:0.75rem;">
      <div class="hash-row"><span class="hash-key">Restored SHA-256</span><span class="hash-val">${escapeHtml(res.sha256)}</span><button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(res.sha256)}" type="button">${escapeHtml(t('copyBtn'))}</button></div>
    </div>
    <button id="rdiffDlRestored" class="btn btn-teal btn-sm" type="button">${escapeHtml(t('dlRestored'))}</button>
  `;
  bindCopyButtons(rdiffPatchOut);
  document.getElementById('rdiffDlRestored').addEventListener('click', () => {
    downloadBlob(restoredBytes, 'restored-' + oldFile.name);
  });
});

// =========================================================================
// Tab 3: Universal Artifact Inspector
// =========================================================================
const inspectDrop = document.getElementById('inspectDrop');
const inspectFile = document.getElementById('inspectFile');
const inspectMeta = document.getElementById('inspectMeta');
const inspectSampleDeltaBtn = document.getElementById('inspectSampleDelta');
const inspectSampleSigBtn = document.getElementById('inspectSampleSig');

function renderInspectResult(state) {
  const { name, rawBytes, parsed, detail, innerDeltaDetail, elapsedMs } = state;
  if (!parsed.ok) {
    inspectResultsEl.innerHTML = `
      <div class="card err-card">
        <strong>Inspection Failed (${escapeHtml(name)} · ${fmtBytes(rawBytes.length)}):</strong>
        <code>${escapeHtml(parsed.error)}</code>
      </div>
    `;
    return;
  }

  const schemaPill = parsed.schema_version
    ? `<span class="verified-pill info">Schema v${escapeHtml(parsed.schema_version)}</span>`
    : `<span class="verified-pill info">Binary Wire Format</span>`;

  const statCards = [];
  const hashRows = [];
  const pushSummaryFields = (obj) => {
    for (const [k, v] of Object.entries(obj || {})) {
      if (k.includes('sha256')) {
        hashRows.push([k, String(v)]);
      } else {
        const isBytes = k.endsWith('_bytes') || k === 'block_len' || k === 'strong_sum_len';
        const displayVal = isBytes && /^\d+$/.test(String(v)) ? fmtBytes(v) : String(v);
        const subVal = isBytes && /^\d+$/.test(String(v)) ? `${Number(v).toLocaleString()} B` : '';
        statCards.push({ label: k.replaceAll('_', ' '), value: displayVal, sub: subVal });
      }
    }
  };

  if (parsed.artifact_kind === 'gzip') {
    const ratio = Number(parsed.compressed_bytes) > 0
      ? (Number(parsed.uncompressed_bytes) / Number(parsed.compressed_bytes)).toFixed(2) + '×'
      : '—';
    pushSummaryFields({
      compressed_bytes: parsed.compressed_bytes,
      uncompressed_bytes: parsed.uncompressed_bytes,
      expansion_ratio: ratio,
      uncompressed_sha256: parsed.uncompressed_sha256,
    });
  } else if (parsed.artifact_kind === 'bundle-archive') {
    statCards.push({
      label: 'archive bytes',
      value: fmtBytes(parsed.archive_bytes),
      sub: `${Number(parsed.archive_bytes).toLocaleString()} B`,
    });
    pushSummaryFields(parsed.summary);
  } else {
    pushSummaryFields(parsed.summary);
  }

  const statsHtml = statCards
    .map(
      (c) => `<div class="stat-card">
        <div class="stat-label">${escapeHtml(c.label)}</div>
        <div class="stat-value">${escapeHtml(c.value)}</div>
        ${c.sub ? `<div class="stat-sub">${escapeHtml(c.sub)}</div>` : ''}
      </div>`,
    )
    .join('');

  const hashesHtml = hashRows.length
    ? `<div class="hash-list" style="margin-bottom:0.85rem;">${hashRows
        .map(
          ([k, v]) => `<div class="hash-row">
            <span class="hash-key">${escapeHtml(k)}</span>
            <span class="hash-val">${escapeHtml(v)}</span>
            <button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(v)}" type="button">${escapeHtml(t('copyBtn'))}</button>
          </div>`,
        )
        .join('')}</div>`
    : '';

  const heatmapDetail = detail || innerDeltaDetail;
  const innerNote = innerDeltaDetail
    ? `<div class="status-bar ok" style="margin-bottom:1rem;"><div class="status-left"><span class="dot"></span><span>${escapeHtml(t('inspectInnerDelta'))}</span></div></div>`
    : '';
  const heatmapHtml = heatmapDetail ? buildHeatmapCardHtml(heatmapDetail, 'inspect-hm') : '';

  inspectResultsEl.innerHTML = `
    <div class="result-hero">
      <div class="hero-metric">
        <span class="hero-pct" style="font-size:1.5rem;">${escapeHtml(parsed.artifact_kind)}</span>
        <span class="hero-desc">${escapeHtml(name)} · ${fmtBytes(rawBytes.length)} (${rawBytes.length.toLocaleString()} B · ${elapsedMs.toFixed(1)} ms)</span>
      </div>
      <div class="controls-row">
        ${schemaPill}
        <span class="verified-pill">✓ Validated</span>
      </div>
    </div>

    <div class="stats-grid">${statsHtml}</div>
    ${innerNote}
    ${heatmapHtml}

    <div class="card">
      ${hashesHtml}
      <div class="hex-card"><div class="hex-title">Header Hex Preview (${rawBytes.length.toLocaleString()} B)</div>${escapeHtml(toHexPreview(rawBytes, 40))}</div>
      <details class="wire-box">
        <summary>${escapeHtml(t('inspectRawJson'))}</summary>
        <pre class="cli-pre" style="margin-top:0.6rem;border-radius:10px;background:#0f172a;">${escapeHtml(JSON.stringify(parsed, null, 2))}</pre>
      </details>
    </div>
  `;

  bindCopyButtons(inspectResultsEl);
  if (heatmapDetail) wireHeatmapEvents(inspectResultsEl, heatmapDetail, 'inspect-hm');
}

async function inspectArtifactBytes(bytes, name) {
  const mod = await loadEngine();
  const t0 = performance.now();
  const parsed = JSON.parse(mod.inspect_artifact_json(bytes));
  let detail = null;
  let innerDeltaDetail = null;
  if (parsed.ok && parsed.artifact_kind === 'delta') {
    detail = JSON.parse(mod.inspect_delta_detailed_json(bytes, 512));
  } else if (parsed.ok && parsed.artifact_kind === 'gzip') {
    const plain = mod.decompress_gzip_bytes(bytes, 67108864);
    if (plain.length >= 5 && plain[0] === 0x72 && plain[1] === 0x73 && plain[2] === 0x02 && plain[3] === 0x36) {
      const inner = JSON.parse(mod.inspect_delta_detailed_json(plain, 512));
      if (inner.ok) innerDeltaDetail = inner;
    }
  }
  const elapsedMs = performance.now() - t0;
  lastInspectState = { name, rawBytes: bytes, parsed, detail, innerDeltaDetail, elapsedMs };
  renderInspectResult(lastInspectState);
}

wireDropzone(inspectDrop, inspectFile, inspectMeta, async (file) => {
  const bytes = new Uint8Array(await file.arrayBuffer());
  await inspectArtifactBytes(bytes, file.name);
});

inspectSampleDeltaBtn.addEventListener('click', async () => {
  const mod = await loadEngine();
  const { oldBuf, newBuf } = makeBuiltInBinaryPair();
  const sig = mod.create_signature_bytes(oldBuf, 2048, 16);
  const delta = mod.create_delta_bytes(sig, newBuf);
  inspectMeta.textContent = `sample-128k.delta (${fmtBytes(delta.length)})`;
  inspectMeta.classList.add('selected');
  await inspectArtifactBytes(delta, 'sample-128k.delta');
});

inspectSampleSigBtn.addEventListener('click', async () => {
  const mod = await loadEngine();
  const { oldBuf } = makeBuiltInBinaryPair();
  const sig = mod.create_signature_bytes(oldBuf, 0, 16);
  inspectMeta.textContent = `sample-128k.sig (${fmtBytes(sig.length)})`;
  inspectMeta.classList.add('selected');
  await inspectArtifactBytes(sig, 'sample-128k.sig');
});

// =========================================================================
// Tab 4: Directory Sync Planner & Integrity Audit (dir-verify + --exclude)
// =========================================================================
function setDirMode(mode) {
  dirMode = mode;
  dirModePlanBtn.classList.toggle('active', mode === 'plan');
  dirModeVerifyBtn.classList.toggle('active', mode === 'verify');
}
dirModePlanBtn.addEventListener('click', () => setDirMode('plan'));
dirModeVerifyBtn.addEventListener('click', () => setDirMode('verify'));

fillExcludePresetBtn.addEventListener('click', () => {
  dirExcludeInput.value = '.git, node_modules, *.tmp';
});

function parseExcludePatterns() {
  const raw = dirExcludeInput.value || '';
  return raw
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

function excludeCliArgs(patterns) {
  return patterns.map((p) => ` --exclude "${p.replaceAll('"', '')}"`).join('');
}

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
  if (kind === 'update-candidate' || kind === 'modified') return 'badge badge-update';
  if (kind === 'extra') return 'badge badge-info';
  return 'badge badge-delete';
}

function renderDirPlan(state) {
  const { planText, basisSnapText, targetSnapText, patterns, elapsedMs } = state;
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

  const exFlags = excludeCliArgs(patterns || []);
  const dirCli = [
    `moonlibsync dir-snapshot ./basis basis.snap.json${exFlags}`,
    `moonlibsync dir-signatures ./basis basis.snap.json ./basis-sigs --block-size auto --streaming`,
    `moonlibsync dir-pack basis.snap.json ./basis-sigs ./target ./bundle --streaming${exFlags}`,
    `moonlibsync dir-apply ./basis ./bundle ./restored --streaming`,
  ].join('\n');

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
        <pre class="cli-pre">${escapeHtml(dirCli)}</pre>
      </div>
    </div>
  `;

  document.getElementById('copyDirCli').addEventListener('click', (e) => {
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

function renderDirVerify(state) {
  const { verifyText, basisSnapText, targetSnapText, patterns, elapsedMs } = state;
  const report = JSON.parse(verifyText);
  if (report.error) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Directory verify error:</strong> <code>${escapeHtml(report.error)}</code></div>`;
    return;
  }
  const s = report.summary;
  const issues = report.issues || [];
  const q = currentDirSearch.trim().toLowerCase();
  const filtered = issues.filter((it) => {
    if (currentDirFilter !== 'all' && it.kind !== currentDirFilter) return false;
    if (q && !it.path.toLowerCase().includes(q)) return false;
    return true;
  });

  const fmtDigest = (d) =>
    d ? `${fmtBytes(d.byte_length)} · <code>${escapeHtml(d.sha256.slice(0, 12))}...</code>` : '—';

  const rows = filtered
    .map(
      (it) => `<tr>
        <td><code>${escapeHtml(it.path)}</code></td>
        <td><span class="${badgeClassForKind(it.kind)}">${escapeHtml(it.kind)}</span></td>
        <td>${fmtDigest(it.expected)}</td>
        <td>${fmtDigest(it.actual)}</td>
      </tr>`,
    )
    .join('');

  const filterKinds = [
    ['all', `${t('allFilter')} (${issues.length})`],
    ['modified', `modified (${s.modified})`],
    ['missing', `missing (${s.missing})`],
    ['extra', `extra (${s.extra})`],
  ];
  const pillsHtml = filterKinds
    .map(
      ([k, label]) =>
        `<button class="filter-pill ${currentDirFilter === k ? 'active' : ''}" data-kind="${k}" type="button">${escapeHtml(label)}</button>`,
    )
    .join('');

  const exFlags = excludeCliArgs(patterns || []);
  const verifyCli = [
    `moonlibsync dir-snapshot ./expected expected.snap.json${exFlags}`,
    `moonlibsync dir-verify expected.snap.json ./actual --report verify-report.json${exFlags}`,
  ].join('\n');

  dirResultsEl.innerHTML = `
    <div class="result-hero ${report.ok ? '' : 'drift'}">
      <div class="hero-metric">
        <span class="hero-pct ${report.ok ? '' : 'danger'}" style="font-size:1.45rem;">
          ${report.ok ? 'VERIFIED OK' : 'DRIFT DETECTED'}
        </span>
        <span class="hero-desc">matched=${escapeHtml(s.matched)} · issues=${issues.length} (${elapsedMs.toFixed(1)} ms)</span>
      </div>
      <span class="verified-pill ${report.ok ? '' : 'fail'}">
        ${report.ok ? '✓ ' + escapeHtml(t('verifyOkBadge')) : '✕ ' + escapeHtml(t('verifyDriftBadge'))}
      </span>
    </div>

    <div class="stats-grid">
      <div class="stat-card"><div class="stat-label">Matched</div><div class="stat-value" style="color:var(--emerald-text)">${escapeHtml(s.matched)}</div></div>
      <div class="stat-card"><div class="stat-label">Modified</div><div class="stat-value" style="color:var(--amber-text)">${escapeHtml(s.modified)}</div></div>
      <div class="stat-card"><div class="stat-label">Missing</div><div class="stat-value" style="color:var(--rose-text)">${escapeHtml(s.missing)}</div></div>
      <div class="stat-card"><div class="stat-label">Extra</div><div class="stat-value" style="color:var(--primary)">${escapeHtml(s.extra)}</div></div>
    </div>

    <div class="card">
      <div class="card-header">
        <h3 class="card-title">Schema 3 Verification Report (moonlibsync-dir-verify)</h3>
        <div class="controls-row">
          <button id="dlVerifyReport" class="btn btn-teal btn-sm" type="button">Download verify-report.json</button>
          <button id="dlExpSnap" class="btn btn-secondary btn-sm" type="button">expected-snapshot.json</button>
          <button id="dlActSnap" class="btn btn-secondary btn-sm" type="button">actual-snapshot.json</button>
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
              <th>${escapeHtml(t('issueKindCol'))}</th>
              <th>${escapeHtml(t('expectedCol'))}</th>
              <th>${escapeHtml(t('actualCol'))}</th>
            </tr>
          </thead>
          <tbody>${rows || `<tr><td colspan="4" style="text-align:center;color:var(--emerald-text);font-weight:600;">${escapeHtml(t('verifyNoIssues'))}</td></tr>`}</tbody>
        </table>
      </div>
      <div class="cli-wrap">
        <div class="cli-head">
          <span>${escapeHtml(t('cliVerifyTitle'))}</span>
          <button id="copyVerifyCli" class="btn btn-secondary btn-sm" type="button">${escapeHtml(t('copyBtn'))}</button>
        </div>
        <pre class="cli-pre">${escapeHtml(verifyCli)}</pre>
      </div>
    </div>
  `;

  document.getElementById('copyVerifyCli').addEventListener('click', (e) => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(verifyCli);
      e.target.textContent = t('copiedBtn');
      setTimeout(() => { e.target.textContent = t('copyBtn'); }, 1200);
    }
  });
  document.getElementById('dlVerifyReport').addEventListener('click', () => {
    downloadBlob(verifyText, 'verify-report.json', 'application/json');
  });
  document.getElementById('dlExpSnap').addEventListener('click', () => {
    downloadBlob(basisSnapText, 'expected-snapshot.json', 'application/json');
  });
  document.getElementById('dlActSnap').addEventListener('click', () => {
    downloadBlob(targetSnapText, 'actual-snapshot.json', 'application/json');
  });
  for (const pill of dirResultsEl.querySelectorAll('.filter-pill')) {
    pill.addEventListener('click', () => {
      currentDirFilter = pill.dataset.kind;
      renderDirVerify(lastDirState);
    });
  }
  const searchEl = document.getElementById('dirSearch');
  searchEl.addEventListener('input', () => {
    currentDirSearch = searchEl.value;
    renderDirVerify(lastDirState);
    const nextSearch = document.getElementById('dirSearch');
    if (nextSearch) {
      nextSearch.focus();
      nextSearch.setSelectionRange(currentDirSearch.length, currentDirSearch.length);
    }
  });
}

function buildSnapshotWithExcludes(mod, entries, patterns) {
  if (patterns.length > 0) {
    return mod.filter_dir_entries_json(JSON.stringify(entries), JSON.stringify(patterns));
  }
  return mod.create_dir_snapshot_json(JSON.stringify(entries));
}

async function buildSnapshotFromFiles(mod, fileList, patterns) {
  const entries = [];
  for (const { rel, file } of normalizeRelativeFolderFiles(fileList)) {
    const bytes = new Uint8Array(await file.arrayBuffer());
    const sha256 = mod.sha256_hex_bytes(bytes);
    entries.push({ path: rel, byte_length: String(bytes.length), sha256 });
  }
  return buildSnapshotWithExcludes(mod, entries, patterns);
}

function makeSampleDirEntries(mod) {
  const enc = new TextEncoder();
  const entryOf = (rel, text) => {
    const b = enc.encode(text);
    return { path: rel, byte_length: String(b.length), sha256: mod.sha256_hex_bytes(b) };
  };
  const basisEntries = [
    entryOf('.git/HEAD', 'ref: refs/heads/main\n'),
    entryOf('README.md', '# MoonLibSync\n'),
    entryOf('assets/logo.svg', '<svg viewBox="0 0 28 28">v1</svg>'),
    entryOf('cache/session.tmp', 'temporary scratch data'),
    entryOf('src/engine.mbt', 'pub fn delta() { ... }\n'.repeat(180)),
    entryOf('legacy/deprecated.txt', 'old legacy file'),
  ];
  const targetEntries = [
    entryOf('.git/HEAD', 'ref: refs/heads/release-0.5\n'),
    entryOf('README.md', '# MoonLibSync\n'),
    entryOf('assets/logo.svg', '<svg viewBox="0 0 28 28">v2-updated-vector</svg>'),
    entryOf('cache/session.tmp', 'temporary scratch data v2'),
    entryOf('src/engine.mbt', 'pub fn delta() { ... }\n'.repeat(180) + '// v0.5.0 streaming\n'),
    entryOf('docs/dir-sync.md', '# Schema 3 Directory Sync Guide\n'.repeat(40)),
    entryOf('compress/gzip.mbt', 'pub fn compress_gzip() {}\n'.repeat(30)),
  ];
  return { basisEntries, targetEntries };
}

function executeDirComparison(mod, basisSnap, targetSnap, mode, patterns, t0) {
  const parsedBasis = JSON.parse(basisSnap);
  if (parsedBasis.ok === false) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>BASIS / Expected snapshot error:</strong> <code>${escapeHtml(parsedBasis.error)}</code></div>`;
    return;
  }
  const parsedTarget = JSON.parse(targetSnap);
  if (parsedTarget.ok === false) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>TARGET / Actual snapshot error:</strong> <code>${escapeHtml(parsedTarget.error)}</code></div>`;
    return;
  }
  currentDirFilter = 'all';
  currentDirSearch = '';
  if (mode === 'verify') {
    const verifyText = mod.verify_dir_snapshots_json(basisSnap, targetSnap);
    lastDirState = {
      mode: 'verify',
      verifyText,
      basisSnapText: basisSnap,
      targetSnapText: targetSnap,
      patterns,
      elapsedMs: performance.now() - t0,
    };
    renderDirVerify(lastDirState);
  } else {
    const planText = mod.plan_dir_snapshots_json(basisSnap, targetSnap);
    lastDirState = {
      mode: 'plan',
      planText,
      basisSnapText: basisSnap,
      targetSnapText: targetSnap,
      patterns,
      elapsedMs: performance.now() - t0,
    };
    renderDirPlan(lastDirState);
  }
}

runDirSampleBtn.addEventListener('click', async () => {
  const mod = await loadEngine();
  const patterns = parseExcludePatterns();
  const t0 = performance.now();
  const { basisEntries, targetEntries } = makeSampleDirEntries(mod);
  const basisSnap = buildSnapshotWithExcludes(mod, basisEntries, patterns);
  const targetSnap = buildSnapshotWithExcludes(mod, targetEntries, patterns);
  executeDirComparison(mod, basisSnap, targetSnap, dirMode, patterns, t0);
});

runDirVerifyCleanSampleBtn.addEventListener('click', async () => {
  const mod = await loadEngine();
  setDirMode('verify');
  const patterns = parseExcludePatterns();
  const t0 = performance.now();
  const { basisEntries } = makeSampleDirEntries(mod);
  const snap = buildSnapshotWithExcludes(mod, basisEntries, patterns);
  executeDirComparison(mod, snap, snap, 'verify', patterns, t0);
});

async function runDirFoldersWithMode(mode) {
  const mod = await loadEngine();
  setDirMode(mode);
  if (!basisDirInput.files?.length && !targetDirInput.files?.length) {
    dirResultsEl.innerHTML = `<div class="card err-card">${escapeHtml(t('pickDirWarn'))}</div>`;
    return;
  }
  const patterns = parseExcludePatterns();
  const t0 = performance.now();
  const basisSnap = await buildSnapshotFromFiles(mod, basisDirInput.files, patterns);
  const targetSnap = await buildSnapshotFromFiles(mod, targetDirInput.files, patterns);
  executeDirComparison(mod, basisSnap, targetSnap, mode, patterns, t0);
}

runDirDiffBtn.addEventListener('click', () => runDirFoldersWithMode('plan'));
runDirVerifyBtn.addEventListener('click', () => runDirFoldersWithMode('verify'));

// =========================================================================
// Tab 5: Gzip Security Defense Lab
// =========================================================================
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
