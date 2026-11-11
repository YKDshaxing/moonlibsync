# MoonLibSync 0.3.0：阶段 B 冻结与发布验收

状态：`published-and-consumer-verified`。0.3.0已实际上传，并通过Windows/NTFS与Linux/ext4的全部必需独立注册表消费。阶段B功能基线为`82d2f98e69a95bbce2d125635b27890a02cfb0fa`；正式publication_source_sha为`35b2225e56747c0d7568dd117017c25e6c658146`，[发布源同SHA CI](https://github.com/YKDshaxing/moonlibsync/actions/runs/43025252619)三个任务全部成功。本段为发布后文档，文档SHA在delivery.json单列，不冒充发布源；上传原包保留当时的候选状态描述，不随文档HEAD变化。

## 本版冻结范围

自0.3.0提供显式自动块长、Delta／Full更新规划及schema2受校验应用。公开声明以pkg.generated.mbti为准，不重新设计Commit25/26类型。

| 能力 | 冻结入口／类型 |
|---|---|
|auto|recommend_block_len、signature --block-size auto，policy v1|
|规划|plan_update、UpdateOptions、UpdatePayload、UpdatePlan、UpdateDecision|
|schema2|TransferManifest及create/parse/encode_transfer_manifest、apply_update|
|CLI|新增make-transfer-manifest、apply-update；连同旧九条共十一条文件/检查命令|
|原兼容|标准signature/delta/patch、Prepared、检查API、schema1清单和verified_patch|

默认签名2048/32不变，auto只显式启用。policy v1以约512记录、偏好最小64、2次幂舍入和当前预算/块上限确定参数，不保证签名、delta或时间更小；标准头中只保存实际数字参数。

规划先完整生成实际delta，再按 `D<N && N-D>=M` 选择，M默认0；平局Full，负阈值报错，大非负阈值精确比较，生成错误或预算不足不降级Full。savings_bytes表示选中负载的实际节省，Full为0。比较只含负载，不含清单、路径或传输协议，不是实测网络收益。Full就是NEW原始字节，不能交给rdiff patch。

schema2与schema1分别严格解析，未知kind/字段混用拒绝，不以扩展名或魔数猜测。API Full忽略basis，CLI Full明确拒绝--basis；Delta必须有basis并沿用verified_patch的长度/摘要、严格END、COPY原basis范围、分配前预测及最终结果核验。SIG描述不代表接收端实际核验过SIG文件。制作清单不证明恢复，完整性不认证发布者。

所有旧错误变体、默认Limits、逻辑工作单位、一次性/Prepared记账、RK+BLAKE2 profile及EOF短尾策略不改。仍为全缓冲；候选delta、中间指令/索引、JSON树、转换副本和恢复缓冲可能共存，不承诺流式、输入快照、进程总内存或断电持久化。两轮历史耗时结果保留原阶段，没有新计时或峰值测量。

核心Native/JS/Wasm-GC，CLI Windows/NTFS、Linux/ext4；Linux仍生成.exe后缀ELF。沿用有界读取、现存输出拒绝、同目录CreateNew、完整写/sync/close、无覆盖提交和清理诊断。DrvFS不支持提交时明确失败，不降低保证。

## 有限组合与同源消费

独立计划tests/stage-b/plan.json含13个代表输入、13次固定rdiff签名字节对照、26份分别判断的候选及26条应用链，涵盖固定/auto、一次性/Prepared、空/微小/整块/短尾、五种编辑及收益边界。每份候选各按自己的实际长度选型，不要求MoonBit和rdiff delta字节、大小或最终选择相同。报告记录计划指纹、输入/签名/候选/负载/结果长度及SHA-256、Delta上游恢复数和Full原始校验数；Full不计入librsync恢复。

同一阶段B外部模板用于候选与公开注册表三目标：auto独立预期128、257记录、5152字节签名；计划全部决策字段、两种负载、schema2编码/解析/应用、阈值与错误；同时实际执行schema1并交叉拒绝。相应包源码CLI保留48项transfer检查，另加2项auto/数字字节一致检查。坏消费者实际使工具入口非零，恢复后通过；拒绝用例不创建输出。来源标记区分workspace候选与无替换注册表。

保留每平台三目标194库测试、Windows392/Linux393 CLI、各19辅助、原3968/阶段A504/Prepared32恢复、82/29消费、auto35签名/70恢复、Commit26的2 Delta/6 Full。新组合、消费者、工具门禁分别统计，不累加成库测试。

## 实际分发与发布门禁

固定moonc0.10.20+65efd5b93、moon/moonrun0.1.20261104、mooncrypt0.4.5及闭包哈希。版本唯一源moon.mod，通过release_version.py生成归档/依赖/缓存路径；原Unicode、长路径、只读清理和ZIP安全回归保留。沿用.moonignore及完整开发闭包；库、CLI、五例、接口、新消费者/计划/工具数据、完整GPL/LGPL/Apache文本及core NOTICE逐成员审计，SDK/缓存/凭据/二进制/运行报告不入包。

输出统一_build/release-0.3.0，Windows/Linux分目录保存实际moon package ZIP、audit.json、candidate-report.json、registry-report.json、组合/日志、SHA256SUMS。所有包成员与干净发布Git原始blob核对；不同平台ZIP分开记录，不要求压缩容器相同。保护清单逐项核对旧1541文件；0.1.0/0.2.0记录不改。

只有版本未占用、Mooncakes身份/命名空间权限、干净推送源、同SHA三个CI、许可证/实际包/干净重建及两平台候选消费全部通过才执行标准 `moon publish --dry-run`、`moon publish`。不用此前不适用的publish --frozen，不升级依赖或关闭验证。网络结果不明先查询，不盲目重复上传。

发布后每平台从正式发布源独立检出执行release_check.py --registry：新SDK、空模块缓存、公开下载0.3.0，无workspace/path/Git/候选替换；核对全部依赖闭包，原/阶段A/阶段B三目标及下载源码CLI，前后成员字节保持一致。任一平台未完成，状态保持published-consumption-pending；两端均通过才published-and-consumer-verified。候选CI不能抵扣注册表实测。

参考官方[模块发布与版本规则](https://docs.moonbitlang.com/en/latest/toolchain/moon/package-manage-tour.html#publish-your-module)，实际选项以固定客户端help为准。本笔不创建标签、Release或安装器，止于Commit27，不进入阶段C。

## 实际发布与两平台验收（2026-11-11）

标准moon publish --dry-run及moon publish均退出0；服务端created_at为`2026-11-11T13:10:20.787881+00:00`，来自公开版本元数据，不用本机时间替代。发布前既有0.2.0查询成功、0.3.0明确404、YKDshaxing身份及namespace权限由服务器dry-run验证；网络查询失败独立记录，不当作版本不存在。版本在上传前再次确认可用；没有重复上传、标签、Release或安装器操作。

实际上传ZIP为YKDshaxing-moonlibsync-0.3.0.zip，266成员，压缩443781字节，未压缩1184417字节；SHA-256为`f96d2d93f305286b7cd761db6504d7c5590e06a0453a7df0ce71941a30fddfd7`。Windows和Linux公开下载都为这一大小及SHA，逐成员内容与发布Git原始blob一致，编译后重新核对未改变。GPL/LGPL、Apache-2.0、core LICENSE/NOTICE及来源说明完整，闭包四项固定依赖的归档哈希与源码全部核对。SDK、缓存和凭据未入模块包。

CI的Windows候选ZIP同上传哈希；Ubuntu候选SHA为`7eeefefb03681146ee6287f32d9be7939a817c8c58d4345c091606ae4df0ef03`。两平台266个成员路径、原始内容及逐成员哈希相同；容器字节不同，不据此判源码差异。本地Linux包审计也单列保存，不拿它替代实际下载ZIP。

两平台都从正式发布源干净检出执行release_check.py --registry，安装新SDK到独立临时目录，初始模块缓存为空，从公开注册表真实取得0.3.0，未用workspace/path/Git/候选替换。原消费者、阶段A、阶段B分别在Native/JS/Wasm-GC运行。下载源码CLI保留旧流程和48项transfer，另有2项auto/显式数字字节一致检查（32769字节选128，摘要32签名9264字节）；API模板则验证摘要16的5152字节签名、计划决策字段、Delta/Full、收益阈值、错误、schema1兼容和schema2交叉拒绝。两平台各执行阶段A/B坏消费者非零与恢复门禁；日志中的预期断言失败不是正常消费失败。

保留两平台三目标各194库测试、Windows392/Linux393 CLI、各19辅助、3968/504/32恢复、82/29消费、auto35签名/70恢复、Commit26的2 Delta/6 Full，原Python互操作工具6项、包安全10项、五例和全部失败门禁。新增组合实际13输入、13签名对照、26候选/应用，分别16次Delta上游恢复、10次Full原始校验，9项拒绝检查；不把这些数量累加成库测试，也没有跨生成器强求相同delta或选择。

本地初次干净重建与部分只读查询遇到TLS握手EOF；失败日志保留，通过本机已配置代理重试成功，TLS校验、SDK/依赖及文件保证不变。本机Windows两组链接能力不可用，372项可执行CLI场景通过；同SHA Windows CI完整392项，Linux完整393项。最初预提交检查发现工具尾随空格，已在发布源提交前修正并重验。没有新计时、峰值内存或阶段C工作。

[Mooncakes 0.3.0](https://mooncakes.io/docs/YKDshaxing/moonlibsync@0.3.0)、[公开元数据](https://mooncakes.io/api/v0/manifest/YKDshaxing/moonlibsync@0.3.0)。实际包、逐成员许可索引、两平台候选与注册表报告、15项发布源CI产物ZIP校验、组合计划/命令/失败记录、delivery.json和SHA256SUMS保存在_build/release-0.3.0/。旧发布与基准1541文件逐项保护，无新增或改写。发布后文档CI另行记录，不能用其候选重建包替代本版上传原包。
