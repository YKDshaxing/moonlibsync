# 0.1.0 兼容范围与发布归属

## Commit 19 开发源码准备对象（尚未发布）

新增 prepare_signature 与不透明 PreparedSignature；完整解析及受限稳定索引复用既有实现，内部保留真实签名字节数、签名元数据/记录及最终排序，外部不暴露字段或构造器。无basis、MatchWork或扫描状态；默认值、原六项操作、检查CLI、错误顺序及一次性delta预算不变。公开黑盒持有与三目标内部只读查询验证生命周期及封装，不宣称线程安全。

本笔尚无 PreparedSignature::delta，复用生成和有限基准留待Commit20；不加入新CLI、清单或流式处理。注册表0.1.0不含此API，元数据版本与原包归档不变，不修改历史基准或发布证明。下文各Commit段的未实现项仍指当时范围。

## Commit 18 开发源码检查 CLI（尚未发布）

新增 inspect-signature、inspect-delta、check-patch 三个只读命令，及检查专用 --json。核心 API 与 Commit 17 一致，原三个文件命令、默认值、输出保护、退出0/2/1与输入链接策略保留。检查不创建输出文件；check-patch 只取 OLD 元数据，有界读取 DELTA，不认证内容或提供快照。schema 1 的 Int64 全为精确十进制字符串；失败仍 stderr 诊断、stdout 为空，stdout 通道失败非零。详细字段与路径选项语义见[CLI说明](cli.md#commit-18开发源码检查命令)。

这些功能只在开发源码，注册表0.1.0仍只有原三个文件命令。版本元数据、原包归档、许可证和发布证据不变；本笔不发布或创建标签/Release，不进入Commit19。原Windows/Ubuntu任务接入新增CLI检查，不复制CI矩阵。下文保留各阶段范围。

## Commit 17 开发源码增量（尚未发布）

当前 Git 源码新增 `inspect_signature(Bytes, Limits)`、`inspect_delta(Bytes, Limits)`、`check_patch(Int64, Bytes, Limits)` 及三个不可变摘要类型，返回/字段见[设计说明](design.md#commit-17开发源码只读检查)。注册表 0.1.0、其正式源码 SHA 和归档仍保留原三项操作，不能将当前元数据中的 0.1.0 解释为这些新增接口已发布。拟定 0.2.0 仍在开发。

新入口沿用固定工具链、RK+BLAKE2 profile、标准 delta 全部 opcode、严格 END 和原资源/错误策略；原三项公开声明、默认值、候选顺序、工作计量及 CLI 文件行为不变。格式检查接受结构合法的高位 UInt64 COPY offset，范围预检才按显式 basis 长度拒绝越界。签名不能推断真实 basis 长度；预检不认证身份或内容。Native/JS/Wasm-GC 使用原完整矩阵加入新测试，没有新增目标或文件系统保证。

本笔只到核心检查 API；JSON CLI（Commit 18）、PreparedSignature、完整性清单、自动块长和流式处理均未实现，不进行发布、标签或 Release 操作。下文保留原阶段事实和冻结/发布归属。

三项公开字节API已实现，核心Native/JS/Wasm-GC检查与Linux Native固定rdiff互操作分别执行；当前入口与边界见[README](../README.md)、[资源契约](resources.md)、[CLI](cli.md)、[九项验收表](contest-acceptance.md)。固定工具链不表示全部更高版本兼容；Commit15完成有限基准与功能冻结；Commit16的实际包审计、上传和独立注册表消费按[发布验收](release.md)及交付记录区分。

以下各Commit章节保留对应阶段事实，“当前/未完成”仅指该阶段，不作为当前能力限制；原README早期阶段全文另存[历史快照](history.md)。

# Commit 3：固定参考与离线夹具

基线 66ffddb29fdfdc50cdb583a274c60c59a76f92e0。工具链、核心依赖、公开接口及 Commit 1/2 历史文档保持不变。

参考源码：https://github.com/librsync/librsync ，v2.3.4，完整提交 e364852674780e43d578e4239128ff7014190ed3。实际核对固定 CMakeLists.txt 后选择 Release、BUILD_SHARED_LIBS=OFF、BUILD_RDIFF=ON、USE_LIBB2=OFF、ENABLE_COMPRESSION=OFF、ENABLE_TRACE=OFF。BLAKE2 实际编译 src/blake2/blake2b-ref.c，不使用系统 rdiff。脚本验证源码 HEAD、内容无差异、版本和 compile_commands.json。

本机 Ubuntu 24.04 WSL2，GNU C 13.3.0，CMake 3.28.4 Linux wheel，libpopt-dev 1.19+dfsg-1build1。WSL 软件源更新失败且旧包索引有失效 URL，改经 Windows 网络取得 CMake wheel 与官方 Ubuntu POPT 包后在 WSL 实际构建，未更换参考版本。完整构建参数、依赖版本、绝对工具路径和完整 rdiff --version 输出保存在忽略目录 .toolchain/reference/build.log 与 version.txt，机器路径不进入确定性 manifest。CI 通过 Ubuntu 软件源安装构建依赖，不使用二进制缓存。

## 输入与参数

输入由 scripts/fixture_data.py 的 cases() 定义，使用显式字节及 (i*73+19)%256（i=0..4999），无平台 PRNG、时间或私人文件。16个用例保存64个二进制文件，共12507字节，不含 manifest。

| 用例 | block / strong | 用途 |
| --- | --- | --- |
| empty | 2048 / 32 | 空到空，12字节签名 |
| empty-new | 7 / 1 | 空到00 80 ff |
| to-empty | 7 / 16 | 非空到空 |
| one | 7 / 1 | 单字节00到ff |
| before-block | 16 / 16 | 块长减一 |
| exact-block | 16 / 32 | 完整块 |
| after-block | 16 / 1 | 块长加一 |
| multi | 7 / 32 | 互异块和3字节短尾，保持不变供后续COPY验证 |
| repeat | 16 / 16 | 重复完整块、连续相同高位字节 |
| insert-head / middle / tail | 7 / 1、16、32 | 头、中、尾插入 |
| delete-head / middle / tail | 7 / 16、32、1 | 头、中、尾删除 |
| default-edit | 2048 / 32 | 5000字节，长公共区域与局部三字节修改 |

每例明确执行 -H blake2 -R rabinkarp -b BLOCK -S STRONG signature，然后 delta、patch、cmp new.bin restored.bin。恢复文件比较后删除；独立生成的new.bin是预期。短摘要产生上游推荐长度警告，属于边界测试，不构成安全配置建议。

## 使用与门禁

先 bash scripts/build-reference.sh，再 bash scripts/generate-fixtures.sh 一个不存在的新目录。生成不会覆盖基准。bash scripts/rebuild-reference.sh 在mktemp目录重建、逐文件diff并比较生成字节文本；发现差异失败，不刷新基准。各脚本set -euo pipefail传播错误。

python scripts/verify_fixtures.py 只读验证 manifest，不重算它。拒绝缺失文件、长度/哈希错误、重复ID/文件登记、路径逃逸、签名头参数不一致及未登记文件；还检查确定性输入与记录数。重建脚本复制临时数据并故意追加字节，要求校验非零退出，不改正式夹具。

reference_bytes_wbtest.mbt 由 verify_fixtures.py --export 独立搬运原始old.sig字节；校验器重新渲染并全文比较。普通MoonBit测试离线运行，不安装rdiff、不编译C、不联网。新增1项测试遍历16例，检查空签名、三种摘要长度、记录数、名义偏移、weak/strong原字节和重复记录。保留原26项手写边界测试，合计27项。delta仅保存，没有新增完整解码器。

## 阶段状态（首次提交前）

| 项目 | 状态 |
| --- | --- |
| 固定参考从源码实际构建 | 已通过，本机WSL |
| 离线夹具完整性 | 已通过，16例64文件12507字节 |
| 上游自身生成恢复 | 已通过，16次patch后cmp成功 |
| MoonBit读取上游签名结构 | 已通过，Wasm-GC初检27/27；本地Native、JS、Wasm-GC均27/27，格式、依赖、接口及原探针通过 |
| 独立重建、损坏副本拒绝 | 已通过，本机WSL重建diff一致，损坏副本非零退出 |
| MoonBit签名生成 | 未执行 |
| 双向互操作 | 未执行 |

同SHA CI链接由最终交付报告提供，不能用提交前快照宣称云端通过。Linux reference任务从源码构建、重建全部数据并拒绝损坏副本；原Windows/Ubuntu三目标矩阵保留。未实现滚动校验、匹配、signature/delta/patch，未发布版本、标签或Release；止于Commit 3。

## Commit 4 增量证据

新增内部Rabin–Karp弱校验，使用独立逐窗口/EOF重算、固定上游向量及原16例basis真实块与签名weak_sum逐块比较。old.bin由已校验夹具离线搬运，不在生成器内计算弱校验。原夹具和manifest不刷新；历史Commit 3构建与roundtrip证据仍属原阶段。弱校验一致不表示强摘要适配、签名生成或双向互操作完成，详见rabinkarp.md及最终同SHA CI报告。

## Commit 5 增量证据

内部强摘要适配固定BLAKE2b输出参数32，再取1..32字节前缀。新增10组独立hashlib向量与所有长度前缀验证，覆盖127/128/129和255/256/257压缩边界；原16例强摘要记录逐块比较通过，空basis不增加记录、真实尾块不补零。原夹具与manifest不刷新，原阶段历史快照不改。该结果不等于完整签名生成、候选匹配或双向互操作通过；详情见strongsum.md，同SHA云端结果由最终报告提供。

## Commit 6 增量证据

公开signature标准输出与16例保存rdiff签名完整字节一致，并通过内部解析/重编码闭环。Linux新增66个临时参数和长度组合，不扩充正式夹具；82例由固定rdiff消费MoonBit签名，执行上游delta、patch、cmp均通过。普通三目标新增5项测试，总计43项。本阶段是“MoonBit签名的上游消费验证”，不是双向互操作，MoonBit delta/patch均未实现。原参考重建和损坏副本拒绝门禁继续保留；具体错误与参数说明见signature-format.md，同SHA云端状态由最终报告提供。

## Commit 7 增量证据

内部排序索引只接收已解析签名和共享工作预算，不读取basis。新增8项测试，共51项；候选按原序号稳定选择，全部配置摘要字节参与确认，短窗口使用真实内容。真实16例完整块/短尾查询、攻击者构造的结构合法弱键碰撞、预算精确边界和累计耗尽均验证。此处不是新文件扫描或COPY输出，公开API未变；正式夹具与manifest保留。预算单位与信息边界详见matching.md，云端结果在最终同SHA报告提供。

## Commit 8 增量证据

基线 a31a9036fd3e25efc0d41554505c33af344807a9。内部标准 delta 编解码新增 7 项测试，共 58 项，覆盖全部 literal/COPY 宽度、最短编码独立字节预期、非最短解析、全部保留 opcode、逐参数截断、END/尾随、零长度、UInt64 高位/最大值和三项预算。16 个上游 update.delta 离线完整解析至 END，重编码后比较 literal 原始内容和 COPY 参数；不执行指令或恢复 new.bin。

原参考组仍为 16 例、64 个文件、12507 字节，原 manifest 未改。手写 opcode 组为 29 向量、1 个数据文件及 1 个独立 manifest；验证器检查登记、路径、长度、SHA-256、缺失/多余文件及搬运常量。重建时将独立手写组复制到临时重建目录后整体比较，另要求损坏 opcode 副本被拒绝，未让 rdiff 重生成手写预期。原重建、损坏参考副本拒绝、三目标门禁及 82 次上游签名消费流程保留。

格式与优先级详见 delta-format.md。公开接口、匹配预算单位、旧夹具、工具链和依赖锁不变；无公开 delta/patch、扫描、补丁执行或双向互操作声明。本机及同 SHA 云端实际结果由最终报告提供，止于 Commit 8。

## Commit 9 增量证据

基线 6e6601705661279360139f13af2c6f18b0edeb24。新增公开 patch，不公开内部指令模型；先完整解析，再预检全部 COPY 和输出长度，最后分配并执行。原 58 项保留，新增 9 项，共 67 项：公开黑盒覆盖所有 COPY 宽度、非顺序/重复/重叠引用、二进制 literal、四项预算、无符号越界、竞争错误及失败后复用；离线参考测试将原 16 个 delta 恢复为对应 new.bin，逐字节相等。

新增 new.bin 搬运函数，预期只来自已校验的原始文件。原 16 例/64 数据文件/12507 字节和原 manifest、29 个 opcode 向量及独立清单不变。固定参考重建、两类损坏副本拒绝、82 次上游签名消费、格式/依赖/原探针和三目标检查保留；接口快照只新增公开 patch。

新增证据称为“MoonBit patch 恢复固定上游 delta”，尚不是“MoonBit signature → 上游 delta → MoonBit patch”完整链路证据。此笔无 delta 生成、新文件扫描、正式 CLI、完整双向互操作或版本发布；实际本机和同 SHA CI 结果见最终交付报告，止于 Commit 9。

## Commit 10 增量证据

基线7131afe9c8172dd737ab3f71a9d019317adc13f7。新增公开delta(Bytes签名, Bytes新文件, Limits)，接口快照只增加delta；signature、patch及内部格式/候选顺序保持不变。滚动扫描真实使用rotate/rollout和匹配后重建，连续literal及真正连续COPY受检合并，索引/扫描/确认/累积共享同一预算，累积前检查合并后指令数和编码大小。

原67项保留，新增13项，共80项。覆盖空/相同/全异、头中尾插删改、完整块/短尾/尾块移动/块移动/重复块/二进制字节，代表block1/2/64/2048和strong1/16/32。解析生成结果逐条核验真实basis范围、COPY内容、总输出、合并及确定性；八块复用门槛预设COPY≥512且delta<515，实际new515、delta18、COPY512。配置、签名错误、输入/输出/编码/指令预算、共享工作精确边界、候选攻击、极小块增长、失败复用和输入不变均验证。

scripts/consume_delta.py在现有Linux参考任务追加必需步骤：16个保存的上游签名和独立new.bin生成MoonBit delta，13个临时复用/短尾代表例用固定rdiff准备签名；所有29例由上游patch及cmp验证恢复，生成/恢复/比较命令退出码写入日志，任一失败导致任务失败。生成适配仅取得签名和新文件，不取得basis。正式16例64文件12507字节及manifest、29个手写opcode向量及清单不改，参考重建、两类损坏拒绝、原82次签名消费及所有探针保留。

此处是“固定上游签名→MoonBit delta→上游patch”的已执行代表范围，不表示完整双向互操作矩阵通过。完整反向链、交叉随机变异、小文件穷举、统一资源审计、CLI与发布仍未完成。具体本机与同SHA CI结果由最终报告提供，止于Commit10。

## Commit 11 双向矩阵证据

基线8fe4d2c1e159d3c2d590994b9a7917728ac4315e。新增scripts/interop.sh与Python编排，Native适配器最小增加公开patch调用；delta模式仍不接收basis。公开API、核心算法、工具链/依赖锁和正式参考/opcode数据不变。

矩阵配置tests/interop/matrix.json、源码interop_cases.py及计划SHA-256固定输入：16原始+66参数边界+12短尾+3复用+13编辑+338穷举参数+48固定种子变异=496参数用例，对应274独立old/new对。参数覆盖block1/2/7/16/64/2048与strong1/16/32，分配及LCG32(基种子0x4d4c5311、逐例派生状态、1–6次有界编辑)的精确规则见tests/interop/README.md。穷举范围仅为字母表00/80/ff、长度0–2共13串的169有序对，在block1/2,strong32下各执行八组合。

两条必需链A(upstream signature→MoonBit delta→upstream patch)、B(MoonBit signature→upstream delta→MoonBit patch)及其余六组合各计划496次，共3968矩阵恢复。签名完整字节比较496次，每次恢复与独立new逐字节比较，不以哈希/长度替代，不要求delta编码一致。COPY门槛检查两种签名来源，复用new515要求COPY≥512且delta<515，相同文件要求512，局部两块修改要求384。额外一次门禁后的正常恢复单独统计。

Python指令检查器补齐完整参数/payload/END/尾随检查，原consume_delta复用该检查器，避免Python切片截断被int.from_bytes接受。六项离线Python工具检查验证全部手写宽度、截断/保留/零长/END、真实内容比较、固定计划与清理前归档；这6项不是新增MoonBit库测试，库仍80项。没有为增加回归数制造算法失败；本轮若无真实失败，最终报告明确记载“本轮未发现需归档的算法失败样本”。

缺失参考工具通过隔离的不存在路径测试入口非零，比较失败通过修改恢复副本走真实比较函数非零；二者只在观察到预期错误码/标记时通过，之后再正常恢复。外部非零、超时、崩溃、输出缺失或不一致都会失败。临时清理前保存输入、产物、种子/组合/命令和版本。忽略的_build/interop报告分别统计预期/成功/失败/未执行，记录真实HEAD、dirty与源码内容摘要，报告另附SHA-256；同SHA CI保存完整产物。

保留原82次签名消费、29次delta消费、参考重建及两类损坏副本拒绝，现有Linux参考任务追加统一矩阵并上传报告，Windows/Ubuntu三目标核心检查不变。实际执行状态由最终交付报告及同SHA产物提供；Linux Native互操作与Native/JS/Wasm-GC离线单元证据分别列出，不扩展为JS/Wasm-GC直接运行rdiff。有限矩阵通过不是任意输入兼容或短摘要无碰撞证明；统一资源审计、CLI、最终验收、发布仍留后续，止于Commit11。

本机WSL已实际完成274对输入、496参数用例、各组合496次及总3968次恢复，A/B均496成功、0失败、0未执行；496次签名完整字节比较通过。两个预期失败均观察到退出码1，门禁后额外正常恢复通过。插入复用例两种签名来源均为new515、delta18、COPY512；相同例COPY512，局部修改COPY384。本轮未发现需归档的算法失败样本；只修复了Python统计器对截断的校验缺口并增加对应工具回归。该本机报告明确source.head为基线8fe4d2c、dirty=true，不当作最终提交源码的同SHA证据；最终CI产物另行核对。

## Commit 12 资源审计与回归

基线ebca75e597be8a43c88e957f97a22de217beee2c。逐代码检查signature计划/解析、索引、扫描/累积/编码、patch及wire和固定摘要依赖。实际发现Array.push扩容可在原1单位追加中隐藏线性搬移；先加回归，观察旧80通过、新项失败（原实现未拒绝不足预算），再修复显式容量预收/保留。已知签名记录数在预检后精确保留，避免多余容量。无API、标准格式、候选顺序或默认值改变。

新增19项集中库测试，总99；原80项保留，其中三个精确工作边界按新增首槽费由32/82/16改为33/83/17并给出推导。16个入口/适用字段关系完成少1/等于/多1；包括128恶意同弱键/长前缀候选、64重复窗口不可合并COPY、512连续miss、容量/编码边界、UInt64乘加与索引、错误竞争、输入不变及失败后复用。原6项Python工具检查保留。完整契约和存储模型见resources.md。

既有三目标任务的同次无过滤全套测试输出资源报告（源码SHA/dirty、每目标观察总数、19资源项、三点关系数），与互操作产物分开保存，不新建重复矩阵。完整274对/496参数/3968恢复/八组合各496、原82签名及29delta消费、参考重建、两类损坏拒绝和工具失败门禁不缩减；实际同SHA执行结果见交付报告及产物。

本轮不测峰值堆或制造OOM，字段上限按各自阶段承诺，允许其他已受限阶段先工作/分配；输入已由调用者分配，视图可保活完整缓冲，容器头/容量、临时数组及最终转换副本另计。统一契约不是总CPU或进程内存保证。止于Commit12，CLI、最终交付、打包发布和0.1.0验收仍未完成。

## Commit 13 Native CLI 文件流程

基线d7f4f05f3dd3392418eccf089c31748ffe7f21f3。新增cmd/moonlibsync，Native包隔离文件/参数/stderr依赖，只调用公开signature/delta/patch，不复用参考适配器充当产品CLI。核心API、默认资源、锁文件及正式参考/opcode数据不变。Windows/Linux实际产物路径与命令见cli.md；Linux同样生成.exe后缀的ELF本机程序。

6项Native私有辅助测试覆盖严格参数、读入增长/截短、部分写、临时名撞名、无覆盖提交及清理失败。共享Python驱动直接运行真实二进制：本机NTFS79项场景通过，4项符号链接因WinError1314未执行；Linux/ext4为81项，包含链接场景；Windows若具备链接权限总83，最终同SHA实数由报告提供。不可写目录在同身份探针确实失败后才测试CLI，恢复权限后再实际写探针。三组双进程竞争每组恰一成功，完整目标属于赢家，失败进程不替换它且无自己的临时残留。所有失败后重跑完整三命令，输入/原有输出保护和临时清理均检查。

CLI默认读上限OLD/NEW64MiB、SIG16MiB、DELTA80MiB，已知大小先拒绝，读取仍最多初始N加1字节探针，不使用无界read_all/read_binary。路径规范化、实际父目录及不跟随叶链接的存在性检查处理相同/等价/硬链接输出；最终rename(replace=false)防预检后竞态，不删除已有最终目标。临时CreateNew、完整write、文件sync、close后提交；清理错误同时报告。核心错误/IO退出1、用法2、成功0，stdout不放二进制，开发版本与元数据核验。

固定后端Linux renameat2(RENAME_NOREPLACE)、Windows FileRenameInfoEx无替换（旧系统MoveFileEx也无替换）；本机DrvFS实测EINVAL时退出1、输入不变、无最终目标且清理成功，Linux正向烟雾在ext4执行。该负向结果保留为明确不支持边界，不写成DrvFS正向成功。文件sync不承诺父目录持久化或断电恢复；稳定可信父目录/输入、未测网络盘和其他FS等限制见cli.md。

现有Windows/Ubuntu任务追加对应烟雾和CLI产物，根库99项按包选择仍在三目标执行，CLI6仅Native；6项Python工具、274对/496参数/3968恢复、原82/29消费、参考重建和全部失败门禁保留。CLI报告单列版本、实际路径/魔数、文件系统、源码SHA/dirty、退出码、未执行项与清理，不能把平台场景次数加到库测试总数。实际同SHA证据由交付报告提供；止于Commit13，不宣称Commit14示例、整体验收、发布或0.1.0交付完成。

## Commit 14 示例、接口与失败传播

只增加公开API示例、CI整合、文件交换演示、隔离失败门禁及文档；核心实现、预算、工具链、依赖锁与正式夹具不变。纯示例发送端函数仅取得签名和新数据，三个目标各真实运行，脚本从本次stdout提取delta并用既有严格解析器验证COPY>=512、delta<515、实际内容与大小；它不导出内部指令。

固定moon info为新basic可执行包生成空公开接口，提交该文件并显式保护。已跟踪接口在任何自动生成前与HEAD比较，缺失也失败；前后比较包含显式包范围的缺失状态，不盲扫缓存和_build。隔离副本删除digest接口，实际前置入口拒绝，恢复后通过。

CI使用check_fixtures.py包装真实verify_fixtures.py；参考及opcode副本损坏均要求预期诊断和非零，未刷新manifest。预期字节损坏运行真实check_example.py，实际恢复断言输出BASIC_RESTORE_MISMATCH后非零，check_returncode继续失败；外层check.py及CI无容错步骤继续失败。仅临时副本被改动；恢复原始字节后同一正常入口须通过，损坏和复验日志独立。Wasm-GC abort本身只显示unreachable，因此示例在失败分支先明确打印断言诊断，再中止。

文件交换使用正式Native CLI，不用probes/signature替代，固定rdiff身份与原始文件均核对；新目录中实际执行两条链，独立new逐字节比较，保留命令及交换文件。Linux/ext4正向运行，DrvFS边界不变；演示不新增完整矩阵，正常互操作计划与原消费次数完整保留。产物路径与分项计数见验收表。

## Commit 15：首版功能冻结

冻结基于Commit14执行代码925d47979549da4e8e3c32b742806513478346e6。本笔只新增有限基准配置/驱动、工具正确性CI步骤及文档，未改变运行库、CLI执行代码、公开接口、默认预算、依赖锁或正式夹具。被测20个运行库/CLI/构建配置/锁文件的逐文件SHA-256在 `tests/benchmarks/runtime-baseline.json`；测量时HEAD/dirty如实保留，提交后交付记录提供最终冻结SHA、干净同SHA必需CI和运行库哈希关联，不为自身SHA增加循环提交。

| 冻结项 | 首版固定范围 | 权威文件／证据 |
| --- | --- | --- |
| 主API | signature(Bytes,SignatureOptions,Limits)、delta(Bytes,Bytes,Limits)、patch(Bytes,Bytes,Limits)，均返回Bytes并raise SyncError | pkg.generated.mbti、api.mbt、examples/basic |
| 公开类型 | SignatureOptions的block_len/strong_sum_len，Limits九个Int64字段及default/validate；SyncError十个既有变体（InvalidOptions带String，其余无载荷） | pkg.generated.mbti、docs/design.md |
| 默认参数 | 签名2048/32；支持强摘要1–32；默认Limits原值不变 | api.mbt、limits.mbt、docs/resources.md |
| 签名 | 标准0x72730147 RK+BLAKE2；BLAKE2b(len=32)前缀，不补齐尾块；无私有身份/尾长字段 | docs/signature-format.md、SOURCES.md |
| delta/patch | 标准0x72730236、literal/COPY/END、1/2/4/8字节参数；END完整且无尾随；COPY只读原basis，解析/区间预检后分配恢复 | delta.mbt、patch.mbt、docs/design.md |
| 匹配 | 仅凭签名和new；稳定弱校验/块序号顺序、首个强匹配；EOF真实窗口逐字节收缩；不保证最优delta | index.mbt、delta.mbt及资源契约 |
| 错误与资源 | 现有分类和检查顺序；单次delta共享工作预算，容量费用；超限失败，无不收费literal退路；全量缓冲及中间/转换副本边界 | docs/resources.md、99项核心测试 |
| CLI | 三命令，signature独有block-size/sum-size，--语义；用法2、文件/核心1、成功0；有界读、现存输出拒绝、独占临时、sync、无覆盖提交、显式清理错误 | docs/cli.md、两平台集成与6项Native辅助测试 |
| 目标/文件系统 | 核心Native/JS/Wasm-GC；CLI Windows/NTFS、Linux/ext4；DrvFS不支持提交时明确失败；不承诺断电持久化/任意文件系统/恶意路径替换防护 | 同SHA三任务与CLI报告 |
| 首版之外 | 其他profile、网络/SSH协议、目录同步、权限/时间戳同步、流式调度、压缩加密、浏览器服务、更多CLI选项 | 本冻结表与原规划边界 |

[基准](benchmarks.md)为本次WSL2/ext4、两个规模/五场景的进程文件流程实测，不是算法内核或全平台性能保证。运行代码未因性能数字优化，文件提交保证未放宽。源码早期“provisional”等注释保留其阶段来源；本次冻结以这里列出的实际公开声明和行为契约为准，不据此暗示过去已经冻结。

Commit16仍须：核对精确版本和发布身份/权限；审计实际源码包及许可证分发内容；在干净目录重建；关联发布源SHA与必需CI；实际发布Mooncakes；通过无本地替换的独立注册表消费者；归档发布后证据。功能冻结不是已审计包候选，也不是版本已发布；这七项本笔没有执行。

## Commit 16：0.1.0 分发范围

算法、公开API、默认参数/预算和文件行为不变。仅将CLI版本展示改为 `MoonLibSync 0.1.0` 并同步烟雾断言，模块描述去除开发态前缀，使用文档改为版本能力陈述。本次没有重跑基准；Commit15原始测量、指纹及冻结SHA保留原归属，CLI展示源码/模块描述改变意味着发布二进制与旧测量二进制不保证字节相同。

实际模块包保留全部开发测试、对应生成常量/夹具与工具引用，另交付公开消费者模板及包检查器；不留缺少夹具的半套工程。唯一打包过滤策略为.moonignore，正式moon package归档逐成员与候选源原始字节核对。候选workspace消费与无替换注册表消费分别记录；CLI按源码构建交付，没有发布预编译安装器。最终状态、发布源与后续证据提交严格区分，详见release.md。

## 0.1.0 发布后证据归属

0.1.0已实际发布并通过无本地替换的公开注册表Native/JS/Wasm-GC消费。功能冻结SHA为857aa981debc3ce0c1e54176621e84454733202e，正式发布源码SHA为f62958eceda9deecc4eae8a14007f5be76c59b0e；本段所在后续文档提交不改变发布包。实际成员、校验、服务端发布时间、固定客户端frozen校验限制及经用户允许的标准publish命令、独立目录/缓存/解析闭包和环境边界见[发布实证](release.md#010-实际发布与消费结果2026-11-09)。

注册表三目标和下载源码CLI实测为Windows/NTFS；Linux/ext4有发布源同SHA候选包CI，包内容与公开下载一致。没有用单个目标代替三目标，也没有将源码构建说成预编译安装。前述Commit阶段未发布/未消费的状态仍属于当时历史，不能倒填为早期已交付。
