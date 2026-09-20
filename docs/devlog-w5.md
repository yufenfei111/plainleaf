# W5 开发日志 · 笔记本/标签 + FTS5 搜索 + .plbk 备份（2026-09-16 ~ 09-20）

对应：docs/DEVELOPMENT.md §三 阶段 1 W5（issue #10–#14），M1 冲刺周。

## 交付内容

### 1. 笔记本管理（issue #10）

- `NotebooksDao.create`：新建自定义笔记本（space = life/study/custom，sortIndex 默认 99 置尾）。
- 笔记本页：新增本、条目计数、按空间分组展示。

### 2. 标签管理（issue #11）

- `TagsDao`：创建 / 重命名 / 软删 / `tagEntry` 打标 / `tagsOfEntry` 查询；`entry_tags` 纯关联表（复合主键）。
- **多级标签预留**：`tags` 增加 `parent_id`，`schemaVersion` 1 → 2。
- 迁移按数据红线执行：`onUpgrade` 走 Drift `MigrationStep.addColumn`（禁"卸载重装"绕过），
  `test/migration_test.dart` 覆盖 v1 → v2 加列且旧数据保留。
- 防御分支：裸库/实验版库走 `onCreate` 时 `createAll` 的 `IF NOT EXISTS` 不会补列，
  故显式查 `pragma_table_info('tags')` 判断后 `ALTER TABLE ADD COLUMN`。
- 分层红线：`TagItem` 视图层 + `tagsStreamProvider`，UI 不直接命名 Drift 生成类。

### 3. FTS5 全文搜索页（issue #12）

- `/search`（shell 之外全屏）：`entries_fts MATCH` + 类型过滤芯片，结果点击跳 `/editor?id=N`。
- 时间轴 AppBar 与「我的」页各加入口。

### 4. 备份包 .plbk（issue #13）

- `BackupService.exportBackup`：`VACUUM INTO` 生成一致性快照（不依赖打开连接的文件直拷）
  → zip 打包 `plainleaf.sqlite` + `media/**` + `manifest.json`（app/format/schemaVersion/exportedAt/统计）。
- `verify()`：校验 manifest 存在、`app == plainleaf`、`format == plbk/1`、快照存在。
- `restore()`：校验 → **自动再备份当前数据** → 关库 → 替换库文件 → 还原媒体 → 返回路径。
- `listBackups()`：列私有目录下 `.plbk`，按修改时间倒序（不触库，恢复后仍可安全调用）。
- 设置页补「从备份包恢复」入口：底部列表选包 → 二次确认 → 覆盖 → 提示重启。

### 5. Markdown 导出（issue #14）

- `MarkdownExporter.exportEntry / exportAll`：已发布记录导出为单 .md，草稿与软删不出现。

## 卡点与解法

1. **CJK 分词陷阱**：FTS5 `unicode61` 下中文连续串是单 token，`'学习'` 无法前缀命中，
   必须转 `'学习*'`。`_preprocess` 按空白拆词后逐词加 `*`。
2. **`FileStat.size()` 误用**：`stat.size` 是属性不是方法，`stat.size()` 报
   `invocation_of_non_function_expression`——`dart analyze` 直接抓到。
3. **恢复后状态失效**：`restore()` 会 `db.close()`，页面若继续消费流会崩。
   故恢复成功后弹不可取消对话框，强制要求重启应用；`listBackups` 设计成不触库以避开该窗口。
4. **`onCreate` 不补列**：见上文防御分支，是本机复现的真实坑（实验版库残留）。

## 决策记录

- **恢复入口用「列表选择」而非文件选择器**：M1 形态先闭环「导出 → 恢复」主链路，
  避免为任意路径选择新增 `file_selector` 依赖与权限；W6 打磨导出时一并换成 file_selector。
- **Markdown 导出 M1 只到控制台**：验收标准是"导出不锁定"，落文件对话框与 W6 的导出打磨合并做，
  避免 W5 范围蔓延。
- **标签软删保留 `entry_tags` 关联**：标签误删可回归且不丢关联数据，符合"删除一律软删除"红线。

## 验证结果

| 验证 | 结果 |
|---|---|
| dart analyze（lib + test） | No issues found |
| flutter test | **未能执行**：本机 `flutter_tester` 连接失败（`WebSocketException: Invalid WebSocket upgrade request`），需在开发机终端或 CI 复核 |
| flutter build apk --debug | 待开发机执行（+archive 依赖） |

## 遗留 / 下一步

- W5 真机走查：拍照/选图、搜索中文命中、备份导出与**恢复后重启**全链路（含权限拒绝/低存储）。
- W6 相册阶段：图片压缩/medium/EXIF + Isolate 转码、相册网格、Markdown 落文件、导出打磨。
- 「我的」页仍有 W9 主题、W13 WebDAV、W14 应用锁三个禁用占位项。
