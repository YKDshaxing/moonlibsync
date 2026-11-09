# MoonLibSync 0.1.0 发布验收

0.1.0提供signature、delta、patch三项字节API，以及Windows/Linux Native单文件CLI源码；核心目标Native/JS/Wasm-GC。默认参数、profile、严格END、尾块、全量缓冲/资源契约、外部完整性责任及NTFS/ext4/DrvFS边界保持冻结范围，详见design/resources/cli/compatibility。delta不保证比new小；计时含启动、I/O和本CLI额外同步。

## 正式模块包

按[官方模块配置说明](https://docs.moonbitlang.com/en/stable/toolchain/moon/module.html)采用唯一.moonignore策略（不混用旧include/exclude）。固定工具链实际支持moon package --list、--frozen及moon publish --frozen --dry-run。正式包由moon package生成，不手工重打包冒充；实际格式/成员数/大小/哈希以audit.json为准。

归档保留库、CLI/示例、完整测试和相应夹具/工具、必要文档、许可证/版权及来源闭包。缓存、工具链、参考二进制、凭据、报告/临时文件排除。每个成员须无路径逃逸/重复/链接，原始字节与候选源对应。完整许可文本及来源索引被纳入逐成员审计，不以源码树中有LICENSE代替实际包检查。

仓库执行 `python scripts/release_check.py` 完成真实打包和仓库外workspace候选消费；三个目标各运行两个独立预期场景、公开默认值/类型与明确错误捕获，严格解析实际delta确认COPY。本地workspace结果只称候选包消费。`--clean` 额外从新检出源码安装固定工具链、取得依赖并运行三目标示例和Native文件流程，确认没有复用原构建结果，构建前后受审计字节一致。

普通CI执行上述候选检查及单列发布工具测试，不自动发布。它不代替Mooncakes身份、命名空间、精确版本可用性或发布后消费检查。

## 真实发布与注册表消费

正式上传使用[官方发布流程](https://docs.moonbitlang.com/en/latest/toolchain/moon/package-manage-tour.html)，所有前置门禁必须通过：Mooncakes身份/权限正确、0.1.0未占用、干净候选已推送、同SHA全部必需CI成功、实际包/许可审计通过、干净重建及候选包消费通过。Git认证/署名不代替注册表身份；dry-run不代替上传。普通CI不带发布凭据。

最终执行moon publish --frozen前后核对打包输入；网络结果不明先查询注册表，不盲目重发。上传成功但消费未通过时保留published-consumption-pending状态，不撤回、覆盖或擅自加版本。

发布后 `python scripts/release_check.py --registry` 在另一个仓库外新目录声明0.1.0，使用公开注册表，不创建moon.work或path/Git替换，不把候选包复制到依赖目录。必须确认实际解析路径/版本/闭包，三目标恢复、真实COPY、默认值与公开错误捕获均通过，下载成员和字节与审计包一致。CLI从下载源码另行构建，明确不是预编译二进制。若服务重新压缩，归档字节差异与成员内容差异分别记录，源码差异不能忽略。

## 证据与源码归属

忽略目录 `_build/release-0.1.0/` 保存正式模块归档、audit.json、report.json、delivery.json、SHA256SUMS和logs。状态依次为unpublished-release-candidate、published-consumption-pending、published-and-consumer-verified，只在对应实际事件发生后转换。

交付记录区分功能冻结SHA、publication_source_sha和发布后文档SHA；记录模块/版本、当前身份（不输出凭据）、权限/版本/标签/Release检查、实际包/逐成员哈希、许可审计、干净重建、候选消费、同SHA CI及产物、上传命令/退出码/响应/实际时间来源、Mooncakes页面与下载来源、三目标注册表结果及CLI边界。后续仓库文档不自动改变注册表内文档。

Commit15基准是原环境、原二进制的历史测量。Commit16只调整CLI版本展示/对应断言及模块描述，不改算法；运行文件指纹的具体变化在交付记录中记录，不重跑测量来换SHA、不宣称发布二进制与旧测量字节相同。本笔不默认创建GitHub标签、Release或安装器。

## 0.1.0 实际发布与消费结果（2026-11-09）

- 功能冻结：857aa981debc3ce0c1e54176621e84454733202e。
- 正式发布源码：f62958eceda9deecc4eae8a14007f5be76c59b0e；[发布源同SHA三项必需CI](https://github.com/YKDshaxing/moonlibsync/actions/runs/42594652417)全部成功。首轮Windows取消后由用户在网页重跑成功，Linux成功结果保留。
- 本段属于后续证据文档提交，具体文档SHA见交付记录；不能代替上述发布源。注册表中的README等文件仍来自发布源，不随本次仓库文档更新。
- [Mooncakes 0.1.0 页面](https://mooncakes.io/docs/YKDshaxing/moonlibsync@0.1.0/)及[公开版本元数据](https://mooncakes.io/api/v0/manifest/YKDshaxing/moonlibsync@0.1.0)已实际访问200。注册表created_at为2026-11-09T13:25:46.635422+00:00，即北京时间2026-11-09 21:25:46.635422；以服务端字段为时间来源。
- 实际官方ZIP为YKDshaxing-moonlibsync-0.1.0.zip，268008字节、179个文件成员，SHA-256 `07d6ea0ffbc77df9a3b9d2b792ee3ca0192a8527adec8da8c5c5926019a0dd96`。每个成员已核对发布Git提交的原始字节、完整许可证/来源及路径安全。Linux/Windows CI生成包的成员内容相同；容器哈希分别保留，不强求跨平台压缩字节相同。
- 上传前确认Mooncakes身份YKDshaxing、版本未占用、干净源码已推送、同SHA CI、审计、干净重建、候选三目标消费均通过。固定客户端`--frozen`在临时解包目录缺依赖处失败；标准dry-run完整校验并返回202。用户明确允许保留工具链/依赖而改用标准 `moon publish`，实际命令退出0、服务器200。源码/锁及上传包前后哈希不变，没有升级或关闭包验证。
- 公开注册表独立消费者位于仓库外新目录，重新安装固定工具链，空注册表缓存，未创建moon.work/path/Git替换；实际解析YKDshaxing/moonlibsync0.1.0、mooncrypt0.4.5、moonbase0.4.2、moondate0.1.0、moonrand0.1.0。下载ZIP与审计ZIP的压缩字节哈希也相同，179个模块文件及元数据逐字节一致。
- 注册表API消费实测环境为Windows11/NTFS，Native、JS、Wasm-GC各运行相同文件和小替换两个场景，独立new恢复相等；签名均300字节，delta分别9/2065字节，COPY分别16384/14336字节。公开默认2048/32与TruncatedInput错误捕获在三个目标均通过。不是把消费者次数计作新增库测试。
- 从实际下载模块另行构建Windows Native CLI，版本MoonLibSync0.1.0，三命令恢复/COPY验证通过。它是**注册表包源码构建**，没有预编译二进制。Linux/ext4的同SHA候选包三目标及CLI由CI验证，内容与下载包一致；没有额外声称本机WSL直接注册表消费成功。
- 首次注册表消费者在工具链下载阶段遇到TLS中断，日志单独保留；第二次在全新目录完整重试通过，没有重传发布版本。原基准和冻结证据未重跑或改写。

最终状态为 `published-and-consumer-verified`。原99项库测试、Python工具6项、两平台Native辅助各6项、Windows83/Linux81项CI集成、三目标示例、274/496/3968互操作、原82/29次消费及全部失败门禁保留通过；发布工具4项另计。交付记录和SHA256SUMS位于 `_build/release-0.1.0/`。本笔未创建GitHub标签、Release或安装器，未进入后续功能开发。

严格重放0.1.0的包字节/注册表对照，应在发布源 `f62958eceda9deecc4eae8a14007f5be76c59b0e` 的干净检出运行检查器。后续文档HEAD生成的候选归档包含不同的证据文档，不能拿它替代已发布的179成员原包；CI在后续提交生成的候选产物也不是再次发布。
