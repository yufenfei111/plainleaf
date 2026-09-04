# 素页 PlainLeaf

> 本地优先的多媒体相册记事本 —— 拍照即记、图文时间轴、笔记标签与全文搜索，数据完全属于自己。

**素页（PlainLeaf）** 是一款面向学生与年轻人群的「生活 + 学习」双空间记录工具：以图文时间轴为骨架，融合相册、笔记、日记、待办与学习统计；本地优先、免注册可用、支持 WebDAV 自主同步与端到端加密（V2+）。

## 项目标识

| 项 | 值 |
|---|---|
| 项目名 | 素页（PlainLeaf） |
| 包名（Android applicationId / iOS bundle id） | `com.plainleaf.app` |
| 备份包后缀 | `.plbk` |
| 目标平台 | Android 优先，兼顾 Windows / iOS |
| 开发模式 | 个人独立开发（课余） |
| 计划周期 | 16 周（2026-09-07 启动，M1 目标 2026-10-11） |

## 技术栈

Flutter 3.x（fvm 锁版）· Dart 3 · flutter_riverpod 2.x · go_router · Drift（SQLite + FTS5）· flutter_quill · camera / image_picker · image / photo_manager · fl_chart

## MVP 范围（v1.0）

- 图文记录增删改查 + 草稿自动保存（500ms 防抖）
- 选图 / 拍照 → 原图入库 → 时间轴展示（压缩 / EXIF / medium 图在 W6 补全）
- 笔记本分类（生活 / 学习双空间 + 自定义）+ 多级标签 + FTS5 全文搜索
- 本地数据库稳定、本地备份（`.plbk`）导出
- Android APK 可真机安装运行

> 路线图、架构与数据模型、开发规范、阶段 0 清单等完整内容见开发文档；README 不重复维护路线图，避免多处文档各自改一处漏两处。

## 文档

- **开发文档（唯一开发执行依据）**：[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) —— 评审结论、修订版 16 周路线、修正版架构与数据模型、功能开发规范、阶段 0 逐日清单、归档方案、变更记录
- 历史 HTML 计划书（项目计划书、技术选型与架构图）内容已被开发文档吸收修订，冻结归档于 `docs/archive/`，不再维护（归档迁移待执行）
