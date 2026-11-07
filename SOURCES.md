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
