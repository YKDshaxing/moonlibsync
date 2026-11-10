# MoonLibSync 0.1.0 Native CLI

0.1.0 提供下述单文件命令与保证边界。Commit16只将版本输出改为 `MoonLibSync 0.1.0` 并同步相应检查；下方Commit13/15的development/not released字样属于当时历史输出，不能作为本版当前输出。模块包交付CLI源码；从注册表下载包构建时明确称为“注册表包源码构建”，不代表预编译二进制安装。发布/消费证据见[发布验收](release.md)。

## Commit 18：开发源码检查命令

注册表 0.1.0 仍只有原 `signature`、`delta`、`patch` 文件命令。下列命令只属于当前开发源码，尚未发布为新版本；模块元数据与 `--version` 保留0.1.0。当前帮助明确区分注册表发布与开发检查功能。

```text
moonlibsync inspect-signature SIG [--json]
moonlibsync inspect-delta DELTA [--json]
moonlibsync check-patch OLD DELTA [--json]
```

构建路径与下文一致；Linux ELF 也带 `.exe` 后缀。Windows PowerShell（`$cli` 先设为构建产物路径）：

```powershell
& $cli inspect-signature 'old.sig'
& $cli inspect-signature 'old.sig' --json
& $cli inspect-delta 'update.delta'
& $cli inspect-delta --json 'update.delta'
& $cli check-patch 'old file.bin' --json 'update.delta'
& $cli check-patch 'old file.bin' 'update.delta'
```

Linux Bash 对应为 `"$cli" inspect-signature old.sig --json`、`"$cli" inspect-delta update.delta --json`、`"$cli" check-patch 'old file.bin' update.delta --json`。`--json` 可出现在命令后的路径前、中、后，必须位于 `--` 之前；例如 `inspect-delta --json -- -` 检查字面文件名 `-`，`inspect-signature --json -- --json` 检查字面文件名 `--json`。去掉前一个 `--json` 则以人类文本输出。重复、未知选项、缺少/多余路径、旧命令使用 `--json` 均退出2；旧命令的数值选项仍仅用于 signature。

### 稳定成功 JSON（schema 1）

stdout 为唯一 UTF-8 JSON 对象，以换行结束；没有 BOM、标题、日志、用户路径或原始二进制。顶层 `schema_version` 类型为整数且值为1，`command` 为实际命令字符串。所有计数及字节数（Int64）为十进制字符串，格式化不转浮点、不经过 JS Number。字段和层级如下，不添加“内容正确”标志。

对12字节 `727301470000080000000020` 头部，`inspect-signature --json` 实际输出：

```json
{"schema_version":1,"command":"inspect-signature","summary":{"magic":"0x72730147","profile":"RS_RK_BLAKE2_SIG_MAGIC","block_len":"2048","strong_sum_len":"32","record_count":"0","signature_bytes":"12"}}
```

对8字节 `7273023645000300`（COPY offset=0, length=3），`inspect-delta --json` 实际输出：

```json
{"schema_version":1,"command":"inspect-delta","summary":{"delta_bytes":"8","instruction_count":"1","literal_commands":"0","copy_commands":"1","literal_bytes":"0","copy_bytes":"3","output_bytes":"3"}}
```

以3字节 `abc` 为 OLD，对同一 delta，`check-patch --json` 实际输出：

```json
{"schema_version":1,"command":"check-patch","basis_bytes":"3","summary":{"delta_bytes":"8","instruction_count":"1","literal_commands":"0","copy_commands":"1","literal_bytes":"0","copy_bytes":"3","output_bytes":"3"}}
```

对应人类输出以命令名为首行，逐行打印相同字段；长度字段注明 `bytes`。签名文本说明实际 basis/尾块长度未编码；delta 文本说明尚未校验 COPY 范围；check-patch 文本说明只检查格式与长度范围，没有认证 basis 身份或验证恢复内容。END 不计指令，literal 中零字节照常计入内容。

### 只读、错误与资源边界

私有计划用 `WriteFile(output)` 与 `Inspect(json)` 区分操作。检查分支不调用输出准备、临时文件或提交逻辑，可在普通可读但不可写的目录中执行。SIG/DELTA 沿用同句柄受限读取、EOF探针、大小复核、叶链接拒绝和句柄清理；默认上限分别16777216/83886080字节，没有增加 CLI Limits 选项。完整解析仍受核心记录、块长、指令及预计输出预算限制。

check-patch 先拒绝不支持的 OLD 叶种类，打开只读句柄并查询实际种类和大小；仅对 DELTA 调用 bounded_read，调用公开 check_patch，再在成功输出前复核同一 OLD 句柄大小，所有路径关闭句柄。OLD 默认预算67108864字节，由核心预检检查。OLD 不经内容读取、哈希或恢复缓冲；测试中的注入读取回调只接收 DELTA 路径。大小变化拒绝，同大小修改不能检测；这不是快照、身份认证、恢复内容验证或输出路径可提交证明。

退出0表示该命令定义的检查通过，退出2为用法错误，退出1为文件/预算/核心失败。失败 stdout 为空，stderr 包含命令、相关路径及具体错误类别，例如 InvalidOpcode、TruncatedInput、CopyOutOfBounds、LimitExceeded 或 ReadLimitExceeded。`--json` 不改变失败协议，不输出 JSON 错误对象。只有完整检查和格式化成功后才写 stdout；通道写失败非零退出，已写入部分字节无法普遍撤回。原写文件命令仍成功时 stdout 为空。

私有辅助测试共12项：原6项完整保留，新增6项覆盖参数计划、大于2^53的数值及Int64.MAX的精确格式化、DELTA专用读取、OLD变化复核、句柄关闭及写失败。大数是格式化边界测试，不冒称默认预算可处理该大小文件。CLI 集成以独立 Python JSON 解析器检查唯一对象、重复键、全部字段及类型，涵盖29个原 opcode 向量、全部16种COPY宽度、只读目录、错误后合法调用和真实关闭管道；原集成检查与新增项分别统计于 `_build/cli/report.json`。Windows/NTFS、Linux/ext4及原写入的DrvFS保证边界不变，不由只读检查推导新的提交保证。

# Commit 13：Native 单文件 CLI

基线d7f4f05f3dd3392418eccf089c31748ffe7f21f3。CLI包为cmd/moonlibsync，仅支持Native，通过三项公开字节API计算；核心API、默认Limits、标准格式及JS/Wasm-GC依赖保持不变。probes/signature仍只用于参考互操作，不是产品CLI。

## 构建与真实产物

固定moonc 0.10.20+65efd5b93、moon/moonrun 0.1.20261104及原锁定依赖。安装及选择方法沿用README。Windows选择.toolchain/selected后：

```powershell
moon build cmd/moonlibsync --target native
$cli = "$PWD/_build/native/debug/build/cmd/moonlibsync/moonlibsync.exe"
& $cli --version
& $cli signature "old file.bin" "old.sig" --block-size 2048 --sum-size 32
& $cli delta "old.sig" "new file.bin" "update.delta"
& $cli patch "old file.bin" "update.delta" "restored.bin"
```

Linux选择对应Linux工具链后，正常默认构建路径同样保留.exe后缀：

```bash
moon build cmd/moonlibsync --target native
cli="$PWD/_build/native/debug/build/cmd/moonlibsync/moonlibsync.exe"
"$cli" --version
"$cli" signature 'old file.bin' old.sig --block-size 2048 --sum-size 32
"$cli" delta old.sig 'new file.bin' update.delta
"$cli" patch 'old file.bin' update.delta restored.bin
```

这是Native可执行文件，Linux产物是ELF而不是Windows PE；测试报告记录实际路径和文件魔数，不能自行去掉.exe。上述命令均采用debug默认构建，本笔不提供发行安装器或发布包。本机WSL为保留Windows工具链而使用.toolchain/linux和自定义_build/linux目标，实际运行路径为_build/linux/native/debug/build/cmd/moonlibsync/moonlibsync.exe；CI各平台独立checkout使用默认_build。

## 参数、数据与退出码

```text
moonlibsync signature OLD SIG [--block-size N] [--sum-size N]
moonlibsync delta SIG NEW DELTA
moonlibsync patch OLD DELTA OUT
moonlibsync --help
moonlibsync --version
```

仅signature接受两个选项，可在两个位置参数前、中、后出现，但必须在`--`之前；`--`结束选项识别，此后全部是路径。单独的`-`始终是普通文件名，不表示stdin/stdout。未知/重复选项、缺值、缺路径、多余位置参数和命令均退出2。--help/--version仅作为唯一参数时成功；signature中的--help不是额外缩写。

数字要求完整ASCII十进制数字串，允许正数前导零；拒绝空值、符号、空白、非法后缀、零、负数与溢出。block-size为1..1048576，sum-size为1..32，不截断、钳制或恢复默认。默认2048/32，使用Limits::default，版本输出为0.1.0 development/not released，并由烟雾测试核对moon.mod，不表示正式发布。

| 退出码 | 含义与输出 |
| --- | --- |
| 0 | 文件操作成功时终端无二进制或额外日志；help/version只输出stdout文本 |
| 2 | 命令/参数错误，stderr提供用法问题 |
| 1 | 文件、大小限制、核心计算或提交/清理错误；stderr含操作、相关路径及错误类别/OS信息 |

核心计算仍使用SyncError，CLI将其明确类别写入诊断；文件错误留在私有CLI错误层，不增加核心变体，不依赖未处理异常栈。

## 输入范围与有界读取

| 子命令 | 第一输入 | 第二输入 |
| --- | --- | --- |
| signature | OLD≤67108864字节 | 无 |
| delta | SIG≤16777216字节 | NEW≤67108864字节 |
| patch | OLD≤67108864字节 | DELTA≤83886080字节 |

路径先按平台Path.resolve规范化并解析实际输出父目录；任何已存在的输出条目都拒绝，包括文件、目录、硬链接、符号链接和悬空链接。输入输出的同路径、相对/绝对、点段、Windows大小写/分隔符等价写法由规范化及OS条目查询保护，不只比较原始字符串。父目录必须已存在，CLI不创建目录。Windows缺失输出的叶名还拒绝冒号及尾部点/空格，避免备用数据流等不明确名称。

输入叶节点仅接受普通文件，叶符号链接（包括悬空链接）、目录、管道、设备等拒绝；两个只读输入可恰好是同一文件。父目录中的正常链接可经realpath解析，但输入和父目录应由调用者信任并在操作期间保持稳定。不承诺对恶意替换路径的防护或事务一致快照。

每次读取先查询路径种类，再打开ReadOnly/OpenExisting；随后在同一句柄上检查实际种类和初始大小N。已知N超过对应上限即拒绝，尚未分配N字节读取缓冲。通过后仅分配N，循环read_at，每次最多65536字节，按实际返回数推进；提前EOF、短读耗尽或读取错误失败。末尾只再读取一个字节作EOF探针，并复核句柄大小。逻辑传输至多N+1字节，存储至多N字节加1字节探针；任何增长（即使仍未到默认上限）或大小变化都拒绝，不扩展缓冲去追随增长。句柄由defer在所有正常返回/异常路径关闭。

同大小的并发内容修改未必能被识别，大小检查不是快照。应用必须保持输入稳定；delta只读取SIG和NEW，不推断或查找OLD，烟雾测试会在delta期间移走OLD。本实现补足读入阶段限制，仍是全量Bytes缓冲，不是常量内存流式算法。

## 无覆盖发布、清理及保证边界

顺序为参数/路径检查→有界读取→核心计算→输出同目录独占创建临时文件→完整write→文件sync(only_data=false)→close→rename(replace=false)。临时名由OS随机16字节生成，格式.moonlibsync-<hex>.tmp，CreateNew且POSIX permission0600；Windows权限继承父目录，core忽略POSIX permission。最终路径从不调用默认覆盖write_binary，也不先删除目标。

固定core runtime/fs.c已实际核对：Linux调用renameat2(RENAME_NOREPLACE)；Windows调用SetFileInformationByHandle(FileRenameInfoEx)，replace=false时Flags=0，旧系统回退MoveFileExW也不设置MOVEFILE_REPLACE_EXISTING。同目录避免跨文件系统移动；不支持所需操作的OS/文件系统返回错误，CLI清理自己临时文件，不回退覆盖。

| 性质 | 本笔支持的范围 |
| --- | --- |
| 已有目标保护 | 在已验证后端，即使另一个进程在预检后抢先创建目标，提交也不替换该目标；三组并发竞争均只有一个成功、完整结果 |
| 正常失败 | 计算失败尚未创建临时文件；写入/同步/提交失败关闭并只清理本次成功CreateNew的路径；不会删除最终目标 |
| 临时名碰撞 | CreateNew失败不授予清理所有权，不删除其他操作/用户已有的同名临时文件 |
| 清理失败 | 返回1，保留原始错误和cleanup failed路径/原因，不报告成功；残留路径由调用者按诊断处理 |
| 提交可见性 | 依赖被验证文件系统的单次同目录无覆盖重命名；完整数据在提交前已写完并关闭；竞争测试不等于所有FS/并发读者行为均已证明 |
| 崩溃与持久化 | 文件sync完成后才提交，但未同步父目录，也无启动恢复日志；不承诺断电恢复、崩溃后无临时残留或跨多个输入事务一致性 |

本机Windows Native/NTFS和Linux Native/ext4正向流程已验证。WSL的/mnt/d DrvFS本机实测对该renameat2标志返回EINVAL：CLI退出1、输入不变、无最终输出且临时清理成功。DrvFS不在该Linux正向保证内；这与Windows Native/NTFS是不同后端。网络盘、其他文件系统、所有旧版Windows及恶意父目录替换未全面验证，不能从一次竞态测试泛化。

## 测试与报告

```powershell
./scripts/cli-smoke.ps1
```

```bash
bash scripts/cli-smoke.sh
```

两个包装脚本共用Python驱动，PowerShell显式检查LASTEXITCODE，Shell使用set -euo pipefail并exec。驱动只构建一次真实产品二进制，运行6项Native私有辅助测试；再直接调用该二进制验证正常三命令、空文件、二进制字节、空格路径、完整/短尾、默认/显式/边界参数、--/字面-、错误、稀疏max+1输入、路径别名、链接、真实权限失败及三组竞争。权限失败先由同一执行身份验证真实不可写，结束恢复原权限并实际重新写入探针；不对普通可写目录伪造失败。只调整本次测试目录，不改全局设置。

6项私有测试使用不暴露给用户的函数回调，控制读取后的增长/截短、部分写失败、提交前目标抢占、临时名撞名和清理失败；没有产品故障注入参数或环境变量。所有失败后再完成一次完整signature/delta/patch；检查输入、已有输出及旁观临时文件不变，正常成功清理测试目录。复用门槛new8200、COPY≥8192且delta<new，本机实际delta18/COPY8197。

本机Windows NTFS执行79项集成场景和6项辅助测试；账号缺少创建符号链接权限，4项链接检查明确未执行、不计通过，未修改权限开关。Linux ext4执行81项和6项，含全部链接检查。支持符号链接的Windows runner还会执行这4项，总83；实际同SHA数量及可选能力以CI报告为准，不预先把未执行写成通过。

报告默认_build/cli/report.json、commands.log、native-helper-tests.log，记录实际二进制路径/魔数、文件系统、工具链、SHA/dirty、每场景退出码、未执行项、权限证明及清理结果；自定义MOONLIBSYNC_BUILD_DIR时在该目录/cli。MOONLIBSYNC_CLI_TMP_PARENT只控制测试驱动的临时根，不是产品选项。WSL共享Windows工作区时已实测：

```bash
MOON_HOME="$PWD/.toolchain/linux" \
PATH="$PWD/.toolchain/linux/bin:/usr/bin:/bin" \
MOONLIBSYNC_BUILD_DIR=_build/linux MOONLIBSYNC_CLI_TMP_PARENT=/tmp \
bash scripts/cli-smoke.sh
```

这让Linux正向文件操作位于ext4而报告仍在工作区；不会把DrvFS提交降级。原99库测试按根包选择在Native/JS/Wasm-GC各执行一次，CLI6仅Native另计；原6 Python工具、274对/496参数/3968恢复、82/29消费和所有参考/失败门禁均保留。报告分别作为现有任务产物，不新建三目标重复矩阵。止于Commit13，Commit14示例/整体验收、基准、源码包及发布不在本笔完成范围。

## Commit 14：Linux Native 文件交换

选择固定Linux工具链，先运行 `bash scripts/rebuild-reference.sh`，然后实际执行：

```bash
python3 scripts/file_exchange.py
```

WSL工程在/mnt/d时设置 `MOONLIBSYNC_CLI_TMP_PARENT=/tmp`，使用ext4临时目录；不在DrvFS放正向输出。CI checkout所在Linux文件系统支持无覆盖提交。脚本核对固定moonc、rdiff2.3.4及上游完整SHA，构建正式cmd/moonlibsync，核对ELF魔数，在独立临时目录创建512字节old与515字节new后实际运行：

```text
rdiff -H blake2 -R rabinkarp -b 64 -S 32 signature old.bin upstream.sig
<product-cli> delta upstream.sig new.bin moon.delta
rdiff patch old.bin moon.delta upstream-restored.bin
<product-cli> signature old.bin moon.sig --block-size 64 --sum-size 32
rdiff delta moon.sig new.bin upstream.delta
<product-cli> patch old.bin upstream.delta moon-restored.bin
```

两份restored均与独立new逐字节相等；签名完整字节一致，实际moon.delta严格检查内容与COPY>=512。真实命令/绝对CLI路径、退出码、版本、文件系统和源码SHA/dirty保存于 `_build/exchange/commands.log` 与 `report.json`，实际交换文件保存于其独占files-*目录。临时目录只清理本次拥有的内容，不覆盖已有输出。这是两条Linux Native演示，单列于274对/496参数/3968恢复之外；不代表JS/Wasm-GC直接调用rdiff或发布包消费者验证。

## Commit 15：release基准与CLI冻结

用户默认debug构建及其真实路径保持前文不变。基准显式运行 `moon --target-dir RUN/build build cmd/moonlibsync --target native --release`，真实ELF路径为 `RUN/build/native/release/build/cmd/moonlibsync/moonlibsync.exe`，Linux仍保留.exe；脚本检查当前--help、实际路径、魔数和哈希，不回退到debug。Linux正向基准把两端可执行文件、输入和新输出均放在ext4临时目录，原始命令和构建身份见[基准](benchmarks.md)。

计时包含本CLI的完整受限读取、计算、文件sync和无覆盖提交，与rdiff的文件保证不同。本笔没有关闭安全路径、改变预算或增加CLI参数来获取更好数字。冻结本页语法、退出码、输入稳定责任、链接及现存输出保护、失败清理和NTFS/ext4/DrvFS边界；最终源码包、安装器、Mooncakes发布及注册表消费未执行。

## Commit 22：清单文件命令（仅开发源码）

```text
moonlibsync basis-info OLD SIG INFO
moonlibsync make-manifest INFO SIG NEW DELTA MANIFEST
moonlibsync patch-verified OLD DELTA MANIFEST OUT
```

完整两端可运行流程、长度/SHA拒绝字段与读取上限见[清单说明](manifests.md#commit-22受校验应用与文件流程)。三项均仅一个最终输出，成功stdout/stderr为空；退出码沿用0/1/2。拒绝--json、重复/多余/未知参数；`--`和普通文件名`-`保持现有含义。错误诊断含操作及输入/输出路径。make-manifest不需要或查找OLD；patch-verified没有SIG输入，不声称实际验证SIG文件。必须可信地获取MANIFEST；不提供发布者认证。

所有读取沿用bounded_read。验证前可只读检查输出路径，结果长度/摘要未通过绝不创建临时或最终文件。通过后复用原同步和无覆盖发布器，既有输入/输出别名、目录、符号链接、竞争、仅清理自有临时文件和NTFS/ext4/DrvFS边界均不变。新增3项Native辅助测试覆盖同步失败清理和后续成功、验证失败不调用发布器、参数路径解析；总15项（前述12项保留）。CLI新增文件流程独立统计为manifest_cases_passed，原original/inspection计数不混入新功能。
