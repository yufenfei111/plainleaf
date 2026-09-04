# 素页 PlainLeaf · 最终开发文档 v1.1

> 基于《相册记事本-项目计划书 v1.0》《技术选型与架构图》、plainleaf README 与现有代码现状（2026-09-04）评审后整合而成。
> 本文档是唯一的开发执行依据；HTML 计划书转为归档资料，后续变更一律改本文件并记录于文末变更表。

---

## 一、文档评审结论：发现的不合理部分（必读）

### 🔴 P0 — 必须立即解决

| # | 问题 | 说明 | 处理决定 |
|---|------|------|----------|
| 1 | **项目命名严重分裂** | 计划书全篇叫「拾光札记 MemoLeaf」（目录示例 `memoleaf/`、备份后缀 `.mlbk`、包名示例 `com.yourname.memoleaf`），而 GitHub 仓库 README 叫「素页 PlainLeaf」（包名 `com.plainleaf.app`）。包名、备份文件后缀、目录名、文档四处将来全部要改，越晚改成本越高 | **统一为「素页 PlainLeaf」**：包名 `com.plainleaf.app`，备份后缀改为 `.plbk`，所有文档中的 MemoLeaf/拾光札记/mlbk 表述废弃 |
| 2 | **规划文档引用"对话"** | 计划书 7.1 写"配套的分层架构示意图见**对话中**的独立可视化"，文档自包含性被破坏，脱离本次对话即失效 | 本文档第四章已内含架构说明；HTML 归档，不再维护 |
| 3 | **三处文档各自维护路线图** | 计划书 HTML、架构图 HTML、README 各写一份路线图/规范，改一处漏两处 | 路线图与规范**只保留在本文件**；README 只放简介 + 指向本文件 |
| 4 | **仓库无 CHANGELOG** | 计划书自己要求"Release 写变更日志"，但 plainleaf 仓库只有 README，无 CHANGELOG.md、无 Issue 模板 | 阶段 0 内补齐（见 §6 清单） |

### 🟡 P1 — 本周内修正

| # | 问题 | 说明 | 处理决定 |
|---|------|------|----------|
| 5 | **排期风险点：W4 图片管线** | 一周内完成 image_picker/camera + 压缩 + 两级缩略图 + Isolate 转码 + 图文混排，对新手明显超载，这是 MVP 阶段最可能崩的一周 | 图片管线拆两步：W4 只做「选图 → 原图入库 → 时间轴显示」；压缩/medium 图/EXIF 移到 W6 相册阶段 |
| 6 | **排期风险点：W13 WebDAV 双向同步** | 计划书 6.4 自己说"第一版只做备份/恢复，双向同步放第 13 周以后"，但 W13 就排了双向 LWW，自相矛盾且一年内最难工程点只给一周 | W13-14 只做 **WebDAV 单向备份上传/恢复**；双向 LWW 同步移到 v1.0 之后作为 v0.5/v2 迭代（与计划书 6.4 的演进节奏对齐） |
| 7 | **MoSCoW 与路线图不对齐** | W8「地点记录」（MoSCoW 中是 Could 级）、W9「Markdown 导入」（MoSCoW 表中根本没出现）被排进固定周——这正是计划书警告过的范围蔓延信号 | 地点/EXIF 改为"有buffer再做"；Markdown 导入明确标注 Should，排在 W9 可选项，砍掉不影响里程碑 |
| 8 | **数据模型缺陷** | ① `hash_sha1` 应改 `hash_sha256`（SHA-1 已不安全）；② `todos` 缺 `completed_at`（学习统计需要完成时间）；③ `entries` 缺 `metadata_json` 弹性字段（日记模板问答等扩展内容）；④ FTS5 与 entries 的同步机制未写明（trigger 还是 Repository 双写） | 建表时按 §4.3 修正版执行；FTS 同步统一走 **Repository 层事务内双写**（不用 trigger，便于测试） |
| 9 | **存储职责重叠** | `settings_kv`（数据库）与 `shared_preferences` 边界没定义 | 约定：**需要同步/备份的配置**（主题、字体、备份计划）→ `settings_kv`；**纯设备本地偏好**（窗口尺寸、最近搜索）→ `shared_preferences`；**加密密钥** → `flutter_secure_storage` |
| 10 | **目录示例歧义** | 工程结构图中 `<feature>/data · domain · presentation` 缩进在 settings 下方，易读成仅 settings 有三层；应用锁放在 core/security 但入口在「我的」Tab | 澄清：**每个 feature 统一 data/domain/presentation 三层**；应用锁 UI 在 features/settings，加解密实现在 core/security |

### 🟢 P2 — 采纳/放宽

- 测试"核心逻辑覆盖率 70%"对课余独立开发偏高：**仅对 core 逻辑（Repository/LWW/图片管线/统计计算）设 70% 硬指标，UI 层不设覆盖率指标**，以 Widget 测试覆盖主链路即可。
- 开源协议建议 AGPL-3.0：若目标是软著/竞赛/简历展示且暂不担心闭源 fork，**MIT 或 Apache-2.0 更省心**；若坚持防白嫖闭环产品再选 AGPL-3.0。阶段 5 前决定即可。
- counter_demo 的 `main.dart` 使用了 Dart 3.10+ 点简写语法（`.fromSeed`、`.center`），说明本地 SDK 很新——**用 fvm 锁定 Flutter 版本**写入 `.fvmrc`，避免"我机器能跑"问题。

---

## 二、项目标识（唯一版本）

| 项 | 值 |
|---|---|
| 项目名 | 素页 PlainLeaf |
| 包名 | `com.plainleaf.app` |
| 备份包后缀 | `.plbk` |
| 代码仓库 | `plainleaf/`（GitHub: main / dev 双分支） |
| 技术栈 | Flutter 3.x（fvm 锁版）· Dart 3 · Riverpod 2 · go_router · Drift(SQLite+FTS5) · flutter_quill · image/photo_manager · fl_chart |
| 定位 | 本地优先的「生活+学习」双空间图文记录工具；免注册、WebDAV 自主同步 |
| 周期 | 16 周，2026-09-07（周一）启动，M1 目标 2026-10-11 |

---

## 三、开发路线（修订版 16 周）

在原计划基础上做了三处调整（W4 减负、W13-14 降级为单向备份、双向同步移出 v1.0）：

| 阶段 | 周 | 日期 | 内容 | 里程碑 |
|---|---|---|---|---|
| 0 立项与环境 | W1 | 9/7–9/13 | Flutter 环境+fvm 锁版；Dart 速通；**5 Tab 空框架**；GitHub 补齐 CHANGELOG/Issue 模板/CI | 可真机运行空壳 |
| 1 MVP 记录内核 | W2–W5 | 9/14–10/11 | W2 Drift 建表(§4.3 修正版)+Repository+Riverpod+时间轴静态 UI；W3 quill 编辑器+CRUD+500ms 自动保存+草稿；W4 **选图/拍照→原图入库→时间轴展示**（压缩后移）；W5 笔记本/标签+FTS5 搜索+本地备份(.plbk)导出+真机走查 | **M1 `v0.1.0-alpha`（10/11）** |
| 2 相册与组织 | W6–W9 | 10/12–11/8 | W6 **图片管线补全**（压缩/medium/EXIF/Isolate）+相册网格+滚动优化；W7 月分组+筛选器+置顶收藏+回收站；W8 详情页打磨+空态引导（地点记录为可选项）；W9 主题系统+设置+（可选）Markdown 导入；**邀请 3–5 位同学试用** | **M2 `v0.2.0`** |
| 3 日记与学习 | W10–W12 | 11/9–11/29 | W10 日记模板+心情打卡+日历视图+连续天数；W11 待办+番茄钟（后台+通知）+速记箱；W12 fl_chart 统计（柱状/热力图）+那年今日+本地通知 | **M3 `v0.3.0`** |
| 4 安全与分享 | W13–W15 | 11/30–12/20 | W13 WebDAV **单向备份上传/恢复**（坚果云实测）；W14 AES-GCM 加密选项+应用锁+Markdown/PDF 导出；W15 学习打卡卡片+日记长图+系统分享 | **M4 `v0.4.0-beta`** |
| 5 发布 | W16 | 12/21–12/27 | 真机矩阵测试（≥3 台 Android）、性能优化、图标/隐私政策/协议、Release 发 APK+Windows 包、社区投递 | **M5 `v1.0.0`** |

**v1.0 后迭代队列**（不进 v1.0 排期）：WebDAV 双向 LWW 同步（uuid+version+软删除字段已在建表时预留）→ 语义搜图/复习卡片 → 远期社区。

**节奏纪律**：每周日晚产出一个可演示构建（`flutter build apk --debug` 装真机）；期中/期末周只保 M1/M5；新点子一律写进「灵感清单」不插队。

---

## 四、架构与数据模型（修正版）

### 4.1 分层
轻量 Clean Architecture，五层：Presentation(Page/Widget) → State(Riverpod) → Domain(纯 Dart 实体/仓库接口/用例) → Data(Drift DAO/文件存储/WebDAV) → Core(图片管线/加密/备份/通知/权限)。上层只依赖下层抽象。

### 4.2 目录（feature-first，每个 feature 统一三层）

```
plainleaf/
├── lib/
│   ├── app/            # 入口、主题、go_router
│   ├── core/
│   │   ├── db/         # Drift: tables / daos / database.g.dart
│   │   ├── storage/    # 媒体文件、.plbk 备份包
│   │   ├── sync/       # WebDAV client（v1.0 仅单向）
│   │   └── security/   # 加解密、密钥
│   ├── features/       # timeline / editor / gallery / notebooks /
│   │                   # diary / study / search / share / settings
│   │   └── <feature>/data · domain · presentation   # ← 每个 feature 都是这个结构
│   └── shared/         # 共享 widget、扩展
├── test/               # 镜像 lib 结构
├── docs/               # 本文件、开发日志、灵感清单
└── CHANGELOG.md
```

### 4.3 核心数据表（对计划书 7.2 的 4 处修正已并入）

- 所有业务表统一携带 `uuid / created_at / updated_at / version / deleted`（为 v1.0 后双向同步预留，**第一版建表必须加**）。
- `assets.hash_sha1` → **`hash_sha256`**。
- `todos` 增加 **`completed_at`**（学习统计"每日完成数"依赖它）。
- `entries` 增加 **`metadata_json`**（日记模板问答、心情扩展等弹性内容，避免频繁改表）。
- `entries_fts` 同步：**Repository 事务内双写**（写 entries 同事务写/删 FTS 行），不用数据库 trigger，保证可测试。
- 存储分工：需同步配置→`settings_kv`；设备本地偏好→`shared_preferences`；密钥→`flutter_secure_storage`。

媒体文件：原图存 `media/yyyy/mm/<uuid>.jpg`，`thumb/`（长边 400, q80）与 `medium/`（长边 1600）两级，数据库只存相对路径；删除走软删除+回收站 30 天清理；备份包 `.plbk` = zip(db + media + manifest.json)。

---

## 五、功能开发规范

### 5.1 Git 与协作
- 分支：`main`（可发布，受保护）/ `dev`（集成）/ `feat/<模块>-<内容>`（如 `feat/editor-autosave`）。
- 提交：Conventional Commits（`feat:` `fix:` `refactor:` `docs:` `test:` `chore:`），单次提交只做一件事。
- 一个功能 = 一个 GitHub Issue（用模板：背景/验收标准/估时≤2h 粒度拆分），PR 关联 `Closes #N`。
- 每个里程碑打 tag `v0.x.0`，CHANGELOG.md 按 Keep a Changelog 格式手写。

### 5.2 代码规范
- `flutter_lints` 全量启用，`flutter analyze` 0 警告方可合并；CI（GitHub Actions）在 push/PR 时跑 `analyze + test`，打 tag 时自动 `build apk` 附加到 Release。
- 生成文件（`*.g.dart`、`*.freezed.dart`）必须提交入库，build_runner 版本随 pubspec 锁定。
- 状态管理只用 Riverpod：页面不直接触碰 DAO/文件系统，一律经由 Repository；异步用 `AsyncValue`，错误三层透传（数据层抛领域异常 → Notifier 转 AsyncError → UI 统一 SnackBar/空态）。
- 数据库：任何写操作走事务；**每次表结构变更必须写 Drift Migration + 迁移测试**，禁止"卸载重装"式绕过；升级前自动做一次 `.plbk` 备份。
- 性能红线：时间轴/相册滚动 60fps（缩略图本地缓存+分页）；冷启动 < 2s；图片转码一律 Isolate；正文 ≥14sp、触控目标 ≥44dp。
- UI 走查三要素：空态、加载态、错误态缺一不可；暗色模式与字体放大必测。
- 数据红线：删除一律软删除；权限按需申请并解释用途；密钥永不入 `shared_preferences`/代码。

### 5.3 测试策略（按修订后的指标）
- 单元测试（硬指标 70% 覆盖，仅限 core）：Repository、FTS 双写、备份打包/恢复、图片管线、统计计算。
- Widget 测试：编辑器自动保存（500ms 防抖）、时间轴渲染、搜索高亮。
- 集成测试主链路：建记录 → 搜得到 → 备份 → 恢复 → 数据一致。
- 每个里程碑手动演练一次备份恢复 + 手工真机清单（权限拒绝/断网/低存储/进程被杀/暗黑/字体放大）。

### 5.4 工具链（2026 独立开发者最小配置）
- 版本管理：fvm 锁 Flutter（写入 `.fvmrc`）+ Git + GitHub CLI。
- IDE：Android Studio（真机/性能）+ VS Code（Dart 编辑）。
- AI 辅助：Gemini CLI（免费 1000 次/天）或 Aider；生成的代码必须自己读懂再提交。
- CI/CD：GitHub Actions（analyze/test/build 三 job）。
- 设计：Figma / 即时设计 / Penpot（开源）画 5 主页面线框，先纸后码。
- Windows 效率：scoop 安装 `eza bat fd ripgrep dust delta`；终端用 Windows Terminal。

---

## 六、阶段 0（本周 9/7–9/13）执行清单

- [ ] Day 1：安装 Flutter SDK + fvm 锁版本，`flutter doctor` 全绿，真机跑 Hello World
- [ ] Day 2–3：Dart 速通 + Widget 基础，手写静态时间轴页
- [ ] Day 4：Riverpod + go_router，5 Tab 框架可切换
- [ ] Day 5：Drift demo 跑通建表/DAO/Stream 查询（**用 §4.3 修正版表结构**）
- [ ] Day 6：Figma/纸笔画 5 主页面线框并走查 3 遍；GitHub 建 Issue 模板 + CHANGELOG.md + CI workflow
- [ ] Day 7：空壳工程提交 dev 分支、PR 合 main、写第 1 周开发日志

---

## 七、归档与仓库整理意见

当前 `豆包/` 目录混杂了正式项目、练手 demo、临时缓存和无关项目，建议整理为：

```
豆包/
├── plainleaf/                  # ← 唯一正式仓库（即现在的 相册记事本项目/plainleaf）
│   ├── docs/
│   │   ├── DEVELOPMENT.md      # ← 本文档（移入仓库版本管理）
│   │   ├── archive/            # 两份 HTML 计划书原样归档，只读不再维护
│   │   └── ideas.md            # 灵感清单（范围蔓延防火墙）
│   └── ...
└── _archive/                   # 与 plainleaf 无关的一切
    ├── flutter_counter_demo/   # Flutter 模板练手工程（含 .dart_tool/.idea/build 数十 MB 产物；
    │                           #   若留作 Dart 语法参考，删除构建产物目录后移入此处）
    ├── fitness-tracker/        # 无关小项目
    ├── dev-tools-summary/      # 工具调研报告，属个人资料非项目资产
    └── .preview/               # 豆包 HTML 预览缓存，可直接删除
```

要点：
1. **`flutter_counter_demo` 不进 plainleaf 仓库**——它是 `flutter create` 原始模板（README 还是 "counter_demo"），仅证明环境可跑；若保留，删掉 `.dart_tool/`、`.idea/`、`build/`、`windows/flutter/ephemeral/` 后存 `_archive/`。其中 `local.properties` 含本机 SDK 路径，任何仓库都不该提交。
2. **两份 HTML 计划书**内容已被本文档吸收修订，移入 `docs/archive/` 冻结；后续需求变更改本文档并记变更表。
3. **`.preview/` 是渲染缓存**，确认 HTML 已归档后即可删除。
4. **plainleaf 仓库现状检查**：已有 main/dev 双分支和 origin 远端，起步姿势正确；下一步只需按第六章把空壳工程与文档补进去。

---

## 八、变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1.1 | 2026-09-04 | 依据计划书 v1.0 评审：统一命名为 PlainLeaf；修订 W4/W13 排期；修正数据模型 4 处；补充开发规范与归档方案 |
| v1.0 | 2026-09-03 | 《相册记事本-项目计划书》初版（拾光札记 MemoLeaf，已归档） |
