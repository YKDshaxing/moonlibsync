# MoonLibSync 0.4.0 目录级确定性快照、同步规划与增量分发包（Schema 3）

0.4.0 在纯核心库中引入零 IO、完全兼容 `native` / `js` / `wasm-gc` 的目录快照、差分规划、远端签名索引与自包含增量包模型（[dir_sync.mbt](../dir_sync.mbt)），并在 Native CLI 提供 `dir-snapshot`、`dir-plan`、`dir-signatures`、`dir-pack` 与 `dir-apply` 五条子命令（[cmd/moonlibsync/dir.mbt](../cmd/moonlibsync/dir.mbt)、[cmd/moonlibsync/dir_bundle.mbt](../cmd/moonlibsync/dir_bundle.mbt)）。

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

---

## 四、Native CLI 目录命令与事务安全边界

```bash
# 1. 接收端：为本地基准目录生成快照与标准签名目录
moonlibsync dir-snapshot ./v1 v1.snapshot.json [DIR_LIMITS]
moonlibsync dir-signatures ./v1 v1.snapshot.json ./v1-sigs --block-size auto --streaming [LIMITS] [DIR_LIMITS]

# 2. 只读差异规划（可选，绝不修改任何文件）
moonlibsync dir-plan v1.snapshot.json v2.snapshot.json --json [DIR_LIMITS]

# 3. 发送端：仅凭远端快照与签名目录打包增量包（绝不访问 BASIS_DIR）
moonlibsync dir-pack v1.snapshot.json ./v1-sigs ./v2 ./bundle-v1-to-v2 --streaming [--min-savings N] [LIMITS] [DIR_LIMITS]

# 4. 接收端：校验每个文件 SHA-256 并重建全新输出目录（绝不修改 BASIS_DIR）
moonlibsync dir-apply ./v1 ./bundle-v1-to-v2 ./v2-restored --streaming [LIMITS] [DIR_LIMITS]
```

- **不跟随任何符号链接**：目录根路径及任意层级的子目录、普通文件均逐段使用 `follow_symlink=false` 检查；遇到符号链接、管道、Socket、设备节点立即失败且不创建输出。
- **绝不覆写已有目录、绝不改动 `BASIS_DIR`**：`dir-signatures`、`dir-pack` 与 `dir-apply` 均先在父目录创建独占临时暂存目录 `.moonlibsync-<hex>.tmp`，全部生成与 SHA-256 校验完成后才以 `rename(replace=false)` 原子发布为最终目录；若目标已存在或中途出现篡改、缺失、超限，自动递归清理暂存目录，不遗留半成品目录。
