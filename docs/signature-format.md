# Commit 2：受检整数与内部签名结构解析

本笔基线为 `98b0b59692feabeb66ae39bc649df22ccb32aa26`，工作区开始时干净，origin 为 `git@github-ykd:YKDshaxing/moonlibsync.git`。沿用仓库署名、模块 `YKDshaxing/moonlibsync`、工具链与全部依赖，不新增运行依赖、不升级版本。Commit 1 的历史记录与首次提交前 CI 快照仍保留于 `docs/probes.md`，没有全局改写。

本阶段只实现内部结构解析与固定宽度 u32/u64 wire 工具。没有签名生成、滚动校验、匹配索引、delta 或 patch；没有构建 rdiff、生成互操作夹具、发布包、标签或 Release。手写向量测试通过不等于 rdiff 互操作通过。

## 字节布局与 profile

固定参考 librsync v2.3.4，提交 `e364852674780e43d578e4239128ff7014190ed3`。实际核对 [`src/librsync.h`](https://github.com/librsync/librsync/blob/e364852674780e43d578e4239128ff7014190ed3/src/librsync.h) 的 magic 分类和 [`src/readsums.c`](https://github.com/librsync/librsync/blob/e364852674780e43d578e4239128ff7014190ed3/src/readsums.c) 的读取顺序。来源与声明另见 `SOURCES.md`、`THIRD_PARTY_NOTICES.md`；没有移植 C 状态机。

头部固定 12 字节，全部多字节整数为大端：

| 相对起点 | 宽度 | 字段 | 本项目要求 |
| --- | --- | --- | --- |
| 0 | 4 | magic，u32 | 只接受 `0x72730147` |
| 4 | 4 | block_len，u32 | 大于零，随后检查实现表示范围与项目限制 |
| 8 | 4 | strong_sum_len，u32 | 1–32；零不表示自动选默认值 |

| magic | 上游分类 | 本项目处理 |
| --- | --- | --- |
| `0x72730147` | `RS_RK_BLAKE2_SIG_MAGIC` | 接受头部后继续检查 |
| `0x72730136` | `RS_MD4_SIG_MAGIC` | `UnsupportedSignatureProfile` |
| `0x72730137` | `RS_BLAKE2_SIG_MAGIC` | `UnsupportedSignatureProfile` |
| `0x72730146` | `RS_RK_MD4_SIG_MAGIC` | `UnsupportedSignatureProfile` |
| `0x72730236` | `RS_DELTA_MAGIC` | `InvalidSignature` |
| 其他值 | 未知或其他格式 | `InvalidSignature` |

不以名称、共同前缀或接近的数值推断算法。未读满 12 字节时不会先根据已收到的 magic 分类。

头部后是连续记录，每条恰好 `4 + strong_sum_len` 字节：

| 相对记录起点 | 宽度 | 字段 |
| --- | --- | --- |
| 0 | 4 | weak_sum，完整 u32，大端 |
| 4 | strong_sum_len | strong_sum，原始字节 |

记录区必须整除记录宽度，完整记录后的残缺 weak 或 strong 字节一律为 `TruncatedInput`，不补零、不丢弃尾部。只有合法头部、没有记录的输入可以成功，包括记录数上限为零时；字节和块长限制仍然适用。

## 内部结构与信息边界

`Signature`、`SignatureRecord` 均为私有类型，`parse_signature` 和 wire 函数都是内部函数。未增加公开解析 API，未公开记录数组，`pkg.generated.mbti` 与基线保持一致。

`Signature` 保存经过检查的 magic（UInt32）、block_len（Int32）、strong_sum_len（Int32）及记录。每条记录保存：

- `block_index: Int32`：输入顺序中的零起始序号。
- `nominal_offset: UInt64`：受检的序号乘块长，只是推算位置。
- `weak_sum: UInt32`：原始无符号位模式，`0x80000000`、`0xffffffff` 都是合法值。
- `strong_sum: Bytes`：复制该条记录中的摘要字节，不执行摘要验证。

保留输入顺序和重复记录，不建匹配索引。签名没有 `basis_len`、每块真实长度、显式块偏移或整文件摘要字段，解析器没有向 wire 格式增加这些字段。记录数乘块长不是旧文件真实长度，最后一块可能不足整块；`nominal_offset` 也不证明某个真实 basis 存在、可访问或具有这些字节。仅解析该格式不能认证旧文件身份。

## 整数、位置与写入原子性范围

`read_u32_be` / `write_u32_be` 使用 UInt32，`read_u64_be` / `write_u64_be` 使用 UInt64。逐字节移位和合并不经过浮点，也不把高位 wire 值先转成有符号索引。写入前检查整个输出区间，因此返回错误时不会留下部分修改；这只是内存缓冲区操作的保证，不是文件原子提交保证。

`checked_index` 先在 UInt64 域检查 `value <= 2147483647`，然后才转 Int32。wire 位置参数是 Int64：负值、超出索引表示范围或超过缓冲区末尾的位置返回 `IntegerOutOfRange`；刚好位于末尾的位置合法，但若剩余空间不足 4/8 字节则返回 `TruncatedInput`。

`checked_wire_span` 先证明 `0 <= start <= length`，再比较 `width <= length - start`，不先计算可能溢出的 `offset + width`。索引加法只出现在完整区间检查之后。块偏移先用 `record_index <= UInt64.MAX / block_len` 检查，再执行乘法；零因子的数学乘积为零，但签名中的块长零仍是格式错误。

block_len 在内部需要 Int32 表示。完整且对齐的签名中，`0x80000000..0xffffffff` 的块长返回 `IntegerOutOfRange`，不会先窄化为负数，也不会先按较小的项目块长上限返回资源错误。strong_sum_len 的 u32 最大值先因不在 1–32 内而返回 `InvalidSignature`；weak_sum 则不做有符号索引转换。

## 明确的错误优先级

以下顺序是本项目策略，由竞争错误测试固定，不声称复现上游 C API 的错误顺序：

| 顺序 | 检查 | 失败类别 |
| --- | --- | --- |
| 1 | `Limits::validate()`，沿用其既定字段顺序 | `InvalidOptions(字段名)` |
| 2 | 输入长度不超过 `max_signature_bytes` | `LimitExceeded` |
| 3 | 头部完整达到 12 字节 | `TruncatedInput` |
| 4 | 对完整头部的 magic 分类 | 已知其他签名 profile 为 `UnsupportedSignatureProfile`；其他为 `InvalidSignature` |
| 5 | block_len 非零，strong_sum_len 在 1–32 | `InvalidSignature` |
| 6 | 记录区对齐 | `TruncatedInput` |
| 7 | block_len 能安全表示为内部 Int32 | `IntegerOutOfRange` |
| 8 | 块长上限，然后记录数上限 | `LimitExceeded` |
| 9 | 分配前检查最大名义偏移的 UInt64 乘法 | `IntegerOutOfRange` |
| 10 | 分配记录存储，受检读取并复制各条摘要 | 不忽略尾部，不验证校验和内容 |

因此，非法 Limits 优先于输入预算，输入预算优先于短头部；完整头部的已知不支持 profile 优先于字段错误；字段错误优先于尾部对齐；残缺记录优先于块长表示范围或解析资源上限。格式、数值与资源错误保持独立，不全部折叠成 `InvalidSignature`。

## 真正落实的 Limits

现有字段类型、默认值和合法配置范围保持不变。调用者传入的字节已经存在，解析器在读取头部或进行额外记录分配前检查输入预算；不把它描述成限制调用者最初获取输入时的分配。

| 字段 | 执行位置 | 小输入边界测试 |
| --- | --- | --- |
| `max_signature_bytes` | 所有额外解析分配之前，连短头部也先检查预算 | 输入 17 字节；上限 16 拒绝，17/18 通过，0 拒绝 |
| `max_signature_records` | 记录区对齐并计算记录数后，记录存储分配前 | 2 条记录；上限 1 拒绝，2/3 通过；0 上限接受零条并拒绝一条 |
| `max_block_bytes` | 字段合法且能表示后，记录存储分配前 | 块长 7；上限 6 拒绝，7/8 通过 |

最大偏移的预检覆盖所有更早偏移：块长为正、序号非负，偏移随序号递增。随后每条记录仍使用受检函数。允许名义偏移超出 Int32 索引范围并以 UInt64 保留，例如 3 条记录、块长 2147483647 时第三条偏移是 4294967294；此时没有把它转成某个 basis 字节数组的索引。

其他 Limits 字段只做配置合法性检查，仍未落实为旧/新文件、delta、恢复输出、指令或匹配工作量预算。测试还将这些无关预算设为零进行合法结构解析，防止把名义偏移误作真实旧文件长度。没有进行巨大签名分配来触发数值边界，也没有声明总堆内存或实际运行时间预算已经覆盖。

## 手写向量与测试

新增 `wire_wbtest.mbt` 中 9 项测试、`signature_wbtest.mbt` 中 14 项测试，原有 3 项 Limits 测试保留，共 26 项。数量是当前实际测试项统计，不是验收门槛。

wire 的 6 个手写 u32 向量包含 0、1、`0x7fffffff`、`0x80000000`、`0xffffffff`、`0x01234567`；8 个手写 u64 向量包含 0、1、`0xffffffff`、`0x100000000`、`0x7fffffffffffffff`、`0x8000000000000000`、`0xffffffffffffffff`、`0x0123456789abcdef`。读取分别对照整数预期，写入分别对照手写字节；没有仅用往返自证正确性。起点为零和非零、BytesView 自身有底层偏移、每个截断位置、非法位置、失败后缓冲区不变均有覆盖。

受检转换覆盖 Int32 最大值及其后一个值、u32/u64 高位值；区间边界用合成长度检查；偏移乘法测试包括 `0x5555555555555555 * 3 == UInt64.MAX` 以及其后一个序号溢出、`2^63 * 2`、`2^32 * 2^32` 拒绝，不分配巨大输入。

签名向量直接写出头部和记录十六进制，未使用新 wire 写入器生成：

```text
72 73 01 47 00 00 00 07 00 00 00 01
00 00 00 00 00
80 00 00 00 80
ff ff ff ff ff
ff ff ff ff ff
```

该样本预期 block_len=7、strong_sum_len=1，四条记录弱校验依次为 0、0x80000000、0xffffffff、0xffffffff，摘要依次为 00、80、ff、ff，序号 0–3，名义偏移 0、7、14、21；最后两条重复记录保留。另有 strong_sum_len 为 16、32 的完整手写记录和仅头部的零记录样本。

错误测试覆盖支持/不支持/未知 magic 的头部 0–11 字节、块长零、强摘要长 0/33/u32 最大值、三种已知其他 profile、未知和 delta magic、第一条及完整记录后的每种残缺 weak/strong 长度、三项小预算及竞争错误。连续多次失败后均再解析合法输入，检查没有共享游标或残留记录。

## 执行证据（本笔独立记录）

日期：2026-11-07（Asia/Shanghai）。所有命令先选择本项目 `.toolchain/selected`，实际版本为：

```text
moon 0.1.20261104 (940aa18 2026-11-04)
moonc v0.10.20+65efd5b93 (2026-11-05)
moonrun 0.1.20261104 (940aa18 2026-11-04)
Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

| 环境 / 检查 | 状态 | 证据 |
| --- | --- | --- |
| Windows / Wasm-GC 新增测试初检 | 已通过 | `moon check --target wasm-gc`、`moon test --target wasm-gc` 退出 0；26/26，零警告 |
| Windows / 完整现有检查脚本 | 已通过 | `python scripts/check.py` 退出 0，详见下方逐项目标结果 |
| Windows / Native | 已通过 | check/build/test 均退出 0；`Total tests: 26, passed: 26, failed: 0.`；摘要两条向量完整匹配 |
| Windows / JS | 已通过 | check/build/test 均退出 0；26/26；Node v24.18.0 实际执行，摘要两条向量完整匹配 |
| Windows / Wasm-GC | 已通过 | check/build/test 均退出 0；26/26；固定 moonrun 实际执行，摘要两条向量完整匹配 |
| 格式与依赖 | 已通过 | `moon fmt --check`、固定四包归档/解包源码核验、独立 hashlib 向量均退出 0，无新依赖 |
| 公开接口与基线保护 | 已通过 | `moon info` 前后快照一致；与基线对比无接口差异，锁文件、模块配置和 docs/probes.md 也无改动 |
| Windows / Native 文件探针 | 已通过 | 外部 roundtrip=0、intentional failure=23、缺失文件/父目录=24；stderr 与字节回读均匹配，临时目录清理成功 |
| 同 SHA 的 Windows / Ubuntu CI | 未执行（首次提交前快照） | 推送后核对实际 SHA 的运行记录，在最终交付报告给出链接；[工作流记录](https://github.com/YKDshaxing/moonlibsync/actions/workflows/ci.yml) |

`scripts/check.py` 保留工具链核对、依赖归档及源码完整性、格式、公开接口快照、三目标 check/build/test、摘要探针和 Native 文件探针的全部门禁，只更新阶段名称及完成提示。新增测试自动进入现有矩阵，没有复制一套 CI。为保持内部入口不公开，部分目前只由白盒测试消费的函数/字段使用局部 unused 警告注解；未关闭错误、接口一致性或任一实际测试。

未执行项：rdiff 构建、互操作及参考夹具、签名生成、滚动校验、匹配、delta、patch、性能和完整 CLI 验收。到 Commit 2 完成即止，不自动进入 Commit 3；首版仍未完成。

## Commit 6：公开标准签名生成

新增公开SignatureOptions（block_len:Int64、strong_sum_len:Int64）、default()与signature(Bytes, SignatureOptions, Limits) -> Bytes raise SyncError。默认2048/32；block_len必须正且可表示为Int32，strong_sum_len为1..32；0不表示自动参数。内部Signature、记录、解析器、wire及校验入口不公开，没有delta或patch声明。

生成错误优先级独立于解析：Limits::validate既定顺序 → block_len正值 → strong_sum_len范围 → 块长实现表示范围 → max_old_bytes → max_block_bytes → max_signature_records → 输出乘加及Int32表示范围 → max_signature_bytes。非法选项返回InvalidOptions(字段名)，表示范围错误为IntegerOutOfRange，预算错误为LimitExceeded；原解析优先级不变。

记录数按整除加余数计算，不做basis_len+block_len-1；输出乘法先用UInt64除法界限检查，再证明body<=UInt64.MAX-12，最后检查Int32索引范围。所有预算和表示检查都在输出分配及摘要计算前完成。块结束位置先比较剩余长度，完整块不额外追加空记录，短尾块不补零。空basis只有12字节头，但仍需合法选项、块长预算、至少12字节输出预算，记录预算0可接受空输出记录区。

复用RabinKarp、strong_sum和大端wire工具写出0x72730147头及原顺序记录，不增加basis_len、真实尾块长度、显式偏移或整文件摘要。内部encode_signature复用头/记录写入能力，验证解析后重编码完全一致，不增加公开序列化API。其他Limits仍不代表匹配、指令、delta或恢复的预算实现。

新增5项测试（2项公开黑盒、3项白盒），保留原38项，共43项。黑盒覆盖block=1/2/64/2048、strong=1/16/32，输入长度0/1/B-1/B/B+1/2B-1/2B及确定性字节。保存空、单记录、多记录及短尾块完整字节样本，预期由独立Python标量弱校验与hashlib一次核算后固化，并与16例上游完整签名交叉验证。小预算测试涵盖四项生成限制、空文件预算、零记录上限、错误恢复；算术极值在内部size预检测试，不申请巨大数组。

Linux scripts/consume_signature.py先核对固定moonc、依赖及夹具，用隔离Native包probes/signature通过公开API生成临时签名；固定源码e364852674780e43d578e4239128ff7014190ed3的绝对路径rdiff重新生成签名并完整比较，再执行delta、patch、cmp。16例固定数据加66个去重临时参数用例均已在本机WSL通过，共82次上游消费验证。该Native工具只写本次临时目录，CreateNew避免覆盖；不是产品CLI，不参与JS/Wasm-GC核心编译。

本地完整检查：Native、JS、Wasm-GC各43/43，接口生成审查仅新增上述配置及signature，快照门禁保留；正式16例64文件12507字节及manifest、依赖版本、锁文件和校验算法不变。Linux参考CI接入相同哈希锁定工具链，在原重建/损坏副本门禁后执行消费脚本；同SHA结果以最终交付报告为准。本阶段只完成signature，MoonBit delta、patch、候选匹配及双向互操作未实现，0.1.0仍未完成。

## Commit 12 资源审计补充

公开signature的basis/块/记录/输出预检及原错误顺序不变，输出缓冲与摘要工作只在plan通过后开始。parse_signature先完成字节、头部、对齐、表示、块/记录预算和最大名义偏移预检，才按已知count精确保留记录槽，再逐条复制strong子区间；65条的记录容量为65。signature不收匹配工作，未适用的合法0字段不误限，但所有字段仍配置校验。完整九字段契约、三点测试、摘要依赖临时对象和最终Bytes转换副本见resources.md；不把最终签名字节上限等同峰值堆内存。
