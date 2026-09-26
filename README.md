# 素页 PlainLeaf

> 本地优先的多媒体相册记事本 —— 拍照即记、图文时间轴、笔记标签与全文搜索，数据完全属于自己。

**素页（PlainLeaf）** 是一款面向学生与年轻人群的「生活 + 学习」双空间记录工具：以图文时间轴为骨架，融合相册、笔记、日记、待办与学习统计；本地优先、免注册可用，支持 WebDAV 云备份（单向）与备份包整包加密（AES-256-GCM，v0.4.0-beta 起）。

## 项目标识

| 项 | 值 |
|---|---|
| 项目名 | 素页（PlainLeaf） |
| 包名（Android applicationId / iOS bundle id） | `com.plainleaf.app` |
| 备份包后缀 | `.plbk` |
| 目标平台 | Android 优先，兼顾 Windows / iOS |
| 开发模式 | 个人独立开发（课余） |
| 计划周期 | 16 周（2026-09-07 启动） |
| 当前版本 | `0.4.0-beta`（M4，阶段 4 已完成并合并入 dev）；M5 `v1.0.0` 为发布目标 |
| 里程碑 tag | `v0.1.0-alpha` / `v0.2.0` / `v0.3.0` / `v0.4.0-beta`（打点依据见 CHANGELOG 顶部索引） |

## 技术栈

Flutter 3.x（fvm 锁版）· Dart 3 · flutter_riverpod 2.x · go_router · Drift（SQLite + FTS5）· flutter_quill · camera / image_picker · image / photo_manager · fl_chart

## 功能现状（v0.4.0-beta）

- 图文记录：增删改查 + 500ms 防抖自动保存 + 草稿箱 + 回收站（软删，可恢复）
- 图片：选图 / 拍照 → 原图入库 → 两级缩略图管线（Isolate 转码 + EXIF 方向烘焙）+ 保存到系统相册
- 时间轴：月分组 / 筛选器 / 置顶 / 多选批量操作；另有相册网格、日历回顾、「那年今日」
- 组织：笔记本（生活 / 学习双空间 + 自定义）+ 多级标签 + FTS5 全文搜索 + Markdown 导入
- 学习：日记模板 + 心情打卡 + 待办 + 学习统计
- 外观：主题系统（浅色 / 深色 / 跟随系统 + 强调色）+ 字号缩放 + 启动过场
- 备份与导出：本地 `.plbk` 备份包、Markdown / PDF 导出、WebDAV 云备份（单向）
- 安全：备份包 AES-256-GCM 整包加密、应用锁（密码 + 生物识别快速解锁）

> 完整的逐周变更见 [CHANGELOG.md](CHANGELOG.md)。

> 路线图、架构与数据模型、开发规范、阶段 0 清单等完整内容见开发文档；README 不重复维护路线图，避免多处文档各自改一处漏两处。

## 文档

- **开发文档（唯一开发执行依据）**：[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) —— 评审结论、修订版 16 周路线、修正版架构与数据模型、功能开发规范、阶段 0 逐日清单、归档方案、变更记录
- 历史 HTML 计划书（[项目计划书](docs/archive/相册记事本-项目计划书.html)、[技术选型与架构图](docs/archive/技术选型与架构图.html)）内容已被开发文档吸收修订，冻结于 `docs/archive/`，只读不再维护
- 隐私政策：[PRIVACY.md](PRIVACY.md) —— 逐条对应代码事实（不收集、不联网、无第三方 SDK）
- 发布检查清单：[docs/release-checklist-w16.md](docs/release-checklist-w16.md) —— 含 release 构建的 ASCII 路径约束、签名步骤、真机矩阵
- 真机走查手册：[docs/device-checklist-w13-w14.md](docs/device-checklist-w13-w14.md) —— 26 条，含预期现象与失败判据
