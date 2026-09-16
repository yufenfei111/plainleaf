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

## [0.1.0] - unreleased

- M1 目标（2026-10-11）：MVP 记录内核（编辑器/图片管线/搜索/备份），发布 v0.1.0-alpha tag