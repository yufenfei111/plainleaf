# W9 开发日志 · 主题系统 + 设置 +（可选）Markdown 导入（2026-09-22）

对应：DEVELOPMENT.md §三 W9（主题系统+设置+可选 Markdown 导入），及 §6 路线图 W9 行（第 60 行）。
W9 仍属阶段 2（W6–W9），目标 M2 `v0.2.0`。Markdown 导入是 MoSCoW 的 **Should 级可选项**
（DEVELOPMENT.md 第 25 行已标注），砍掉不影响里程碑——本期把它做成了"粘贴文本导入"的最小实现。

GitHub：W9 由主代理编排，三名功能子代理并行（共享层冻结契约 + 设置页外观 + Markdown 导入），
另有一名**文档子代理（即本文作者）只写 Markdown、不碰任何 `.dart`、不跑 flutter/dart 命令**。
未单独开 issue（功能归属路线图 W9 行）。

## 〇、分工与文件所有权（为什么要这么切）

本期三部分彼此依赖弱、可并行。主代理先把**共享层契约冻结并先合入**
（`SettingsStore` / 三个 Provider / `AppTheme` / `PlainLeafApp` 接好线），子代理只在契约之上写实现，
路径互不重叠，最后由主代理做集成合并与路由注册。

| 子代理 | 独占路径 | 说明 |
|---|---|---|
| 主代理 | `lib/core/db/settings_store.dart`、`lib/app/providers.dart`、`lib/app/theme.dart`、`lib/main.dart` | 先落共享层契约（已冻结、过静态检查），再统一收口 |
| 子代理 B | `lib/features/settings/presentation/settings_page.dart`（外观卡片） | 强依赖三个 Provider，只读不改共享层 |
| 子代理 C | `lib/features/importer/**`（domain/data/presentation + `test/`） | 纯 Markdown 解析与落库，零 Flutter 依赖的解析器便于单测 |
| 文档子代理 | `docs/devlog-w9.md`、`docs/verification-w9.md` | 只写文档，不改动任何代码、不执行 flutter/dart |

为什么这么做：并行最大风险是"互踩"。主代理先把 `SettingKeys`、三个 Notifier 的读写契约、
`AppTheme` 的 `light/dark({Color? seed})` 接口定死，子代理只消费，避免后期大规模返工。

## 一、共享层（A，主代理）

### ① `SettingsStore`（`lib/core/db/settings_store.dart`）
- 读写 `settings_kv` 表（表定义见 `lib/core/db/tables.dart:155`，已在 `@DriftDatabase(tables:[...])`
  列表内，`lib/core/db/database.dart:25`）。暴露 `watchString / readString / writeString` 三个方法；
  `writeString` 是 upsert，value 为 null 时**软删**（`deleted` 置位），遵循 §4.3 数据红线。
- 键名常量集中在 `SettingKeys`：`themeMode` / `textScale` / `accentSeed`，避免魔法字符串散落。
- **两个关键取舍**（务必记下来）：
  1. **主题/字体这类配置必须落 `settings_kv`，不进 `shared_preferences`**——
     DEVELOPMENT.md 第 27 行硬约定：需要同步/备份的配置（主题、字体、备份计划）→ `settings_kv`；
     纯设备本地偏好 → `shared_preferences`。主题/字体要跟着 `.plbk` 备份包走，所以只能进库。
  2. **故意不写成 `@DriftAccessor`**——`SettingsKv` 早在 `@DriftDatabase(tables:[...])` 里，
     生成代码已暴露 `db.settingsKv` 这个 TableInfo（`database.g.dart` 内）。直接
     `db.select(_db.settingsKv) / into(_db.settingsKv) / update(_db.settingsKv)` 即可，
     **避免为了一个 CRUD 跑一次 build_runner 把全量 `.g.dart` 重新生成**（那才是真正的风险源）。

### ② 三个 NotifierProvider（`lib/app/providers.dart`）
- `themeModeProvider`（`ThemeModeController`）：默认 `ThemeMode.system`；`set()` 立即改 state 并异步落库。
- `textScaleProvider`（`TextScaleController`）：`static const options = [0.85, 1.0, 1.15, 1.3]`，默认 `1.0`。
- `accentSeedProvider`（`AccentSeedController`）：存 ARGB32（如 `0xFF4E9B8F`），默认兜底 `AppTheme.primary.toARGB32()`。
- 三者都用 Notifier 而非 StateProvider：把"改状态 + 落盘"收在一处，页面不会出现"改了状态忘记存"。
- **`build()` 同步返回默认值，`_restore()` 异步读库后回写 state**；读/写失败的兜底全部 `catch`
  的是 **`on Object`**（不是 `on Exception`）——disposed 后写 `state` 抛的是 `StateError`，属于 `Error`
  不是 `Exception`，只 `on Exception` 接不住（详见 §四③）。

### ③ `AppTheme`（`lib/app/theme.dart`）
- 新增 `AccentPreset`（名称 + 种子色）与 5 个预设：**青竹 / 黛蓝 / 陶土 / 藤黄 / 墨紫**
  （`AppTheme.accents`）。
- `light({Color? seed})` / `dark({Color? seed})`：用 `ColorScheme.fromSeed(seedColor: seed ?? primary)`
  换主色；FAB 配色改为跟随 `scheme.primary`（`floatingActionButtonTheme.backgroundColor`）而非写死默认主色。
- **明确决定不引入 flex_color_scheme**：原计划 W9 要接入，但只做"换主色"一件事，
  `ColorScheme.fromSeed` 换 seed 足够，引入重量级依赖整体替换调色实现收益/风险比更低。

### ④ `PlainLeafApp`（`lib/main.dart`）
- 用 `Consumer` 读三个 Provider（主题模式 / 强调色 seed / 字体缩放），改一处整 App 立即生效。
- 字体缩放走 `MediaQuery.copyWith(textScaler: TextScaler.linear(scale))`——
  **`textScaleFactor` 已废弃**，必须用 `TextScaler`（详见 §四④）。
- **保留 `const` 构造**（已有测试大量使用 `const PlainLeafApp(...)`），为此 `build` 里用 `Consumer`
  而非把 `PlainLeafApp` 改成 `ConsumerWidget`；新增可选 `themeMode` 参数供测试注入（默认跟随 Provider）。

## 二、设置页外观分组（B，子代理）

`lib/features/settings/presentation/settings_page.dart` 顶部（备份分组之前）新增「外观」卡片
（`_appearanceCard`），含三块：

- **主题模式**：`SegmentedButton<ThemeMode>` 三选一（跟随系统 / 浅色 / 深色），选中态比 RadioListTile 更紧凑。
- **字体缩放**：`SegmentedButton<double>` 四档，标签用口语「更小 / 标准 / 较大 / 超大」而非裸数字
  （`labels` 映射 `0.85→更小` `1.0→标准` `1.15→较大` `1.3→超大`），避免暴露实现细节；超出映射才回退 `xx%`。
- **强调色**：`Wrap` 横排 5 个预设色块（`_accentSwatch`）；选中态的描边与对勾取自 `Theme`
  （`scheme.primary` / `scheme.surface`），只有色块本体用预设色。

原有备份 / 导出 / 搜索 / 应用锁 / 关于等入口**未破坏**，且新增了「导入 Markdown（.md）」入口
（`onTap: () => context.push('/import')`，`settings_page.dart:49`）。

## 三、Markdown 导入（C，子代理，Should 级可选项）

新建 `lib/features/importer/`，分层清晰、解析器零 Flutter 依赖：

- **`domain/markdown_importer.dart`**：纯 Dart 解析器（只 `import` `timeline_entry`，**不 import Flutter**），
  输出 `List<ParsedEntry>`。能原样吃回本应用 W5 的 Markdown 导出格式
  （`# 标题` + `> 日期 ｜ 类型 ｜ 心情: x` + 正文，多条以 `---` 分隔）。
- **`data/markdown_import_service.dart`**：逐条 `repo.saveEntry`，**单条失败不中断整批**（记 `lastError` 继续）；
  仅当"解析出条目但全部写入失败"才包成 `DatabaseException` 上抛。
- **`presentation/markdown_import_page.dart`**：粘贴文本导入页（`TextField` + 「开始导入」按钮），
  落库经由 `timelineRepositoryProvider`，页面不直接碰 DAO/文件。
- **`test/w9_import_test.dart`**（位于 `test/`，沿用 `PlainLeafApp` + 注入 `GoRouter`）：5 例——
  ① 单条（头信息识别 + Markdown 标记剥除）② 多条 `---` 分隔 ③ 无标题回退 + 空/空白输入返回空列表
  ④ 内存库落库后可在时间轴查到 ⑤ 页面渲染输入框与按钮。

已知取舍（写进日志，避免后人误以为是 bug）：
1. **故意不支持正文内的 `---` 水平分隔线**：单独成行的 `---` 一律当作多条记录分隔符
   （`_splitBlocks`），正文里想画分隔线会被切条。
2. **不硬造 quill Delta**：`contentDelta` 留空串（依赖 W8 详情页自动降级渲染 `plainText`）。
3. **头信息识别不到时**：类型默认 `note`、日期为 `null`、心情为 `null`。

> 注：W5 导出格式里心情写作 `心情: x`（带值），导入端 `_applyToken` 能正确解析；
> 纯裸值 `---` 分隔块若无头信息则回落默认。_round-trip 自洽。

## 四、踩坑章节

### ① settings_kv vs shared_preferences 的硬约定（A，主代理）
主题/字体是要跟着 `.plbk` 备份包走的，DEVELOPMENT.md 第 27 行明令"需同步配置→settings_kv；
设备本地偏好→shared_preferences"。若图省事扔进 `shared_preferences`，备份恢复后主题会丢、
且违反数据红线约定。本期严格走 `settings_kv` 并加注释固化理由。

### ② 不跑 build_runner 的技巧：`SettingsKv` 已在 `@DriftDatabase` 内（A，主代理）
`SettingsKv` 早在数据库类的 `tables:[...]` 列表里，生成代码已暴露 `db.settingsKv` 这个 TableInfo。
因此完全不需要写 `@DriftAccessor` 再跑一次 `build_runner`——直接 `db.select/into/update` 即可。
这是并行窗口里避免"重生成全量 `.g.dart` 触发别人的编译"的关键动作，也是 W9 零表结构变更、
零新 `.g.dart` 的根因（schemaVersion 仍是 2，无需新 Migration）。

### ③ `on Object` 才能接住 Riverpod 的 StateError（A，主代理）
三个 Notifier 的 `_restore()` / `set()` 都 `catch on Object` 而非 `on Exception`。原因：
Notifier 在组件 disposed 之后异步回写 `state` 会抛 **`StateError`**，而 `StateError` 是 `Error`
不是 `Exception`，`on Exception` 接不住，会直接变成未捕获异常把启动/切换流程打断。
读库失败（库未就绪）同理兜底回落默认，绝不影响启动。

### ④ `textScaleFactor` 已废弃 → 必须用 `TextScaler`（A，主代理）
字体缩放不能再用 `MediaQueryData.textScaleFactor`（已废弃、将来移除）。改走
`MediaQuery.copyWith(textScaler: TextScaler.linear(scale))`，Flutter 会用 `TextScaler` 统一计算。
写错成 `textScaleFactor` 编译期就会告警（违反 `flutter analyze` 0 警告红线）。

### ⑤（读代码发现）`theme.dart` 第 6 行残留旧注释与最终决定矛盾
`lib/app/theme.dart:6` 仍写着「W9 主题系统阶段接入 flex_color_scheme，只替换本文件内部实现，
对外 API 不变」——但本期**明确决定不引入** flex_color_scheme（见 23–26 行新注释）。
旧注释是阶段 0 计划书的遗留表述，与新决策相反，属于注释漂移。建议后续清理第 6 行旧注释，
以免误导"将来要换成 flex_color_scheme"的判断。

### ⑥（读代码发现）强调色仅重着色"主色点缀"，不重着色 AppBar 背景
`AppTheme.light/dark` 里 `appBarTheme.backgroundColor` 写死为 `paper` / `paperDark`（纸张底），
强调色只通过 `ColorScheme.fromSeed(seed)` 改变 `colorScheme.primary`（进而作用于 FAB、
`FilledButton`、选中描边、对勾等主色点缀）。因此"强调色全局生效"准确说是**主色点缀生效**，
AppBar 背景仍是纸张色、不变色。验证/文档里写"含 AppBar"略有夸大——强调色影响的是 AppBar 前景
（图标/文字取 `colorScheme.onSurface`/primary 的细微变化），而非 AppBar 底色。

### ⑦（读代码发现）三件套默认值是"异步恢复"，冷启动有一帧回落默认
`build()` 同步返回默认值（system / 1.0 / primary），`_restore()` 异步读库后再 `state =` 回写。
即：冷启动到 restore 完成前的那一帧，会用默认主题渲染、随后可能闪一下跳到存储值；
且"重启后是否记得"完全取决于 `_restore()` 成功——而 `_restore()` 用 `on Object` 吞错，
吞错后**静默回落默认**而非报错。这正是 verification-w9 把"重启后仍生效"列为重点的根因：
一旦持久化路径异常，现象是"主题没记住、默默变回默认"，不会崩但难察觉。

## 五、测试情况

M9 新增一个套件（位于 `test/`，沿用 `PlainLeafApp` + 注入 `GoRouter` 隔离路由）：

| 套件 | 用例 | 覆盖点 |
|---|---|---|
| `w9_import_test.dart` | 5 例（①②③④⑤） | 单条头信息+标记剥除；`---` 多分隔；无标题回退+空输入不抛；内存库落库后时间轴可查；页面渲染输入框与按钮 |

> 说明：按子代理硬约束，本文档作者**未运行 `flutter analyze` / `flutter test`**
> （避免与并行的功能子代理测试抢 `.dart_tool` 锁）。最终 pass/fail、覆盖率与
> `flutter analyze` 结论由并行测试子代理汇总；上表仅列已就绪套件与覆盖点，已逐文件核对
> 解析器/服务/页面断言与代码一致。W8 既有套件须保持全绿（回归）。

## 六、遗留与下一步

1. **（读代码已证，与原始描述不符）`/import` 路由与设置页入口其实已接好，不是"待主代理合并时补上"。**
   `lib/app/router.dart:36-39` 已注册 `GoRoute(path: '/import', ...)`，且
   `settings_page.dart:49` 已有「导入 Markdown（.md）」入口 `context.push('/import')`。
   原始分工描述写"路由与设置页入口由主代理合并时补上"，但工作树里二者均在位——集成已闭合，
   无功能性接缝缺口（与 W8 的 `/detail` 缺口不同）。
2. 主题/字体/强调色的**真机持久化**是本期最易翻车点，须按 verification-w9 逐项走查
   （尤其"重启后仍生效"，见 §四⑦）。
3. `theme.dart:6` 残留旧注释待清理（见 §四⑤）。
4. Markdown 导入本期只做"粘贴文本"，文件选择器（避免引入额外权限/依赖）排到"有 buffer 再做"；
   正文内 `---` 不支持（见 §三取舍①）。
5. iOS 本期不在范围：`ios/Runner/Info.plist` 已读代码确认缺 `NSCameraUsageDescription` /
   `NSPhotoLibraryUsageDescription`（第 70 行止无任何相机/相册用途描述），做 iOS 前必须先补，
   否则相机/相册权限请求会崩。
6. 真机走查清单见 `docs/verification-w9.md`（主题三模式 / 强调色 / 字体四档 / 重启持久化 /
   深色逐页 / 字体放大溢出 / Markdown 导入 / iOS 红线）。
