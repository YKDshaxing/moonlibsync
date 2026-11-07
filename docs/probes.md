# Commit 1：可行性探针与检查记录

记录日期：2026-11-07（Asia/Shanghai）。状态仅使用“已通过 / 未通过 / 未执行”。本文件记录工程基础，不是 signature、delta、patch、互操作或 0.1.0 交付报告。

## 目录、工具链与身份

开始时 `D:\project\moonlibsync` 为空，`git status --short --branch` 退出 128，提示不是 Git 仓库，无基线 SHA。未发现适用的 AGENTS.md；确认后才执行 `git init -b main`。没有清空或覆盖用户已有文件。沙箱账号和目录所有者不同，Git 命令使用单次 `-c safe.directory=D:/project/moonlibsync`，没有修改全局 Git 配置。

初始工具链完整输出（`moon version --all`、`moonc -v`，命令退出均为 0）：

```text
moon 0.1.20260915 (2e1a46d 2026-09-15) ~\.moon\bin\moon.exe
moonc v0.10.13+cbb11c36f (2026-09-15) ~\.moon\bin\moonc.exe
moonrun 0.1.20260915 (2e1a46d 2026-09-15) ~\.moon\bin\moonrun.exe

Feature flags enabled: rr_moon_mod,rr_moon_pkg
v0.10.13+cbb11c36f (2026-09-15)
```

初始编译器最低版本要求：**未通过**，`0.10.13 < 0.10.16`。没有用旧版冒充本笔已验证版本，也未升级用户全局工具链。

最终选用的 Windows 工具链完整输出（两条命令退出均为 0）：

```text
moon 0.1.20261104 (940aa18 2026-11-04) D:\project\moonlibsync\.toolchain\selected\bin\moon.exe
moonc v0.10.20+65efd5b93 (2026-11-05) D:\project\moonlibsync\.toolchain\selected\bin\moonc.exe
moonrun 0.1.20261104 (940aa18 2026-11-04) D:\project\moonlibsync\.toolchain\selected\bin\moonrun.exe

Feature flags enabled: rr_moon_mod,rr_moon_pkg
v0.10.20+65efd5b93 (2026-11-05)
```

最终工具链要求：**已通过**。固定安装版本为 `0.10.20+65efd5b93`，不是 moon 的日期版本；已实取官方版本化 Windows/Linux 归档及配套 core，SHA-256 见 `toolchain.lock.json`。Windows `python scripts/install_toolchain.py` 退出 0，实际验证归档、解包、bundle core（528 个任务）和运行版本。Linux 补证另列于下方。

| 项目 | 状态 | 实测版本 / 输出 |
| --- | --- | --- |
| Windows Native 编译 | 已通过 | Visual Studio Build Tools 17.14.37710.0，MSVC x64 `19.44.35229`；实际生成并运行 Native 测试与探针 |
| Windows SDK | 已通过 | MSVC Native 链接及 async 文件接口探针成功；没有单独宣称测试所有 SDK API |
| MinGW | 已通过 | 调查命令 `gcc --version`：14.2.0，退出 0；本笔 Windows Native 实际使用 MSVC，未采用 MinGW |
| Windows JS 运行时 | 已通过 | `node --version`：`v24.18.0`，退出 0；JS 测试与摘要输出通过 |
| Windows Wasm-GC 运行时 | 已通过 | `moonrun 0.1.20261104 (940aa18 2026-11-04)`；实际运行测试与摘要输出 |
| 模块与包格式 | 已通过 | 运行 `moon new` 的隔离临时样例确认 `moon.mod` / `moon.pkg`；本仓库仅采用此格式 |
| 依赖锁机制 | 已通过 | 未生成 Moon 原生解析锁；`.mooncakes/.moon-lock` 是空互斥锁。项目自建 `dependencies.lock.json` 并逐文件核验 |

核对过当前 `moon new/add/check/build/test/run/fmt/info/bundle --help`。尤其 `moon check` 会自动更新接口，所以一致性脚本在调用前保存快照，第一次拉取依赖用 `--no-mbti`，最后 `moon info` 后比较；CI 再用 Git 检查已跟踪接口差异。

GitHub 归属固定为 `YKDshaxing/moonlibsync`，origin 为 `git@github-ykd:YKDshaxing/moonlibsync.git`。初次 `github-ykd` 未配置时失败；用户配置后重新验证：

```text
ssh -o BatchMode=yes -T git@github-ykd
Hi YKDshaxing! You've successfully authenticated, but GitHub does not provide shell access.
exit=1
```

SSH 认证：**已通过**，依据提示中的账号，退出码 1 不当成失败。仓库起初返回 `Repository not found`；用户创建仓库后再次 `git ls-remote origin` 退出 0、无 refs（空仓库），Actions 页面 HTTP 200。已分开核对认证、仓库权限与提交署名。连接器当前身份是另一账号，不通过该连接器写入；Git 推送使用指定 SSH 别名。

用户后续明确“不需要邮箱”，Git 仓库级设置使用 `user.name=YKDshaxing`、空 `user.email`、`user.useConfigOnly=true`。`git var GIT_AUTHOR_IDENT` 实际接受 `YKDshaxing <>`。没有猜测 noreply 地址，没有借用全局的 BigSaltyMan 署名或邮箱，也不声称空邮箱提交已关联 GitHub 个人资料。

## 配置校验和公开接口

**已通过**：`error.mbt` 声明十个规划分类；当前只使用 `InvalidOptions(String)`。`Limits` 九个字段均为 Int64，除块长下限为 1 外，下限均为 0，上限统一为 2147483647。字段单位与默认值见 README；匹配工作量单位计量规则仍待后续固定。

三个测试分别验证默认值、九字段的边界/负数/越界与错误字段名、块长拒绝零。覆盖 Int64 最小值、-1、下限、1、2147483647、2147483648 和 Int64 最大值；超出 Int64 的输入无法构造该类型，未通过截断强制转换来“验证”。每个目标均报告 `Total tests: 3, passed: 3, failed: 0.`。

生成并保留核心和摘要包的 `pkg.generated.mbti`；Native 探针无公开声明，且不支持模块规范后端 Wasm-GC，因此当前 `moon info` 不生成其规范接口文件。`moon info --target all` 实测会报告该包 Native 接口与不支持的规范后端有差别；这不是核心跨目标 API 漂移。CI 使用规范接口生成与差异检查。

**未执行**：算法预算执行、退化输入资源验证、解析器错误载荷设计。三个主操作不存在，不把配置测试当算法正确性证据。

## BLAKE2b-256 依赖

| 阶段 | 状态 | 命令、退出码与证据 |
| --- | --- | --- |
| 候选检索 | 已通过 | 注册表和包源码找到 `moonbitstack/mooncrypt@0.4.5`；`oboard/mooncrypto@0.1.8` 元数据只列 md5/sha/base64，没有据此主张其支持 BLAKE2b |
| 依赖获取 | 已通过 | 固定模块首次 `moon check` 实际下载 mooncrypt、moonbase 0.4.2、moondate 0.1.0、moonrand 0.1.0，退出 0 |
| 参数源码核对 | 已通过 | `hash(..., kind=Blake2b, len=32)`；`build` 的 BLAKE2b 初始参数字包含 `nn=len`，内部采用 UInt64 模加、旋转与小端序 |
| 许可证核对 | 已通过 | mooncrypt 文件头 Apache-2.0、Copyright 2026 Leo Cheng；全部闭包版本与 SHA-256 固定，完整许可证保留 |
| 版本和源码核验 | 已通过 | `python scripts/verify_dependencies.py` 退出 0：四个包 archive and source 一致，依赖闭包无漂移 |
| 独立向量来源 | 已通过 | `python scripts/reference_vectors.py` 退出 0；CPython 3.14.6 hashlib，`digest_size=32`；来源见 SOURCES.md |
| Native 编译 | 已通过 | `moon build --target native`，退出 0 |
| Native 向量运行 | 已通过 | `moon run probes/digest --target native`，退出 0；两个实际值逐一等于下表 |
| JS 编译 | 已通过 | `moon build --target js`，退出 0 |
| JS 向量运行 | 已通过 | `moon run probes/digest --target js`，退出 0；两个实际值逐一等于下表 |
| Wasm-GC 编译 | 已通过 | `moon build --target wasm-gc`，退出 0 |
| Wasm-GC 向量运行 | 已通过 | `moon run probes/digest --target wasm-gc`，退出 0；两个实际值逐一等于下表 |

以下每个向量均无密钥、盐或个性化参数，BLAKE2b 的输出长度参数为 **32**。Windows 三个目标均实际输出以下完整实际值：

| 原始输入（hex） | 预期摘要 | Native 实际 | JS 实际 | Wasm-GC 实际 |
| --- | --- | --- | --- | --- |
| 空串 | `0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8` | `0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8` | `0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8` | `0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8` |
| `616263`（ASCII abc） | `bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319` | `bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319` | `bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319` | `bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319` |

探针还逐一检查 strong_sum_len 为 1–32 时，截取上述 32 字节摘要的前缀；并对比实际 BLAKE2s(len=32)、BLAKE2b(len=64) 的前 32 字节，确认其不等于该预期。预期值没有由 mooncrypt 产生。

依赖路线已确定，无需在本阶段移植 BLAKE2b。后续使用前仍需补充长输入、块边界等与实际算法需求相匹配的测试；本笔两个向量不证明整个密码库的全面正确性。

## Windows Native 文件接口

**已通过**：`python scripts/native_probe.py` 和 `./scripts/native_probe.ps1`，均退出 0。实际使用固定 core 的 `async/fs` 读写二进制文件、`env.args()`、`async/stdio.stderr.write` 和 `env.exit()`。Native 包通过 `supported_targets = "-all+native"` 隔离；JS/Wasm-GC 不会引入它。

每次使用 `_build/probe-runs` 下独立新建的临时目录，目录在清理前验证位于指定根内；只清理该次探针目录。含空格样本路径实际往返成功。关键外部进程结果：

```text
mode=roundtrip exit=0 stdout=native-probe roundtrip-ok bytes=00,7f,80,ff empty=ok path=.../binary sample with spaces.bin stderr=
mode=fail exit=23 stdout= stderr=native-probe intentional-failure
mode=read-missing exit=24 stdout= stderr=native-probe io-error: @fs.open(): ... The system cannot find the file specified.
mode=write-missing exit=24 stdout= stderr=native-probe io-error: @fs.open(): ... The system cannot find the path specified.
```

MoonBit 端使用字节相等比较，外部 Python 再核对 `00 7f 80 ff` 原始字节及空文件 `b""`，不是仅比长度。参数中含空格路径成功送达且用于读写。失败路径若意外成功会退出 25，并产生不同 stdout，不能被误认成预期的 I/O 错误 24。PowerShell 包装显式检查外部 Python 的 `$LASTEXITCODE`，Python 对每个 Native 子进程的实际 returncode/stderr/stdout 分别断言；没有只依赖 `$ErrorActionPreference`。

未来输出保护接口调查：固定 `core/async/fs` 暴露 `CreateNew`、`rename(old, new, replace?)`、`File::sync`、`SyncMode`，这些是后续调查候选。`moonbitlang/x@0.5.7` 调查中的写入实现使用 `fopen(...,"wb")`，不是未来无覆盖提交保证；因此未采用它作输出保护依据。本笔只在全新临时路径使用 `CreateNew`，**未执行**覆盖冲突、竞争写入、无覆盖 rename、崩溃一致性、持久化及原子提交验证；不宣称已具备并发安全文件提交或完整 CLI。

## Linux 补证

环境：Ubuntu 24.04 WSL2 x86_64，内核 `6.6.87.2-microsoft-standard-WSL2`，GCC `13.3.0`，Node.js `v22.23.2`，Python `3.12.3`。Linux 工具链路径 `.toolchain/linux`，版本与 Windows 完全一致。构建目录设置 `MOONLIBSYNC_BUILD_DIR=_build/linux`，避免复用 Windows 产物。

直接从 WSL 下载工具链：**未通过**，网络连接被重置。随后通过 Windows 网络取得同一官方固定 Linux 归档，按锁文件校验后放入共享下载缓存；`python3 scripts/install_toolchain.py --name linux`：**已通过**，退出 0，core bundle 528 个任务，实际运行 moon/moonc/moonrun 输出与上面固定版本一致。

WSL 使用已核验的相同依赖归档与四份注册表记录，并显式设置 `MOONLIBSYNC_OFFLINE_INDEX=1` 跳过网络更新；没有改版本或跳过摘要/源码校验。首次运行因注册表尚未复制失败，已补齐固定记录。CI 不设置该离线变量，会执行 `moon update`。

Linux 完整检查与文件接口探针：**已通过**，`python3 scripts/check.py` 退出 0。设置上述 Linux MOON_HOME/PATH、独立构建目录和离线索引变量后，Native、JS、Wasm-GC 的 check/build/test 均退出 0，各目标同样是 3/3 配置测试；各目标实际打印的空输入与 `616263` 摘要分别与上表完整预期值一致。Linux 的独立 oracle 为 CPython 3.12.3 hashlib，输出也相同。格式、四包源码/归档核验、接口前后快照及 `git diff --check` 均通过。

Linux Native 外部进程实际输出：

```text
mode=roundtrip exit=0 stdout=native-probe roundtrip-ok bytes=00,7f,80,ff empty=ok path=.../binary sample with spaces.bin stderr=
mode=fail exit=23 stdout= stderr=native-probe intentional-failure
mode=read-missing exit=24 stdout= stderr=native-probe io-error: @fs.open(): ... No such file or directory
mode=write-missing exit=24 stdout= stderr=native-probe io-error: @fs.open(): ... No such file or directory
Native file/args/stderr/exit probe passed.
```

Linux 上 Python 检查脚本及 Native 子进程均实际执行；WSL 没有安装 Linux PowerShell，因而本地 Linux PowerShell 包装为**未执行**，由 Ubuntu CI 的 pwsh 步骤补证。Windows PowerShell 包装已通过。云端 runner 与本机 WSL 不视为同一个环境。

## 最小检查与 CI

Windows `python scripts/check.py`：**已通过**，退出 0。执行项目：

```text
moon version --all
moon fmt --check
moon update
moon check --target wasm-gc --no-mbti
python scripts/verify_dependencies.py
python scripts/reference_vectors.py
moon check --target native
moon build --target native
moon test --target native
moon run probes/digest --target native
moon check --target js
moon build --target js
moon test --target js
moon run probes/digest --target js
moon check --target wasm-gc
moon build --target wasm-gc
moon test --target wasm-gc
moon run probes/digest --target wasm-gc
python scripts/native_probe.py
moon info
git -c safe.directory=D:/project/moonlibsync diff --check
```

各实际子命令均检查非零状态并中止；三个目标各 3 个配置测试通过。摘要向量由独立运行包打印并断言，不拿空测试包当摘要正确性证据。接口前后快照一致，格式检查通过。

云端 CI：**未执行（本文件首次提交前快照）**，此时尚无远端提交、运行 SHA 或 CI 链接。已配置 Windows/Linux 两个 job，每个 job 验证固定工具链、固定依赖、三目标及 Native 文件接口；没有添加 rdiff 互操作、算法空测试矩阵、性能、完整 CLI 验收或发布任务。推送后核对实际 SHA 的 [Actions 记录](https://github.com/YKDshaxing/moonlibsync/actions/workflows/ci.yml)，在最终交付报告中提供实际运行链接与状态；仓库 Actions 页面可访问不等于 CI 通过。官方 Node `v24.18.0` 发行校验清单地址已实际取得 HTTP 200；两平台的同版 MoonBit 归档也已实际下载并安装，不仅填写版本字符串。

未执行且超出本笔：signature、delta、patch，实现资源预算，rdiff 构建/互操作/离线夹具，性能测试、完整 CLI 验收、Mooncakes 发布、版本标签、GitHub Release。到 Commit 1 工程基础与依赖路线确定为止。
