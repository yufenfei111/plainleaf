# W5 验收报告（2026-09-20）

> 依据：DEVELOPMENT.md §三 W5 条目 + §5.2/§5.3 开发规范与测试策略。
> 范围：Android 侧（iOS 本期不纳入）。结论：**W5 通过，M1 具备发布条件，剩真机走查一项待执行。**

## 一、验收结论

| 验收项 | 要求 | 结果 |
|---|---|---|
| flutter analyze | 0 警告 | ✅ No issues found（ASCII 路径下执行，见"环境要点"） |
| flutter test | 全绿 | ✅ 32/32 passed |
| core 逻辑覆盖率 | ≥70%（§5.3 硬指标） | ✅ 73.5%（388/528 行，不含生成代码） |
| flutter build apk --debug | 可打包 | ✅ `build/app/outputs/flutter-apk/app-debug.apk` |
| W5 五项功能 | #10–#14 | ✅ 全部落地并有测试覆盖 |
| 主链路集成 | 建→搜→备份→恢复→一致 | ✅ test/main_flow_test.dart（真实文件库） |
| 真机走查 | §5.3 里程碑演练 | ⬜ **待执行**（见第四节清单） |

## 二、分组覆盖率（`flutter test --coverage`）

| 分组 | 行覆盖 |
|---|---|
| core（手写） | **73.5%** ← 硬指标口径 |
| core（drift 生成，*.g.dart） | 26.7%（不计入指标） |
| features | 57.3% |
| app / shared | 89.4% / 100% |

说明：生成代码体量大（3524 行）且与手写逻辑无关，计入会稀释指标，
故按 §5.3「core 逻辑」口径单列。

## 三、本轮补齐的验收缺口

1. **搜索关键词高亮**（§5.3 列为 Widget 测试对象，但功能本身缺失）
   - `buildHighlightSpans()` 纯函数切分命中区间，重叠区间合并、无命中不拆分；
   - 搜索结果标题/摘要改为 `Text.rich` 高亮渲染；
   - `test/search_page_test.dart`：3 例切分边界 + 1 例真渲染断言。
2. **编辑器 500ms 防抖专项测试**（此前只有"新建→输入→发布"冒烟）
   - `test/autosave_test.dart`：窗口内（200ms）不落库 → 越过窗口（600ms）自动落库，
     不点「完成」也生效。
3. **主链路集成测试**（§5.3 要求，此前目录都没有）
   - `test/main_flow_test.dart`：建记录 → FTS 命中 → 导出 .plbk → 恢复 → 重开库校验数据与索引，
     并断言恢复前自动备份存在。放 `test/` 而非 `integration_test/`，因为后者需真机/模拟器，
     无法并入本机与 CI 的 `flutter test`。
4. **core 覆盖率从 65.3% 提到 73.5%**：补 `restore()` 全链路、笔记本 rename/softDelete/
   insertNotebook、`MediaStorage.deleteRel`、`DatabaseException` 异常层。

## 四、待执行：真机走查清单（§5.3 里程碑演练）

在 Android 真机上执行 `flutter install` 或安装上述 APK，逐项勾选：

- [ ] 冷启动到时间轴可见（种子数据渲染，记录冷启动耗时，红线 <2s）
- [ ] 悬浮「+」新建 → 输入标题/正文 → 停手 1 秒看 AppBar 转「已保存」（500ms 防抖）
- [ ] 点「完成」发布 → 返回时间轴能看到该条
- [ ] 拍照：授权弹窗**拒绝** → 不应崩溃，应有错误提示；再允许 → 图片进附件条
- [ ] 相册选图 → 时间轴卡片显示真实缩略图
- [ ] 搜索页输入中文（如"学习"）→ 有结果且关键词高亮
- [ ] 我的 → 导出备份包 → 提示文件名；再进「从备份包恢复」→ 选中 → 确认 → 提示重启 → 重启后数据一致
- [ ] 断网（飞行模式）走一遍以上流程 → 无报错（本地优先）
- [ ] 低存储/进程被杀：切后台再回来，草稿不丢
- [ ] 暗色模式 + 系统字体放大到最大 → 布局不炸、正文仍 ≥14sp

## 五、环境要点（本机踩坑，换机器前必看）

1. **`flutter test` 必须去掉代理**：本机 `HTTP_PROXY=http://127.0.0.1:22339` 会劫持
   测试进程与 `flutter_tester` 之间的本地 WebSocket，报错
   `Unable to connect to flutter_tester process: WebSocketException: Invalid WebSocket upgrade request`。
   执行方式：
   ```bash
   env -u HTTP_PROXY -u http_proxy -u HTTPS_PROXY -u https_proxy flutter test
   ```
   （不去掉的话 100% 失败，且现象容易被误判为代码问题。CI 无此变量，不受影响。）
2. **`flutter analyze` 在中文路径下必崩**：项目路径含中文时，分析服务握手 JSON 中的
   百分号编码路径会触发 `FormatException: Unterminated string`。
   替代方案：`dart analyze lib test`（可用），或在 ASCII 路径副本里跑 `flutter analyze`。
3. Windows 宿主跑数据层测试无需额外配置 sqlite3.dll（当前环境直接可用）；
   若换机器报缺库，设 `PLAINLEAF_SQLITE3_DLL` 指向 sqlite3.dll（见 `lib/app/providers.dart`）。
