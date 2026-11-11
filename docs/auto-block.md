# 显式自动块长：开发源码 policy v1

Commit 25 增加 `recommend_block_len(basis_len: Int64, strong_sum_len: Int64, limits: Limits) -> Int64 raise SyncError` 和 `signature --block-size auto`。仅当前阶段 B Git 开发源码具备；已发布 0.2.0 原包不包含它。元数据仍为 0.2.0，不表示新能力已经发布。默认仍为 2048/32，零不是 auto，数字选项沿用原行为。

## 完整整数规则

按顺序校验全部 Limits、basis_len 非负、strong_sum_len 在 1..32、basis_len <= max_old_bytes、max_signature_bytes >= 12。负长度返回 `InvalidOptions("basis_len")`，非法摘要长度返回 `InvalidOptions("strong_sum_len")`，预算不足返回 `LimitExceeded`；非法 Limits 先按原配置规则拒绝。

空输入返回 `min(2048,max_block_bytes)`，零条记录、12 字节签名；零记录预算合法，但不能省略头部预算或其他配置校验。

非空输入计算：

```text
width = 4 + strong_sum_len
allowed = min(max_signature_records, (max_signature_bytes - 12) / width)
allowed == 0 => LimitExceeded
required = ceil(basis_len / allowed)
required > max_block_bytes => LimitExceeded
target = ceil(basis_len / 512)
preferred = max(64, target, required)
rounded = 不小于 preferred 的最小 2 次幂
block_len = min(rounded, max_block_bytes)
```

最后用原 `signature_plan` 复核记录数、签名字节和表示范围。ceil 使用商加非零余数，不先加 divisor-1。Limits 已把长度与容量限定在 Int32 可表示范围；舍入用 Int64，最多到 2^31，再受块长上限约束。头部先检查再减；width 为 5..36；所有除数先检查正数。无浮点、内容试探或摘要运算。

64 是偏好，不是强制下限。上限为17、basis为34、记录上限2时返回17；basis为35则无解。已验证 required 可行后，最终结果仍 >= required，因此限制导致的非2次幂结果合法。目标约512条并非强制记录数，也不保证最优 delta、最低内存或最快扫描。max_match_work 等不适用预算允许合法零值，但仍校验其配置合法性。

推荐器只接收长度，不读取文件、不哈希、不建索引、不修改 Limits。返回值用于构造原 SignatureOptions，再调用原 signature。可运行公开 API 示例：

```bash
moon run examples/auto --target native
moon run examples/auto --target js
moon run examples/auto --target wasm-gc
```

[示例源码](../examples/auto/main.mbt) 使用32769字节、摘要16，独立断言块长128、257条记录、5152字节签名，并验证恢复与原默认2048行为。

## CLI 和标准格式

```text
moonlibsync signature OLD auto.sig --block-size auto --sum-size 16
moonlibsync inspect-signature auto.sig --json
```

只接受小写 `auto`，仅作用于 block-size；sum-size auto、空值、负数、零、大小写变体和重复数字/auto 均拒绝。原选项位置、`--`、字面 `-` 语义保留。私有 Explicit/Auto 类型表达选择，无零哨兵。完成原有界 OLD 读取和输入变化检查后，按本次实际 Bytes 长度推荐；原输出保护、同步、无覆盖提交及清理规则不变。

SIG 头只保存实际数字块长和摘要长度，仍是 RK+BLAKE2 标准签名。检查 JSON schema、清单 schema 和格式均未增加 auto 字段；接收方不需要知道策略。

## 有限数据量对照：不是计时基准

命令 `python3 scripts/check_auto_block.py`；Linux Native release、WSL2/ext4，固定SDK及 librsync v2.3.4 / e364852674780e43d578e4239128ff7014190ed3。生成规则、种子和修改位置沿用未改动的 `tests/benchmarks/config.json` 及 `benchmark.inputs`，新计划为 `tests/auto-block/plan.json`。全异样本的字节集合互斥，实际两端 COPY 为零。

首次执行的 source SHA 为30a36f5c105f84b41d79dc2f1245f1cc0965a36c、dirty=true，不能称为最终干净同SHA运行；最终提交的干净CI另保留自动块长 artifact。原始记录 `_build/auto-block/report.json` 含每个输入长度、SHA-256、工具路径/哈希、参数、两端 delta/COPY 及恢复状态，commands.log 保留实际命令。下表为 MoonLibSync delta；所有行均成功恢复。固定/自动两端均为强摘要32。

| old规模 | 场景 | 块长 固定/自动 | 记录 固定/自动 | SIG字节 固定/自动 | delta字节 固定/自动 | COPY字节 固定/自动 |
|---|---|---|---|---|---|---|
|65536|相同|2048/128|32/512|1164/18444|11/11|65536/65536|
|65536|小替换|2048/128|32/512|1164/18444|2065/144|63488/65408|
|65536|前插|2048/128|32/512|1164/18444|44/44|65536/65536|
|65536|全异|2048/128|32/512|1164/18444|65546/65546|0/0|
|65536|重复|2048/128|32/512|1164/18444|166/1574|65536/65536|
|1048576|相同|2048/2048|512/512|18444/18444|11/11|1048576/1048576|
|1048576|小替换|2048/2048|512/512|18444/18444|2071/2071|1046528/1046528|
|1048576|前插|2048/2048|512/512|18444/18444|44/44|1048576/1048576|
|1048576|全异|2048/2048|512/512|18444/18444|1048586/1048586|0/0|
|1048576|重复|2048/2048|512/512|18444/18444|2086/2086|1048576/1048576|

new 长度分别为 old（相同/小替换/全异）、old+32（前插/重复）。64KiB小替换的细粒度提高COPY并缩小delta，但签名从1164增到18444，单次交换总量更大；重复内容虽COPY相同，稳定首候选选择产生更多指令，delta反而增大。全异delta比NEW大，额外签名也没有省掉。1MiB推荐恰与默认一致。更小块增加记录、索引及潜在扫描/候选工作；这里没有测量耗时或内存，不能据数据量推导速度。没有重跑或覆盖两轮历史性能基准。

独立新计划含15个阈值样本和10对比较，共35次完整签名字节核对（相同实际参数显式传入固定rdiff，同时与数字CLI签名核对）、70次跨实现恢复。实际delta由原严格检查器解析并重放；生成时移除OLD，验证仅SIG+NEW。新旧验证分开计数，旧矩阵/夹具不变。

## 边界与交付范围

新增三目标13项库测试，覆盖阈值前/等/后、1/16/32摘要、字节/记录预算、非2次幂上限、无解、Int64极值、全部非法Limits、无关合法零预算和失败后复用；另有2项Native辅助测试和每平台29项CLI集成用例。原每目标166项库测试、15辅助及314/315 CLI范围保留。最终同SHA实数由交付记录和CI产物提供。

候选检查默认写 `_build/stage-b-candidate/`，拒绝写历史0.1.0/0.2.0发布目录；结果称未发布开发快照，不是注册表0.2.0验收。公开接口只增加推荐函数，默认预算、依赖锁、SIG/DELTA/清单/检查协议均不变。止于Commit25，不包含Full/Delta选择、流式处理、新profile或发布操作。
