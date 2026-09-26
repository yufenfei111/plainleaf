# W14 开工前自查 · 问题清单与规避策略

> 用途同 `w13-lessons.md`：把**真实踩过**的坑与决策收敛成一张表，本轮逐条对照。
> 没触发任何一条，才允许合入 dev。

---

## 一、环境与验证通道

| # | 历史问题 | 代价 | 本轮规避策略 |
|---|---|---|---|
| E1 | **bat 里写 UTF-8 中文注释 → cmd 直接静默退出**。现象极具迷惑性：计划任务 `LastTaskResult=1`、输出文件**连第一行都没动**，看起来像"任务没启动" | 排查约 20 分钟，一度怀疑任务注册失效 | **`run_test.bat` 里只写 ASCII**（`rem` 注释也用英文）。要写中文就写到 `.md` 里 |
| E2 | 每次换测试文件都要重写 bat（Read→Write 一轮） | 迭代变慢 | bat 从 `test_targets.txt` 读目标：改一行文本即可切换要跑的用例，bat 本身不动 |
| E3 | **"本机 pub get 跑不通"这条旧结论是错的**（W13 因网络抖动留下） | W13 为此砍掉了安全存储依赖 | 本轮一次装成 4 个：`cryptography` / `flutter_secure_storage` / `local_auth` / `pdf`。**前提是走代理 + 单独跑一次**，别把网络动作和本地动作串在同一条命令里 |
| E4 | pub get 后 `quill_native_bridge`、`win32` 被降版本（依赖求解的合法结果） | 容易误判成"工程坏了" | 加完依赖**立刻跑一次全量基线**（本次 146/146 全绿），确认没有连带破坏再动代码 |
| E5 | `Building with plugins requires symlink support`（没开开发者模式） | 误以为新增插件失败 | 这只影响**原生构建**；`flutter test` 与 `dart analyze` 完全不受影响 |
| E6 | 跑测试被本地代理劫持 / 静默成功就当完成 | 老坑 | `run_test.bat` 已清空代理；启动任务后**必须回读输出文件**确认真的跑完 |

---

## 二、密码学实现（新增，历史没有）

| # | 要点 | 为什么这样决定 |
|---|---|---|
| C1 | **MAC 不在 `SecretBox.cipherText` 尾部** | cryptography 里 `cipherText` / `mac` / `nonce` 是三个独立字段。以为"AEAD 的认证标签附在密文末尾"而只存密文，等于存了一份**无法验证完整性**的数据 |
| C2 | 口令必须经 PBKDF2 派生，且**每次加密用新盐** | 用户口令熵远低于 256 位随机密钥；同盐会让"同一个口令的两个包"共用一把密钥，拖走一个等于拖走全部 |
| C3 | **失败只有一种答案**：密码错 / 数据被截断 / 被改一个字节，GCM 的表现完全一致 | 所以 `SecurityException.userMessage` 必须写成"密码不正确，或者这份数据已被改动过"。**能区分才说明认证算法有问题** |
| C4 | `SecretBoxAuthenticationError` 是 `implements Exception`（不是 Error） | 可以用 `on SecretBoxAuthenticationError` 精确捕获；但外层仍建议兜一层 `on Object` |
| C5 | 容器自描述（magic + 盐/IV/MAC 长度） | 解密时不靠"我记得当初参数是多少"；将来改迭代次数只需动版本字节 |
| C6 | **没给密码**不能混成"认证失败"，要单独失败并抛 `passwordRequired` | 让 UI 知道该**弹密码框**，而不是弹一句"校验失败"。这是 UI 唯一需要区分的情形 |

---

## 三、UI 与测试

| # | 问题 | 规避策略 |
|---|---|---|
| U1 | `flutter_secure_storage` 在 `flutter test` 里必抛 `MissingPluginException` | 抽 `SecretStore` 接口；测试 override 成 `InMemorySecretStore`。约定：**read 失败静默返回 null，write 失败必须抛**——写失败了还让用户以为设上了，比不设更糟 |
| U2 | 循环动画让 `pumpAndSettle` 挂死 | 锁屏的转圈只在校验期间存在；测试里用 `pump()` + `pump(Duration)` 推进，不用 `pumpAndSettle` |
| U3 | 应用锁挂在哪一层 | 挂在 `MaterialApp` **内部**的 builder 上：解锁页要用 App 的主题与文案，放外面拿不到 `Theme` |
| U4 | 状态读不出来时会不会把用户锁在门外 | `appLockEnabledProvider` 一律兜底为"未启用"。**把用户锁在自己的数据外面是最糟的失败模式，没有之一** |
| U5 | 何时重新上锁 | 切到后台（paused/hidden）立刻重锁，不用计时器。计时方案要么太短烦人、要么太长形同虚设 |
| U6 | PDF 中文字体 | 实测 `.ttc`（msyh.ttc）**解析必然失败**（`FormatException: Unexpected extension byte`），只收 `.ttf/.otf`；找不到就抛 `ExportException` **明确失败**，绝不产出打开全是方块的"成功"文件 |
| U7 | CI 上没有中文字体怎么办 | 相关用例在拿不到字体时 `return` 跳过，而不是把流水线变红 |
| U8 | **`local_auth` 在 Android 上要求宿主 Activity 是 `FlutterFragmentActivity`**，并需要 `USE_BIOMETRIC` 权限；默认脚手架给的是 `FlutterActivity`，也没有该权限 | 真机点「用指纹解锁」会抛异常 → 被降级逻辑吞成"设备不支持指纹" → **功能静默不可用**，而本机 `flutter test` 在架构上根本走不到这条路（缺插件时只返回降级值）。已改 `MainActivity.kt` + `AndroidManifest.xml` |
| U9 | 怎么确认平台侧的改动真的进了 APK | `aapt2 dump permissions <apk>` 直接列包内权限（本次实测能看到 `USE_BIOMETRIC` + local_auth 自动合并的 `USE_FINGERPRINT`）。比"看构建日志猜"可靠 |

---

## 五、打包通道（本轮新增）

| # | 事实 | 说明 |
|---|---|---|
| B1 | `flutter build apk --debug` 在计划任务通道里可跑 | 首次带插件的构建 135s，增量 20s；产物 `build/app/outputs/flutter-apk/app-debug.apk`（debug 约 190MB，含调试符号） |
| B2 | **构建要带代理**，测试要去代理 | 方向相反：Gradle 需要下载依赖；而 `flutter test` 的本地 WebSocket 会被 `HTTP_PROXY` 劫持 |
| B3 | 改完 Kotlin/Manifest 后**必须重跑构建** | 若构建早于改动启动，第一次产物不含改动；判据：第二次构建是否 `up-to-date`（Gradle 输入哈希一致 → 说明第一次已吃到新源） |

---

## 四、数据红线与兼容性

| # | 约束 | 落地方式 |
|---|---|---|
| D1 | 明文备份包的行为**一字不能变**（W5/W13 的老包仍要能恢复） | `format` 仍是 `plbk/2`，加密作用在**包外层**；`verify()` 只在返回值里多给一个 `encrypted` |
| D2 | 恢复前自动备份不能被加密 | `restore()` 内部那份 `before-restore` 强制明文：它的用途是"刚恢复错能立刻退回去"，这时候还要输一遍密码是添乱 |
| D3 | W13 的明文凭据 `webdav.json` 要升级，但不能让老用户重填一次 | 读不到安全容器就去读老文件，读到立刻迁移 + 删明文；迁移失败静默，下次再试 |
| D4 | **凭据迁移不能因为"拿不到安全容器"就废掉功能** | `write()` 捕获 `SecurityException(storage)` 后**退回明文文件**：宁可信"少一层保护但能用"，也不让云备份在部分机型上变摆设 |
| D5 | 应用锁不是数据加密 | 必须如实写在注释与 UI 文案里：它防的是"手机被借用时顺手翻两下"，不是"设备被取证" |
