# 来源与固定版本

本文件只记录实际来源和使用程度，不把参考版本等同于构建、移植或互操作验证。

| 项目 | 固定版本 / 来源 | 本阶段使用 |
| --- | --- | --- |
| MoonLibSync | 本仓库原创文件，LGPL-2.1-or-later | 工程、配置校验、受检整数、内部签名结构解析、白盒测试、探针和脚本 |
| librsync | [v2.3.4 提交 e364852674780e43d578e4239128ff7014190ed3](https://github.com/librsync/librsync/tree/e364852674780e43d578e4239128ff7014190ed3) | 签名格式参考；未移植算法、未构建 rdiff、未生成夹具、未验证互操作 |
| moonbitstack/mooncrypt | Mooncakes `0.4.5`，仓库 [moonbitstack/mooncrypt](https://github.com/moonbitstack/mooncrypt) | 真实调用 `src/hash/blake2/blake2.mbt` 与 `src/spec`，BLAKE2b 输出参数 32 |
| moonbase / moondate / moonrand | `0.4.2` / `0.1.0` / `0.1.0` | mooncrypt 模块声明的依赖；没有将未调用的包算法说成已验证 |
| MoonBit core | `0.10.20+65efd5b93` 配套压缩包 | 字节、数值、hex、env、Native async/fs、async/stdio |
| Python hashlib | Windows CPython 3.14.6；可复核脚本 `scripts/reference_vectors.py` | 独立生成并核对两个 BLAKE2b-256 预期向量，未由 mooncrypt 自生预期 |

完整依赖压缩包 SHA-256 及精确依赖关系位于 `dependencies.lock.json`；工具链与 core 各平台 SHA-256 位于 `toolchain.lock.json`。注册表源码压缩包没有被提交到本仓库，安装后由 `scripts/verify_dependencies.py` 对比压缩包和解包源文件。mooncrypt `blake2.mbt` 的实际头部为 `Copyright 2026 Leo Cheng` / `SPDX-License-Identifier: Apache-2.0`；其实现使用 `UInt64` 模加、移位和小端字节拼接，参数块初始化包含输出长度，不是对 64 字节摘要进行截断。

独立向量依据：[Python hashlib 的 BLAKE2 文档](https://docs.python.org/3/library/hashlib.html#blake2)，其 `digest_size` 指定算法输出长度；算法设计参考 [RFC 7693](https://www.rfc-editor.org/rfc/rfc7693)。两条向量的原始输入为十六进制空串和 `616263`，无密钥、盐或个性化参数。当前摘要依赖满足探针需求，因此本阶段没有启动最小 BLAKE2b 移植，也没有引入 C librsync FFI。

许可证文本来源：

- `COPYING.LESSER`：逐字节保留固定 librsync 提交的 [`COPYING`](https://raw.githubusercontent.com/librsync/librsync/e364852674780e43d578e4239128ff7014190ed3/COPYING)，LGPL v2.1。SHA-256 `5bbcbb737e60fe9deba08ecbd00920cfcc3403ba2e534c64fdeea49d6bb87509`。该上游没有 `COPYING.LESSER` 路径，未伪称从该路径下载。
- `COPYING`：逐字节保留 GNU GCC [releases/gcc-14.2.0/COPYING](https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.2.0/COPYING) 的 GPL v2 文本，SHA-256 `231f7edcc7352d7734a96eef0b8030f77982678c516876fcb81e25b32d68564c`。只复用许可证文本，没有引入 GCC 源码。
- `licenses/Apache-2.0.txt`：固定 mooncrypt `0.4.5` 源码压缩包中的完整 `LICENSE`。
- `licenses/MoonBit-core-LICENSE` 和 `licenses/MoonBit-core-NOTICE`：固定 core 压缩包中的原文，保留其实际声明。

没有将上游文件统一改标为 MIT。项目的 `LGPL-2.1-or-later` 不替代 Apache-2.0 依赖的原有许可；本阶段无二进制发布，也不宣称已经完成未来发布时全部组合许可与再分发审核。

## Commit 2 格式参考

实际读取固定提交的 [`src/librsync.h`](https://github.com/librsync/librsync/blob/e364852674780e43d578e4239128ff7014190ed3/src/librsync.h) 和 [`src/readsums.c`](https://github.com/librsync/librsync/blob/e364852674780e43d578e4239128ff7014190ed3/src/readsums.c)：前者核对四种签名 magic 与 delta magic 的分类；后者核对 magic、块长、强摘要长的头顺序，以及每条记录先 weak u32、后指定长度 strong 字节的布局。没有根据名字或字节前缀推测 profile 算法。

`wire.mbt`、`signature.mbt` 及白盒测试为独立 MoonBit 实现，未逐行移植 C 解析状态机或其有符号整数读取代码。手写十六进制向量不是由本项目编码器生成。头部长度、零字段拒绝、严格尾部对齐、错误优先级和资源限制是本项目明确制定并测试的解析策略，不能将其错误返回行为等同于上游 C API。上游 `librsync.h` 的原始声明为 Martin Pool / Donovan Baarda，`readsums.c` 为 Martin Pool / Andrew Tridgell，均为 LGPL-2.1-or-later；没有变更其声明。适用文本已保留在 `COPYING.LESSER` / `COPYING`，本笔没有新增第三方代码或运行依赖。

## Commit 3 参考构建

固定 e364852674780e43d578e4239128ff7014190ed3 的 CMakeLists.txt、src/rdiff.c 和 src/blake2/blake2b-ref.c 实际用于参考构建；上游源码与二进制留在忽略目录，不进入核心运行依赖。CMakeLists.txt 保留 Adam Schubert / Martin Pool 的 LGPL-2.1-or-later；BLAKE2参考代码 Copyright 2012 Samuel Neves，允许选择 CC0、OpenSSL 或 Apache-2.0，本参考路径按 Apache-2.0 声明保留来源，完整许可见 licenses/Apache-2.0.txt。没有将其统一改标为MIT。tests/fixtures 输入为本项目规则生成，输出由该固定rdiff产生；manifest记录命令、完整版本、长度和SHA-256。数据及常量生成不是MoonBit算法实现或双向互操作证据。

## Commit 4 弱校验移植

固定提交 e364852674780e43d578e4239128ff7014190ed3 的 src/rabinkarp.h、src/rabinkarp.c 与 tests/rabinkarp_test.c 已实际核对。rabinkarp.mbt移植头文件状态、常量和标量公式，不移植C展开更新循环或幂表；保留Donovan Baarda 2019 LGPL-2.1-or-later。rabinkarp_wbtest.mbt的固定向量来自上游测试并保留Donovan Baarda 2003声明，额外独立重算与边界验证为本项目新增。原夹具字节仅扩展搬运old.bin，不重算或刷新上游预期。

## Commit 5 来源

strongsum.mbt是原创LGPL-2.1-or-later内部适配，真实调用既有moonbitstack/mooncrypt@0.4.5的hash/blake2（kind=Blake2b，len=32，无key/salt/person），不是本项目移植BLAKE2b实现；依赖原Apache-2.0声明不变。语义参考固定e364852674780e43d578e4239128ff7014190ed3的src/checksum.c及src/librsync.h：最大强摘要长度32，初始化和最终输出都使用该长度。checksum.c原声明Martin Pool、Andrew Tridgell、Paul Mackerras，LGPL-2.1-or-later；本笔只核对参数语义，未复制其C实现。独立预期来自Python hashlib，输入规则、完整32字节值与Python版本见tests/strongsum-vectors.json，脚本默认只读核验。

## Commit 6 原创组合层

api.mbt、signature.mbt新增生成/预检/内部编码，复用已有Rabin–Karp移植、mooncrypt强摘要适配及wire工具，不重写校验算法。固定上游格式和算法参考版本不变。signature_test.mbt的少量完整字节预期由独立Python struct、标量弱校验及hashlib生成后固化；16例完整上游字节仍来自原夹具，未刷新。Native参考适配只调用公开API；消费脚本的delta与patch始终调用固定rdiff，未移植这些算法。

## Commit 8 Delta 格式来源

继续固定 librsync `e364852674780e43d578e4239128ff7014190ed3`：实际核对 [src/prototab.c](https://github.com/librsync/librsync/blob/e364852674780e43d578e4239128ff7014190ed3/src/prototab.c) 的 opcode 表、[src/patch.c](https://github.com/librsync/librsync/blob/e364852674780e43d578e4239128ff7014190ed3/src/patch.c) 的 offset 后 length 顺序，以及 [src/netint.c](https://github.com/librsync/librsync/blob/e364852674780e43d578e4239128ff7014190ed3/src/netint.c) / [src/emit.c](https://github.com/librsync/librsync/blob/e364852674780e43d578e4239128ff7014190ed3/src/emit.c) 的大端参数与宽度编码。prototab.c 原声明 Martin Pool (2000, 2001, 2014, 2015)、Donovan Baarda (2003)；patch.c 为 Martin Pool (2000, 2001)；netint.c 为 Martin Pool (1999, 2000, 2001)、Andrew Tridgell (1999)；emit.c 为 Martin Pool (2000, 2001, 2004)。均保留 LGPL-2.1-or-later 来源，完整许可仍在 COPYING.LESSER / COPYING。

Delta 及 wire 扩展是依据格式事实的独立 MoonBit 实现，不移植 C patch 状态机，不链接 C librsync。严格 END、零长度拒绝、预算和错误优先级是本项目策略。29 个 opcode 向量由指令表手写十六进制及独立语义，未由被测编码器生成；清单固定长度/SHA-256，校验器默认只读，搬运常量另行核验。16 个 update.delta 仍为固定 rdiff 产物，本笔只搬运并解析，未重算基准或执行 MoonBit 补丁。

## Commit 9 原创补丁执行层

复用 Commit 8 已核对的固定 src/patch.c / prototab.c 格式及原始 basis COPY 语义，固定提交和原 LGPL-2.1-or-later 声明不变；本笔未移植 C 回调、状态机或文件接口。patch.mbt、公开入口和测试为原创组合层，先完整解析并预检，再在内存中复制。new.bin 预期从原 16 个参考文件只读搬运，不由 MoonBit patch 生成；原参考输出、依赖和许可不变。

## Commit 10 Delta 扫描流程参考

实际核对固定 e364852674780e43d578e4239128ff7014190ed3 的 [src/delta.c](https://github.com/librsync/librsync/blob/e364852674780e43d578e4239128ff7014190ed3/src/delta.c)：rs_delta_s_scan/flush 的 rotate/rollout、rs_findmatch 的真实窗口长度与重建、rs_appendmatch 的偏移连续合并。原声明 Copyright (C) 2000, 2001 Martin Pool；Copyright (C) 2003 Donovan Baarda，LGPL-2.1-or-later；许可文本仍在 COPYING.LESSER / COPYING，delta.mbt保留流程来源提示。

新增扫描是基于上述语义的独立全缓冲MoonBit组合实现，复用本项目既有滚动校验、稳定候选索引及标准编码器；不复制C流式tube/scoop状态机、回调或分段常量。共享收费、增量预算检查、新文件视图合并为本项目策略。临时参考适配只调用公开API，rdiff从固定源码构建用于独立消费，无新增运行依赖或许可证替换。

## Commit 11 互操作与确定性输入来源

参考仍为固定librsync v2.3.4/e364852674780e43d578e4239128ff7014190ed3，从既有脚本构建并核验源码、版本与参考BLAKE2编译路径，不使用PATH中未知rdiff。Native适配只调用既有公开signature/delta/patch，核心库及第三方实现未改。Python编排、严格指令检查器、有限穷举及显式LCG32变异规则为本项目测试代码，无额外运行依赖。原16参考数据不刷新，其他预期new由固定独立输入生成器构造，绝不由恢复输出定义。来源/参数/完整计划指纹见tests/interop，运行源码SHA和dirty状态随报告记录，不以本机未提交运行冒充最终同SHA证据。

## Commit 12 资源结构核对

实际读取固定工具链core/builtin/array.mbt的push、reserve_capacity、resize_buffer及容量增长，确认自动追加可能复制活跃前缀；bytes.mbt与bytesview.mbt核对Bytes转换的跨目标复制/独占复用及视图to_owned语义。core原Copyright 2026 International Digital Economy Academy / Apache-2.0及既有NOTICE不变，未复制其实现；本项目新增的是预收费、容量上限和公共接口调用。固定mooncrypt0.4.5的blake2.mbt核对128字节处理缓冲、压缩临时数组和finish副本，不修改其Apache-2.0实现。resources.md的规模关系由这些真实结构推导，不是峰值内存测量或新增第三方代码。

## Commit 13 Native 文件适配来源

实际读取固定core async/fs的File.kind/size/read_at/write/sync/close、kind(follow_symlink=false)、realpath和rename接口，以及runtime/fs.c的Windows/Linux重命名后端。runtime/fs.c原Copyright 2025 International Digital Economy Academy / Apache-2.0，其他core文件原声明及既有LICENSE/NOTICE保留，不复制或修改其实现。Windows使用FileRenameInfoEx Flags=0、旧系统MoveFileEx无REPLACE_EXISTING，Linux调用renameat2/RENAME_NOREPLACE，未知支持时失败；不据参数名空泛宣称所有文件系统安全。

新增CLI参数、限量读取、独占临时发布及烟雾编排为原创LGPL-2.1-or-later适配，算法只调用原三项公开API。Python ctypes与PowerShell权限设置仅在受控测试中证明当前身份不可写并恢复，不进入产品算法，也不修改全局设置。无新增C librsync FFI或第三方运行依赖；实际平台与文件系统边界见docs/cli.md。

## Commit 15 基准与设计说明来源

scripts/benchmark.py、tests/benchmarks/config.json为本项目原创LGPL-2.1-or-later工具/计划。输入用Python标准库hashlib.shake_256的显式域和长度生成，取不相交字节集合及固定修改；不复制外部数据集或Python哈希实现。计时使用标准库perf_counter_ns/subprocess/statistics，运行依赖不进入MoonBit核心。独立new在所有恢复前已确定。既有严格delta检查器复用，不把上游结果当作生成输入的定义。

参考仍为固定librsync2.3.4，Release构建只供对比，不链接进核心，原许可/版权不变。正式CLI和运行库、锁、资源默认值及正式夹具未改。环境、帮助、实际构建命令、可执行文件哈希、原始测量与运行文件指纹见docs/benchmarks.md及忽略产物；基准不是之前阶段已有的证据。

2026-11-09实际读取niuniu513-ask/moon-sync-delta的main/README.md（blob dadc91b71b36bad983d97c34766ce2f7a6a21d2b）用于描述文档中声明的交集，不复制其源码、不宣称执行验证或认可；两个moon_vcdiff候选链接本次404，限制已写入docs/design.md。正式分发包仍须按实际内容进行许可证审计。
