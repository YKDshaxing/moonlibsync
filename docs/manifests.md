# Commit 21：独立完整性清单（开发源码）

本笔提供SHA-256适配、basis-info与update-manifest的制作/解析/编码。清单在标准.sig/.delta之外，不改变magic、头部、END或已有检查CLI的JSON schema。注册表0.1.0不含这些API；元数据版本不改。**尚无受校验patch、清单CLI或文件提交**，这些留给Commit22。

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

发送端并没有OLD，因此不能证明DELTA内容恢复成NEW。本笔测试刻意接受“合法literal xyz、NEW abc”的同长度清单，以明确这个边界；Commit22必须实际应用后对照结果摘要再返回/提交。伪造但格式合法的basis信息也不是认证凭证，SHA-256本身不提供发布者认证，清单必须来自可信来源；没有数字签名、密钥管理或认证协议。

## 错误、工作及内存

ManifestError单列Core(SyncError)、InvalidUtf8、InvalidJson、InvalidSchema、InvalidField(field)、BindingMismatch(field)、ResourceLimit(bound)、HashFailure。Core保留旧错误；公开接口不暴露JSON/UTF-8依赖错误类型。resource bound区分manifest_bytes/depth/fields以及具体文件预算，绑定错误区分basis_signature、signature_length、signature_sha256、result_length。旧SyncError未增加变体。

SHA-256来自固定mooncrypt0.4.5/hash/sha2，显式Kind::Sha256，输出必须恰好32字节，不截断、不用其他32字节算法冒名。每次调用前检查实际输入长度，SHA工作不计入原max_match_work；create_basis_info中签名再生成的BLAKE2/RK费用仍遵守原signature输入/输出预算。合法max_match_work=0不阻止这些制作操作。没有重新移植算法或升级依赖。

制作可同时持有调用者文件Bytes、解析记录/摘要、重新生成的完整SIG、摘要依赖工作存储、编码字符串/Bytes转换副本；发送端还可持有delta解析元数据。它们是全量缓冲流程，不是常量内存、流式或全进程峰值保证。所有失败不返回半份清单、不改变输入、无全局缓存，后续合法调用仍可成功。

## 验证归属

新增20项库测试（公开15、白盒5），保留原137项，各目标157项。SHA独立向量9组：空、abc、00/7f/80/ff，55/56/63/64/65/1024字节的(73*i+19)%256序列，完整输入hex和SHA-256预期在tests/integrity/vectors.json；`python scripts/verify_integrity_vectors.py`用hashlib/json独立复核，并由现有check.py调用。3组完整清单覆盖空/default、abc/default、one/非默认7/1参数；其编码逐字节对照独立预期。原正式16夹具、opcode、依赖锁及发布归档不刷新，性能基准不重跑。

当前只完成清单数据、绑定及严格解析；新增接口尚未发布。Commit22受校验应用、结果摘要闭环和文件提交均未实现。
