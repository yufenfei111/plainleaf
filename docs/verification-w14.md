# W14 验收报告 · 安全与导出

> 分支 `feat/w14-security-export`（从 W13 尖端切出）。
> 开工前的问题清单与规避策略见 `docs/w14-lessons.md`（逐条对照，本轮触发见第五节）。

---

## 一、验收结果（逐项）

| 项 | 标准 | 结果 |
|---|---|---|
| `flutter test` | 全部通过，用例数 ≥146 | ✅ **173/173**（基线 146 + 新增 27） |
| `dart analyze --fatal-infos lib test tool` | 0 issue | ✅ **No issues found** |
| 既有行为回归 | W1–W13 的旧用例一字不改地通过 | ✅ 146 条旧用例全绿（含明文备份包、WebDAV 上传/恢复） |
| 依赖红线 | 新增依赖必须逐个说明用途与必要性 | ✅ 4 个，见第四节 |
| 生成代码红线 | 不手改 `*.g.dart`、不跑 build_runner | ✅ 无 `.g.dart` 变更 |
| 数据红线 | 明文包行为不变、恢复前自动备份、凭据不进备份包 | ✅ 见第三节 |

---

## 二、本轮交付

### 新增文件

| 文件 | 职责 |
|---|---|
| `lib/core/security/crypto_service.dart` | AES-256-GCM 加解密 + PBKDF2-HMAC-SHA256 派生 + 自描述容器格式 |
| `lib/core/security/secret_store.dart` | 安全键值存储抽象（`SecretStore`）+ 系统安全容器实现 + 内存实现 |
| `lib/core/security/app_lock.dart` | 应用锁：存 verifier 而非密码/哈希，支持设置/修改/关闭/校验 |
| `lib/core/security/biometrics.dart` | 生物识别快速解锁（失败一律降级到密码） |
| `lib/core/exporter/pdf_exporter.dart` | PDF 导出：系统中文字体探测 + 找不到字体时明确失败 |
| `lib/features/settings/presentation/lock_screen.dart` | 解锁页（依赖全部注入，可独立测） |
| `lib/features/settings/presentation/app_lock_gate.dart` | 门控：挂在主 App 内，切后台自动重锁 |
| `lib/features/settings/presentation/providers/security_providers.dart` | Provider + 写入门面 `AppLockActions` |
| `test/w14_security_test.dart` | 16 例：容器格式、口令派生、应用锁、安全存储降级 |
| `test/w14_backup_crypto_test.dart` | 3 例：加密包导出/校验/恢复 + 明文包兼容 |
| `test/w14_export_test.dart` | 5 例：PDF 成功与缺字体失败两条路径 |
| `test/w14_lock_ui_test.dart` | 3 例：锁屏交互 + 门控拦截 + 未开启时零拦截 |

### 修改文件

| 文件 | 改动 |
|---|---|
| `lib/core/errors/app_exception.dart` | 新增 `SecurityErrorKind` / `SecurityException` / `ExportException`（**纯新增，未触碰既有类型**） |
| `lib/core/exporter/backup_service.dart` | `exportBackup/verify/restore` 支持 `password`；`BackupFileInfo` 带 `encrypted` 标记 |
| `lib/core/sync/webdav_config.dart` | 凭据从明文 `webdav.json` 迁移到系统安全容器（老用户自动迁移，容器不可用则退回文件） |
| `lib/core/sync/cloud_backup_service.dart` | 恢复支持密码；安全类异常原样透出（UI 才知道该弹密码框） |
| `lib/features/settings/presentation/settings_page.dart` | 应用锁入口（启用/改密/关闭）、导出加密选项、加密包恢复、PDF 导出入口 |
| `lib/features/settings/presentation/providers/webdav_providers.dart` | 记录最近一次安全失败原因，供 UI 补密码重试 |
| `lib/main.dart` | 门控挂在 `MaterialApp` 内的 builder 上 |
| `android/.../MainActivity.kt` | `FlutterActivity` → **`FlutterFragmentActivity`**（`local_auth` 的 Android 端硬要求，否则真机点指纹抛异常后被降级吞掉） |
| `android/app/src/main/AndroidManifest.xml` | 新增 `USE_BIOMETRIC` 权限 |
| `pubspec.yaml` / `pubspec.lock` | 新增 4 个依赖（见下） |

---

## 三、测试覆盖（27 例）

| 分组 | 例数 | 覆盖点 |
|---|---|---|
| 加密容器 | 8 | 往返、错密码、篡改一字节、非容器、同口令不同密文、空/64KB、文件头判定、非法盐 |
| 应用锁 | 6 | 初始状态、正确/错误密码、改密码必须先过旧密码、关闭、空密码、verifier 不含明文 |
| 安全存储 | 2 | 无插件时读静默 null / 写抛异常；内存实现读写删 |
| 备份加密 | 3 | 缺密码 vs 密码错 vs 密码对、加密包完整恢复（含 FTS）、明文包行为不变 |
| PDF 导出 | 5 | 缺字体明确失败、有字体出合法 `%PDF`、单条导出、类型标签、正文按行 |
| 应用锁 UI | 3 | 锁屏错误态与放行、门控拦截后解锁、未开启时零拦截 |

---

## 四、关键取舍（四条必须写下来的）

1. **GCM 只回答"通过/不通过"**，所以"密码错""文件被截""被改一个字节"在 UI 上是同一句文案：
   「密码不正确，或者这份数据已被改动过」。能区分才说明认证算法有问题。
2. **应用锁不是数据加密**：本地库仍是明文，它防的是"手机被借用时顺手翻两下"。
   这句话写在 `AppLockService` 的类注释与设置页副标题里，不夸大。
3. **改 PBKDF2 迭代次数 = 换一套密钥**：老密文一律解不开。真要升级必须同时抬容器
   magic 的版本字节，并在 `open()` 里按版本选参数（`crypto_service.dart` 已写警告）。
4. **PDF 中文字体只吃 `.ttf/.otf`**：实测 `.ttc`（微软雅黑）必然抛 `FormatException`。
   找不到可用字体就抛 `ExportException` **明确失败**，绝不产出打开全是方块的"成功"文件。

### 新增依赖与用途

| 依赖 | 用途 | 不新增会怎样 |
|---|---|---|
| `cryptography` 2.9.0 | AES-256-GCM / PBKDF2，纯 Dart、无平台通道 | 只能手写 GCM（GF(2^128) 等），自己实现密码学是风险最高的选择 |
| `flutter_secure_storage` 9.2.4 | 密钥与凭据进系统安全容器（DEVELOPMENT §4.3 明确要求） | 只能在私有目录明文存，W13 留下的坑补不上 |
| `local_auth` 2.3.0 | 指纹快速解锁 | 应用锁每次都要输密码，体验退化明显 |
| `pdf` 3.12.0 | PDF 生成（纯 Dart） | 无 PDF 导出 |

---

## 五、本轮真实踩过的坑（已写进 lessons）

- **bat 里写 UTF-8 中文注释 → cmd 静默退出**（`LastTaskResult=1`、输出文件一行未动）。排查约 20 分钟。
- **KDF 迭代次数不一致导致"密码正确却解不开"**：用例用 1000 次设密码、运行用 10 万次校验。
  两侧必须是同一个 KDF 参数——这条已写成注释与用例内的说明。
- **FTS 中文按整 token 前缀匹配**：正文「内容戊己庚」搜「戊己庚\*」搜不到，须用完整前缀。

---

## 六、打包与走查

### 已在本机完成的验证（无需真机）

- **debug APK 构建通过**：`flutter build apk --debug` → `build/app/outputs/flutter-apk/app-debug.apk`
  （首次带插件 135s，增量 20s）。
- **版本号机制修复**：`version` 此前停在 `0.2.0+2`（W10 起未动，横跨 M3 与阶段 4 前两周），
  现已改为唯一真源 + CI 门禁，取 `0.4.0-beta+14`。`aapt2 dump badging` 实测确认
  `versionCode` 由 `2` 变为 `14`、`versionName` 由 `0.2.0` 变为 `0.4.0-beta`。
- **平台侧改动确实进了包**：`aapt2 dump permissions app-debug.apk` 输出含
  `android.permission.USE_BIOMETRIC`（我们声明的）与 `USE_FINGERPRINT`（local_auth 自动合并）——
  比"看构建日志猜"可靠。
- **"加密真的生效"对照实验**（本地生成一对样例包 `sample-*.plbk`，已在 .gitignore）：

  | 文件 | 头部 | 能否当 zip 打开 |
  |---|---|---|
  | `sample-plain.plbk` | `PK\x03\x04` | ✅ 可见 `plainleaf.sqlite` + `manifest.json` |
  | `sample-encrypted.plbk` | `PLSEC1\x10\x0c` | ❌ `BadZipFile: File is not a zip file` |

  即：加密包连"里面有几个文件、各叫什么名字"都看不出来——这正是整包加密的目的。

### 仍需真机 / 账号（**未做**）

1. 应用锁：真机开启后冷启动是否出现锁屏；录有指纹时是否出现「用指纹解锁」并弹出系统验证框。
2. 息屏 / 切到其他 App 再回来，是否立刻重新上锁。
3. PDF 导出：真机能否生成中文 PDF（字体候选是否命中该 ROM）；未命中时是否提示"设备缺中文字体"。
4. 加密包恢复全流程：本地列表应显示 🔒 与"已加密"，选中后弹密码框，密码错提示
   「密码不正确，或者这份数据已被改动过」；W13 导出的明文老包仍能正常恢复。
5. **覆盖安装（不要卸载）**：从 W13 版本升级安装 → 原 WebDAV 配置应仍在
   （首次启动自动迁移到安全容器），不必重填。卸载重装会连安全容器一起清掉，属预期行为。
6. 坚果云：加密包上传 → 下载恢复（需用户自己的账号与另一台设备）。

---

## 七、已知遗留（不属于 W14，别顺手改）

- 数据库本体仍是明文——真正的库加密要改 Drift 连接层与迁移，属更后的独立议题。
- PDF 未打包字体子集：靠系统字体，ROM 无可用字体时明确失败（见取舍 4）。
- 生物识别只是快速通道，不做唯一通道；未实现"连续失败次数限制"（本地离线场景意义有限）。
- W13 遗留的坚果云实测走查仍未做（`verification-w13.md` 第五节）。
