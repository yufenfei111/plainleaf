# W2 开发日志（阶段 1 · MVP 记录内核 · 9/14–9/20）

> 依据 DEVELOPMENT.md §三 W2 行：「Drift 建表（§4.3 修正版）+ Repository + Riverpod + 时间轴静态 UI」。
> 建表与 5 Tab/时间轴静态 UI 已在骨架日（W1 末）提前落地；本周为 W2 本体：**Repository 分层 + Riverpod 正规化 + FTS 事务双写 + 时间轴接领域模型**。

## 2026-09-16（周三）W2 主体交付

### 今日完成

1. **统一异常层**（lib/core/errors/app_exception.dart）：
   - `sealed class PlainLeafException` 基类 + `DatabaseException`（含 cause 原始异常）；
   - 错误三层透传第一层落地：Repository 写操作捕获 DAO 异常并包装（§5.2 规范）。
2. **三组领域实体与 Repository（接口/实现分离）**——
   结构学习自 ModuNote 参考（`interfaces/ local/` 分层、`abstract interface class`、`Local*Repository` 命名，只读学习未拷代码）：
   - timeline：`TimelineEntry`（含 EntryType 枚举、EntryDraft 草稿对象）→ `TimelineRepository` → `LocalTimelineRepository`；
   - study：`StudyTodo` → `TodoRepository` → `LocalTodoRepository`；
   - notebooks：`NotebookItem` → `NotebookRepository` → `LocalNotebookRepository`。
3. **FTS 事务双写落地（§4.3 数据红线）**：
   - `EntriesDao.saveEntry()`：entries 插入 + entries_fts 写入同一事务；
   - `EntriesDao.softDelete()`：deleted 置位 + version 递增 + FTS 行清除同一事务；
   - 种子数据重构为「整只单事务 + 走双写路径」，幂等标记与数据同事务落库（要么全有，要么全无）。
4. **Riverpod 正规化（issue #2）**：
   - 每个 feature 增加 `presentation/providers/`：`xxxRepositoryProvider` + `xxxStreamProvider`；
   - 三个页面从「StreamBuilder + 直连 DAO」迁移到 `ref.watch(streamProvider).when(...)` 三态消费；
   - UI 不再 import 任何 DAO / 生成表类（分层红线达成）。
5. **测试（+3，全量 7 例）** test/repository_test.dart：
   - saveEntry 事务双写（entries+fts 同步、可检索）；
   - softDelete 事务双删（软删保留原行 version+1、时间轴与 FTS 同步消失）；
   - watchTimeline 领域映射（枚举/心情/笔记本名）。

### 决策记录

- **不引入 riverpod_generator/codegen**：本规模下手工 Provider 更轻，且生成流程需走英文路径通道、频繁重生成有摩擦；W9 若 provider 激增再评估。
- **双写原语放 DAO、由 Repository 调用**：种子数据（core 层）与 Repository 复用同一事务原语，避免双写逻辑两处实现；等价满足「Repository 事务内双写、不用 trigger」的文档要求。
- **FTS 查询当前为精确 token 匹配**：unicode61 分词下 CJK 连续串为单 token（如「阶段 0 启动」→ 阶段/0/启动）；W5 搜索页将做查询预处理（前缀 `*` / 多词拆分）。

### 验证结果

| 验证 | 结果 |
|---|---|
| dart analyze | No issues found（0 警告 0 提示，CI 同口径） |
| flutter test | All tests passed!（+7：db_smoke 1 + repository 3 + UI 3） |
| flutter build apk --debug | 成功（Gradle 28.4s，暖缓存），产物已同步 build/app/outputs/flutter-apk/ |

### 遗留 / 下一步

- W3：flutter_quill 编辑器 + 记录核心 CRUD + 500ms 防抖自动保存 + 草稿（issue #4/#5）；
- W3 开工前建议拍板指挥文档决策点 2（仓库迁英文路径），可同时废除 analyze 与 build_runner 两条 workaround 通道。
