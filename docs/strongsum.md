# Commit 5：BLAKE2b-256 强摘要适配

基线5bfb28330ab3ae2c622aed53acb417a8bcc327c8。moonc 0.10.20+65efd5b93、moon/moonrun 0.1.20261104、mooncrypt 0.4.5及全部锁文件不变；根包仅增加已有hash/blake2的import。strongsum.mbt为本项目原创内部胶合层，不是自行移植BLAKE2b。

内部strong_sum(BytesView, Int32)先检查1<=strong_sum_len<=32，不合法返回InvalidOptions("strong_sum_len")；负值、0、33、Int32最小/最大值均被拒绝，依赖调用与切片都在检查之后。每次独立调用 @blake2.hash(input, kind=Blake2b, len=32)，不提供key/salt/person，然后复制full[0:strong_sum_len]。不缓存hasher或返回依赖类型，不新增公开API，不声明已实现完整匹配预算。

固定上游librsync v2.3.4 / e364852674780e43d578e4239128ff7014190ed3 的 src/checksum.c 以RS_MAX_STRONG_SUM_LENGTH初始化及完成BLAKE2b，该值在src/librsync.h为32。本适配不使用BLAKE2s、64字节BLAKE2b截断，也不把strong_sum_len作为算法输出参数。算法输出长度改变参数块，和取32字节结果前缀不同。

## 独立预期

完整输入hex、32字节摘要、生成规则、Python完整版本与来源保存于 tests/strongsum-vectors.json。来源为CPython hashlib.blake2b(data, digest_size=32)，首次生成使用Python 3.14.6（Anaconda，MSC v.1942 x64），不是MoonBit依赖。向量包括空、单字节00、ASCII abc、007f80ff，以及(i*73+19)%256算术序列的127/128/129/255/256/257字节，总计10组。128字节为BLAKE2b压缩块边界，不等同于librsync默认2048字节签名块长。

显式更新命令为 python scripts/strong_vectors.py --write，随后用固定moon fmt格式化生成的strongsum_vectors_wbtest.mbt。默认 python scripts/strong_vectors.py 和已有scripts/reference_vectors.py只读校验保存的完整预期、输入规则和生成代码一致性，不刷新文件；代码比较只忽略字符串之外的排版空白。普通MoonBit测试直接使用保存的字节常量，离线运行，不调用Python。

新增5项白盒测试，保留原33项，总计38项：

- 所有10组完整摘要与独立预期比较，再对1..32全部长度逐字节比较独立预期前缀和准确长度。
- 非法长度后再次合法调用，确认没有panic或残留状态。
- 所有向量用带前后哨兵的非零偏移BytesView计算，包括空视图；重复、交错调用后输入及先前返回值不变。
- 对空、短和各块边界输入，BLAKE2b-512截断、BLAKE2s-256以及直接len=1/16均与正确独立预期区分；反例不替代正确性向量。
- 对原16例basis实际块调用本适配，与上游签名strong_sum逐字节比较，覆盖1/16/32及default-edit长块，尾块不补零，空basis不增加记录。

本地 python scripts/check.py 已通过：Native、JS、Wasm-GC各38/38，格式、依赖完整性、公开接口与原摘要/Native文件探针通过。正式16例64文件12507字节及manifest、Rabin–Karp、解析策略和Limits均未改变。同SHA Windows、Ubuntu和Linux参考任务结果在最终报告单独提供，首次提交前快照不预先宣称云端成功。

Commit 1依赖探针、Commit 3参考构建、Commit 4弱校验仍各归原阶段。本笔只完成内部强摘要适配，未实现签名生成、匹配索引、delta、patch或双向互操作，未发布包、标签或Release，止于Commit 5。
