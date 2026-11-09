# 0.1.0 发布验收记录入口（Commit 16）

功能冻结SHA为857aa981debc3ce0c1e54176621e84454733202e。0.1.0交付三项字节API、指定标准格式/资源契约、Native单文件CLI及核心三目标。正式归档、干净重建、候选包消费、发布身份/上传和无替换注册表消费逐项独立验收；提交前状态及日志在 `_build/release-0.1.0/`，实际结果由提交后交付记录提供，不能由本页能力描述推断上传成功。

[发布说明](release.md)列出门禁、实际源码与包内容的关联方式。候选发布源必须干净、已推送且同SHA全部必需CI成功。后续发布证据文档提交不改变注册表内原文档，也不能替代publication_source_sha。以下完整保留Commit15与Commit14快照，旧未发布状态归属各自阶段。

# Commit 15：当前阶段验收与功能冻结

基线925d47979549da4e8e3c32b742806513478346e6。当前已完成有限基准、使用/设计文档与首版功能冻结；运行库、CLI执行代码、默认值、锁和正式夹具保持基线。最终冻结SHA、同SHA全部必需CI、原始产物校验和测量/最终源码关联，在提交后交付记录提供，不为自身SHA另增提交。

| 原规划要求 | Commit15当前实现/交付状态 | 实际证据及目标 | 源码归属与未完成项 |
| --- | --- | --- | --- |
| 1 MoonBit为主，moonc>=0.10.16 | 固定0.10.20+65efd5b93与既有依赖闭包；核心/CLI仍为MoonBit | toolchain.lock、dependencies.lock、check.py三目标；Linux release基准 | Commit1–14执行代码不变；不承诺全部更高版本 |
| 2 GitHub公开，提交清晰 | 既有YKDshaxing仓库，Commit15独立工具/文档提交 | git历史、最终同SHA CI与交付记录 | 未代替发布身份/模块权限检查 |
| 3 结构清晰，核心功能完成 | 三API、现有标准格式/资源/CLI/目标范围冻结 | compatibility.md冻结表、tests/benchmarks/runtime-baseline.json的20文件指纹 | 运行代码归属Commit1–14，冻结15；不是0.1.0整体交付完成 |
| 4 README可复现 | 源码获取、公开导入、完整运行示例、错误/边界与基准说明 | README、design.md完整basic代码、现有三目标实际运行；CLI两平台 | 当前为源码消费；正式包解压与独立注册表消费待16 |
| 5 CI覆盖检查/构建/测试 | 保留原3任务和全部必需检查，增加小型基准工具正确性入口 | 同SHA三任务，benchmark.py --self-check（无完整计时或速度阈值） | 原覆盖不缩减，提交后报告实际状态 |
| 6 至少一个可运行例子 | 每平台三目标basic，实际COPY与恢复；Linux正式CLI/rdiff两条交换 | examples/basic、check_example.py、file_exchange.py | Commit14示例继续验证；不是已安装发布包消费 |
| 7 完整核心测试 | 各目标99；Python6；两平台Native辅助各6及平台集成；274/496/3968；原82/29；所有失败门禁 | check.py、cli_smoke、interop、consume脚本、failure_gates；基准另120预热/420正式，不混入测试 | Commit15没有增加库测试或用基准替代原回归；范围仍有限 |
| 8 发布Mooncakes | **未发布**，0.1.0仅开发元数据，无独立注册表证明 | 未发布声明；没有执行moon publish | 身份/精确版本检查、实际发布、无本地替换消费均待16 |
| 9 OSI许可证及上游授权 | LGPL-2.1-or-later、来源及第三方说明保留，新增工具明确原创/标准库调用 | COPYING.LESSER、COPYING、SOURCES、THIRD_PARTY_NOTICES | 源码许可文件存在不等于实际源码包分发审计通过，待16 |

有限基准在WSL2/Linux Native/ext4实际完成：两规模五类场景，参数2048/32，release正式CLI对固定rdiff Release，2预热+7正式交替顺序，三项操作全校验。patch两端使用相同rdiff delta。结果、min/median/max、实际大小/COPY/指令数、原始文件校验及结论边界见[基准](benchmarks.md)。运行时HEAD为基线且dirty=true，不冒充最终干净提交；交付前逐文件关联最终冻结源码，配置/依赖/执行代码变化必须重新测量。

冻结[公开接口/默认值/profile/标准指令/错误资源/CLI/目标及范围外清单](compatibility.md#commit-15首版功能冻结)。Commit16尚须完成：精确版本与发布身份检查；实际源码包和许可证分发审计；干净目录重建；发布源SHA与必需CI对应；Mooncakes实际发布；无本地替换的独立注册表消费；发布后证据归档。此七项没有在本笔执行；未创建标签、Release或上传。

## Commit 14 历史验收快照

以下完整保留Commit14记录；其中“未测基准/未冻结”等只属于当时阶段，不作为Commit15当前状态。

# Commit 14：九项阶段验收

本表逐项沿用原《MoonLibSync 远端签名差分库开发与验收规划书》“九项验收要求对应”的九行，不将规划当作结果。阶段基线为 Commit 13 `d605522738066ee2494b2b5306dd1b7d217ffeef`；本笔增量为示例、CI整合、失败门禁及文档。提交前采用稳定证据入口；最终源码SHA、同SHA CI与产物链接由提交后交付报告提供，不为补记自身SHA追加循环提交。

| 要求 | 当前实现或交付状态 | 实际命令／证据位置 | 验证目标与环境 | 源码提交归属 | 未完成项 |
| --- | --- | --- | --- | --- | --- |
| 1 MoonBit 为主，moonc >= 0.10.16 | 核心、CLI和示例为MoonBit；固定moonc 0.10.20+65efd5b93，moon/moonrun 0.1.20261104；依赖mooncrypt0.4.5 | `python scripts/check.py`；toolchain.lock.json、dependencies.lock.json及CI版本输出 | Windows/Linux，核心Native/JS/Wasm-GC | 工具链/依赖Commit1，算法Commit2–12，CLI13，示例14 | 没有验证所有更高版本；未承诺0.10.16本身可编译 |
| 2 GitHub 公开，提交清晰 | YKDshaxing/moonlibsync公开仓库；逐阶段独立提交，固定SSH归属 | 仓库匿名页面、`git log`、`git remote -v`；最终交付提供推送SHA | GitHub公开源码；推送认证与提交署名分别核对 | Commit1–14历史 | 不代表Mooncakes命名空间权限或发布成功 |
| 3 结构清晰，核心功能完成 | 三项公开字节API；标准RK+BLAKE2签名；全部delta指令解析；只凭签名生成增量；Native单文件CLI | pkg.generated.mbti、signature.mbt、delta.mbt、patch.mbt；`bash scripts/interop.sh`；docs/cli.md | 核心三目标；跨实现仅Linux Native；CLI Windows/NTFS、Linux/ext4 | 算法Commit2–12，CLI13；整合14 | 全量缓冲、单文件；无网络、目录同步、流式；首版冻结待后续 |
| 4 README 可复现 | 当前使用入口前置；固定工具链安装、依赖、示例、CLI及完整检查命令 | README.md；`python scripts/install_toolchain.py` 后按README运行；干净CI checkout实际执行 | Windows与Ubuntu24.04独立CI环境；本机WSL正向CLI用/tmp ext4 | 原说明Commit1–13；当前入口与历史分离14 | 独立正式源码包解压复现及注册表消费者待后续，不以本地源码示例抵扣 |
| 5 CI 覆盖检查/构建/测试 | 保留3任务：Linux参考，Windows及Ubuntu基础；核心check/build/test；三目标示例；CLI；资源、接口与隔离失败门禁 | .github/workflows/ci.yml；scripts/check.py；`python scripts/failure_gates.py`；_build/resources、interfaces、examples、gates、cli、interop、exchange | 固定工具链；Native/JS/Wasm-GC；rdiff仅Linux Native | 原任务Commit1–13，整合/门禁14 | 同SHA实际状态与产物在提交后报告；产物上传不代替检查通过 |
| 6 至少一个可运行例子 | examples/basic仅导入公开库；实际恢复断言；严格检查本次delta COPY>=512且delta<515；CLI/rdiff两条真实文件链 | `moon run examples/basic --target TARGET`；`python scripts/check_example.py --target TARGET`；`python scripts/file_exchange.py`；_build/examples与exchange | 纯字节示例Native/JS/Wasm-GC；文件交换Linux Native/ext4 | 示例及文件交换14，正式CLI13 | 不代表三目标均调用rdiff，不代表安装发布包后消费 |
| 7 完整核心测试 | 原99项库测试（含19资源项）；6项Python工具；6项Native CLI辅助；平台CLI场景；274输入对/496参数/3968恢复；原82签名/29delta消费；重建与损坏拒绝 | scripts/check.py、cli_smoke.py、interop.sh、consume_signature.py、consume_delta.py、rebuild-reference.sh；tests/interop/README.md | 三目标根包分别99；工具/CLI/示例独立计数；固定参考v2.3.4 | 核心Commit2–12、CLI13；14保持范围并新增隔离断言失败验证 | 有限确定性矩阵不是任意输入证明；Windows链接未执行项按实际报告，不计通过；基准/峰值内存未执行 |
| 8 发布 Mooncakes | **未发布**；0.1.0仅为开发元数据 | moon.mod、README未发布声明；没有执行moon publish | 本地源码与CI消费，不是注册表消费 | Commit1元数据，14明确边界 | 账号/命名空间权限、版本可用性、正式包审计、实际发布、无本地替换的外部消费全部待后续 |
| 9 OSI 许可证，遵守上游授权 | LGPL-2.1-or-later；保留完整许可文本及来源/第三方说明；核心不用C librsync FFI，参考工具只用于测试 | COPYING.LESSER、COPYING、SOURCES.md、THIRD_PARTY_NOTICES.md；固定上游SHA与文件级说明 | 源码树与离线夹具来源；依赖闭包按锁核验 | Commit1–13来源记录，14示例SPDX沿用 | 源码文件存在不等于最终分发包审计完成；实际入包内容及义务核对、最终源码包验收待后续 |

## 证据边界与统计

纯字节示例基准输入固定512/515字节，签名300字节。本机三目标实际delta18字节、COPY512，所有恢复相等；门槛仅要求delta<515、COPY>=512，不锁定未来18字节。每个平台正常示例3次单列；隔离故障驱动另运行损坏/正常示例各一次，不计为新增库单元测试。根包仍为99，Python工具仍为6，CLI辅助仍为6；各平台集成数量由本次CLI报告给出（具备Windows链接能力时83；无权限时79通过、4未执行；Linux81）。

Linux固定参考的完整正常矩阵仍执行一次，八组合各496，共3968恢复；两条CLI文件交换演示另列，不追加到矩阵数中。原参考16用例/64文件/12507字节与29个手写opcode向量均不刷新。损坏验证不重复全矩阵。失败门禁命令与结果见 `_build/gates/report.json`：`check_fixtures.py -> verify_fixtures.py` 和 `check_example.py -> moon run` 是CI实际使用的调用链；包装层 `check=True` / `check_returncode` 将非零继续传给 `check.py` 及无容错CI步骤。分别保存broken与normal日志，驱动仅在目标诊断和退出码符合预期时成功。

接口保护显式列根包、probes/digest、probes/native、probes/signature、cmd/moonlibsync、examples/basic。首先与HEAD受检接口原始字节比较（含删除），再保存存在/缺失状态，最后比较moon info后状态；不扫描缓存、构建树。固定工具链为basic生成空公开接口，已纳入提交；其他Native可执行包当前没有生成接口，其缺失状态也受检。

报告中的源码SHA与dirty取自实际Git；本地提交前执行为dirty，仅作为阶段调试证据。最终干净同SHA CI的日志与产物才作为提交交付证据。固定工具链/核心三目标验证、Linux参考兼容、CLI文件系统保证、源码许可证、正式分发审计及公开注册表消费是不同证据，不能互相替代。NTFS/ext4的正向结果不扩展到DrvFS；无覆盖重命名不支持时继续明确失败。

停止于Commit14。没有开展benchmark，没有修改默认预算、核心公开API、锁文件或正式夹具；没有进入Commit15首版冻结、打包、标签、Release或Mooncakes发布。
