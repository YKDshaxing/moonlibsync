# Commit 26：Delta／完整文件选择（开发源码，尚未发布）

当前 Git 源码增加更新规划及 schema 2；已发布0.2.0原包不包含这些接口。版本保持0.2.0。本笔不发布、不建标签或Release，止于Commit26，版本决定、阶段B最终验收及注册表消费留待Commit27。

## 公开 API 与固定选择规则

| 入口 | 参数 | 返回及错误 |
|---|---|---|
|plan_update|SIG:Bytes, NEW:Bytes, UpdateOptions, Limits|UpdatePlan raise SyncError|
|create_transfer_manifest|BasisInfo, SIG:Bytes, NEW:Bytes, candidate DELTA:Bytes, UpdateOptions, Limits|TransferManifest raise ManifestError|
|parse_transfer_manifest|JSON:Bytes, Limits|TransferManifest raise ManifestError|
|encode_transfer_manifest|TransferManifest, Limits|Bytes raise ManifestError|
|apply_update|basis:Bytes?, payload:Bytes, TransferManifest, Limits|Bytes raise ManifestError|

`UpdateOptions { min_savings_bytes:Int64 }` 默认0，负数为 `InvalidOptions("min_savings_bytes")`。`UpdatePlan { payload:UpdatePayload, decision:UpdateDecision }`；payload为 `Delta(Bytes)` 或 `Full(Bytes)`。这些字段均不可变，没有公开扫描状态或工作余额。

plan_update先验证全部Limits、选项，再调用原delta，成功后按实际长度选择。设N为NEW长度、D为实际候选delta长度、M为阈值，**仅D<N且N-D>=M时选择Delta**。平局、delta更大、收益不足均Full；M=0仍要求严格更小。只在D<N时做减法，不计算D+M，Int64.MAX阈值合法。

decision保存kind（librsync-delta/full-file）、reason、new_bytes、delta_bytes、payload_bytes、savings_bytes、min_savings_bytes。稳定reason为 `minimum-savings-met`、`delta-not-smaller`、`below-minimum-savings`。savings_bytes为**选中负载**相对NEW实际省掉的字节数，Full恒0；候选D仍保留。只比较负载，不含清单、路径或协议开销，不代表实测网络节省。

Full负载就是NEW原始字节。没有小文件提前绕过生成，损坏/不支持签名、签名限制、delta输出预算或工作预算等错误原样传播，不能捕获后返回Full。原delta和PreparedSignature::delta始终返回标准delta；policy v1与默认2048/32不变。

## schema 2 独立于 schema 1

`TransferManifest::Delta(UpdateManifest)`复用旧描述符数据存储，但新编码使用schema_version数值token `2`和字段 `payload`，不是旧 `delta` 字段。`TransferManifest::Full(FileDigest,FileDigest)`依次保存payload/result。公开可构造数据每次重验，不是已经验证的凭证。

Delta根字段精确为schema_version、kind、basis、signature、payload、result，kind为librsync-delta，payload是标准librsync delta。Full根字段精确为schema_version、kind、payload、result，kind为full-file；没有虚构的basis、signature、delta或空占位。Full两描述符长度、摘要必须相同。独立固定编码样例见[Delta](../tests/transfer/schema2-delta.json)与[Full](../tests/transfer/schema2-full.json)，每份以LF结尾。

长度为规范十进制字符串，摘要为64位小写SHA-256。沿用64KiB输入、容器深度2、总对象字段最多16、严格UTF-8、拒绝BOM/重复键/未知字段/类型错配/非规范长度；schema2 Delta为14个总字段，Full为8个。字段计数在JSON树构造后检查；此前输入/深度限制约束树分配，并非流式解析或分配前字段计数。schema1旧解析器拒绝schema2，新解析器只接受schema2，未知版本/kind或混合字段拒绝。决策原因和候选D不进入清单。

create_transfer_manifest不接收OLD。两分支都先执行原create_update_manifest的INFO/SIG绑定、大小检查、标准delta结构/COPY范围预检及预计输出长度核对，再选择并绑定实际负载。因此选Full也不跳过坏候选检查。制作无法证明候选真的恢复NEW，接收端最终摘要核验才确认结果。

## 应用顺序与资源

apply_update依次：全部Limits合法性 → 公开清单描述符格式/适用预算/Full一致性 → 分支实际检查。

Delta要求Some(basis)，缺失为InvalidField("basis")；复用verified_patch全部逻辑：实际old/delta预算与长度、basis摘要、payload摘要、严格delta解析和COPY范围、分配恢复前的预测长度、原basis COPY执行、最终结果长度/摘要。SIG描述只随清单传递，接收端没有SIG参数，不表示实际核验了SIG文件。

Full不读取、哈希或依赖传入basis（即使API提供Some也不用），不解析魔数、不执行delta。payload声明受max_new_bytes，result声明受max_output_bytes；再检查一致性、实际payload两个字节上限、长度及摘要，成功才返回原payload。合法但不适用的max_old_bytes/max_delta_bytes/max_match_work等零值不会阻止Full，非法Limits仍优先拒绝。Full不使用max_delta_bytes上限。

沿用ManifestError所有既有变体；描述符超预算为ResourceLimit(字段)，描述符不合法为InvalidField，内容绑定错误为BindingMismatch，原核心错误封装为Core且不降级。Delta payload沿用旧内部字段名，错误标签仍为delta_length/delta_sha256；Full为payload_length/payload_sha256。所有失败不返回未验证结果，不改输入，后续调用可复用。

全缓冲：SIG/NEW、索引与候选指令、完整候选DELTA可能同时存在；选择后Full返回NEW引用，不代表生成期间省掉候选成本。编码/解析还可持有JSON树、字符串、UTF-8转换及摘要缓冲；应用Delta另有恢复缓冲。没有实测峰值，也不承诺进程总内存上限、输入快照、发布者认证或断电持久化。清单必须来自可信来源。

## 两个单输出 CLI

```text
moonlibsync make-transfer-manifest INFO SIG NEW DELTA MANIFEST [--min-savings N]
moonlibsync apply-update PAYLOAD MANIFEST OUT [--basis OLD]
```

发送端有界读取INFO/SIG/NEW/已有DELTA，验证全部候选输入，只输出一个schema2清单；不重新生成DELTA，不复制NEW、不做双文件事务。按kind发送输入DELTA或输入NEW。

接收端先读并解析最多64KiB清单，再按kind决定payload上限及basis要求。Delta必须显式--basis；Full携带--basis为用法错误，且不打开这个路径。所有校验完成才调用原发布器创建同目录CreateNew临时、完整写/sync/close、无覆盖提交。路径别名、输入保护、部分写、同步、竞争和清理规则均保留；0/2/1退出码，写命令成功stdout为空，失败stderr诊断。保留选项位置、`--`和字面`-`。Linux .exe仍为ELF；NTFS/ext4正向保证和DrvFS不支持提交时明确失败的边界不变。

## 运行示例及证据

```bash
moon run examples/transfer --target native
moon run examples/transfer --target js
moon run examples/transfer --target wasm-gc
python scripts/check_transfer.py
```

[公开示例](../examples/transfer/main.mbt)实际运行SIG/INFO→plan_update→制作/编码/解析schema2→apply_update→独立NEW比较，两分支都执行。16字节相同NEW生成8字节delta，默认及收益阈值8选Delta，阈值9或Int64.MAX选Full；8字节NEW、8字节delta平局选Full；3字节全异NEW生成9字节delta选Full。

新增15项库测试与2项Native辅助；原179/17项范围保留。新增CLI49项（含实证权限失败），原343/344项保留；本机缺链接权限时相应原可选场景仍单列未执行。候选包解压到仓库外，用独立消费者在三目标运行两分支，并用包源码CLI执行48项新检查；编译后重验包原始字节。这里只是候选包workspace消费，不是注册表消费。

check_transfer固定librsync v2.3.4 / e364852674780e43d578e4239128ff7014190ed3，运行真实release CLI和公开规划示例。8个决策样本中2个Delta交给固定rdiff恢复，6个Full直接校验原始字节，**Full不计librsync恢复次数**。原严格检查器另读全部候选delta。原始命令、退出码、选择/清单/大小/哈希、失败与恢复记录位于 `_build/commit26/reference/`；最终SHA/CI/包校验在提交后 `_build/commit26/delivery.json`，不为写自身SHA追加提交。

原3968恢复、阶段A504、82/29消费、Prepared32、Commit25的35签名/70跨恢复及旧工具/包安全/示例/失败门禁保留，新增协议计数单列。候选包仍写_build/stage-b-candidate，历史发布/冻结/基准目录不改。本笔不重跑耗时基准，不声称总传输量或性能普遍改善。
