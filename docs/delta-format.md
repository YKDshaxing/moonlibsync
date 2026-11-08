# Commit 8：内部标准 Delta 格式

固定 librsync v2.3.4 / e364852674780e43d578e4239128ff7014190ed3，格式来源及声明见 ../SOURCES.md。内部模型为 Literal(BytesView) / Copy(UInt64 offset, UInt64 length)，END 不存入数组。无 basis 参数，解析成功只表示格式及项目预算通过，不表示某个真实 basis 上可以执行补丁。不计算 offset+length、不执行 COPY、不分配恢复输出。

## 指令及最短编码

大端 u32 magic `0x72730236`，随后零条或多条数据指令，最终一个 `0x00` END。空 delta 为 `72 73 02 36 00`。literal 内容按声明长度消费，其中 00 是数据。

| opcode | 内容 |
| --- | --- |
| 01–40 | opcode 即 literal 长度 1–64，随后 payload |
| 41 / 42 / 43 / 44 | 1 / 2 / 4 / 8 字节无符号长度，随后 payload |
| 45–54 | 先 offset，后 length，宽度见下表 |
| 55–ff | 保留，InvalidOpcode |

| offset 宽度＼length 宽度 | 1 | 2 | 4 | 8 |
| --- | --- | --- | --- | --- |
| 1 | 45 | 46 | 47 | 48 |
| 2 | 49 | 4a | 4b | 4c |
| 4 | 4d | 4e | 4f | 50 |
| 8 | 51 | 52 | 53 | 54 |

多字节参数均大端。解析接受合法非最短宽度；编码 literal 1–64 用直接 opcode，65–255 用 41，256–65535 用 42，65536–0xffffffff 用 43，更大用 44。COPY 两个参数各自选择最短 1/2/4/8 字节宽度。offset=0 合法，任何 length=0 返回 InvalidDelta。不合并相邻指令。大参数测试仅用小文件、宽度选择及头部写入，不申请 GiB payload。

## 检查顺序

解析优先返回先遇到的错误：

1. Limits.validate，再检查完整输入大小 max_delta_bytes。
2. 至少四字节 magic：不足 TruncatedInput，完整但不符 InvalidDelta。
3. 读 opcode：END 立即检查余下字节，任何尾部为 TrailingData；保留 opcode 为 InvalidOpcode。
4. 完整读取全部参数，包括 COPY 第二参数；不足为 TruncatedInput，数值保持 UInt64。
5. 零长度 InvalidDelta；随后检查 max_instructions、累计预计输出 max_output_bytes。
6. literal 再作必要索引转换、完整 payload 检查，不足为 TruncatedInput；通过后保存借用视图。COPY 保存宽参数，不窄化为 Int。
7. 到达输入末尾仍没有 END 返回 TruncatedInput。

所以巨大长度且缺少 payload 可先因输出预算返回 LimitExceeded；完整参数读取、零长度拒绝均先于指令预算。END 不消耗指令数或输出预算，零指令预算允许空 delta。输入字节预算包括 magic 和 END。

编码先 validate，再检查总指令数，逐条检查非零长度和输出预算，预计算编码大小（起始 5 字节包含 magic/END），最后检查 max_delta_bytes、受检索引转换并分配编码缓冲区。编码与解析的跨类别错误优先级不强求相同。输出长度在加法前用 `length <= maximum - accumulated` 检查；编码大小每次加法检查 UInt64 剩余范围。必要表示或整数运算失败为 IntegerOutOfRange，项目预算不足为 LimitExceeded。

底层 wire 只接受 1/2/4/8 宽度，写入前验证完整空间及数值可表示性，失败不留下部分参数。所有 Limits 字段、默认值、合法范围不变。literal 在输出预算后才窄化，数组 push 前完成预算检查；literal 借用不可变输入，避免重复复制。编码分配的是预检大小的 delta 字节，并非恢复输出。

## 验证边界

29 个独立手写向量及 manifest 位于 tests/fixtures/opcodes；另有直接 literal 全覆盖及固定规则 payload 边界测试。16 个原始 update.delta 离线搬运并比较解析/重编码后的逐条指令语义，不要求非最短输入保留原始字节。失败后合法调用检查无残留游标。原 51 项保留，新增 7 项，共 58 项；实际本机与同 SHA 云端结果由交付报告提供。原 82 次上游签名消费中的 delta/patch 均由 rdiff 执行，不是 MoonBit 补丁能力证据。

## Commit 9：公开 patch 与恢复边界

此前章节描述 Commit 8 的格式编解码，原解析策略不变。新增公开 `patch(Bytes, Bytes, Limits) -> Bytes raise SyncError`；内部模型和执行计划不公开，不需要签名、不访问文件系统。

入口检查顺序为：Limits.validate → basis 的 max_old_bytes → parse_delta 完整解析 → 遍历所有指令检查 COPY 范围并累计最终输出 → 受检输出索引转换 → 分配恢复缓冲区 → 顺序复制 → 返回完整 Bytes。basis 预算与错误 magic 并存时先返回 LimitExceeded；配置本身不合法则先返回 InvalidOptions。即使前面 COPY 越界，后面格式错误也由完整解析先返回；例如尾随数据为 TrailingData。解析器已有的参数、零长度、指令数、预计输出、payload 和 END 优先级不变。

COPY 在 UInt64 域先证明 `offset <= basis_len`、`length <= basis_len - offset`，才允许窄化和索引；不先求 offset+length。失败为 CopyOutOfBounds，包括 offset 等于末尾但 length 正、空 basis 上非空 COPY、高位及最大 UInt64 offset。零长度仍由解析器返回 InvalidDelta；巨大 length 可先因输出预算返回 LimitExceeded。累计长度在加法前用 delta_add_output 的减法比较预检。全部指令范围及输出预算在恢复分配前通过，不向调用者返回半成品。

执行只从不可变原 basis 或 literal 视图读取，绝不从恢复输出读取。允许非顺序、重复、重叠的 basis 区间；literal 保留零字节和高位字节。恢复缓冲区按最终长度一次构造并顺序写入，最后转为独立 Bytes，无中间字符串转换或反复 Bytes 拼接；输入不修改，无跨调用可变状态。

max_old_bytes 限制 basis，max_delta_bytes 含 magic/END，max_instructions 只统计数据指令，max_output_bytes 限制恢复长度。max_new_bytes 和 max_match_work 不用于 patch；Limits 字段、默认值和合法范围不变。只有 magic/END 的空 delta 可以在零指令/输出预算下返回空 Bytes，但仍检查 basis 和 delta 字节预算。

标准 delta 不携带 basis 身份认证。范围合法的错误 basis 可以成功执行但恢复错误内容；整体内容校验由应用在标准格式外承担，不增加私有摘要字段。

原 58 项保留，新增 9 项，共 67 项：8 项公开黑盒验证手写正常/错误/预算/复用及全部 16 种 COPY 宽度，1 项调用公开 patch 恢复全部 16 个原始上游 delta，并与独立搬运的 new.bin 逐字节比较。生成器只搬运已核验文件，不调用 patch 生成预期。该证据是“MoonBit patch 恢复固定上游 delta”，并非两条互操作链完成；无公开 delta 生成、扫描、CLI 或发布。
