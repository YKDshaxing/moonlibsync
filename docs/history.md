# Commit 1–13 阶段记录（历史快照）

以下保留 Commit 13 基线 README 的原文。所有“当前”“尚未”“待定”均属于对应段落的历史阶段，不是 Commit 14 的当前能力声明；阶段演进请按 Commit 编号阅读。当前入口以仓库根 README、资源契约和阶段验收表为准。原文的仓库相对链接已随文件移动调整；历史事实及阶段文字保持原样。

# MoonLibSync

开发中的 MoonBit 纯字节库，目标是兼容指定 librsync/rdiff 文件格式。采用全量字节缓冲 API，现提供 Windows／Linux Native 单文件 CLI，仍处于开发阶段。

模块：`YKDshaxing/moonlibsync`；仓库归属：[`YKDshaxing/moonlibsync`](https://github.com/YKDshaxing/moonlibsync)。元数据版本 `0.1.0` 是开发目标，**尚未发布**，不表示版本已预留或已获得 Mooncakes 发布权限。

当前已完成工程基础，以及 Commit 2 的受检大端 u32/u64 读写和内部签名结构解析。解析器检查头部、profile、记录对齐、无符号数值、名义块偏移及三项签名预算；所有新类型和函数均为内部使用，未新增公开解析 API。**目前已公开 signature、delta 和 patch**。Commit 10 的 delta 生成只接收远端签名与新文件，三项主操作均有可运行路径；完整互操作矩阵和发布验收仍未完成。

文件格式参考固定为 librsync v2.3.4，提交 `e364852674780e43d578e4239128ff7014190ed3`。Commit 1 阶段没有构建 rdiff、生成离线互操作夹具或验证互操作；后续证据按阶段记录于下文。项目不主张 MoonBit 的远端签名差分领域为空白。网络传输、目录同步、流式 API 和其他签名 profile 不在首版范围。

## 已验证版本与运行

已验证工具链固定为 `moonc v0.10.20+65efd5b93 (2026-11-05)`，moon/moonrun 为 `0.1.20261104 (940aa18 2026-11-04)`。这不构成支持所有 `0.10.16` 以上版本的声明。Commit 1 在本地 Windows 和 Ubuntu 24.04 WSL2 上验证过三个目标与探针：Windows 使用 Node.js `v24.18.0`、MSVC x64 `19.44.35229`，Linux 使用 Node.js `v22.23.2`、GCC `13.3.0`。保留其历史记录 [docs/probes.md](../docs/probes.md)，Commit 2 的格式策略、测试与执行证据单独记录于 [docs/signature-format.md](../docs/signature-format.md)。

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

采用 `moonbitstack/mooncrypt@0.4.5` 的 `hash/blake2` 包，通过 `hash(input, kind=Blake2b, len=32)` 将输出长度参数设为 32，再取 `strong_sum_len` 的前 1–32 字节。探针同时排除 BLAKE2s-256 和截断 BLAKE2b-512。内部解析器只读取签名中已有的摘要字节，不重算摘要；本节保留 Commit 1 依赖可行性探针；Commit 5 内部适配见文末，签名生成仍未实现。

```powershell
moon run probes/digest --target native
moon run probes/digest --target js
moon run probes/digest --target wasm-gc
```

预期向量来自独立的 Python `hashlib.blake2b(..., digest_size=32)`，可用 `python scripts/reference_vectors.py` 复核。记录包含原始输入、预期输出和各目标实际输出，见 [探针记录](../docs/probes.md)。

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

零预算允许表达“不能消费此类资源”，不表示任意空格式都能通过。内部签名解析入口先校验所有配置，再实际落实 `max_signature_bytes`、`max_signature_records`、`max_block_bytes`；零记录签名可在记录数预算为零时通过，但仍需合法头部、块长与足够的字节预算。其他字段尚未落实为旧/新文件、delta、恢复输出、指令执行或匹配工作量预算。

`SyncError` 包括 `InvalidOptions`、`UnsupportedSignatureProfile`、`TruncatedInput`、`InvalidSignature`、`InvalidDelta`、`InvalidOpcode`、`IntegerOutOfRange`、`CopyOutOfBounds`、`TrailingData`、`LimitExceeded`。只有 `InvalidOptions(String)` 携带字段名，本笔未改变公开错误声明。`Limits::validate()` 和内部解析器使用 MoonBit 的 `raise SyncError` 返回明确错误。

## 内部签名结构解析

只接受 RK/BLAKE2 profile `0x72730147`。MD4、BLAKE2 和 RK/MD4 三种已知其他 profile 返回 `UnsupportedSignatureProfile`；未知 magic 和 delta magic 返回 `InvalidSignature`。头部固定 12 字节，块长必须为正，强摘要长必须为 1–32；头部不足或尾部不足一条记录返回 `TruncatedInput`。

记录保持原顺序与重复项，弱校验以 UInt32 保留全部位；u64 wire 工具完整保留 UInt64。实现范围和项目预算分别报 `IntegerOutOfRange`、`LimitExceeded`，不会先窄化再比较。具体字段、错误优先级与手写向量覆盖见 [签名格式说明](../docs/signature-format.md)。

签名不包含 `basis_len`、每块真实长度、显式块偏移或整文件摘要。内部 `nominal_offset` 只是受检的块序号乘块长，不能据此推断真实旧文件长度或最后一块长度，也不能认证旧文件身份。当前没有签名生成、滚动校验、匹配或恢复能力。

## CI 与许可证

[CI 配置](../.github/workflows/ci.yml) 在 Windows 和 Ubuntu 上执行格式、依赖完整性、接口一致性、Native/JS/Wasm-GC check/build/test、摘要向量和 Native 基础文件接口探针。脚本在任何自动写接口的检查之前保存接口快照；生成后比较差异，不把自动覆盖视为一致。云端执行状态与本地结果分别记录，不以 CI 配置文件存在代替运行证据。

原创代码采用 `LGPL-2.1-or-later`，完整文本见 [COPYING.LESSER](../COPYING.LESSER) 和 [COPYING](../COPYING)。依赖保留 Apache-2.0 等上游声明，详见 [SOURCES.md](../SOURCES.md) 和 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。本阶段不打包或发布二进制。

Commit 3 建立固定 librsync v2.3.4 参考构建与16个自有输入用例的离线签名/delta夹具。普通检查核验 manifest 与字节搬运文件；三目标测试离线读取上游签名。独立 Linux CI 从源码重建、逐文件比较并拒绝损坏副本。见 [兼容性证据](../docs/compatibility.md)。上游自行恢复不等于 MoonBit 双向互操作通过。

## Commit 4 弱校验

新增内部 Rabin–Karp 标量状态及加入、批量更新、旋转、EOF缩短操作，详见 [Rabin–Karp说明](../docs/rabinkarp.md)。使用独立重算、固定上游向量及16例真实签名记录逐块验证；仅扩展old.bin离线字节搬运，正式夹具与manifest不变。Commit 4 时强摘要适配尚未实现，不能将历史探针结果当作 Commit 5 适配证据。

## Commit 5 强摘要适配

现已实现内部strong_sum入口：固定计算32字节BLAKE2b，再取1..32字节前缀，非法长度先拒绝。10组独立hashlib向量覆盖128字节压缩块边界，并逐块匹配原16例rdiff强摘要记录；详见 [强摘要说明](../docs/strongsum.md)。模块版本和锁不变，没有新增公开API，签名生成、匹配、delta、patch和双向互操作仍未实现。

## 公开 signature 调用（Commit 6）

客户端moon.pkg导入：

```moonbit
import { "YKDshaxing/moonlibsync" }
```

main.mbt：

```moonbit
fn main raise {
  let bytes = @moonlibsync.signature(
    b"abc",
    @moonlibsync.SignatureOptions::default(),
    @moonlibsync.Limits::default(),
  )
  println(bytes.length()) // 48
}
```

该调用已由公开黑盒测试编译执行。默认块长2048、强摘要前缀32；选项字段为Int64，块长必须正且可表示为Int32，摘要长1..32，零不代表自动选择。返回标准RK+BLAKE2签名，不是delta，签名自身不能恢复新文件。生成前实际检查max_old_bytes、max_block_bytes、max_signature_records、max_signature_bytes；空文件只输出12字节头，完整块不多出空尾块，短尾块不补零，格式不保存真实尾块长度。错误顺序及预算细节见[签名说明](../docs/signature-format.md)。

当前仅signature公开可调用；delta、patch、匹配索引与双向互操作仍待后续阶段。Commit 6本机已完成16例固定夹具和66个临时参数用例的完整上游签名比较及82次“MoonBit签名的上游消费验证”；其中delta/patch都是上游操作，不是MoonBit实现。历史各笔“未实现”描述保留其阶段归属。

## Commit 7 内部候选匹配

已增加仅从已验证签名建立的排序索引，按完整弱校验和原序号稳定定位，用一次强摘要确认候选。共享max_match_work预算覆盖索引分配/排序、查询、候选、摘要字节及比较，具体单位、错误和短尾块边界见[匹配说明](../docs/matching.md)。公开API仍只有signature；没有新文件扫描、COPY、delta或patch，不代表双向互操作完成。

## Commit 8 内部 Delta 指令编解码

内部编解码已覆盖直接 literal 1–64、四种扩展 literal 宽度和 16 种 COPY 参数宽度组合。编码逐参数选择最短形式，解析接受非最短形式，要求最终 END 且拒绝尾随数据。字节、指令及预期输出预算在对应存储增长前检查；COPY 保留 UInt64 参数。详见[Delta 格式说明](../docs/delta-format.md)。

原参考数据仍为 16 例、64 文件、12507 字节及原 manifest；新增 `tests/fixtures/opcodes/` 的 29 个手写向量，使用 1 个 JSON 数据文件及独立 manifest，分别核验。新增 7 项测试，共 58 项，16 个上游 delta 已离线解析并按指令语义重编码。公开接口不变；新文件扫描、公开 delta/patch、补丁执行、双向互操作及 0.1.0 发布仍未完成。历史段落保留对应阶段状态。

## Commit 9 公开补丁应用

公开入口 `patch(basis: Bytes, delta_bytes: Bytes, limits: Limits) -> Bytes raise SyncError` 只接收旧文件、标准 delta 和 Limits，不需要签名或预期新文件，不访问文件系统。以下 `main.mbt` 继续使用上文导入方式，已由公开黑盒测试编译并执行相同调用：

```moonbit
fn main raise {
  let restored = @moonlibsync.patch(
    b"abc",
    b"\x72\x73\x02\x36\x45\x00\x03\x00",
    @moonlibsync.Limits::default(),
  )
  println(restored.length()) // 3; restored == b"abc"
}
```

COPY 始终读取原始 basis，支持非顺序、重复和重叠区间，不能引用新增输出。入口先校验配置、basis 字节预算，完整解析全部 delta（必须 END 且无尾随），再预检所有 COPY 范围和最终输出长度，通过后才分配恢复缓冲区。失败只返回错误，不暴露半成品；输入不变。使用 max_old_bytes、max_delta_bytes、max_instructions 和 max_output_bytes；不消耗匹配工作预算，也不使用 max_new_bytes 代替恢复输出上限。详见[格式与补丁边界](../docs/delta-format.md)。

标准 delta **不认证 basis 身份**：错误 basis 即使范围合法，也可能恢复出错误内容。应用需在标准格式外校验整体内容，本项目不添加私有摘要字段。新增 9 项测试，共 67 项，涵盖公开调用与 16 个固定上游 delta 的逐字节恢复；此证据称为“MoonBit patch 恢复固定上游 delta”，尚未验证“MoonBit signature → 上游 delta → MoonBit patch”完整链路。公开能力现在是 signature 和 patch，delta 生成、新文件扫描、完整双向互操作及 0.1.0 发布仍未完成。

## Commit 10 从远端签名生成增量

新增 `delta(signature_bytes: Bytes, new_bytes: Bytes, limits: Limits) -> Bytes raise SyncError`，生成路径不接收 basis、不访问文件系统或全局缓存。签名只提供块长、弱/强校验和名义偏移，尾块长度由当前真实匹配窗口决定。扫描使用 rotate 逐字节推进、EOF rollout 缩短；确认强摘要后才输出 COPY。连续 literal 保存为新文件视图，仅合并输出相邻且 basis 区间连续的 COPY。详见[格式与生成流程](../docs/delta-format.md)及[工作预算](../docs/matching.md)。

以下示例沿用上文导入，签名准备模拟接收端；发送端的 delta 调用只使用签名和新文件：

```moonbit
fn main raise {
  let limits = @moonlibsync.Limits::default()
  let remote_signature = @moonlibsync.signature(
    b"abc", @moonlibsync.SignatureOptions::default(), limits,
  )
  let encoded = @moonlibsync.delta(remote_signature, b"!abc", limits)
  println(encoded.length())
}
```

同一次调用的索引、弱校验重建、滚动推进、候选确认和指令累积共享 max_match_work，超限即失败，不退化为完整 literal。输入受签名、新文件及预计恢复输出预算限制，指令累积时按合并后指令数和实际最短编码大小检查，最终编码器仍预检。签名即使配合空新文件也必须合法；其他公开入口及默认 Limits 不变。

预设复用用例为八个互异 64 字节块，中间插入 3 字节；固定门槛 COPY≥512 且 delta<515。实测 new=515、delta=18、COPY=512 字节。全异或很小的输入可能产生比新文件更大的 delta，不承诺普遍压缩。短强摘要有碰撞概率，伪造签名及看不到的 basis 无法认证，范围合法性与整体内容仍需接收端及应用验证。

新增 13 项测试，共 80 项。固定上游 old.sig + 独立 new.bin → MoonBit delta → 上游 rdiff patch/cmp，本机通过 16 个正式用例和 13 个临时复用/短尾用例。此处仅记录该方向及代表集，完整反向链、交叉/随机矩阵、小文件穷举和统一资源审计留待后续；无网络、目录同步、流式 API、正式 CLI 或发布。

## Commit 11 双向互操作与确定性回归

统一入口 `bash scripts/interop.sh` 使用固定rdiff和Native公开API适配器，执行两条必需链及signature/delta/patch的全部八种组合。计划固定为274对独立old/new、496个参数用例、3968次矩阵恢复；每组合及链A/B各496次。包含指定三字节字母表、长度0–2的169对有限穷举（block1/2、strong32）和48个固定LCG种子变异样本。精确分配、生成顺序、收费边界之外的未覆盖项见[互操作计划](../tests/interop/README.md)。

所有恢复逐字节比较独立new，签名要求完整字节一致；不要求两端delta字节、大小或指令数相同。保留COPY门槛、原82次签名及29次delta消费；工具缺失与比较失败都必须非零，随后再验证正常恢复。失败输入在临时清理前归档，报告和命令记录写入忽略目录_build/interop，由同SHA CI保存；本机未提交运行明确标记dirty。

本笔不新增公开API，不改变核心算法，80项MoonBit库测试与6项Python工具检查分别统计。Linux Native跨实现验证不代表JS/Wasm-GC直接调用rdiff已验证；有限随机回归也不代表所有输入均兼容。统一资源审计、正式CLI、最终跨目标验收与0.1.0发布仍未完成，历史阶段结论保留原归属。

## Commit 12 资源契约审计

九项Limits的逐入口适用范围、默认值、预检顺序、错误及全量缓冲存储关系见[资源契约](../docs/resources.md)。本笔修复指令Array自动扩容的隐藏搬移工作：在reserve/push前计入新容量槽及活跃槽搬移，容量不超过指令上限；已知签名记录数通过预检后精确预留。原工作单位保留，新增容量费用使三条旧精确预算32/82/16变为33/83/17，默认预算未提高。

新增19项资源测试，原80项保留，共99项，另保留6项Python工具检查；三目标使用同次完整测试生成独立资源报告。覆盖16个适用入口/字段关系的少1/等于/多1、退化候选与指令、UInt64边界、优先级及失败后复用。资源产物与完整互操作报告分别统计，274输入对/496参数/3968恢复计划不变。

API接收已存在的完整Bytes，视图会保活输入，记录、排序数组、命令容量、输出缓冲和最终转换副本可能共存。单项上限不是全进程峰值内存或精确CPU预算；没有执行OOM或堆峰值测量，也不承诺OOM能作为普通错误恢复。公开API、格式和默认参数不变；正式CLI、流式实现和发布仍未完成。

## Commit 13 Native 单文件 CLI

选择上述固定工具链后实际构建：

```text
moon build cmd/moonlibsync --target native
```

Windows与Linux默认产物均为`_build/native/debug/build/cmd/moonlibsync/moonlibsync.exe`；Linux文件实际为Native ELF，保留.exe后缀。本机WSL自定义目标目录为_build/linux。三个子命令：

```text
moonlibsync signature "old file.bin" old.sig --block-size 2048 --sum-size 32
moonlibsync delta old.sig "new file.bin" update.delta
moonlibsync patch "old file.bin" update.delta restored.bin
moonlibsync --help
moonlibsync --version
```

signature默认2048/32，选项仅对signature有效；--结束选项解析，单独-是普通文件名，不是管道。退出码0成功/help/version、2用法错误、1文件/核心错误；错误到stderr，文件操作成功时不打印二进制或额外日志。版本0.1.0仍为development/not released。

输入按普通文件和同句柄大小检查后分块限量读取：OLD/NEW各64MiB、SIG16MiB、DELTA80MiB。只分配已检查初始大小，增长/截短则拒绝；仍为全量缓冲，不是快照或流式保证。输出默认拒绝任何已有条目；同目录CreateNew临时文件写完、文件同步并关闭后，以replace=false提交，失败只清理自己临时文件，清理失败明确报错。

已测Windows Native/NTFS及Linux Native/ext4，WSL DrvFS对无覆盖重命名的EINVAL会明确失败并清理；未验证所有文件系统或断电持久化。构建路径、输入稳定要求、路径/链接策略、两平台证据及完整保证边界见[CLI说明](../docs/cli.md)。运行`./scripts/cli-smoke.ps1`或`bash scripts/cli-smoke.sh`。CLI检查与99项跨目标库测试、6项Python工具检查分别统计；核心API、资源默认值和正式夹具不变。未发布版本、标签或Release，止于Commit13。
