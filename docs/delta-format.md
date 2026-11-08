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
