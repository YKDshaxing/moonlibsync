# MoonLibSync

开发中的 MoonBit 纯字节库，目标是兼容指定 librsync/rdiff 文件格式。首版计划采用全量字节缓冲 API，并提供 Native 单文件 CLI。

模块：`YKDshaxing/moonlibsync`；仓库归属：[`YKDshaxing/moonlibsync`](https://github.com/YKDshaxing/moonlibsync)。元数据版本 `0.1.0` 是开发目标，**尚未发布**，不表示版本已预留或已获得 Mooncakes 发布权限。

当前只实现 Commit 1 的工程基础：10 类错误声明、Limits 草案及配置校验、固定摘要依赖的向量探针、独立 Native 文件接口探针和最小 CI 配置。**signature、delta、patch 均未实现**，没有返回占位成功结果的接口。

文件格式参考固定为 librsync v2.3.4，提交 `e364852674780e43d578e4239128ff7014190ed3`。本阶段没有构建 rdiff、生成离线互操作夹具或验证互操作。项目不主张 MoonBit 的远端签名差分领域为空白。网络传输、目录同步、流式 API 和其他签名 profile 不在首版范围。

## 已验证版本与运行

本地 Windows 与 Ubuntu 24.04 WSL2 已验证编译器为 `moonc v0.10.20+65efd5b93 (2026-11-05)`，moon/moonrun 为 `0.1.20261104 (940aa18 2026-11-04)`。这不构成支持所有 `0.10.16` 以上版本的声明。Windows 已验证 Node.js `v24.18.0` 和 MSVC x64 `19.44.35229`；Linux 已验证 Node.js `v22.23.2` 和 GCC `13.3.0`。两环境的三目标检查和探针均通过，逐项证据与云端状态见 [docs/probes.md](docs/probes.md)。

需要 Git、Python 3.12+，以及 Native 所需的 C/C++ 工具；Windows 使用含 Windows SDK 的 Visual Studio C++ Build Tools。构建系统会发现 MSVC，MinGW 的存在不替代 MSVC 验证。

Windows PowerShell：

```powershell
python scripts/install_toolchain.py
if ($LASTEXITCODE -ne 0) { throw 'Toolchain installation failed' }
$env:MOON_HOME = (Resolve-Path '.toolchain/selected').Path
$env:PATH = "$env:MOON_HOME\bin;$env:PATH"
python scripts/check.py
if ($LASTEXITCODE -ne 0) { throw 'Checks failed' }
./scripts/native_probe.ps1
```

Linux Bash：

```bash
python3 scripts/install_toolchain.py
export MOON_HOME="$PWD/.toolchain/selected"
export PATH="$MOON_HOME/bin:$PATH"
python3 scripts/check.py
```

安装仅写入本项目被忽略的 `.toolchain`，不替换系统默认工具链或持久修改 PATH。`toolchain.lock.json` 固定版本、Windows/Linux 工具链和配套 core 压缩包 SHA-256；脚本从官方版本化地址获取并校验，不以 `latest` 安装。

当前工具链使用 `moon.mod` / `moon.pkg`，没有创建 JSON 旧配置。它未生成依赖解析锁文件；`.mooncakes/.moon-lock` 是空互斥锁文件。项目维护的 `dependencies.lock.json` 配合显式版本声明，核验全部依赖闭包的版本、压缩包 SHA-256 和解包源码；它不是 Moon 原生生成的锁文件。

## 摘要探针

采用 `moonbitstack/mooncrypt@0.4.5` 的 `hash/blake2` 包，通过 `hash(input, kind=Blake2b, len=32)` 将输出长度参数设为 32，再取 `strong_sum_len` 的前 1–32 字节。探针同时排除 BLAKE2s-256 和截断 BLAKE2b-512。这只确定后续实现的摘要路线；尚未添加核心摘要 API 或签名格式。

```powershell
moon run probes/digest --target native
moon run probes/digest --target js
moon run probes/digest --target wasm-gc
```

预期向量来自独立的 Python `hashlib.blake2b(..., digest_size=32)`，可用 `python scripts/reference_vectors.py` 复核。记录包含原始输入、预期输出和各目标实际输出，见 [探针记录](docs/probes.md)。

## Limits 草案

所有字段使用 `Int64`，允许范围为 `0..2147483647`，只有 `max_block_bytes` 必须为正。显式校验后才能在后续步骤考虑转换为集合索引；当前不进行缩窄转换。超出 `Int64` 表示范围的值不属于该 API 的可构造输入，超出共同 32 位集合上界的可表示 `Int64` 则返回 `InvalidOptions(字段名)`。

| 字段 | 单位 | 默认值 |
| --- | --- | --- |
| `max_old_bytes` | 字节 | 64 MiB |
| `max_new_bytes` | 字节 | 64 MiB |
| `max_signature_bytes` | 字节 | 16 MiB |
| `max_signature_records` | 条记录 | 1,000,000 |
| `max_block_bytes` | 字节，至少 1 | 1 MiB |
| `max_delta_bytes` | 字节 | 80 MiB |
| `max_output_bytes` | 字节 | 64 MiB |
| `max_instructions` | 条指令 | 1,000,000 |
| `max_match_work` | 工作量单位，计量规则待定 | 256 × 1024 × 1024 |

零预算允许表达“不能消费此类资源”，不表示未来任意空格式都能通过。当前仅做逐字段配置校验，未固定跨字段关系，也**没有约束算法分配、指令执行或匹配工作量**。

`SyncError` 包括 `InvalidOptions`、`UnsupportedSignatureProfile`、`TruncatedInput`、`InvalidSignature`、`InvalidDelta`、`InvalidOpcode`、`IntegerOutOfRange`、`CopyOutOfBounds`、`TrailingData`、`LimitExceeded`。只有当前实际使用的 `InvalidOptions(String)` 携带字段名，其余分类不冻结未来解析器的详细载荷。`Limits::validate()` 使用 MoonBit 的 `raise SyncError` 返回明确校验错误。

## CI 与许可证

[CI 配置](.github/workflows/ci.yml) 在 Windows 和 Ubuntu 上执行格式、依赖完整性、接口一致性、Native/JS/Wasm-GC check/build/test、摘要向量和 Native 基础文件接口探针。脚本在任何自动写接口的检查之前保存接口快照；生成后比较差异，不把自动覆盖视为一致。云端执行状态与本地结果分别记录，不以 CI 配置文件存在代替运行证据。

原创代码采用 `LGPL-2.1-or-later`，完整文本见 [COPYING.LESSER](COPYING.LESSER) 和 [COPYING](COPYING)。依赖保留 Apache-2.0 等上游声明，详见 [SOURCES.md](SOURCES.md) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。本阶段不打包或发布二进制。
