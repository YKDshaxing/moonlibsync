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
