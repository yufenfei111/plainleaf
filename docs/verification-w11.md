# 素页 PlainLeaf · W11（W10 收尾 + 体验与信息架构第一期）交付与自查报告

> 日期：2026-09-23　基线：`v0.2.0+2`（W10 完成态，81/81 用例绿，`dart analyze --fatal-infos` 0 issue）
> 范围：5 个子代理并行改造 12 个文件 + 新增 7 个文件（+1274 / −149 行）
> 主题：**轻量、丝滑、克制** —— 不堆视觉装饰，只做让常用路径更快更直觉的改动

---

## 一、先说环境与「自查口径」（这条决定了下面每一条结论的分量）

本次会话里 Windows 出现了 **创建子进程管道被拦** 的情况：任何 `Process.start/run` 挂 `stdout/stdin`
都返回 `ERROR_PIPE_BUSY(231)`，表现为

```
CreateFile failed 231 (所有的管道范例都在使用中。)
ProcessException: … Command: git --version
```

实测结论（对本会话成立）：

| 手段 | 结果 | 原因 |
|---|---|---|
| `flutter test` | ❌ 崩在启动阶段 | flutter tool 派生 git / flutter_tester 需要管道 |
| `dart analyze` | ❌ 崩 | dartdev 要派生 analysis_server AOT |
| `flutter build apk` | ❌ 同上 | Gradle/java 同样要管道 |
| `python subprocess(capture_output=True)` | ✅ | CPython 走匿名管道，不受影响 |
| `node spawnSync(stdio:'ignore','pipe','pipe')` | ✅ | 只要不给子进程建 **stdin** 管道就行 |
| `dart run <脚本>`（脚本自己不派生） | ✅ | 不派生子进程 |

因此本阶段的自动化测试验证**没有跑起来**，静态检查改用了临时加的进程内分析器
`tool/inprocess_analyze.dart`（直接 `import package:analyzer`，在同进程内跑，不派生任何子进程）。

**它覆盖了什么 / 没覆盖什么**（已用反向用例校验过）：

| 校验项 | inprocess_analyze | 真实 `flutter analyze` |
|---|---|---|
| 编译错误 / 未定义符号 / 类型不匹配 | ✅ 已验证可抓 | ✅ |
| lint（含 CI 口径 `--fatal-infos` 的 info 级） | ❌ 抓不到 | ✅ |
| 运行时行为（Widget 用例、真机） | ❌ | ❌（只影响 CI） |

> 结论：**本报告里「通过」= 通过类型/编译级检查 + 人工代码走查，不等于跑过测试。**
> 团队在正常环境（或 CI）必须先按 §6 的命令补跑一遍再合 dev。

---

## 二、本阶段交付清单

| # | 交付项 | 归属 | 主要文件 |
|---|---|---|---|
| 1 | **首屏主题预读**（消除启动闪屏） | B | `lib/main.dart`、`lib/app/providers.dart` |
| 2 | **共享骨架屏组件**（替代转圈） | 主代理 | `lib/shared/widgets/skeleton.dart`（新增） |
| 3 | **时间轴分页续拉**（首屏 40 + 滚动续拉） | A | timeline providers / page |
| 4 | **时间轴下拉刷新** | A | timeline page |
| 5 | **时间轴 loading 换骨架屏** | A | timeline page |
| 6 | **筛选交互重做**（筛选入口 + 底部弹层） | A | timeline page |
| 7 | **学习 Tab 待办录入**（输入框 / 分组 / 软删撤销 / 空态） | C | `lib/features/study/**`、`lib/core/db/daos/todos_dao.dart` |
| 8 | **编辑器打磨**（字数统计 / 退出确认 / 长按看大图） | D | `lib/features/editor/presentation/editor_page.dart` |
| 9 | **相册全屏浏览**（翻页 + 缩放，取代「跳详情」过渡方案） | E | `lib/features/gallery/presentation/photo_viewer_page.dart`（新增） |
| 10 | **静态检查兜底工具** | 主代理 | `tool/inprocess_analyze.dart`（新增） |

未交付（有意推迟，见 §5）：列表增删动画（AnimatedList）、底部导航 Tab 合并、**任何新第三方依赖**。

---

## 三、依赖选型：一个都没加，理由如下

调研过的候选（数据取自 pub.dev API，`pub.dev/api/packages/<name>`）：

| 候选 | 体积/依赖 | 维护状态 | 结论与理由 |
|---|---|---|---|
| `shimmer` 4.0.0 | 自身很轻，但 4.0.0 起依赖 `material_ui ^1.0.1`（又一整个 UI 体系） | 活跃（2026-08-21 发布） | **不用**。它做的唯一一件事是「循环微光动画」，而这恰好是我们的红线：循环动画会让 `flutter test` 的 `pumpAndSettle` 永远等不到静止，把整套 Widget 测试挂死；并且项目基调是「动画克制」。用不到 100 行自写静态骨架代替 |
| `photo_view` 0.15.0 | 零第三方运行时依赖（仅 flutter SDK） | **停更：最后发布 2024-04-17，距今 2 年+**，且 sdk 约束写到 `<4.0.0` | **不用**。Flutter 自带的 `InteractiveViewer` 已覆盖「双指缩放 + 双击缩放 + 边界夹取」，且能与我们自写的 `PageView` 手势层按需组合；引入一个两年没动、且自带一套 controller 体系的包，收益抵不上维护风险 |
| `flutter_native_splash` | 会改 Android/iOS 原生配置 | 活跃 | **不用**。本次的「闪」是 **主题/字号/强调色恢复导致的二帧重绘**，不是缺少启动背景图——加原生启动图只会把闪点从「白屏后重绘」变成「品牌图后重绘」 |
| `build_runner` 重新生成代码 | — | — | **没触发**。时间轴分页复用了 `EntriesDao.watchTimeline` 已存在的 `limit` 参数；todos 新增方法全部是手写 Drift DSL 普通方法（`@DriftAccessor` 的注解方法才需要代码生成） |

净新增第三方依赖：**0 个**。新增投递量与 APK 体积影响：无。

---

## 四、关键设计取舍（每条都是「为什么这么做」，避免走回头路）

1. **分页用「取前 N 条」而不是 offset**：时间轴排序是「置顶优先 + 日期倒序」，用户随时会新写一条插到队首，
   offset 分页第二页必然错位/重复；`limit +40` 每次重取前 N 条，插入天然安全。
2. **hasMore = 「返回条数 >= limit」**：不再为「还有没有」单发一次 count 查询 —— 分页就是为了省查询。
3. **续拉时不用 `AsyncValue.when`**：Riverpod 重载时是 `AsyncLoading(hasValue:true)`，`when` 会走 loading 分支，
   把用户的滚动位置推翻；改成按 `state.valueOrNull` 先分流（与 W10 修相册续拉是同一个教训）。
4. **骨架屏不加呼吸动画**：既是「动画克制」，也避免 `pumpAndSettle` 死等。
5. **筛选从横向 chip 条改成入口 + 底部弹层**：笔记本只会越建越多，横向条里可见的永远只有两三个；
   弹层里改的是草稿，「查看结果」才提交 —— 否则每点一个 chip 都带着新 where 重查一次流。
6. **筛选条件变更时把 limit 复位 40**：避免带着续拉出来的大 limit 在新条件上白拉几十条。
7. **主题预读放在 `runApp` 前、复用同一个 db 实例**：只有三次 settings_kv 主键等值查询，库已打开，无额外 IO；
   失败一律降级为空快照（"读不到偏好"绝不能升级成"启动不起来"）。
8. **快照字段全可空 + 默认实现返回 empty**：没有注入时（= 所有既有 Widget 测试）行为与旧版一字不差，不回归。
9. **退出确认只在 `dirty && !empty && !bypass` 时拦**（抽成纯函数 `shouldConfirmExit`）：
   空记录退出会被回收（不该拦）、已落库再加拦是打扰、点「完成」发布必须直接放行 —— 否则发布流程被自己挡死。
10. **发布/确认退出后置 `_bypassExitConfirm` 且 `addPostFrameCallback` 里再 pop**：
    `PopScope.canPop` 是在 `didUpdateWidget` 里同步给 `canPopNotifier` 的，不重建就还是旧值。
11. **对话框收尾只用对话框自己的 context**（W10 结论复用）：页面级 `context.pop()` 会把整页弹掉。
12. **待办删除走软删**（`deleted=1` + version+1），`confirmDismiss` 里先写库成功才真滑走：杜绝「UI 删了库里还在」。
13. **全屏看图三级渐进 + 每级都带 `cacheWidth`**（thumb→medium→原图，只双击/放大后才升到原图，缩放夹 1×–4×）：
    全屏不是「放任解码原图」的豁免区。
14. **相册用手写 `Listener` 判定手势方向**：`InteractiveViewer` 的 scale 识别器在命中路径更深层，
    会先赢走已关闭的竞技场，导致 PageView 翻不动。
15. **相册路由用 `Navigator.push(rootNavigator:true)` 自建 200ms 淡入**：不改 `router.dart`（合并型高危文件），
    且能盖住底部 Tab。

---

## 五、自查结果（逐项）

### 5.1 完整性

| 项 | 结果 | 备注 |
|---|---|---|
| 10 项交付是否都在代码里 | ✅ | `git status` 逐个核对（见 §7 改动清单） |
| 三态（loading / empty / error）是否齐全 | ✅ | 时间轴、相册、学习页均有骨架屏 + 空态 + 错误态；学习页错误态复用 `EmptyState` |
| 是否引入循环动画 | ✅ 无 | 全仓 grep `repeat(` / `AnimationController` 仅相册两个已 dispose 的控制器 |
| 是否越过分层红线（页面直接用 DAO） | ✅ 无 | 新增写入均经 domain 接口 + Actions 门面 |
| 是否破坏软删/数据红线 | ✅ 无 | 待办软删 + version 递增 + uuid 在 DAO 生成；无表结构变更（无 Migration） |
| 是否引入第三方依赖 | ✅ 0 个 | 见 §3 |
| 是否动到 *.g.dart / 需要 build_runner | ✅ 无 | 新增查询全部手写 Drift DSL |

### 5.2 一致性

| 项 | 结果 | 说明 |
|---|---|---|
| 颜色是否写死 | ✅ | 新代码全部取 `Theme.of(context).colorScheme / textTheme`（相册用 `scrim` 做深底） |
| 触控目标 ≥44dp | ✅ | 筛选入口、关闭按钮显式 44dp |
| 过渡是否统一 200ms | ✅ | 相册淡入 200ms / 淡出 160ms，与 `app/transitions.dart` 同口径 |
| 命名与注释语言 | ✅ | 中文注释讲「为什么」，无下划线开头局部变量（CI `--fatal-infos` 口径） |
| 既有用例兼容性（人工核对） | ⚠️ 见下 | 未跑测试，逐条走的静态依赖分析 |

**对既有测试的兼容性分析**（这是本次最大的未验证风险，逐条核对过源码）：

- `smoke_test`：切换 Tab 用 `find.text('学习'/'笔记本')`（导航未改 ✅）；学习页勾选仍用 `Checkbox.first`
  （`_TodoTile` 仍是 `CheckboxListTile` ✅）；发布流程 `TextField.first` → 「完成」按钮 ✅
  （注意：D 新加了 PopScope，`_publish` 里已置 bypass；但「PopScope 到底会不会拦到 go_router 的返回」
  这条只能实跑确认）。
- `w8_timeline_empty_test`：直接改 `timelineFilterProvider` 后期望空态 + 「清除筛选」—— 空态逻辑保留 ✅，
  但原先验证入口是 `_FilterBar` 里的 `ActionChip('清除 N')`，**现在入口改成了弹层，这条链路需要实跑确认**。
- `w10_fixes_test` / `autosave_test` / `editor_fallback_test`：依赖 `TextField.first` 与 quill 页面结构，
  D 未新增 TextField ✅；新增了 `Document.changes` 订阅，**正文现在也会随防抖落库**（行为变化，属预期，但要实跑）。
- `w10_fixes_test` 的相册续拉用例依赖 `GalleryRepository.page` 与 `GalleryAsset` 构造签名 —— E 未改这两个签名 ✅。

### 5.3 性能

| 项 | 预期 | 依据 |
|---|---|---|
| 时间轴首帧构建量 | ↓ 至少一半（100 → 40 条 → 月/日/卡三类行随之减少） | 静态推导，**未做真机帧率实测** |
| 首屏重绘次数 | ↓ 1 次（去掉「默认主题 → 恢复主题」） | 代码路径推导，**未做 `--trace-startup` 实测** |
| 全屏看图内存 | 受控（逐级 + cacheWidth 夹取 + 缩放夹 1×–4×） | 与 W10 详情页同口径 |
| 已知代价 | learning page 多了 composer + 分组两段表头；每页多一行 footer 提示 | 可忽略 |

### 5.4 异常边界（人工核对）

- 配置读取失败 → 空快照降级 ✅；缩略图加载失败 → 破图图标（原逻辑保留）✅
- 续拉失败 → 保留已展示数据 + 底部重试（W10 已有）✅；下拉刷新失败 → 指示器照常收起，错误交错误态 ✅
- 空白待办 → DAO trim 后返回 0，UI 出轻提示，不落库 ✅
- 软删失败 → 行会弹回（Dismissible 语义）✅
- 图片全屏：`mediumPath` 缺失回退原图，`cacheWidth` 夹 `[1, 4096]` 避免「测量为 0」 ✅
- 编辑器：无内容退出不拦（会被回收）、发布不拦、确认后退出口径统一 ✅

### 5.5 遗留问题（未做 / 做不了，及原因）

| # | 遗留 | 原因 |
|---|---|---|
| 1 | **所有新增用例（test/w11_*.dart 共 22 例）未实跑** | 本机派生子进程被拦（§1）。静态分析过了 ≠ 用例过了，这条风险最高 |
| 2 | lint 未被本地校验（`--fatal-infos` 口径） | 进程内分析器不套用 `analysis_options.yaml` 的 include；靠编码自律 + CI 兜底 |
| 3 | 列表增删动画（AnimatedList）没做 | 无测试可跑时做手算 diff 的动画风险高，收益又偏观感，排到下一轮 |
| 4 | 底部导航 Tab 合并（笔记本 Tab 的去留）没动 | `smoke_test` 里有切 Tab 断言，且属于信息架构级改动，**应等实机能跑测试时再做**；建议一并决策 |
| 5 | 真机帧率 / 冷启动耗时没有实测 | 需要能构建的环境（`flutter run --profile` / `--trace-startup`） |
| 6 | 相册全屏的双击/双指手感、翻页阈值未调 | 经验值，必须真机调 |
| 7 | 已完成待办不支持删除 | 学习页目前只做「取消勾选」；删除统一到回收站方案时再处理 |
| 8 | `tool/inprocess_analyze.dart` 是环境受限时的临时兜底 | 正常环境请直接用 `flutter analyze`，本机恢复后建议删除该工具 |

---

## 六、验证步骤（拿到正常环境后按这个跑）

```bash
cd C:/Users/雨/Desktop/豆包/相册记事本项目/plainleaf

# 1) 静态检查（CI 口径：INFO 也算问题）
dart analyze --fatal-infos lib test

# 2) 用例（本机必须去代理，否则 flutter_tester 的本地 WebSocket 会被劫持）
env -u HTTP_PROXY -u http_proxy -u HTTPS_PROXY -u https_proxy flutter test

# 3) 只看本阶段新增的 5 个文件
flutter test test/w11_timeline_test.dart test/w11_startup_test.dart \
             test/w11_study_test.dart  test/w11_editor_test.dart test/w11_gallery_test.dart

# 4) 构建 + 真机手测清单
flutter build apk --debug
flutter run --profile   # DevTools 抓时间轴/相册滑动帧时间，目标 p95 < 16ms
flutter run --trace-startup
```

**手测点（自动化覆盖不到的部分）**：
1. 冷启动是否有「主题闪一下」；2. 时间轴下滑能否自然续拉、到底是否提示「已经到底了」；
3. 下拉刷新动画是否完整（不是一闪而过）；4. 筛选弹层：多选后「查看结果」是否立刻生效且回到首屏；
5. 学习页录入回车后是否清空并置顶；左滑删除后 SnackBar「撤销」是否还原；
6. 编辑器：有内容按返回是否弹确认、点「完成」是否**不弹**、字数是否随输入更新；
7. 相册：点图全屏是否盖住底部 Tab、左右翻页是否顺、双指放大后内存是否失控；
8. 深色模式 + 1.3× 大字号下以上各页是否不溢出。

---

## 七、改动清单（`git status` 核对后的实际结果）

| 文件 | 类型 | 说明 |
|---|---|---|
| `lib/main.dart` | 改 | 预读外观快照 + ProviderScope 注入 |
| `lib/app/providers.dart` | 改 | `AppearanceSnapshot` / `initialAppearanceProvider` / `readAppearanceSnapshot`；三 Controller build 优先取预读值 |
| `lib/shared/widgets/skeleton.dart` | 新增 | `SkeletonBox` / `TimelineSkeleton` / `GridSkeleton` |
| `lib/features/timeline/presentation/providers/timeline_providers.dart` | 改 | `kTimelinePageSize`、`timelineLimitProvider`、流透传 limit |
| `lib/features/timeline/presentation/timeline_page.dart` | 改 | 三态分流 / 分页续拉 / 下拉刷新 / 筛选入口与弹层 / 骨架屏 |
| `lib/features/study/**`（5 个文件） | 改 | 待办录入 + 分组 + 软删撤销 + 空态 + TodoActions |
| `lib/core/db/daos/todos_dao.dart` | 改 | 手写 `addTodoWithContent` / `softDeleteTodo` / `restoreTodo`（无代码生成） |
| `lib/features/editor/presentation/editor_page.dart` | 改 | 字数统计 / 退出确认 / 长按看大图 |
| `lib/features/gallery/presentation/gallery_page.dart` | 改 | 点图开全屏、长按保留「查看所属记录」、首屏换 GridSkeleton |
| `lib/features/gallery/presentation/photo_viewer_page.dart` | 新增 | PageView + InteractiveViewer 全屏浏览 |
| `test/w11_*.dart`（5 个） | 新增 | 22 例（**全部未实跑**） |
| `tool/inprocess_analyze.dart` | 新增 | 环境受限时的进程内静态检查兜底 |
