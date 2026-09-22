# W8 开发日志 · 详情页打磨 + 空态引导（2026-09-22）

对应：DEVELOPMENT.md §三 W8（详情页打磨 + 空态引导），及 §6 路线图 W8 行。

范围红线（已在 DEVELOPMENT.md 第 25/60 行重申）：**地点记录是 MoSCoW 的 Could 级可选项，
本期明确不做**（不新增地点录入 UI、不解析 EXIF 位置）。本期限定在「详情页」与「空态引导」两件事。

GitHub：W8 由主代理编排、三名子代理并行完成，未单独开 issue（功能归属路线图 W8 行）。

## 〇、分工与文件所有权（为什么要这么切）

本次四个部分彼此依赖弱、可并行，主代理先把**接口契约冻结**后，把代码切成互不重叠的独占路径，
三子代理各写各的、互不触碰对方文件，最后由主代理做集成合并与路由注册。

| 子代理 | 独占路径 | 说明 |
|---|---|---|
| 主代理 | `entry_asset.dart`、`timeline_repository_impl.dart`、`timeline_repository.dart`（接口）、`router.dart` | 先落数据契约，再统一收口合并 |
| 子代理 B | `lib/features/detail/**`（整个 `presentation/` 子树） | 详情页与两个 provider，强依赖契约 |
| 子代理 C | `lib/shared/widgets/empty_state.dart` + 五个页面装配 | 纯展示组件，零业务依赖 |
| 子代理 D | `timeline_page.dart`、`trash_page.dart` 的空态改造 | 只动空态分支，不动列表/删除逻辑 |

为什么这么做：并行开发最大的风险是「互踩」——A 改了实体字段、B 的页面编译挂掉。
所以主代理先把 `EntryAsset`、`TimelineRepository.findEntryById/findAssetsByEntry`、
`TimelineEntry.contentDelta` 这几个**对外契约**定死并先合入，子代理只在契约之上写实现，
避免后期大规模返工（详见 §五 踩坑③）。

## 一、数据接口契约（A，主代理）

- 新增领域实体 `lib/features/timeline/domain/entities/entry_asset.dart`（`EntryAsset`）：
  - 字段 `relPath / thumbPath / mediumPath / width / height / sortIndex`；
  - getter `preferredRelPath => mediumPath ?? thumbPath ?? relPath`（**medium → thumb → 原图**）；
  - getter `needsBackfill => mediumPath == null && thumbPath == null`（两者皆空 = 只能回退原图）。
- `TimelineRepository` 接口（`timeline_repository.dart`）新增：
  - `Future<TimelineEntry?> findEntryById(int id)`：单条详情，不存在/已物理删除返回 null，不做 JOIN；
  - `Future<List<EntryAsset>> findAssetsByEntry(int entryId)`：按 `sortIndex` 升序，`assetsDao` 未注入时返回空列表。
- 实现（`timeline_repository_impl.dart`）**内部复用已有的 `EntriesDao.findById` 与 `AssetsDao.byEntry`**，
  因此**没有新增任何 Drift 代码生成**（零 `.g.dart` 改动，零迁移脚本）。
- `TimelineEntry` 新增可选字段 `contentDelta`（quill Delta JSON，旧数据/纯文本为空串）。

## 二、详情页（B，新建 `lib/features/detail/**`）

`EntryDetailPage`（`ConsumerWidget`，构造签名固定 `const EntryDetailPage({super.key, required this.entryId})`）
+ `entryDetailProvider` / `entryAssetsProvider` 两个 `FutureProvider.family`。

要点：
- **medium 图首次有了消费点**：列表/网格之外，详情页大图走 `EntryAsset.preferredRelPath`，
  并对 `Image.file` 设 `cacheWidth`（屏幕宽×DPR）防止原图解码。这是 W6 两级缩略图管线的
  第一个、也是目前唯一的使用方。
- 富文本正文：优先 `QuillController` + `QuillEditor` 只读渲染；`contentDelta` 为空串、
  `jsonDecode` 失败、或解析出的不是 `List`（合法 JSON 但非 Delta）时，**静默降级为 `Text(plainText)`**，
  绝不让一条坏数据把详情页搞崩（解析异常连 `Error` 一起兜）。
- 图片浏览：横向 `PageView` 翻页，多图显示「n/N」；点击打开全屏 `Dialog` + `InteractiveViewer` 双指缩放。
- 三态齐全：加载中 `CircularProgressIndicator`、id 不存在 `_NotFoundView`（「记录不存在或已被删除」）、
  报错 `_ErrorView`（「加载失败」+ 错误文案）。
- 入口：`_EntryCard.onTap` 已从 `/editor?id=` 改为 `context.push('/detail?id=${entry.id}')`；
  详情页菜单「编辑」→ `/editor?id=N`，「删除」→ 二次确认后 `softDelete` 并 `pop` 返回。

## 三、统一空态组件（C，新建 `lib/shared/widgets/empty_state.dart`）

`EmptyState`：icon / title / subtitle / 可选主次行动按钮（`actionLabel+onAction` 主、`secondaryActionLabel+onSecondaryAction` 次）。
设计约束：
- 不写死任何颜色，一律取 `Theme` 的 `colorScheme` / `textTheme`，浅色与深色模式自适应；
- 无回调就不渲染按钮（不留 disabled 占位）；
- 加了 `Semantics` 容器，方便 `find.text` / `find.byType` 做无障碍与测试定位。

已装配到五个页面（文案见 §七 与 verification-w8.md）：gallery、study、notebooks、drafts、search。
其中 **search 区分「未输入关键词」与「搜了但没结果」两种文案**（`输入关键词开始搜索` / `没有匹配的记录`）。

> 注意：时间轴与回收站的空态**仍是内联实现**（`timeline_page.dart._buildEmptyState`、
> `trash_page.dart._buildEmptyState`），两处注释都写明「主代理后续会统一替换成共享的 `EmptyState` 组件」。
> 本期未替换，避免在并行合并窗口里再动这两处已稳定的页面。

## 四、时间轴 / 回收站改造（D）

- `timeline_page.dart`：卡片点击改 `context.push('/detail?id=${entry.id}')`；空态区分两种——
  - 「库里根本没记录」（`noFilter`）：欢迎式「还没有记录」+ 主行动「记一笔」→ `/editor`；
  - 「筛选后为空」：`noFilter == false`，文案「没有符合条件的记录」+「清除筛选」按钮，
    直接把 `timelineFilterProvider` 重置为 `const TimelineFilter()`（不下推客户端过滤）。
- `trash_page.dart`：空态换成带图标、30 天保留说明（「回收站中的记录会从删除之日起保留 30 天，到期自动清理。」）、
  返回按钮的新版引导。
- 路由 `/detail?id=N`：**由主代理在 `lib/app/router.dart` 注册**（见 §七 遗留①——当前工作树里尚未注册）。

## 五、踩坑章节

### ① flutter_quill 11.x 的 API 名变更（B 子代理）
flutter_quill **11.6.0** 里没有 `QuillEditorConfigurations`，正确类名是 **`QuillEditorConfig`**；
`readOnly` 挂在 **`QuillController`** 上而不是 config；`QuillEditor.basic` 的实际签名是
`QuillEditor.basic({required QuillController controller, QuillEditorConfig config})`。
按旧文档（`QuillEditorConfigurations` + config 上带 `readOnly`）写会直接编译失败。

### ② `cacheWidth` 把 `FileImage` 包成 `ResizeImage`（测试断言）
测试里要断言详情页大图确实走了 medium 而非原图，但 `cacheWidth` 存在时 Flutter 会把
`FileImage` 包成 `ResizeImage`，其内层字段名是 **`imageProvider`**（不是 `image`）。
要先解一层 `provider is ResizeImage ? provider.imageProvider : provider` 才能拿到 `File` 路径断言。
（见 `test/w8_detail_test.dart` 用例②。）

### ③ 并行开发必须先把接口契约冻结（协作坑，本期验证有效）
三子代理并行时，若契约（实体字段 / 仓库方法签名）中途变动，会大面积编译失败、互相阻塞。
本期做法是主代理先合入 `entry_asset.dart` + 仓库接口 + `TimelineEntry.contentDelta`，
再放行子代理实现，全程零返工。下期若继续并行，务必沿用「先契约、后实现、路径独占」。

### ④（读代码发现）全屏查看未限 `cacheWidth`，与列表缩略图策略不一致
`_ImageGallery` 列表位用了 `cacheWidth` 限制解码尺寸，但 `_openFullscreen` 里的
`InteractiveViewer` 直接 `Image.file(File(abs), fit: BoxFit.contain)` **没有 `cacheWidth`**。
`abs` 走 `preferredRelPath` 指向 medium（长边 1600），不是原图，内存可控；但和列表的
「严格限制解码尺寸」策略不一致。若后续要进一步压内存，可在此也按屏幕宽×DPR 限 `cacheWidth`。

### ⑤（读代码发现）图片区依赖 `supportDirProvider` 已解析，缺失时静默消失
详情页图片用 `p.join(root, preferredRelPath)` 拼绝对路径，`root`（支持目录）为 null 时
`_ImageGallery` 直接返回 `SizedBox.shrink()`——**不报错、不占位**。好处是永不崩，
坏处是若某平台 `path_provider` 异常取不到目录，图片区会「神秘消失」而非给错误提示，
真机排查成本高。测试里靠 `supportDirProvider.overrideWith` 覆盖临时目录规避。

## 六、测试情况

三个新套件（均在 `test/` 下，沿用 `PlainLeafApp` + 注入自定义 `GoRouter` 隔离路由）：

| 套件 | 用例 | 覆盖点 |
|---|---|---|
| `w8_detail_test.dart` | 6 例（①~⑥） | 无图渲染、有图必走 medium（ResizeImage 解包断言）、非法 Delta 降级、id 不存在、编辑入口、loading 态 |
| `w8_empty_state_test.dart` | 5 例（①~⑤） | 无回调不渲染按钮、主/次按钮点击、搜索「未输入」与「无结果」两态文案确实不同 |
| `w8_timeline_empty_test.dart` | 4 例（①~④） | 空库无「清除筛选」、筛选空点击重置、卡片跳转 `/detail?id=N`、回收站新空态文案 |

合计 **15 例新增**。W7 既有套件（月分组/筛选/置顶/回收站/缩略图补齐 + 主链路）须保持全绿（回归）。

> 说明：按子代理硬约束，本文档作者**未运行 `flutter analyze` / `flutter test`**（避免与主代理的
> 并行测试抢 `.dart_tool` 锁）。最终 pass/fail 与覆盖率由并行测试子代理汇总；上表仅列已就绪的
> 套件与覆盖点，已逐文件核对代码与测试断言一致。

## 七、遗留与下一步

1. **（重要）`/detail` 路由尚未在 `router.dart` 注册。** 当前工作树里 `lib/app/router.dart`
   只有 `/editor` `/drafts` `/search` `/trash` 与底部 5 Tab，`/detail` 缺位；而 `timeline_page`
   已 `context.push('/detail?id=N')`。即：详情页代码完整，但**全局路由表没接上**，真机点击卡片会落到
   go_router 的未匹配错误页。需主代理在合并时补 `GoRoute(path: '/detail', ...)` 并解析 `id` 参数
   （详情页构造签名已固定，接上即可）。这是本期唯一的功能性接缝缺口。
2. 时间轴 / 回收站空态仍是内联实现，待主代理统一替换成 `EmptyState` 组件（契约已对齐，替换成本低）。
3. 全屏查看未限 `cacheWidth`（见 §五④），可作为后续微优化。
4. 地点记录（Could 级）仍不做；EXIF/位置录入排在「有 buffer 再做」。
5. iOS 本期不在范围：`ios/Runner/Info.plist` 未声明 `NSCameraUsageDescription` /
   `NSPhotoLibraryUsageDescription`（已读代码确认缺），做 iOS 前必须先补，否则相机/相册权限请求会崩。
6. 真机走查清单见 `docs/verification-w8.md`（含三态、三入口、medium 消费点、空态逐页文案）。
