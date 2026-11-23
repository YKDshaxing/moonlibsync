# MoonLibSync 0.7.0：发布归档、红队加固与双平台验收记录

状态：`published-and-consumer-verified`。`0.7.0` 已推送 GitHub、创建标签 `v0.7.0` 并发布至 Mooncakes，同时通过 Windows/NTFS 与 WSL2 Linux/ext4 独立新缓存公开注册表消费验证及 Mooncakes 在线文档构建。

> **源码归属声明**：
> - 正式发布源 `publication_source_sha`：`79b96b783f47dcbcb31920a18521441df0258945`（分支 `main`、标签 `v0.7.0`）。
> - 本文件及同步补齐的 `0.7.0` 文档对齐修改属于**发布后纯文档提交**（记录已产生的发布事实、CI 链接与检验明细），**不改动 `79b96b7` 对应的 `.mbt` / `.mbti` / `.js` / `.d.ts` / `moon.mod` / `moon.pkg` 代码与已上传 `YKDshaxing/moonlibsync@0.7.0` 模块包字节**，不以文档提交替代发布源。

---

## 一、固定工具链、依赖闭包与模块包指纹

- **工具链锁定**（`toolchain.lock.json`）：`moonc v0.10.22+124d61d05`（`2026-11-19`）、`moon 0.1.20261119 (738607b)`、`moonrun 0.1.20261119 (738607b)`。
- **依赖闭包**（`dependencies.lock.json`，已通过 `scripts/verify_dependencies.py` 逐归档与源码树校验）：
  - `moonbitstack/mooncrypt@0.4.5`（Apache-2.0，`0f92531d4eb54449df999efba856802759c0737dc17de22884caa0cd7897f5bb`）
  - `moonbitstack/moonbase@0.4.2`（Apache-2.0，`6dcdd67b5d560ab6ead572dabd29ccb715770dd7278ede56ae369607258e8bea`）
  - `moonbitstack/moondate@0.1.0`（Apache-2.0，`6eb270f866f17668d3494a321d048112e5a60208fc92df0bf86a2bb3d9c6565d5`）
  - `moonbitstack/moonrand@0.1.0`（Apache-2.0，`dca800751da31069b590ec74bc44f7d45fdddfd5f78d434da9ad82fc9c605d43`）
- **实验特性与许可**：根包 `YKDshaxing/moonlibsync` 与 `YKDshaxing/moonlibsync/crypto` 保持零 `allow-experimental-packages`；仓库许可为 **LGPL-2.1-or-later**，完整第三方声明保留于 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) 与 [SOURCES.md](../SOURCES.md)。
- **Mooncakes 发布结果**（`moon publish` 退出 `0`，服务器响应 `200 OK`）：
  - 包页面：[Mooncakes `YKDshaxing/moonlibsync@0.7.0`](https://mooncakes.io/docs/YKDshaxing/moonlibsync@0.7.0)
  - 公开清单 JSON：[manifest API](https://mooncakes.io/api/v0/manifest/YKDshaxing/moonlibsync@0.7.0)（`build_status: "success"`、`yanked: false`、`created_at: 2026-11-23T05:41:39.493776+00:00`，即北京时间 `2026-11-23 13:41:39.493776`）
  - 正式包归档 `YKDshaxing-moonlibsync-0.7.0.zip`：**`344` 个文件成员**、**`862,006` 字节**、SHA-256 `755bffbc2112df066f450d882af972626299fca315736b09f60fee1fcae5c816`（与 `_build/release-0.7.0/windows/audit.json` 及 `git_blob_byte_identity_verified: true` 完全一致）。

---

## 二、同 SHA (`79b96b7`) 自动化 CI 与交付产物

| 交付链路 | 运行 / 地址 | 结果 | 说明 |
| --- | --- | --- | --- |
| **Core, Examples, CLI & Interop (`main`)** | [GitHub Actions run 45119294836](https://github.com/YKDshaxing/moonlibsync/actions/runs/45119294836) | `success` | `reference`（Linux `librsync v2.3.4` 互操作）、`windows-latest`、`ubuntu-24.04` 三任务全部通过 |
| **Core, Examples, CLI & Interop (`v0.7.0`)** | [GitHub Actions run 45119304641](https://github.com/YKDshaxing/moonlibsync/actions/runs/45119304641) | `success` | 与 `v0.7.0` tag 同源 `79b96b7` 三任务全部通过 |
| **Release Native CLI (`v0.7.0`)** | [GitHub Actions run 45119304653](https://github.com/YKDshaxing/moonlibsync/actions/runs/45119304653) / [Release v0.7.0](https://github.com/YKDshaxing/moonlibsync/releases/tag/v0.7.0) | `success` | 产出并校验 `moonlibsync-linux-x86_64`（`4,789,608` B）、`moonlibsync-windows-x86_64.exe`（`3,148,800` B）、`SHA256SUMS.txt`（`188` B） |
| **Deploy Web Demo to GitHub Pages** | [GitHub Actions run 45119294853](https://github.com/YKDshaxing/moonlibsync/actions/runs/45119294853) / [Live Web Studio](https://ykdshaxing.github.io/moonlibsync/) | `success` | 构建并发布 37 导出纯 JS Web Studio `0.7.0`，在线访问返回 `HTTP 200` |
| **Mooncakes 官方文档构建** | [mooncakes.io `0.7.0`](https://mooncakes.io/docs/YKDshaxing/moonlibsync@0.7.0) | `success` | 根包、`compress`、`crypto` 等子包与 `0.7.0` 新增公开符号完整生成 |

---

## 三、双平台公开注册表消费验收（`--registry`）

两端均从干净仓库外临时目录、零本地 `moon.work`/路径/Git 替换、初始空 `.mooncakes` 缓存执行 `scripts/release_check.py --registry`：

- **Windows 11 / NTFS**（`_build/release-0.7.0/windows/registry-report.json`）：
  - 状态：`published-and-consumer-verified`
  - 公开下载归档：`862,006` 字节，SHA-256 `755bffbc2112df066f450d882af972626299fca315736b09f60fee1fcae5c816`，与发布包逐字节一致，344 成员无增删改；无本地替换消费端（Native / JS / Wasm-GC，含 Stage A 与 Stage B）及注册表下载源码 CLI 全部通过。
- **WSL2 Linux / ext4**（`_build/release-0.7.0/linux/registry-report.json`，工具链 `.toolchain/linux` `0.10.22+124d61d05`）：
  - 状态：`published-and-consumer-verified`
  - 公开下载归档同样为 `862,006` 字节，SHA-256 `755bffbc2112df066f450d882af972626299fca315736b09f60fee1fcae5c816`（本地 Linux 重新打包的审计容器 zip 哈希为 `09d4c7fba3112d053c6810be5f9afac2571d28d7617a28dbc528d31fd2d5712a`，344 个解压成员内容逐字节一致）；三目标消费及源码 CLI 全部通过。

---

## 四、已核实的 `0.7.0` 测试矩阵与红队加固摘要

- **核心库、压缩与密码学三目标（`native` / `js` / `wasm-gc`）**：
  - 根核心库 `YKDshaxing/moonlibsync`：**`252` / `252` × 3 目标**
  - 有界压缩子包 `YKDshaxing/moonlibsync/compress`：**`13` / `13` × 3 目标**
  - 零 IO 密码学子包 `YKDshaxing/moonlibsync/crypto`：**`20` / `20` × 3 目标**
- **示例、CLI、SDK 与互操作**：
  - 6 个 MoonBit 公开示例 × 3 目标、`scripts/check_prepared_interface.py`（12 次编译期封装检查）与 `scripts/native_probe.py` 全部通过（`python scripts/check.py`）。
  - Native CLI `cmd/moonlibsync`：**`57` 项 Native 单元测试** + **784 项 Windows/NTFS 集成用例**（[cli-smoke.ps1](../scripts/cli-smoke.ps1)） + **808 项 Linux/ext4 集成用例（`0 unsupported`）**（[cli-smoke.sh](../scripts/cli-smoke.sh)）。
  - 外部 `librsync v2.3.4` 互操作（Linux CI `reference` 任务）：**274 对输入 / 496 参数组合 / 3,968 次恢复**；固定夹具 `scripts/verify_fixtures.py`：**16 用例 / 64 文件 / 29 opcode 向量**；5 组正反失败门禁 `scripts/failure_gates.py` 与 `tests/release`（10 项）/ `tests/interop`（6 项）全部通过。
  - Web Studio & JS/TS SDK：`node examples/web-demo/test-node.mjs`（`WEB_DEMO_OK ... exports=37 verified=true`）、`PAGES_RELEASE_SMOKE_OK exports=37`、`node js/test-sdk.mjs`（`JS_SDK_OK`）、`js/index.d.ts` **0 个 `any` 类型**，以及本地暂存发布包 Chromium 实测 5 大卡片 / 弹窗与中英文切换（`0` console errors、`0` page errors）。
- **红队对抗加固要点**（详见 [CHANGELOG.md](../CHANGELOG.md#L27-L32) 与 [SECURITY.md](../SECURITY.md)）：
  - Core：`apply_range_fetch` 强制 `max_instructions`/`max_ranges`/`max_block_bytes` 与严格递增不相交区间；`plan_dir_metadata` 修复存活/可执行父目录误删并补齐大小写折叠冲突检测；扩展 Windows 保留文件名校验（`COM0`/`LPT0`、尾随空格、上标数字）。
  - Crypto：`TrustKeyring` 限额（`<= 64` 受信任公钥、`<= 256` 吊销 ID）与单趟 O(K + S) 仲裁验签；X25519 公钥强制 RFC 7748 规范编码（MSB 为 0 且 `u < p`）；`seal_envelope` 拒绝全零内容密钥并防护 `Int32` 容量上溢。
  - CLI：禁止 CWD 文件遮蔽 64-hex 字面量公钥；修复 `--exclude` 将仅含被排除文件的目录误判为空目录；POSIX `--meta` 在加权与权限读写前复检常规文件并限定 `0o700` 且与归档清单交叉校验；`fetch-sync` 强制 `http(s)` 非空主机、拒绝非 `identity` `Content-Encoding`、强制 `206` 规范 `Content-Range`、按 `min(max_new_bytes, max_output_bytes)` 先验限流并施加 `60 s` HTTP 超时；Zsh 补全使用 `compdef` 可用性守卫。
  - Web Studio / SDK：> 1 MiB `.zlib` 检测绕开 JSON 大小上限并支持 `0x78 0x5e` 错误保留与 `moonlibsync-range-plan` 识别；CORS Range 拉取禁止 `206` 缺 `Content-Range` 时误判 `targetLength = 1`，施加 `64 MiB` 上限并用远端 `.sig` 逐块重算校验；修复 CLI 命令提示为 `moonlibsync fetch-sync`、进度条 100% 对齐、Quorum 错误清理及中英文切换保留文件元数据；SDK 统一小写 hex 返回并在 CSPRNG 失败时 fail-closed 报错。

---

## 五、显式边界与非承诺声明

1. **JS/TS SDK 分发范围**：`js/`（`@ykdshaxing/moonlibsync@0.7.0`）为仓库内随附的零运行时依赖 ESM/TypeScript SDK，**尚未独立发布至 npm registry**，未声明 npm 注册表安装。
2. **基准数据归属**：[docs/benchmarks.md](benchmarks.md) 与 [docs/benchmarks-prepared.md](benchmarks-prepared.md) 仍为历史 `0.1.0` 阶段（`Commit 15` / `Commit 20`，`moonc 0.10.20`）Linux Native 有限对比实测，不代表或冒充 `0.7.0` 的重测性能。
3. **HTTP `Range` 测试边界**：`fetch-sync` 与 Web Studio Live CORS 逻辑已在本地回环 HTTP 测试服务器及浏览器模拟器/逻辑测试中充分验证，未声称对任意第三方公网 CDN 的实测网络吞吐。
4. **`--meta` 签名边界与内存模型**：CLI `--verify-sig` / `--verify-bundle` 覆盖 `.mbundle` / `.mbundle.gz` 或目标载荷字节，`--meta` 伴随文件位于该摘要之外（如需防篡改请单独签名）；`Limits` / `DirLimits` / `SealLimits` 为逻辑资源上限，不构成进程级峰值 RSS 或硬件 OOM 恢复保证。
