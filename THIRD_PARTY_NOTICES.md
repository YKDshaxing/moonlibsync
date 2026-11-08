# 第三方声明

本项目原创文件的 LGPL-2.1-or-later 声明不适用于第三方作品及其许可文本。下载的源码和工具链保存在忽略目录中；以下是已采用的依赖和实际调用范围。

| 作品 | 版本 | 原始声明 | 用途 |
| --- | --- | --- | --- |
| moonbitstack/mooncrypt | 0.4.5 | Copyright 2026 Leo Cheng；Apache-2.0 | `hash/blake2` 和其 `spec` 依赖，纯 MoonBit 摘要探针 |
| moonbitstack/moonbase | 0.4.2 | Copyright 2026 Leo Cheng；Apache-2.0 | 模块依赖闭包；不代表全包测试通过 |
| moonbitstack/moondate | 0.1.0 | Copyright 2026 Leo Cheng；Apache-2.0 | 模块依赖闭包 |
| moonbitstack/moonrand | 0.1.0 | Copyright 2026 Leo Cheng；Apache-2.0 | 模块依赖闭包 |
| moonbitlang/core | 0.10.20+65efd5b93 | International Digital Economy Academy 等贡献者；Apache-2.0，详见原始 NOTICE | 工具链配套标准库与 Native 系统接口 |
| librsync | v2.3.4 / e364852674780e43d578e4239128ff7014190ed3 | 保留上游 COPYING 中 LGPL v2.1 文本 | 读取 librsync.h、readsums.c 核对签名布局与 magic；无 C 代码移植或链接 |

完整 Apache-2.0 文本见 `licenses/Apache-2.0.txt`，core 的原始声明见 `licenses/MoonBit-core-LICENSE` 与 `licenses/MoonBit-core-NOTICE`。本仓库没有分发 mooncrypt 实现副本或工具链二进制，也没有修改依赖源码的版权头。所有固定包的许可证和压缩包校验值还记录在 `dependencies.lock.json` 中。

`moonbitlang/x@0.5.7` 在调查中安装并检查过文件 API，但最终未采用：固定工具链的 `core/async/fs`、`core/env`、`core/async/stdio` 已提供本笔所需能力。它不属于本模块最终依赖闭包。

Python hashlib 只作为开发阶段独立向量来源，不复制其实现或链接 Python 到 MoonBit 核心；许可证与算法参考链接见 `SOURCES.md`。没有用 C librsync FFI 替代核心。

Commit 2 的格式参考包括 `src/readsums.c`，其头部保留 Martin Pool、Andrew Tridgell 的版权及 LGPL-2.1-or-later 声明；本项目仅据此核对格式事实，受检整数与内部解析器独立实现，没有复制上游状态机或覆盖其版权。固定文件链接与实际使用程度见 `SOURCES.md` 的 Commit 2 记录。

Commit 3 在忽略目录构建固定 librsync 源码，保留 LGPL-2.1-or-later 声明。内置 src/blake2/blake2b-ref.c 为 Samuel Neves 2012 作品，原声明可选 CC0、OpenSSL、Apache-2.0，本参考路径保留 Apache-2.0 选择与来源；未复制其实现到MoonBit核心。完整许可证文本已在 licenses/Apache-2.0.txt 保存。夹具输入为本项目自有规则数据，参考输出可追溯至 manifest 的固定源码和命令。

Commit 4 将固定librsync src/rabinkarp.h的标量状态公式移植至MoonBit，保留Copyright (C) 2019 Donovan Baarda；固定测试向量保留tests/rabinkarp_test.c的Copyright (C) 2003 Donovan Baarda。许可均为LGPL-2.1-or-later，完整文本保存在COPYING.LESSER / COPYING；未重标为MIT，未移植展开循环或性能表。

Commit 5新增原创适配胶合层，BLAKE2实现仍属于mooncrypt 0.4.5，保留Apache-2.0声明，未冒称自行移植。固定librsync checksum.c的LGPL-2.1-or-later参数语义仅供参考，原版权为Martin Pool、Andrew Tridgell、Paul Mackerras；相关完整许可已保留。Python hashlib仅用于离线独立向量，不复制其实现到核心。

Commit 6仅新增原创签名生成胶合层、预算预检、公开配置和参考适配工具，采用项目LGPL-2.1-or-later；复用依赖及弱校验的原声明不变，没有新增第三方实现或运行依赖。固定rdiff只在参考验证中消费签名，未把其delta/patch链接或移植到核心。

Commit 8 依据固定 librsync prototab.c、patch.c、netint.c、emit.c 核对 opcode、大端参数及 COPY 顺序，原创 MoonBit 编解码器不复制 C 状态机。原声明分别为 Martin Pool / Donovan Baarda、Martin Pool、Martin Pool / Andrew Tridgell、Martin Pool，均 LGPL-2.1-or-later；年份、固定文件链接和使用程度见 SOURCES.md 的 Commit 8 记录，完整许可见 COPYING.LESSER / COPYING。手写 opcode 数据和预算策略为本项目新增，无新增第三方运行依赖或许可证替换。

Commit 10 核对固定librsync src/delta.c的扫描、EOF和连续COPY语义，保留Martin Pool (2000, 2001)、Donovan Baarda (2003)及LGPL-2.1-or-later来源声明，完整许可见COPYING.LESSER / COPYING，固定链接及使用程度见SOURCES.md。新增全缓冲扫描、预算与合并胶合层为独立MoonBit实现，不复制C流式状态机；既有Rabin–Karp移植和mooncrypt摘要的原声明不变，无新增第三方运行依赖。
