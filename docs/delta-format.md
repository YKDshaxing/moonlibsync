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

## Commit 10：只依赖远端签名的公开 delta

新增 `delta(Bytes, Bytes, Limits) -> Bytes raise SyncError`；两个 Bytes 分别为标准签名和新文件，生成路径不持有 basis。入口顺序为 Limits.validate → parse_signature 完整验证 → max_new_bytes → max_output_bytes → max_delta_bytes 至少5 → 创建一次共享 MatchWork → 非空输入建索引并扫描 → 原 encode_delta。空新文件在签名验证及字节预算通过后返回 magic/END，不建立索引；不跳过损坏或不支持的签名。

扫描不变量：position 指向当前未处理的新字节；弱校验 count 等于窗口真实长度；窗口内容是 new[position:position+count]；已有指令准确覆盖此前新字节，最后一条 literal 视图可继续增长。初始化及匹配后重建取 min(block_len, remaining)，非空匹配先累积 COPY 并推进 count；无匹配且有后续字节时 rotate，EOF 无字节补入时 rollout，二者都前进一字节。循环没有不推进重试。

弱键筛选及配置长度的全部强摘要字节确认后才 COPY，长度取当前窗口 count。记录顺序与最小候选选择不变，不把所有记录假设为完整块，不推断私有尾块长度。短尾移到中间可成为 literal，尾部缩短仍能复用。相邻 literal 共享原输入视图合并；COPY 仅在输出相邻且 basis 偏移连续时受检合并，重复引用同一区间不合并。编码继续选择各参数最短宽度，最终只有一个 END。

max_signature_bytes/records、max_block_bytes 由既有解析器执行；新文件同时受 max_new_bytes、max_output_bytes 限制。共享工作收费详见 matching.md；每次累积按最终合并后的指令数和精确编码大小检查，再允许数组增长，最终编码器门禁不关闭。部分失败只留在局部不可见状态，不改变签名或新文件，也不重置工作预算或回退到完整 literal。

保留原67项，新增13项，共80项。测试检查正常 roundtrip、逐条真实 COPY 内容/范围、输出总长度、literal/COPY合并、确定性及小预算；代表配置 block=1/2/64/2048、strong=1/16/32。八个互异64字节块中插入3字节，预设 COPY下限512、delta<515，实际COPY512、delta18；相同文件及多块修改另要求真实COPY。EOF样例 ABCDxyz→00 80 xyz 的手写预期包含2字节literal及COPY(offset4,length3)。

必要参考方向为固定上游签名+新文件→MoonBit delta→上游patch/cmp，16正式例及13临时复用/短尾例；不比较delta字节同一性。Native参考适配的 delta 分支只读取签名和新文件路径，basis只用于签名准备与上游恢复；输出只写新临时文件，该适配不是产品CLI。没有开展完整反向链、随机矩阵或小文件穷举，也未发布版本。

## Commit 12 资源审计补充

扫描及编码格式不变。修复累积指令Array的容量增长工作：原追加/合并1单位仍涵盖固定元数据动作，增长时另先收新容量+活跃槽搬移，显式reserve后再push；容量被max_instructions截断，替换无需增长费。新编码大小与合并后数量仍在增长之前检查，最终encode_delta完整预检继续保留。首槽新增1使旧精确工作32/82/16变为33/83/17，默认值及其他单位不变。

patch仍先完整parse，再检查全部COPY和输出尺寸，才分配恢复缓冲；解析期间已存在的受限命令不是恢复输出，也不表示所有失败前绝不分配。高位offset先无符号比较，巨长length可能先触发输出预算；零长度和严格END策略不变。资源三点/退化/复用、字节视图保活、标准Array解析容量和结果转换副本详见resources.md。
