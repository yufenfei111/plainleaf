# W6 开发日志 · 图片管线补全 + 相册网格 + 滚动优化（2026-09-20）

对应：DEVELOPMENT.md §三 W6（图片管线补全 + 相册网格 + 滚动优化），
外加真机反馈的"详情空白"缺陷修复。

## 一、真机反馈驱动的定位

真机走查结论：功能基本正常，但**界面滑动不够丝滑**。定位到三处：

1. 时间轴卡片用 `Image.file()` **直接解码原图**：52dp 的框里解码 4000×3000 的照片，
   单张几十 MB 解码内存，滑动时反复解码 —— 列表卡顿的头号来源。
2. 每张卡一个 `FutureBuilder` 现解析路径：滑动重建时 Future 反复创建，
   首帧必然是 loading 圈再跳变。
3. 相册页空壳，图片一多会一次性全进内存（无分页）。

## 二、修复：两级缩略图管线（`core/media/thumbnail_pipeline.dart`）

- thumb 长边 400 / q80（列表与网格用），medium 长边 1600 / q82（单图查看用，W7 消费）。
- **转码跑在 `Isolate.run`**：解码/缩放/编码是纯 CPU 活，放主线程会直接和 16ms 帧预算抢时间。
- `bakeOrientation`：手机照片普遍带 EXIF 方向，不烘焙会出现"竖拍照片在列表里横躺"。
- 小于目标边**不放大**（避免小图插值变糊、白耗 IO）。
- 顺带算出 §4.3 要求的 `hash_sha256` 与原始宽高/字节数，一次 IO 全拿到。
- 依赖：`image ^4.2`（解析到 4.3.0）、`crypto ^3.0`（解析到 3.0.7）。

路径约定（与 §4.3 对齐、且兼容 W4 旧数据）：
**相对路径以支持目录为基准**，形如 `media/2026/09/{uuid}.jpg`、`thumb/2026/09/{uuid}_t.jpg`。
这样同一字段就能表达"哪一级 + 哪个月"，解析只需 join 支持目录，不必为三类各存字段。

## 三、修复：时间轴卡片

- 优先渲染 `thumbPath`，无 thumb（W4 期历史数据）才回退原图，**但解码尺寸仍受限**。
- `cacheWidth = 显示尺寸 × devicePixelRatio`：即使回退原图，也只按显示尺寸解码。
- 新增 `supportDirProvider`：顶层取一次支持目录往下传字符串，
  **去掉每张卡的 FutureBuilder**，卡片内变成纯字符串拼接，不再有异步与首帧跳变。
- `ScrollCacheExtent.viewport(1.0)`：预渲染一屏缓冲，减少"边滑边建"的抖动。

## 四、W6 主线：相册页

按 §4.2 用标准三层实现（不再欠架构债）：
`domain/entities` + `domain/repositories` + `data/gallery_repository_impl`
+ `presentation/providers` + `presentation/gallery_page`。

- `CustomScrollView` + `SliverGrid` 月分组（不用嵌套 `GridView(shrinkWrap)`，
  避免重复布局计算）。
- 分页：首屏 60 张，滚到距底 500px 续拉；`AsyncNotifier` 保留已加载数据。
- 格子同样只渲染 thumb + `cacheWidth`。
- 空态/加载态/错误态齐全，AppBar 提供刷新。

## 五、缺陷修复：点开详情正文空白（且保存会清空正文）

**现象**：列表摘要有文本，点进详情正文是空的。

**根因**：编辑器以 `contentDelta` 为准，但种子数据与 W3 之前落库的记录只写了
`plainText`、`contentDelta` 为空串。`jsonDecode('')` 抛 `FormatException`
后直接返回空文档——**不止显示空白，此时一旦触发保存（输入标题或点「完成」的 flush），
就会用空文档覆盖 plainText，正文永久丢失**。定为数据丢失级缺陷。

修复两层：
1. `_controllerFromDelta` 增加 `fallbackText`：Delta 为空/非法/无实质内容时用 plainText 回填；
2. 种子数据补齐 `contentDelta`（新增 `seedDeltaOf`），保证两列自洽。

回归用例 `test/editor_fallback_test.dart`：打开只带 plainText 的记录 →
改动触发防抖保存 → 断言正文仍在且回写了有效 Delta。

## 六、顺带修的健壮性问题

测试用的假图片文件让 `img.decodeImage` 抛 **RangeError（Error 而非 Exception）**，
原来的 `on Exception` 兜不住——等价于真机上"挂一张损坏图片就崩"。
- 管线内 `_safeDecode` 把解码异常统一转成 `FormatException`；
- `_derive` 改为 `on Object` 降级：转码失败保留原图，等待 `backfillDerived` 重跑。

## 七、备份包格式升级 plbk/1 → plbk/2

- 打包 `media/`（原图）+ `thumb/`（缩略图）；**排除 medium**——它是派生图，
  体积大而可重算，避免备份包翻倍。
- `verify()` 同时兼容 `plbk/1` 与 `plbk/2`；恢复时按支持目录还原两级。

## 八、验证结果

| 验证 | 结果 |
|---|---|
| dart analyze（lib + test） | No issues found |
| flutter test（去代理） | **38/38 passed**（新增 5 例管线 + 1 例编辑器回归 + 1 例修复） |
| core 手写覆盖率 | **77.2%**（W5 为 73.5%，硬指标 70%） |
| flutter build apk --debug | 通过 |

## 九、遗留 / 下一步

- 真机复测滑动手感（**必须用 `--profile` 模式量，debug 模式慢 10 倍，手感不代表真机**）。
- W7：月分组筛选器、置顶收藏、回收站 UI 清理；历史资产缩略图一键补齐入口
  （`backfillDerived()` 已就绪，尚未接到设置页）。
- medium 图的消费点在 W7 详情页；当前 medium 已生成但只在备份排除策略里被引用。
