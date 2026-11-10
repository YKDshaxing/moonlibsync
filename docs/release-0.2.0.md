# MoonLibSync 0.2.0冻结与发布验收

状态：`published-and-consumer-verified`。0.2.0实际发布及Windows/NTFS、Linux/ext4必需注册表消费均通过。阶段A验证基线为4452eddcd27818b5852850f07085f454fe75b453；正式发布源为`069c126e2ea67c52a5759478edf480afa68f31a4`，[发布源同SHA CI](https://github.com/YKDshaxing/moonlibsync/actions/runs/42813769983)三个必需任务全部成功。本文属于发布后文档提交，文档SHA在交付记录中单列，不冒充发布源；原包不会随Git文档变更而更新。

## 冻结范围

自0.2.0提供检查API、可复用签名索引、完整性清单及受校验补丁流程。原signature/delta/patch、inspect_signature/inspect_delta/check_patch、prepare_signature/PreparedSignature::delta、两种清单create/parse/encode、verified_patch全部冻结。公开接口精确定义以pkg.generated.mbti为准；SyncError、ManifestError及全部公开结构字段不改，PreparedSignature字段不透明。

九条CLI为signature、delta、patch、inspect-signature、inspect-delta、check-patch、basis-info、make-manifest、patch-verified；--help/--version仍为元信息。参数、退出0/2/1、仅检查命令支持--json、写入成功静默、普通文件/有界读取、无覆盖提交和自有临时清理均沿用已验证行为。Native/JS/Wasm-GC核心及Windows Native/NTFS、Linux Native/ext4的文件流程冻结；Linux ELF仍带.exe后缀。DrvFS不支持无覆盖提交时拒绝，不降级。

RK+BLAKE2 profile，默认block2048/strong32；强摘要为先计算BLAKE2b-256再截取1..32字节。全部Limits默认、逻辑工作单位、标准literal/COPY所有宽度、严格END/尾随数据、COPY始终读取原basis、EOF收缩和未知短尾长度策略不变。检查JSON schema1，完整性清单schema1（64KiB、容器深度2、建树后字段16、严格UTF8无BOM、重复键拒绝、规范长度及小写SHA256）不变。

check_patch仅预检长度范围；create_update_manifest不证明恢复内容。verified_patch实际核验OLD、DELTA、结果，不传SIG故不实际核验SIG文件。清单须来自可信来源，不提供发布者认证。全量输入、解析结构、恢复缓冲、转换副本与哈希工作存储可共存，不承诺RSS峰值、总CPU、流式或事务快照。两轮有限性能基准保留原测量SHA，不重跑；复用未观察到稳定总耗时优势。

范围外：自动块长、Full模式、流式/调度器、其他profile、网络、目录同步、加密压缩、安装器、GitHub标签和Release。本笔不进入阶段B或Commit25。

## 正式包、消费与身份门禁

固定moonc0.10.20+65efd5b93、moon/moonrun0.1.20261104、mooncrypt0.4.5及原依赖闭包。版本唯一来源moon.mod；发布工具动态生成归档名、消费者依赖、缓存路径、版本断言；CLI版本与元数据由测试核对。原4项ZIP工具测试加5项版本/归档保护回归单列。Windows候选验收保留PYTHONUTF8=0/UTF8日志回归。

官方规则核对来源：[模块元数据](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html)与[发布流程](https://docs.moonbitlang.com/en/stable/toolchain/moon/package-manage-tour.html)。首次公开版本检查确认0.2.0未占用，现有0.1.0查询作正向对照；选定工具链登录YKDshaxing。命名空间权限最终由标准moon publish --dry-run和实际上传验证，Git SSH不代替Mooncakes身份。GitHub仓库公开且归属YKDshaxing，首次检查无标签/Release；本笔不创建它们。

正式使用moon package --list --frozen及moon package --frozen，选项已按固定客户端帮助核对；不是手工ZIP。实际归档/成员数/压缩与未压缩大小/逐成员SHA256/许可归属在_build/release-0.2.0/audit.json中记录，Windows/Linux分别记录，不套用0.1.0数字。实际成员与Git原始字节对应，保留运行源码、SHA256/JSON导入、CLI、示例、测试夹具、源码工具及完整GPL/LGPL/Apache许可/NOTICE/来源；凭据、SDK、依赖缓存、rdiff二进制与报告不入包。

`python scripts/release_check.py --clean`完成正式归档、干净SDK/源码重建及仓库外候选消费，允许显式workspace替换。实际上传后，`--registry`使用另一个仓库外目录及全新SDK/空模块缓存，仅公开注册表下载，禁止workspace/path/Git替换；实际版本、闭包、解包成员、三目标旧/阶段A消费者、封装拒绝及从下载源码构建的产品CLI均另行核验。两个平台分别完成，候选证据不能抵扣注册表证据。

保留166库测试/各目标/平台、CLI314/315和15辅助、原496参数3968恢复、82/29消费、32Prepared恢复、阶段A28对/28参数504恢复/38SIG/38准备对象/112调用、每目标16拒绝、每平台9封装拒绝和24候选CLI检查。阶段A计划指纹仍为5f02d159961131c569582b306ae6a48ddf794bb10906f8d2492f204c913174e9。

## 发布状态与后续证据

发布前只执行候选门禁；全部发布源同SHA CI成功后才执行标准moon publish --dry-run，再执行moon publish。不重新强制此前失败的--frozen临时解包发布路径，不关闭验证、不升级工具链或依赖。上传响应不明先查询注册表，不盲目重复；上传后为published-consumption-pending，两平台全部注册表消费通过后才记published-and-consumer-verified。

发布后文档另行提交，明确发布源SHA与文档SHA不同，已上传包不会因Git文档变更自动更新。严格重放成员对照应检出正式发布源再执行，不能用后续文档HEAD冒充原包内容。0.1.0原归档、delivery、SHA256SUMS及历史发布说明完全保留。

干净重建/注册表消费者可复用已有固定SDK/core的下载归档，按toolchain.lock逐一验证后在新目录重新解包、bundle和检查版本；这不是复用已构建SDK。报告记录归档源与哈希。该缓存只含工具链/core，不复制任何注册表模块或候选包进模块缓存；注册表验收仍在全新空模块缓存中真实下载。新SDK使用固定客户端支持的MOON_REGISTRY_API=1查询官方元数据，版本及完整依赖归档继续逐字节/哈希核验。

本机Windows关闭长路径支持时，固定客户端的双SHA256元数据缓存路径触发旧临时目录清理失败；发布工具使用短临时前缀/内部SDK目录，并在核对自有临时根目录后以Windows extended-length路径执行清理；回归实际创建双64字符目录及第三个64字符缓存文件名，确保超过MAX_PATH的文件也能删除。不关闭或忽略清理错误。工具测试合计10项（原4、版本/保护5、路径1），运行库及协议未涉及修复。本机WSL访问官方站点必要时经仅放行官方站点及其已核对CDN域名的临时CONNECT转发，客户端TLS和真实下载仍保留，不复制候选包进模块缓存。

同一清理回归还包含Git克隆的只读pack索引；仅在Windows、仅对已验证自有临时根之内的只读文件恢复写位后重试原删除操作。其他权限/清理错误继续失败，不触碰原仓库或共享归档的权限。

## 实际发布与独立消费结果（发布后补记）

| 项目 | 实际结果 |
|---|---|
| 模块/版本 | YKDshaxing/moonlibsync@0.2.0 |
| 发布状态 | published-and-consumer-verified |
| 标准客户端 | moon publish --dry-run退出0；moon publish退出0，服务端200；未使用发布--frozen，也未绕过验证 |
| 服务端created_at | 2026-11-10T12:21:05.748505+00:00 |
| 正式发布源 | 069c126e2ea67c52a5759478edf480afa68f31a4 |
| 正式源CI | [42813769983](https://github.com/YKDshaxing/moonlibsync/actions/runs/42813769983)，reference / Windows / Ubuntu全部成功 |
| 实际模块包 | 官方moon package ZIP；232成员；归档387947字节，成员未压缩合计1039325字节 |
| 实际上传/两端下载SHA256 | bb9a66b61be62fb377e011d822716c5b2d74b9e5301d6856da922729cb88f0b8 |
| Linux候选ZIP SHA256 | bd93f401d0ce421a2746e043f1b8a44da3f4fe7d0c1f4471dd7e2f4a5b1345a8；成员内容与Windows逐字节一致，压缩容器字节不强求相同 |
| 逐成员/许可 | audit.json记录路径、大小、压缩大小、SHA256和许可范围；Git原始字节对应、完整GPL/LGPL/Apache与core NOTICE/来源齐全；无凭据/SDK/缓存/参考二进制/运行报告入包 |
| 干净重建/候选消费 | 两平台发布源同SHA CI及本机复验通过；新目录重新安装锁定SDK、构建core和三个示例，仓库外解包候选的三目标旧/阶段A消费者及包内CLI通过 |
| Windows注册表消费 | NTFS，空模块缓存、新SDK、无workspace/path/Git替换，实际0.2.0原包与审计成员逐字节一致；旧/阶段A三目标、每目标16类公开拒绝、9项封装编译拒绝、24项下载源码CLI及错误后复用通过 |
| Linux注册表消费 | ext4，空模块缓存、新SDK、无workspace/path/Git替换；与Windows相同三目标/封装/24项CLI通过；实际下载ZIP同哈希，全部四项依赖归档和源码对应锁定闭包 |
| 原覆盖 | 每平台各目标166库测试，CLI314/315和各15辅助，496参数/3968恢复，82/29消费及32次Prepared恢复、6项Python互操作工具、原示例/12封装探针及全部门禁保留 |
| 阶段A覆盖 | 28对/28参数/504恢复；38份SIG/38准备对象/112复用调用，计划指纹5f02d159961131c569582b306ae6a48ddf794bb10906f8d2492f204c913174e9不变 |
| 发布工具 | 原4项ZIP安全、5项版本/归档保护、1项真实长路径/只读Git清理回归，共10项；CP1252 Unicode诊断回归保留 |
| 标签/Release | 本笔未创建；远端标签及公开Release列表检查为空；没有安装器/预编译二进制交付 |

[公开注册表0.2.0](https://mooncakes.io/docs/YKDshaxing/moonlibsync@0.2.0)；[版本元数据](https://mooncakes.io/api/v0/manifest/YKDshaxing/moonlibsync@0.2.0)。实际注册表消费是包源码构建，不是预编译二进制。完整发布命令/响应/时间、Windows和Linux报告、实际ZIP、逐成员审计、CI产物摘要、delivery.json及SHA256SUMS保存在_build/release-0.2.0/，0.1.0原归档/交付/校验清单未改。

发布前Windows长路径/只读索引的验证工具故障均保留失败记录并增加真实回归；没有修改运行库或放宽校验。本机网络连接重置的失败尝试也保留，最终两平台消费真实通过；临时传输转发仅到官方服务/其核对的CDN，客户端TLS和官方实际下载未替换。

阶段A 0.2.0必需交付已完成，无未完成的平台消费。仍不承诺其他SDK、所有文件系统、网络盘、恶意路径替换/断电事务保证、线程安全或稳定总耗时优势。未重新计时，不新增自动块长/Full/流式，不进入Commit25或阶段B。
