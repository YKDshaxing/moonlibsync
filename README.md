# MoonLibSync

MoonLibSync 0.1.0 是 MoonBit 纯字节远端签名差分库，提供 `signature(old, options, limits)`、`delta(signature, new, limits)`、`patch(old, delta, limits)`。发送端只持有标准签名与新字节即可生成增量。附 Windows／Linux Native 单文件 CLI；全量字节缓冲，不含网络或目录同步。

模块及公开仓库：[YKDshaxing/moonlibsync](https://github.com/YKDshaxing/moonlibsync)。0.1.0 的功能、接口与行为范围已冻结；实际上传、注册表消费及其源码归属按[发布验收说明](docs/release.md)和独立交付记录核对，能力说明本身不代表上传或消费已成功。

## 获取源码与本地导入

```text
git clone https://github.com/YKDshaxing/moonlibsync.git
cd moonlibsync
```

仓库内消费者的 `moon.pkg` 导入 `"YKDshaxing/moonlibsync" @lib`。完整可运行代码、三项API输入/返回/错误及完整性责任见[使用与设计](docs/design.md)与[纯字节示例](examples/basic/main.mbt)。注册表依赖声明与真实解析/运行结果分别核验，见下节。

## 模块包与仓库开发的区别

0.1.0 模块包交付字节库、`cmd/moonlibsync` Native CLI源码、`examples/basic`、完整许可证/来源说明及配套开发测试/夹具。没有预编译CLI二进制。对已取得的模块源码，可在模块根选择固定工具链、安装依赖后运行 `moon run examples/basic --target native`（也可js/wasm-gc），或构建前述CLI。对注册表下载源码的构建，应称为“注册表包源码构建”。

使用公开注册表版本的消费者，其 `moon.mod` 声明 `import { "YKDshaxing/moonlibsync@0.1.0", }`，包配置导入 `"YKDshaxing/moonlibsync" @lib`；本地候选消费者另用明确的workspace替换。版本声明不是下载成功证明，必须核对实际解析路径、版本与结果，不能将候选本地替换计作注册表消费。

下面安装器、Git接口保护、互操作、基准及发布工具命令属于**完整Git检出开发流程**，需要Git元数据及相应参考工具。脚本和完整测试资料随包保留以便审查，不能据此在没有.git的注册表依赖目录中直接执行仓库CI入口。基础示例/CLI构建与仓库CI入口分开使用。

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

Linux ELF 产物也保留 `.exe` 后缀。默认签名参数2048/32，CLI只读两个相应输入；所有输出必须不存在，父目录须已存在。用法错误退出2、文件/核心错误退出1。参数、受限读取、链接策略、无覆盖提交、清理及保证边界见 [CLI 文档](docs/cli.md)。

## 仓库开发：自动检查和参考交换

```text
python scripts/check.py
python scripts/verify_fixtures.py
python scripts/failure_gates.py
```

`check.py` 执行格式、生成前后接口保护、锁定依赖、Native/JS/Wasm-GC check/build/根包99项测试与各目标实际示例，不重复核心矩阵来生成统计。示例、接口与资源证据分别在 `_build/examples/`、`_build/interfaces/`、`_build/resources/`。CLI 独立执行 `./scripts/cli-smoke.ps1` 或 `bash scripts/cli-smoke.sh`；6项 Native 辅助测试不混入99项根包测试。

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

冻结三项API/公开类型、默认值、RK+BLAKE2 profile、标准delta宽度、错误与资源契约、CLI语法及文件保证、已验证目标和范围外能力；详见[冻结记录](docs/compatibility.md#commit-15首版功能冻结)。冻结不表示源码包候选、发布或0.1.0整体交付已经完成。

## 支持与交付边界

支持签名 profile `RS_RK_BLAKE2_SIG_MAGIC`，BLAKE2b先计算32字节再截取1–32字节；delta解析覆盖全部标准 literal/COPY 参数宽度，严格拒绝END后尾随数据。其他签名profile返回明确错误。详见[格式与兼容性](docs/compatibility.md)、[资源契约](docs/resources.md)。各项预算是逻辑字节/记录/工作上限，不是进程峰值内存或CPU时间保证；不承诺OOM恢复。

CLI已验证 Windows Native/NTFS、Linux Native/ext4。WSL DrvFS `/mnt/d` 不支持所需无覆盖提交时明确失败并清理，不退回覆盖；本机WSL正向CLI运行设置 `MOONLIBSYNC_CLI_TMP_PARENT=/tmp`。未验证所有文件系统、网络盘、恶意路径替换或断电持久化。

[九项阶段验收表](docs/contest-acceptance.md) 区分实现、目标、证据、阶段归属与未完成项。有限基准与首版功能冻结已完成；[基准报告](docs/benchmarks.md)包含10组实际数据量、COPY及三项操作中位数/最小/最大值。Commit16的实际归档审计、发布源、注册表获取与消费证据按[发布验收说明](docs/release.md)独立归档。历史记录保留在 [Commit 1–13 快照](docs/history.md)，不作为当前能力声明。

采用 LGPL-2.1-or-later；[LGPL文本](COPYING.LESSER)、[GPL文本](COPYING)、[来源](SOURCES.md)、[第三方说明](THIRD_PARTY_NOTICES.md) 以实际文件为准；源码说明存在不代表正式分发包义务审计已经完成。
