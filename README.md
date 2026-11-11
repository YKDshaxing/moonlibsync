# MoonLibSync 0.3.0

0.3.0能力已冻结，当前为发布候选；实际上传和两平台注册表验收状态以[0.3.0发布记录](docs/release-0.3.0.md)为准，版本字符串不是发布证明。自0.3.0提供显式自动块长、Delta／Full更新规划及schema2受校验应用。0.2.0的历史发布源与注册表实证保留于[原版记录](docs/release-0.2.0.md)。

MoonLibSync提供与librsync互操作的全量缓冲字节差分库及Native单文件CLI。自0.2.0提供检查API、可复用签名索引、完整性清单及受校验补丁流程。本页保留0.2.0能力并增加0.3.0阶段B契约；实际上传与独立注册表验收状态见[本版发布记录](docs/release-0.3.0.md)，版本字符串本身不是发布证明。

| 层次 | 公开入口与用途 |
|---|---|
| 标准字节差分 | signature / delta / patch；发送端仅需远端签名与NEW |
| 检查与预检 | inspect_signature / inspect_delta / check_patch；长度预检不认证内容身份 |
| 可复用索引 | prepare_signature / PreparedSignature::delta；准备一次、逐次重检限制并独立计量 |
| 格式外清单 | create/parse/encode_basis_info 与 create/parse/encode_update_manifest |
| 校验后返回/提交 | verified_patch 与patch-verified实际核验OLD、DELTA及结果；未传入SIG，不实际核验SIG文件 |

清单需要可信来源，不提供发布者认证。签名profile为RK+BLAKE2，BLAKE2b先计算32字节再截取；默认2048/32，严格END及尾随数据策略不变。全量缓冲与转换副本的边界见[资源契约](docs/resources.md)。有限复用基准未观察到稳定总耗时优势，历史测量未重跑。

```text
git clone https://github.com/YKDshaxing/moonlibsync.git
cd moonlibsync
```

本版消费者依赖声明如下，用于发布后的注册表验收；实际可用状态见发布记录。moon.mod声明 `import { "YKDshaxing/moonlibsync@0.3.0", }`，moon.pkg导入 `"YKDshaxing/moonlibsync" @lib`。注册表消费必须核验实际解析路径与版本；本地候选包允许明确workspace替换，两者分别统计。[basic](examples/basic/main.mbt)、[prepared](examples/prepared/main.mbt)、[verified](examples/verified/main.mbt)均为可运行公共API示例。

模块包交付库、十一条CLI命令的源码、示例及许可/来源资料，不含预编译二进制或安装器。从注册表下载后构建CLI应称为“注册表包源码构建”。完整Git检出的参考、CI、基准与发布工具需要Git元数据和相应参考环境，不应在普通依赖目录直接当作库入口运行。

0.1.0的原三项API发布源为f62958eceda9deecc4eae8a14007f5be76c59b0e，历史实际包/许可证、发布及消费证据完整保留于[0.1.0发布记录](docs/release.md)。本版不改写其179成员/268008字节或既有归档，也不把旧包称为包含阶段A接口。

## 自0.3.0：显式自动块长

自0.3.0新增 `recommend_block_len` 和 `signature OLD SIG --block-size auto`，已发布0.2.0原包不含此入口。必须显式启用，默认2048/32、数字选项及标准签名格式不变；本版实际发布状态见发布记录。policy v1按长度和预算使用整数规则推荐，目标约512条记录，不保证更小delta或更快。完整规则、预算边界和固定/自动数据量对照见[自动块长](docs/auto-block.md)。[公开API示例](examples/auto/main.mbt)可用 `moon run examples/auto --target native`（也可js/wasm-gc）运行，原0.2.0注册表包不含新API，本版发布状态单列。

## 固定工具链与源码运行

已验证 `moonc v0.10.20+65efd5b93 (2026-11-05)`、moon/moonrun `0.1.20261104`；不代表所有 >=0.10.16 版本均兼容。`toolchain.lock.json` 固定 Windows/Linux 工具链及配套 core 哈希；`dependencies.lock.json` 固定 mooncrypt 0.4.5 等依赖闭包，`.mooncakes/.moon-lock` 仅为空互斥文件。

需要 Git、Node.js（CI 24.18.0）、Native C/C++ 工具链。Windows 使用带 Windows SDK 的 MSVC Build Tools；Linux 使用 GCC/build-essential。安装与自动校验另需 Python 3.12+。安装器仅写本项目 `.toolchain`，不修改全局工具链。

Windows PowerShell：

```powershell
python scripts/install_toolchain.py
if ($LASTEXITCODE -ne 0) { throw 'Toolchain installation failed' }
$env:MOON_HOME = (Resolve-Path '.toolchain/selected').Path
$env:PATH = "$env:MOON_HOME\bin;$env:PATH"
moon update
if ($LASTEXITCODE -ne 0) { throw 'Dependency index failed' }
moon run examples/basic --target native
if ($LASTEXITCODE -ne 0) { throw 'Native example failed' }
moon run examples/basic --target js
if ($LASTEXITCODE -ne 0) { throw 'JS example failed' }
moon run examples/basic --target wasm-gc
if ($LASTEXITCODE -ne 0) { throw 'Wasm-GC example failed' }
```

Linux Bash（任一命令失败应停止）：

```bash
set -euo pipefail
python3 scripts/install_toolchain.py
export MOON_HOME="$PWD/.toolchain/selected"
export PATH="$MOON_HOME/bin:$PATH"
moon update
moon run examples/basic --target native
moon run examples/basic --target js
moon run examples/basic --target wasm-gc
```

[纯字节示例](examples/basic/main.mbt) 仅导入公开库，自身运行不调用 Python、文件系统或 rdiff。八个互异64字节块构成512字节旧数据，中间插入 `00 80 ff` 得到515字节新数据，参数64/32；恢复不等或 delta 不小于新数据时非零退出。配套 `python scripts/check_example.py --target native`（也可 js/wasm-gc）解析**本次输出的 delta**，严格验证 COPY >=512 字节及 delta <515；示例次数与库单元测试分开统计。说明见 [examples/basic/README.md](examples/basic/README.md)。

## Native 单文件 CLI

```text
moon build cmd/moonlibsync --target native
```

Windows PowerShell：

```powershell
$cli = "$PWD/_build/native/debug/build/cmd/moonlibsync/moonlibsync.exe"
& $cli signature 'old file.bin' old.sig --block-size 64 --sum-size 32
if ($LASTEXITCODE -ne 0) { throw 'signature failed' }
& $cli delta old.sig 'new file.bin' update.delta
if ($LASTEXITCODE -ne 0) { throw 'delta failed' }
& $cli patch 'old file.bin' update.delta restored.bin
if ($LASTEXITCODE -ne 0) { throw 'patch failed' }
```

Linux Bash：

```bash
cli="$PWD/_build/native/debug/build/cmd/moonlibsync/moonlibsync.exe"
"$cli" signature 'old file.bin' old.sig --block-size 64 --sum-size 32
"$cli" delta old.sig 'new file.bin' update.delta
"$cli" patch 'old file.bin' update.delta restored.bin
```

Linux ELF 产物也保留 `.exe` 后缀。默认签名参数2048/32，CLI按相应命令读取输入；所有输出必须不存在，父目录须已存在。用法错误退出2、文件/核心错误退出1。参数、受限读取、链接策略、无覆盖提交、清理及保证边界见 [CLI 文档](docs/cli.md)。

本版还支持（`$cli` 为上文构建路径）：

```powershell
& $cli inspect-signature old.sig --json
& $cli inspect-delta update.delta --json
& $cli check-patch 'old file.bin' update.delta --json
```

去掉 `--json` 得到相同核心字段的人类文本。检查不创建输出/临时文件；`check-patch` 只查询 OLD 种类与大小，有界读取 DELTA，再复核 OLD 大小，不读取或哈希 OLD 内容。JSON 为单个 UTF-8 对象加换行，`schema_version` 是整数1，所有 Int64 字段是精确十进制字符串。失败 stdout 为空、stderr 为诊断，退出码仍为0/2/1；stdout 写失败返回非零，已写入的管道字节不保证撤回。完整 schema 与示例见[检查 CLI 契约](docs/cli.md#commit-18开发源码检查命令)。

## 仓库开发：自动检查和参考交换

```text
python scripts/check.py
python scripts/verify_fixtures.py
python scripts/failure_gates.py
```

`check.py` 执行格式、生成前后接口保护、锁定依赖、Native/JS/Wasm-GC check/build/根包166项测试（原157项加9项受校验补丁测试）与各目标 basic/prepared/verified 实际示例，不重复核心矩阵来生成统计。另有三目标12次外部编译封装探针，单列于 `_build/prepared-encapsulation/`；独立hashlib/JSON清单向量工具也在同入口运行。示例、接口与资源证据分别在 `_build/examples/`、`_build/interfaces/`、`_build/resources/`。CLI 独立执行 `./scripts/cli-smoke.ps1` 或 `bash scripts/cli-smoke.sh`；15项 Native 辅助测试（原12项加3项）不混入166项根包测试，CLI集成场景亦在报告中单列。

Linux 参考任务先安装 `build-essential cmake libpopt-dev`，在支持无覆盖提交的文件系统运行：

```bash
bash scripts/rebuild-reference.sh
python3 scripts/consume_signature.py
python3 scripts/consume_delta.py
bash scripts/interop.sh
python3 scripts/file_exchange.py
```

固定 librsync v2.3.4 / `e364852674780e43d578e4239128ff7014190ed3`。保留原82次签名消费、29次delta消费；完整矩阵为274对输入、496参数用例、八组合各496，共3968次恢复，另有6项Python工具检查。[文件交换演示](docs/cli.md#commit-14linux-native-文件交换) 使用正式CLI与固定rdiff完成两条真实链，命令、输入输出及逐字节比较证据在 `_build/exchange/`。这是 Linux Native 参考验证，三目标核心检查不表示三目标均直接调用rdiff。

`failure_gates.py` 只破坏可运行临时源码副本：原参考夹具、opcode夹具及示例预期字节错误必须使 CI 实际入口非零；恢复正常内容后对应入口必须成功。另删除受检接口验证生成前拒绝。异常、超时或工具缺失不会被当作预期通过；分离日志与报告在 `_build/gates/`。CI沿用一个Linux参考任务和两个平台基础任务，任何必需检查失败阻断任务，`always()` 仅用于保存证据。

## 仓库开发：有限基准与功能冻结

Linux Native选择固定工具链、安装参考构建依赖后：

```bash
bash scripts/build-reference.sh
python3 scripts/benchmark.py --self-check
python3 scripts/benchmark.py
```

固定五类场景、64KiB/1MiB、2048/32，预热2轮、正式7轮，release CLI与固定rdiff Release在ext4上交替执行；patch比较使用同一rdiff delta。计时包含启动和文件流程，Moon还含sync与无覆盖提交；不是纯算法耗时。全异场景实际零COPY且delta大于new，本机Moon进程流程比rdiff慢，结论限于这次环境。原始轮次、输入/可执行文件哈希及最终源码关联保存在 `_build/benchmarks/`，完整方法/结果见[基准](docs/benchmarks.md)。CI只运行工具正确性检查，不设置硬件性能门槛。

上段为Commit15首版基准的历史方法与结果，后续复用基准见[独立报告](docs/benchmarks-prepared.md)，均未重新计时。本版保留阶段A契约并冻结阶段B入口、类型、schema2及文件边界，见[0.3.0冻结记录](docs/release-0.3.0.md)。

## 支持与交付边界

支持签名 profile `RS_RK_BLAKE2_SIG_MAGIC`，BLAKE2b先计算32字节再截取1–32字节；delta解析覆盖全部标准 literal/COPY 参数宽度，严格拒绝END后尾随数据。其他签名profile返回明确错误。详见[格式与兼容性](docs/compatibility.md)、[资源契约](docs/resources.md)。各项预算是逻辑字节/记录/工作上限，不是进程峰值内存或CPU时间保证；不承诺OOM恢复。

CLI已验证 Windows Native/NTFS、Linux Native/ext4。WSL DrvFS `/mnt/d` 不支持所需无覆盖提交时明确失败并清理，不退回覆盖；本机WSL正向CLI运行设置 `MOONLIBSYNC_CLI_TMP_PARENT=/tmp`。未验证所有文件系统、网络盘、恶意路径替换或断电持久化。

[九项阶段验收表](docs/contest-acceptance.md) 区分实现、目标、证据、阶段归属与未完成项。有限基准与首版功能冻结已完成；[基准报告](docs/benchmarks.md)包含10组实际数据量、COPY及三项操作中位数/最小/最大值。Commit16的实际归档审计、发布源、注册表获取与消费证据按[发布验收说明](docs/release.md)独立归档。历史记录保留在 [Commit 1–13 快照](docs/history.md)，不作为当前能力声明。

采用 LGPL-2.1-or-later；[LGPL文本](COPYING.LESSER)、[GPL文本](COPYING)、[来源](SOURCES.md)、[第三方说明](THIRD_PARTY_NOTICES.md) 以实际文件为准；逐成员正式包审计及其实际状态以本版发布记录为准。

## 0.3.0验证与正式发布边界

`python scripts/release_check.py --clean`审计实际moon package并在仓库外完成旧版、阶段A、阶段B三目标消费；默认写 `_build/release-0.3.0/windows` 或 `linux`，也可用MOONLIBSYNC_RELEASE_DIR显式分目录。`--registry`只在上传后运行，用新SDK和空模块缓存真实下载本版，禁止workspace/path/Git替换，并从下载源码构建CLI。候选和注册表共用48项transfer、2项auto检查与相同阶段B模板，来源类型单列；旧消费者和阶段A检查保留。错误消费者必须使工具非零，恢复后通过。0.1.0/0.2.0归档只读；两平台实际消费不能由候选CI抵扣。完整门禁、许可与状态见[发布记录](docs/release-0.3.0.md)。

## 自0.3.0：更新负载选择

自0.3.0提供 `plan_update`、schema2 `TransferManifest` 制作/编解码和 `apply_update`，以及 `make-transfer-manifest` / `apply-update` 两条单输出CLI。只有实际delta严格更小且达到min_savings_bytes（默认0）才选Delta，其余Full；生成错误仍传播。原delta、schema1和默认参数不变。先生成再选择不免除计算/内存成本。完整[API、协议、错误及文件流程](docs/updates.md)与[三目标可运行示例](examples/transfer/main.mbt)展示本版公开API；0.2.0原包没有这些入口，实际上传状态见本版发布记录。
