# 阶段 0 逐日开工检查表（W1 · 2026-09-07 ~ 09-13）

> 本表是 `DEVELOPMENT.md` §6「阶段 0 执行清单」的可勾选执行版，**唯一执行依据仍是 DEVELOPMENT.md**；
> 阶段 0 收尾时把过程记录并入开发日志（`docs/devlog-w1.md`），本表不再单独维护，避免多处文档重复。
> 本周里程碑：**可真机运行的空壳工程** + 仓库基建（CHANGELOG / Issue 模板 / CI）。
> 节奏：课余每天 1–2 小时；周日晚上必须产出一个可演示构建（`flutter build apk --debug` 装真机）。

## 每日收尾（通用）

- [ ] 卡点已记录：报错原文 + 已尝试解法 → 记入当日开发日志
- [ ] 当天变更可在 dev 分支提交（或留下明确的 TODO）

---

## Day 1 · 9/7（周一）环境就绪

**目标**：本机能编译，真机能跑，仓库里长出 Flutter 工程。

- [x] 安装 Flutter SDK（稳定版），`flutter --version` 可用 → 3.47.2 stable / Dart 3.13.2
- [x] 安装 fvm，`fvm install <锁定版本>` + `fvm use` 生成 `.fvmrc`（锁版，避免"我机器能跑"）→ fvm 4.3.0 锁定 3.47.2；Windows 符号链接权限问题用 junction 等效替代，见 devlog-w1 Day1
- [x] `flutter doctor` 全绿（Android toolchain / 真机识别 / license 已接受）→ No issues found（真机待连接）
- [x] 在 plainleaf 仓库根目录初始化工程：`flutter create . --org com.plainleaf.app --project-name plainleaf`
      （实际用 `--platforms=android,ios,windows` 收敛目标平台；注意 --org 会拼出 com.plainleaf.app.plainleaf，已手工修正为 com.plainleaf.app，详见 devlog-w1 Day1 卡点 1）
- [ ] 真机跑通空壳：USB 调试开启，`flutter run -d <device>` 手机亮起 Flutter 默认页（**待连接真机，需用户操作**）

**验收**：`flutter build apk --debug` 在本机成功产出 APK（✅ 已产出，aapt2 核验包名/应用名正确）；真机安装可打开（⏳ 待真机）。
**产出**：`lib/main.dart`、`pubspec.yaml`、`.fvmrc` 等提交 dev（或留 TODO）。

---

## Day 2 · 9/8（周二）Dart 速通

**目标**：能看懂并手写 Dart 基础，为写页面打底。

- [ ] 过一遍 Dart 要点：null-safety / 类型推断、async-await、集合与迭代、record、class 与 mixin
- [ ] 手写小练习：一个「异步加载列表数据」的命令行小 demo（不追求 UI）
- [ ] 通读现有 counter_demo 的 `main.dart`，确认能解释每一行（含 `.fromSeed`、`.center` 等新语法）

**验收**：能不看资料手写一个"异步取数 + 列表渲染"的 Dart 类。
**产出**：练习代码提交 dev（或独立练习分支，不进 main）。

---

## Day 3 · 9/9（周三）Widget 基础

**目标**：手写静态时间轴页，暂不接数据。

- [ ] 学习布局核心：Scaffold / ListView / Card / Padding / Row–Column / StatefulWidget 生命周期
- [ ] 手写静态时间轴页：日期锚点 + 图文卡片 + 心情色点 + 悬浮「+」（样式对照计划书 §5.2 时间轴首页）
- [ ] 同一页补空态（无记录时的引导文案），为 UI 走查三要素打底

**验收**：静态时间轴页在真机显示，滚动流畅、空态可见。
**产出**：`lib/features/timeline/presentation/` 静态页提交 dev。

---

## Day 4 · 9/10（周四）状态与路由

**目标**：5 Tab 空框架可切换。

- [ ] 引入 flutter_riverpod + go_router（ProviderScope / 路由表）
- [ ] 建 5 个 Tab 空壳：**① 时间轴（首页） ② 相册 ③ 学习 ④ 笔记本 ⑤ 我的**
      （Tab 命名与顺序以计划书 §5.1 为准；底部 NavigationBar 切换）
- [ ] 路由：各 Tab 可跳转占位详情页；App 启动默认进时间轴

**验收**：5 Tab 底部切换无报错，返回 / 跳转正常。
**产出**：`lib/app/`（入口、路由、主题骨架）+ 5 个 feature 空目录提交 dev。

---

## Day 5 · 9/11（周五）数据层 demo

**目标**：Drift 建表 / DAO / Stream 查询跑通，用 DEVELOPMENT.md §4.3 修正版表结构。

- [ ] 引入 drift + drift_flutter + build_runner，`pubspec.yaml` 锁版本
- [ ] 按 §4.3 建核心表（entries / notebooks / tags / assets / todos / settings_kv），统一携带
      `uuid / created_at / updated_at / version / deleted` 五字段；`hash_sha256`、`completed_at`、`metadata_json` 按修正并入
- [ ] DAO 写 / 读 / Stream 查询 demo：插入一条记录 → UI 实时出现（StreamBuilder）
- [ ] 确认 `*.g.dart` 生成并提交入库（生成文件必须入库）

**验收**：重启 App 数据仍在（持久化）；字段名与 §4.3 一致。
**产出**：`lib/core/db/`（tables / daos / database.g.dart）+ 一个 Stream 驱动的 demo 页提交 dev。

---

## Day 6 · 9/12（周六）设计走查 + 仓库基建

**目标**：5 主页面线框定稿；仓库补齐 CHANGELOG / Issue 模板 / CI。

- [ ] 纸笔或 Figma 画 5 个主页面线框（时间轴 / 相册 / 学习 / 笔记本 / 我的 + 编辑器页）
- [ ] 自走查 3 遍（对照计划书 §5.2 关键页面清单：核心元素是否齐、空态 / 加载态 / 错误态是否有位）
- [ ] GitHub 建 Issue 模板（背景 / 验收标准 / ≤2h 任务拆分，参照 DEVELOPMENT.md §5.1）
- [ ] 建 `CHANGELOG.md`（Keep a Changelog 格式，首个条目 `[0.1.0] - unreleased`）
- [ ] 建 CI workflow：push / PR 跑 `flutter analyze` + `flutter test`（参照 §5.2 / §5.4）

**验收**：线框走查 3 遍无重大缺项；仓库 Push 后 Actions 首次跑绿（或已提交待触发）。
**产出**：`.github/`（issue template + workflows）、`CHANGELOG.md` 提交 dev。

---

## Day 7 · 9/13（周日）收尾冲刺

**目标**：空壳工程达到可发布基线，阶段 0 闭环。

- [ ] 全仓 `flutter analyze` 0 警告；`flutter test` 通过（补 1 个冒烟 Widget 测试）
- [ ] 周日可演示构建：`flutter build apk --debug` 装真机，把 5 Tab 完整走一遍
- [ ] dev 分支整理提交（Conventional Commits，单次提交一件事），PR 合入 main
- [ ] 写第 1 周开发日志（做了什么 / 卡点 / 下周计划），存 `docs/devlog-w1.md`
- [ ] 回顾 ideas.md：阶段 0 冒出但没做的想法记入，不插队

**验收**：main 上有可运行空壳 + 完整文档；CHANGELOG 含 `[0.1.0] - unreleased` 条目。
**产出**：PR 合 main、`docs/devlog-w1.md`。（M1 的 `v0.1.0-alpha` tag 在 W5 打，本阶段不打 tag）

---

## 开工前通读一遍

- DEVELOPMENT.md §4 架构与数据模型（表结构写死在这里，Day 5 直接用）
- DEVELOPMENT.md §5 开发规范（Git / 代码 / 测试 / 工具链）
- 计划书 §5.1 信息架构（5 Tab 定义）、§5.2 关键页面清单（线框依据）
