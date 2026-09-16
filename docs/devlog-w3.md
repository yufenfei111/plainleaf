# W3 开发日志（阶段 1 · MVP 记录内核 · 9/21–9/27）

> 依据 DEVELOPMENT.md §三 W3 行：「quill 编辑器 + CRUD + 500ms 自动保存 + 草稿」+ 回收站（issue #4/#5/#6）。
> 提前于 9/16 完成 W3 主体（进度领先排期约一周）。

## 2026-09-16（周三）W3 主体交付

### 今日完成

1. **flutter_quill 接入（issue #4）**：
   - 依赖：flutter_quill ^11.6.0（pub 建议升级解决 intl 冲突：SDK flutter_localizations 锁 intl 0.20.3，quill 10.x 要求 0.19；quill 11.6 与 0.20.3 兼容）；
   - 编辑器页 `features/editor/presentation/editor_page.dart`：QuillEditor.basic + QuillSimpleToolbar（按 11.6 实际参数名裁剪按钮组）+ 标题输入区；
   - MaterialApp 注册 FlutterQuillLocalizations.delegate（工具栏 tooltip 依赖，缺它建工具栏即抛 MissingFlutterQuillLocalizationException）；
   - 持久化格式：Delta JSON 存 entries.content_delta，纯文本派生存 plain_text 供列表与 FTS。
2. **记录核心 CRUD + 草稿（issue #5）**：
   - `EntriesDao.updateEntryContent`：内容列 + FTS 同一事务重写，version 递增（双写红线延续）；
   - `EntryStatus`（draft/normal/archived）加入领域实体；`EntryDraft` 带 status；
   - 新建流程：进编辑器即落草稿拿稳定 id → 防抖更新；「完成」发布 status=normal；退出时标题正文全空自动进回收站（不留垃圾行）；
   - `shared/widgets/debouncer.dart`：500ms 防抖器（§5.2 规范），flush 用于退出前冲刷；
   - 草稿箱页（watchDrafts 流）：继续编辑 / 丢弃。
3. **回收站（issue #6）**：
   - `softDelete` 双删（FTS 清除）→ `restore` 恢复（FTS 重建），同一事务；watchTrash 流 + 恢复按钮；
   - `purgeExpiredTrash(retainDays: 30)`：物理删除过期软删行；main.dart 启动时静默执行；
   - 时间轴查询改为 `deleted=false AND status='normal'`（草稿不再混入时间轴）。
4. **路由**：/editor（?id=N 编辑）、/drafts、/trash 挂在 shell 之外全屏沉浸；`buildAppRouter()` 工厂化（测试隔离）+ PlainLeafApp.routerConfig 可注入。

### 卡点与解法

1. **quill 11 工具栏 API 与 10.x 不同**：showBulletList/showNumberedList/showUndoRedo 等参数不存在，实际为 showListBullets/showListNumbers/showUndo+showRedo；showSearchButton/showLink/showHeaderStyle 等默认 true 需显式关。对照包源码 simple_toolbar_config.dart 核实。
2. **MissingFlutterQuillLocalizationException**：quill 11 工具栏 build 时读 LocalizationsExt.loc；解法 = MaterialApp.localizationsDelegates 注册 FlutterQuillLocalizations.delegate（flutter_localizations 三件套顺带注册）。
3. **WillPopScope 已弃用**：改 PopScope + onPopInvokedWithResult。
4. **go_router 跨测试污染**：全局 appRouter 是有状态单例，widget 测试间共享导航栈导致「单独跑过、全量挂」；解法 = buildAppRouter() 工厂 + PlainLeafApp.routerConfig 注入，每个用例独立路由实例。
5. **intl 版本冲突**：见上，按 pub solver 建议升 quill 到 ^11.6.0。

### 决策记录

- **新建即落草稿**：为让 500ms 防抖更新始终有稳定主键，新建进入编辑器就 insert 一条 draft 行；空稿退出转回收站而非删除标记复用——保持行历史与回收站语义统一。
- **工具栏按钮精简**：W3 只留文本样式/列表/引用/代码块/缩进/撤销重做；颜色/字体/对齐/链接默认关闭（W4 图片按钮随 flutter_quill_extensions 接入）。
- **清理时机**：启动时同步清理一次（数据量小）；W11+ 若首屏受影响再挪后台 Isolate。

### 验证结果

| 验证 | 结果 |
|---|---|
| dart analyze | No issues found（0 警告 0 提示） |
| flutter test | All tests passed!（+12 = db 1 + repository 3 + lifecycle 4 + UI 4） |
| flutter build apk --debug | 见构建输出（产物同步 build/app/outputs/flutter-apk/） |

### 遗留 / 下一步

- W4：图片输入（拍照/选图）→ 原图入库 → 时间轴展示（issue #7/#8/#9）；图片嵌入编辑器随 flutter_quill_extensions；
- 真机走查（用户操作项）继续保留；建议 W4 前拍板迁仓英文路径。
