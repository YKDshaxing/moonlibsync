# 字节库使用与设计

## Commit 19：不透明签名准备

开发源码新增 `prepare_signature(signature_bytes: Bytes, limits: Limits) -> PreparedSignature raise SyncError`；这是准备操作，不是增量生成或签名真实性认证。外部包能接收、持有和传递对象，但不能构造对象、访问记录/排序/摘要数组，也没有 setter。生成的接口为 `pub struct PreparedSignature { // private fields }`，仅新增该类型与一个函数；原六项操作与检查CLI不变。

准备顺序固定：验证全部 Limits → 完整 parse_signature → 创建本次 MatchWork → 现有 build_signature_index → 返回完整对象。签名字节、profile、字段、对齐、表示范围、块长、记录数及名义偏移检查沿用原优先级。实际适用 max_signature_bytes、max_signature_records、max_block_bytes、max_match_work；其他合法但不适用限制为零不会误限准备。空签名允许零工作预算；非空索引先预收3n，再逐比较/写入计量。解析记录可能在索引预算不足前已分配，不是“零预算零分配”。

对象只保留真实输入字节数和 SignatureIndex。后者拥有完整 Signature（magic、块长、摘要长、全部记录及各自拥有的摘要Bytes）与最终序号数组；不保留原始签名缓冲、排序临时数组、第二份强摘要索引、basis、文件句柄、MatchWork、扫描窗口或全局缓存。字段不可由外部访问，现有内部查询仅只读访问；GC所有权保持跨函数生命周期，不用悬空视图或裸指针。多个对象各自保留这些存储，并非免费共享缓存；只读封装不构成线程安全承诺。

原始输入字节数与索引中块长/记录数等信息足以在 Commit 20 重新检查每次调用的适用 Limits，防止宽松准备绕过严格调用。届时每次扫描需新建独立状态和工作预算，不重复收费未执行的索引建设；**本笔尚未提供 PreparedSignature::delta**，没有复用生成结果或加速结论。原一次性 delta 仍走原共享索引/扫描/指令工作预算路径，未改成调用 prepare。

prepared_test.mbt 的5项公开测试与 prepared_wbtest.mbt 的7项白盒测试，覆盖封装后的持有、完整错误顺序、独立推导的预算边界、稳定序号、6442450941 的名义偏移、跨作用域查询、多对象及失败后独立性、16个上游夹具完整块与短尾。没有将查询白盒帮助函数开放成公共接口。该能力只在开发源码，注册表0.1.0不含它，不改发布版本元数据或旧基准。下文 Commit 18/17 的未完成项保留各阶段历史归属。

## Commit 18：检查 CLI

当前开发源码将下列三项检查 API 接到正式 Native CLI，命令为 inspect-signature、inspect-delta、check-patch，支持人类文本及 schema_version=1 JSON；详见[CLI 契约](cli.md#commit-18开发源码检查命令)。核心公开接口与 Commit 17 完全一致。检查计划不携带输出路径，不走写文件准备/提交；check-patch 持有 OLD 只读句柄、仅查询种类/大小，读取 DELTA 后调用公开预检并复核 OLD 大小。所有检查成功后才格式化/写出，stdout 写失败传播为非零。Int64 直接格式化为十进制字符串，不经过浮点。

注册表0.1.0只有原三个文件命令；新增 CLI 尚未发布，元数据版本不改。本笔到 Commit 18 为止，不实现 PreparedSignature、清单或后续阶段。下文 Commit 17 中“JSON CLI 留待 Commit 18”为该阶段的历史边界。

## Commit 17：开发源码只读检查

注册表 0.1.0 的公开操作仍为 `signature`、`delta`、`patch`。下列三项仅在当前开发源码可用，属于拟定 0.2.0 阶段；不修改发布版本元数据，不代表新版本已经发布。

| 入口 | 输入 | 返回（字段均不可变） |
| --- | --- | --- |
| `inspect_signature` | `Bytes, Limits` | `SignatureSummary`：`magic: UInt32`；`block_len, strong_sum_len, record_count, signature_bytes: Int64` |
| `inspect_delta` | `Bytes, Limits` | `DeltaSummary`：`delta_bytes, instruction_count, literal_commands, copy_commands, literal_bytes, copy_bytes, output_bytes: Int64` |
| `check_patch` | `basis_len: Int64, Bytes, Limits` | `PatchCheck`：`basis_bytes: Int64, summary: DeltaSummary` |

三项均 `raise SyncError`，每次先验证所有 Limits 字段。`inspect_signature` 完整复用签名解析器：签名字节预算、完整头部/profile、参数、记录对齐、数值与记录预算，错误顺序不变。只支持 RK+BLAKE2 `0x72730147`；12 字节头部的记录数为零。签名没有实际 basis 长度、真实尾块长度或文件身份信息；检查不计算摘要。

`inspect_delta` 完整解析后统计：全部 literal 编码、16 种 COPY 宽度、合法非最短编码、输入/指令/输出预算以及严格 END/尾随策略均沿用原解析器。END 不计指令；literal 内的零字节按 payload 消费。指令数为 literal 与 COPY 数之和，输出字节为两者字节之和；空 delta 为5字节、其余统计为零。高位 UInt64 offset 只涉及格式，在没有 basis 的检查中不返回范围错误。

`check_patch` 固定顺序为：Limits 验证 → 负长度 `InvalidOptions("basis_len")` → basis 预算 `LimitExceeded` → 完整 delta 解析 → 共用 `patch_size` 的所有 COPY 范围及输出长度预检 → 摘要。范围在 UInt64 域检查 `offset <= basis_len && length <= basis_len - offset`，不先做加法或窄化。完整解析错误优先于合法前缀中的坏 COPY；零长度/巨大长度遵循原解析错误顺序。通过仅证明长度范围，不能证明恢复内容、旧文件身份或文件系统能提交。

新入口不调用 patch，不创建虚拟 basis，不分配恢复输出。解析仍分配有界记录、摘要副本或指令元数据；这不等于零分配或常量内存。返回值不保留输入视图或指令数组。公开调用及独立字段预期见 `inspect_test.mbt`，随完整根包测试在 Native/JS/Wasm-GC 编译运行；`inspect_wbtest.mbt` 覆盖29个原 opcode 向量、16个参考夹具与共用预检帮助函数。JSON CLI 留待 Commit 18。

## Commit 15 功能冻结历史

本记录冻结 Commit 14 已实现的执行行为，Commit 15 只增加测量工具和文档，不修改核心执行代码。0.1.0提供本页三项字节API和Native单文件CLI；实际发布/注册表消费证据按[发布验收](release.md)核对，功能冻结本身不是上传证明。

## 从源码调用

先按根 README 克隆源码、选择固定工具链并执行 `moon update`。随包提供的可运行源码示例为 `examples/basic`，其 `moon.pkg` 仅导入 `"YKDshaxing/moonlibsync" @lib`，注册表消费者声明目标版本后，仍须独立核对下载的实际版本与内容。在源码工作区新增消费者包时沿用这个导入；模块名来自根 moon.mod。工具链固定不等于已验证所有更高版本。

以下完整 `main.mbt` 与仓库内已实际编译运行的 [basic示例](../examples/basic/main.mbt) 一致，使用该包的 `moon.pkg`（仅导入公开根库）。从根目录运行 `moon run examples/basic --target native`，也分别运行js与wasm-gc；没有另提供未经执行的新示例。

```moonbit
// SPDX-License-Identifier: LGPL-2.1-or-later

///|
// The sender has no basis argument or filesystem access.
fn sender(
  remote_signature : Bytes,
  new_bytes : Bytes,
) -> Bytes raise @lib.SyncError {
  @lib.delta(remote_signature, new_bytes, @lib.Limits::default())
}

///|
fn main {
  let old = Bytes::makei(512, i => (0x10 + i / 64).to_byte())
  let new_bytes = old[0:256].to_owned() + b"\x00\x80\xff" + old[256:].to_owned()
  let limits = @lib.Limits::default()
  let remote_signature = @lib.signature(
    old,
    { block_len: 64, strong_sum_len: 32, },
    limits,
  ) catch {
    _ => abort("BASIC_SIGNATURE_FAILED")
  }
  let encoded = sender(remote_signature, new_bytes) catch {
    _ => abort("BASIC_GENERATION_FAILED")
  }
  let restored = @lib.patch(old, encoded, limits) catch {
    _ => abort("BASIC_PATCH_FAILED")
  }
  let expected = new_bytes
  guard restored == expected else {
    println("BASIC_RESTORE_MISMATCH")
    abort("BASIC_RESTORE_MISMATCH")
  }
  guard encoded.length() < new_bytes.length() else { abort("BASIC_DELTA_SIZE") }
  let alphabet = "0123456789abcdef"
  let mut hex = ""
  for byte in encoded {
    let value = byte.to_int()
    let high = value >> 4
    let low = value & 15
    hex = hex +
      alphabet[high:high + 1].to_owned() +
      alphabet[low:low + 1].to_owned()
  }
  println(
    "old_bytes=\{old.length()} new_bytes=\{new_bytes.length()} signature_bytes=\{remote_signature.length()} delta_bytes=\{encoded.length()}",
  )
  println("delta_hex=\{hex}")
  println("restored_equal=true")
}
```

三个函数均返回新的 `Bytes`，并 `raise SyncError`；调用方必须传播或处理错误。输入为已存在的完整字节串，不是文件名或流。发送端函数只接收 `remote_signature` 和 `new_bytes`，不访问 old。接收端保留 old，并最终验证 restored 与预期内容或外部可信整文件摘要相等。

| 公开入口 | 输入与返回 | 主要失败条件 |
| --- | --- | --- |
| signature | basis、SignatureOptions、Limits → 标准签名Bytes | 非法选项、整数/集合表示、basis/签名/记录/块预算 |
| delta | 标准签名、new、Limits → 标准delta Bytes | 签名格式/profile、new及预计输出、指令/delta/共享匹配工作预算 |
| patch | basis、delta、Limits → 恢复Bytes | 完整解析、END、COPY范围、basis及输出预算 |

`SignatureOptions` 两个 Int64 字段：`block_len` 默认2048，`strong_sum_len` 默认32（支持1–32）。块长受 `max_block_bytes` 约束，0从不表示自动选择。强摘要先计算 **BLAKE2b 输出长度32**，再截取前s字节；既不是 BLAKE2b-512 截断，也不是将摘要参数改为s。短摘要有更高碰撞风险，默认32也不认证 basis 身份。

`SyncError` 固定为 `InvalidOptions(String)`、`UnsupportedSignatureProfile`、`TruncatedInput`、`InvalidSignature`、`InvalidDelta`、`InvalidOpcode`、`IntegerOutOfRange`、`CopyOutOfBounds`、`TrailingData`、`LimitExceeded`。配置先验证；各阶段格式、资源及范围检查顺序以 [资源契约](resources.md) 为准，不承诺将不同坏输入统一映射到一个错误。失败不返回半成品，也不会污染下次独立调用。

## 格式、匹配与恢复

签名头为大端 magic `0x72730147`、块长、摘要长度，随后是 weak u32 与s字节强摘要记录；没有文件总长、尾块实际长度、文件身份或整文件认证。只支持 RK+BLAKE2 profile；其他已知组合明确返回 UnsupportedSignatureProfile。尾块签名按真实字节计算，不补零。

索引只排序记录号，按弱校验、原始块序号稳定排序。扫描使用Rabin–Karp，弱候选存在时才计算当前窗口一次强摘要，逐候选确认；选择第一个匹配的块序号。重复内容因此可能反复选择 basis 的低偏移块，产生多个不能合并的COPY，不承诺最少指令、最小delta或最优速度。只有 basis 偏移连续的相邻COPY才合并。

窗口开始取 min(block_len, remaining)。未命中且还有新字节时rotate；到EOF后逐字节rollout收缩窗口，可匹配签名中未知长度的尾块。签名没有尾长，候选匹配确认的只是**当前真实窗口长度的摘要**，不能凭记录数推断实际 basis 长度。delta 生成不持有 basis；最终 patch 仍须按真实 basis 长度检查所有COPY。

delta magic `0x72730236`；解析覆盖标准 literal、COPY、END及1/2/4/8字节参数宽度。编码选最短适用宽度，不要求与rdiff输出逐字节相同。必须完整END，END后任何尾随数据拒绝；零长度数据指令、非法opcode、截断、无符号溢出及超限均明确失败。

COPY始终从原始 basis 读取，不从正在增长的恢复输出读取。patch先完整解析，再验证每个区间和最终大小，才分配恢复缓冲。标准格式不认证“这是正确的旧文件”；错误但同样长的 basis 可能恢复出错误内容，应用必须维护身份和外部完整性/真实性验证。

## 资源、文件与目标

九项 Limits 的默认值、单位、收费时机及适用操作列于 [资源契约](resources.md)。一次delta共享一个工作账本：索引、候选、摘要输入字节、扫描及指令容量增长均在相关动作前收费；超限失败，不退回不收费的全literal。逻辑工作单位不是CPU周期、总时间或总堆上限。

全量缓冲API在入口前已持有输入；签名记录/摘要副本、排序数组、命令容量及literal视图、输出缓冲和转换副本可能同时存活，视图还可能保活整个输入。没有测量堆峰值或制造OOM，不承诺OOM可恢复，也不将单个64MiB输入上限等同于进程64MiB。

核心已验证 Native／JS／Wasm-GC。文件功能隔离在正式 Native CLI，语法、实际 `.exe` 产物、严格参数与退出码见 [CLI说明](cli.md)。文件成功流程包含有界读、临时CreateNew、完整写、文件sync、关闭、无覆盖提交；与rdiff进程的文件保证不同。Windows/NTFS、Linux/ext4是已验证正向边界；DrvFS不支持无覆盖提交时明确失败并清理，不回退覆盖。文件sync不保证父目录/断电持久化，父目录与输入需稳定可信。

## 与已有项目的交集

2026-11-09 重新读取 [moon-sync-delta README](https://github.com/niuniu513-ask/moon-sync-delta/blob/main/README.md)（Git blob `dadc91b71b36bad983d97c34766ce2f7a6a21d2b`）。其文档描述0.2远端签名生成标准VCDIFF、复用moon_vcdiff解码和SHA-256元数据；这与本项目的远端签名/滚动匹配应用存在交集。这里只确认文档内容，没有运行其实现、验证其发布或作者认可。

本项目差异是直接读写指定librsync签名/delta格式，并以固定librsync2.3.4真实rdiff做双向交换；不为标准字节添加私有身份封装。不能据此声称远端签名差分在MoonBit中为空白或性能普遍更优。规划中的 `yangxixi00/moon_vcdiff` 以及上述README链接的 `yangxixi00/moon-vcdiff` 本次读取均返回404，无法独立确认其当前仓库能力；不把旧调研当作本次验证。项目间格式、能力和许可应以各自实际来源为准。

有限成本与数据量实测见 [基准](benchmarks.md)；本笔冻结范围及 Commit 16 交付条件见 [兼容性记录](compatibility.md#commit-15首版功能冻结)。
