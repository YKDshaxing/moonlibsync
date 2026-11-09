# Commit 12：资源契约与全量缓冲内存模型

基线 ebca75e597be8a43c88e957f97a22de217beee2c。三项公开 API、SignatureOptions、默认2048/32、标准格式、严格END、稳定候选选择及依赖均不变。全部入口先Limits.validate；随后只使用该操作适用字段。下表的大小指逻辑字节或项目数量，不是总堆或总CPU上限。

## 九个字段与适用范围

所有字段是Int64配置值，合法范围0..2147483647，只有max_block_bytes必须1..2147483647。配置非法返回InvalidOptions(字段名)，包括在该操作中不适用的字段。默认值未提高。

| 字段 | 默认值 | 单位 | signature | delta | patch |
| --- | --- | --- | --- | --- | --- |
| max_old_bytes | 67108864 | 字节 | basis输入 | 不读取basis | basis输入 |
| max_new_bytes | 67108864 | 字节 | 不适用 | new输入 | 不适用 |
| max_signature_bytes | 16777216 | 字节 | 签名输出 | 签名输入 | 不适用 |
| max_signature_records | 1000000 | 条 | 生成记录 | 解析及索引记录 | 不适用 |
| max_block_bytes | 1048576 | 字节 | 生成块长 | 签名块长 | 不适用 |
| max_delta_bytes | 83886080 | 字节 | 不适用 | 编码输出，含magic/END | delta输入，含magic/END |
| max_output_bytes | 67108864 | 字节 | 不适用 | 预计恢复长度，即new长度 | 恢复输出 |
| max_instructions | 1000000 | 条 | 不适用 | 最终保留的合并后数据指令 | 解析的literal/COPY，不含END |
| max_match_work | 268435456 | 逻辑工作单位 | 不适用 | 索引、匹配、扫描、指令及其容量增长 | 不适用 |

项目预算不足为LimitExceeded；必要整数表示、受检乘加或索引失败为IntegerOutOfRange。格式和范围错误保持InvalidSignature、UnsupportedSignatureProfile、InvalidDelta、InvalidOpcode、TruncatedInput、TrailingData、CopyOutOfBounds各自分类，不合并成资源错误。

## 实际检查时机与限制对象

以下记basis长度O、块长B、记录数n、强摘要长度s、编码字节Z。

| 阶段 | 分配/工作之前的检查 | 规模约束 |
| --- | --- | --- |
| signature_plan | 配置、选项及表示范围、basis、块、记录数、输出乘加/索引、签名字节预算 | count=ceil(O/B)，Z=12+count*(4+s)；计算不先窄化或溢出 |
| signature输出与摘要 | 完整plan通过才signature_header和逐块hash | 输出固定Z字节，真实尾块不补零；不消耗匹配工作 |
| parse_signature | 输入预算、完整头/profile、字段、记录对齐、块表示/预算、记录预算、最大名义偏移 | 通过后精确分配n个记录槽，再逐条复制s字节摘要；不按UInt32值域分配 |
| build_signature_index | 3*n工作单位在两次n槽分配前预收 | 两个Int32排序数组；只排序号，不复制第二份摘要；比较/写入继续逐动作收费 |
| delta入口 | 配置、完整签名解析，再new长度和预计恢复长度、至少5字节编码预算 | 签名解析可能已产生受限记录存储，才发现new预算不足 |
| delta扫描/累积 | 查询/摘要/滚动更新先收费；替换或追加前检查合并后的编码大小和逻辑指令数 | literal为原new视图；增量size始终含magic与END；不在末尾才拒绝海量指令 |
| 指令容量增长 | 原追加动作收费后，先检查字节/指令，再预收新容量槽数+搬移的活跃槽数 | 首槽容量1，之后倍增但不超过max_instructions；reserve完成才push，替换不扩容 |
| encode_delta | 配置、指令数、每条非零长度、预计输出及编码乘加、delta字节、输出索引 | 所有输出分配前预检完成；保留原最短编码，不受新增计量替代 |
| patch入口及解析 | 配置、basis预算，再parse_delta完整通过END/尾随 | 命令存储由输入字节、指令数及预计输出约束；此前合法前缀可能已分配元数据 |
| patch_size与执行 | 全部COPY在UInt64域检查offset≤basis_len、length≤basis_len−offset，减法形式累计输出，再索引转换 | 通过后才分配恢复缓冲；只读原basis，失败不返回半成品 |

“预检”针对对应阶段，不表示任何失败前都不分配。索引初始分配收费通过后，后续排序可再因工作不足失败；完整delta解析可先保存受限命令，再因尾部损坏失败。所有这类局部状态不向调用者暴露，也不污染下次独立调用。

内部wire只接受1/2/4/8大端宽度，先检查完整跨度与值域再读写，失败写入不留半个参数；它不自行读取Limits。read/write、checked_index、checked_block_offset、checked_match_end由调用者组合。内部parse_delta限制delta输入、数据指令和预计输出；encode_delta限制输出delta及同口径指令/预计输出，不接收basis。内部parse_signature/encode_signature执行签名字节、记录、块预算；它们不替代公开入口的basis/new预算，也不认证真实basis身份。

## 工作审计及实际修复

Commit7/10既有单位保持：索引初始化3*n；归并每比较/写入1；二分探测1；弱组存在检查1；每窗口强摘要1+真实窗口字节数（不是截断摘要长度）；每候选1；完整比较预收s；窗口建立/重建1+实际字节数；调度1；rotate3；rollout2；追加/合并有界元数据动作1。未命中也收费，无弱候选不哈希，同一窗口候选再多也只计算一次强摘要。一次公开delta仅一个MatchWork，所有阶段共享；失败收费不扣该次不足的动作，已扣不退，辅助函数不重置，超限不回退literal。

实际缺口是原追加动作中Array.push可能触发O(k)搬移，但只计1单位。先加入失败回归，旧代码在预算3（追加1+新槽2+搬移1实际需4）时意外成功，80旧项通过且新回归失败。修复为显式保留容量：容量不足时先收new_capacity+live_length，再reserve_capacity和push；扩容时活跃前缀长度等于旧容量，内部搬移逐槽已计量。新容量用Int64倍增并截断到已验证指令上限，转换受检。该计量按槽访问抽象，不是分配器耗时或CPU周期。记录解析另在已知count预检后精确预留，避免动态倍增多余槽；65条记录现在容量65，而不是自动扩为128。

原单abc/3/16精确工作32→33；三候选末条命中82→83；空索引abc纯literal16→17，均因为首个新槽新增1单位。这是新增动作的推导，不是提高预算绕过失败；默认值、既有查询/摘要单位和格式错误顺序未改。后续扩容费用依真实活跃槽数及新容量计，不被固定1掩盖。替换/连续COPY合并不追加容量费用，低指令上限仍允许真正连续块合并。

计量之外的签名解析受字节/记录/块约束，最终编码及复制受指令和字节约束，signature与patch不强行引入匹配预算。常数次元数据动作、运行时引用处理及回收不是全库CPU契约。本审计不将max_match_work称为总分配量、总CPU或精确时间限制。

## 集中测试与错误优先级

resources_wbtest.mbt新增19项，与原80项合计99项。以下16项适用关系均用need−1拒绝、need通过、need+1通过验证；测试向量小，精确需求独立由wire长度或既有单位推导。

| 入口/向量 | 字段及need |
| --- | --- |
| signature，abc，block2/strong16 | old3、block2、records2、signature_bytes52（12+2*(4+16)） |
| delta，abc签名block3/strong16，new=abc | signature_bytes32、records1、block3、new3、output3、delta_bytes8、instructions1、match_work33 |
| patch，literal X + COPY(0,3)，basis abc | old3、delta_bytes10、output4、instructions2 |

空签名12字节、空delta5字节另作少1/等于/多1；零记录允许空区，零输出/零指令允许空恢复，END不计数。空new仍解析签名，但跳过索引/扫描，工作0可以通过。不适用的合法0字段不误限其他操作；九字段负值及大于Int32上界在三入口均拒绝。max_block_bytes=0本身非法，返回InvalidOptions而非LimitExceeded。

公开检查顺序保持：

- signature：全部配置→block选项→strong选项→必要表示→old预算→block预算→记录预算→输出表示→签名字节预算；例如巨大block先返回IntegerOutOfRange，不能因同时old不足统一写成LimitExceeded。
- delta：全部配置→完整签名解析的原顺序→new预算→output预算→delta至少5→共享预算及扫描。签名输入预算先于头部截断；记录对齐先于block窄化，所以高位block配截断记录仍是TruncatedInput，完整头才是IntegerOutOfRange。
- patch：全部配置→basis预算→完整delta解析→COPY与输出预检→分配。完整parse优先于早期坏COPY，因此尾随数据/截断/保留opcode可以先返回；大length先被预计输出预算拦截，高offset且小length再返回CopyOutOfBounds，零length仍InvalidDelta。

19项还覆盖128个同弱键/31字节相同前缀且末尾不同的攻击元数据、全部不匹配/末候选成功、64次重复窗口与不可合并COPY、512字节连续miss、窗口实际输入长度（包括256字节窗口、仅1字节摘要前缀仍预收257哈希单位）、无力支付rollout、扩容前余额/容量/长度/size不变、容量上限、UInt64/乘加/索引/写入极值及三操作交错失败复用。人工签名通过真实格式解析，不冒称真实不同内容的弱校验碰撞。精确例：128条索引1728，完整查询4237且只哈希一次；最后比较少1时保留31不够支付32，不发生退款。64重复窗口总2942含190扩容单位；512无匹配总2562含rotate和EOF。拒绝位置由余额及实际控制流证明，不以墙钟快慢或OOM判断。

旧80项保留，其中涉及新增费用的精确边界更新推导；原6项Python工具检查保留。scripts/check.py仍每目标执行一次无过滤全套测试，复用同次stdout统计19资源项及总99，不另外跑资源矩阵。_build/resources/report.json和三目标日志记录实际退出码、观察总数、源码SHA/dirty和三点契约数；与_build/interop报告分别统计，CI在现有Windows/Ubuntu任务保存资源产物。

## 全量缓冲内存模型（结构推导，未测量峰值）

记O=basis字节，N=new字节，S=签名输入字节，n=记录数，s=摘要长度，K=最终指令数，D=delta输入字节，Z=编码输出字节，R=恢复字节。下列是主要活跃结构关系，不是实测堆峰值：

| 路径 | 可能同时持有的主要结构 |
| --- | --- |
| signature | 调用者O；输出固定缓冲Z；转换中的结果Bytes最多再Z；每块RabinKarp及BLAKE2b状态/128字节块缓冲、压缩临时数组及32字节摘要/前缀 |
| delta解析/索引 | 调用者S与N；n个记录对象和n*s摘要副本；索引排序期间两个n槽Int32数组，返回索引复用记录/摘要 |
| delta扫描/编码 | 上述记录/索引；C槽命令数组和K个枚举/视图元数据；编码缓冲Z及转换结果至多再Z；扩容期间旧C与新容量短暂并存；单窗口摘要状态 |
| patch | 调用者O及D；解析命令数组与literal借用视图；通过全部预检后的R缓冲，转换中最多再R结果Bytes |

signature输出大小Z=12+n*(4+s)。解析记录槽精确n，摘要副本合计n*s；无第二份完整候选摘要。生成命令容量C不超过max_instructions，几何保留使其为O(K)，扩容期间新旧都可能存活；解析delta使用标准Array增长，K>0时容量规模不超过max(8,2*K)，逻辑指令限制不是该运行时容量本身。记录对象、枚举、视图、数组头、对齐及引用的实际字节另计。排序及生成保留关系是线性规模，不按2^32开表。

literal视图不复制payload，却可能保活整个new或delta输入。最终Bytes::from_array在固定core的JS/Wasm-GC路径会复制；Native在独占且覆盖完整底层数组时可能复用，不能据此保证所有目标只有一个输出副本。BytesView::to_owned整段可共享原Bytes，子区间通常分配；解析签名的strong区间是子区间，确实产生每记录副本。固定mooncrypt按128字节块处理消息，当前可达摘要状态大小有界，但每次压缩有临时对象，未回收垃圾及收集器时机另计，不推断全进程常量内存。

输入Bytes在调用前已经由调用者获取；输入上限无法阻止此前的分配。单字段上限不限制全部同时存活结构、容器容量、运行时/依赖开销、其他线程或进程内对象。全量缓冲API不承诺常量内存流式处理。普通不可信输入错误用SyncError返回，不承诺操作系统内存耗尽也能转换成普通错误并恢复。本轮没有执行OOM或峰值堆测量，未把这些结构推导写成实测数字。

## 必需回归范围与停止边界

完整保留274独立输入、496参数用例、3968恢复、八组合各496的互操作计划和固定指纹；随机/穷举/短摘要不删减，不给无限预算。原82次签名消费、29次delta验证、参考重建、两类损坏副本拒绝、工具缺失/比较失败门禁及门禁后正常恢复继续执行。默认预算下的实际同SHA结果见交付报告及CI产物。止于Commit12，正式CLI、流式API、最终跨目标交付、打包发布及0.1.0验收不在本笔完成范围。

## Commit 13 文件适配补充

核心资源默认值及上述99项库测试不变。CLI只在Native包引入文件系统，用公开API计算；读入前检查普通文件和同一打开句柄初始大小N，已知超限不分配N，实际分块读取至N并额外用1字节EOF探针检查增长，再复核大小，所有正常/异常路径关闭。增长或截短拒绝，不追随新增内容；同大小并发修改不提供快照保证。CLI的OLD/NEW/SIG/DELTA分别对应原输入上限，不新增核心IO错误或配置。

CLI读取缓冲和最终Bytes可能短暂共存，两个输入、核心中间结构及结果也可能共存；有界读入不是常量内存算法或进程总内存限制。输出同目录CreateNew临时文件及无覆盖重命名保证边界见cli.md，文件sync不等于父目录持久化。本机DrvFS不支持该Linux提交操作时明确失败，不通过降低安全性来让测试通过。

scripts/check.py现显式选择根库包完整99项，避免把Native CLI专属6项加进JS/Wasm-GC资源报告。CLI真实二进制烟雾另报平台场景数，6项Python互操作工具另计，原完整互操作规模不变。

## Commit 15 冻结与测量口径

本次冻结上述九字段原默认值、适用阶段、错误与共享收费，不提高预算或改用新资源模型。实际基准仅观测同一Linux Native文件流程耗时及字节/COPY/指令数量，原始轮次与方法见[基准](benchmarks.md)。没有测量运行时堆峰值、RSS峰值或CPU周期，不能用这些时间或文件大小替代本页的全量缓冲/中间结构推导。失败或未校验样本禁止进入成功统计；没有通过超限后丢弃样本改善数字。首版冻结不改变资源失败后的独立调用复用契约。
