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
