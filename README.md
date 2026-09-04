# 素页 PlainLeaf

> 本地优先的多媒体相册记事本 —— 拍照即记、图文时间轴、笔记标签与全文搜索，数据完全属于自己。

**素页（PlainLeaf）** 是一款面向学生与年轻人群的「生活 + 学习」双空间记录工具：以图文时间轴为骨架，融合相册、笔记、日记、待办与学习统计；本地优先、免注册可用、支持 WebDAV 自主同步与端到端加密（V2+）。

## 项目标识

| 项 | 值 |
|---|---|
| 项目名 | 素页（PlainLeaf） |
| 包名（Android applicationId / iOS bundle id） | `com.plainleaf.app` |
| 目标平台 | Android 优先，兼顾 Windows / iOS |
| 开发模式 | 个人独立开发（课余） |
| 计划周期 | 16 周（2026-09-07 起） |

## 技术栈

Flutter 3.x + Dart 3 · flutter_riverpod 2.x · go_router · Drift（SQLite + FTS5）· flutter_quill · camera / image_picker · image / photo_manager · fl_chart（详见项目计划书第 6 章）

## MVP 范围（计划书第 4 章 / 第 5 周末达标）

- 图文记录的增删改查 + 草稿自动保存（500ms 防抖）
- 拍照 / 选图、图片压缩、缩略图、时间轴展示
- 笔记本分类（生活 / 学习双空间 + 自定义）+ 多级标签 + FTS5 全文搜索
- 本地数据库稳定、本地备份（.mlbk）与 Markdown 导出
- Android APK 可真机安装运行

## 开发路线图（16 周）

| 阶段 | 时间 | 内容 |
|---|---|---|
| 阶段 0 | 第 1 周（9/7–9/13） | 立项与环境：Flutter SDK、Android Studio、GitHub 建仓、5 Tab 空框架 |
| 阶段 1 · MVP | 第 2–5 周（9/14–10/11） | 记录内核：数据库 / 编辑器 / 图片管线 / 分类搜索备份，里程碑 M1 v0.1.0-alpha |
| 阶段 2 | 第 6–9 周 | 相册与组织能力，里程碑 M2 v0.2.0 |
| 阶段 3 | 第 10–12 周 | 日记与学习双模块，里程碑 M3 v0.3.0 |
| 阶段 4 | 第 13–15 周 | 同步、安全与分享，里程碑 M4 v0.4.0-beta |
| 阶段 5 | 第 16 周 | 打磨与发布，里程碑 M5 v1.0.0 |

## 工程规范

- 分支：`main`（可发布）/ `dev`（集成）/ `feat/xxx`（功能）
- 提交信息：Conventional Commits（`feat:` / `fix:` / `refactor:` / `docs:`）
- 每个功能对应一个 GitHub Issue，PR 描述关联 Issue
- 每个里程碑打 tag，Release 写变更日志（CHANGELOG）

## 文档

- [项目计划书（HTML）](../相册记事本-项目计划书.html)
- [技术选型与架构图（HTML）](../技术选型与架构图.html)
