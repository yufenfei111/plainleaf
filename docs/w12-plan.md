# 素页 PlainLeaf · W12 施工图（回忆沉淀第一期）

> 分支：`feat/w12-calendar-nav`（从 dev 切出，dev 已 fast-forward 到 W11 修复态）
> 起始基线：`flutter test` 104/104 通过、`dart analyze --fatal-infos lib test` 0 issue
> 范围来源：W11 报告 §5.5 遗留 #3/#4 + 路线图阶段 3（日记与学习）的前半

---

## 一、范围与取舍

| 做 | 入口 | 理由 |
|---|---|---|
| 底部导航 5 Tab → 4 Tab | `home_page.dart` + `router.dart` | W11 遗留 #4。笔记本本质是记录的「一个维度」，不该与「相册/学习」平级占一个 Tab |
| 时间轴列表增删动效 | `timeline_page.dart` | W11 遗留 #3。上一轮因无法跑测试而推迟，现已具备验证条件 |
| 日历回顾视图 | 新 feature `calendar` | 路线图 W10 的日历视图，是「回忆沉淀」的主入口 |
| 那年今日卡片 | 新 widget + provider | 让历史记录在时间轴上自然复现，是把「记录」变成「回顾」的最小杠杆 |
| 学习待办收尾 | `features/study/**` | W11 遗留 #7（已完成待办不能删）+ 为后续统计铺路 |

| 不做（明确推迟） | 原因 |
|---|---|
| fl_chart 等图表的统计页 | 需要新依赖，且要先有数据形状（日历密度 + 每日完成数是前置件） |
| 番茄钟 / 本地通知 | 需要新依赖 + 平台配置，属于独立一轮 |
| 真机帧率与冷启动实测 | 需要真机与 profile 构建，不阻塞本阶段合入 |

---

## 二、文件所有权（并行开发互斥表）

| 代理 | 准改/新建 | 禁碰 |
|---|---|---|
| **A `nav-tab`** | `lib/app/home_page.dart`、`lib/app/router.dart`（仅：`/notebooks` 提升为顶层 GoRoute）、`lib/features/timeline/presentation/timeline_page.dart`、`test/smoke_test.dart` | 其余一切 |
| **B `memory-cal`** | 新建 `lib/features/calendar/**`、`lib/features/timeline/presentation/widgets/on_this_day_card.dart`、`.../providers/on_this_day_provider.dart`、`test/w12_calendar_test.dart`、`test/w12_onthisday_test.dart` | `lib/app/**`、`lib/core/db/**`、timeline_page.dart |
| **C `study-todo`** | `lib/features/study/**`、`test/w12_study_test.dart` | `lib/core/db/**`、`lib/app/**` |
| **主代理** | `lib/core/db/daos/entries_dao.dart`（冻结契约）、`lib/app/router.dart`（加 `/calendar` 路由）、`timeline_page.dart`（挂 OnThisDayCard）、文档 | 子代理地盘内不做重叠改动 |

**合并型高危文件 `lib/app/router.dart` 的写者只有一个**：A 负责摘 branch，主代理负责加 `/calendar`，**串行**，不并行。

---

## 三、冻结的数据层契约（主代理实现，已验证可编译）

```dart
// lib/core/db/daos/entries_dao.dart
Stream<List<EntryDateHit>> watchEntryDates(DateTime from, DateTime to);
Stream<List<TimelineRow>> watchOnThisDay(DateTime today, {int limit = 3});
```

设计取舍（不走回头路）：

1. **日历只取轻量行**（`id` + `entry_date`）。整行会带上 `contentDelta` 这类大字段，
   日历一次看一整月，白读的代价被放大。
2. **聚合放在 Dart 层，不写 SQLite 日期函数**。`strftime` 这类函数跨 engine 行为不一致，
   写错函数名要等运行时才炸；个人库量级下 Dart 聚合是常数级开销，换确定性划算。
3. **复用 `watchTimeline` 的行组装逻辑**（抽成 `_rowsFor`），那年今日需要首图与笔记本，
   与其复制一遍 map/归并，不如共用——W12 起 DAO 有了第二个消费方。
4. **那年今日用「今年之前」的年份范围做粗筛，再在 Dart 比月日**，同样是为了不碰日期函数。

---

## 四、验收标准（合入 dev 的前置条件）

```bash
# 注意：本机命令执行环境禁止被执行的进程再派生子进程（CreateFile failed 231），
# 必须用 Windows 计划任务跑，结果落到文件再读（见 docs/verification-w11.md §六点五）
```

| 项 | 标准 |
|---|---|
| `flutter test` | 全部通过，且用例数 **≥104**（不许为了绿而删断言） |
| `dart analyze --fatal-infos lib test` | **0 issue**（CI 口径，info 级也算失败） |
| 既有行为回归 | 分页续拉 / 下拉刷新 / 筛选弹层 / 月分组 / 置顶组 / 三态 / 编辑器自动保存 / 备份恢复 全部不变 |
| 新功能三态 | 日历与那年今日各自的加载 / 空 / 错误态齐全 |
| 动效 | 一次性、≤250ms，无常驻 ticker（`pumpAndSettle` 不得被挂死） |

---

## 五、交付物

- 代码：上表「准改/新建」全部文件
- 测试：`test/w12_*.dart`
- 文档：`docs/verification-w12.md`（验收自查报告）、`docs/devlog-w12.md`（开发日志）、`CHANGELOG.md` 条目
- 提交：`feat:` 功能提交 + `docs:` 文档提交，Conventional Commits

---

## 六、已知风险

1. **`router.dart` 与 `home_page.dart` 必须同时改对**（branch 数 == destinations 数），
   中间态会运行时报错——由主代理在集成时确认两者一致。
2. **`smoke_test` 是导航改动的守门人**，改动后必须实跑，不能只看代码。
3. **动效与分页共存**是本期最易踩坑处：`SliverAnimatedList` 的初始项数必须与首屏数据一致，
   否则首屏会「补动画」。主代理实测时优先验证这一条。
