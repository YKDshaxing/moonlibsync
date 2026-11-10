# 阶段 A 组合与候选消费

Commit 23仅整合验证。公开API、默认Limits、检查JSON schema1、清单schema1与标准SIG/DELTA均不改；新增API仍未发布。五层边界见[设计说明](../../docs/design.md#commit-23阶段-a-组合验证开发源码)；资源检查的具体时机见[资源表](../../docs/resources.md#commit-23阶段-a-资源契约汇总)。

## 固定计划

`plan.json`包含16个原参考用例以及bytes/pairs/blocks三个四目标组，共28对不同输入、28参数用例、19签名组。生成规则在scripts/stage_a_data.py，引用原fixture_data.cases但不改其数据；显式字节或SHA256(big-endian counter)序列可独立重建。每组的old/new长度、完整SHA-256、参数及每个生成器必须满足的COPY门槛均在计划里，执行前比较；还锁定两个输入生成文件的LF源码哈希。

计划SHA-256：`5f02d159961131c569582b306ae6a48ddf794bb10906f8d2492f204c913174e9`。覆盖block 1/2/7/16/64/2048及strong 1/16/32，按代表用例分配，不扩展全参数笛卡尔积。场景包含同一旧版本的多目标、相同/全异/局部修改（全异目标仅含old中不存在的0x7f，实际要求三种生成均COPY=0）、前插、块移动、重复块、短尾与尾块移中、空/零字节/高位字节。

每个参数用例执行两种SIG来源（固定rdiff、MoonBit），三种delta生成（rdiff、一次性、Prepared），三种恢复（rdiff、patch、verified_patch）：全部18路径，合计504次。上游只理解标准SIG/DELTA；清单由本项目API制作/消费，不能称为rdiff原生支持清单。

| 项目 | 预期执行数 |
|---|---:|
| 独立输入对 / 参数用例 | 28 / 28 |
| 签名组 / 实际SIG文件 | 19 / 38 |
| 同参数完整SIG比较 | 19 |
| 准备对象 / 复用生成调用 | 38 / 112 |
| 其中第二次确定性复验 | 56 |
| 多目标对象 / 其生成调用 | 6 / 48 |
| 每种delta生成的实际文件 | 56（共168） |
| inspect_signature / inspect_delta / check_patch | 各168 |
| basis-info / update-manifest | 38 / 168 |
| 每种恢复 / 总恢复 | 168 / 504 |

每个签名组在同一Native进程准备一次，处理所有目标，并对每个目标调用两次prepared.delta核对确定性；112调用不伪装为112独立新文件。一次性与复用的56份输出逐字节一致。每个delta均被严格Python检查器独立读取，检查实际COPY及每段输出；API检查统计与独立解析逐字段对照。每份清单由独立Python json/hashlib核对全部字段，再由公开parse/verified_patch消费。两条发送路径运行期间实际移除OLD，接口也没有OLD参数。

在固定工具链且固定rdiff已构建后执行 `python scripts/check_stage_a.py`（Linux Native）。报告在 `_build/stage-a/{plan.json,report.json,commands.log,failures/}`；每个数有预期、实际、状态，失败不汇总为通过，临时输入清理前归档。记录实际SHA、dirty、可执行路径/哈希及每组输入哈希。Windows/DrvFS不是该上游组合入口的执行环境；本机Linux组合在干净或明确记录dirty的ext4临时检出执行，CI使用同SHA干净Ubuntu检出。

## 实际候选包消费与拒绝矩阵

PowerShell：`$env:MOONLIBSYNC_RELEASE_DIR='_build/stage-a-candidate'; python scripts/release_check.py`。Linux：`MOONLIBSYNC_RELEASE_DIR=_build/stage-a-candidate python scripts/release_check.py`。目录配置只影响验证工具，不新增产品CLI参数。原工具默认release-0.1.0目录不用于本笔；CI也显式配置开发候选目录，不覆盖正式发布归档。仅本机已有锁定索引时可沿用MOONLIBSYNC_OFFLINE_INDEX=1；报告注明缓存模式，CI正常更新索引，依赖声明与工具链不变。

实际moon package候选解压在仓库外的package目录；moon.work显式列出package与stage-a-consumer，公共程序只导入模块@lib，`moon tree --json`核对实际解析路径就是该解包目录。`consumer.mbt.txt`在两平台三个目标运行：三项统计有独立预期，准备一次处理两个目标，16种拒绝后再次成功；另有每目标3次私有字段/构造编译拒绝及正常复验。它们不计入166项根包测试，也不属于公开注册表消费。

`rejections.json`列出16个核心拒绝类别，其中12个适用于产品CLI（prepared对象四类没有CLI等价入口）。每目标核心覆盖：当前更严字节/记录/block限制、同对象扫描耗尽后复用、OLD/SIG错配、INFO/SIG错配、等长错误basis、损坏delta、错误result长度/摘要、合法literal恢复内容错误、重复键/歧义schema、64KiB/深度2/字段16边界。包内源码构建的真实产品CLI每平台执行24项检查（含12类拒绝），分别覆盖三项检查命令和完整发送/接收流程，核验输入/已有输出未变、失败无最终/临时输出，最后正常调用成功。

新增消费者故障门禁将独立signature字节预期52改为53，实际CI消费者检查脚本必须返回非零，再恢复重跑成功；另破坏实际MANIFEST结果摘要，产品CLI失败且无输出，再恢复成功。既有failure_gates.py也增加受校验产品CLI包装入口的坏清单/正常复验，验证非零传播到外层脚本。所有故障只在临时副本/临时消费目录操作，不污染正式夹具。

旧范围保留：两平台三目标各166库测试、CLI314/315和各15辅助、274对/496参数/3968恢复、82/29消费、32次Prepared恢复、Python工具/示例/封装及原失败门禁。基准仅原工具self-check及Prepared恢复，不重新计时。不合并这些不同计量为“案例总数”。

Commit24尚待：精确版本与身份检查、功能/接口冻结、最终实际分发包及许可证审计、干净目录重建、发布源SHA/必需CI关联、Mooncakes实际新版本发布、无workspace替换的独立注册表消费及发布证据归档。本笔不创建标签或Release。

Windows首次CI暴露新消费者诊断日志依赖系统CP1252编码的缺口；新工具文本读写显式使用UTF-8。候选消费步骤固定PYTHONUTF8=0、PYTHONIOENCODING=utf-8，仍实际编译并保存包含Unicode的三目标私有字段拒绝诊断，使该编码环境进入持续回归；不放宽任何拒绝或恢复检查。运行库不涉及此修复。
