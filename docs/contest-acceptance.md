# MoonLibSync 0.7.1 / 0.7.0 演进与验收矩阵

> **0.7.1 增量加固说明**：`0.7.1` 在保持 `0.7.0` 全部公开 API（`.mbti` 零变更）基础上，修复了 `README*.md` CLI 示例、`examples/web-demo/demo.js` 提示命令与 `CHANGELOG.md` 描述偏差，为 Native CLI `fetch-sync` 补齐了**无条件远端 `.sig` 块级重算核验**与**至多 5 跳安全 HTTP `3xx` 重定向跟踪**（阻止 `https:// -> http://` 降级、非 HTTP scheme 及权威区 `@` 注入），并配置 `.github/workflows/release.yml` 自动提取 `CHANGELOG.md` + `SHA256SUMS.txt` 发布说明；CLI 实测扩展至 **58** 项 Native 单元测试 + **788** Windows/NTFS & **812** Linux/ext4（`0 unsupported`）集成用例。下方表格完整保留已完成发布的 `0.7.0`（`79b96b7`）实测档案。

状态：**`0.7.0` `published-and-consumer-verified` / `0.7.1` 发布准备中**。`0.7.0`（正式发布源 `publication_source_sha`：`79b96b783f47dcbcb31920a18521441df0258945`，分支 `main`、标签 `v0.7.0`）已完成四层红队对抗加固、同 SHA 全平台 CI、Mooncakes 上线、双平台独立新缓存消费、GitHub Release 二进制分发及 GitHub Pages Web Studio 部署。完整发布指纹与归档校验见 [0.7.0 发布验收记录](release-0.7.0.md)。

| 验收维度 | `0.7.0` 实测状态与核验内容 | 实际证据与边界说明 |
| --- | --- | --- |
| **1. MoonBit 架构与零实验包** | 纯 MoonBit（62 个生产 `.mbt` / 22,784 行，17 个包），锁定 `moonc v0.10.22+124d61d05` 与 `mooncrypt@0.4.5` 等 4 项依赖；根包与 `crypto/` 零 `allow-experimental-packages` | `toolchain.lock.json`、`dependencies.lock.json`、`scripts/verify_dependencies.py`；三目标（`native`/`js`/`wasm-gc`）零告警 `--deny-warn` |
| **2. GitHub 公开与版本流** | 公开仓库 `YKDshaxing/moonlibsync`；同 SHA `79b96b7` 标签 `v0.7.0` 与 [GitHub Release v0.7.0](https://github.com/YKDshaxing/moonlibsync/releases/tag/v0.7.0) 已正式发布 | Release 附带 CI 自动构建的 `moonlibsync-linux-x86_64`（`4,789,608` B）、`moonlibsync-windows-x86_64.exe`（`3,148,800` B）、`SHA256SUMS.txt`（`188` B） |
| **3. 核心差异化功能闭环** | 在双向兼容 `librsync v2.3.4`（`0x72730147`/`0x72730137`/`0x72730236`）与流式目录归档（`MLSBDL01`）基础上，交付 HTTP `Range` (`zsync`) 规划与拉取、零中间文件 `compose_deltas`、Zlib/Raw DEFLATE 有界流、`MLSENC02` X25519 多接收方信封、Ed25519 `M-of-N` 吊销 Keyring、`--jobs` 并发目录引擎与 `DirMetadata` | 公开声明受 `scripts/interface_guard.py` 与 `pkg.generated.mbti` 基线守护；历史 `0.1.0` 进程基准（`docs/benchmarks.md`）独立归属 `Commit 15`，不冒充 `0.7.0` 重测数据 |
| **4. 复现文档与红队安全边界** | 同步更新中英 `README`、`CHANGELOG.md`、`SECURITY.md`、`SOURCES.md`、`THIRD_PARTY_NOTICES.md`、`docs/cli.md`、`docs/resources.md`、`docs/dir-sync.md` | 显式声明 `--meta` 独立于 `--verify-sig`/`--verify-bundle` 摘要、`Limits` 为逻辑预算而非 RSS 硬保证、`js/` SDK 当前未发 npm |
| **5. 同 SHA 多平台 CI 与失败门禁** | `79b96b7` 上 `Core examples CLI and interoperability`（`main` [45119294836](https://github.com/YKDshaxing/moonlibsync/actions/runs/45119294836) / `v0.7.0` [45119304641](https://github.com/YKDshaxing/moonlibsync/actions/runs/45119304641)）、`Release Native CLI`（[45119304653](https://github.com/YKDshaxing/moonlibsync/actions/runs/45119304653)）、`Deploy Web Demo to GitHub Pages`（[45119294853](https://github.com/YKDshaxing/moonlibsync/actions/runs/45119294853)）全部 `success` | `scripts/failure_gates.py` 5 组正反失败门禁、`scripts/check_prepared_interface.py`（12 项编译期检查）、`scripts/native_probe.py` 全通过 |
| **6. 可运行示例、SDK 与 Web Studio** | 6 个 MoonBit 示例 × 三目标（`basic`/`prepared`/`verified`/`auto`/`transfer`/`streaming`）；Web Studio `0.7.0` 37 项 JS ESM 导出与 `@ykdshaxing/moonlibsync@0.7.0` SDK（33 个强类型方法、0 `any`） | `WEB_DEMO_OK exports=37 verified=true`、`PAGES_RELEASE_SMOKE_OK exports=37`、`JS_SDK_OK`；实机浏览器 5-Tab 交互与中英切换实测 `0` console/page errors；线上 [GitHub Pages](https://ykdshaxing.github.io/moonlibsync/) HTTP `200` |
| **7. 全目标、CLI 与 `rdiff` 测试矩阵** | 根核心库 **252/252 × 3 目标** + `compress` **13/13 × 3 目标** + `crypto` **20/20 × 3 目标**；Native CLI **57** 项单元测试 + **784** Windows/NTFS & **808** Linux/ext4（`0 unsupported`）集成用例 | 外部真实 `librsync v2.3.4` 互操作 **274 对 / 496 参数 / 3,968 恢复**（Linux CI `reference` 实跑）；16 夹具/29 opcode 向量；HTTP `Range` 在回环服务与模拟器实测 |
| **8. Mooncakes 发布与双平台消费** | [Mooncakes `YKDshaxing/moonlibsync@0.7.0`](https://mooncakes.io/docs/YKDshaxing/moonlibsync@0.7.0) 已上传（`862,006` B、`344` 成员、SHA-256 `755bffbc...`），在线文档 `build_status: "success"` | Windows/NTFS 与 WSL2 Linux/ext4 独立新缓存 `release_check.py --registry` 均返回 `published-and-consumer-verified`，下载字节与审计完全一致 |
| **9. 开源许可证与第三方合规** | **LGPL-2.1-or-later**，随包保留完整 `COPYING.LESSER` / `COPYING` / `LICENSE`、`licenses/MoonBit-core-{LICENSE,NOTICE}`、`SOURCES.md` 与 `THIRD_PARTY_NOTICES.md` | `_build/release-0.7.0/windows/audit.json` 确认 `dirty: false`、`git_blob_byte_identity_verified: true`，无未经授权的源码改标 |

### `0.5.0`–`0.6.1` 历史演进里程碑
- **`0.6.1`**：将 `toolchain.lock.json` 升级至官方 `0.10.22+124d61d05`，适配 `core/compress/gzip` 单流语义与 `async/fs` 变更，清除四目标警告，修复 Mooncakes 在线文档构建。
- **`0.6.0`**：新增零 IO 密码学子包 `YKDshaxing/moonlibsync/crypto`（Ed25519 发布者签名 + `MLSENC01` ChaCha20-Poly1305/Argon2id AEAD）、双 Profile（`Rollsum` `0x72730137` + `RabinKarp` `0x72730147`）、`--detect-moves`、`reverse-delta`、`inspect-bundle`、`--exclude-from` 与 Shell 自动补全（CLI 增至 28 条）。
- **`0.5.0`**：新增确定性 `MLSBDL01` `.mbundle`/`.mbundle.gz` 归档容器、`dir-verify`、`--exclude` 前置目录剪枝、`--progress` stderr 进度条与零依赖 JS/TS SDK / 5-Tab Web Studio。

以下完整保留 `0.4.0`–`0.1.0` 历史验收快照，各自仅归属对应历史提交。

---

# MoonLibSync 0.4.0 演进与验收矩阵

- **0.4.0（本地全门禁通过）**：在保持 0.3.x 全部互操作与安全不变量的基础上，新增 Sans-IO `PatchDecoder` + `Sha256Hasher`、纯核心零 IO Schema 3 目录快照规划 `dir_sync.mbt`（三目标根库 **218/218** 通过）、Native CLI `--streaming`（已通过 **128 MiB** 大文件 `signature --block-size auto -> delta -> patch -> patch-verified` SHA-256 逐字节恢复实测）与 `dir-snapshot` / `dir-plan`（**30/30** Native CLI 单元测试与 **442** 集成用例通过），以及零后端浏览器 JS/ESM Demo `examples/web-demo`（`test-node.mjs` 通过）。详见 [CHANGELOG.md](../CHANGELOG.md)。
- **0.3.2**：O(1) 弱校验开放定址表与 Pending Literal Run（1 MiB 全异提速 **5.40x–5.60x**）、零 IO 流式状态机、`inspect-manifest` 与 `--max-*` 覆盖。
- **0.3.0 已发布并完成双平台注册表消费验收**（状态 `published-and-consumer-verified`）：正式发布源 `35b2225e56747c0d7568dd117017c25e6c658146`，[发布源同 SHA CI](https://github.com/YKDshaxing/moonlibsync/actions/runs/43025252619) 三任务全部通过，Windows/NTFS 与 Linux/ext4 独立新 SDK 空缓存下载消费通过。完整明细见 [0.3.0 发布记录](release-0.3.0.md)。
- **0.3.1 仓库整理与零破坏演进**：在完全保持 0.3.0 兼容性与测试矩阵的基础上，落地 `inspect_signature` O(1) 零分配、`RabinKarp` 快速幂/单次摘要、`SignatureIndex` 扁平弱校验缓存与批量 `blit` 拷贝优化，补充 `PreparedSignature::summary` / `PreparedSignature::plan_update`，并完善中英双语 README、历史发布 Tag 与 GitHub Release 自动化。详见 [CHANGELOG.md](../CHANGELOG.md)。

下文保留 0.2.0 与 0.1.0 历史阶段验收快照，不作为本版验收结论。

---

# 0.2.0阶段A发布验收（Commit24）

阶段A基线4452eddcd27818b5852850f07085f454fe75b453；0.2.0冻结标准差分、检查、索引复用、清单与受校验返回/提交，schema和默认预算不改。本版实际模块包审计、干净重建、发布源同SHA CI、标准Mooncakes上传及Windows/Linux两端三目标独立注册表消费全部通过，状态published-and-consumer-verified。最终结果及发布源/文档SHA分离见[0.2.0记录](release-0.2.0.md)。

下文0.1.0及各早期Commit的发布结果保持原版本和原SHA归属，不作为本版验收结果。

---

# 0.1.0 首版交付结果

**实际发布与独立注册表消费均通过**，状态published-and-consumer-verified。功能冻结857aa981debc3ce0c1e54176621e84454733202e；发布源f62958eceda9deecc4eae8a14007f5be76c59b0e；本段为后续证据文档，具体文档SHA在交付记录中单列，不冒充发布源。

| 验收范围 | 实际结果 |
| --- | --- |
| 实际模块包/许可证 | 官方moon package生成ZIP，179成员/268008字节；与发布Git原始字节及完整许可/来源核对通过 |
| 干净源码重建 | 仓库外新检出、固定工具链重新安装、三目标示例与Native文件流程通过，源内容未被构建改写 |
| 候选包消费 | Windows/NTFS与Linux/ext4的三目标API、默认/错误/实际COPY及CLI源码流程通过；本地workspace范围明确 |
| 发布源CI | [同SHA三项任务](https://github.com/YKDshaxing/moonlibsync/actions/runs/42594652417)成功；99/6/CLI各6/Windows83/Linux81/274对496参数3968恢复/82与29消费/全部门禁保留；新增发布工具4项另计 |
| Mooncakes实际上传 | YKDshaxing账号，用户允许的标准moon publish退出0/服务器200；2026-11-09T13:25:46.635422+00:00为注册表created_at |
| 独立注册表消费 | Windows上Native/JS/Wasm-GC，无本地替换、空注册表缓存，实际0.1.0及闭包核对，完整下载成员/元数据和ZIP哈希与候选一致，恢复/实际COPY/默认类型/错误捕获全部通过 |
| 公开包CLI | 实际下载源码另建Windows Native CLI/NTFS流程通过；Linux同SHA候选源码CLI/ext4验证，内容与公开包相同；无预编译安装器声明 |
| 标签/Release/后续开发 | 本笔未创建；没有进入后续功能开发 |

[完整发布实证](release.md)及交付记录区分冻结、发布源和后续文档。原基准保留原测量归属，未为换SHA重跑。首版规划内必需交付已无阻塞；未额外在WSL直接执行注册表消费，不扩大实测环境。以下发布前和早期阶段记录完整保留为历史快照。

# 0.1.0 发布验收记录入口（Commit 16）

功能冻结SHA为857aa981debc3ce0c1e54176621e84454733202e。0.1.0交付三项字节API、指定标准格式/资源契约、Native单文件CLI及核心三目标。正式归档、干净重建、候选包消费、发布身份/上传和无替换注册表消费逐项独立验收；提交前状态及日志在 `_build/release-0.1.0/`，实际结果由提交后交付记录提供，不能由本页能力描述推断上传成功。

[发布说明](release.md)列出门禁、实际源码与包内容的关联方式。候选发布源必须干净、已推送且同SHA全部必需CI成功。后续发布证据文档提交不改变注册表内原文档，也不能替代publication_source_sha。以下完整保留Commit15与Commit14快照，旧未发布状态归属各自阶段。

# Commit 15：当前阶段验收与功能冻结

基线925d47979549da4e8e3c32b742806513478346e6。当前已完成有限基准、使用/设计文档与首版功能冻结；运行库、CLI执行代码、默认值、锁和正式夹具保持基线。最终冻结SHA、同SHA全部必需CI、原始产物校验和测量/最终源码关联，在提交后交付记录提供，不为自身SHA另增提交。

| 原规划要求 | Commit15当前实现/交付状态 | 实际证据及目标 | 源码归属与未完成项 |
| --- | --- | --- | --- |
| 1 MoonBit为主，moonc>=0.10.16 | 固定0.10.20+65efd5b93与既有依赖闭包；核心/CLI仍为MoonBit | toolchain.lock、dependencies.lock、check.py三目标；Linux release基准 | Commit1–14执行代码不变；不承诺全部更高版本 |
| 2 GitHub公开，提交清晰 | 既有YKDshaxing仓库，Commit15独立工具/文档提交 | git历史、最终同SHA CI与交付记录 | 未代替发布身份/模块权限检查 |
| 3 结构清晰，核心功能完成 | 三API、现有标准格式/资源/CLI/目标范围冻结 | compatibility.md冻结表、tests/benchmarks/runtime-baseline.json的20文件指纹 | 运行代码归属Commit1–14，冻结15；不是0.1.0整体交付完成 |
| 4 README可复现 | 源码获取、公开导入、完整运行示例、错误/边界与基准说明 | README、design.md完整basic代码、现有三目标实际运行；CLI两平台 | 当前为源码消费；正式包解压与独立注册表消费待16 |
| 5 CI覆盖检查/构建/测试 | 保留原3任务和全部必需检查，增加小型基准工具正确性入口 | 同SHA三任务，benchmark.py --self-check（无完整计时或速度阈值） | 原覆盖不缩减，提交后报告实际状态 |
| 6 至少一个可运行例子 | 每平台三目标basic，实际COPY与恢复；Linux正式CLI/rdiff两条交换 | examples/basic、check_example.py、file_exchange.py | Commit14示例继续验证；不是已安装发布包消费 |
| 7 完整核心测试 | 各目标99；Python6；两平台Native辅助各6及平台集成；274/496/3968；原82/29；所有失败门禁 | check.py、cli_smoke、interop、consume脚本、failure_gates；基准另120预热/420正式，不混入测试 | Commit15没有增加库测试或用基准替代原回归；范围仍有限 |
| 8 发布Mooncakes | **未发布**，0.1.0仅开发元数据，无独立注册表证明 | 未发布声明；没有执行moon publish | 身份/精确版本检查、实际发布、无本地替换消费均待16 |
| 9 OSI许可证及上游授权 | LGPL-2.1-or-later、来源及第三方说明保留，新增工具明确原创/标准库调用 | COPYING.LESSER、COPYING、SOURCES、THIRD_PARTY_NOTICES | 源码许可文件存在不等于实际源码包分发审计通过，待16 |

有限基准在WSL2/Linux Native/ext4实际完成：两规模五类场景，参数2048/32，release正式CLI对固定rdiff Release，2预热+7正式交替顺序，三项操作全校验。patch两端使用相同rdiff delta。结果、min/median/max、实际大小/COPY/指令数、原始文件校验及结论边界见[基准](benchmarks.md)。运行时HEAD为基线且dirty=true，不冒充最终干净提交；交付前逐文件关联最终冻结源码，配置/依赖/执行代码变化必须重新测量。

冻结[公开接口/默认值/profile/标准指令/错误资源/CLI/目标及范围外清单](compatibility.md#commit-15首版功能冻结)。Commit16尚须完成：精确版本与发布身份检查；实际源码包和许可证分发审计；干净目录重建；发布源SHA与必需CI对应；Mooncakes实际发布；无本地替换的独立注册表消费；发布后证据归档。此七项没有在本笔执行；未创建标签、Release或上传。

## Commit 14 历史验收快照

以下完整保留Commit14记录；其中“未测基准/未冻结”等只属于当时阶段，不作为Commit15当前状态。

# Commit 14：九项阶段验收

本表逐项沿用原《MoonLibSync 远端签名差分库开发与验收规划书》“九项验收要求对应”的九行，不将规划当作结果。阶段基线为 Commit 13 `d605522738066ee2494b2b5306dd1b7d217ffeef`；本笔增量为示例、CI整合、失败门禁及文档。提交前采用稳定证据入口；最终源码SHA、同SHA CI与产物链接由提交后交付报告提供，不为补记自身SHA追加循环提交。

| 要求 | 当前实现或交付状态 | 实际命令／证据位置 | 验证目标与环境 | 源码提交归属 | 未完成项 |
| --- | --- | --- | --- | --- | --- |
| 1 MoonBit 为主，moonc >= 0.10.16 | 核心、CLI和示例为MoonBit；固定moonc 0.10.20+65efd5b93，moon/moonrun 0.1.20261104；依赖mooncrypt0.4.5 | `python scripts/check.py`；toolchain.lock.json、dependencies.lock.json及CI版本输出 | Windows/Linux，核心Native/JS/Wasm-GC | 工具链/依赖Commit1，算法Commit2–12，CLI13，示例14 | 没有验证所有更高版本；未承诺0.10.16本身可编译 |
| 2 GitHub 公开，提交清晰 | YKDshaxing/moonlibsync公开仓库；逐阶段独立提交，固定SSH归属 | 仓库匿名页面、`git log`、`git remote -v`；最终交付提供推送SHA | GitHub公开源码；推送认证与提交署名分别核对 | Commit1–14历史 | 不代表Mooncakes命名空间权限或发布成功 |
| 3 结构清晰，核心功能完成 | 三项公开字节API；标准RK+BLAKE2签名；全部delta指令解析；只凭签名生成增量；Native单文件CLI | pkg.generated.mbti、signature.mbt、delta.mbt、patch.mbt；`bash scripts/interop.sh`；docs/cli.md | 核心三目标；跨实现仅Linux Native；CLI Windows/NTFS、Linux/ext4 | 算法Commit2–12，CLI13；整合14 | 全量缓冲、单文件；无网络、目录同步、流式；首版冻结待后续 |
| 4 README 可复现 | 当前使用入口前置；固定工具链安装、依赖、示例、CLI及完整检查命令 | README.md；`python scripts/install_toolchain.py` 后按README运行；干净CI checkout实际执行 | Windows与Ubuntu24.04独立CI环境；本机WSL正向CLI用/tmp ext4 | 原说明Commit1–13；当前入口与历史分离14 | 独立正式源码包解压复现及注册表消费者待后续，不以本地源码示例抵扣 |
| 5 CI 覆盖检查/构建/测试 | 保留3任务：Linux参考，Windows及Ubuntu基础；核心check/build/test；三目标示例；CLI；资源、接口与隔离失败门禁 | .github/workflows/ci.yml；scripts/check.py；`python scripts/failure_gates.py`；_build/resources、interfaces、examples、gates、cli、interop、exchange | 固定工具链；Native/JS/Wasm-GC；rdiff仅Linux Native | 原任务Commit1–13，整合/门禁14 | 同SHA实际状态与产物在提交后报告；产物上传不代替检查通过 |
| 6 至少一个可运行例子 | examples/basic仅导入公开库；实际恢复断言；严格检查本次delta COPY>=512且delta<515；CLI/rdiff两条真实文件链 | `moon run examples/basic --target TARGET`；`python scripts/check_example.py --target TARGET`；`python scripts/file_exchange.py`；_build/examples与exchange | 纯字节示例Native/JS/Wasm-GC；文件交换Linux Native/ext4 | 示例及文件交换14，正式CLI13 | 不代表三目标均调用rdiff，不代表安装发布包后消费 |
| 7 完整核心测试 | 原99项库测试（含19资源项）；6项Python工具；6项Native CLI辅助；平台CLI场景；274输入对/496参数/3968恢复；原82签名/29delta消费；重建与损坏拒绝 | scripts/check.py、cli_smoke.py、interop.sh、consume_signature.py、consume_delta.py、rebuild-reference.sh；tests/interop/README.md | 三目标根包分别99；工具/CLI/示例独立计数；固定参考v2.3.4 | 核心Commit2–12、CLI13；14保持范围并新增隔离断言失败验证 | 有限确定性矩阵不是任意输入证明；Windows链接未执行项按实际报告，不计通过；基准/峰值内存未执行 |
| 8 发布 Mooncakes | **未发布**；0.1.0仅为开发元数据 | moon.mod、README未发布声明；没有执行moon publish | 本地源码与CI消费，不是注册表消费 | Commit1元数据，14明确边界 | 账号/命名空间权限、版本可用性、正式包审计、实际发布、无本地替换的外部消费全部待后续 |
| 9 OSI 许可证，遵守上游授权 | LGPL-2.1-or-later；保留完整许可文本及来源/第三方说明；核心不用C librsync FFI，参考工具只用于测试 | COPYING.LESSER、COPYING、SOURCES.md、THIRD_PARTY_NOTICES.md；固定上游SHA与文件级说明 | 源码树与离线夹具来源；依赖闭包按锁核验 | Commit1–13来源记录，14示例SPDX沿用 | 源码文件存在不等于最终分发包审计完成；实际入包内容及义务核对、最终源码包验收待后续 |

## 证据边界与统计

纯字节示例基准输入固定512/515字节，签名300字节。本机三目标实际delta18字节、COPY512，所有恢复相等；门槛仅要求delta<515、COPY>=512，不锁定未来18字节。每个平台正常示例3次单列；隔离故障驱动另运行损坏/正常示例各一次，不计为新增库单元测试。根包仍为99，Python工具仍为6，CLI辅助仍为6；各平台集成数量由本次CLI报告给出（具备Windows链接能力时83；无权限时79通过、4未执行；Linux81）。

Linux固定参考的完整正常矩阵仍执行一次，八组合各496，共3968恢复；两条CLI文件交换演示另列，不追加到矩阵数中。原参考16用例/64文件/12507字节与29个手写opcode向量均不刷新。损坏验证不重复全矩阵。失败门禁命令与结果见 `_build/gates/report.json`：`check_fixtures.py -> verify_fixtures.py` 和 `check_example.py -> moon run` 是CI实际使用的调用链；包装层 `check=True` / `check_returncode` 将非零继续传给 `check.py` 及无容错CI步骤。分别保存broken与normal日志，驱动仅在目标诊断和退出码符合预期时成功。

接口保护显式列根包、probes/digest、probes/native、probes/signature、cmd/moonlibsync、examples/basic。首先与HEAD受检接口原始字节比较（含删除），再保存存在/缺失状态，最后比较moon info后状态；不扫描缓存、构建树。固定工具链为basic生成空公开接口，已纳入提交；其他Native可执行包当前没有生成接口，其缺失状态也受检。

报告中的源码SHA与dirty取自实际Git；本地提交前执行为dirty，仅作为阶段调试证据。最终干净同SHA CI的日志与产物才作为提交交付证据。固定工具链/核心三目标验证、Linux参考兼容、CLI文件系统保证、源码许可证、正式分发审计及公开注册表消费是不同证据，不能互相替代。NTFS/ext4的正向结果不扩展到DrvFS；无覆盖重命名不支持时继续明确失败。

停止于Commit14。没有开展benchmark，没有修改默认预算、核心公开API、锁文件或正式夹具；没有进入Commit15首版冻结、打包、标签、Release或Mooncakes发布。

## Commit 23：阶段 A 组合验证（开发源码）

本笔保留旧166项库三目标矩阵、CLI314/315及15辅助、274对/496参数/3968恢复、82/29消费和32次Prepared恢复。新增28对/28参数的504组合恢复、两平台各三目标候选消费者、每目标16类核心拒绝及9个封装编译拒绝、每平台12类候选CLI拒绝和实际脚本故障传播分别记录，不合并为独立案例总数。计划、指纹、命令、计数及上传产物见[阶段A说明](../tests/stage-a/README.md)。

候选消费使用明确本地workspace替换，不是注册表消费。复用未观察到稳定总耗时优势，仍为全量缓冲；本笔不重新计时、不改写0.1.0历史发布证据。Commit24的版本决定、冻结、最终包/许可证审计、发布SHA/CI绑定、Mooncakes新版本发布及无替换注册表消费仍待后续，不创建标签或Release。
