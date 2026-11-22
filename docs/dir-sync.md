# MoonLibSync 0.5.0 目录级确定性快照、单文件归档、同步规划与巡检（Schema 3 + `MLSBDL01`）

0.4.0 / 0.5.0 在纯核心库中提供零 IO、完全兼容 `native` / `js` / `wasm-gc` 的目录快照、差分规划、远端签名索引、自包含增量包、单文件确定性归档容器（`MLSBDL01`，[bundle_archive.mbt](../bundle_archive.mbt)）与目录完整性巡检及 `--exclude` 过滤模型（[dir_sync.mbt](../dir_sync.mbt)），并在 Native CLI 提供 `dir-snapshot`、`dir-plan`、`dir-signatures`、`dir-pack`、`dir-apply` 与 `dir-verify` 六条子命令（[cmd/moonlibsync/dir.mbt](../cmd/moonlibsync/dir.mbt)、[cmd/moonlibsync/dir_bundle.mbt](../cmd/moonlibsync/dir_bundle.mbt)）。

---

## 一、独立资源预算：`DirLimits`

为避免放松单文件 `manifest.mbt` 的 64 KiB / 16 字段 / 深度 2 边界，目录层使用独立预算结构 `DirLimits`：

| 字段 | 默认值 | 合法范围 | 说明 |
| --- | --- | --- | --- |
| `max_entries` | `4096` | `0..65536` | 单份快照最大文件条目数；规划产物至多 `2 * max_entries` 条动作 |
| `max_path_bytes` | `1024` | `1..4096` | 单条 POSIX 相对路径的 UTF-8 最大字节数 |
| `max_depth` | `32` | `1..64` | 路径最大层级段数（根目录直属文件为 `1`） |
| `max_snapshot_bytes` | `1048576` (1 MiB) | `64..16777216` | 单份 Schema 3 快照 JSON 字节上限；`dir-plan` JSON 上限为 `min(64 MiB, 4 * max_snapshot_bytes)` |
| `max_file_bytes` | `67108864` (64 MiB) | `0..2147483647` | 快照内单个普通文件的最大字节数及 CLI 流式 SHA-256 读取上限 |

---

## 二、POSIX 相对路径安全规则与冲突拒绝

每一条 `DirEntry.path` 与 `DirSyncAction.path` 在构造、编码、解析及规划阶段均严格校验：
1. **严格相对 POSIX 形式**：非空、UTF-8 长度 `<= max_path_bytes`、层级段数 `<= max_depth`；
2. **禁止路径穿越与特殊分隔**：
   - 禁止前导 `/`、尾随 `/`、连续 `//`、`\`、`:`（防 Windows 盘符与 NTFS ADS）；
   - 禁止 `.` 或 `..` 段；
   - 禁止 NUL 与全部 ASCII 控制字符（`< 0x20` 或 `0x7f`）；
   - 禁止任意路径段以 `.` 或空格结尾（防跨平台静默剥离尾随字符）；
3. **禁止重复及 ASCII 大小写折叠碰撞**：
   - 单份快照内禁止完全重复路径与仅 ASCII 大小写不同的路径（如 `README.md` 与 `readme.md`），违规统一返回 `InvalidField("path_collision")`；
   - `plan_dir_sync` 在两份快照之间同样执行跨快照 ASCII 大小写碰撞检查，防止在大小写不敏感文件系统上产生静默覆盖风险；
4. **规范确定性排序**：
   - 使用 UTF-8 字节序字典序（`lexical_path_compare`）排序，**绝不采用短词优先（shortlex）排序**；
   - `parse_dir_snapshot` 与 `parse_dir_plan` 均要求 `entries` / `actions` 严格升序（违规报 `InvalidField("path_order")`）。

---

## 三、Schema 3 JSON 线缆格式

沿用严格 UTF-8、无 BOM、禁止 JSON 重复键（`reject_duplicate_keys=true`）、`preserve_number_repr=true` 与精确 `Int64` 十进制字符串策略：

### 1. 快照（`moonlibsync-dir-snapshot`，容器最大深度 `3`）
```json
{
  "schema_version": 3,
  "kind": "moonlibsync-dir-snapshot",
  "entries": [
    {
      "path": "src/main.mbt",
      "byte_length": "1234",
      "sha256": "..."
    }
  ]
}
```

### 2. 同步计划（`moonlibsync-dir-plan`，容器最大深度 `4`）
```json
{
  "schema_version": 3,
  "kind": "moonlibsync-dir-plan",
  "summary": {
    "unchanged": "1",
    "add": "1",
    "update": "1",
    "delete": "1",
    "transfer_upper_bound_bytes": "2048"
  },
  "actions": [
    {
      "path": "a.bin",
      "kind": "unchanged",
      "basis": { "byte_length": "10", "sha256": "..." },
      "target": { "byte_length": "10", "sha256": "..." }
    }
  ]
}
```

### 3. 远端签名索引（`moonlibsync-dir-signatures`）与增量分发包清单（`moonlibsync-dir-bundle`）

- `DirSignatureIndex`（`create/encode/parse_dir_signature_index`，`kind: "moonlibsync-dir-signatures"`）：为每个文件绑定 `path`、`basis` 摘要、`signature_path`（强制位于 `sigs/` 前缀内，拒绝重复与 ASCII 大小写折叠碰撞）及标准 `0x72730147` 签名文件的 SHA-256；JSON 预算上限为 `min(64 MiB, 4 * max_snapshot_bytes)`。
- `DirBundleManifest`（`create/encode/parse_dir_bundle_manifest`，`kind: "moonlibsync-dir-bundle"`）：记录 `unchanged`、`add-full`、`update-delta`（完整绑定 `basis` / `signature` / `delta` / `result` 四项 SHA-256）、`update-full`、`delete` 及汇总计数和 `total_payload_bytes`；所有 `payload_path` 强制位于 `payloads/` 前缀内且拒绝碰撞；JSON 预算上限为 `min(64 MiB, 8 * max_snapshot_bytes)`。

### 4. 目录巡检报告（`moonlibsync-dir-verify`，0.5.0 新增）

- `verify_dir_snapshot(expected, actual, limits) -> DirVerifyReport` 与 `encode/parse_dir_verify_report`（`kind: "moonlibsync-dir-verify"`）：严格校验两份快照（含跨快照 ASCII 大小写折叠碰撞检查），按规范字典序汇总 `matched` / `missing` / `extra` / `modified` 计数及精确 `issues` 列表（`ok` 为布尔值）。

### 5. 单文件确定性目录归档格式（`MLSBDL01` `.mbundle` / `.mbundle.gz`，0.5.0 新增）

- 线缆布局（全大端无符号整数，零时间戳、零 UID/GID、完全字节确定）：
  1. 8 字节魔数：`MLSBDL01`（`4D 4C 53 42 44 4C 30 31`）
  2. 4 字节大端 `u32`：`manifest_len`（Schema 3 `DirBundleManifest` 规范 JSON 字节数）
  3. `manifest_len` 字节：规范 UTF-8 `DirBundleManifest` JSON
  4. 零个或多个载荷块（严格按 `manifest.entries` 声明顺序与长度一一对应）：
     - 2 字节大端 `u16`：`payload_path_len`（UTF-8 字节数）
     - `payload_path_len` 字节：必须逐字节等于清单中下一条 `payload_path`
     - 8 字节大端 `u64`：`payload_len`（必须等于清单中该条载荷声明字节数）
     - `payload_len` 字节：对应 `.delta` 或全量文件原始载荷字节
  5. 严格 EOF：拒绝任意缺失、路径失配、长度失配或尾随多余字节。
- 核心库同时提供一次性 `encode_bundle_archive` / `parse_bundle_archive` 与流式 Sans-IO `BundleArchiveDecoder`（`new` / `has_pending_event` / `step` / `finish`）；CLI 可叠加 `--gzip` 使用独立 `compress/` 子包封装为标准单流 RFC 1952 `.mbundle.gz`。

### 6. 前置 `--exclude` Glob 规则（`match_dir_exclude`，0.5.0 新增）

- 支持 POSIX 风格通配符 `*`（跨段或单段匹配）与 `?`（单字符），对不带 `/` 的模式匹配任意层级路径段（如 `.git`、`node_modules`、`*.tmp`），对含 `/` 的模式匹配完整相对路径（如 `build/*.o`）。CLI 在遍历目录前即剪枝匹配的子目录，避免深入忽略目录或误触其中符号链接。

---

## 四、Native CLI 目录命令与事务安全边界

```bash
# 1. 接收端：为本地基准目录生成快照与标准签名目录（支持 --exclude 与 --progress）
moonlibsync dir-snapshot ./v1 v1.snapshot.json --exclude .git --exclude '*.tmp' [DIR_LIMITS]
moonlibsync dir-signatures ./v1 v1.snapshot.json ./v1-sigs --block-size auto --streaming --progress [LIMITS] [DIR_LIMITS]

# 2. 只读差异规划（可选，绝不修改任何文件）
moonlibsync dir-plan v1.snapshot.json v2.snapshot.json --json [DIR_LIMITS]

# 3. 发送端：仅凭远端快照与签名目录打包（支持目录增量包，或 --archive [--gzip] 单文件 .mbundle/.mbundle.gz）
moonlibsync dir-pack v1.snapshot.json ./v1-sigs ./v2 ./v1-to-v2.mbundle.gz --archive --gzip --exclude .git --exclude '*.tmp' --streaming --progress [--min-savings N] [LIMITS] [DIR_LIMITS]

# 4. 接收端：校验每个文件 SHA-256 并重建全新输出目录（绝不修改 BASIS_DIR）
moonlibsync dir-apply ./v1 ./v1-to-v2.mbundle.gz ./v2-restored --archive --gzip --streaming --progress [LIMITS] [DIR_LIMITS]

# 5. 完整性巡检：验证目标目录与预期快照逐文件一致（一致返回 0，存在缺失/多余/篡改返回 1）
moonlibsync dir-verify ./v2-restored v2.snapshot.json --json --exclude .git --exclude '*.tmp' [DIR_LIMITS]
```

- **不跟随任何符号链接**：目录根路径及任意层级的子目录、普通文件均逐段使用 `follow_symlink=false` 检查；遇到符号链接、管道、Socket、设备节点立即失败且不创建输出。
- **绝不覆写已有目录、绝不改动 `BASIS_DIR`**：`dir-signatures`、`dir-pack` 与 `dir-apply` 均先在父目录创建独占临时暂存目录 `.moonlibsync-<hex>.tmp`，全部生成与 SHA-256 校验完成后才以 `rename(replace=false)` 原子发布为最终目录；若目标已存在或中途出现篡改、缺失、超限，自动递归清理暂存目录，不遗留半成品目录。
