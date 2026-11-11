# MoonLibSync 0.3.0：阶段 B 冻结与发布验收

状态：`unpublished-release-candidate`。本文件随候选源码打包，不宣称已经上传或注册表验收成功；实际发布源SHA、同SHA CI、最终包索引及两平台下载证据在提交后 `_build/release-0.3.0/delivery.json` 保存。阶段B功能基线为 `82d2f98e69a95bbce2d125635b27890a02cfb0fa`，[基线CI](https://github.com/YKDshaxing/moonlibsync/actions/runs/43020414564)三任务成功。发布后文档提交与正式publication_source_sha分别记录，文档HEAD不代替上传原包。

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
