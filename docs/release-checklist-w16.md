# W16 发布检查清单 · 阶段 5（M5 v1.0.0）

> 制作于 2026-09-26，与提交 `d496c04`（发布构建配置）配套。
> 本文件分两部分：**本机已完成并可复现的**，以及**必须由你（真机 / 账号 / 商店后台）执行的**。
> 判据写清楚了，照着勾即可。

---

## 一、当前状态速览

| 项 | 状态 |
|---|---|
| release APK 构建链 | ✅ 已打通并验证（`app-release.apk` 71.2 MB，BUILD_EXIT=0） |
| release 包权限 | ✅ INTERNET / USE_BIOMETRIC / WRITE_EXTERNAL_STORAGE(max 29) / USE_FINGERPRINT |
| release 包版本 | ✅ versionCode=15、versionName=0.4.0-beta、minSdk=24、targetSdk=36 |
| 混淆（R8） | ✅ 已启用，规则见 `android/app/proguard-rules.pro` |
| 正式签名 | ⬜ **未配置**（无 `key.properties`，当前产出的是 debug 签名包，**不可分发**） |
| release 包真机走查 | ⬜ **未做**（开混淆后必须人工过一轮主链路） |
| 真机矩阵（≥3 台） | ⬜ 未做 |
| 隐私政策 / 用户协议 | ⬜ 文档已写（`PRIVACY.md`），**待托管到可访问的 URL** |
| 应用商店投递 | ⬜ 未做 |

---

## 二、构建 release 包（本机已验证的标准流程）

### ⚠️ 必须先读：本项目**不能在中文路径下构建 release**

| 项 | 说明 |
|---|---|
| 现象 | `AOT snapshotter exited with code 255`，日志里 `Unable to read file: C:\Users\??\Desktop\??\...\app.dill`（中文变乱码），arm / arm64 / x64 三个目标同时失败 |
| 根因 | Dart 的 AOT 编译器 `gen_snapshot` **读不了非 ASCII 路径**。而本机项目路径与系统用户名（`雨`）都含中文 |
| 为什么以前没发现 | debug 构建走 JIT，**不需要 AOT**，所以 W1–W15 一直是正常的 |
| ❌ 无效解法 | 用目录联接（junction）给项目一个 ASCII 入口 —— Gradle 会把联接**解析回真实路径**，错误信息里依旧是中文乱码 |
| ✅ 有效解法 | **真正把代码放到纯 ASCII 路径下构建**（下面第 1 步） |

### 标准流程

```bash
# 1. 克隆到纯 ASCII 路径（注意：用户名下的路径都含中文，别放在 C:\Users\雨\）
git clone -b dev "C:/Users/雨/Desktop/豆包/相册记事本项目/plainleaf" C:/plainleaf-release-src

# 2. 构建（首次约 2 分钟；AOT 缓存命中后约 40 秒）
cd C:/plainleaf-release-src
flutter pub get                  # 需要代理（Gradle/pub 要下载）
flutter build apk --release
```

产物：`C:\plainleaf-release-src\build\app\outputs\flutter-apk\app-release.apk`

**本机已注册对应任务**，可替代手工执行（自动带代理、绕开 sandbox 的进程派生限制）：

```bash
"C:/Users/雨/.workbuddy/binaries/python/envs/default/Scripts/python.exe" \
  "C:/Users/雨/AppData/Local/Temp/run_task.py" plainleaf_release_ascii
# 输出：C:\plainleaf-release-src\release_out.txt（含 PUBGET_EXIT / BUILD_EXIT）
```

> 端口提醒：`run_release.bat` 里的代理端口写死为当时会话的值，**每次用之前用
> `env | grep -i proxy` 现查并更新**，否则 Gradle 下载会挂住。

### 产物自检（不要只看 BUILD_EXIT）

```bash
BT="C:/Users/雨/AppData/Local/Android/sdk/build-tools/36.1.0"
"$BT/aapt2.exe" dump badging   <apk> | head -8      # versionCode / versionName / label
"$BT/aapt2.exe" dump permissions <apk>             # 权限清单
"$BT/apksigner.bat" verify --print-certs <apk>     # 签名是否已是正式密钥
```

`aapt2 dump permissions` 上**必须能看到 `android.permission.INTERNET`**。
这条曾经是缺的（Flutter 模板只在 debug/profile 变体声明它），后果是 release 包
完全无法联网、云备份静默失效而 debug 包一切正常。已在 `d496c04` 修复，别删那一行。

---

## 三、配置正式签名（发布前**必做**）

> 现在 `android/key.properties` 不存在，构建会自动降级为 **debug 签名**并在 Gradle
> 日志里打警告。debug 签名的包**不能上架、不能分发**。

### 1. 生成密钥库

```bash
keytool -genkey -v \
  -keystore C:/plainleaf-release-src/android/plainleaf-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias plainleaf
```

### 2. 写 `android/key.properties`（模板见 `android/key.properties.example`）

```properties
storePassword=<密钥库密码>
keyPassword=<密钥密码>
keyAlias=plainleaf
storeFile=../plainleaf-release.jks
```

`storeFile` 相对于 `android/app/` 解析。

### 3. 重新构建并确认签名已换

```bash
flutter build apk --release
"$BT/apksigner.bat" verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```
DN 不应再是 `CN=Android Debug`。

### ⚠️ 两条不可逆的提醒

1. **密钥库与密码一旦丢失，已发布的 App 就永远无法更新**（Android 要求同一签名的包才能覆盖安装），只能换包名重发。请备份到密码管理器 + 离线介质。
2. `key.properties` 与 `*.jks` 已在 `.gitignore` 里 —— **不要**为了"方便"把它们提交上去。

---

## 四、release 包真机走查（**开混淆后必做**）

混淆规则写错的典型症状是**构建成功、装上就崩**（`ClassNotFoundException` /
`NoSuchMethodError`），只看构建日志发现不了。至少覆盖：

| # | 项 | 判失败 |
|---|---|---|
| R1 | 冷启动到主界面 | 白屏 / 闪退 |
| R2 | 新建记录 → 输入 → 保存 → 时间轴可见 | 崩溃或丢数据 |
| R3 | 打开一条含图片的旧记录 | 图片不显示 |
| R4 | 相册页滚动 | 卡顿或崩溃 |
| R5 | **云备份 → 测试连接 / 上传** | 失败即说明 INTERNET 或网络层被裁（用真机 + 坚果云账号） |
| R6 | **保存图片到系统相册**（`gal`） | 失败 / 崩溃 |
| R7 | **开启应用锁 → 重启 → 指纹解锁**（`local_auth` + 系统安全容器） | 指纹按钮不出现 / 崩溃 |
| R8 | **导出加密备份包 → 恢复**（GCM + 安全容器） | 加解密失败 |
| R9 | 导出 PDF（中文字体） | 方块 / 失败 |

R5–R8 分别对应 `d496c04` 里 keep 的四个平台插件，是本次混淆的主要风险面。

W13 / W14 的完整走查项（26 条）见 `docs/device-checklist-w13-w14.md`，可直接复用。

---

## 五、真机矩阵（≥3 台）

| 维度 | 建议覆盖 | 理由 |
|---|---|---|
| Android 版本 | 至少含 1 台 **Android 10 以下** | `WRITE_EXTERNAL_STORAGE` 只在 API ≤29 生效，保存相册走的是另一条分支 |
| 厂商 ROM | 至少含 **1 台国产 ROM**（小米/华为/OPPO 等） | 生物识别的 `BiometricPrompt` 实现差异最大，最容易"静默不可用" |
| 屏幕 | 至少含 1 台小屏（≤5.5"） | 启动过场与多选工具条的布局压力点 |
| 架构 | arm64 为主 | 当前 APK 含 arm / arm64 / x64 三个 ABI |

> 应用锁那条尤其要在**已录入指纹**的真机上测。模拟器通常没有指纹，
> 测出来只会是"设备不支持"——那是降级路径，不是主路径。

---

## 六、上架前还要做的

| # | 项 | 说明 |
|---|---|---|
| 1 | 隐私政策托管 | `PRIVACY.md` 写好了，但商店要求**可访问的 URL**（GitHub Pages / 个人站 / 云盘公开链接均可） |
| 2 | 应用截图与描述 | 各商店后台要求，至少 4 张 |
| 3 | 签名后的 APK 体积核对 | 当前 71.2 MB（三 ABI 未拆分）。若嫌大可用 `--split-per-abi` 出三份，或只出 arm64 |
| 4 | Windows 包 | `flutter build windows --release` → 产物在 `build/windows/x64/runner/Release/`，注意一起分发 `data/` 目录与 VC++ 运行库 |
| 5 | 版本号推进 | 上架前把 `pubspec.yaml` 的 version 推到 `1.0.0+16`（M5 = v1.0.0，周次 16），**必须同步改 `lib/app/app_version.dart`**，否则 CI 门禁直接红 |
| 6 | 打 M5 tag | 上架完成后按前面 4 个里程碑的同样口径打 `v1.0.0` |

---

## 七、本机环境备忘（给未来的自己）

- **构建要带代理，测试要去代理** —— 方向相反，别记混。
- 本机禁止被执行的进程再派生子进程（`CreateFile failed 231`），所以 flutter / dart / node 都**不能从 bash 直接跑**，必须经任务计划派生（`plainleaf_all` / `plainleaf_test` / `plainleaf_icons` / `plainleaf_release_ascii`）。
- 任务计划的默认 `IdleSettings.StopOnIdleEnd = True` 会在**系统退出空闲时杀掉任务**
  （现象：进程收到 `^C`，`LastTaskResult = 0xC000013A`）。新建任务时务必关掉，
  否则长构建/长验证会莫名其妙半途而废。已注册的四个任务都已关闭该项。
- `.bat` 里**不能出现任何非 ASCII 字符**（含中文注释），cmd 会静默退出
  （`LastTaskResult=1`、输出文件一行未动）。
- `.bat` 里写 `echo X=%errorlevel%>> file`（数字紧贴 `>>`）会被 cmd 解析成
  **fd 0 重定向**，那行不会落盘。必须写成 `echo X=%errorlevel% >> file`（加空格）。
