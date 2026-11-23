// SPDX-License-Identifier: LGPL-2.1-or-later
const IS_REPO_LOCAL = window.location.pathname.includes('/examples/web-demo/');
const MODULE_PATHS = IS_REPO_LOCAL
  ? [
      '../../_build/js/release/build/examples/web-demo/web-demo.js',
      '../../_build/js/release/build/YKDshaxing/moonlibsync/examples/web-demo/web-demo.js',
      '../../_build/js/debug/build/examples/web-demo/web-demo.js',
      '../../_build/js/debug/build/YKDshaxing/moonlibsync/examples/web-demo/web-demo.js',
      './web-demo.js',
    ]
  : [
      './web-demo.js',
      '../../_build/js/release/build/examples/web-demo/web-demo.js',
      '../../_build/js/release/build/YKDshaxing/moonlibsync/examples/web-demo/web-demo.js',
      '../../_build/js/debug/build/examples/web-demo/web-demo.js',
      '../../_build/js/debug/build/YKDshaxing/moonlibsync/examples/web-demo/web-demo.js',
    ];

const I18N = {
  zh: {
    subtitle: '纯 MoonBit 编译的浏览器零后端二进制差分、HTTP Range 增量拉取、Delta 链压缩合并、Gzip/Zlib、单文件目录打包与 X25519 / Ed25519 多签密码学工作台',
    tabFile: '文件差分 & Gzip',
    tabRdiff: '独立角色在线工具',
    tabInspect: '通用产物剖析器',
    tabDir: '目录同步规划 & 巡检',
    tabLab: '安全防线与密码学实验室',
    fileCardTitle: '流式签名 · 差分 · 反向回滚 · Gzip 二次压缩 · 块复用 Hexdump 热力图',
    sigProfile: '签名格式',
    blockSize: '块长',
    chunkSize: '流式分块',
    sumSize: '强校验',
    runSample: '运行内置 128 KiB 二进制示例',
    runLogSample: '运行 64 KiB 日志差分示例（高压缩率）',
    oldLabel: 'OLD 基准文件（旧版本）',
    newLabel: 'NEW 目标文件（新版本）',
    dropHint: '点击选择或拖拽任意本地文件至此',
    localPrivacy: '100% 本地浏览器 Web Worker 后台计算，绝不上传任何文件数据；导出的 .sig / .delta / rollback.delta 与 librsync rdiff 及 CLI 完全兼容。',
    runFiles: '对比所选文件并验证还原',
    heatmapTitle: 'Delta 块复用热力图（Interactive Block Reuse Heatmap）',
    heatmapHint: '悬停或点击上方任意色块查看指令详情；点击琥珀色 Literal 色块可展开 Hexdump + UTF-8 明文预览',
    heatmapTruncated: (shown, total) => `已展示前 ${shown} / ${total} 条指令`,
    heatmapTableToggle: (n) => `展开指令明细表（前 ${n} 条）`,
    litPreviewTitle: (shown, total, trunc) =>
      `Literal 载荷 Hexdump 预览（前 ${shown} B / 共 ${total} B${trunc ? ' · 已截断' : ''}）`,
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
    inspectCardTitle: '通用产物剖析器（.sig · .delta · .gz · .zlib · .mbundle · .menc · MLSENC02 · Schema 1/2/3/4 JSON）',
    inspectSampleDelta: '剖析示例 .delta（含热力图）',
    inspectSampleSig: '剖析示例 .sig (0x72730137)',
    inspectSampleSeal: '剖析示例 .menc',
    inspectSampleEnvelope: '剖析示例 MLSENC02',
    inspectSampleKeyring: '剖析示例 Keyring',
    inspectSamplePubSig: '剖析示例 .msig.json',
    inspectDropLabel: '拖入任意 MoonLibSync 二进制或 JSON 产物自动剖析',
    inspectDropHint: '支持 .sig / .delta / .gz / .zlib / .mbundle / .menc / MLSENC02 / Keyring / Signature Bundle / Dir Metadata / Schema 1/2/3/4 JSON',
    inspectRawJson: '展开原始剖析 JSON 响应',
    inspectInnerDelta: '检测到 Gzip 内层为标准 0x72730236 Delta，已自动展开块复用热力图与 Literal Hexdump 预览',
    inspectInnerBundle: '检测到 Gzip 内层为 MLSBDL01 单文件目录归档（.mbundle.gz）',
    dirCardTitle: '浏览器端 Schema 3 目录快照、移动检测、巡检与 .mbundle.gz 单文件打包',
    dirModePlan: '同步规划 (dir-plan)',
    dirModeVerify: '完整性巡检 (dir-verify)',
    dirModeBundle: '单文件打包/解包 (.mbundle.gz)',
    runDirSample: '运行内置目录变更示例',
    runDirVerifyCleanSample: '巡检一致示例 (OK)',
    basisDirLabel: 'BASIS 基准目录（旧目录 / Expected 预期基线）',
    targetDirLabel: 'TARGET 目标目录（新目录 / Actual 实测目录）',
    pickDirHint: '点击选择本地文件夹',
    dirExcludeLabel: '--exclude 排除规则（逗号分隔）',
    fillExcludePreset: '填入常用忽略',
    dirDetectMoves: '--detect-moves (重命名/移动 0 字节复用)',
    bundlePanelTitle: '单文件归档打包 & 浏览器端解包验证（MLSBDL01 / .mbundle.gz）',
    bundleGzipLabel: '启用 RFC 1952 Gzip 压缩 (.mbundle.gz)',
    bundlePackSampleBtn: '打包内置示例为 .mbundle.gz',
    bundlePackFoldersBtn: '打包所选 BASIS + TARGET 目录',
    bundleUnpackDropLabel: '拖入 .mbundle 或 .mbundle.gz 归档文件执行解包与全量 SHA-256 校验',
    bundleUnpackHint: '将结合上方 BASIS 目录（未选目录时自动使用内置示例 BASIS）逐文件还原并校验 SHA-256',
    bundleFooterHint: '支持 CopyFromBasis 0 字节复用、UpdateDeltaFrom 跨路径差分，解包时自动解压 Gzip 并逐文件验证 SHA-256。',
    bundleUnpackBtn: '解包所选归档并校验还原',
    bundlePickArchiveWarn: '请先拖入 .mbundle / .mbundle.gz 归档文件，或先点击上方「打包内置示例」后使用一键往返解包。',
    bundleDlArchive: (isGz) => (isGz ? '下载 .mbundle.gz' : '下载 .mbundle'),
    bundleRoundtripBtn: '一键往返解包并全量校验 SHA-256',
    bundleUnpackOkBadge: (n) => `✓ 全部 ${n} 个文件 SHA-256 校验通过`,
    bundleDownloadFile: '下载',
    dirHint: '自动执行 --exclude 匹配、--detect-moves 内容指纹移动检测、POSIX 路径安全校验与跨平台 ASCII 大小写冲突检测。',
    runDirDiff: '生成 Schema 3 同步计划',
    runDirVerify: '执行 dir-verify 巡检',
    verifyOkBadge: 'VERIFIED OK · 目录完全一致',
    verifyDriftBadge: 'DRIFT DETECTED · 检测到目录漂移',
    verifyNoIssues: '零漂移：所有文件长度与 SHA-256 与预期基线完全匹配。',
    expectedCol: '预期基线 (Expected)',
    actualCol: '实测目录 (Actual)',
    issueKindCol: '漂移类型',
    engineReady: 'MoonBit 纯 JS 引擎已就绪（v0.7.1 · 零后端 · 零 C FFI · 37 项核心导出）',
    workerBadgeActive: 'Web Worker 后台线程',
    workerBadgeFallback: '主线程回退模式',
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
    dlRollback: '下载反向回滚补丁 (rollback.delta)',
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
    labTitle: '有界 Gzip / Zlib 安全防线实测（Zip-Bomb · 尾随数据 · 截断流）',
    runAllLab: '一键运行全部 3 项安全演练',
    labBombTitle: '1. Zip-Bomb 解压炸弹拦截',
    labBombDesc: '现场生成 256 KiB 零字节高压缩炸弹（仅约 300 B），以 4 KiB 解压上限执行有界解压，验证引擎在超出预算瞬间中断并报 LimitExceeded。',
    labBombBtn: '触发 Zip-Bomb 测试',
    labTrailTitle: '2. 尾随垃圾字节拒绝',
    labTrailDesc: '在合法单流压缩帧（Gzip CRC32/ISIZE 或 Zlib Adler-32）尾部追加 1 字节多余载荷（0x42），验证严格帧校验立刻返回 TrailingData。',
    labTrailBtn: '触发 TrailingData 测试',
    labTruncTitle: '3. 截断流 / 尾部缺失拒绝',
    labTruncDesc: '截去尾部校验和（CRC32/ISIZE 或 Adler-32）的最后 1 字节，验证解码器严格报 TruncatedInput，绝不静默返回不完整数据。',
    labTruncBtn: '触发 TruncatedInput 测试',
    labCustomTitle: '自定义文本有界 Gzip / Zlib 往返实验室',
    labLevel: '压缩级别',
    labMaxOut: '解压上限 (B)',
    labRunCustom: '压缩并有界解压测试',
    edCardTitle: 'Ed25519 发布者数字签名 & 验签实验室（RFC 8032 · Schema 4 .msig.json）',
    edGenKeyBtn: '生成随机 Ed25519 密钥对',
    edSignBtn: '签名并生成 .msig.json',
    edDlSigBtn: '下载 .msig.json',
    edVerifyValidBtn: '验证合法签名 (Valid)',
    edVerifyTamperBtn: '模拟 1 字节载荷篡改 (DigestMismatch)',
    edVerifyUntrustedBtn: '模拟非信任公钥验证 (UntrustedKey)',
    aeadCardTitle: 'AEAD 流式加密封装实验室（MLSENC01 · ChaCha20-Poly1305 + Argon2id .menc）',
    aeadKdfLabel: '密钥模式',
    aeadMemLabel: 'Argon2 内存',
    aeadPassesLabel: '轮次',
    aeadSecretLabel: '口令 / 32B 十六进制密钥',
    aeadGenRawKeyBtn: '生成随机 32B 密钥',
    aeadSealBtn: '加密封装为 .menc',
    aeadDlMencBtn: '下载 .menc',
    aeadUnsealBtn: '解密并校验 SHA-256',
    aeadTamperBtn: '模拟 1 字节密文篡改 (AuthenticationFailed)',
    rangeCardTitle: '静态 CDN HTTP Range 增量拉取模拟器 & CORS 实网拉取',
    rangeModeSim: '本地 CDN 模拟',
    rangeModeLive: 'CORS 实网 URL',
    rangeProfileLabel: '签名',
    rangeMergeGapLabel: '合并间隙',
    rangeMergeGapZero: '0 B (不合并)',
    rangeSigVerifiedBadge: '远端签名 BLAKE2b 逐块校验通过',
    runRangeSimBtn: '一键运行 128 KiB HTTP Range 增量拉取模拟 (v1 → v2)',
    rangeSimHint: '无需服务端差分计算：仅凭静态托管的 v2.sig 与本地 v1 基准，规划最小 HTTP Range 请求区间、模拟 HTTP 206 Partial Content 拉取并逐字节验证还原结果。',
    rangeTargetUrlLabel: '远端目标文件 URL（支持 CORS 与 HTTP 206 Range）',
    rangeSigUrlLabel: '远端 .sig 签名 URL（留空则自动追加 .sig）',
    rangeLiveBasisLabel: '本地旧基准文件 (OLD Basis，可选)',
    rangeLiveBasisHint: '可选：拖入本地旧版文件以最大化本地块复用（不选则视为空基准）',
    rangeLiveHint: '要求远端静态主机返回 Access-Control-Allow-Origin 并允许 Range 请求头与 Content-Range 响应头。',
    runRangeLiveBtn: '通过 HTTP Range 实网拉取并还原',
    rangeSavedLabel: 'HTTP 带宽节省（静态 Range 拉取）',
    rangePillsTitle: 'HTTP Range 请求区间列表（RFC 9110）',
    rangeZeroRanges: '零网络请求：本地基准已包含 100% 目标块！',
    rangeUrlRequired: '请先输入远端目标文件 URL（https://...）。',
    rangeDlPlanBtn: '下载 range-plan.json',
    rangeDlRestoredBtn: '下载还原后的目标文件',
    rangeCliTitle: '等价 Native CLI 静态 Range 拉取命令',
    composeCardTitle: '多代 Delta 链零中间文件合并（v1 → v2 → v3 ⇒ v1 → v3）',
    runCompose2Btn: '一键演示 2 跳合并 (v1→v2→v3)',
    runCompose3Btn: '一键演示 3 跳合并 (v1→v2→v3→v4)',
    composeDesc: '无需还原中间版本 v2/v3，直接将串联的增量补丁代数合并为单跳直达补丁 d1→N，自动折叠重复覆写并合并相邻 COPY/Literal 指令。',
    composeDropLabel: '或选择/拖入 2 个及以上按版本顺序排列的 .delta 文件进行合并',
    composeDropHint: '将按文件名顺序合并为单条标准 0x72730236 Delta 并支持直接下载',
    composeFooterHint: '合并产物完全符合标准 0x72730236 线缆格式，可直接配合 apply_patch 或原生 librsync rdiff 使用。',
    runComposeCustomBtn: '合并所选 .delta 链',
    composeSavedLabel: 'Delta 链合并体积缩减',
    composeVerifiedBadge: 'patch(v1, d_composed) === v_final 逐字节验证通过',
    composeCustomBadge: '多跳 Delta 合并完成',
    composePickWarn: '请先选择至少 2 个 .delta 文件，或点击上方一键演示按钮。',
    composeDlBtn: '下载合并后的 .delta',
    composeSumBar: '原始多代 Delta 体积之和',
    composeDirectBar: '合并后直达单跳 Delta',
    composeGzBar: '合并后 Delta + Gzip',
    composeCliTitle: '等价 Native CLI Delta 链合并命令',
    envCardTitle: 'X25519 多接收方信封加密实验室（MLSENC02 · HKDF-SHA256 + ChaCha20-Poly1305）',
    envGenKeysBtn: '生成 Alice / Bob / Mallory 密钥对',
    envSealBtn: '封装给 Alice + Bob (MLSENC02)',
    envDlBtn: '下载 .menv',
    envRecipientBadge: '授权接收方',
    envOutsiderBadge: '未授权第三方',
    envUnsealAliceBtn: '以 Alice 私钥解密 ✓',
    envUnsealBobBtn: '以 Bob 私钥解密 ✓',
    envUnsealMalloryBtn: '以 Mallory 私钥尝试解密 (拒绝)',
    envTamperBtn: '模拟 1 字节密文篡改 (AuthenticationFailed)',
    quorumCardTitle: 'Ed25519 信任密钥环 & 2-of-3 门限多签实验室（Schema 4 Keyring + Quorum）',
    quorumMinLabel: '门限阈值',
    quorumGenBtn: '生成 3 签名者密钥并实时验签',
    quorumSignedChk: '参与签名',
    quorumRevokedChk: '吊销密钥',
    quorumVerifyBtn: '重新执行门限多签校验',
    quorumTamperBtn: '模拟 1 字节载荷篡改 (DigestMismatch)',
    quorumDlKeyringBtn: '下载 keyring.json',
    quorumDlBundleBtn: '下载 bundle.msig.json',
    quorumJsonToggle: '展开 Schema 4 TrustKeyring & SignatureBundle JSON',
    quorumStateActive: '已签名 · 有效',
    quorumStateRevoked: '已吊销',
    quorumStateUnsigned: '未签名',
  },
  en: {
    subtitle: 'Pure-MoonBit zero-backend browser studio with Web Worker execution, HTTP Range (zsync) pull, delta squashing, Gzip/Zlib, .mbundle.gz, and X25519 / Ed25519 quorum labs',
    tabFile: 'File Sync & Gzip',
    tabRdiff: 'Split-Role rdiff',
    tabInspect: 'Artifact Inspector',
    tabDir: 'Dir Plan & Verify',
    tabLab: 'Security & Crypto Lab',
    fileCardTitle: 'Streaming Signature · Delta · Rollback · Gzip Framing · Literal Hexdump Heatmap',
    sigProfile: 'Profile',
    blockSize: 'Block',
    chunkSize: 'Chunk',
    sumSize: 'Strong Sum',
    runSample: 'Run Built-in 128 KiB Binary Sample',
    runLogSample: 'Run 64 KiB Log Delta Sample (High Gzip Ratio)',
    oldLabel: 'OLD Basis File',
    newLabel: 'NEW Target File',
    dropHint: 'Click to browse or drag & drop a local file',
    localPrivacy: '100% local in-browser Web Worker execution with zero uploads. Exported .sig / .delta / rollback.delta files are wire-compatible with librsync rdiff and CLI.',
    runFiles: 'Diff & Verify Selected Files',
    heatmapTitle: 'Interactive Delta Block Reuse Heatmap',
    heatmapHint: 'Hover or click any segment above for instruction details; click any amber Literal segment for a Hexdump + UTF-8 payload preview',
    heatmapTruncated: (shown, total) => `Showing first ${shown} of ${total} instructions`,
    heatmapTableToggle: (n) => `Show ordered instruction table (top ${n})`,
    litPreviewTitle: (shown, total, trunc) =>
      `Literal Payload Hexdump Preview (first ${shown} B of ${total} B${trunc ? ' · truncated' : ''})`,
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
    inspectCardTitle: 'Universal Artifact Inspector (.sig · .delta · .gz · .zlib · .mbundle · .menc · MLSENC02 · Schema 1/2/3/4 JSON)',
    inspectSampleDelta: 'Inspect Sample .delta (+ Heatmap)',
    inspectSampleSig: 'Inspect Sample .sig (0x72730137)',
    inspectSampleSeal: 'Inspect Sample .menc',
    inspectSampleEnvelope: 'Inspect Sample MLSENC02',
    inspectSampleKeyring: 'Inspect Sample Keyring',
    inspectSamplePubSig: 'Inspect Sample .msig.json',
    inspectDropLabel: 'Drop any MoonLibSync binary or JSON artifact to inspect',
    inspectDropHint: 'Supports .sig / .delta / .gz / .zlib / .mbundle / .menc / MLSENC02 / Keyring / Signature Bundle / Dir Metadata / Schema 1/2/3/4 JSON',
    inspectRawJson: 'Show Raw Inspector JSON',
    inspectInnerDelta: 'Inner Gzip payload is a standard 0x72730236 delta — Block Reuse Heatmap & Literal Hexdump rendered below',
    inspectInnerBundle: 'Inner Gzip payload is a single-file MLSBDL01 directory bundle archive (.mbundle.gz)',
    dirCardTitle: 'In-Browser Schema 3 Directory Snapshot, Move Detect, Audit & .mbundle.gz Packing',
    dirModePlan: 'Sync Plan (dir-plan)',
    dirModeVerify: 'Integrity Audit (dir-verify)',
    dirModeBundle: 'Pack & Unpack (.mbundle.gz)',
    runDirSample: 'Run Built-in Sample Folder Pair',
    runDirVerifyCleanSample: 'Run Clean Verify Sample (OK)',
    basisDirLabel: 'BASIS Folder (Old / Expected Baseline)',
    targetDirLabel: 'TARGET Folder (New / Actual Observed)',
    pickDirHint: 'Click to select a local folder',
    dirExcludeLabel: '--exclude patterns (comma-separated)',
    fillExcludePreset: 'Fill Common Preset',
    dirDetectMoves: '--detect-moves (0-Byte Move / Copy Reuse)',
    bundlePanelTitle: 'Single-File Bundle Pack & In-Browser Unpack Verification (MLSBDL01 / .mbundle.gz)',
    bundleGzipLabel: 'Compress with RFC 1952 Gzip (.mbundle.gz)',
    bundlePackSampleBtn: 'Pack Built-in Sample to .mbundle.gz',
    bundlePackFoldersBtn: 'Pack Selected BASIS + TARGET Folders',
    bundleUnpackDropLabel: 'Drop a .mbundle or .mbundle.gz archive to unpack & verify every SHA-256',
    bundleUnpackHint: 'Reconstructs against BASIS folder above (or built-in sample basis if none selected) and verifies every file SHA-256',
    bundleFooterHint: 'Supports 0-byte CopyFromBasis reuse, cross-path UpdateDeltaFrom, automatic Gzip decompression, and full SHA-256 verification.',
    bundleUnpackBtn: 'Unpack & Verify Selected Archive',
    bundlePickArchiveWarn: 'Drop a .mbundle / .mbundle.gz file first, or click "Pack Built-in Sample" and use One-Click Roundtrip Unpack.',
    bundleDlArchive: (isGz) => (isGz ? 'Download .mbundle.gz' : 'Download .mbundle'),
    bundleRoundtripBtn: 'One-Click Roundtrip Unpack & Verify',
    bundleUnpackOkBadge: (n) => `✓ All ${n} Files SHA-256 Verified`,
    bundleDownloadFile: 'Download',
    dirHint: 'Applies --exclude globs, --detect-moves content-digest reuse, POSIX path hygiene, and cross-platform ASCII case-folding collision detection.',
    runDirDiff: 'Generate Schema 3 Sync Plan',
    runDirVerify: 'Run dir-verify Audit',
    verifyOkBadge: 'VERIFIED OK · Exact Directory Match',
    verifyDriftBadge: 'DRIFT DETECTED · Integrity Differences Found',
    verifyNoIssues: 'Zero drift: every file length and SHA-256 matches the expected baseline snapshot.',
    expectedCol: 'Expected Baseline',
    actualCol: 'Actual Observed',
    issueKindCol: 'Drift Kind',
    engineReady: 'MoonBit pure-JS engine ready (v0.7.1 · zero backend · zero C FFI · 37 core exports)',
    workerBadgeActive: 'Web Worker Thread',
    workerBadgeFallback: 'Main-Thread Fallback',
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
    dlRollback: 'Download Rollback Delta',
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
    labTitle: 'Bounded Gzip / Zlib Security Defense Lab (Zip-Bomb · Trailing · Truncated)',
    runAllLab: 'Run All 3 Security Drills',
    labBombTitle: '1. Zip-Bomb Decompression Guard',
    labBombDesc: 'Compresses 256 KiB of zeros (~300 B bomb) live in-browser and decompresses under a 4 KiB cap, proving immediate LimitExceeded cutoff.',
    labBombBtn: 'Run Zip-Bomb Drill',
    labTrailTitle: '2. Trailing Garbage Rejection',
    labTrailDesc: 'Appends 1 extra byte (0x42) after a valid single-member Gzip (CRC32/ISIZE) or Zlib (Adler-32) trailer, proving strict TrailingData rejection.',
    labTrailBtn: 'Run TrailingData Drill',
    labTruncTitle: '3. Truncated Trailer Rejection',
    labTruncDesc: 'Removes the final byte of the checksum trailer (CRC32/ISIZE or Adler-32), proving TruncatedInput rejection with zero silent partial output.',
    labTruncBtn: 'Run TruncatedInput Drill',
    labCustomTitle: 'Custom Text Bounded Gzip / Zlib Round-Trip Playground',
    labLevel: 'Level',
    labMaxOut: 'Max Output (B)',
    labRunCustom: 'Compress & Bounded Decompress',
    edCardTitle: 'Ed25519 Publisher Sign & Verify Lab (RFC 8032 · Schema 4 .msig.json)',
    edGenKeyBtn: 'Generate Random Ed25519 Keypair',
    edSignBtn: 'Sign & Generate .msig.json',
    edDlSigBtn: 'Download .msig.json',
    edVerifyValidBtn: 'Verify Valid',
    edVerifyTamperBtn: 'Simulate 1-Byte Payload Tamper (DigestMismatch)',
    edVerifyUntrustedBtn: 'Simulate Untrusted Key (UntrustedKey)',
    aeadCardTitle: 'AEAD Streaming Encryption Lab (MLSENC01 · ChaCha20-Poly1305 + Argon2id .menc)',
    aeadKdfLabel: 'Key Mode',
    aeadMemLabel: 'Argon2 Memory',
    aeadPassesLabel: 'Passes',
    aeadSecretLabel: 'Passphrase / 32-Byte Hex Key',
    aeadGenRawKeyBtn: 'Generate Random 32B Key',
    aeadSealBtn: 'Seal to .menc',
    aeadDlMencBtn: 'Download .menc',
    aeadUnsealBtn: 'Unseal & Verify SHA-256',
    aeadTamperBtn: 'Simulate 1-Byte Ciphertext Tamper (AuthenticationFailed)',
    rangeCardTitle: 'Static HTTP Range (zsync) Incremental Pull Simulator & Live CORS Fetch',
    rangeModeSim: 'Local CDN Simulator',
    rangeModeLive: 'Live Static CORS URL',
    rangeProfileLabel: 'Profile',
    rangeMergeGapLabel: 'Merge Gap',
    rangeMergeGapZero: '0 B (No merge)',
    rangeSigVerifiedBadge: 'Signature BLAKE2b Verified',
    runRangeSimBtn: 'Run 1-Click 128 KiB HTTP Range Pull Simulation (v1 → v2)',
    rangeSimHint: 'Zero server-side diffing: plan minimal HTTP Range requests from static v2.sig + local v1 basis, simulate HTTP 206 Partial Content fetches, and verify bit-exact reconstruction.',
    rangeTargetUrlLabel: 'Remote Target File URL (CORS + HTTP 206 Range enabled)',
    rangeSigUrlLabel: 'Remote .sig Signature URL (blank = auto-append .sig)',
    rangeLiveBasisLabel: 'Local OLD Basis File (Optional)',
    rangeLiveBasisHint: 'Optional: drop your local old version to maximize block reuse (empty basis if omitted)',
    rangeLiveHint: 'Requires remote static host to send Access-Control-Allow-Origin and allow Range request + Content-Range response headers.',
    runRangeLiveBtn: 'Fetch Remote via HTTP Range & Reconstruct',
    rangeSavedLabel: 'HTTP Bandwidth Saved (Static Range Pull)',
    rangePillsTitle: 'HTTP Range Request Spans (RFC 9110)',
    rangeZeroRanges: 'Zero network requests needed: local basis already has 100% of target blocks!',
    rangeUrlRequired: 'Please enter a remote target file URL (https://...) first.',
    rangeDlPlanBtn: 'Download range-plan.json',
    rangeDlRestoredBtn: 'Download Reconstructed Target',
    rangeCliTitle: 'Equivalent Native CLI Static Range Pull Commands',
    composeCardTitle: 'Zero-Intermediate Delta Chain Squashing (v1 → v2 → v3 ⇒ v1 → v3)',
    runCompose2Btn: '1-Click 2-Hop Squash (v1→v2→v3)',
    runCompose3Btn: '1-Click 3-Hop Squash (v1→v2→v3→v4)',
    composeDesc: 'Algebraically squash chained deltas into one direct v1 → vN patch without materializing v2/v3, collapsing overwrites and coalescing adjacent COPY/Literal ops.',
    composeDropLabel: 'Or select / drop 2+ ordered .delta files to compose',
    composeDropHint: 'Composed in filename order into a single wire-standard 0x72730236 delta ready for download',
    composeFooterHint: 'Output is wire-standard 0x72730236 librsync delta compatible with apply_patch and native librsync rdiff.',
    runComposeCustomBtn: 'Compose Selected .delta Chain',
    composeSavedLabel: 'Delta Chain Size Reduction',
    composeVerifiedBadge: 'patch(v1, d_composed) === v_final Bit-Exact Verified',
    composeCustomBadge: 'Delta Chain Composed',
    composePickWarn: 'Please select at least 2 .delta files, or click a 1-click demo button above.',
    composeDlBtn: 'Download Composed .delta',
    composeSumBar: 'Sum of Individual Deltas',
    composeDirectBar: 'Squashed Direct Delta',
    composeGzBar: 'Squashed Delta + Gzip',
    composeCliTitle: 'Equivalent Native CLI Delta Chain Composition Command',
    envCardTitle: 'X25519 Multi-Recipient Envelope Lab (MLSENC02 · HKDF-SHA256 + ChaCha20-Poly1305)',
    envGenKeysBtn: 'Generate Alice / Bob / Mallory Keypairs',
    envSealBtn: 'Seal for Alice + Bob (MLSENC02)',
    envDlBtn: 'Download .menv',
    envRecipientBadge: 'Authorized Recipient',
    envOutsiderBadge: 'Unauthorized Outsider',
    envUnsealAliceBtn: 'Decrypt as Alice ✓',
    envUnsealBobBtn: 'Decrypt as Bob ✓',
    envUnsealMalloryBtn: 'Try Decrypt as Mallory (Rejected)',
    envTamperBtn: 'Simulate 1-Byte Ciphertext Tamper (AuthenticationFailed)',
    quorumCardTitle: 'Ed25519 Trust Keyring & 2-of-3 Threshold Quorum Lab (Schema 4 Keyring + Quorum)',
    quorumMinLabel: 'Quorum Threshold',
    quorumGenBtn: 'Generate 3 Signer Keys & Verify Live',
    quorumSignedChk: 'Include Sig',
    quorumRevokedChk: 'Revoked',
    quorumVerifyBtn: 'Re-Run Quorum Verification',
    quorumTamperBtn: 'Simulate 1-Byte Payload Tamper (DigestMismatch)',
    quorumDlKeyringBtn: 'Download keyring.json',
    quorumDlBundleBtn: 'Download bundle.msig.json',
    quorumJsonToggle: 'Show Schema 4 TrustKeyring & SignatureBundle JSON',
    quorumStateActive: 'Signed · Active',
    quorumStateRevoked: 'Revoked',
    quorumStateUnsigned: 'Unsigned',
  },
};

let lang = (navigator.language || '').toLowerCase().startsWith('zh') ? 'zh' : 'en';
let theme = window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
let engineClient = null;
let engineMode = null; // 'worker' | 'main'
let engineLoadPromise = null;

// Tab 1 state
let lastResultState = null;
let lastArtifacts = null;
let lastInputs = null;
let lastDetailState = null;
let lastBenchmarkState = null;

// Tab 2 v0.7.0 state
let rangePullMode = 'sim'; // 'sim' | 'live'
let lastRangePullState = null;
let lastComposeState = null;
let rangeLiveBasisFileObj = null;
let composeFileObjs = [];

// Tab 3 state
let lastInspectState = null;

// Tab 4 state
let dirMode = 'plan'; // 'plan' | 'verify' | 'bundle'
let lastDirState = null;
let currentDirFilter = 'all';
let currentDirSearch = '';
let droppedBundleArchiveFile = null;
let lastPackedBundle = null; // { archiveBytes, isGz, basisFilesJson, packRes }

// Tab 5 Crypto Lab state
let labFormat = 'gzip'; // 'gzip' | 'zlib'
let edState = null; // { seed, keyId, publicKeyHex, lastSigJson, lastPayloadBytes }
let aeadState = null; // { cipherBytes, usePassphrase, secretBytes }
let envState = null; // { alice, bob, mallory, cipherBytes, sealRes }
let quorumState = null; // { signers: [{name, seed, kp}], lastKeyringJson, lastBundleJson }

const statusBar = document.getElementById('statusBar');
const statusText = document.getElementById('statusText');
const statusAction = document.getElementById('statusAction');
const engineProgressFill = document.getElementById('engineProgressFill');
const resultsEl = document.getElementById('results');
const inspectResultsEl = document.getElementById('inspectResults');
const dirResultsEl = document.getElementById('dirResults');
const oldInput = document.getElementById('oldFile');
const newInput = document.getElementById('newFile');
const oldMeta = document.getElementById('oldMeta');
const newMeta = document.getElementById('newMeta');
const oldDrop = document.getElementById('oldDrop');
const newDrop = document.getElementById('newDrop');
const sigProfileSelect = document.getElementById('sigProfile');
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
const dirDetectMovesCheckbox = document.getElementById('dirDetectMoves');
const dirModePlanBtn = document.getElementById('dirModePlan');
const dirModeVerifyBtn = document.getElementById('dirModeVerify');
const dirModeBundleBtn = document.getElementById('dirModeBundle');
const dirBundlePanel = document.getElementById('dirBundlePanel');
const bundleGzipToggle = document.getElementById('bundleGzipToggle');
const runBundleSamplePackBtn = document.getElementById('runBundleSamplePack');
const runBundleFolderPackBtn = document.getElementById('runBundleFolderPack');
const bundleUnpackDrop = document.getElementById('bundleUnpackDrop');
const bundleUnpackFile = document.getElementById('bundleUnpackFile');
const bundleUnpackMeta = document.getElementById('bundleUnpackMeta');
const runBundleUnpackBtn = document.getElementById('runBundleUnpackBtn');
const runDirSampleBtn = document.getElementById('runDirSample');
const runDirVerifyCleanSampleBtn = document.getElementById('runDirVerifyCleanSample');
const runDirDiffBtn = document.getElementById('runDirDiff');
const runDirVerifyBtn = document.getElementById('runDirVerify');
const langToggle = document.getElementById('langToggle');
const themeToggle = document.getElementById('themeToggle');

let droppedOldFile = null;
let droppedNewFile = null;
let progressHideTimer = null;
let inFlightCount = 0;

function t(key) {
  return I18N[lang][key];
}

function errMessage(err) {
  return err instanceof Error ? err.message : String(err);
}

function escapeHtml(text) {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function fmtBytes(n) {
  const v = Number(n);
  if (v < 1024) return `${v.toLocaleString()} B`;
  if (v < 1048576) return `${(v / 1024).toFixed(1)} KiB`;
  return `${(v / 1048576).toFixed(2)} MiB`;
}

function bytesToHex(bytes) {
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i].toString(16).padStart(2, '0');
  }
  return out;
}

function hexNibble(code) {
  if (code >= 0x30 && code <= 0x39) return code - 0x30;
  if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
  if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10;
  return -1;
}

function hexToBytes(hex) {
  const clean = String(hex || '').trim();
  if (clean.length % 2 !== 0) return new Uint8Array(0);
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    const hi = hexNibble(clean.charCodeAt(i * 2));
    const lo = hexNibble(clean.charCodeAt(i * 2 + 1));
    if (hi < 0 || lo < 0) return new Uint8Array(0);
    out[i] = (hi << 4) | lo;
  }
  return out;
}

function toHexPreview(bytes, maxLen = 28) {
  const n = Math.min(bytes.length, maxLen);
  const parts = [];
  for (let i = 0; i < n; i++) {
    parts.push(bytes[i].toString(16).padStart(2, '0'));
  }
  return parts.join(' ') + (bytes.length > maxLen ? ' ...' : '');
}

function formatHexdump(previewHex, previewUtf8, baseOffset = 0) {
  const hex = String(previewHex || '');
  const text = String(previewUtf8 || '');
  const byteLen = Math.floor(hex.length / 2);
  if (byteLen === 0) return '(empty literal)';
  const hasMultibyte = text.length !== byteLen;
  const lines = [];
  for (let row = 0; row < byteLen; row += 16) {
    const offStr = (baseOffset + row).toString(16).padStart(8, '0');
    const left = [];
    const right = [];
    let rowAscii = '';
    for (let i = 0; i < 16; i++) {
      const idx = row + i;
      if (idx < byteLen) {
        const cell = hex.slice(idx * 2, idx * 2 + 2);
        if (i < 8) left.push(cell);
        else right.push(cell);
        if (hasMultibyte) {
          const hi = hexNibble(cell.charCodeAt(0));
          const lo = hexNibble(cell.charCodeAt(1));
          const b = hi >= 0 && lo >= 0 ? (hi << 4) | lo : 0;
          rowAscii += b >= 0x20 && b < 0x7f ? String.fromCharCode(b) : '.';
        }
      } else {
        if (i < 8) left.push('  ');
        else right.push('  ');
      }
    }
    const textSlice = hasMultibyte ? rowAscii : text.slice(row, Math.min(byteLen, row + 16));
    lines.push(`${offStr}  ${left.join(' ')}  ${right.join(' ')}  |${textSlice}|`);
  }
  if (hasMultibyte && text.length > 0) {
    lines.push(`UTF-8: ${text}`);
  }
  return lines.join('\n');
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

function setProgress(pct) {
  if (!engineProgressFill) return;
  if (progressHideTimer) {
    clearTimeout(progressHideTimer);
    progressHideTimer = null;
  }
  if (pct <= 0) {
    if (inFlightCount > 0) return;
    engineProgressFill.classList.remove('active');
    engineProgressFill.style.width = '0%';
    return;
  }
  if (pct >= 100 && inFlightCount > 0) {
    engineProgressFill.classList.add('active');
    engineProgressFill.style.width = '85%';
    return;
  }
  engineProgressFill.classList.add('active');
  engineProgressFill.style.width = `${Math.min(100, Math.max(8, pct))}%`;
  if (pct >= 100) {
    progressHideTimer = setTimeout(() => {
      if (inFlightCount > 0) return;
      engineProgressFill.classList.remove('active');
      engineProgressFill.style.width = '0%';
    }, 320);
  }
}

function renderEngineStatusBadge() {
  if (!engineMode) return;
  statusText.textContent = t('engineReady');
  if (engineMode === 'worker') {
    statusAction.innerHTML = `<span class="worker-pill">⚡ ${escapeHtml(t('workerBadgeActive'))}</span>`;
  } else {
    statusAction.innerHTML = `<span class="worker-pill fallback">● ${escapeHtml(t('workerBadgeFallback'))}</span>`;
  }
}

// =========================================================================
// Zero-Dependency Web Worker EngineClient (with Main-Thread Fallback)
// =========================================================================
class WorkerEngineClient {
  constructor(worker) {
    this.worker = worker;
    this.nextId = 1;
    this.pending = new Map();
    this.proxy = null;
    this.dead = false;
    this.worker.addEventListener('message', (ev) => {
      const msg = ev.data || {};
      if (msg.type === 'progress') {
        const pct = Number(msg.pct);
        setProgress(Number.isFinite(pct) ? pct : 50);
        return;
      }
      const entry = this.pending.get(msg.id);
      if (!entry) return;
      this.pending.delete(msg.id);
      inFlightCount = Math.max(0, inFlightCount - 1);
      if (msg.ok) {
        if (inFlightCount === 0) setProgress(100);
        entry.resolve(msg.result);
      } else {
        if (inFlightCount === 0) setProgress(0);
        entry.reject(new Error(msg.error || 'Worker call failed'));
      }
    });
    this.worker.addEventListener('error', (err) => {
      this.terminateWithError(new Error(err.message || 'Web Worker error'));
    });
  }

  terminateWithError(error) {
    if (this.dead) return;
    this.dead = true;
    const dropped = this.pending.size;
    const entries = Array.from(this.pending.values());
    this.pending.clear();
    inFlightCount = Math.max(0, inFlightCount - dropped);
    if (inFlightCount === 0) setProgress(0);
    try {
      this.worker.terminate();
    } catch (_) {}
    if (this.proxy && engineClient === this.proxy) {
      engineClient = null;
      engineMode = null;
      engineLoadPromise = null;
    }
    for (const entry of entries) entry.reject(error);
  }

  call(method, ...args) {
    return new Promise((resolve, reject) => {
      if (this.dead) {
        reject(new Error('Web Worker has terminated'));
        return;
      }
      const id = this.nextId++;
      this.pending.set(id, { resolve, reject });
      inFlightCount += 1;
      setProgress(18);
      try {
        this.worker.postMessage({ id, method, args });
      } catch (err) {
        this.pending.delete(id);
        inFlightCount = Math.max(0, inFlightCount - 1);
        if (inFlightCount === 0) setProgress(0);
        reject(err);
      }
    });
  }

  asProxy() {
    if (this.proxy) return this.proxy;
    const client = this;
    this.proxy = new Proxy(
      {},
      {
        get(_target, prop) {
          if (prop === 'then' || typeof prop === 'symbol') return undefined;
          return (...args) => client.call(String(prop), ...args);
        },
      },
    );
    return this.proxy;
  }
}

function createMainThreadProxy(rawMod) {
  return new Proxy(
    {},
    {
      get(_target, prop) {
        if (prop === 'then' || typeof prop === 'symbol') return undefined;
        return async (...args) => {
          inFlightCount += 1;
          setProgress(35);
          try {
            const out = rawMod[String(prop)](...args);
            inFlightCount = Math.max(0, inFlightCount - 1);
            if (inFlightCount === 0) setProgress(100);
            return out;
          } catch (err) {
            inFlightCount = Math.max(0, inFlightCount - 1);
            if (inFlightCount === 0) setProgress(0);
            throw err;
          }
        };
      },
    },
  );
}

async function tryInitWorker() {
  if (typeof Worker === 'undefined') {
    throw new Error('Worker API unavailable');
  }
  const worker = new Worker('./worker.js', { type: 'module' });
  const client = new WorkerEngineClient(worker);
  let timeoutId = null;
  const timeoutPromise = new Promise((_, reject) => {
    timeoutId = setTimeout(() => reject(new Error('Worker init timeout')), 15000);
  });
  try {
    await Promise.race([client.call('__init__'), timeoutPromise]);
    clearTimeout(timeoutId);
    return client.asProxy();
  } catch (err) {
    clearTimeout(timeoutId);
    client.terminateWithError(err instanceof Error ? err : new Error(String(err)));
    throw err;
  }
}

async function loadEngine() {
  if (engineClient) return engineClient;
  if (engineLoadPromise) return engineLoadPromise;

  engineLoadPromise = (async () => {
    try {
      engineClient = await tryInitWorker();
      engineMode = 'worker';
      statusBar.className = 'status-bar ok';
      renderEngineStatusBadge();
      return engineClient;
    } catch (_workerErr) {
      // Graceful fallback to main-thread ES module import
      let lastErr = null;
      for (const path of MODULE_PATHS) {
        try {
          const rawMod = await import(path);
          engineClient = createMainThreadProxy(rawMod);
          engineMode = 'main';
          statusBar.className = 'status-bar ok';
          renderEngineStatusBadge();
          return engineClient;
        } catch (err) {
          lastErr = err;
        }
      }
      engineLoadPromise = null;
      statusBar.className = 'status-bar warn';
      statusText.textContent = t('engineMissing');
      setProgress(0);
      throw lastErr || new Error('Failed to load web-demo.js');
    }
  })();
  return engineLoadPromise;
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
    if (el.classList.contains('selected')) continue;
    const key = el.getAttribute('data-i18n');
    if (typeof I18N[lang][key] === 'string') el.textContent = I18N[lang][key];
  }
  langToggle.textContent = lang === 'zh' ? 'English' : '简体中文';
  if (engineClient) {
    renderEngineStatusBadge();
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
  if (typeof basisDirInput !== 'undefined' && typeof basisDirMeta !== 'undefined') {
    updateFolderMeta(basisDirInput, basisDirMeta);
  }
  if (typeof targetDirInput !== 'undefined' && typeof targetDirMeta !== 'undefined') {
    updateFolderMeta(targetDirInput, targetDirMeta);
  }
  if (lastResultState) renderResult(lastResultState.data, lastResultState.elapsedMs);
  if (lastRangePullState) renderRangePullResult(lastRangePullState);
  if (lastComposeState) renderComposeResult(lastComposeState);
  if (lastInspectState) renderInspectResult(lastInspectState);
  if (lastDirState) {
    if (lastDirState.mode === 'verify') renderDirVerify(lastDirState);
    else if (lastDirState.mode === 'bundle-pack') renderBundlePackResult(lastDirState);
    else if (lastDirState.mode === 'bundle-unpack') renderBundleUnpackResult(lastDirState);
    else renderDirPlan(lastDirState);
  }
  if (typeof updateQuorumBadges === 'function') updateQuorumBadges();
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

// =========================================================================
// Shared Component: Interactive Delta Block Reuse Heatmap + Literal Hexdump
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
            : `#${idx} Literal | length=${it.length} B (${pct}%) | out_offset=${it.output_offset} (click for Hexdump)`;
          return `<button type="button" class="hm-seg ${isCopy ? 'copy' : 'literal'}" data-hm="${prefix}" data-idx="${idx}" style="flex:${Math.max(1, len)} 0 auto;min-width:${minW};" title="${escapeHtml(tip)}" aria-label="${escapeHtml(tip)}"></button>`;
        })
        .join('') + tailHtml;

  const rowsHtml = items
    .map((it, idx) => {
      const isCopy = it.kind === 'copy';
      const previewCell = !isCopy && it.preview_utf8
        ? `<code style="font-size:0.74rem;color:var(--amber-text);">${escapeHtml(it.preview_utf8.slice(0, 32))}${it.preview_utf8.length > 32 || it.preview_truncated ? '…' : ''}</code>`
        : '—';
      return `<tr class="hm-row" data-hm-row="${prefix}" data-idx="${idx}" style="cursor:pointer;">
        <td><code>#${idx}</code></td>
        <td><span class="badge ${isCopy ? 'badge-add' : 'badge-update'}">${isCopy ? 'COPY' : 'Literal'}</span></td>
        <td><code>${isCopy ? Number(it.offset).toLocaleString() : '—'}</code></td>
        <td><code>${Number(it.length).toLocaleString()} B</code> (${fmtBytes(it.length)})</td>
        <td><code>${Number(it.output_offset).toLocaleString()}</code></td>
        <td>${previewCell}</td>
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
      <div id="${prefix}-hexbox" class="literal-preview-box" hidden></div>
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
                <th>Preview</th>
              </tr>
            </thead>
            <tbody>${rowsHtml || '<tr><td colspan="6" style="text-align:center;color:var(--text-subtle);">No instructions</td></tr>'}</tbody>
          </table>
        </div>
      </details>
    </div>
  `;
}

function wireHeatmapEvents(rootEl, detail, prefix) {
  if (!detail || !detail.ok) return;
  const tipEl = rootEl.querySelector(`#${prefix}-tip`);
  const hexBox = rootEl.querySelector(`#${prefix}-hexbox`);
  if (!tipEl) return;
  const items = detail.items || [];
  const totalOut = Math.max(1, Number(detail.summary.output_bytes));
  const showItem = (idx, btn) => {
    const it = items[idx];
    if (!it) return;
    for (const s of rootEl.querySelectorAll(`.hm-seg[data-hm="${prefix}"]`)) {
      s.classList.toggle('active', btn ? s === btn : Number(s.dataset.idx) === idx);
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
    if (hexBox) {
      if (!isCopy && typeof it.preview_hex === 'string') {
        const shownBytes = Math.floor(it.preview_hex.length / 2);
        const dump = formatHexdump(it.preview_hex, it.preview_utf8 || '', outStart);
        hexBox.innerHTML = `
          <div class="lit-head">
            <span>${escapeHtml(I18N[lang].litPreviewTitle(shownBytes, len, !!it.preview_truncated))}</span>
            <span>out=0x${outStart.toString(16).padStart(8, '0')}</span>
          </div>
          <pre class="lit-hexdump">${escapeHtml(dump)}</pre>
        `;
        hexBox.hidden = false;
      } else {
        hexBox.hidden = true;
      }
    }
  };
  for (const btn of rootEl.querySelectorAll(`.hm-seg[data-hm="${prefix}"]`)) {
    const idx = Number(btn.dataset.idx);
    btn.addEventListener('mouseenter', () => showItem(idx, btn));
    btn.addEventListener('focus', () => showItem(idx, btn));
    btn.addEventListener('click', () => showItem(idx, btn));
  }
  for (const tr of rootEl.querySelectorAll(`.hm-row[data-hm-row="${prefix}"]`)) {
    const idx = Number(tr.dataset.idx);
    tr.addEventListener('click', () => showItem(idx, null));
  }
}

// =========================================================================
// Tab 1: File Sync, Profile Selection, Rollback, Heatmap & Benchmark
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
  const sigMagic = data.sig_magic || '0x72730147';
  const sigProfile = data.sig_profile || 'rk-blake2';
  const copyPct = newBytes > 0 ? ((copyBytes / newBytes) * 100).toFixed(1) : '100.0';
  const deltaPct = newBytes > 0 ? ((deltaBytes / newBytes) * 100).toFixed(2) : '0.00';
  const gzPct = newBytes > 0 ? ((gzBytes / newBytes) * 100).toFixed(2) : '0.00';
  const savedPct = newBytes > 0 ? Math.max(0, (1 - gzBytes / newBytes) * 100).toFixed(2) : '0.00';
  const gzGain = gzBytes > 0 ? (deltaBytes / gzBytes).toFixed(2) : '1.00';
  const rollbackLen = lastArtifacts?.rollbackDelta?.length || 0;

  const hexSection = lastArtifacts
    ? `
      <details class="wire-box">
        <summary>${escapeHtml(t('wireInspect'))}</summary>
        <div class="hex-grid">
          <div class="hex-card"><div class="hex-title">.sig (${escapeHtml(sigMagic)} · ${sigBytes} B)</div>${escapeHtml(toHexPreview(lastArtifacts.sig))}</div>
          <div class="hex-card"><div class="hex-title">.delta (0x72730236 · ${deltaBytes} B)</div>${escapeHtml(toHexPreview(lastArtifacts.delta))}</div>
          <div class="hex-card"><div class="hex-title">.delta.gz (RFC 1952 · ${gzBytes} B)</div>${escapeHtml(toHexPreview(lastArtifacts.deltaGz))}</div>
          <div class="hex-card"><div class="hex-title">rollback.delta (NEW → OLD · ${rollbackLen} B)</div>${escapeHtml(toHexPreview(lastArtifacts.rollbackDelta))}</div>
        </div>
      </details>
    `
    : '';

  const blockArg = Number(blockSelect.value) === 0 ? 'auto' : String(blockSelect.value);
  const sumArg = String(sumSelect.value);
  const profileFlag = sigProfile === 'rollsum-blake2' ? ' --profile rollsum-blake2' : '';
  const oldName = (lastArtifacts?.baseName || 'old.bin').replaceAll('"', '');
  const newName = (lastArtifacts?.newName || 'new.bin').replaceAll('"', '');
  const cliCmd = [
    `moonlibsync signature "${oldName}" "${oldName}.sig" --streaming --block-size ${blockArg} --sum-size ${sumArg}${profileFlag}`,
    `moonlibsync delta "${oldName}.sig" "${newName}" "${oldName}.delta" --streaming`,
    `moonlibsync compress "${oldName}.delta" "${oldName}.delta.gz" --streaming`,
    `moonlibsync patch "${oldName}" "${oldName}.delta" "restored-${newName}" --streaming`,
    `moonlibsync reverse-delta "${oldName}" "${newName}" "${oldName}.rollback.delta"`,
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
        <div class="pipe-name">Signature (${escapeHtml(sigMagic)})</div>
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
        <div class="stat-label">Signature (${escapeHtml(sigMagic)})</div>
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
          <button id="dlRollback" class="btn btn-primary btn-sm" type="button">${escapeHtml(t('dlRollback'))}</button>
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
    const outEl = document.getElementById('benchmarkOut');
    try {
      const mod = await loadEngine();
      const raw = await mod.benchmark_block_sizes_json(lastInputs.oldBuf, lastInputs.newBuf, Number(sumSelect.value));
      lastBenchmarkState = JSON.parse(raw);
      if (outEl) outEl.innerHTML = buildBenchmarkContentHtml(lastBenchmarkState);
    } catch (err) {
      if (outEl) {
        outEl.innerHTML = `<div class="card err-card" style="margin-top:0.8rem;margin-bottom:0;"><strong>Benchmark Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
      }
    }
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
  document.getElementById('dlRollback').addEventListener('click', () => {
    if (lastArtifacts?.rollbackDelta?.length) {
      downloadBlob(lastArtifacts.rollbackDelta, lastArtifacts.baseName + '.rollback.delta');
    }
  });
  document.getElementById('dlRestored').addEventListener('click', () => {
    if (lastArtifacts) downloadBlob(lastArtifacts.restored, 'restored-' + lastArtifacts.newName);
  });
}

async function runSync(oldBuf, newBuf, baseName = 'sample', newName = 'new.bin') {
  const mod = await loadEngine();
  const profile = sigProfileSelect.value || 'rk-blake2';
  const blockLen = Number(blockSelect.value);
  const chunkSize = Number(chunkSelect.value);
  const sumLen = Number(sumSelect.value);
  const t0 = performance.now();

  let parsed = null;
  let sig = null;
  let delta = null;
  let deltaGz = null;
  let restored = null;
  let rollbackDelta = null;
  let detail = null;

  if (profile === 'rk-blake2') {
    const json = await mod.run_streaming_sync_json(oldBuf, newBuf, blockLen, sumLen, chunkSize);
    parsed = JSON.parse(json);
    if (parsed.ok) {
      parsed.sig_magic = '0x72730147';
      parsed.sig_profile = 'rk-blake2';
      sig = await mod.create_signature_with_profile_bytes(oldBuf, blockLen, sumLen, 'rk-blake2');
      delta = await mod.create_delta_bytes(sig, newBuf);
      deltaGz = await mod.compress_gzip_bytes(delta, 6);
      restored = await mod.apply_patch_bytes(oldBuf, delta);
      rollbackDelta = await mod.create_reverse_delta_bytes(oldBuf, newBuf, blockLen, sumLen);
      detail = JSON.parse(await mod.inspect_delta_detailed_json(delta, 512));
    }
  } else {
    sig = await mod.create_signature_with_profile_bytes(oldBuf, blockLen, sumLen, profile);
    if (!sig.length) {
      parsed = { ok: false, error: 'InvalidSignatureProfileOrOptions' };
    } else {
      delta = await mod.create_delta_bytes(sig, newBuf);
      if (!delta.length) {
        parsed = { ok: false, error: 'DeltaGenerationFailed' };
      } else {
        deltaGz = await mod.compress_gzip_bytes(delta, 6);
        if (!deltaGz.length) {
          parsed = { ok: false, error: 'GzipCompressionFailed' };
        } else {
          restored = await mod.apply_patch_bytes(oldBuf, delta);
          rollbackDelta = await mod.create_reverse_delta_bytes(oldBuf, newBuf, blockLen, sumLen);
          const sigIns = JSON.parse(await mod.inspect_artifact_json(sig));
          detail = JSON.parse(await mod.inspect_delta_detailed_json(delta, 512));
          if (!detail.ok) {
            parsed = { ok: false, error: detail.error || 'InvalidDelta' };
          } else {
            const [oldSha, newSha, recSha] = await Promise.all([
              mod.sha256_hex_bytes(oldBuf),
              mod.sha256_hex_bytes(newBuf),
              mod.sha256_hex_bytes(restored),
            ]);
            const sum = detail.summary || {};
            const sigSum = sigIns.summary || {};
            parsed = {
              ok: true,
              sig_magic: sigSum.magic || '0x72730137',
              sig_profile: 'rollsum-blake2',
              block_len: sigSum.block_len || String(blockLen),
              strong_sum_len: sigSum.strong_sum_len || String(sumLen),
              old_bytes: String(oldBuf.length),
              new_bytes: String(newBuf.length),
              signature_bytes: String(sig.length),
              delta_bytes: String(delta.length),
              gzip_delta_bytes: String(deltaGz.length),
              copy_bytes: sum.copy_bytes || '0',
              literal_bytes: sum.literal_bytes || '0',
              instruction_count: sum.instruction_count || '0',
              copy_commands: sum.copy_commands || '0',
              literal_commands: sum.literal_commands || '0',
              old_sha256: oldSha,
              new_sha256: newSha,
              restored_sha256: recSha,
              verified: recSha === newSha && restored.length === newBuf.length,
            };
          }
        }
      }
    }
  }

  const elapsed = performance.now() - t0;
  lastInputs = { oldBuf, newBuf, baseName, newName };
  lastBenchmarkState = null;
  if (parsed && parsed.ok) {
    lastArtifacts = { sig, delta, deltaGz, rollbackDelta, restored, baseName, newName };
    lastDetailState = detail;
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
  const patchA = new TextEncoder().encode('MOONLIBSYNC-070-HEADER-EDIT-SEGMENT '.repeat(6));
  const patchB = new TextEncoder().encode(
    'MOONLIBSYNC-BROWSER-WORKER-LITERAL-HEXDUMP-LINE '.repeat(12),
  );
  newBuf.set(patchA, 20480);
  newBuf.set(patchB, 65536);
  return { oldBuf, newBuf };
}

async function runBuiltInBinarySample() {
  try {
    const { oldBuf, newBuf } = makeBuiltInBinaryPair();
    await runSync(oldBuf, newBuf, 'sample-128k', 'sample-new.bin');
  } catch (err) {
    resultsEl.innerHTML = `<div class="card err-card"><strong>Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
}

sampleBtn.addEventListener('click', runBuiltInBinarySample);

logSampleBtn.addEventListener('click', async () => {
  try {
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
  } catch (err) {
    resultsEl.innerHTML = `<div class="card err-card"><strong>Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

runFilesBtn.addEventListener('click', async () => {
  const oldFile = droppedOldFile || oldInput.files?.[0];
  const newFile = droppedNewFile || newInput.files?.[0];
  if (!oldFile || !newFile) {
    resultsEl.innerHTML = `<div class="card err-card">${escapeHtml(t('pickBothWarn'))}</div>`;
    return;
  }
  try {
    const [oldArr, newArr] = await Promise.all([oldFile.arrayBuffer(), newFile.arrayBuffer()]);
    await runSync(new Uint8Array(oldArr), new Uint8Array(newArr), oldFile.name, newFile.name);
  } catch (err) {
    resultsEl.innerHTML = `<div class="card err-card"><strong>Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

// =========================================================================
// Tab 2: Split-Role rdiff (Generate .sig / Generate .delta / Apply & Verify)
// =========================================================================
const rdiffSigProfile = document.getElementById('rdiffSigProfile');
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
  try {
    const mod = await loadEngine();
    const oldBytes = new Uint8Array(await file.arrayBuffer());
    const profile = rdiffSigProfile.value || 'rk-blake2';
    const blockLen = Number(rdiffSigBlock.value);
    const sumLen = Number(rdiffSigSum.value);
    const t0 = performance.now();
    const sigBytes = await mod.create_signature_with_profile_bytes(oldBytes, blockLen, sumLen, profile);
    const elapsed = performance.now() - t0;
    if (!sigBytes.length) {
      rdiffSigOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Error:</strong> failed to generate signature (check size limits)</div>`;
      return;
    }
    const [inspectedRaw, sigSha, oldSha] = await Promise.all([
      mod.inspect_artifact_json(sigBytes),
      mod.sha256_hex_bytes(sigBytes),
      mod.sha256_hex_bytes(oldBytes),
    ]);
    const inspected = JSON.parse(inspectedRaw);
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
  } catch (err) {
    rdiffSigOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

rdiffGenDeltaBtn.addEventListener('click', async () => {
  const sigFile = rdiffFiles.deltaSig || rdiffDeltaSigFile.files?.[0];
  const newFile = rdiffFiles.deltaNew || rdiffDeltaNewFile.files?.[0];
  if (!sigFile || !newFile) {
    rdiffDeltaOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;">${escapeHtml(t('rdiffPickSigNew'))}</div>`;
    return;
  }
  try {
    const mod = await loadEngine();
    const [sigArr, newArr] = await Promise.all([sigFile.arrayBuffer(), newFile.arrayBuffer()]);
    const sigBytes = new Uint8Array(sigArr);
    const newBytes = new Uint8Array(newArr);
    const sigCheck = JSON.parse(await mod.inspect_artifact_json(sigBytes));
    if (!sigCheck.ok || sigCheck.artifact_kind !== 'signature') {
      rdiffDeltaOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Invalid .sig:</strong> <code>${escapeHtml(sigCheck.error || sigCheck.artifact_kind || 'InvalidSignature')}</code></div>`;
      return;
    }
    const t0 = performance.now();
    const deltaBytes = await mod.create_delta_bytes(sigBytes, newBytes);
    const gzBytes = deltaBytes.length ? await mod.compress_gzip_bytes(deltaBytes, 6) : new Uint8Array(0);
    const elapsed = performance.now() - t0;
    if (!deltaBytes.length) {
      rdiffDeltaOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Error:</strong> failed to generate delta</div>`;
      return;
    }
    const [detailRaw, deltaSha] = await Promise.all([
      mod.inspect_delta_detailed_json(deltaBytes, 64),
      mod.sha256_hex_bytes(deltaBytes),
    ]);
    const detail = JSON.parse(detailRaw);
    const sum = detail.summary || {};
    const copyPct = newBytes.length > 0 ? ((Number(sum.copy_bytes || 0) / newBytes.length) * 100).toFixed(1) : '100.0';
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
  } catch (err) {
    rdiffDeltaOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

rdiffApplyPatchBtn.addEventListener('click', async () => {
  const oldFile = rdiffFiles.patchOld || rdiffPatchOldFile.files?.[0];
  const deltaFile = rdiffFiles.patchDelta || rdiffPatchDeltaFile.files?.[0];
  const manifestFile = rdiffFiles.patchManifest || rdiffPatchManifestFile.files?.[0] || null;
  if (!oldFile || !deltaFile) {
    rdiffPatchOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;">${escapeHtml(t('rdiffPickOldDelta'))}</div>`;
    return;
  }
  try {
    const mod = await loadEngine();
    const [oldArr, deltaArr, manifestText] = await Promise.all([
      oldFile.arrayBuffer(),
      deltaFile.arrayBuffer(),
      manifestFile ? manifestFile.text() : Promise.resolve(''),
    ]);
    const oldBytes = new Uint8Array(oldArr);
    const deltaOrGz = new Uint8Array(deltaArr);
    const t0 = performance.now();
    const res = JSON.parse(await mod.apply_verified_patch_json(oldBytes, deltaOrGz, manifestText));
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
      ? (res.decompressed_gzip ? await mod.decompress_gzip_bytes(deltaOrGz, 67108864) : deltaOrGz)
      : await mod.apply_patch_or_gzip_bytes(oldBytes, deltaOrGz);

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
  } catch (err) {
    rdiffPatchOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Patch / Verify Failed:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

// --- Card D: Static HTTP Range (zsync) Incremental Pull Simulator & Live CORS Fetch ---
const rangeModeSimBtn = document.getElementById('rangeModeSim');
const rangeModeLiveBtn = document.getElementById('rangeModeLive');
const rangeSimPanel = document.getElementById('rangeSimPanel');
const rangeLivePanel = document.getElementById('rangeLivePanel');
const rangeProfileSelect = document.getElementById('rangeProfileSelect');
const rangeMergeGapSelect = document.getElementById('rangeMergeGapSelect');
const runRangeSimBtn = document.getElementById('runRangeSimBtn');
const rangeTargetUrlInput = document.getElementById('rangeTargetUrl');
const rangeSigUrlInput = document.getElementById('rangeSigUrl');
const rangeLiveBasisDrop = document.getElementById('rangeLiveBasisDrop');
const rangeLiveBasisFile = document.getElementById('rangeLiveBasisFile');
const rangeLiveBasisMeta = document.getElementById('rangeLiveBasisMeta');
const runRangeLiveBtn = document.getElementById('runRangeLiveBtn');
const rangePullOut = document.getElementById('rangePullOut');

function setRangePullMode(mode) {
  rangePullMode = mode;
  rangeModeSimBtn.classList.toggle('active', mode === 'sim');
  rangeModeLiveBtn.classList.toggle('active', mode === 'live');
  rangeSimPanel.hidden = mode !== 'sim';
  rangeLivePanel.hidden = mode !== 'live';
}
rangeModeSimBtn.addEventListener('click', () => setRangePullMode('sim'));
rangeModeLiveBtn.addEventListener('click', () => setRangePullMode('live'));

wireDropzone(rangeLiveBasisDrop, rangeLiveBasisFile, rangeLiveBasisMeta, (f) => {
  rangeLiveBasisFileObj = f;
});

function renderRangePullResult(state) {
  const { plan, applyRes, expectedSha, verified, modeLabel, targetName, mergeGap, elapsedMs, restoredBytes, verifiedBadgeKey } = state;
  const targetLen = Number(plan.target_length);
  const reused = Number(plan.reused_bytes);
  const fetchBytes = Number(plan.fetch_bytes);
  const reqBytes = Number(plan.request_bytes);
  const gapOverhead = Math.max(0, reqBytes - fetchBytes);
  const reusedOnly = Math.max(0, reused - gapOverhead);
  const savedPct = targetLen > 0 ? Math.max(0, (1 - reqBytes / targetLen) * 100).toFixed(2) : '0.00';
  const reusedPct = targetLen > 0 ? ((reused / targetLen) * 100).toFixed(1) : '100.0';
  const barReusedPct = targetLen > 0 ? ((reusedOnly / targetLen) * 100).toFixed(1) : '100.0';
  const fetchPct = targetLen > 0 ? ((fetchBytes / targetLen) * 100).toFixed(1) : '0.0';
  const gapPct = targetLen > 0 ? ((gapOverhead / targetLen) * 100).toFixed(1) : '0.0';
  const ranges = plan.ranges || [];

  const pillsHtml = ranges.length
    ? ranges
        .map(
          (r, idx) =>
            `<span class="range-pill" title="Range #${idx + 1}: start=${r.start}, length=${r.length}"><span>#${idx + 1}</span><code>${escapeHtml(r.http_range)}</code><span class="rp-len">(${fmtBytes(r.length)})</span></span>`,
        )
        .join('')
    : `<span class="badge badge-add">${escapeHtml(t('rangeZeroRanges'))}</span>`;

  const planJsonText = JSON.stringify(plan, null, 2);
  const safeTargetName = String(targetName || 'target.bin').replace(/["`$\\]/g, '_');
  const cliCmd = [
    `moonlibsync signature "${safeTargetName}" "${safeTargetName}.sig" --profile ${plan.profile}`,
    `moonlibsync range-plan "${safeTargetName}.sig" ${targetLen} local-v1.bin --merge-gap ${mergeGap} -o range-plan.json`,
    `moonlibsync fetch-sync "https://cdn.example.com/${safeTargetName}" --basis local-v1.bin --sig "${safeTargetName}.sig" -o "restored-${safeTargetName}" --merge-gap ${mergeGap}`,
  ].join('\n');

  const shaRows = expectedSha
    ? `
      <div class="hash-row"><span class="hash-key">Remote v2 SHA-256</span><span class="hash-val">${escapeHtml(expectedSha)}</span><button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(expectedSha)}" type="button">${escapeHtml(t('copyBtn'))}</button></div>
      <div class="hash-row"><span class="hash-key">Restored SHA-256</span><span class="hash-val">${escapeHtml(applyRes.restored_sha256)}</span><button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(applyRes.restored_sha256)}" type="button">${escapeHtml(t('copyBtn'))}</button></div>
    `
    : `<div class="hash-row"><span class="hash-key">Restored SHA-256</span><span class="hash-val">${escapeHtml(applyRes.restored_sha256)}</span><button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(applyRes.restored_sha256)}" type="button">${escapeHtml(t('copyBtn'))}</button></div>`;

  rangePullOut.innerHTML = `
    <div class="result-hero" style="margin-bottom:0.85rem;">
      <div class="hero-metric">
        <span class="hero-pct">${savedPct}%</span>
        <span class="hero-desc">${escapeHtml(t('rangeSavedLabel'))} · ${fmtBytes(targetLen)} → ${fmtBytes(reqBytes)} (${ranges.length} HTTP Range reqs · ${elapsedMs.toFixed(1)} ms)</span>
      </div>
      <div class="controls-row">
        <span class="verified-pill info">${escapeHtml(modeLabel)} · ${escapeHtml(plan.profile)}</span>
        <span class="verified-pill ${verified ? '' : 'fail'}">${verified ? '✓ ' + escapeHtml(t(verifiedBadgeKey || 'verifiedBadge')) : '✕ ' + escapeHtml(t('mismatchBadge'))}</span>
      </div>
    </div>

    <div class="stats-grid">
      <div class="stat-card"><div class="stat-label">Target Length</div><div class="stat-value">${fmtBytes(targetLen)}</div><div class="stat-sub">block=${plan.block_len} B</div></div>
      <div class="stat-card"><div class="stat-label">Reused Local (CopyLocal)</div><div class="stat-value" style="color:var(--emerald-text)">${fmtBytes(reused)}</div><div class="stat-sub">${reusedPct}% · ${reused.toLocaleString()} B</div></div>
      <div class="stat-card"><div class="stat-label">Minimal Fetch</div><div class="stat-value" style="color:var(--primary)">${fmtBytes(fetchBytes)}</div><div class="stat-sub">${fetchPct}% · ${fetchBytes.toLocaleString()} B</div></div>
      <div class="stat-card"><div class="stat-label">HTTP Request Bytes</div><div class="stat-value">${fmtBytes(reqBytes)}</div><div class="stat-sub">${ranges.length} range(s) · gap +${fmtBytes(gapOverhead)}</div></div>
    </div>

    <div style="margin-bottom:0.85rem;">
      <div class="bar-item-head">
        <span>CopyLocal (${reusedPct}%) · FetchRemote (${fetchPct}%)${gapOverhead > 0 ? ` · Gap Coalesce (+${gapPct}%)` : ''}</span>
        <span>${reqBytes.toLocaleString()} / ${targetLen.toLocaleString()} B</span>
      </div>
      <div class="bar-copy-track" style="background:var(--surface-muted);">
        <div class="bar-seg-reused" style="width:${Math.min(100, Number(barReusedPct))}%">${Number(barReusedPct) >= 12 ? `Reused ${reusedPct}%` : ''}</div>
        <div class="bar-seg-fetch" style="width:${Math.min(100, Number(fetchPct))}%">${Number(fetchPct) >= 10 ? `Fetch ${fetchPct}%` : ''}</div>
        ${gapOverhead > 0 ? `<div class="bar-seg-gap" style="width:${Math.min(100, Number(gapPct))}%" title="Coalesced gap overhead: ${gapOverhead} B"></div>` : ''}
      </div>
    </div>

    <div style="margin-bottom:0.85rem;">
      <div class="stat-label" style="margin-bottom:0.2rem;">${escapeHtml(t('rangePillsTitle'))}</div>
      <div class="range-pills">${pillsHtml}</div>
    </div>

    <div class="hash-list" style="margin-bottom:0.75rem;">${shaRows}</div>

    <div class="controls-row">
      <button id="rangeDlPlanBtn" class="btn btn-secondary btn-sm" type="button">${escapeHtml(t('rangeDlPlanBtn'))}</button>
      <button id="rangeDlRestoredBtn" class="btn btn-teal btn-sm" type="button">${escapeHtml(t('rangeDlRestoredBtn'))}</button>
    </div>

    <div class="cli-wrap">
      <div class="cli-head">
        <span>${escapeHtml(t('rangeCliTitle'))}</span>
        <button id="copyRangeCli" class="btn btn-secondary btn-sm" type="button">${escapeHtml(t('copyBtn'))}</button>
      </div>
      <pre class="cli-pre">${escapeHtml(cliCmd)}</pre>
    </div>
  `;

  bindCopyButtons(rangePullOut);
  document.getElementById('rangeDlPlanBtn').addEventListener('click', () => {
    downloadBlob(planJsonText, 'range-plan.json', 'application/json');
  });
  document.getElementById('rangeDlRestoredBtn').addEventListener('click', () => {
    downloadBlob(restoredBytes, 'restored-' + targetName);
  });
  document.getElementById('copyRangeCli').addEventListener('click', (e) => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(cliCmd);
      e.target.textContent = t('copiedBtn');
      setTimeout(() => { e.target.textContent = t('copyBtn'); }, 1200);
    }
  });
}

runRangeSimBtn.addEventListener('click', async () => {
  try {
    const mod = await loadEngine();
    const profile = rangeProfileSelect.value || 'rk-blake2';
    const mergeGap = Number(rangeMergeGapSelect.value);
    const t0 = performance.now();

    // Synthesize 128 KiB local v1 basis and remote v2 target with 3 scattered edits
    // (two nearby edits 1.5 KiB apart to demonstrate merge_gap_bytes coalescing!).
    const basis = new Uint8Array(131072);
    for (let i = 0; i < basis.length; i++) {
      basis[i] = (i * 59 + 31 + Math.floor(i / 256) * 13 + Math.floor(i / 2048) * 7) % 256;
    }
    const remoteV2 = new Uint8Array(basis.length);
    remoteV2.set(basis);
    const enc = new TextEncoder();
    const edit1 = enc.encode('HTTP-RANGE-PATCH-REGION-ALPHA-070 '.repeat(14));
    const edit2 = enc.encode('HTTP-RANGE-PATCH-NEARBY-BETA-070 '.repeat(14));
    const edit3 = enc.encode('HTTP-RANGE-PATCH-TAIL-GAMMA-070 '.repeat(18));
    remoteV2.set(edit1, 16384);
    remoteV2.set(edit2, 16384 + 2048 + 1024); // close enough to coalesce when merge_gap >= 2048
    remoteV2.set(edit3, 98304);

    const targetSig = await mod.create_signature_with_profile_bytes(remoteV2, 2048, 16, profile);
    const planWrap = JSON.parse(
      await mod.plan_range_fetch_json(targetSig, remoteV2.length, basis, mergeGap, 256),
    );
    if (!planWrap.ok) {
      rangePullOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Range Plan Error:</strong> <code>${escapeHtml(planWrap.error)}</code></div>`;
      return;
    }
    const plan = planWrap.plan;
    const hexSlices = (plan.ranges || []).map((r) =>
      bytesToHex(remoteV2.subarray(Number(r.start), Number(r.start) + Number(r.length))),
    );
    const applyRes = JSON.parse(
      await mod.apply_range_fetch_json(
        targetSig,
        remoteV2.length,
        basis,
        mergeGap,
        256,
        JSON.stringify(hexSlices),
      ),
    );
    if (!applyRes.ok) {
      rangePullOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Range Apply Error:</strong> <code>${escapeHtml(applyRes.error)}</code></div>`;
      return;
    }
    const expectedSha = await mod.sha256_hex_bytes(remoteV2);
    const restoredBytes = hexToBytes(applyRes.restored_hex);
    const elapsedMs = performance.now() - t0;
    const verified =
      applyRes.restored_sha256 === expectedSha && restoredBytes.length === remoteV2.length;

    lastRangePullState = {
      plan,
      applyRes,
      expectedSha,
      verified,
      modeLabel: 'Simulated HTTP 206',
      targetName: 'release-v2.bin',
      mergeGap,
      elapsedMs,
      restoredBytes,
    };
    renderRangePullResult(lastRangePullState);
  } catch (err) {
    rangePullOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Range Pull Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

runRangeLiveBtn.addEventListener('click', async () => {
  const rawTargetUrl = (rangeTargetUrlInput.value || '').trim();
  let parsedTarget;
  try {
    parsedTarget = new URL(rawTargetUrl);
  } catch (_) {
    rangePullOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;">${escapeHtml(t('rangeUrlRequired'))}</div>`;
    return;
  }
  if (parsedTarget.protocol !== 'http:' && parsedTarget.protocol !== 'https:') {
    rangePullOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;">${escapeHtml(t('rangeUrlRequired'))}</div>`;
    return;
  }
  const targetUrl = parsedTarget.href;
  const rawSigUrl = (rangeSigUrlInput.value || '').trim();
  let sigUrl;
  if (rawSigUrl) {
    try {
      const parsedSig = new URL(rawSigUrl);
      if (parsedSig.protocol !== 'http:' && parsedSig.protocol !== 'https:') {
        throw new Error('Unsupported scheme');
      }
      sigUrl = parsedSig.href;
    } catch (_) {
      rangePullOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Invalid .sig URL:</strong> <code>${escapeHtml(rawSigUrl)}</code></div>`;
      return;
    }
  } else {
    const defaultSigUrl = new URL(parsedTarget.href);
    defaultSigUrl.pathname = `${defaultSigUrl.pathname}.sig`;
    sigUrl = defaultSigUrl.href;
  }
  const mergeGap = Number(rangeMergeGapSelect.value);
  try {
    const mod = await loadEngine();
    const t0 = performance.now();
    const basisFile = rangeLiveBasisFileObj || rangeLiveBasisFile.files?.[0] || null;
    const basis = basisFile ? new Uint8Array(await basisFile.arrayBuffer()) : new Uint8Array(0);

    const sigResp = await fetch(sigUrl);
    if (!sigResp.ok) {
      throw new Error(`Failed to fetch .sig (${sigResp.status} ${sigResp.statusText})`);
    }
    const targetSig = new Uint8Array(await sigResp.arrayBuffer());
    const sigInfo = JSON.parse(await mod.inspect_artifact_json(targetSig));
    if (!sigInfo.ok || sigInfo.artifact_kind !== 'signature') {
      throw new Error(`Invalid remote .sig artifact (${sigInfo.error || sigInfo.artifact_kind || 'InvalidSignature'})`);
    }

    let targetLength = -1;
    try {
      const headResp = await fetch(targetUrl, { method: 'HEAD' });
      const cl = headResp.headers.get('content-length');
      if (headResp.ok && cl && /^\d+$/.test(cl.trim())) {
        targetLength = Number(cl.trim());
      }
    } catch (_) {}
    if (targetLength < 0) {
      const probeResp = await fetch(targetUrl, { headers: { Range: 'bytes=0-0' } });
      const cr = probeResp.headers.get('content-range') || '';
      const m = /\/(\d+)$/.exec(cr.trim());
      if (m) {
        targetLength = Number(m[1]);
      } else if (probeResp.status === 200) {
        const full = new Uint8Array(await probeResp.arrayBuffer());
        targetLength = full.length;
      }
    }
    if (!Number.isInteger(targetLength) || targetLength < 0 || targetLength > 67108864) {
      throw new Error(
        targetLength > 67108864
          ? `Remote target exceeds 64 MiB browser limit (${targetLength} B)`
          : 'Could not determine remote target byte length (check CORS Content-Length / Content-Range)',
      );
    }

    const planWrap = JSON.parse(
      await mod.plan_range_fetch_json(targetSig, targetLength, basis, mergeGap, 256),
    );
    if (!planWrap.ok) {
      throw new Error(`plan_range_fetch_json: ${planWrap.error}`);
    }
    const plan = planWrap.plan;
    const hexSlices = [];
    for (const r of plan.ranges || []) {
      const resp = await fetch(targetUrl, { headers: { Range: r.http_range } });
      if (resp.status !== 206 && !(resp.status === 200 && Number(r.start) === 0 && Number(r.length) === targetLength)) {
        throw new Error(`Expected HTTP 206 for ${r.http_range}, got HTTP ${resp.status}`);
      }
      if (resp.status === 206) {
        const cr = resp.headers.get('content-range');
        if (cr && cr.trim()) {
          const endByte = Number(r.start) + Number(r.length) - 1;
          const expectedCr = `bytes ${r.start}-${endByte}/${targetLength}`;
          if (cr.trim() !== expectedCr) {
            throw new Error(`Content-Range mismatch for ${r.http_range}: got "${cr.trim()}", expected "${expectedCr}"`);
          }
        }
      }
      const slice = new Uint8Array(await resp.arrayBuffer());
      if (slice.length !== Number(r.length)) {
        throw new Error(`Range ${r.http_range} returned ${slice.length} B (expected ${r.length} B)`);
      }
      hexSlices.push(bytesToHex(slice));
    }

    const applyRes = JSON.parse(
      await mod.apply_range_fetch_json(
        targetSig,
        targetLength,
        basis,
        mergeGap,
        256,
        JSON.stringify(hexSlices),
      ),
    );
    if (!applyRes.ok) {
      throw new Error(`apply_range_fetch_json: ${applyRes.error}`);
    }
    const restoredBytes = hexToBytes(applyRes.restored_hex);
    if (restoredBytes.length !== targetLength) {
      throw new Error(`Reconstructed target byte length mismatch (${restoredBytes.length} != ${targetLength})`);
    }
    const recomputedSig = await mod.create_signature_with_profile_bytes(
      restoredBytes,
      Number(sigInfo.summary.block_len),
      Number(sigInfo.summary.strong_sum_len),
      sigInfo.summary.profile,
    );
    let sigMatch = targetSig.length > 0 && recomputedSig.length === targetSig.length;
    for (let i = 0; sigMatch && i < targetSig.length; i++) {
      if (recomputedSig[i] !== targetSig[i]) sigMatch = false;
    }
    if (!sigMatch) {
      throw new Error('Reconstructed target signature mismatch against remote .sig');
    }
    const elapsedMs = performance.now() - t0;
    const urlPathName = parsedTarget.pathname.split('/').pop() || 'remote-target.bin';

    lastRangePullState = {
      plan,
      applyRes,
      expectedSha: null,
      verified: sigMatch,
      verifiedBadgeKey: 'rangeSigVerifiedBadge',
      modeLabel: 'Live CORS HTTP 206',
      targetName: urlPathName,
      mergeGap,
      elapsedMs,
      restoredBytes,
    };
    renderRangePullResult(lastRangePullState);
  } catch (err) {
    rangePullOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Live CORS Range Fetch Failed:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

// --- Card E: Delta Chain Squashing (v1 -> v2 -> v3 => v1 -> v3) ---
const runCompose2Btn = document.getElementById('runCompose2Btn');
const runCompose3Btn = document.getElementById('runCompose3Btn');
const composeDrop = document.getElementById('composeDrop');
const composeFilesInput = document.getElementById('composeFiles');
const composeMeta = document.getElementById('composeMeta');
const runComposeCustomBtn = document.getElementById('runComposeCustomBtn');
const composeOut = document.getElementById('composeOut');

function setComposeSelectedFiles(fileList) {
  const list = Array.from(fileList || []).sort((a, b) => a.name.localeCompare(b.name));
  if (!list.length) return;
  composeFileObjs = list;
  const total = list.reduce((acc, f) => acc + f.size, 0);
  composeMeta.textContent = `${list.map((f) => f.name).join(' → ')} (${fmtBytes(total)})`;
  composeMeta.classList.add('selected');
}
composeFilesInput.addEventListener('change', () => setComposeSelectedFiles(composeFilesInput.files));
composeDrop.addEventListener('dragover', (e) => {
  e.preventDefault();
  composeDrop.classList.add('dragover');
});
composeDrop.addEventListener('dragleave', () => composeDrop.classList.remove('dragover'));
composeDrop.addEventListener('drop', (e) => {
  e.preventDefault();
  composeDrop.classList.remove('dragover');
  if (e.dataTransfer?.files?.length) setComposeSelectedFiles(e.dataTransfer.files);
});

function renderComposeResult(state) {
  const { res, hopSizes, hopLabels, gzSize, composedBytes, verified, expectedSha, restoredSha, isDemo, elapsedMs } = state;
  const inTotal = Number(res.input_total_bytes);
  const outBytes = Number(res.composed_bytes);
  const savedPct = inTotal > 0 ? Math.max(0, (1 - outBytes / inTotal) * 100).toFixed(1) : '0.0';
  const directBarPct = inTotal > 0 ? Math.min(100, Math.max(3, (outBytes / inTotal) * 100)).toFixed(1) : '100';
  const gzBarPct = inTotal > 0 ? Math.min(100, Math.max(2, (gzSize / inTotal) * 100)).toFixed(1) : '100';
  const hopChainDesc = hopLabels.map((lbl, i) => `${lbl} (${fmtBytes(hopSizes[i])})`).join(' + ');
  const cliInputs = hopLabels.map((lbl) => `"${String(lbl).replace(/["`$\\]/g, '_')}.delta"`).join(' ');
  const cliCmd = `moonlibsync compose-delta ${cliInputs} -o squashed.delta`;

  const badgeHtml = isDemo
    ? `<span class="verified-pill ${verified ? '' : 'fail'}">${verified ? '✓ ' + escapeHtml(t('composeVerifiedBadge')) : '✕ ' + escapeHtml(t('mismatchBadge'))}</span>`
    : `<span class="verified-pill">✓ ${escapeHtml(t('composeCustomBadge'))}</span>`;

  composeOut.innerHTML = `
    <div class="result-hero" style="margin-bottom:0.85rem;">
      <div class="hero-metric">
        <span class="hero-pct">${savedPct}%</span>
        <span class="hero-desc">${escapeHtml(t('composeSavedLabel'))} · ${fmtBytes(inTotal)} → ${fmtBytes(outBytes)} (${hopSizes.length} hops · ${elapsedMs.toFixed(1)} ms)</span>
      </div>
      ${badgeHtml}
    </div>

    <div class="stats-grid cols-5">
      <div class="stat-card"><div class="stat-label">Chain Hops</div><div class="stat-value">${hopSizes.length}</div><div class="stat-sub">${escapeHtml(hopLabels.join(' → '))}</div></div>
      <div class="stat-card"><div class="stat-label">Sum of Deltas</div><div class="stat-value">${fmtBytes(inTotal)}</div><div class="stat-sub">${inTotal.toLocaleString()} B</div></div>
      <div class="stat-card"><div class="stat-label">Squashed Delta</div><div class="stat-value" style="color:var(--emerald-text)">${fmtBytes(outBytes)}</div><div class="stat-sub">${outBytes.toLocaleString()} B</div></div>
      <div class="stat-card"><div class="stat-label">Instructions</div><div class="stat-value">${Number(res.instruction_count).toLocaleString()}</div><div class="stat-sub">${res.copy_count} COPY · ${res.literal_count} Literal</div></div>
      <div class="stat-card"><div class="stat-label">Output Size</div><div class="stat-value">${fmtBytes(res.output_bytes)}</div><div class="stat-sub">COPY ${fmtBytes(res.copy_bytes)} · Lit ${fmtBytes(res.literal_bytes)}</div></div>
    </div>

    <div class="bars-stack" style="margin-bottom:0.85rem;">
      <div>
        <div class="bar-item-head"><span>${escapeHtml(t('composeSumBar'))} (${escapeHtml(hopChainDesc)})</span><span>${inTotal.toLocaleString()} B (100%)</span></div>
        <div class="bar-track"><div class="bar-fill bar-full" style="width:100%"></div></div>
      </div>
      <div>
        <div class="bar-item-head"><span>${escapeHtml(t('composeDirectBar'))}</span><span>${outBytes.toLocaleString()} B (${directBarPct}%)</span></div>
        <div class="bar-track"><div class="bar-fill bar-delta" style="width:${directBarPct}%"></div></div>
      </div>
      <div>
        <div class="bar-item-head"><span>${escapeHtml(t('composeGzBar'))}</span><span>${gzSize.toLocaleString()} B (${gzBarPct}%)</span></div>
        <div class="bar-track"><div class="bar-fill bar-gz" style="width:${gzBarPct}%"></div></div>
      </div>
    </div>

    <div class="hash-list" style="margin-bottom:0.75rem;">
      <div class="hash-row"><span class="hash-key">Squashed .delta SHA-256</span><span class="hash-val">${escapeHtml(res.composed_sha256)}</span><button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(res.composed_sha256)}" type="button">${escapeHtml(t('copyBtn'))}</button></div>
      ${isDemo ? `<div class="hash-row"><span class="hash-key">patch(v1, d) SHA-256</span><span class="hash-val">${escapeHtml(restoredSha)}</span><span class="badge ${verified ? 'badge-add' : 'badge-delete'}">${verified ? '=== v_final ✓' : 'MISMATCH'}</span></div>` : ''}
      ${isDemo && expectedSha ? `<div class="hash-row"><span class="hash-key">v_final SHA-256</span><span class="hash-val">${escapeHtml(expectedSha)}</span><button class="btn btn-secondary btn-sm copy-hash" data-hash="${escapeHtml(expectedSha)}" type="button">${escapeHtml(t('copyBtn'))}</button></div>` : ''}
    </div>

    <div class="controls-row">
      <button id="composeDlBtn" class="btn btn-teal btn-sm" type="button">${escapeHtml(t('composeDlBtn'))}</button>
    </div>

    <div class="cli-wrap">
      <div class="cli-head">
        <span>${escapeHtml(t('composeCliTitle'))}</span>
        <button id="copyComposeCli" class="btn btn-secondary btn-sm" type="button">${escapeHtml(t('copyBtn'))}</button>
      </div>
      <pre class="cli-pre">${escapeHtml(cliCmd)}</pre>
    </div>
  `;

  bindCopyButtons(composeOut);
  document.getElementById('composeDlBtn').addEventListener('click', () => {
    downloadBlob(composedBytes, 'squashed.delta');
  });
  document.getElementById('copyComposeCli').addEventListener('click', (e) => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(cliCmd);
      e.target.textContent = t('copiedBtn');
      setTimeout(() => { e.target.textContent = t('copyBtn'); }, 1200);
    }
  });
}

async function runComposeDemo(hops) {
  try {
    const mod = await loadEngine();
    const enc = new TextEncoder();
    const t0 = performance.now();

    // Build deterministic 64 KiB version chain where later versions overwrite earlier hot zones
    // so squashing eliminates redundant intermediate literals cleanly.
    const v1 = new Uint8Array(65536);
    for (let i = 0; i < v1.length; i++) {
      v1[i] = (i * 43 + 11 + Math.floor(i / 512) * 19) % 256;
    }
    const v2 = new Uint8Array(v1);
    v2.set(enc.encode('V2-HOT-CONFIG-REGION-DRAFT-ITERATION-'.repeat(45)), 8192);
    v2.set(enc.encode('V2-TELEMETRY-BLOCK-PAYLOAD-'.repeat(30)), 32768);

    const v3 = new Uint8Array(v2);
    v3.set(enc.encode('V3-HOT-CONFIG-REGION-FINAL-REPLACED!-'.repeat(45)), 8192); // overwrites v2 edit!
    v3.set(enc.encode('V3-NEW-FEATURE-FOOTER-SEGMENT-'.repeat(20)), 52000);

    const versions = [v1, v2, v3];
    const hopLabels = ['d12', 'd23'];
    if (hops >= 3) {
      const v4 = new Uint8Array(v3);
      v4.set(enc.encode('V4-HOT-CONFIG-PRODUCTION-SIGNED-070!-'.repeat(45)), 8192); // overwrites v3 edit!
      v4.set(enc.encode('V4-TELEMETRY-FINAL-RELEASE-'.repeat(30)), 32768);
      versions.push(v4);
      hopLabels.push('d34');
    }

    const deltas = [];
    for (let i = 0; i < versions.length - 1; i++) {
      const sig = await mod.create_signature_bytes(versions[i], 1024, 16);
      const delta = await mod.create_delta_bytes(sig, versions[i + 1]);
      deltas.push(delta);
    }

    const res = JSON.parse(
      await mod.compose_deltas_json(JSON.stringify(deltas.map((d) => bytesToHex(d)))),
    );
    if (!res.ok) {
      composeOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Compose Error:</strong> <code>${escapeHtml(res.error)}</code></div>`;
      return;
    }
    const composedBytes = hexToBytes(res.composed_hex);
    const gzBytes = await mod.compress_gzip_bytes(composedBytes, 6);
    const vFinal = versions[versions.length - 1];
    // Prove patch(v1, d_composed) === v_final WITHOUT touching v2/v3!
    const restored = await mod.apply_patch_bytes(v1, composedBytes);
    const [expectedSha, restoredSha] = await Promise.all([
      mod.sha256_hex_bytes(vFinal),
      mod.sha256_hex_bytes(restored),
    ]);
    const verified = restoredSha === expectedSha && restored.length === vFinal.length;
    const elapsedMs = performance.now() - t0;

    lastComposeState = {
      res,
      hopSizes: deltas.map((d) => d.length),
      hopLabels,
      gzSize: gzBytes.length,
      composedBytes,
      verified,
      expectedSha,
      restoredSha,
      isDemo: true,
      elapsedMs,
    };
    renderComposeResult(lastComposeState);
  } catch (err) {
    composeOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Compose Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
}

runCompose2Btn.addEventListener('click', () => runComposeDemo(2));
runCompose3Btn.addEventListener('click', () => runComposeDemo(3));

runComposeCustomBtn.addEventListener('click', async () => {
  if (composeFileObjs.length < 2) {
    composeOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;">${escapeHtml(t('composePickWarn'))}</div>`;
    return;
  }
  try {
    const mod = await loadEngine();
    const t0 = performance.now();
    const bufs = await Promise.all(
      composeFileObjs.map(async (f) => new Uint8Array(await f.arrayBuffer())),
    );
    const res = JSON.parse(
      await mod.compose_deltas_json(JSON.stringify(bufs.map((b) => bytesToHex(b)))),
    );
    if (!res.ok) {
      composeOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Compose Error:</strong> <code>${escapeHtml(res.error)}</code></div>`;
      return;
    }
    const composedBytes = hexToBytes(res.composed_hex);
    const gzBytes = await mod.compress_gzip_bytes(composedBytes, 6);
    const elapsedMs = performance.now() - t0;

    lastComposeState = {
      res,
      hopSizes: bufs.map((b) => b.length),
      hopLabels: composeFileObjs.map((f) => f.name.replace(/\.delta$/i, '')),
      gzSize: gzBytes.length,
      composedBytes,
      verified: true,
      expectedSha: null,
      restoredSha: null,
      isDemo: false,
      elapsedMs,
    };
    renderComposeResult(lastComposeState);
  } catch (err) {
    composeOut.innerHTML = `<div class="card err-card" style="margin-bottom:0;"><strong>Compose Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

// =========================================================================
// Tab 3: Universal Artifact Inspector (.sig, .delta, .gz, .zlib, .mbundle, .menc, MLSENC02, Schema 1/2/3/4)
// =========================================================================
const inspectDrop = document.getElementById('inspectDrop');
const inspectFile = document.getElementById('inspectFile');
const inspectMeta = document.getElementById('inspectMeta');
const inspectSampleDeltaBtn = document.getElementById('inspectSampleDelta');
const inspectSampleSigBtn = document.getElementById('inspectSampleSig');
const inspectSampleSealBtn = document.getElementById('inspectSampleSeal');
const inspectSampleEnvelopeBtn = document.getElementById('inspectSampleEnvelope');
const inspectSampleKeyringBtn = document.getElementById('inspectSampleKeyring');
const inspectSamplePubSigBtn = document.getElementById('inspectSamplePubSig');

function renderInspectResult(state) {
  const { name, rawBytes, parsed, detail, innerDeltaDetail, innerBundleInfo, elapsedMs } = state;
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
  const hashKeys = new Set([
    'public_key',
    'signature',
    'salt_hex',
    'nonce_prefix_hex',
    'header_hex',
    'ephemeral_public_key_hex',
  ]);
  const pushSummaryFields = (obj) => {
    for (const [k, v] of Object.entries(obj || {})) {
      if (Array.isArray(v)) {
        hashRows.push([k, v.length ? v.join(', ') : '(empty)']);
      } else if (k.includes('sha256') || hashKeys.has(k)) {
        hashRows.push([k, String(v)]);
      } else {
        const isBytes =
          k.endsWith('_bytes') ||
          k === 'block_len' ||
          k === 'strong_sum_len' ||
          k === 'chunk_size' ||
          k === 'byte_length' ||
          k === 'payload_length';
        const displayVal = isBytes && /^\d+$/.test(String(v)) ? fmtBytes(v) : String(v);
        const subVal = isBytes && /^\d+$/.test(String(v)) ? `${Number(v).toLocaleString()} B` : '';
        statCards.push({ label: k.replaceAll('_', ' '), value: displayVal, sub: subVal });
      }
    }
  };

  if (parsed.artifact_kind === 'gzip' || parsed.artifact_kind === 'zlib') {
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
    : innerBundleInfo
      ? `<div class="status-bar ok" style="margin-bottom:1rem;"><div class="status-left"><span class="dot"></span><span>${escapeHtml(t('inspectInnerBundle'))} — unchanged=${escapeHtml(innerBundleInfo.summary.unchanged)}, copy_from_basis=${escapeHtml(innerBundleInfo.summary.copy_from_basis || '0')}, update_delta=${escapeHtml(innerBundleInfo.summary.update_delta)}, add_full=${escapeHtml(innerBundleInfo.summary.add_full)}, delete=${escapeHtml(innerBundleInfo.summary.delete)}</span></div></div>`
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
  const parsed = JSON.parse(await mod.inspect_artifact_json(bytes));
  let detail = null;
  let innerDeltaDetail = null;
  let innerBundleInfo = null;
  if (parsed.ok && parsed.artifact_kind === 'delta') {
    detail = JSON.parse(await mod.inspect_delta_detailed_json(bytes, 512));
  } else if (parsed.ok && parsed.artifact_kind === 'gzip') {
    const plain = await mod.decompress_gzip_bytes(bytes, 67108864);
    if (plain.length >= 5 && plain[0] === 0x72 && plain[1] === 0x73 && plain[2] === 0x02 && plain[3] === 0x36) {
      const inner = JSON.parse(await mod.inspect_delta_detailed_json(plain, 512));
      if (inner.ok) innerDeltaDetail = inner;
    } else if (plain.length >= 8 && new TextDecoder().decode(plain.subarray(0, 8)) === 'MLSBDL01') {
      const inner = JSON.parse(await mod.inspect_artifact_json(plain));
      if (inner.ok && inner.artifact_kind === 'bundle-archive') innerBundleInfo = inner;
    }
  }
  const elapsedMs = performance.now() - t0;
  lastInspectState = { name, rawBytes: bytes, parsed, detail, innerDeltaDetail, innerBundleInfo, elapsedMs };
  renderInspectResult(lastInspectState);
}

wireDropzone(inspectDrop, inspectFile, inspectMeta, async (file) => {
  try {
    const bytes = new Uint8Array(await file.arrayBuffer());
    await inspectArtifactBytes(bytes, file.name);
  } catch (err) {
    inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Inspection Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

inspectSampleDeltaBtn.addEventListener('click', async () => {
  try {
    const mod = await loadEngine();
    const { oldBuf, newBuf } = makeBuiltInBinaryPair();
    const sig = await mod.create_signature_bytes(oldBuf, 2048, 16);
    const delta = await mod.create_delta_bytes(sig, newBuf);
    inspectMeta.textContent = `sample-128k.delta (${fmtBytes(delta.length)})`;
    inspectMeta.classList.add('selected');
    await inspectArtifactBytes(delta, 'sample-128k.delta');
  } catch (err) {
    inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Inspection Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

inspectSampleSigBtn.addEventListener('click', async () => {
  try {
    const mod = await loadEngine();
    const { oldBuf } = makeBuiltInBinaryPair();
    const sig = await mod.create_signature_with_profile_bytes(oldBuf, 0, 16, 'rollsum-blake2');
    inspectMeta.textContent = `sample-rollsum-128k.sig (${fmtBytes(sig.length)})`;
    inspectMeta.classList.add('selected');
    await inspectArtifactBytes(sig, 'sample-rollsum-128k.sig');
  } catch (err) {
    inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Inspection Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

inspectSampleSealBtn.addEventListener('click', async () => {
  try {
    const mod = await loadEngine();
    const enc = new TextEncoder();
    const plain = enc.encode('MoonLibSync 0.7.1 sample MLSENC01 authenticated stream container');
    const salt = new Uint8Array(16);
    crypto.getRandomValues(salt);
    const nonce = new Uint8Array(12);
    crypto.getRandomValues(nonce.subarray(0, 8));
    const sealed = JSON.parse(
      await mod.seal_bytes_json(plain, enc.encode('demo-passphrase'), true, salt, nonce, 65536, 1024, 1),
    );
    if (!sealed.ok) {
      inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Seal Error:</strong> <code>${escapeHtml(sealed.error || 'SealFailed')}</code></div>`;
      return;
    }
    const mencBytes = hexToBytes(sealed.cipher_hex);
    inspectMeta.textContent = `sample-release.menc (${fmtBytes(mencBytes.length)})`;
    inspectMeta.classList.add('selected');
    await inspectArtifactBytes(mencBytes, 'sample-release.menc');
  } catch (err) {
    inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Inspection Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

inspectSampleEnvelopeBtn.addEventListener('click', async () => {
  try {
    const mod = await loadEngine();
    const enc = new TextEncoder();
    const randHex = (n) => {
      const b = new Uint8Array(n);
      crypto.getRandomValues(b);
      return bytesToHex(b);
    };
    const [alice, bob] = await Promise.all([
      mod.x25519_keypair_from_secret_json(randHex(32)).then(JSON.parse),
      mod.x25519_keypair_from_secret_json(randHex(32)).then(JSON.parse),
    ]);
    const sealed = JSON.parse(
      await mod.seal_envelope_json(
        enc.encode('MoonLibSync 0.7.1 sample MLSENC02 multi-recipient envelope'),
        JSON.stringify([alice.public_key_hex, bob.public_key_hex]),
        randHex(32),
        randHex(32),
        randHex(4),
        65536,
      ),
    );
    if (!sealed.ok) {
      inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Envelope Error:</strong> <code>${escapeHtml(sealed.error || 'SealFailed')}</code></div>`;
      return;
    }
    const envBytes = hexToBytes(sealed.ciphertext_hex);
    inspectMeta.textContent = `sample-envelope.menv (${fmtBytes(envBytes.length)})`;
    inspectMeta.classList.add('selected');
    await inspectArtifactBytes(envBytes, 'sample-envelope.menv');
  } catch (err) {
    inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Inspection Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

inspectSampleKeyringBtn.addEventListener('click', async () => {
  try {
    const mod = await loadEngine();
    const makeKp = async () => {
      const s = new Uint8Array(32);
      crypto.getRandomValues(s);
      return JSON.parse(await mod.ed25519_keypair_from_seed_json(s));
    };
    const [k1, k2, k3] = await Promise.all([makeKp(), makeKp(), makeKp()]);
    const kr = JSON.parse(
      await mod.create_trust_keyring_json(
        JSON.stringify([k1.public_key_hex, k2.public_key_hex, k3.public_key_hex]),
        JSON.stringify([]),
        2,
      ),
    );
    if (!kr.ok) {
      inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Keyring Error:</strong> <code>${escapeHtml(kr.error || 'KeyringFailed')}</code></div>`;
      return;
    }
    const krBytes = new TextEncoder().encode(kr.keyring_json);
    inspectMeta.textContent = `release-keyring.json (${fmtBytes(krBytes.length)})`;
    inspectMeta.classList.add('selected');
    await inspectArtifactBytes(krBytes, 'release-keyring.json');
  } catch (err) {
    inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Inspection Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

inspectSamplePubSigBtn.addEventListener('click', async () => {
  try {
    const mod = await loadEngine();
    const seed = new Uint8Array(32);
    crypto.getRandomValues(seed);
    const payload = new TextEncoder().encode('MoonLibSync 0.7.1 sample release payload');
    const signed = JSON.parse(await mod.ed25519_sign_bytes_json(seed, payload));
    if (!signed.ok) {
      inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Sign Error:</strong> <code>${escapeHtml(signed.error || 'SignFailed')}</code></div>`;
      return;
    }
    const sigBytes = new TextEncoder().encode(signed.signature_json);
    inspectMeta.textContent = `release.msig.json (${fmtBytes(sigBytes.length)})`;
    inspectMeta.classList.add('selected');
    await inspectArtifactBytes(sigBytes, 'release.msig.json');
  } catch (err) {
    inspectResultsEl.innerHTML = `<div class="card err-card"><strong>Inspection Error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

// =========================================================================
// Tab 4: Directory Sync Planner, Integrity Audit & .mbundle.gz Pack/Unpack
// =========================================================================
function setDirMode(mode) {
  dirMode = mode;
  dirModePlanBtn.classList.toggle('active', mode === 'plan');
  dirModeVerifyBtn.classList.toggle('active', mode === 'verify');
  dirModeBundleBtn.classList.toggle('active', mode === 'bundle');
  dirBundlePanel.hidden = mode !== 'bundle';
}
dirModePlanBtn.addEventListener('click', () => setDirMode('plan'));
dirModeVerifyBtn.addEventListener('click', () => setDirMode('verify'));
dirModeBundleBtn.addEventListener('click', () => setDirMode('bundle'));

fillExcludePresetBtn.addEventListener('click', () => {
  dirExcludeInput.value = '.git, node_modules, *.tmp';
});

wireDropzone(bundleUnpackDrop, bundleUnpackFile, bundleUnpackMeta, (f) => {
  droppedBundleArchiveFile = f;
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
  if (kind === 'add-full' || kind === 'copy-from-basis') return 'badge badge-add';
  if (kind === 'update-candidate' || kind === 'update-delta' || kind === 'update-delta-from' || kind === 'update-full' || kind === 'modified') {
    return 'badge badge-update';
  }
  if (kind === 'extra') return 'badge badge-info';
  return 'badge badge-delete';
}

function renderDirPlan(state) {
  const { planText, basisSnapText, targetSnapText, patterns, detectMoves, elapsedMs } = state;
  const plan = JSON.parse(planText);
  if (plan.ok === false) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Directory plan error:</strong> <code>${escapeHtml(plan.error)}</code></div>`;
    return;
  }
  const s = plan.summary;
  const cfbCount = s.copy_from_basis || '0';
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
      const actionExtra =
        a.kind === 'copy-from-basis' && a.source_path
          ? ` <span class="hint">← <code>${escapeHtml(a.source_path)}</code> (0 B)</span>`
          : '';
      return `<tr>
        <td><code>${escapeHtml(a.path)}</code></td>
        <td><span class="${badgeClassForKind(a.kind)}">${escapeHtml(a.kind)}</span>${actionExtra}</td>
        <td>${bLen}</td>
        <td>${tLen}</td>
      </tr>`;
    })
    .join('');

  const filterKinds = [
    ['all', `${t('allFilter')} (${plan.actions.length})`],
    ['unchanged', `unchanged (${s.unchanged})`],
    ['copy-from-basis', `copy-from-basis (${cfbCount})`],
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
  const moveFlag = detectMoves ? ' --detect-moves' : '';
  const dirCli = [
    `moonlibsync dir-snapshot ./basis basis.snap.json${exFlags}`,
    `moonlibsync dir-snapshot ./target target.snap.json${exFlags}`,
    `moonlibsync dir-plan basis.snap.json target.snap.json${moveFlag}`,
    `moonlibsync dir-signatures ./basis basis.snap.json ./basis-sigs --streaming`,
    `moonlibsync dir-pack basis.snap.json ./basis-sigs ./target ./bundle.mbundle.gz --archive --gzip${moveFlag}${exFlags}`,
    `moonlibsync dir-apply ./basis ./bundle.mbundle.gz ./restored --archive --gzip --streaming`,
  ].join('\n');

  dirResultsEl.innerHTML = `
    <div class="stats-grid cols-5">
      <div class="stat-card"><div class="stat-label">Unchanged</div><div class="stat-value">${escapeHtml(s.unchanged)}</div></div>
      <div class="stat-card"><div class="stat-label">Copy From Basis (0 B)</div><div class="stat-value" style="color:var(--emerald-text)">${escapeHtml(cfbCount)}</div></div>
      <div class="stat-card"><div class="stat-label">Add Full</div><div class="stat-value" style="color:var(--emerald-text)">${escapeHtml(s.add)}</div></div>
      <div class="stat-card"><div class="stat-label">Update Candidate</div><div class="stat-value" style="color:var(--amber-text)">${escapeHtml(s.update)}</div></div>
      <div class="stat-card"><div class="stat-label">Delete</div><div class="stat-value" style="color:var(--rose-text)">${escapeHtml(s.delete)}</div></div>
      <div class="stat-card"><div class="stat-label">Transfer Upper Bound</div><div class="stat-value">${fmtBytes(s.transfer_upper_bound_bytes)}</div><div class="stat-sub">${elapsedMs.toFixed(1)} ms</div></div>
    </div>

    <div class="card">
      <div class="card-header">
        <h3 class="card-title">Schema 3 Sync Plan${detectMoves ? ' (--detect-moves)' : ''}</h3>
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
    `moonlibsync dir-verify ./actual expected.snap.json --json${exFlags} > verify-report.json`,
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

function renderBundlePackResult(state) {
  const { packRes, archiveBytes, elapsedMs } = state;
  if (!packRes.ok) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Bundle pack error:</strong> <code>${escapeHtml(packRes.error)}</code></div>`;
    return;
  }
  const s = packRes.summary;
  const ratio = packRes.archive_bytes > 0 ? (packRes.raw_bytes / packRes.archive_bytes).toFixed(2) : '1.00';
  const ext = packRes.gzip ? '.mbundle.gz' : '.mbundle';
  const entries = packRes.manifest?.entries || [];

  const rows = entries
    .map((e) => {
      let detail = '—';
      if (e.kind === 'copy-from-basis') {
        detail = `← <code>${escapeHtml(e.source_path)}</code> (0 B payload)`;
      } else if (e.kind === 'update-delta-from') {
        detail = `← <code>${escapeHtml(e.source_path)}</code> · delta ${fmtBytes(e.delta.byte_length)}`;
      } else if (e.kind === 'update-delta') {
        detail = `delta ${fmtBytes(e.delta.byte_length)} → ${fmtBytes(e.result.byte_length)}`;
      } else if (e.kind === 'add-full' || e.kind === 'update-full') {
        detail = `full ${fmtBytes(e.target.byte_length)}`;
      } else if (e.kind === 'unchanged') {
        detail = `${fmtBytes(e.basis.byte_length)} (0 B payload)`;
      } else if (e.kind === 'delete') {
        detail = `remove ${fmtBytes(e.basis.byte_length)}`;
      }
      return `<tr>
        <td><code>${escapeHtml(e.path)}</code></td>
        <td><span class="${badgeClassForKind(e.kind)}">${escapeHtml(e.kind)}</span></td>
        <td>${detail}</td>
      </tr>`;
    })
    .join('');

  dirResultsEl.innerHTML = `
    <div class="result-hero">
      <div class="hero-metric">
        <span class="hero-pct" style="font-size:1.5rem;">${fmtBytes(packRes.archive_bytes)}</span>
        <span class="hero-desc">MLSBDL01 raw ${fmtBytes(packRes.raw_bytes)} → ${ext} (${ratio}× · ${elapsedMs.toFixed(1)} ms)</span>
      </div>
      <div class="controls-row">
        ${packRes.gzip ? '<span class="verified-pill info">RFC 1952 Gzip</span>' : '<span class="verified-pill info">Raw MLSBDL01</span>'}
        <span class="verified-pill">✓ Bundle Packed</span>
      </div>
    </div>

    <div class="stats-grid cols-5">
      <div class="stat-card"><div class="stat-label">Copy From Basis</div><div class="stat-value" style="color:var(--emerald-text)">${escapeHtml(s.copy_from_basis)}</div><div class="stat-sub">0 B wire</div></div>
      <div class="stat-card"><div class="stat-label">Update Delta</div><div class="stat-value" style="color:var(--amber-text)">${escapeHtml(s.update_delta)}</div></div>
      <div class="stat-card"><div class="stat-label">Add / Update Full</div><div class="stat-value">${Number(s.add_full) + Number(s.update_full)}</div></div>
      <div class="stat-card"><div class="stat-label">Unchanged / Delete</div><div class="stat-value">${escapeHtml(s.unchanged)} / ${escapeHtml(s.delete)}</div></div>
      <div class="stat-card"><div class="stat-label">Total Payloads</div><div class="stat-value">${fmtBytes(s.total_payload_bytes)}</div><div class="stat-sub">${Number(s.total_payload_bytes).toLocaleString()} B</div></div>
    </div>

    <div class="card">
      <div class="card-header">
        <h3 class="card-title">MLSBDL01 Bundle Archive (${ext})</h3>
        <div class="controls-row">
          <button id="bundleDlArchiveBtn" class="btn btn-teal btn-sm" type="button">${escapeHtml(I18N[lang].bundleDlArchive(packRes.gzip))}</button>
          <button id="bundleRoundtripUnpackBtn" class="btn btn-primary btn-sm" type="button">${escapeHtml(t('bundleRoundtripBtn'))}</button>
        </div>
      </div>

      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>${escapeHtml(t('pathCol'))}</th>
              <th>${escapeHtml(t('actionCol'))}</th>
              <th>Payload / Source</th>
            </tr>
          </thead>
          <tbody>${rows || `<tr><td colspan="3" style="text-align:center;color:var(--text-subtle);">${escapeHtml(t('emptyDir'))}</td></tr>`}</tbody>
        </table>
      </div>
    </div>
  `;

  document.getElementById('bundleDlArchiveBtn').addEventListener('click', () => {
    downloadBlob(
      archiveBytes,
      'moonlibsync-bundle' + ext,
      packRes.gzip ? 'application/gzip' : 'application/octet-stream',
    );
  });

  document.getElementById('bundleRoundtripUnpackBtn').addEventListener('click', async () => {
    if (!lastPackedBundle) return;
    try {
      await runBundleUnpackBytes(lastPackedBundle.basisFilesJson, lastPackedBundle.archiveBytes, 'roundtrip' + ext);
    } catch (err) {
      dirResultsEl.innerHTML = `<div class="card err-card"><strong>Bundle unpack error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
    }
  });
}

function renderBundleUnpackResult(state) {
  const { unpackRes, archiveName, elapsedMs } = state;
  if (!unpackRes.ok) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Bundle unpack / verification failed:</strong> <code>${escapeHtml(unpackRes.error)}</code></div>`;
    return;
  }
  const files = unpackRes.files || [];
  const rows = files
    .map(
      (f, idx) => `<tr>
        <td><code>${escapeHtml(f.path)}</code></td>
        <td><code>${fmtBytes(f.byte_length)}</code> (${Number(f.byte_length).toLocaleString()} B)</td>
        <td><code style="font-size:0.74rem;">${escapeHtml(f.sha256.slice(0, 20))}...</code></td>
        <td><button class="btn btn-secondary btn-sm bundle-dl-file" data-idx="${idx}" type="button">${escapeHtml(t('bundleDownloadFile'))}</button></td>
      </tr>`,
    )
    .join('');

  dirResultsEl.innerHTML = `
    <div class="result-hero">
      <div class="hero-metric">
        <span class="hero-pct" style="font-size:1.45rem;">${unpackRes.file_count} Files Restored</span>
        <span class="hero-desc">${escapeHtml(archiveName)} · ${elapsedMs.toFixed(1)} ms</span>
      </div>
      <div class="controls-row">
        ${unpackRes.was_gzip ? '<span class="verified-pill info">Gzip Auto-Decompressed</span>' : ''}
        <span class="verified-pill">${escapeHtml(I18N[lang].bundleUnpackOkBadge(unpackRes.file_count))}</span>
      </div>
    </div>

    <div class="card">
      <div class="card-header">
        <h3 class="card-title">Verified Restored Files (SHA-256 Checked)</h3>
      </div>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>${escapeHtml(t('pathCol'))}</th>
              <th>Size</th>
              <th>Verified SHA-256</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>${rows || `<tr><td colspan="4" style="text-align:center;color:var(--text-subtle);">${escapeHtml(t('emptyDir'))}</td></tr>`}</tbody>
        </table>
      </div>
    </div>
  `;

  for (const btn of dirResultsEl.querySelectorAll('.bundle-dl-file')) {
    btn.addEventListener('click', () => {
      const f = files[Number(btn.dataset.idx)];
      if (!f) return;
      const baseName = f.path.split('/').pop() || 'file.bin';
      downloadBlob(hexToBytes(f.content_hex), baseName);
    });
  }
}

async function buildSnapshotWithExcludes(mod, entries, patterns) {
  if (patterns.length > 0) {
    return mod.filter_dir_entries_json(JSON.stringify(entries), JSON.stringify(patterns));
  }
  return mod.create_dir_snapshot_json(JSON.stringify(entries));
}

async function buildSnapshotFromFiles(mod, fileList, patterns) {
  const entries = [];
  for (const { rel, file } of normalizeRelativeFolderFiles(fileList)) {
    const bytes = new Uint8Array(await file.arrayBuffer());
    const sha256 = await mod.sha256_hex_bytes(bytes);
    entries.push({ path: rel, byte_length: String(bytes.length), sha256 });
  }
  return buildSnapshotWithExcludes(mod, entries, patterns);
}

function makeSampleRawFiles() {
  const enc = new TextEncoder();
  const make = (path, text) => ({ path, bytes: enc.encode(text) });
  const movedManual =
    '# MoonLibSync Operations Manual\n' +
    'Zero-byte content-digest move detection avoids re-uploading renamed files.\n'.repeat(30);
  const changelogBase =
    '# Changelog\n' +
    Array.from({ length: 60 }, (_, i) => `- v0.5.${i}: deterministic streaming check #${i}\n`).join('');
  const basisFiles = [
    make('.git/HEAD', 'ref: refs/heads/main\n'),
    make('README.md', '# MoonLibSync 0.7.1\n'),
    make('assets/logo.svg', '<svg viewBox="0 0 28 28">v1</svg>'),
    make('assets/manual-v1.txt', movedManual),
    make('cache/session.tmp', 'temporary scratch data'),
    make('src/engine.mbt', 'pub fn delta() { ... }\n'.repeat(220)),
    make('legacy/changelog.md', changelogBase),
    make('legacy/deprecated.txt', 'old legacy file'),
  ];
  const targetFiles = [
    make('.git/HEAD', 'ref: refs/heads/release-0.7\n'),
    make('README.md', '# MoonLibSync 0.7.1\n'),
    make('assets/logo.svg', '<svg viewBox="0 0 28 28">v2-updated-vector</svg>'),
    make('cache/session.tmp', 'temporary scratch data v2'),
    make('src/engine.mbt', 'pub fn delta() { ... }\n'.repeat(220) + '// v0.7.1 range-sync + compose + crypto\n'),
    make('docs/manual.txt', movedManual),
    make(
      'docs/changelog.md',
      changelogBase +
        '- v0.7.0: HTTP Range pull, delta composition, Zlib, X25519 MLSENC02, and M-of-N quorum!\n' +
        '- v0.7.1: fetch-sync mandatory .sig checksum verification and bounded safe 3xx redirects.\n',
    ),
    make('compress/gzip.mbt', 'pub fn compress_gzip() {}\n'.repeat(30)),
  ];
  return { basisFiles, targetFiles };
}

async function makeSampleDirEntries(mod) {
  const { basisFiles, targetFiles } = makeSampleRawFiles();
  const toEntries = async (list) => {
    const out = [];
    for (const f of list) {
      const sha256 = await mod.sha256_hex_bytes(f.bytes);
      out.push({ path: f.path, byte_length: String(f.bytes.length), sha256 });
    }
    return out;
  };
  const [basisEntries, targetEntries] = await Promise.all([
    toEntries(basisFiles),
    toEntries(targetFiles),
  ]);
  return { basisEntries, targetEntries };
}

async function filterRawFilesByExcludes(mod, rawFiles, patterns) {
  if (!patterns.length) return rawFiles;
  const entries = [];
  for (const f of rawFiles) {
    const sha256 = await mod.sha256_hex_bytes(f.bytes);
    entries.push({ path: f.path, byte_length: String(f.bytes.length), sha256 });
  }
  const snap = JSON.parse(
    await mod.filter_dir_entries_json(JSON.stringify(entries), JSON.stringify(patterns)),
  );
  if (snap.ok === false) {
    throw new Error(snap.error || 'Invalid exclude pattern');
  }
  const kept = new Set((snap.entries || []).map((e) => e.path));
  return rawFiles.filter((f) => kept.has(f.path));
}

function serializeHexFiles(rawFiles) {
  return JSON.stringify(rawFiles.map((f) => ({ path: f.path, content_hex: bytesToHex(f.bytes) })));
}

async function readFolderToRawFiles(fileList) {
  const out = [];
  for (const { rel, file } of normalizeRelativeFolderFiles(fileList)) {
    const bytes = new Uint8Array(await file.arrayBuffer());
    out.push({ path: rel, bytes });
  }
  return out;
}

async function executeDirComparison(mod, basisSnap, targetSnap, mode, patterns, detectMoves, t0) {
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
    const verifyText = await mod.verify_dir_snapshots_json(basisSnap, targetSnap);
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
    const planText = await mod.plan_dir_snapshots_with_options_json(basisSnap, targetSnap, detectMoves);
    lastDirState = {
      mode: 'plan',
      planText,
      basisSnapText: basisSnap,
      targetSnapText: targetSnap,
      patterns,
      detectMoves,
      elapsedMs: performance.now() - t0,
    };
    renderDirPlan(lastDirState);
  }
}

async function runBundlePackRaw(basisRaw, targetRaw) {
  const patterns = parseExcludePatterns();
  const detectMoves = !!dirDetectMovesCheckbox.checked;
  const gzipCompress = !!bundleGzipToggle.checked;
  const t0 = performance.now();
  try {
    const mod = await loadEngine();
    const [basisKept, targetKept] = await Promise.all([
      filterRawFilesByExcludes(mod, basisRaw, patterns),
      filterRawFilesByExcludes(mod, targetRaw, patterns),
    ]);
    const basisFilesJson = serializeHexFiles(basisKept);
    const targetFilesJson = serializeHexFiles(targetKept);
    const packRes = JSON.parse(
      await mod.pack_dir_bundle_archive_json(basisFilesJson, targetFilesJson, detectMoves, gzipCompress),
    );
    const elapsedMs = performance.now() - t0;
    const archiveBytes = packRes.ok ? hexToBytes(packRes.archive_hex) : new Uint8Array(0);
    if (packRes.ok) {
      lastPackedBundle = { archiveBytes, isGz: packRes.gzip, basisFilesJson, packRes };
    }
    lastDirState = { mode: 'bundle-pack', packRes, archiveBytes, elapsedMs };
    renderBundlePackResult(lastDirState);
  } catch (err) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Bundle pack error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
}

async function runBundleUnpackBytes(basisFilesJson, archiveBytes, archiveName) {
  try {
    const mod = await loadEngine();
    const t0 = performance.now();
    const unpackRes = JSON.parse(await mod.unpack_dir_bundle_archive_json(basisFilesJson, archiveBytes));
    const elapsedMs = performance.now() - t0;
    lastDirState = { mode: 'bundle-unpack', unpackRes, archiveName, elapsedMs };
    renderBundleUnpackResult(lastDirState);
  } catch (err) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Bundle unpack error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
}

runDirSampleBtn.addEventListener('click', async () => {
  try {
    if (dirMode === 'bundle') {
      const { basisFiles, targetFiles } = makeSampleRawFiles();
      await runBundlePackRaw(basisFiles, targetFiles);
      return;
    }
    const mod = await loadEngine();
    const patterns = parseExcludePatterns();
    const detectMoves = !!dirDetectMovesCheckbox.checked;
    const t0 = performance.now();
    const { basisEntries, targetEntries } = await makeSampleDirEntries(mod);
    const [basisSnap, targetSnap] = await Promise.all([
      buildSnapshotWithExcludes(mod, basisEntries, patterns),
      buildSnapshotWithExcludes(mod, targetEntries, patterns),
    ]);
    await executeDirComparison(mod, basisSnap, targetSnap, dirMode, patterns, detectMoves, t0);
  } catch (err) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Directory operation error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

runDirVerifyCleanSampleBtn.addEventListener('click', async () => {
  try {
    const mod = await loadEngine();
    setDirMode('verify');
    const patterns = parseExcludePatterns();
    const t0 = performance.now();
    const { basisEntries } = await makeSampleDirEntries(mod);
    const snap = await buildSnapshotWithExcludes(mod, basisEntries, patterns);
    await executeDirComparison(mod, snap, snap, 'verify', patterns, false, t0);
  } catch (err) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Directory verify error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

async function runDirFoldersWithMode(mode) {
  setDirMode(mode);
  if (!basisDirInput.files?.length && !targetDirInput.files?.length) {
    dirResultsEl.innerHTML = `<div class="card err-card">${escapeHtml(t('pickDirWarn'))}</div>`;
    return;
  }
  try {
    const mod = await loadEngine();
    const patterns = parseExcludePatterns();
    const detectMoves = !!dirDetectMovesCheckbox.checked;
    const t0 = performance.now();
    const [basisSnap, targetSnap] = await Promise.all([
      buildSnapshotFromFiles(mod, basisDirInput.files, patterns),
      buildSnapshotFromFiles(mod, targetDirInput.files, patterns),
    ]);
    await executeDirComparison(mod, basisSnap, targetSnap, mode, patterns, detectMoves, t0);
  } catch (err) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Directory operation error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
}

runDirDiffBtn.addEventListener('click', () => runDirFoldersWithMode('plan'));
runDirVerifyBtn.addEventListener('click', () => runDirFoldersWithMode('verify'));

runBundleSamplePackBtn.addEventListener('click', async () => {
  setDirMode('bundle');
  const { basisFiles, targetFiles } = makeSampleRawFiles();
  await runBundlePackRaw(basisFiles, targetFiles);
});

runBundleFolderPackBtn.addEventListener('click', async () => {
  setDirMode('bundle');
  if (!basisDirInput.files?.length && !targetDirInput.files?.length) {
    dirResultsEl.innerHTML = `<div class="card err-card">${escapeHtml(t('pickDirWarn'))}</div>`;
    return;
  }
  try {
    const [basisRaw, targetRaw] = await Promise.all([
      readFolderToRawFiles(basisDirInput.files),
      readFolderToRawFiles(targetDirInput.files),
    ]);
    await runBundlePackRaw(basisRaw, targetRaw);
  } catch (err) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Bundle pack error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

runBundleUnpackBtn.addEventListener('click', async () => {
  const archiveFile = droppedBundleArchiveFile || bundleUnpackFile.files?.[0];
  if (!archiveFile) {
    dirResultsEl.innerHTML = `<div class="card err-card">${escapeHtml(t('bundlePickArchiveWarn'))}</div>`;
    return;
  }
  try {
    const mod = await loadEngine();
    const patterns = parseExcludePatterns();
    const archiveBytes = new Uint8Array(await archiveFile.arrayBuffer());
    let basisFilesJson;
    if (basisDirInput.files?.length) {
      const basisRaw = await filterRawFilesByExcludes(mod, await readFolderToRawFiles(basisDirInput.files), patterns);
      basisFilesJson = serializeHexFiles(basisRaw);
    } else {
      const { basisFiles } = makeSampleRawFiles();
      const basisKept = await filterRawFilesByExcludes(mod, basisFiles, patterns);
      basisFilesJson = serializeHexFiles(basisKept);
    }
    await runBundleUnpackBytes(basisFilesJson, archiveBytes, archiveFile.name);
  } catch (err) {
    dirResultsEl.innerHTML = `<div class="card err-card"><strong>Bundle unpack error:</strong> <code>${escapeHtml(errMessage(err))}</code></div>`;
  }
});

// =========================================================================
// Tab 5: Security & Crypto Lab (Gzip/Zlib Guard + Ed25519 + MLSENC01/02 + Quorum)
// =========================================================================
const labFmtGzipBtn = document.getElementById('labFmtGzip');
const labFmtZlibBtn = document.getElementById('labFmtZlib');
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

function setLabFormat(fmt) {
  labFormat = fmt;
  labFmtGzipBtn.classList.toggle('active', fmt === 'gzip');
  labFmtZlibBtn.classList.toggle('active', fmt === 'zlib');
}
labFmtGzipBtn.addEventListener('click', () => setLabFormat('gzip'));
labFmtZlibBtn.addEventListener('click', () => setLabFormat('zlib'));

async function labCompress(mod, raw, level) {
  if (labFormat === 'zlib') {
    return mod.compress_zlib_bytes(raw, 67108864, 67108864, level);
  }
  return mod.compress_gzip_bytes(raw, level);
}

async function labDecompressCheck(mod, compressed, cap) {
  if (labFormat === 'zlib') {
    const res = JSON.parse(await mod.decompress_zlib_check_json(compressed, 67108864, cap));
    return res.ok
      ? { ok: true, byte_length: String(res.output_bytes), sha256: res.output_sha256 }
      : res;
  }
  return JSON.parse(await mod.decompress_gzip_check_json(compressed, cap));
}

async function runBombDrill() {
  try {
    const mod = await loadEngine();
    const raw = new Uint8Array(262144);
    const label = labFormat === 'zlib' ? 'zlib' : 'gzip';
    const comp = await labCompress(mod, raw, 6);
    const res = await labDecompressCheck(mod, comp, 4096);
    const ratio = (raw.length / comp.length).toFixed(0);
    labBombOut.className = 'lab-out ' + (!res.ok && res.error === 'LimitExceeded' ? 'blocked' : 'err');
    labBombOut.textContent = !res.ok
      ? `✓ BLOCKED (${res.error}) [${label}] — 256 KiB → ${comp.length} B bomb (${ratio}×) stopped at 4,096 B cap`
      : `Unexpected pass: ${JSON.stringify(res)}`;
  } catch (err) {
    labBombOut.className = 'lab-out err';
    labBombOut.textContent = `✕ Error: ${errMessage(err)}`;
  }
}

async function runTrailingDrill() {
  try {
    const mod = await loadEngine();
    const label = labFormat === 'zlib' ? 'zlib' : 'gzip';
    const sample = new TextEncoder().encode('moonlibsync-strict-framing-check');
    const comp = await labCompress(mod, sample, 6);
    const forged = new Uint8Array(comp.length + 1);
    forged.set(comp, 0);
    forged[comp.length] = 0x42;
    const res = await labDecompressCheck(mod, forged, 65536);
    labTrailOut.className = 'lab-out ' + (!res.ok && res.error === 'TrailingData' ? 'blocked' : 'err');
    labTrailOut.textContent = !res.ok
      ? `✓ BLOCKED (${res.error}) [${label}] — ${comp.length} B valid frame + 1 rogue byte rejected`
      : `Unexpected pass: ${JSON.stringify(res)}`;
  } catch (err) {
    labTrailOut.className = 'lab-out err';
    labTrailOut.textContent = `✕ Error: ${errMessage(err)}`;
  }
}

async function runTruncatedDrill() {
  try {
    const mod = await loadEngine();
    const label = labFormat === 'zlib' ? 'zlib' : 'gzip';
    const sample = new TextEncoder().encode('moonlibsync-strict-trailer-check');
    const comp = await labCompress(mod, sample, 6);
    const trunc = comp.subarray(0, comp.length - 1);
    const res = await labDecompressCheck(mod, trunc, 65536);
    labTruncOut.className = 'lab-out ' + (!res.ok && res.error === 'TruncatedInput' ? 'blocked' : 'err');
    labTruncOut.textContent = !res.ok
      ? `✓ BLOCKED (${res.error}) [${label}] — ${trunc.length}/${comp.length} B truncated trailer rejected`
      : `Unexpected pass: ${JSON.stringify(res)}`;
  } catch (err) {
    labTruncOut.className = 'lab-out err';
    labTruncOut.textContent = `✕ Error: ${errMessage(err)}`;
  }
}

async function runCustomGzipDrill() {
  try {
    const mod = await loadEngine();
    const label = labFormat === 'zlib' ? 'zlib' : 'gzip';
    const raw = new TextEncoder().encode(labInputEl.value || '');
    const level = Number(labLevelEl.value);
    const cap = Math.max(0, Number(labMaxOutEl.value) || 0);
    const comp = await labCompress(mod, raw, level);
    const check = await labDecompressCheck(mod, comp, cap);
    if (check.ok) {
      const pct = raw.length > 0 ? ((comp.length / raw.length) * 100).toFixed(1) : '100.0';
      labCustomOut.className = 'lab-out blocked';
      labCustomOut.textContent =
        `✓ OK [${label}] — raw=${raw.length} B → ${label}=${comp.length} B (${pct}%, level=${level}) · decompressed=${check.byte_length} B · sha256=${check.sha256.slice(0, 16)}... · hex=${toHexPreview(comp, 14)}`;
    } else {
      labCustomOut.className = 'lab-out blocked';
      labCustomOut.textContent =
        `✓ GUARD TRIGGERED (${check.error}) [${label}] — raw=${raw.length} B, ${label}=${comp.length} B, max_output cap=${cap} B`;
    }
  } catch (err) {
    labCustomOut.className = 'lab-out err';
    labCustomOut.textContent = `✕ Error: ${errMessage(err)}`;
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

// --- Card 2: Ed25519 Publisher Sign & Verify Lab ---
const edGenKeyBtn = document.getElementById('edGenKeyBtn');
const edKeyIdVal = document.getElementById('edKeyIdVal');
const edPubKeyVal = document.getElementById('edPubKeyVal');
const edCopyKeyIdBtn = document.getElementById('edCopyKeyIdBtn');
const edCopyPubKeyBtn = document.getElementById('edCopyPubKeyBtn');
const edPayloadInput = document.getElementById('edPayloadInput');
const edSignBtn = document.getElementById('edSignBtn');
const edDlSigBtn = document.getElementById('edDlSigBtn');
const edSigPreview = document.getElementById('edSigPreview');
const edVerifyValidBtn = document.getElementById('edVerifyValidBtn');
const edVerifyTamperBtn = document.getElementById('edVerifyTamperBtn');
const edVerifyUntrustedBtn = document.getElementById('edVerifyUntrustedBtn');
const edVerifyOut = document.getElementById('edVerifyOut');

async function ensureEdKeypair(forceNew = false) {
  if (edState && !forceNew) return edState;
  const mod = await loadEngine();
  const seed = new Uint8Array(32);
  crypto.getRandomValues(seed);
  const kp = JSON.parse(await mod.ed25519_keypair_from_seed_json(seed));
  if (!kp.ok) throw new Error(kp.error || 'Keypair generation failed');
  edState = {
    seed,
    keyId: kp.key_id,
    publicKeyHex: kp.public_key_hex,
    lastSigJson: null,
    lastPayloadBytes: null,
  };
  edKeyIdVal.textContent = kp.key_id;
  edPubKeyVal.textContent = kp.public_key_hex;
  edDlSigBtn.disabled = true;
  edSigPreview.hidden = true;
  return edState;
}

async function runEdSign() {
  try {
    const state = await ensureEdKeypair(false);
    const mod = await loadEngine();
    const payloadBytes = new TextEncoder().encode(edPayloadInput.value || '');
    const t0 = performance.now();
    const signed = JSON.parse(await mod.ed25519_sign_bytes_json(state.seed, payloadBytes));
    const elapsed = performance.now() - t0;
    if (!signed.ok) {
      edVerifyOut.className = 'lab-out err';
      edVerifyOut.textContent = `✕ Sign failed: ${signed.error}`;
      return null;
    }
    state.lastSigJson = signed.signature_json;
    state.lastPayloadBytes = payloadBytes;
    edSigPreview.textContent = JSON.stringify(signed.signature, null, 2);
    edSigPreview.hidden = false;
    edDlSigBtn.disabled = false;
    edVerifyOut.className = 'lab-out blocked';
    edVerifyOut.textContent = `✓ Signed ${payloadBytes.length} B with key_id=${state.keyId} (${elapsed.toFixed(1)} ms) — ready to verify or download .msig.json`;
    return state;
  } catch (err) {
    edVerifyOut.className = 'lab-out err';
    edVerifyOut.textContent = `✕ Sign error: ${errMessage(err)}`;
    return null;
  }
}

edGenKeyBtn.addEventListener('click', async () => {
  try {
    const st = await ensureEdKeypair(true);
    edVerifyOut.className = 'lab-out blocked';
    edVerifyOut.textContent = `✓ Generated new RFC 8032 Ed25519 keypair · key_id=${st.keyId}`;
  } catch (err) {
    edVerifyOut.className = 'lab-out err';
    edVerifyOut.textContent = `✕ Keygen error: ${errMessage(err)}`;
  }
});

edCopyKeyIdBtn.addEventListener('click', () => {
  if (edState && navigator.clipboard) {
    navigator.clipboard.writeText(edState.keyId);
    edCopyKeyIdBtn.textContent = t('copiedBtn');
    setTimeout(() => { edCopyKeyIdBtn.textContent = t('copyBtn'); }, 1200);
  }
});

edCopyPubKeyBtn.addEventListener('click', () => {
  if (edState && navigator.clipboard) {
    navigator.clipboard.writeText(edState.publicKeyHex);
    edCopyPubKeyBtn.textContent = t('copiedBtn');
    setTimeout(() => { edCopyPubKeyBtn.textContent = t('copyBtn'); }, 1200);
  }
});

edSignBtn.addEventListener('click', runEdSign);

edDlSigBtn.addEventListener('click', () => {
  if (edState?.lastSigJson) {
    downloadBlob(edState.lastSigJson, `publisher-${edState.keyId}.msig.json`, 'application/json');
  }
});

edVerifyValidBtn.addEventListener('click', async () => {
  try {
    const state = edState?.lastSigJson ? edState : await runEdSign();
    if (!state) return;
    const mod = await loadEngine();
    const t0 = performance.now();
    const res = JSON.parse(
      await mod.ed25519_verify_bytes_json(
        state.lastSigJson,
        JSON.stringify([state.publicKeyHex]),
        state.lastPayloadBytes,
      ),
    );
    const elapsed = performance.now() - t0;
    edVerifyOut.className = 'lab-out ' + (res.ok && res.verified ? 'blocked' : 'err');
    edVerifyOut.textContent = res.ok
      ? `✓ Verified (Ed25519 OK · ${elapsed.toFixed(1)} ms) — key_id=${res.key_id} · payload=${res.payload_length} B · sha256=${res.payload_sha256.slice(0, 16)}...`
      : `✕ Verification failed: ${res.error}`;
  } catch (err) {
    edVerifyOut.className = 'lab-out err';
    edVerifyOut.textContent = `✕ Verify error: ${errMessage(err)}`;
  }
});

edVerifyTamperBtn.addEventListener('click', async () => {
  try {
    const state = edState?.lastSigJson ? edState : await runEdSign();
    if (!state) return;
    const mod = await loadEngine();
    const tampered = new Uint8Array(state.lastPayloadBytes.length || 1);
    tampered.set(state.lastPayloadBytes);
    tampered[0] = (tampered[0] ^ 0x01) & 0xff;
    const res = JSON.parse(
      await mod.ed25519_verify_bytes_json(
        state.lastSigJson,
        JSON.stringify([state.publicKeyHex]),
        tampered,
      ),
    );
    edVerifyOut.className = 'lab-out ' + (!res.verified && String(res.error).startsWith('DigestMismatch') ? 'blocked' : 'err');
    edVerifyOut.textContent = !res.verified
      ? `✕ ${res.error} — 1-byte payload tamper rejected as expected!`
      : `Unexpected pass: ${JSON.stringify(res)}`;
  } catch (err) {
    edVerifyOut.className = 'lab-out err';
    edVerifyOut.textContent = `✕ Verify error: ${errMessage(err)}`;
  }
});

edVerifyUntrustedBtn.addEventListener('click', async () => {
  try {
    const state = edState?.lastSigJson ? edState : await runEdSign();
    if (!state) return;
    const mod = await loadEngine();
    const otherSeed = new Uint8Array(32);
    crypto.getRandomValues(otherSeed);
    const otherKp = JSON.parse(await mod.ed25519_keypair_from_seed_json(otherSeed));
    const res = JSON.parse(
      await mod.ed25519_verify_bytes_json(
        state.lastSigJson,
        JSON.stringify([otherKp.public_key_hex]),
        state.lastPayloadBytes,
      ),
    );
    edVerifyOut.className = 'lab-out ' + (!res.verified && String(res.error).startsWith('UntrustedKey') ? 'blocked' : 'err');
    edVerifyOut.textContent = !res.verified
      ? `✕ ${res.error} — signer key not in trusted set rejected as expected!`
      : `Unexpected pass: ${JSON.stringify(res)}`;
  } catch (err) {
    edVerifyOut.className = 'lab-out err';
    edVerifyOut.textContent = `✕ Verify error: ${errMessage(err)}`;
  }
});

// --- Card 3: AEAD Streaming Encryption Lab (MLSENC01) ---
const aeadModeSelect = document.getElementById('aeadModeSelect');
const aeadArgonMem = document.getElementById('aeadArgonMem');
const aeadArgonPasses = document.getElementById('aeadArgonPasses');
const aeadSecretInput = document.getElementById('aeadSecretInput');
const aeadGenRawKeyBtn = document.getElementById('aeadGenRawKeyBtn');
const aeadPlainInput = document.getElementById('aeadPlainInput');
const aeadSealBtn = document.getElementById('aeadSealBtn');
const aeadDlMencBtn = document.getElementById('aeadDlMencBtn');
const aeadUnsealBtn = document.getElementById('aeadUnsealBtn');
const aeadTamperBtn = document.getElementById('aeadTamperBtn');
const aeadOut = document.getElementById('aeadOut');

function generateRandomRawKeyHex() {
  const key = new Uint8Array(32);
  crypto.getRandomValues(key);
  return bytesToHex(key);
}

aeadGenRawKeyBtn.addEventListener('click', () => {
  aeadModeSelect.value = 'raw-key';
  aeadSecretInput.value = generateRandomRawKeyHex();
  aeadOut.className = 'lab-out blocked';
  aeadOut.textContent = '✓ Generated random 32-byte raw ChaCha20-Poly1305 key (64 hex chars).';
});

aeadModeSelect.addEventListener('change', () => {
  if (aeadModeSelect.value === 'raw-key' && !/^[0-9a-fA-F]{64}$/.test(aeadSecretInput.value.trim())) {
    aeadSecretInput.value = generateRandomRawKeyHex();
  } else if (aeadModeSelect.value === 'argon2id' && /^[0-9a-fA-F]{64}$/.test(aeadSecretInput.value.trim())) {
    aeadSecretInput.value = 'moonlibsync-070-browser-passphrase';
  }
});

function getCurrentAeadSecret() {
  const usePassphrase = aeadModeSelect.value === 'argon2id';
  const raw = aeadSecretInput.value || '';
  if (usePassphrase) {
    return { usePassphrase: true, secretBytes: new TextEncoder().encode(raw) };
  }
  const keyBytes = hexToBytes(raw);
  return { usePassphrase: false, secretBytes: keyBytes };
}

async function runAeadSeal() {
  try {
    const mod = await loadEngine();
    const plainBytes = new TextEncoder().encode(aeadPlainInput.value || '');
    const { usePassphrase, secretBytes } = getCurrentAeadSecret();
    const salt16 = new Uint8Array(16);
    crypto.getRandomValues(salt16);
    const noncePrefix12 = new Uint8Array(12);
    crypto.getRandomValues(noncePrefix12.subarray(0, 8)); // bytes 8..11 stay 0x00
    const memKib = Number(aeadArgonMem.value) || 1024;
    const passes = Number(aeadArgonPasses.value) || 1;
    const t0 = performance.now();
    const res = JSON.parse(
      await mod.seal_bytes_json(plainBytes, secretBytes, usePassphrase, salt16, noncePrefix12, 65536, memKib, passes),
    );
    const elapsed = performance.now() - t0;
    if (!res.ok) {
      aeadOut.className = 'lab-out err';
      aeadOut.textContent = `✕ Seal failed: ${res.error}`;
      return null;
    }
    const cipherBytes = hexToBytes(res.cipher_hex);
    aeadState = { cipherBytes, usePassphrase, secretBytes };
    aeadDlMencBtn.disabled = false;
    aeadOut.className = 'lab-out blocked';
    aeadOut.textContent = `✓ Sealed MLSENC01 (${res.kdf_mode}) — plain=${res.plain_bytes} B → cipher=${res.cipher_bytes} B (56 B header + AEAD tag · ${elapsed.toFixed(1)} ms) · header=${toHexPreview(cipherBytes, 16)}`;
    return aeadState;
  } catch (err) {
    aeadOut.className = 'lab-out err';
    aeadOut.textContent = `✕ Seal error: ${errMessage(err)}`;
    return null;
  }
}

aeadSealBtn.addEventListener('click', runAeadSeal);

aeadDlMencBtn.addEventListener('click', () => {
  if (aeadState?.cipherBytes?.length) {
    downloadBlob(aeadState.cipherBytes, 'sealed-payload.menc', 'application/octet-stream');
  }
});

aeadUnsealBtn.addEventListener('click', async () => {
  try {
    const state = aeadState?.cipherBytes?.length ? aeadState : await runAeadSeal();
    if (!state) return;
    const mod = await loadEngine();
    const { usePassphrase, secretBytes } = getCurrentAeadSecret();
    const t0 = performance.now();
    const res = JSON.parse(await mod.unseal_bytes_json(state.cipherBytes, secretBytes, usePassphrase));
    const elapsed = performance.now() - t0;
    if (res.ok) {
      const plainText = new TextDecoder().decode(hexToBytes(res.plain_hex));
      const snippet = plainText.length > 72 ? plainText.slice(0, 72) + '…' : plainText;
      aeadOut.className = 'lab-out blocked';
      aeadOut.textContent = `✓ Authenticated (${res.kdf_mode} · ${elapsed.toFixed(1)} ms) — plain=${res.plain_bytes} B · sha256=${res.plain_sha256.slice(0, 16)}... · "${snippet}"`;
    } else {
      aeadOut.className = 'lab-out err';
      aeadOut.textContent = `✕ Unseal failed (${res.error})`;
    }
  } catch (err) {
    aeadOut.className = 'lab-out err';
    aeadOut.textContent = `✕ Unseal error: ${errMessage(err)}`;
  }
});

aeadTamperBtn.addEventListener('click', async () => {
  try {
    const state = aeadState?.cipherBytes?.length ? aeadState : await runAeadSeal();
    if (!state) return;
    const mod = await loadEngine();
    const tampered = new Uint8Array(state.cipherBytes.length);
    tampered.set(state.cipherBytes);
    tampered[tampered.length - 1] = (tampered[tampered.length - 1] ^ 0x01) & 0xff;
    const res = JSON.parse(await mod.unseal_bytes_json(tampered, state.secretBytes, state.usePassphrase));
    aeadOut.className = 'lab-out ' + (!res.ok && res.error === 'AuthenticationFailed' ? 'blocked' : 'err');
    aeadOut.textContent = !res.ok
      ? `✕ ${res.error} — 1-byte ciphertext / Poly1305 tag tamper rejected as expected!`
      : `Unexpected pass: ${JSON.stringify(res)}`;
  } catch (err) {
    aeadOut.className = 'lab-out err';
    aeadOut.textContent = `✕ Tamper test error: ${errMessage(err)}`;
  }
});

// --- Card 4: X25519 Multi-Recipient Envelope Lab (MLSENC02) ---
const envGenKeysBtn = document.getElementById('envGenKeysBtn');
const envSealBtn = document.getElementById('envSealBtn');
const envDlBtn = document.getElementById('envDlBtn');
const envAliceMeta = document.getElementById('envAliceMeta');
const envBobMeta = document.getElementById('envBobMeta');
const envMalloryMeta = document.getElementById('envMalloryMeta');
const envPlainInput = document.getElementById('envPlainInput');
const envUnsealAliceBtn = document.getElementById('envUnsealAliceBtn');
const envUnsealBobBtn = document.getElementById('envUnsealBobBtn');
const envUnsealMalloryBtn = document.getElementById('envUnsealMalloryBtn');
const envTamperBtn = document.getElementById('envTamperBtn');
const envOut = document.getElementById('envOut');
const envMetaPreview = document.getElementById('envMetaPreview');

function randomHexBytes(len) {
  const buf = new Uint8Array(len);
  crypto.getRandomValues(buf);
  return bytesToHex(buf);
}

async function ensureEnvKeys(forceNew = false) {
  if (envState?.alice && !forceNew) return envState;
  const mod = await loadEngine();
  const [alice, bob, mallory] = await Promise.all([
    mod.x25519_keypair_from_secret_json(randomHexBytes(32)).then(JSON.parse),
    mod.x25519_keypair_from_secret_json(randomHexBytes(32)).then(JSON.parse),
    mod.x25519_keypair_from_secret_json(randomHexBytes(32)).then(JSON.parse),
  ]);
  if (!alice.ok || !bob.ok || !mallory.ok) {
    throw new Error(alice.error || bob.error || mallory.error || 'X25519 keygen failed');
  }
  envState = { alice, bob, mallory, cipherBytes: null, sealRes: null };
  envAliceMeta.textContent = `key_id: ${alice.key_id}\npub: ${alice.public_key_hex.slice(0, 24)}…`;
  envBobMeta.textContent = `key_id: ${bob.key_id}\npub: ${bob.public_key_hex.slice(0, 24)}…`;
  envMalloryMeta.textContent = `key_id: ${mallory.key_id}\npub: ${mallory.public_key_hex.slice(0, 24)}…`;
  envDlBtn.disabled = true;
  envMetaPreview.hidden = true;
  return envState;
}

async function runEnvSeal() {
  try {
    const state = await ensureEnvKeys(false);
    const mod = await loadEngine();
    const plainBytes = new TextEncoder().encode(envPlainInput.value || '');
    const t0 = performance.now();
    const res = JSON.parse(
      await mod.seal_envelope_json(
        plainBytes,
        JSON.stringify([state.alice.public_key_hex, state.bob.public_key_hex]),
        randomHexBytes(32),
        randomHexBytes(32),
        randomHexBytes(4),
        65536,
      ),
    );
    const elapsed = performance.now() - t0;
    if (!res.ok) {
      envOut.className = 'lab-out err';
      envOut.textContent = `✕ Envelope seal failed: ${res.error}`;
      return null;
    }
    state.cipherBytes = hexToBytes(res.ciphertext_hex);
    state.sealRes = res;
    envDlBtn.disabled = false;
    envOut.className = 'lab-out blocked';
    envOut.textContent = `✓ Sealed MLSENC02 for ${res.recipient_count} recipients (Alice + Bob · ${elapsed.toFixed(1)} ms) — plain=${plainBytes.length} B → cipher=${res.ciphertext_bytes} B · sha256=${res.ciphertext_sha256.slice(0, 16)}...`;
    envMetaPreview.textContent = JSON.stringify(
      {
        magic: 'MLSENC02',
        recipient_count: res.recipient_count,
        recipient_key_ids: res.recipient_key_ids,
        ephemeral_public_key_hex: res.ephemeral_public_key_hex,
        chunk_size: res.chunk_size,
        ciphertext_bytes: res.ciphertext_bytes,
      },
      null,
      2,
    );
    envMetaPreview.hidden = false;
    return state;
  } catch (err) {
    envOut.className = 'lab-out err';
    envOut.textContent = `✕ Envelope seal error: ${errMessage(err)}`;
    return null;
  }
}

envGenKeysBtn.addEventListener('click', async () => {
  try {
    const st = await ensureEnvKeys(true);
    envOut.className = 'lab-out blocked';
    envOut.textContent = `✓ Generated fresh X25519 keys — Alice=${st.alice.key_id}, Bob=${st.bob.key_id}, Mallory=${st.mallory.key_id}`;
  } catch (err) {
    envOut.className = 'lab-out err';
    envOut.textContent = `✕ X25519 keygen error: ${errMessage(err)}`;
  }
});

envSealBtn.addEventListener('click', runEnvSeal);

envDlBtn.addEventListener('click', () => {
  if (envState?.cipherBytes?.length) {
    downloadBlob(envState.cipherBytes, 'multi-recipient.menv', 'application/octet-stream');
  }
});

async function runEnvUnsealAs(who, expectReject = false) {
  try {
    const state = envState?.cipherBytes?.length ? envState : await runEnvSeal();
    if (!state) return;
    const party = state[who];
    const mod = await loadEngine();
    const t0 = performance.now();
    const res = JSON.parse(await mod.unseal_envelope_json(state.cipherBytes, party.secret_key_hex));
    const elapsed = performance.now() - t0;
    const label = who.charAt(0).toUpperCase() + who.slice(1);
    if (res.ok) {
      const text = new TextDecoder().decode(hexToBytes(res.plaintext_hex));
      const snippet = text.length > 72 ? text.slice(0, 72) + '…' : text;
      envOut.className = 'lab-out ' + (expectReject ? 'err' : 'blocked');
      envOut.textContent = `✓ Decrypted as ${label} (key_id=${party.key_id} · ${elapsed.toFixed(1)} ms) — ${res.plaintext_bytes} B · sha256=${res.plaintext_sha256.slice(0, 16)}... · "${snippet}"`;
    } else {
      envOut.className = 'lab-out ' + (expectReject && res.error === 'AuthenticationFailed' ? 'blocked' : 'err');
      envOut.textContent = expectReject
        ? `✕ ${res.error} — ${label} (key_id=${party.key_id}) is NOT a recipient and was rejected as expected!`
        : `✕ Unseal as ${label} failed: ${res.error}`;
    }
  } catch (err) {
    envOut.className = 'lab-out err';
    envOut.textContent = `✕ Unseal error: ${errMessage(err)}`;
  }
}

envUnsealAliceBtn.addEventListener('click', () => runEnvUnsealAs('alice', false));
envUnsealBobBtn.addEventListener('click', () => runEnvUnsealAs('bob', false));
envUnsealMalloryBtn.addEventListener('click', () => runEnvUnsealAs('mallory', true));

envTamperBtn.addEventListener('click', async () => {
  try {
    const state = envState?.cipherBytes?.length ? envState : await runEnvSeal();
    if (!state) return;
    const mod = await loadEngine();
    const tampered = new Uint8Array(state.cipherBytes.length);
    tampered.set(state.cipherBytes);
    tampered[tampered.length - 1] = (tampered[tampered.length - 1] ^ 0x01) & 0xff;
    const res = JSON.parse(await mod.unseal_envelope_json(tampered, state.alice.secret_key_hex));
    envOut.className = 'lab-out ' + (!res.ok && res.error === 'AuthenticationFailed' ? 'blocked' : 'err');
    envOut.textContent = !res.ok
      ? `✕ ${res.error} — 1-byte MLSENC02 ciphertext / Poly1305 tamper rejected even for authorized Alice!`
      : `Unexpected pass: ${JSON.stringify(res)}`;
  } catch (err) {
    envOut.className = 'lab-out err';
    envOut.textContent = `✕ Tamper test error: ${errMessage(err)}`;
  }
});

// --- Card 5: Ed25519 Trust Keyring & 2-of-3 Threshold Quorum Lab ---
const quorumMinSelect = document.getElementById('quorumMinSelect');
const quorumGenBtn = document.getElementById('quorumGenBtn');
const quorumPayloadInput = document.getElementById('quorumPayloadInput');
const quorumVerifyBtn = document.getElementById('quorumVerifyBtn');
const quorumTamperBtn = document.getElementById('quorumTamperBtn');
const quorumDlKeyringBtn = document.getElementById('quorumDlKeyringBtn');
const quorumDlBundleBtn = document.getElementById('quorumDlBundleBtn');
const quorumOut = document.getElementById('quorumOut');
const quorumDetails = document.getElementById('quorumDetails');
const quorumJsonPreview = document.getElementById('quorumJsonPreview');

const quorumSignerEls = [0, 1, 2].map((idx) => ({
  card: document.getElementById(`quorumCard${idx}`),
  badge: document.getElementById(`quorumBadge${idx}`),
  meta: document.getElementById(`quorumKeyMeta${idx}`),
  signChk: document.getElementById(`quorumSign${idx}`),
  revokeChk: document.getElementById(`quorumRevoke${idx}`),
}));

function updateQuorumBadges() {
  quorumSignerEls.forEach((el) => {
    const revoked = !!el.revokeChk.checked;
    const signed = !!el.signChk.checked;
    el.card.classList.toggle('revoked', revoked);
    if (revoked) {
      el.badge.className = 'badge badge-delete';
      el.badge.textContent = t('quorumStateRevoked');
    } else if (signed) {
      el.badge.className = 'badge badge-add';
      el.badge.textContent = t('quorumStateActive');
    } else {
      el.badge.className = 'badge badge-unchanged';
      el.badge.textContent = t('quorumStateUnsigned');
    }
  });
}

async function ensureQuorumSigners(forceNew = false) {
  if (quorumState?.signers?.length === 3 && !forceNew) return quorumState;
  const mod = await loadEngine();
  const names = ['Alice', 'Bob', 'Carol'];
  const signers = [];
  for (let i = 0; i < 3; i++) {
    const seed = new Uint8Array(32);
    crypto.getRandomValues(seed);
    const kp = JSON.parse(await mod.ed25519_keypair_from_seed_json(seed));
    if (!kp.ok) throw new Error(kp.error || 'Ed25519 keygen failed');
    signers.push({ name: names[i], seed, kp });
    quorumSignerEls[i].meta.textContent = `key_id: ${kp.key_id}\npub: ${kp.public_key_hex.slice(0, 22)}…`;
  }
  quorumState = { signers, lastKeyringJson: null, lastBundleJson: null };
  updateQuorumBadges();
  return quorumState;
}

async function runQuorumEvaluation(tamperPayload = false) {
  try {
    const state = await ensureQuorumSigners(false);
    updateQuorumBadges();
    const mod = await loadEngine();
    const minQuorum = Number(quorumMinSelect.value) || 2;
    const trustedKeys = state.signers.map((s) => s.kp.public_key_hex);
    const revokedIds = state.signers
      .filter((_, idx) => quorumSignerEls[idx].revokeChk.checked)
      .map((s) => s.kp.key_id);

    const krRes = JSON.parse(
      await mod.create_trust_keyring_json(
        JSON.stringify(trustedKeys),
        JSON.stringify(revokedIds),
        minQuorum,
      ),
    );
    if (!krRes.ok) {
      state.lastKeyringJson = null;
      state.lastBundleJson = null;
      quorumDetails.hidden = true;
      quorumOut.className = 'lab-out err';
      quorumOut.textContent = `✕ Keyring policy rejected (${krRes.error}) — active keys (${3 - revokedIds.length}) < min_quorum (${minQuorum})`;
      quorumDlKeyringBtn.disabled = true;
      quorumDlBundleBtn.disabled = true;
      return;
    }
    state.lastKeyringJson = krRes.keyring_json;
    quorumDlKeyringBtn.disabled = false;

    const payloadBytes = new TextEncoder().encode(quorumPayloadInput.value || '');
    const selectedSigners = state.signers.filter((_, idx) => quorumSignerEls[idx].signChk.checked);
    if (selectedSigners.length === 0) {
      state.lastBundleJson = null;
      quorumDetails.hidden = true;
      quorumOut.className = 'lab-out err';
      quorumOut.textContent = '✕ Select at least 1 signer checkbox to assemble signatures.';
      quorumDlBundleBtn.disabled = true;
      return;
    }

    const sigJsons = [];
    for (const signer of selectedSigners) {
      const signed = JSON.parse(await mod.ed25519_sign_bytes_json(signer.seed, payloadBytes));
      if (!signed.ok) throw new Error(signed.error || 'Sign failed');
      sigJsons.push(signed.signature_json);
    }

    let verifyBytes = payloadBytes;
    if (tamperPayload) {
      verifyBytes = new Uint8Array(payloadBytes.length || 1);
      verifyBytes.set(payloadBytes);
      verifyBytes[0] = (verifyBytes[0] ^ 0x01) & 0xff;
    }

    const t0 = performance.now();
    const qRes = JSON.parse(
      await mod.verify_quorum_bytes_json(JSON.stringify(sigJsons), krRes.keyring_json, verifyBytes),
    );
    const elapsed = performance.now() - t0;

    if (qRes.ok) {
      state.lastBundleJson = qRes.bundle_json;
      quorumDlBundleBtn.disabled = false;
      quorumOut.className = 'lab-out blocked';
      const revNote = qRes.revoked_hits.length ? ` · revoked_hits=[${qRes.revoked_hits.join(', ')}]` : '';
      quorumOut.textContent = `✓ QUORUM VERIFIED (${qRes.verified_key_ids.length}/${qRes.required_quorum} required · ${elapsed.toFixed(1)} ms) — verified=[${qRes.verified_key_ids.join(', ')}]${revNote}`;
      quorumJsonPreview.textContent =
        `// TrustKeyring (Schema 4)\n${krRes.keyring_json.trim()}\n\n// SignatureBundle (Schema 4)\n${qRes.bundle_json.trim()}`;
      quorumDetails.hidden = false;
    } else {
      state.lastBundleJson = null;
      quorumDlBundleBtn.disabled = true;
      const expectedTamper = tamperPayload && String(qRes.error).startsWith('DigestMismatch');
      quorumOut.className = 'lab-out ' + (expectedTamper ? 'blocked' : 'err');
      quorumOut.textContent = tamperPayload
        ? `✕ ${qRes.error} — 1-byte payload tamper rejected by quorum verifier!`
        : `✕ QUORUM FAILED (${qRes.error} · ${elapsed.toFixed(1)} ms) — signed=${selectedSigners.length}, revoked=${revokedIds.length}, required=${minQuorum}`;
      quorumJsonPreview.textContent = `// TrustKeyring (Schema 4)\n${krRes.keyring_json.trim()}`;
      quorumDetails.hidden = false;
    }
  } catch (err) {
    quorumOut.className = 'lab-out err';
    quorumOut.textContent = `✕ Quorum error: ${errMessage(err)}`;
  }
}

quorumGenBtn.addEventListener('click', async () => {
  try {
    await ensureQuorumSigners(true);
    await runQuorumEvaluation(false);
  } catch (err) {
    quorumOut.className = 'lab-out err';
    quorumOut.textContent = `✕ Quorum error: ${errMessage(err)}`;
  }
});
quorumVerifyBtn.addEventListener('click', () => runQuorumEvaluation(false));
quorumTamperBtn.addEventListener('click', () => runQuorumEvaluation(true));
quorumMinSelect.addEventListener('change', () => {
  if (quorumState) runQuorumEvaluation(false);
});
quorumSignerEls.forEach((el) => {
  el.signChk.addEventListener('change', () => {
    updateQuorumBadges();
    if (quorumState) runQuorumEvaluation(false);
  });
  el.revokeChk.addEventListener('change', () => {
    updateQuorumBadges();
    if (quorumState) runQuorumEvaluation(false);
  });
});
quorumDlKeyringBtn.addEventListener('click', () => {
  if (quorumState?.lastKeyringJson) {
    downloadBlob(quorumState.lastKeyringJson, 'trust-keyring.json', 'application/json');
  }
});
quorumDlBundleBtn.addEventListener('click', () => {
  if (quorumState?.lastBundleJson) {
    downloadBlob(quorumState.lastBundleJson, 'quorum-bundle.msig.json', 'application/json');
  }
});

applyTheme();
applyI18n();
loadEngine()
  .then(() => runBuiltInBinarySample())
  .catch(() => {});
