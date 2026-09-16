# W1 开发日志（阶段 0：立项与环境 · 9/7–9/13）

> 配套 `docs/phase0-checklist.md` 使用；本日志按天追加，记录「做了什么 / 卡点与解法 / 明日计划」。

---

## Day 1 · 2026-09-04（提前开工）环境就绪

### 今日完成

1. **环境基线确认**：全局 Flutter 3.47.2 stable（`C:\flutter`）、Dart 3.13.2；Android SDK 36.1.0、JBR JDK 21、licenses 全部接受；`flutter doctor -v` → **No issues found**。
2. **fvm 锁版**：`dart pub global activate fvm`（fvm 4.3.0）；`fvm install 3.47.2`；项目根生成 `.fvmrc`（`{"flutter":"3.47.2"}`，提交入库），后续一律经 fvm 调用 SDK，杜绝"我机器能跑"。
3. **工程初始化**：在仓库根目录 `flutter create . --project-name plainleaf --platforms=android,ios,windows`（按 README 目标平台收敛，不生成 linux/macos/web 脚手架；现有 README.md 被保留未覆盖）。
4. **包名修正为 `com.plainleaf.app`**（详见卡点 1），Android/iOS 双端一致；应用显示名设为「素页」。
5. **国内网络构建链路打通**：Gradle 发行包改腾讯云镜像；插件与依赖仓库改为阿里云镜像优先、官方源兜底（CI 在海外可正常回退官方源）。
6. **`.gitignore` 补强**：忽略 `.fvm/`（本地 SDK 联接，不入库；`.fvmrc` 照常入库）、`**/local.properties`（本机绝对路径）、`Thumbs.db`、`*.bak`。
7. **验证结果**：
   - `dart analyze` → **No issues found!**
   - `flutter test` → **All tests passed!（+1，默认计数器冒烟测试）**
   - `flutter build apk --debug` → **成功**，产物 `build/app/outputs/flutter-apk/app-debug.apk`
   - `aapt2 dump badging` 核验：`package: name='com.plainleaf.app'`、`application-label:'素页'`、`launchable-activity: name='com.plainleaf.app.MainActivity'`、minSdk 24 / targetSdk 36。

### 卡点与解法（换机/重装时先读这里）

1. **`flutter create --org` 会把 project name 拼到包名后面**：`--org com.plainleaf.app --project-name plainleaf` 得到的是 `com.plainleaf.app.plainleaf`，与开发文档 §二 要求的 `com.plainleaf.app` 不符。已手工修正三处：
   - `android/app/build.gradle.kts`：`namespace` 与 `applicationId` 改为 `com.plainleaf.app`；
   - MainActivity 移到 `kotlin/com/plainleaf/app/MainActivity.kt`，`package com.plainleaf.app`；
   - `ios/Runner.xcodeproj/project.pbxproj` 全部 `PRODUCT_BUNDLE_IDENTIFIER` 改为 `com.plainleaf.app`（测试 target 为 `.RunnerTests` 后缀）。
   - 备注：phase0-checklist 里的 create 命令本身有这个坑，后续以本日志修正结果为准。
2. **fvm 无法创建符号链接（Windows errno 1314）**：当前账户未开开发者模式、进程非提权，`fvm use` 报 "Failed to create version symlink"。改用目录联接（junction，不需要特权）等效替代：
   ```
   mklink /J ".fvm\flutter_sdk"      "C:\fvm\versions\3.47.2"
   mklink /J ".fvm\versions\3.47.2"  "C:\fvm\versions\3.47.2"
   ```
   `.fvm/` 已被 gitignore；**换机 clone 后需重新执行联接（或开启开发者模式后重跑 `fvm use`）**。
3. **fvm 缓存路径不能含中文**：fvm 默认缓存到 `C:\Users\雨\fvm`，其中的中文用户名导致原生 shader 编译器 impellerc 找不到 `#include`，`flutter test` 直接崩 `ShaderCompilerException`。解法：`fvm config --cache-path C:\fvm` 后重装 3.47.2。**今后一切 SDK/构建工具路径必须纯英文**（工程目录中文可以，但工具链目录不行）。
4. **`flutter analyze` 在中文工程路径下崩溃**：analysis server LSP 通道抛 `FormatException: Unterminated string`；已做对照实验——同一份代码在纯英文路径 `C:\pltest` 下 analyze 正常，确认是 SDK 对非 ASCII 工程路径的已知问题，与代码无关。本地静态检查改用 **`dart analyze`**（同一套分析引擎，结果可信）；Day 6 的 GitHub Actions CI 跑在 Linux 英文路径，不受此问题影响。
5. **Gradle 发行包下载 SSL 握手失败（PKIX path）**：`services.gradle.org` 会 307 跳转到 GitHub 下载，国内链路被中间设备干扰导致 JDK 证书校验失败。改用腾讯云镜像 `mirrors.cloud.tencent.com/gradle/gradle-9.3.1-all.zip`（已写入 `gradle-wrapper.properties`）。
6. **AGP 拦截非 ASCII 工程路径**：Android Gradle Plugin 9.1.0 默认拒绝中文工程路径，按其官方提示在 `android/gradle.properties` 加 `android.overridePathCheck=true`，**已实测 debug APK 可正常构建**；若后续 NDK/原生构建出现诡异路径问题，再评估把仓库迁出中文目录。

### 环境事实（版本快照）

| 项 | 值 |
|---|---|
| Flutter / Dart | 3.47.2 stable / 3.13.2（fvm 锁定，缓存于 C:\fvm） |
| Gradle / AGP / Kotlin | 9.3.1 / 9.1.0 / 2.4.0 |
| Android | minSdk 24、targetSdk/compileSdk 36、build-tools 36.1.0、JDK 21 |
| 产物 | app-debug.apk（约 144 MB，debug 含全部 ABI 与调试符号，release 会显著缩小） |

### 遗留 / 待办

- [ ] **真机验证（需要你操作）**：当前电脑未连接 Android 手机。手机开启「开发者选项 → USB 调试」并连线后，在仓库根执行 `fvm flutter run -d <设备id>`；或直接把 `build/app/outputs/flutter-apk/app-debug.apk` 传到手机安装，应看到名为「素页」的 Flutter 默认计数器页。
- [ ] 建议把 `C:\Users\雨\AppData\Local\Pub\Cache\bin` 加入用户 PATH，之后可直接用 `fvm` 而不必写全路径（非必须）。
- [ ] （可选）开启 Windows「开发者模式」后，fvm 可使用原生符号链接替代 junction。

### 明日计划（Day 2）

Dart 速通：null-safety / async-await / 集合与迭代 / records / class 与 mixin；手写「异步加载列表」命令行小练习；通读默认 `main.dart` 全部语法。

---

## Day 2-7 · 2026-09-15~16（骨架日合并收官，COMMAND-DOC 决策点 1）

> 阶段 0 剩余六天任务按「骨架日」方案一次做完：Dart/Widget 基础以真实项目代码实践替代独立练习，5 Tab + Drift 建表合并交付。

### 本批完成

1. **依赖基线落地**（pubspec.yaml）：flutter_riverpod 2.6.1 / go_router 14.8.1 / drift 2.31.0 / drift_flutter 0.2.8 / sqlite3_flutter_libs 0.5.42 / path_provider 2.1.6 / uuid 4.6.0；dev：build_runner 2.15.1 / drift_dev 2.31.0。清单外新增：drift_flutter（官方连接助手）、uuid（§4.3 五字段必需）、sqlite3（宿主内存库测试，传递依赖显式声明）。
2. **Drift 数据层（§4.3 修正版）**：notebooks/entries/assets/tags/entry_tags/todos/study_sessions/sync_meta/settings_kv 九表 + entries_fts FTS5 虚表；五字段全覆盖；hashSha256/completedAt/metadataJson 三处修正并入；EntriesDao（时间轴联表 Stream）/TodosDao（completedAt 开关）/NotebooksDao；forTesting 内存库构造。
3. **5 Tab 骨架**：go_router StatefulShellRoute.indexedStack + NavigationBar（时间轴/相册/学习/笔记本/我的）；主题骨架（米白 #FAF7F2 + 低饱和青绿 #4E9B8F，明暗双套）；时间轴页日期锚点分组 + 图文卡片 + 心情色点 + 悬浮「+」+ 三态齐全；学习页待办已接库可勾选；笔记本页双空间分组。
4. **演示种子数据**：首启幂等写入（settings_kv.seed_v1 标记），2 笔记本 + 4 记录 + 2 待办。
5. **仓库基建**：CHANGELOG.md（Keep a Changelog，[Unreleased] 条目）、Issue 模板（背景/验收/≤2h 拆分）、GitHub Actions CI（analyze --fatal-infos + test，Flutter 3.47.2，Linux 装 libsqlite3-dev）、docs/wireframes.md 线框走查文档。
6. **验证结果**：`dart analyze` → No issues found!（CI 同口径 `flutter analyze --fatal-infos` 由 Actions 复核）；`flutter test` → All tests passed!（+4：数据层建表/种子/幂等 1 例 + UI 冒烟 3 例）；`flutter build apk --debug` → 成功（Gradle 68.5s），aapt2 核验 `com.plainleaf.app` / versionName 0.1.0 / minSdk 24 / targetSdk 36 / application-label「素页」，150.1 MB（debug 全 ABI）。

### 卡点与解法（换机/重装先读这里）

1. **中文路径下 build_runner AOT 编译失败（exit 78）**：`Unable to write file: .dart_tool\build\entrypoint\build.dart.aot`。与 Day1 flutter analyze 中文路径问题同源，build_runner 新版 AOT 编译对非 ASCII 路径敏感。解法：复制 lib/test/pubspec 到纯英文路径（本次 C:\plgen）执行生成，`*.g.dart` 回拷入库。**后续每次改表结构都要走这条英文路径生成通道**；若采纳指挥文档决策点 2（仓库迁 C:\dev\plainleaf）此通道可废。
2. **path_provider 2.1.6 依赖链 native assets hook 编译失败**：flutter test 在 Windows 主机报 objective_c 9.6.1 hook `Architecture.arm64e: Member not found`（path_provider_foundation 2.6.0 / path_provider_android 2.3.1 引入 objective_c/jni）。解法：pubspec `dependency_overrides` 钉 path_provider_foundation 2.4.1 + path_provider_android 2.2.10。**Flutter 升级后应重试移除 overrides**。
3. **Windows 宿主测试缺 sqlite3.dll**：Flutter SDK 不自带，drift 内存库需要。解法：`PLAINLEAF_SQLITE3_DLL` 环境变量指定任意含 FTS5 的 sqlite3.dll（实测本机 Python 附带 3.50.4 可用）；providers.dart 内置 System32/Git 回退查找；CI Linux 装 libsqlite3-dev 不受影响。
4. **UI 测试两类挂死**：① drift 流退订会安排 0 延时 Timer（StreamQueryStore.markAsClosed），flutter_test 结束断言 pending timers 误报——用例收尾 `pumpWidget(SizedBox)` + `pump(1ms)` 消化（smoke_test 的 `_drainTimers`）；② 加载指示器动画期间裸 `pumpAndSettle` 永不落定——统一改有界 `_settle`（有限 pump + 3s 超时 settle）。另：进程被杀后残留 .dart_tool 会让 smoke 测试连 loading 都不输出，删 .dart_tool 重 pub get 即恢复。
5. **flutter build 需要平台目录**：英文路径生成通道必须连 `android/` 一起复制，否则报 build.gradle PathNotFoundException。

### 阶段 0 收官快照

| 项 | 值 |
|---|---|
| Flutter / Dart | 3.47.2 / 3.13.2（fvm 锁定不变） |
| 表 | 9 业务表 + entries_fts（§4.3 全项） |
| 测试 | 4 例全绿（db_smoke 1 + UI smoke 3） |
| APK | app-debug.apk 150.1 MB（com.plainleaf.app / 0.1.0） |
| analyze | 0 issue |

### 遗留 / 待办

- [ ] **真机走查（需要你操作）**：USB 调试连线 `fvm flutter run -d <设备id>`，或安装 build/app/outputs/flutter-apk/app-debug.apk，把 5 Tab 完整走一遍。
- [ ] 推送 dev 后观察 GitHub Actions CI 首跑（analyze --fatal-infos + test）。
- [ ] 指挥文档决策点 2：迁移英文仓库路径可同时废掉 build_runner 生成通道与 analyze workaround，越早越省。
- [ ] W2 起跑：Repository 层 + entries_fts 事务双写 + 时间轴接领域模型（学习路径：ModuNote data/datasources + storypad views/home）。