# 阶段 0 交接说明与进度台账（2026-09-16）

> 交付人：AI 协作开发（骨架日批次）｜接续依据：docs/DEVELOPMENT.md §三 路线表 W2 行
> 本文档 = 项目进度台账 + 交接说明；下一步可直接据此开工，无需回溯会话。

## 一、进度台账（阶段 0 · Day 1–7 全量）

| # | 任务（来源） | 状态 | 证据 |
|---|---|---|---|
| 1 | Day1 环境就绪：fvm 3.47.2 / 包名修正 / 镜像链路（§6） | ✅ 9/4 | devlog-w1 Day1 + aapt2 记录 |
| 2 | Day2–3 Dart/Widget 基础 + 静态时间轴页（§6） | ✅ 骨架日合并 | lib/features/timeline/presentation/timeline_page.dart（三态齐全） |
| 3 | Day4 Riverpod + go_router 5 Tab（§6） | ✅ | lib/app/router.dart（5 branch）/ home_page.dart |
| 4 | Day5 §4.3 Drift 建表 + DAO + Stream（§6） | ✅ | lib/core/db/tables.dart（9 表）+ database.dart（FTS5 虚表）+ 3 DAO |
| 5 | Day6 线框走查 + Issue 模板 + CHANGELOG + CI（§6） | ✅ | docs/wireframes.md + .github/* + CHANGELOG.md |
| 6 | Day7 analyze 0 警告 + test 全绿 + 日志（§6） | ✅ | analyze No issues / test +4 / devlog Day2-7 节 |
| 7 | FTS5 虚表 + searchEntryIds 助手（计划书 §7.2，超出清单最小补全） | ✅ | entries_dao.dart + db_smoke FTS 断言 |
| 8 | 可演示构建 apk --debug（checklist 周日项） | ✅ | app-debug.apk 150.1MB，aapt2 核验通过 |
| 9 | git 分批提交（Conventional Commits） | ✅ 8 commits | dev 分支 b95add2…（feat×4/test/chore/docs） |
| 10 | push dev + PR 合 main + CI 首跑（checklist） | ✅ 2026-09-16 | dev 推至 9417098；PR #17 已合并 main（e209909）；dev 与 main 双侧 CI 全绿（analyze --fatal-infos + test） |
| 11 | 真机走查 5 Tab（checklist Day7 / Day1 真机项） | ⬜ 需用户 | 需 USB 连线或安装 APK（代码侧一切就绪） |

## 二、关键决策与假设记录

| 决策 | 依据 | 影响 |
|---|---|---|
| 采纳骨架日方案（Day2-7 合并） | COMMAND-DOC 决策点 1（指挥官待拍板项，本轮按最合理假设先行） | 独立 CLI 练习以真实项目代码替代；检查表已注明 |
| 新增依赖 drift_flutter/uuid/sqlite3 | 清单缺同步五字段与跨平台连接的必需件 | 已在 pubspec 注释与 devlog 记录理由 |
| dependency_overrides 钉 path_provider_foundation 2.4.1 / android 2.2.10 | objective_c/jni native assets hook 与 3.47.2 主机测试不兼容 | Flutter 升级后应重试移除 |
| 英文路径生成通道（C:\plgen） | build_runner AOT 对中文路径失败（exit 78） | 每次改表结构都要走；迁英文仓库路径可废除此通道 |
| 详情页路由延后 W3 | 阶段 0 无编辑器，占位详情页无内容可跳 | checklist 已注明 |
| 种子数据幂等（seed_v1） | 让 5 Tab 非空壳、测试可断言 | 真实数据 W3 编辑器接入 |

## 三、接手即用：下一步操作清单

1. ~~完成推送与合并~~ **已完成（2026-09-16）**：dev 已推送，PR #17 已合并 main，dev 与 main 双侧 CI 首跑全绿。历史记录：推送一度因安全审批超时被拦，后以干净命令完成。```powershell
   cd C:\Users\雨\Desktop\豆包\相册记事本项目\plainleaf
   git push origin dev
   # GitHub 网页或 gh CLI 建 PR：dev → main，合并后 Actions 首跑（analyze --fatal-infos + test）
   ```
2. **真机走查**：安装 `build/app/outputs/flutter-apk/app-debug.apk`（或 `fvm flutter run -d <设备id>`），走查 5 Tab：时间轴种子卡片/学习页勾选待办/笔记本双空间/相册与我的空态。
3. **W2 开工**（按 DEVELOPMENT.md §三 W2 + COMMAND-DOC 学习路径）：
   - Repository 层（接口/实现分离，参考 ModuNote `lib/data/repositories/`）；
   - entries + entries_fts 事务双写落 Repository（本阶段助手已在 EntriesDao 就位）；
   - 时间轴接领域模型（替换 TimelineRowData 占位结构）。
4. **改表结构须知**：一切 schema 变更走「英文路径生成通道」（devlog 卡点 1 五步）+ Migration + 迁移测试（数据红线）。

## 四、遗留问题（阻塞项均非代码）

- ~~push/PR/CI 首跑未完成~~ 已闭环（PR #17 合并 + 双侧 CI 绿）。
- 真机走查需用户手机（唯一遗留）。
- settings_kv 五字段出入已按复核意见修复（9417098）。
- Moodiary 竞品体验（指挥文档决策点 4）未启动——属 W13 前可选项，已记录不入队。