# W4 开发日志（阶段 1 · MVP 记录内核 · 9/28–10/4）

> 依据 DEVELOPMENT.md §三 W4 行（修订版）：「选图/拍照 → 原图入库 → 时间轴展示」。
> 压缩/two 级缩略图按修订移 W6；quill 内嵌图文混排按指挥文档深坑预案改为附件条模式。
> 提前于 9/16 完成 W4 主体（进度领先排期约两周）。

## 2026-09-16（周三）W4 主体交付

### 今日完成

1. **MediaStorage 私有目录服务**（core/storage/media_storage.dart，§4.3 路径约定）：
   - 原图复制进 `media/yyyy/mm/<uuid>.jpg`；相对路径统一 p.posix.join（Windows 上 p.join 给反斜杠，破坏跨平台一致性与测试断言——实测卡点）；
   - `resolve(relPath)` 相对转绝对；`deleteRel` 供回收站物理清理；
   - 数据库只存相对路径（红线不变）。
2. **AssetsDao**：attach（挂接）/ byEntry（条目图片升序）/ softDelete（资产软删，文件不动）。
3. **Repository 附件能力**：`attachImage(entryId, sourcePath)`（复制+落库，异常包装 DatabaseException）、`firstImagePath(entryId)`（无图/文件缺失返回 null）；
   构造注入 AssetsDao + MediaStorage（未注入时附件路径抛领域异常，时间轴等其他能力不受影响）。
4. **编辑器图片附件条**（issue #7，附件条模式）：
   - image_picker 拍照/相册选图（imageQuality: 90 预压缩）→ attachImage → 横向缩略图条，可逐张删除（资产软删）；
   - 编辑既有记录时从 assets 表回载图片；quill 正文内嵌混排延后（深坑 1 预案），W6 相册阶段统一缩略图管线。
5. **时间轴真实缩略图**：卡片左侧首图 Image.file（FutureBuilder 懒解析 + 文件缺失回退加载态），无图回退类型图标——`firstAssetRelPath` 字段（W2 预留）首次消费。

### 卡点与解法

1. **p.join 平台分隔符**：Windows 下生成 `media\2026\09\...`，与 §4.3 正斜杠约定与测试断言不符 → p.posix.join 统一正斜杠。
2. **AssetsCompanion.insert 参数形态**：kind 列有 DB 默认值（insert 参数是 Value<String>），relPath 无默认（required String）——以生成代码 database.g.dart 为准核对，不凭记忆。
3. **depend_on_referenced_packages**：直接 import 传递依赖（path、path_provider_platform_interface）需显式声明进 pubspec。

### 决策记录

- **附件条而非 quill embed**：flutter_quill 图片 embed 是活跃 Issue 重灾区（深坑 1），MVP 用附件条保交付确定性；W6 视情况再评估 embed。
- **imageQuality: 90 的 pickImage 即时压缩**：轻量预压缩；medium/thumb 两级管线仍按修订路线在 W6 做（Isolate 红线届时落实）。
- **AssetsDao 未注入时的语义**：Repository 其余能力（时间轴/生命周期）完全可用，附件能力显式抛错——避免测试构造被迫携带文件系统。

### 验证结果

| 验证 | 结果 |
|---|---|
| dart analyze | No issues found（0 警告 0 提示） |
| flutter test | All tests passed!（+15 = db 1 + repository 3 + lifecycle 4 + UI 4 + media 3） |
| flutter build apk --debug | 见构建输出（+image_picker 依赖） |

### 遗留 / 下一步

- W5：笔记本/标签 + FTS5 搜索页 + .plbk 本地备份导出 + 真机走查（M1 冲刺，issue #10–16）；
- 真机验证拍照/选图（模拟器/桌面无相机，真机操作项保留给用户）。
