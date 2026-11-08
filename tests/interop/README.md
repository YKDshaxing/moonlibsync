# Commit 11 确定性互操作计划

配置在 matrix.json，生成代码在 ../../scripts/interop_cases.py，完整输入计划指纹为 plan.sha256。该计划在运行跨实现链路前固定；不按运行结果删减样本或改变种子。没有新增公开 API。固定 librsync v2.3.4 / e364852674780e43d578e4239128ff7014190ed3；MoonBit 与依赖沿用项目锁定版本。

## 精确范围

| 组 | 参数用例数 | 分配 |
| --- | --- | --- |
| 原参考 | 16 | fixture_data.cases 的原始 old/new、block、strong，完整性检查先行 |
| 签名参数边界 | 66 | block=1/2/64/2048，strong=1/16/32；size为0、1、b−1、b、b+1、2b−1、2b去重；new=00 80 ff+old+7f |
| 短尾 | 12 | block=1/2/64/2048，strong32；尾在EOF、移至中间、修改尾字节各一例 |
| 复用 | 3 | 八个互异64字节块：中插3字节、完全相同、两块各改1字节，strong32 |
| 编辑代表 | 13 | 相同/全异，头中尾插删改，块移动，尾块移中间；按下面六参数轮转 |
| 有限穷举 | 338 | 字母表00/80/ff、长度0–2的13串，共169对有序old/new；block1/2、strong32 |
| 固定种子变异 | 48 | 按下面明确LCG与编辑规则，不使用系统随机源 |
| 合计 | 496 | 274对不同的完整(old,new)输入；每例八组合，共3968次矩阵恢复 |

轮转参数表按顺序是(1,32)、(2,16)、(7,1)、(16,32)、(64,16)、(2048,32)，分别为block/strong，使用ordinal%6。固定参考另覆盖7和16的各摘要边界。有限穷举只指上述169对，不能扩大为所有小文件。

随机基种子0x4d4c5311（1296847633）；第i例初态为(seed+i*0x9e3779b9) mod 2^32，LCG每步state=(1664525*state+1013904223) mod 2^32，字节取state>>24。先抽old长度next()%8193，再按i%3选择LCG字节、长度1–16的重复LCG模式或(i*73+19)%256算术序列。之后取1+next()%6次编辑；第j次操作为(i+j)%6：插入、删除、等长替换、区间移动、尾部缩放、单字节稀疏替换。位置由next()%(len+1)、编辑宽度1+next()%32取得；精确调用顺序、空串处理及移动目标见源码。每例最多6次编辑，old范围0–8192、new上限8384。实际本次old224–8099、new221–8107，空与更小输入由其余组覆盖。参数与每步编辑轨迹、初态存入报告。

## 八组合与比较

signature/delta/patch分别取upstream或moonbit，共2×2×2=8种。每例生成两份签名并比较全部字节；每份签名生成两种delta，每个delta交给两个patch，不重复生成相同产物。链A是upstream/moonbit/upstream，链B是moonbit/upstream/moonbit，各计划496次。每次恢复均与独立构造的new.bin逐字节比较，不只比较哈希/长度或两个恢复器。delta大小、字节及指令数量不要求跨实现一致。

严格Python指令检查器在读取每个参数前检查完整区间，payload也不允许截断，检查magic、保留opcode、非零长度、END及尾随。按真实old/new进一步检查每条COPY范围和对应内容。复用插入例要求new515、COPY≥512、delta<515；相同例COPY≥512，局部两块修改例COPY≥384。每种签名来源的MoonBit delta分别检查这些门槛。门槛未降低，不假设永远编码为18字节。

## 运行、失败与报告

Linux/WSL选择固定MoonBit后运行 `bash scripts/interop.sh`。入口核验固定路径rdiff、干净固定源码、BLAKE2参考编译路径、版本和依赖，缺失或身份不符即失败；参考尚未构建时先执行 `bash scripts/build-reference.sh`。只构建一次Native参考适配器，整个矩阵复用。生成模式只读取签名和new；basis只用于签名准备、独立指令验证及patch。核心库不引入文件系统，适配器不构成产品CLI。

六项Python离线工具检查独立于80项MoonBit库测试。各外部命令有超时，非零/崩溃/超时/缺失输出均阻断，命令、退出码、stdout/stderr和超时部分输出写入commands.log。比较失败进入同一异常路径；在临时清理前保存最早失败case的old/new、已有签名、delta、恢复结果、参数/种子/编辑、失败组合、版本/源码状态及命令日志到failures，并附文件哈希。真实算法失败需从归档另行收敛，重新确认同一失败后修复并增加离线最小回归；不能清理掉样本或无证据归因于碰撞。

运行末尾受控指定不存在rdiff路径，要求入口返回1且标记INTEROP_REFERENCE_MISSING；不移动真实工具。另修改恢复副本一个字节，通过同一个compare_bytes路径要求返回1及INTEROP_COMPARE_MISMATCH。之后再执行一次正常MoonBit恢复并比较，单独记录该额外恢复，不计入3968次矩阵恢复。

默认产物在_build/interop/report.json、commands.log、report.sha256及必要的failures。报告分别给出独立输入对、参数用例、各组合预期/成功/失败/未执行、A/B链、签名/恢复比较、COPY与失败门禁、环境版本、实际HEAD、dirty状态及源码内容指纹。未提交本机运行明确标dirty，不能把父HEAD当成本地修改的提交；最终同SHA CI报告须clean。CI始终上传报告和失败归档，不为写自身SHA增补提交。

Linux Native跨实现证据与Windows/Ubuntu的Native/JS/Wasm-GC离线库测试分开；没有在JS/Wasm-GC中直接调用rdiff。有限矩阵不保证所有输入，短摘要或伪造签名不提供basis身份认证。原82次签名消费、29次delta消费、参考重建和两类损坏副本拒绝保持为独立既有检查。止于Commit11，统一资源审计、正式CLI、最终验收和发布仍未完成。
