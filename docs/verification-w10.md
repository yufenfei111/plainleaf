# 素页 PlainLeaf · W10 自检报告与后续优化计划

> 范围：`plainleaf/lib` 全量代码走查（61 个 dart 文件）+ 全量用例回归（`flutter test`）+ 静态分析（`dart analyze --fatal-infos`）
> 日期：2026-09-22　基线：`v0.2.0+2`（76/76 用例绿）
> 目标：① 首屏与交互流畅度　② 人机交互直觉　③ 图片/编辑类缺陷　④ 下一阶段优化计划

---

## 一、自检方法

| 手段 | 结果 | 说明 |
|---|---|---|
| `dart analyze --fatal-infos lib test` | 0 issue | CI 口径（比本地默认严格） |
| `flutter test`（去代理） | 76/76 → 81/81 | 新增 5 条 W10 回归用例 |
| 逐文件走查 | 61 个 dart 文件 | 重点：启动链路、列表渲染、图片管线、编辑器 |

> 本机跑测试必须去代理：`env -u HTTP_PROXY -u http_proxy -u HTTPS_PROXY -u https_proxy flutter test`
> （`HTTP_PROXY` 会劫持 flutter_tester 的本地 WebSocket，报 `Invalid WebSocket upgrade request`）

---

## 二、问题清单

等级定义：**P0** 功能不可用/数据丢失　**P1** 明显影响体验或性能　**P2** 打磨项

### P0（必须修）

| # | 现象 | 定位 | 根因 |
|---|---|---|---|
| 1 | 编辑已有记录时，附件图**全部显示破图** | `editor_page.dart` `_loadImages`/`_ImageTile` | 库里存的是相对路径 `media/yyyy/mm/xxx.jpg`，却直接 `Image.file(File(rel))`——必然 FileNotFound |
| 2 | 新建/重命名笔记本或标签后，**整个笔记本页被弹走** | `notebooks_page.dart` 三个对话框 | 对话框收尾的 `context.pop()` 用的是**页面级** context（不是 dialog 内部 context），等于关掉弹窗后再 pop 一次路由 |
| 3 | 相册下滑续拉失败时，**已加载的几十张图全部消失**，整页变错误页 | `gallery_providers.dart` `loadMore` | 出错直接 `state = AsyncError(...)`，把已握在手里的数据推翻了 |
| 4 | 点「导出全部记录（Markdown）」提示成功，但**拿不到任何文件** | `settings_page.dart` `_exportMarkdown` | 只把内容 `print` 到控制台，没写磁盘 |

### P1（体验/性能明显受损）

| # | 现象 | 定位 | 根因 |
|---|---|---|---|
| 5 | 新建记录时开头几个字偶尔丢失 | `editor_page._bootstrap` / `_onContentChanged` | 落草稿是异步的，id 未就绪期间 `_onContentChanged` 直接 return，输入被静默丢弃 |
| 6 | 退出编辑器瞬间，最后 500ms 的编辑丢失 | `EditorPage.dispose` | `debouncer.dispose()` 只取消定时不执行挂起动作 |
| 7 | 点「完成」后偶发内容停留在旧版本 | `_publish` | `_debouncer.flush(_persist)` 拿不到 Future，未 await 就执行 `setStatus`，两个事务并发抢锁 |
| 8 | 编辑器**无法设置类型/笔记本/心情**，建完没法归类 | `editor_page` | 三项属性在 UI 上完全不可达，只能落默认类型、不属于任何笔记本 |
| 9 | 编辑器附件图卡顿、换机后失效 | `_ImageTile` / `_pickAndAttach` | ① 72dp 格子解码 4000px 原图（数十 MB/张）；② 用 `image_picker` 的临时缓存路径当永久路径 |
| 10 | 笔记本页角标先闪回 0 再跳到真实值 | `_NotebookTile` | 每个 tile 一个 `FutureBuilder`，N 个本 = N 次查询，且每次 rebuild 都重建 Future |
| 11 | 点笔记本毫无反应 | `_NotebookTile.onTap` | 空的 onTap（W7 遗留） |
| 12 | 搜索结果点进去落在**编辑器** | `search_page.dart` | 用户预期是「看这条」，落编辑器还容易误改内容 |
| 13 | 详情页长正文滑动发涩；全屏大图偶发 OOM | `entry_detail_page.dart` | ① `QuillEditor(scrollable:true)` 嵌在 `SingleChildScrollView` 里形成嵌套滚动；② 全屏图不限制解码尺寸 |
| 14 | 时间轴卡片图片加载失败是**空白色块**，无法归因 | `timeline_page._ThumbTile` | `errorBuilder` 返回 `SizedBox.expand()` |
| 15 | 冷启动偏慢 | `main.dart` | 回收站 30 天清理在 `runApp` **之前** await，一次事务的 IO 等待压在启动路径上 |
| 16 | 相册里的图片点不动 | `gallery_page._GridTile` | 网格项没有点击行为 |

### P2（打磨）

| # | 现象 | 定位 |
|---|---|---|
| 17 | 页面切换生硬（Android 默认整页上下推） | `router.dart` |
| 18 | 卡片 → 详情没有视觉连续性 | 缺 Hero 共享元素 |
| 19 | 保存状态文字硬切 | AppBar title |
| 20 | 相册没有下拉刷新，且数据不足一屏时拉不出来 | `gallery_page` |
| 21 | AppBar 图标语义含混（`edit_note`=草稿箱、`delete_outline`=回收站） | `timeline_page` |
| 22 | 来回滑动掉帧 | `ImageCache` 默认 1000 张/100MB，缩略图被大批淘汰后反复重解码 |

---

## 三、修复方案与落地情况

### 3.1 本轮已修复（含代码改动）

| # | 修复 | 文件 |
|---|---|---|
| 1 | 附件统一「thumb 优先 + 支持目录拼接 + `cacheWidth=72×DPR`」；挂接后**回读**库里的 thumbPath | `editor_page.dart` |
| 2 | 三个对话框只关自己，不再碰页面路由（附注释说明坑点） | `notebooks_page.dart` |
| 3 | 续拉失败保留数据 + 单独暴露 `loadMoreError`，底部给「点击重试」 | `gallery_providers.dart`、`gallery_page.dart` |
| 4 | 导出落到 `supportDir/export/素页导出-yyyyMMdd-HHmm.md`，SnackBar 给出完整路径 | `settings_page.dart` |
| 5 | id 未就绪时把输入标记为 `_pendingPersist`，id 一到立即冲刷 | `editor_page.dart` |
| 6 | `dispose` 先 `flush(_persist)` 再关门 | `editor_page.dart` |
| 7 | 新增 `Debouncer.flushAsync`，发布时 await 内容落库再置 status | `debouncer.dart`、`editor_page.dart` |
| 8 | 新增 `updateEntryMeta`（DAO→Repository→UI）+ 编辑器属性条（类型/笔记本/心情三个 chip） | `entries_dao.dart`、`timeline_repository*.dart`、`editor_page.dart` |
| 9 | 见 #1；同时不再持有临时缓存路径 | `editor_page.dart` |
| 10 | 新增 `watchEntryCountsByNotebook()`（一条 GROUP BY，且是流），tile 只读取值 | `notebooks_dao.dart`、`notebook_repository*.dart`、`notebooks_providers.dart` |
| 11 | 点击笔记本 → 设筛选 + 跳时间轴 | `notebooks_page.dart` |
| 12 | 搜索结果跳 `/detail?id=N` | `search_page.dart` |
| 13 | `QuillEditor(scrollable:false)`（外层统一滚动）+ 全屏图也限制 `cacheWidth` | `entry_detail_page.dart` |
| 14 | 失败态给破图图标（取主题色） | `timeline_page.dart` |
| 15 | 清理挪到 `unawaited(...)`，不再阻塞首帧 | `main.dart` |
| 16 | 网格项点击 → 所属记录详情 | `gallery_page.dart` |
| 17 | 统一 200ms 淡入 + 1.5% 上移过渡（仅全屏路由，Tab 常驻页不套） | `transitions.dart`（新增）、`router.dart` |
| 18 | 卡片缩略图 → 详情首图 Hero（`entry-thumb-<id>`） | `timeline_page.dart`、`entry_detail_page.dart` |
| 19 | 保存状态 `AnimatedSwitcher` 淡入淡出 | `editor_page.dart` |
| 20 | `RefreshIndicator` + `AlwaysScrollableScrollPhysics` | `gallery_page.dart` |
| 21 | 草稿箱用 `drafts_outlined`、回收站用 `restore_from_trash` | `timeline_page.dart` |
| 22 | `ImageCache` 调成 400 张 / 96MB（缩略图约 0.6MB/张，够两三屏） | `main.dart` |

### 3.2 关键设计决策（避免走回头路）

- **图片三要素缺一不可**：相对路径要拼支持目录 / 优先 thumb / 必须 `cacheWidth`。
  少任何一个都会表现成「要么破图、要么卡」。
- **续拉错误与首屏错误要分开**：首屏错了可以整页报错，续拉错了只能「原地提示 + 重试」——
  用户已经滑到第 N 张，推翻他的进度比报错严重得多。
- **编辑器属性写入做指纹比对**（`_metaSignature`）：防抖每 500ms 触发，
  不做比对就会给每次敲字多加一个事务。
- **对话框只用 dialog 自己的 context 收尾**：页面级 context 的 `pop()` 会连页面一起弹掉。
- **`flutter test` 里不要用关库来制造失败**：drift 关闭后的查询可能永远 pending，把测试挂死；
  要 override 一个会抛错的 repository。

---

## 四、验证结果

| 项 | 结果 |
|---|---|
| `dart analyze --fatal-infos lib test` | **0 issue** |
| `flutter test` | **81/81 通过**（原 76 + 新增 5） |
| 新增用例 | `test/w10_fixes_test.dart`：属性写入与清空 / 退出不丢字 / 建本不弹页 / 续拉失败保留数据 / 角标一次查询 |

新增用例逐条对应一个「用户能感知到的坏体验」，不是补覆盖率：

1. ① 类型/笔记本/心情可写入、可显式清空，且未传的字段不被顺手清掉，version 递增；
2. ② 输入后**不等防抖**直接销毁页面，最后那段字仍在库里；
3. ③ 建完笔记本页面还在（此前会被 pop 走）；
4. ④ 续拉抛错后，已加载的 60 张一张不少，`loadMoreError` 有值；
5. ⑤ 一条 GROUP BY 拿到各本计数，空本不在结果里（UI 按 0 处理）。

---

## 五、后续优化计划

### W10 收尾（本阶段剩）

| 项 | 动作 | 预期 |
|---|---|---|
| 首屏主题闪一下 | 在 `main()` 预读 `settings_kv` 的主题/字号/强调色，再 `runApp` | 消除「默认主题 → 恢复主题」的一次重绘 |
| 启动骨架屏 | 首帧给轻量骨架（时间轴卡片 placeholder），替代转圈 | 感知启动时间下降 |
| 时间轴分页 | 对齐相册：`limit 100` → 首屏 40 + 滚动续拉 | 长列表首帧构建量减半 |
| 时间轴下拉刷新 | `RefreshIndicator` + `invalidate(timelineStreamProvider)` | 与相册一致的手势预期 |
| 条目增删动画 | 列表改 `AnimatedList`/`SliverAnimatedList`，删除带 200ms 退场 | 删除不再「啪」地消失 |

### W11：体验与信息架构

- **底部导航精简**：5 Tab 中「学习」当前只有待办只读列表，先补录入入口（输入框 + 回车添加），
  否则该 Tab 是空壳。
- **筛选交互重做**：筛选条在笔记本变多后横向无限滑，改为「筛选」按钮 + 底部弹层
  （笔记本/类型/置顶三段，带已选计数与一键清除）。
- **编辑器**：字数统计、退出确认（有内容时二次确认）、图片长按查看大图。
- **相册**：点图进详情只是过渡，最终要有独立的全屏浏览（左右翻页 + 双指缩放 + 保存到相册）。

### W12：性能与稳定性

- **真机性能实测**：`flutter run --profile` + DevTools 抓时间轴/相册滑动的帧时间，
  目标 p95 < 16ms；本轮所有优化目前只做了静态与单元测试验证，**未做真机帧率实测**。
- **启动耗时量化**：`flutter run --trace-startup`，建立冷启动基线再优化。
- **图片管线**：`ThumbnailPipeline` 当前是单张 Isolate，批量挂接多图时串行等待；
  改为一次 Isolate 批处理或任务队列。
- **备份恢复**：现在要求手动重启 App，改为恢复后热重载 Provider（`ref.invalidate(dbProvider)`）。

### 发布前必须补的缺口

| 项 | 说明 |
|---|---|
| iOS `Info.plist` | 缺 `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription`，**做 iOS 前必须补**，否则一调用相机/相册就崩 |
| 真机走查 | 相机/相册权限、深色模式、大字号（1.3×）、超大图（4000px+）四项 |
| 覆盖率 | 生成代码 `*.g.dart` 单列统计，core 手写覆盖率目标 ≥ 80% |

---

## 六、已知限制

- 本轮所有结论来自**静态走查 + 单元/Widget 测试**，尚未在真机上跑帧率与启动耗时；
  性能类结论（如 ImageCache 调优）需真机复测确认。
- 详情页 `QuillEditor(scrollable:false)` 已在 Widget 测试中验证布局不报错，
  但超长富文本（10000 字 + 多图）的实测仍需真机。
- 相册点图跳详情是过渡方案，最终应替换为独立全屏浏览（见 W11）。
