<div align="center">

# MoonLibSync

**纯 MoonBit 实现的 librsync 兼容二进制差分库与 Native 单文件 CLI**

<p>
  <a href="README.md"><img src="https://img.shields.io/badge/English-Switch%20to%20English-4b5563?style=for-the-badge" alt="English"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-%E5%BD%93%E5%89%8D%E8%AF%AD%E8%A8%80-2563eb?style=for-the-badge" alt="简体中文"></a>
</p>

<p>
  <a href="https://github.com/YKDshaxing/moonlibsync/actions/workflows/ci.yml"><img src="https://github.com/YKDshaxing/moonlibsync/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://ykdshaxing.github.io/moonlibsync/"><img src="https://img.shields.io/badge/Live%20Demo-GitHub%20Pages-0f766e" alt="在线 Web Demo"></a>
  <a href="https://mooncakes.io/docs/YKDshaxing/moonlibsync"><img src="https://img.shields.io/badge/mooncakes-YKDshaxing%2Fmoonlibsync-7c3aed" alt="Mooncakes"></a>
  <a href="https://github.com/YKDshaxing/moonlibsync/releases"><img src="https://img.shields.io/badge/version-0.7.0-0ea5e9" alt="Version 0.7.0"></a>
  <img src="https://img.shields.io/badge/targets-Native%20%7C%20JS%20%7C%20Wasm--GC-10b981" alt="Targets">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-LGPL--2.1--or--later-orange" alt="License"></a>
</p>

</div>

---

**MoonLibSync** 使用纯 MoonBit 实现标准 [`librsync`](https://github.com/librsync/librsync)（`v2.3.4`）二进制差分协议，**零 C FFI 依赖**，核心库原生支持 **Native / JavaScript / Wasm-GC** 三目标编译。在完全兼容标准 `signature` / `delta` / `patch` 字节流的基础上，提供 O(1) 零记录分配元数据检查、可复用签名索引、显式自动块长、SHA-256 完整性清单、Delta/Full 更新负载规划，以及具备有界读取与无覆盖原子提交保障的 Native 单文件 CLI。

## 核心能力

| 层次 | 公开入口 | 用途说明 |
| --- | --- | --- |
| **标准字节差分、双 Profile 与合成** | `signature` / `signature_with_profile` / `delta` / `patch` / `compose_deltas` / `compose_delta_chain` / `create_reverse_delta*` | 与 `librsync` 双 BLAKE2 Profile 互操作（`0x72730147` RK+BLAKE2b 与 `0x72730137` Rollsum+BLAKE2b、delta `0x72730236`）；O(1) 弱校验开放定址表、`v1→v2 + v2→v3 ⇒ v1→v3` 无损补丁链合成与反向回滚增量 |
| **HTTP Range (`zsync`) 静态增量拉取** | `plan_range_fetch` / `apply_range_fetch` / `encode_range_plan_json` / `RangeFetchOptions` | 纯零 IO 静态 CDN / S3 / Nginx 增量拉取规划：用远端新 `.sig` 对本地旧文件滑窗匹配并合并小间隙生成最小 RFC 9110 `bytes=` 区间请求（`fetch-sync` / `range-plan`） |
| **零 IO 流式与 Sans-IO 解码** | `SignatureHasher` / `DeltaScanner` / `PatchApplier` / `PatchDecoder` / `Sha256Hasher` | 纯核心分块状态机 + Sans-IO 步进解码器（`PatchStep`）与流式 SHA-256，同时适配同步 `Bytes`、Native `async/fs` 与浏览器 JS/Web Worker |
| **目录快照、并发、元数据与归档** | `DirSnapshot` / `plan_dir_sync_with_options` / `DirBundleManifest` / `DirVerifyReport` / `DirMetadata` / `plan_dir_metadata` / `BundleArchiveDecoder` | Schema 3 确定性快照、`--jobs N` 有界并发扫描打包（输出字节严格一致）、空目录与 `+x` 可执行位元数据、`--detect-moves` 0 字节 `CopyFromBasis`、完整性巡检及 `.mbundle`/`.mbundle.gz` |
| **Ed25519 多签密钥环与 X25519 / AEAD** | `YKDshaxing/moonlibsync/crypto`：`keypair_from_seed` / `sign_*` / `verify_quorum_*` / `seal_*` / `x25519_keypair_from_secret` / `seal_envelope` / `unseal_envelope` | 纯零 IO Ed25519 签名与 `M-of-N` 阈值 Keyring 吊销验签、`MLSENC01` ChaCha20-Poly1305/Argon2id 流式加密，以及 `MLSENC02` 多接收方 X25519 + HKDF-SHA256 公钥信封加密 |
| **独立有界 Gzip / Zlib / Raw DEFLATE** | `YKDshaxing/moonlibsync/compress`：`compress_gzip` / `decompress_gzip` / `compress_zlib` / `decompress_zlib` / `compress_deflate` / `decompress_deflate` / `{Gzip,Zlib,Deflate}{Encoder,Decoder}` | 纯零 IO 跨三目标单流 RFC 1952 Gzip、RFC 1950 Zlib 与 RFC 1951 Raw DEFLATE 封装，内置防解压炸弹与拒绝尾随数据 |
| **检查与预检** | `inspect_signature` / `inspect_delta` / `check_patch` | O(1) 零记录分配签名头校验、delta 统计以及基于长度的 COPY 范围预检 |
| **可复用签名索引** | `prepare_signature` / `PreparedSignature::{delta, summary, plan_update}` | 一次解析建索引，跨多个目标复用；每次调用独立重检 `Limits` 并拥有独立工作预算 |
| **显式自动块长** | `recommend_block_len` / `signature --block-size auto` | 纯整数 `policy v1` 策略（目标约 512 条记录、2 次幂向上舍入并受当前预算约束） |
| **格式外完整性清单** | `create/parse/encode_basis_info`、`create/parse/encode_update_manifest`、`verified_patch` | 严格有界 JSON（schema 1），使用 SHA-256 绑定 `OLD` / `SIG` / `DELTA` / `RESULT`，校验通过后才返回或提交输出 |
| **更新负载规划** | `plan_update`、`create/parse/encode_transfer_manifest`、`apply_update` | schema 2 自动在 `Delta` 与 `Full` 间择优（仅在实际 delta 严格更小且满足 `min_savings_bytes` 时选 `Delta`） |
| **Native 单文件 CLI** | `cmd/moonlibsync`（35 条子命令） | 全链路 `--streaming` 64 KiB 管线、`fetch-sync`/`range-plan`（HTTP `Range`）、`compose-delta`、`--jobs N`、`--meta-out`/`--meta`、`--format gzip|zlib|deflate`、`x25519-keygen`、`keyring-init`/`sign-combine`/`verify-quorum`、`seal --recipient`、`--verify-bundle`、`completions` 与原子提交 |
| **零依赖 JS/TS SDK 与 Web 工作台** | `js/`（`@ykdshaxing/moonlibsync@0.7.0`）与 `examples/web-demo/` | 零运行依赖 Node.js + 浏览器通用 ES Module（37 项核心导出 / 33 项类型方法，零 `any` `.d.ts`）；5 标签页 Web Worker 静态工作台（HTTP `Range` 增量拉取、Delta 链合成压扁、Literal Hex 透视热力图、`.mbundle.gz` 打包解包、Gzip/Zlib + Ed25519 多签 + X25519/AEAD 实验室） |

## 快速开始

### 1. 通过 Mooncakes 引入依赖

在 `moon.mod` 中声明依赖（已发布至 [Mooncakes](https://mooncakes.io/docs/YKDshaxing/moonlibsync)）：

```moonbit
// moon.mod
import {
  "YKDshaxing/moonlibsync@0.7.0",
}
```

在 `moon.pkg` 中导入根包：

```moonbit
// moon.pkg
import {
  "YKDshaxing/moonlibsync" @lib,
}
```

### 2. 最小可运行代码

```moonbit
fn sync_demo() -> Unit raise {
  let limits = @lib.Limits::default()
  let old = Bytes::makei(512, i => (0x10 + i / 64).to_byte())
  let new_bytes = old[0:256].to_owned() + b"\x00\x80\xff" + old[256:].to_owned()

  // 接收端：根据本地旧文件 OLD 生成签名
  let sig = @lib.signature(old, { block_len: 64L, strong_sum_len: 32L, }, limits)

  // 发送端：仅持有远端 SIG 与新文件 NEW（不需要 OLD）
  let prepared = @lib.prepare_signature(sig, limits)
  let plan = prepared.plan_update(new_bytes, @lib.UpdateOptions::default(), limits)

  // 接收端：将增量应用到本地 OLD 恢复出 NEW
  match plan.payload {
    Delta(delta_bytes) => assert_eq(@lib.patch(old, delta_bytes, limits), new_bytes)
    Full(full_bytes) => assert_eq(full_bytes, new_bytes)
  }
}
```

更多三目标（`native` / `js` / `wasm-gc`）可运行示例：
- [examples/basic](examples/basic/main.mbt) — 基础 `signature` / `delta` / `patch`
- [examples/prepared](examples/prepared/main.mbt) — `PreparedSignature` 跨目标索引复用
- [examples/verified](examples/verified/main.mbt) — schema 1 完整性清单与 `verified_patch`
- [examples/auto](examples/auto/main.mbt) — 显式自动块长 `recommend_block_len`
- [examples/transfer](examples/transfer/main.mbt) — schema 2 `Delta` / `Full` 更新规划与应用
- [examples/streaming](examples/streaming/main.mbt) — 零 IO 分块流式 `SignatureHasher` / `DeltaScanner` / `PatchApplier`（含零依赖 Node.js 运行脚本：`node examples/streaming/run-node.mjs`）
- [examples/web-demo](examples/web-demo/index.html) — 5 标签页零后端静态浏览器 Web Worker 工作台 + 37 导出 JS ES 模块（`node examples/web-demo/test-node.mjs --rebuild`）：HTTP `Range` 增量拉取模拟与实测、Delta 链合成压扁、Literal Hex 透视热力图、多块长基准图、独立角色 rdiff、通用产物剖析、`.mbundle.gz` 打包解包 + `--detect-moves` 与 Gzip/Zlib/Ed25519 多签/X25519/AEAD 安全实验室
- [js/README.md](js/README.md) — 独立零运行时依赖 JS/TS ES Module SDK（`@ykdshaxing/moonlibsync`，`node js/test-sdk.mjs` 验证）

## Native 单文件 CLI

使用锁定工具链与本机 C/C++ 编译器（Windows MSVC Build Tools / Linux GCC）源码构建：

```bash
moon build cmd/moonlibsync --target native --release
```

> 说明：Linux 下 `moon build --target native` 生成的本机 ELF 产物默认保留 `.exe` 后缀（`_build/native/release/build/cmd/moonlibsync/moonlibsync.exe`）；GitHub Releases 打包产物会将 Linux 文件名规范化为 `moonlibsync-linux-x86_64`。

### 基础差分与只读检查

```bash
# 1. 生成签名（默认 2048/32，也支持显式 --block-size auto）
moonlibsync signature old.bin old.sig --block-size 64 --sum-size 32
moonlibsync signature old.bin auto.sig --block-size auto

# 2. 发送端仅凭 SIG + NEW 生成增量
moonlibsync delta old.sig new.bin update.delta

# 3. 接收端将增量应用到 OLD 生成 OUT（绝不覆盖已有文件）
moonlibsync patch old.bin update.delta restored.bin

# 4. 只读检查与补丁范围预检（支持人类可读文本或 --json）
moonlibsync inspect-signature old.sig --json
moonlibsync inspect-delta update.delta --json
moonlibsync check-patch old.bin update.delta --json
moonlibsync inspect-manifest manifest.json --json

# 5. 全链路流式 64 KiB 大文件管线（突破 64 MiB + --progress 实时进度条 + Gzip 二次压缩）
moonlibsync signature large-old.bin large.sig --streaming --progress --block-size auto --max-old-bytes 200000000
moonlibsync basis-info large-old.bin large.sig basis.json --streaming --max-old-bytes 200000000
moonlibsync delta large.sig large-new.bin large.delta --streaming --progress --max-new-bytes 200000000 --max-output-bytes 200000000 --max-match-work 2000000000
moonlibsync compress large.delta large.delta.gz --streaming --progress --max-new-bytes 200000000 --max-output-bytes 200000000
moonlibsync decompress large.delta.gz large.delta.raw --streaming --progress --max-delta-bytes 200000000 --max-output-bytes 200000000
moonlibsync make-transfer-manifest basis.json large.sig large-new.bin large.delta.raw transfer.json --streaming --max-old-bytes 200000000 --max-new-bytes 200000000 --max-delta-bytes 200000000 --max-output-bytes 200000000
moonlibsync apply-update large.delta.raw transfer.json restored.bin --basis large-old.bin --streaming --progress --max-old-bytes 200000000 --max-delta-bytes 200000000 --max-output-bytes 200000000

# 6. 端到端签名 + AEAD 加密 + 移动 0 字节复用 + 自动回滚目录分发闭环（0.6.0）
moonlibsync keygen publisher.priv publisher.pub
moonlibsync dir-snapshot ./v1 v1.snapshot.json --exclude-from .moonlibsyncignore
moonlibsync dir-signatures ./v1 v1.snapshot.json ./v1-sigs --profile rollsum-blake2 --block-size auto --streaming --progress
moonlibsync dir-pack v1.snapshot.json ./v1-sigs ./v2 ./v1-to-v2.mbundle.gz --detect-moves --archive --gzip --exclude-from .moonlibsyncignore --streaming --progress
moonlibsync inspect-bundle ./v1-to-v2.mbundle.gz --gzip --json
moonlibsync sign ./v1-to-v2.mbundle.gz publisher.priv ./v1-to-v2.msig.json --streaming
moonlibsync seal ./v1-to-v2.mbundle.gz ./v1-to-v2.mbundle.gz.menc --passphrase-file pass.txt --streaming --progress
moonlibsync unseal ./v1-to-v2.mbundle.gz.menc ./unsealed.mbundle.gz --passphrase-file pass.txt --streaming --progress
moonlibsync dir-apply ./v1 ./unsealed.mbundle.gz ./v2-restored --archive --gzip --verify-sig ./v1-to-v2.msig.json --verify-key publisher.pub --save-rollback ./rollback-v2-to-v1.mbundle.gz --streaming --progress
moonlibsync dir-verify ./v2-restored v2.snapshot.json --json --exclude-from .moonlibsyncignore
moonlibsync completions powershell > moonlibsync-completions.ps1

# 7. 静态 HTTP Range (`zsync`) 增量拉取、Delta 链合成、X25519 多接收方信封与 M-of-N 多签（0.7.0）
moonlibsync range-plan release-v2.sig 134217728 release-v1.bin --merge-gap 4096 --json
moonlibsync fetch-sync https://cdn.example.com/release-v2.bin --basis release-v1.bin --sig-url https://cdn.example.com/release-v2.sig --verify-bundle release-v2.sigbundle.json --keyring org.keyring.json -o release-v2.bin --json
moonlibsync compose-delta v1-to-v2.delta v2-to-v3.delta -o v1-to-v3.delta --json
moonlibsync x25519-keygen -o alice.x25519.sec --pub-out alice.x25519.pub
moonlibsync x25519-keygen -o bob.x25519.sec --pub-out bob.x25519.pub
moonlibsync seal payload.tar --recipient alice.x25519.pub --recipient bob.x25519.pub -o payload.menv
moonlibsync unseal payload.menv --recipient-key bob.x25519.sec -o payload.restored.tar
moonlibsync keyring-init --trust pub1.pub --trust pub2.pub --trust pub3.pub --quorum 2 -o org.keyring.json
moonlibsync sign-combine sig1.json sig2.json -o bundle.sig.json
moonlibsync verify-quorum artifact.bin bundle.sig.json --keyring org.keyring.json --json
moonlibsync dir-snapshot ./v2 v2.snap.json --jobs 4 --meta-out v2.meta.json
moonlibsync compress artifact.bin artifact.zlib --format zlib --streaming
```

### 完整性校验与传输规划流程

```bash
# Schema 1：带 SHA-256 校验的补丁应用
moonlibsync basis-info old.bin old.sig basis.json
moonlibsync make-manifest basis.json old.sig new.bin update.delta manifest.json
moonlibsync patch-verified old.bin update.delta manifest.json restored.bin

# Schema 2：自动选择 Delta 或 Full 传输负载
moonlibsync make-transfer-manifest basis.json old.sig new.bin update.delta transfer.json --min-savings 64
moonlibsync apply-update update.delta transfer.json restored.bin --basis old.bin
```

**退出码**：`0` 成功 / `--help` / `--version`，`2` 用法错误，`1` 文件、预算或核心错误。完整参数规则、JSON Schema 与原子提交边界见 [docs/cli.md](docs/cli.md)。

## 开发构建与自动化验证

本项目在 [toolchain.lock.json](toolchain.lock.json) 固定工具链（`moonc v0.10.22+124d61d05`、`moon 0.1.20261119`），在 [dependencies.lock.json](dependencies.lock.json) 固定依赖闭包（`mooncrypt 0.4.5`）。安装脚本仅写入仓库内 `.toolchain/`，不改动全局工具链。

<details>
<summary>Windows PowerShell 完整检查命令</summary>

```powershell
python scripts/install_toolchain.py
if ($LASTEXITCODE -ne 0) { throw 'Toolchain installation failed' }
$env:MOON_HOME = (Resolve-Path '.toolchain/selected').Path
$env:PATH = "$env:MOON_HOME\bin;$env:PATH"

python scripts/check.py            # 格式、依赖、252 项库 + 13 项 compress + 20 项 crypto 测试 × 三目标、6 示例、web-demo ESM、JS/TS SDK、接口守卫
python scripts/verify_fixtures.py  # 参考夹具与 opcode 向量完整性校验
python scripts/failure_gates.py    # 隔离损坏与断言失败传播门禁
./scripts/cli-smoke.ps1            # 57 项 Native 辅助测试 + 784 项 Windows CLI 集成用例（Linux/ext4 为 808 项）
node examples/streaming/run-node.mjs --rebuild
node examples/web-demo/test-node.mjs --rebuild
node js/test-sdk.mjs
python scripts/release_check.py --clean
```

</details>

<details>
<summary>Linux Bash 完整检查与 librsync v2.3.4 双向互操作</summary>

```bash
set -euo pipefail
python3 scripts/install_toolchain.py
export MOON_HOME="$PWD/.toolchain/selected"
export PATH="$MOON_HOME/bin:$PATH"

python3 scripts/check.py
python3 scripts/verify_fixtures.py
python3 scripts/failure_gates.py
bash scripts/cli-smoke.sh

# 与固定上游 librsync v2.3.4 双向互操作（需先安装 build-essential cmake libpopt-dev）
bash scripts/rebuild-reference.sh
python3 scripts/consume_signature.py
python3 scripts/consume_delta.py
bash scripts/interop.sh            # 274 对输入、496 参数用例、3968 次恢复
python3 scripts/file_exchange.py
```

</details>

## 兼容范围与安全边界

- **标准协议支持**：完整支持现代 `librsync` 双 BLAKE2 Profile —— `RS_RK_BLAKE2_SIG_MAGIC`（`0x72730147`，默认 `2048/32`）与 `RS_BLAKE2_SIG_MAGIC`（`0x72730137` Rollsum + BLAKE2b）—— 以及标准 delta 全宽度指令（`0x72730236`，严格 `END` 校验且拒绝尾随数据）；遗留 MD4 Profile（`0x72730136`/`0x72730146`）返回 `UnsupportedSignatureProfile`。
- **全量缓冲与分块流式内存模型**：一次性入口工作在有界内存 `Bytes` 缓冲上（默认 `Limits` 上限：`OLD`/`NEW` 64 MiB、`SIG` 16 MiB、`DELTA` 80 MiB），而流式 `SignatureHasher` / `DeltaScanner` / `PatchApplier` / `PatchDecoder` / `BundleArchiveDecoder` / `GzipEncoder` / `GzipDecoder` / `SealEncoder` / `SealDecoder` 在分块处理期间维持有界内部暂存缓冲。预算为逻辑上限，不承诺进程级峰值 RSS 或 OOM 恢复，详见 [docs/resources.md](docs/resources.md)。
- **完整性、发布者认证与机密性**：标准 `delta` / `patch` 不认证旧文件身份；`verified_patch` / `apply_update` / `dir-apply` 校验 SHA-256 完整性，且 `YKDshaxing/moonlibsync/crypto` 提供可选 Ed25519 发布者数字签名（`sign`/`verify`/`--verify-sig`）与 `MLSENC01` 流式 ChaCha20-Poly1305/Argon2id 加密（`seal`/`unseal`）。详见 [SECURITY.md](SECURITY.md)。
- **文件系统边界**：CLI 无覆盖提交已验证 Windows/NTFS 与 Linux/ext4。WSL DrvFS（`/mnt/*`）不支持无覆盖 `renameat2` 时会明确失败并清理临时文件，不降级覆盖（WSL 下运行正向 CLI 烟雾测试请设置 `MOONLIBSYNC_CLI_TMP_PARENT=/tmp`）。

## 文档导航

- [CHANGELOG.md](CHANGELOG.md) — 版本变更记录（`0.7.0` / `0.6.1` / `0.6.0` / `0.5.0` / `0.4.0` / `0.3.2` / `0.3.1` / `0.3.0` / `0.2.0` / `0.1.0`）
- [js/README.md](js/README.md) — 零运行时依赖 Node.js & 浏览器 JS/TS SDK（`@ykdshaxing/moonlibsync`）
- [SECURITY.md](SECURITY.md) — 安全模型与漏洞报告流程
- [docs/design.md](docs/design.md) — 架构与公开 API 设计说明
- [docs/cli.md](docs/cli.md) — Native CLI 手册（`--streaming`、`dir-snapshot`/`dir-plan`、`--max-*`）、JSON Schema 与原子提交说明
- [docs/dir-sync.md](docs/dir-sync.md) — Schema 3 目录快照规范、POSIX 路径安全规则与 `DirLimits`
- [docs/compatibility.md](docs/compatibility.md) — 协议兼容性与各版本契约
- [docs/matching.md](docs/matching.md) — 开放定址弱校验索引、Pending Literal Run 与 `MatchWork` v2 计量
- [docs/resources.md](docs/resources.md) — `Limits`、`MatchWork` v2 与全量/流式内存模型
- [docs/auto-block.md](docs/auto-block.md) — 自动块长 `policy v1` 规则与数据量对照
- [docs/updates.md](docs/updates.md) — Delta/Full 规划与 schema 2 协议规范
- [docs/manifests.md](docs/manifests.md) — schema 1 完整性清单规范
- [docs/benchmarks.md](docs/benchmarks.md) 与 [docs/benchmarks-prepared.md](docs/benchmarks-prepared.md) — 有限进程级基准与索引复用实测
- [docs/release-0.3.0.md](docs/release-0.3.0.md) / [docs/release-0.2.0.md](docs/release-0.2.0.md) / [docs/release.md](docs/release.md) — 历史 Mooncakes 发布与双平台消费实证

## 许可证

采用 **LGPL-2.1-or-later** 开源许可。完整许可文本与上游来源归属见 [LICENSE](LICENSE)、[COPYING.LESSER](COPYING.LESSER)、[COPYING](COPYING)、[SOURCES.md](SOURCES.md) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
