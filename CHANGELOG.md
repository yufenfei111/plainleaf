# Changelog

本文件记录素页 PlainLeaf 的所有重要变更。
格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。
每个里程碑（M1-M5）打 tag 时在此补写正式条目。

## [Unreleased]

### Added（阶段 0 · 立项与环境，2026-09-04 ~ 09-15）
- Flutter 工程初始化：fvm 锁定 3.47.2，包名 com.plainleaf.app，Android/iOS/Windows 三平台脚手架（Day 1）
- 国内构建链路：Gradle 腾讯云镜像 + 依赖阿里云镜像优先（Day 1，见 docs/devlog-w1.md）
- 5 Tab 空框架：时间轴 / 相册 / 学习 / 笔记本 / 我的，go_router StatefulShellRoute + NavigationBar
- Drift 数据层（§4.3 修正版）：notebooks / entries / assets / tags / entry_tags / todos / study_sessions / sync_meta / settings_kv 九表 + entries_fts FTS5 虚表；统一携带 uuid/created_at/updated_at/version/deleted 五字段；hash_sha256、todos.completed_at、entries.metadata_json 三处修正并入
- DAO：EntriesDao（时间轴联表 Stream）/ TodosDao（开关待办）/ NotebooksDao
- 演示种子数据：首启幂等写入 2 笔记本 + 4 条记录 + 2 条待办（settings_kv.seed_v1 标记）
- 主题骨架：米白纸张底 #FAF7F2 + 低饱和青绿主色，明暗双套（设计基调见 frontend/README.md）
- 冒烟 Widget 测试：骨架渲染 + Tab 切换 + 待办勾选交互（test/smoke_test.dart）
- 仓库基建：Issue 模板（背景/验收/≤2h 拆分）、GitHub Actions CI（analyze + test）、本 CHANGELOG
- 静态时间轴页：日期锚点分组 + 图文卡片 + 心情色点 + 空态/加载态/错误态三态齐全

### Added（阶段 1 · W2 Repository 层，2026-09-16）
- Repository 分层：timeline/study/notebooks 三组「领域实体 + 接口 + 本地 Drift 实现」，UI 全量迁移 Riverpod AsyncValue（features/*/presentation/providers/）
- FTS5 事务双写：EntriesDao.saveEntry / softDelete 单事务同步维护 entries_fts（不用 trigger，§4.3 红线）；种子数据重构为单事务幂等写入
- 统一异常层：PlainLeafException / DatabaseException（错误三层透传第一层）
- 测试：test/repository_test.dart（双写/软删/领域映射 3 例），全套 7 例全绿

### Added（阶段 1 · W3 记录内核，2026-09-16）
- flutter_quill 11.6 富文本编辑器：/editor 全屏编辑页，500ms 防抖自动保存，AppBar 保存状态提示；Delta JSON 持久化（content_delta）+ 纯文本派生（plain_text）
- 记录生命周期：新建即落草稿 → 「完成」发布；EntryStatus（draft/normal/archived）全链路；草稿箱页（/drafts）
- 回收站（/trash）：软删除/恢复单事务双写 FTS；30 天过期启动清理（purgeExpiredTrash）
- 路由工厂化 buildAppRouter()（测试隔离）；时间轴入口：FAB 新建、卡片点击编辑、AppBar 草稿箱/回收站
- 测试：test/lifecycle_test.dart 4 例（更新双写/草稿流转/回收恢复/30 天清理），全套 12 例

### Added（阶段 1 · W4 图片输入与入库，2026-09-16）
- MediaStorage 私有目录服务：原图复制 media/yyyy/mm/（相对路径统一正斜杠），resolve/deleteRel
- 图片附件条：编辑器内拍照/选图（image_picker 1.2.3）→ attachImage 落 assets 表 → 缩略图条可删除；时间轴卡片消费 firstAssetRelPath 显示真实缩略图
- AssetsDao：attach/byEntry/softDelete；Repository 附件能力（attachImage/firstImagePath，构造注入 AssetsDao+MediaStorage）
- 测试：test/media_test.dart 3 例（导入解析/挂接取图/无图与软删语义），全套 15 例

### Added（阶段 1 · W5 组织与备份，2026-09-20）
- 笔记本管理（#10）：NotebooksDao.create 自定义本、条目计数、按空间分组
- 标签管理（#11）：TagsDao 创建/重命名/软删/打标/查询；tags.parent_id 多级标签预留，schemaVersion 1 → 2，
  走 Drift MigrationStep.addColumn（+ onCreate 裸库补列防御），迁移测试覆盖
- FTS5 搜索页（#12）：/search 全屏检索 + 类型过滤；CJK 前缀化预处理（中文单 token 需转 '学习*' 才命中）
- 备份包（#13）：BackupService 用 VACUUM INTO 一致性快照打 .plbk（db + media + manifest.json），
  verify 校验格式版本；**设置页补「从备份包恢复」入口**（选包 → 二次确认 → 自动预备份 → 覆盖 → 提示重启），
  此前仅服务层有实现、M1「备份→恢复→一致」链路是断开的
- Markdown 导出（#14）：已发布记录导出为单 .md，排除草稿与软删（M1 形态仅控制台预览，落文件排 W6）
- 依赖：archive ^3.6.0（zip 打包）
- 测试：test/w5_test.dart 7 例 + test/migration_test.dart 1 例，合计 23 例（本机 flutter_tester 无法启动，待 CI/开发机复核）

### Added（阶段 1 · W5 验收补齐，2026-09-20）
- 搜索关键词高亮（#12 补齐）：buildHighlightSpans 切分命中区间（重叠合并、无命中不拆分），
  结果标题/摘要改 Text.rich 渲染 + 4 例测试（§5.3 验收项，此前功能缺失）
- 编辑器 500ms 防抖专项测试：窗口内不落库、越过窗口自动落库（不点「完成」也生效）
- 主链路集成测试 test/main_flow_test.dart：建记录 → FTS 命中 → 导出 .plbk → 恢复 → 重开库校验
  数据与索引 + 断言恢复前自动备份（放 test/ 以便并入 flutter test，integration_test 需真机）
- core 手写代码行覆盖率 65.3% → **73.5%**（§5.3 硬指标 70%）：补齐 restore 全链路、
  笔记本 rename/softDelete/insertNotebook、MediaStorage.deleteRel、DatabaseException
- 验收报告 docs/verification-w5.md：结论表、分组覆盖率、真机走查清单、本机环境要点

### 验收结果（2026-09-20）
- flutter analyze：No issues found；flutter test：**32/32 passed**；core 手写覆盖率 73.5%
- flutter build apk --debug：通过（build/app/outputs/flutter-apk/app-debug.apk）
- 遗留：真机走查（10 项清单见 verification-w5.md）待执行；iOS 本期不纳入

### Fixed（2026-09-20 · 真机反馈）
- **编辑器打开记录正文空白，且保存会清空正文（数据丢失级）**：contentDelta 为空串时
  jsonDecode 抛异常后直接给空文档，此时输入标题或点「完成」触发的 flush 会用空文档覆盖
  plainText。改为 Delta 为空/非法/无实质内容时用 plainText 回填；种子数据补齐 contentDelta
- 损坏图片会让解码器抛 RangeError（Error 而非 Exception），原 `on Exception` 兜不住
  ——等价"挂一张坏图就崩"。改为 `on Object` 降级 + 管线内统一转 FormatException

### Added（阶段 2 · W6 图片管线与相册，2026-09-20）
- 两级缩略图管线（§4.3）：thumb 长边 400/q80、medium 长边 1600/q82，转码跑 `Isolate.run`
  不占 UI 线程；烘焙 EXIF 方向；小图不放大；顺带回填 width/height/hash_sha256
- 时间轴卡片性能改造：优先渲染 thumb + `cacheWidth` 按显示尺寸解码；去掉逐卡 FutureBuilder
  （新增 supportDirProvider 顶层取一次路径）；加视口缓冲 `ScrollCacheExtent.viewport(1)`
- 相册页（W6 主线）：按 §4.2 三层结构实现，CustomScrollView + SliverGrid 月分组网格，
  分页（首屏 60，距底 500px 续拉），空/加载/错误三态齐全
- 存储约定统一：相对路径以支持目录为基准（media/…、thumb/…、medium/…），兼容 W4 旧数据
- 备份包 plbk/1 → plbk/2：打包 media + thumb，排除可重算的 medium；verify 兼容两代
- 依赖：image ^4.2、crypto ^3.0
- 测试：test/thumbnail_test.dart 5 例（缩略图尺寸/小图不放大/attach 回填/backfill/分页）
  + test/editor_fallback_test.dart 1 例回归；全套 38/38，core 手写覆盖率 73.5% → 77.2%

### Added（阶段 2 · W7 组织：月分组 / 筛选 / 置顶 / 回收站，2026-09-21）
- 时间轴月分组（#21）：「2026年09月 · N 条」月头 + 月内日锚点；分组抽成 domain 纯函数
  `groupByMonth`（置顶独立成组并排最前，避免置顶优先被月份切碎），可直接单测
- 筛选器（#21）：笔记本 / 类型 / 仅看置顶三维度，**过滤下推 SQL where**——不在客户端过滤，
  否则先 `LIMIT 100` 再筛会出现"筛选后只剩几条"的假象；筛选态由 `timelineFilterProvider`
  持有，可一键清除；筛选后无结果有独立空态文案
- 置顶收藏（#22）：卡片置顶标记 + 长按菜单切换置顶 / 移到回收站（删除带撤销 SnackBar）
- 回收站（#23）：恢复 / 永久删除（二次确认）/ 清空回收站，并显示剩余保留天数；
  硬删在同一事务内清理 `entries_fts`、`entry_tags`，关联 assets/todos 一并软删
  （drift 默认开外键，子表行必须先处理）
- 历史缩略图补齐（#24，W6 遗留）：设置页入口消费 `backfillDerived`，W4 期无 thumb 的图不再
  只能回退原图解码
- 写操作门面 `TimelineActions`：置顶/删除/恢复/清空/补齐统一入口，错误统一转 SnackBar，
  避免每个 Widget 各写一遍 try/catch
- 测试：test/w7_test.dart 12 例；全套 **50/50 passed**，core 手写覆盖率 77.2% → **79.3%**

### Fixed（阶段 2 · W10 自检：性能 / 交互 / 缺陷修复，2026-09-22）

自检方式：全量代码走查（61 个 dart 文件）+ `dart analyze --fatal-infos` + `flutter test`；
完整问题清单、修复方案与后续计划见 `docs/verification-w10.md`。

**P0 缺陷**
- 编辑器图片全部破图：附件相对路径未拼支持目录；改为「thumb 优先 + 支持目录拼接 +
  `cacheWidth=72×DPR`」，挂接后回读库里的 thumbPath（不再用 image_picker 的临时缓存路径）
- 新建/重命名笔记本或标签后整页被弹走：对话框收尾误用页面级 context 调 `pop()`
- 相册续拉失败清空已加载列表：改为保留数据 + 单独暴露 `loadMoreError`，底部给重试入口
- Markdown 导出只 print 不落文件：改为写入 `supportDir/export/素页导出-yyyyMMdd-HHmm.md`

**P1 缺陷 / 性能**
- 新建记录首帧的输入被静默丢弃（id 未就绪）→ 标记待存，id 就绪立即冲刷
- 退出编辑器丢最后 500ms 输入 → `dispose` 先 flush 再关门
- 点「完成」偶发内容停在旧版本 → 新增 `Debouncer.flushAsync`，await 内容落库后再置 status
- 编辑器无法设置类型 / 笔记本 / 心情 → 新增 `updateEntryMeta`（DAO→Repository）+ 属性条
- 笔记本页角标闪 0 且 N 次查询 → 新增 `watchEntryCountsByNotebook()`（一条 GROUP BY + 流）
- 笔记本点击无反应 → 设筛选并跳时间轴
- 搜索结果落编辑器 → 改跳 `/detail?id=N`
- 详情页富文本嵌套滚动（QuillEditor `scrollable:false`）；全屏大图也限制解码尺寸
- 时间轴图片失败态从「空白色块」改为破图图标（可归因）
- 冷启动：回收站清理移出首帧路径（`unawaited`）
- 相册图片点不动 → 跳所属记录详情

**交互 / 渲染打磨**
- 统一页面过渡动画（200ms 淡入 + 1.5% 上移，仅全屏路由）：`app/transitions.dart`
- 卡片缩略图 → 详情首图 Hero 共享元素（`entry-thumb-<id>`）
- 保存状态 `AnimatedSwitcher`；相册下拉刷新（`AlwaysScrollableScrollPhysics`）
- AppBar 图标语义修正（草稿箱 `drafts_outlined` / 回收站 `restore_from_trash`）
- `ImageCache` 调为 400 张 / 96MB，减少来回滑动时的重复解码

- 测试：test/w10_fixes_test.dart 5 例；全套 **81/81 passed**，`dart analyze --fatal-infos` 0 issue

### Added（阶段 2 · W11：W10 收尾 + 体验与信息架构第一期，2026-09-23）

5 个子代理并行改造 12 个文件、新增 7 个文件（+1274 / −149）。**未引入任何第三方依赖**，
依赖选型比对与完整自查见 `docs/verification-w11.md`。

**启动体验**
- 首屏主题预读：`main()` 在 `runApp` 前读一次「主题模式/字号/强调色」并经 ProviderScope 注入
  （`AppearanceSnapshot` / `initialAppearanceProvider`），消除「默认主题 → 恢复主题」的一次重绘；
  字段全可空 + 默认空快照，所有只 override `dbProvider` 的既有测试行为不变
- 共享骨架屏 `shared/widgets/skeleton.dart`（`SkeletonBox` / `TimelineSkeleton` / `GridSkeleton`）：
  **刻意不做呼吸动画** —— 循环动画会让 `pumpAndSettle` 永远等不到静止

**时间轴**
- 分页续拉：首屏 40 条（`kTimelinePageSize`）+ 滚动续拉；用「取前 N 条」而非 offset，
  因为队首随时会插入新记录，offset 第二页必然错位
- 下拉刷新（`RefreshIndicator` + `AlwaysScrollableScrollPhysics`），刷新时 limit 复位
- loading 态由转圈改为骨架屏；续拉时不退回整页骨架（按 `AsyncValue.hasValue` 分流）
- 筛选交互重做：横向 chip 长条 → 「筛选」入口（带已选数量徽标）+ 底部弹层（笔记本/类型/仅看置顶
  + 重置/查看结果）；弹层内改草稿、「查看结果」才提交，避免每点一个 chip 都重查一次流

**学习 Tab**
- 待办录入：顶部录入行（回车即添加，空/纯空格不落库并给轻提示）+ 未完成/已完成分组
  （已完成默认折叠，但无未完成项时强制展开，否则看起来像数据丢了）
- 左滑删除走**软删**（`deleted=1` + version+1），写库成功才真滑走，SnackBar 带「撤销」
- `TodosDao` 新增 `addTodoWithContent` / `softDeleteTodo` / `restoreTodo`（手写 Drift DSL，无代码生成）

**编辑器**
- 底部字数统计（去空白、按 runes 计，`ValueNotifier` 局部刷新，不重建 QuillEditor）
- 退出二次确认：`shouldConfirmExit = dirty && !empty && !bypass` —— 空记录不拦、已落库不拦、
  点「完成」发布不拦（否则发布被自己的 PopScope 挡死）
- 附件图长按看大图：medium 优先 + `cacheWidth` 限制（与原详情页同口径），不做缩放手势

**相册**
- 新增全屏浏览 `photo_viewer_page.dart`：PageView 翻页 + `InteractiveViewer` 缩放（1×–4×）、
  三级渐进（thumb→medium→原图，每级都带 `cacheWidth`）、背景取 `colorScheme.scrim`、`Navigator.push(rootNavigator)` 自建 200ms 淡入
  —— 取代 W10「点图跳详情」的过渡方案；长按菜单保留「查看所属记录」

**工具**
- 新增 `tool/inprocess_analyze.dart`：本机创建子进程管道被安全策略拦截（`ERROR_PIPE_BUSY 231`）
  时，`dart analyze` / `flutter test` 均崩溃；该工具在同进程内跑 analyzer 做兜底。
  **覆盖范围有限**：能抓编译/类型错误，抓不到 lint；环境恢复后请以 `flutter analyze` 为准

- 测试：新增 test/w11_{timeline,startup,study,editor,gallery}_test.dart 共 22 例
  ⚠️ **全部未经执行** —— 本机会话无法派生子进程；请在正常环境按 `docs/verification-w11.md` 第六节补跑

## [0.1.0] - unreleased

- M1 目标（2026-10-11）：MVP 记录内核（编辑器/图片管线/搜索/备份），发布 v0.1.0-alpha tag