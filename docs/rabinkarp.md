# Commit 4：Rabin–Karp 弱校验

固定上游 librsync v2.3.4，e364852674780e43d578e4239128ff7014190ed3；实际核对 src/rabinkarp.h、src/rabinkarp.c、tests/rabinkarp_test.c。移植头文件中的状态和标量公式，不移植展开循环、幂表或benchmark。实现保留 Donovan Baarda 2019、向量测试保留 Donovan Baarda 2003 的版权，均为 LGPL-2.1-or-later，全文许可沿用 COPYING.LESSER / COPYING。

内部 RabinKarp 状态为 count:Int32、hash:UInt32、mult:UInt32；初始化0/1/1。MULT=0x08104225，INVM=0x98f009ad，ADJ=0x08104224。字节直接转UInt32，不经过有符号校验值或浮点。hash与mult使用模2^32运算；count只允许0..2147483647，单字节及批量更新都在修改前预检容量。

内部操作包含new、rollin、update、rotate、rollout、digest。rotate保持count/mult；rollout先减少count、更新mult，再减去旧字节及seed调整项，支持EOF逐字节缩短直至0/1/1。空窗口旋转或移出返回InvalidOptions("empty_rabinkarp_window")，容量越界返回IntegerOutOfRange，失败保持状态。批量空更新及digest读取不改状态。调用者负责提供正确的窗口首字节，状态不保存窗口，也不检测错误的outgoing字节。

验证分三类：

1. 独立标量重算从seed遍历真实窗口，不调用任何被测操作；独立计算MULT^count。每次滑动、每次EOF移出都比较hash/count/mult。数据包括全零、全ff、递增、00/7f/80/ff混合、重复及固定LCG（seed=0x12345678；每步seed=seed*1664525+1013904223 mod2^32，取高8位；长度2070）。窗口为0/1、6/7/8、15/16/17、2047/2048/2049；覆盖空段、跨边界切分、单字节更新、交错独立状态、直接EOF、滑动后EOF、缩短后复用和失败恢复。合成计数测试拒绝溢出，不分配巨大输入。
2. 固定上游预期：空=00000001，[0]=08104225，[0,1,2,3]=af981e97，[1,2,3,4]=e2ef15f3，[4,5,6,7]=7cf3fc07，[5,6,7]=f284a77f，0..255=c1972381。预期来自固定上游测试，不由本次实现生成。
3. 离线搬运已校验old.bin与old.sig，对16个原用例按头部块长分块，逐块比较MoonBit弱校验与上游weak_sum；尾块只用真实字节，不补零，空basis不增加记录。脚本只搬运字节，不计算弱校验预期。原16例64文件及manifest完全不改；现有导出校验和Linux重建全文比较继续执行。

新增6项白盒测试，保留原27项，共33项。没有新增公开声明、运行依赖或修改签名解析策略、Limits默认值及锁文件。完整本地检查选择 .toolchain/selected，执行 python scripts/check.py、python scripts/verify_fixtures.py 和 git diff --check。最终三目标结果和同SHA Windows、Ubuntu、Linux reference任务链接由交付报告提供，不能用本提交前快照宣称云端通过。

当前仅完成弱校验；未实现强摘要适配、签名生成、匹配索引、delta、patch或双向互操作，不发布版本、标签或Release，止于Commit 4。

本笔本地完整检查已通过：Native、JS、Wasm-GC各33/33；7个固定上游预期、逐次滑动/EOF独立重算及16例上游签名逐块比较均通过。格式、依赖完整性、公开接口与原有摘要/Native文件探针通过。正式夹具与manifest、工具链与依赖锁、签名解析和Limits未变。云端同SHA结果在最终报告单独提供。
