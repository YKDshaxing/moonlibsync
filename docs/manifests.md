# Commit 21：独立完整性清单（开发源码）

本笔提供SHA-256适配、basis-info与update-manifest的制作/解析/编码。清单在标准.sig/.delta之外，不改变magic、头部、END或已有检查CLI的JSON schema。注册表0.1.0不含这些API；元数据版本不改。Commit 21 的数据层记录保留如下；Commit 22 现已补充受校验应用和文件流程，见末节。

## API与数据

| 入口 | 参数 | 返回（均 raise ManifestError） |
| --- | --- | --- |
| create_basis_info | OLD:Bytes, SIG:Bytes, Limits | BasisInfo |
| create_update_manifest | BasisInfo, SIG:Bytes, NEW:Bytes, DELTA:Bytes, Limits | UpdateManifest |
| parse_basis_info / parse_update_manifest | JSON:Bytes, Limits | 对应清单类型 |
| encode_basis_info / encode_update_manifest | 对应清单类型, Limits | UTF-8 Bytes，无BOM，末尾LF |

`FileDigest`包含`byte_length:Int64, sha256:String`；`BasisInfo`包含basis/signature；`UpdateManifest`包含basis/signature/delta/result。三种类型是可公开构造的不可变数据，不是可信凭证。编码及消费入口均重新校验字段、长度和资源限制。类型固定代表schema1；schema/kind由编码器写入，不提供通用JSON反射或公共摘要接口。

## 实际编码示例

下列为OLD=`abc`、2048/32标准签名（48字节）、COPY(0,3) delta（8字节）、NEW=`abc`的完整输出，均以LF结束。独立Python JSON/hashlib预期存于tests/integrity/basis.json和update.json；SIG由固定librsync2.3.4生成，非MoonBit编码器自生预期。

```json
{"schema_version":1,"kind":"moonlibsync-basis-info","basis":{"byte_length":"3","sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},"signature":{"byte_length":"48","sha256":"59a030db700124f21acc20a3563329bb1d90b64c8e8de59f19cbc0ead26c9573"}}
```

```json
{"schema_version":1,"kind":"librsync-delta","basis":{"byte_length":"3","sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},"signature":{"byte_length":"48","sha256":"59a030db700124f21acc20a3563329bb1d90b64c8e8de59f19cbc0ead26c9573"},"delta":{"byte_length":"8","sha256":"22120222ab5b762c88d44e81d72884fcd4ff5f2d82b02a6ae5edb0f56b3b1b53"},"result":{"byte_length":"3","sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"}}
```

输出固定字段顺序，不依赖Map遍历顺序；所有长度直接由精确Int64转十进制字符串，摘要固定64个小写ASCII十六进制字符。已验证的标量仅含数字/小写hex，不拼接未经转义的路径或命令。该约定不是通用密码学JSON规范或数字签名格式。

## 严格解析及顺序

解析顺序：全部Limits.validate → 输入最多65536字节 → core严格UTF-8解码 → 拒绝开头UTF-8 BOM → core完整JSON解析（max_nesting_depth=2，reject_duplicate_keys=true，preserve_number_repr=true）→ 最多16个对象总字段 → 根/嵌套字段集合、schema/kind、字段类型、受检长度、摘要格式与适用预算。

实际core按对象或数组容器计深度：根对象是1层，描述符对象是2层，描述符中的标量不增加容器深度；第三层容器拒绝。basis-info有8个总字段，update-manifest有14个。字段数在JSON树构造后递归检查，**不是在每次分配前阻止**；此前树/字符串分配由输入字节数和深度限制约束。数组最终不符合schema，输入限制不是进程堆/RSS上限，调用者的Bytes早已存在。

根和描述符必须是对象，字段集合精确：basis-info根4项、update根6项；每个描述符仅byte_length/sha256。拒绝缺失、未知字段、重复键（包括转义解码后相同的键）、多个根值、尾随非空白、错误类型、数组、过深/超大输入。允许JSON前后ASCII空白，BOM拒绝；不使用有损UTF-8。schema_version必须是数值token `1`，不接受字符串、1.0或1e0；kind必须精确匹配对应协议。

长度在JSON字符串解码后必须是`0`或非零数字开头的ASCII十进制；不接受符号、空白、指数、小数或多余前导零。先检查每次乘加不超Int64.MAX，之后应用预算，不经浮点或先转Int32。摘要必须完整64位小写hex。声明边界如下：

| 字段 | 最小长度 | 适用上限 |
| --- | --- | --- |
| basis | 0 | max_old_bytes |
| signature | 12 | max_signature_bytes |
| delta | 5 | max_delta_bytes |
| result | 0 | max_output_bytes |

解析或编码声明不证明实际文件存在、格式正确或内容匹配。解析清单不以max_new_bytes误限result声明；发送端收到实际NEW时另同时检查max_new_bytes与max_output_bytes。所有Limits配置字段仍须合法。

## 两端制作与绑定

接收端create_basis_info先验证Limits及OLD预算，再完整inspect_signature；按SIG头的block_len/strong_sum_len重新生成OLD签名，和SIG逐字节比较，通过后才计算OLD和SIG的完整SHA-256。它不是只分别哈希两个任意文件；同长度错误OLD也被拒绝。短签名摘要的既有碰撞语义不变，不把标准签名说成唯一文件身份。

发送端create_update_manifest的参数只有basis-info、SIG、NEW、DELTA、Limits，**没有OLD参数或文件系统查找**。顺序为：配置 → 重验公开basis-info → 实际SIG/NEW/DELTA大小（NEW同时受new/output预算约束）→ SIG长度与声明相等 → SIG完整格式 → SIG实际SHA-256与basis-info比较 → 用声明basis长度调用check_patch完整格式/范围预检 → delta预计输出长度等于NEW长度 → 保存DELTA/NEW实际长度及SHA-256，携带basis信息。

发送端并没有OLD，因此不能证明DELTA内容恢复成NEW。本笔测试刻意接受“合法literal xyz、NEW abc”的同长度清单，以明确这个边界；Commit22的verified_patch实际应用后对照结果摘要再返回/提交。伪造但格式合法的basis信息也不是认证凭证，SHA-256本身不提供发布者认证，清单必须来自可信来源；没有数字签名、密钥管理或认证协议。

## 错误、工作及内存

ManifestError单列Core(SyncError)、InvalidUtf8、InvalidJson、InvalidSchema、InvalidField(field)、BindingMismatch(field)、ResourceLimit(bound)、HashFailure。Core保留旧错误；公开接口不暴露JSON/UTF-8依赖错误类型。resource bound区分manifest_bytes/depth/fields以及具体文件预算，绑定错误区分basis_signature、signature_length、signature_sha256、result_length。旧SyncError未增加变体。

SHA-256来自固定mooncrypt0.4.5/hash/sha2，显式Kind::Sha256，输出必须恰好32字节，不截断、不用其他32字节算法冒名。每次调用前检查实际输入长度，SHA工作不计入原max_match_work；create_basis_info中签名再生成的BLAKE2/RK费用仍遵守原signature输入/输出预算。合法max_match_work=0不阻止这些制作操作。没有重新移植算法或升级依赖。

制作可同时持有调用者文件Bytes、解析记录/摘要、重新生成的完整SIG、摘要依赖工作存储、编码字符串/Bytes转换副本；发送端还可持有delta解析元数据。它们是全量缓冲流程，不是常量内存、流式或全进程峰值保证。所有失败不返回半份清单、不改变输入、无全局缓存，后续合法调用仍可成功。

## 验证归属

新增20项库测试（公开15、白盒5），保留原137项，各目标157项。SHA独立向量9组：空、abc、00/7f/80/ff，55/56/63/64/65/1024字节的(73*i+19)%256序列，完整输入hex和SHA-256预期在tests/integrity/vectors.json；`python scripts/verify_integrity_vectors.py`用hashlib/json独立复核，并由现有check.py调用。3组完整清单覆盖空/default、abc/default、one/非默认7/1参数；其编码逐字节对照独立预期。原正式16夹具、opcode、依赖锁及发布归档不刷新，性能基准不重跑。

以上为Commit21的157项测试归属；Commit22新增验证见下节。新增接口尚未发布。

## Commit 22：受校验应用与文件流程

`verified_patch(basis: Bytes, delta_bytes: Bytes, manifest: UpdateManifest, limits: Limits) -> Bytes raise ManifestError` 不接收 NEW、SIG 或路径。先验证全部 Limits、四个公开描述符及其预算、实际 basis/delta 字节上限，再核对实际长度（basis_length/delta_length）、完整 SHA-256（basis_sha256/delta_sha256），之后仅解析一次 delta，复用原 COPY 范围/累计输出预检和共享执行器。预计结果长度必须等于 result.byte_length（result_length），此检查位于恢复缓冲分配之前；执行后再次核对实际长度和完整 result_sha256，成功才返回 Bytes。所有错误不返回局部输出，不改变输入，没有跨调用工作状态。核心格式/范围错误封装为 ManifestError::Core，原 patch 的错误顺序不变。

signature 描述符仍接受格式、最小12字节和预算检查，但本入口没有实际 SIG，不能验证 signature.sha256 对应某文件。清单须来自可信来源；攻击者若可同时替换清单和内容，SHA-256不提供发布者认证。标准 delta 的 COPY 始终从原 basis 读取。工厂仍可接受合法 literal xyz / NEW abc 的同长度声明；受校验应用会以 result_sha256 拒绝。

字节调用见完整 [examples/verified/main.mbt](../examples/verified/main.mbt)，`moon run examples/verified --target native`（亦可 js / wasm-gc）。固定工具链 `check.py` 实际运行这三个目标的示例。CLI在固定工具链下用 `moon build cmd/moonlibsync --target native --release` 构建；默认路径 `_build/native/release/build/cmd/moonlibsync/moonlibsync.exe`，Linux ELF 同样保留 .exe 后缀。

下面是接收端与发送端分离的命令序列。每项输出必须尚不存在；OLD只在接收端，发送端目录只有复制来的SIG、INFO以及NEW。`moonlibsync.exe` 代表上面的实际构建路径；Linux当前目录执行时加 `./` 或使用绝对路径。

```text
# 接收端：准备旧文件关联
moonlibsync.exe signature OLD SIG
moonlibsync.exe basis-info OLD SIG INFO
# 将 SIG / INFO 送到发送端；此处不能获取 OLD
moonlibsync.exe delta SIG NEW DELTA
moonlibsync.exe make-manifest INFO SIG NEW DELTA MANIFEST
# 通过可信通道向接收端交付 MANIFEST，并传输 DELTA
moonlibsync.exe patch-verified OLD DELTA MANIFEST OUT
```

INFO与MANIFEST均以65536字节上限读取并复用严格解析器；OLD/SIG/NEW/DELTA分别使用现有 max_old/signature/new/delta_bytes。三条新增命令成功静默、退出0；用法错误2，文件/清单/核心错误1，stderr包含操作、输入路径、输出路径及错误分类。没有 --json、--force 或新参数，`--`之后按路径处理，单个 `-`是普通文件名。

输出预检只读；只有制作/校验完全成功后，才进入已有 CreateNew临时文件→完整写入→文件同步→关闭→无覆盖提交的流程。每个输入与输出同路径（包括INFO/MANIFEST）、现存输出文件/目录/链接均拒绝。保留原NTFS/ext4保证；DrvFS不支持该提交原语时失败，不降级覆盖。失败只清理本次独占创建的临时路径；清理失败报告原错误及清理错误。并发路径替换、输入同大小变化、崩溃/断电和目录持久化边界仍见CLI文档，不承诺快照或事务。

本笔新增9项库测试，原157项保留，各目标166项；覆盖16组上游参考、3组独立清单、18组参数/内容组合和伪造字段/格式/预算/结果拒绝。Native辅助新增3项，原12项保留，总15项，单列同步失败清理及失败后复用、验证失败零发布回调。CLI新增案例由独立hashlib/json核对绑定；真实移走OLD后执行delta和make-manifest，再恢复OLD校验OUT。新增案例与原214/215项分列，不计入库测试。现有部分写入、提交竞争及清理失败测试继续使用同一发布器。原0.1.0归档、默认预算、依赖锁及正式夹具未改，未重新测量性能；Commit23的完整功能矩阵整合仍待后续。

## Commit 23：阶段 A 组合验证（开发源码）

新组合流程对38份basis-info与168份update-manifest逐字段核对独立Python json/hashlib预期，再用公开parse/verified_patch恢复。清单制作不证明恢复内容；check_patch不检查身份；verified_patch不接收SIG，只实际核验OLD/DELTA/结果，仍依赖可信清单而非发布者认证。16个核心拒绝类别及适用的12个真实CLI拒绝类别见[阶段A说明](../tests/stage-a/README.md)。

候选消费使用明确本地workspace替换，不是注册表消费。复用未观察到稳定总耗时优势，仍为全量缓冲；本笔不重新计时、不改写0.1.0历史发布证据。Commit24的版本决定、冻结、最终包/许可证审计、发布SHA/CI绑定、Mooncakes新版本发布及无替换注册表消费仍待后续，不创建标签或Release。
