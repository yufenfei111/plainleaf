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

## [0.1.0] - unreleased

- M1 目标（2026-10-11）：MVP 记录内核（编辑器/图片管线/搜索/备份），发布 v0.1.0-alpha tag