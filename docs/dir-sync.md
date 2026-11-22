# MoonLibSync 0.4.0 目录级确定性快照与同步规划（Schema 3）

0.4.0 在纯核心库中引入零 IO、完全兼容 `native` / `js` / `wasm-gc` 的目录快照与差分规划模型（[dir_sync.mbt](../dir_sync.mbt)），并在 Native CLI 提供 `dir-snapshot` 与只读 `dir-plan` 两条子命令（[cmd/moonlibsync/dir.mbt](../cmd/moonlibsync/dir.mbt)）。

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

---

## 四、Native CLI 目录命令与保守边界

```bash
# 生成目录快照（64 KiB 流式计算每个普通文件 SHA-256；原子无覆盖写出）
moonlibsync dir-snapshot ./release-v1 v1.snapshot.json [--max-entries N] [--max-file-bytes N] [...]

# 只读比对两份快照并输出同步计划（支持人类可读文本或 --json）
moonlibsync dir-plan v1.snapshot.json v2.snapshot.json [--json] [--max-snapshot-bytes N] [...]
```

- **不跟随任何符号链接**：目录根路径及任意层级的子目录、普通文件均使用 `follow_symlink=false` 检查；遇到符号链接、管道、Socket、设备节点立即失败且不创建输出。
- **不直接改写用户目录**：`dir-plan` 为纯只读规划命令；`dir-snapshot` 沿用同目录 `.moonlibsync-<hex>.tmp`、`CreateNew`、`fsync` 与 `rename(replace=false)` 原子提交，不提供覆盖参数。
