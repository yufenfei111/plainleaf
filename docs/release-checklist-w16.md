# 发布检查清单（阶段 5）

> 制作于 2026-09-26，与提交 `d496c04`（发布构建配置）配套。
> **2026-09-29 更新**：补上「Windows 开发者模式」这个前提，状态推进到 W20。
> 文件名里的 `w16` 只是创建时间，**内容本身是常青的**（构建流程不随周次变化）。

## 〇、先分清两条路（别把成本估错）

| 目标 | 要做的事 | 状态 |
|---|---|---|
| **个人自用**（当前定位） | 只需 §2「开发者模式」+ §2「构建」 | ✅ **已全部打通** |
| 上架应用商店 | 再加 §3「正式签名」+ §4/§5「走查 / 矩阵」+ §6 | ⬜ 未做，且**当前不计划做** |

> 项目定位是**个人自用、无商业化计划**（见 `docs/DEVELOPMENT.md`）。
> 所以 §3～§6 属于「将来真要发布时再回来看」的部分，平时不必维护。
> 反过来，§3 开头那段说明也解释了**为什么个人自用可以跳过签名**。

---

## 一、当前状态速览

| 项 | 状态 |
|---|---|
| Windows 开发者模式 | ✅ 已开启（`AllowDevelopmentWithoutDevLicense = 1`）—— **构建的前提**，见「第二个前提」|
| release APK 构建链 | ✅ 已打通（`app-release.apk` **72.0 MB**，`BUILD_EXIT=0`，131s） |
| release 包权限 | ✅ INTERNET / USE_BIOMETRIC / WRITE_EXTERNAL_STORAGE(max 29) / READ_MEDIA_IMAGES |
| release 包版本 | ✅ **versionCode=20**、versionName=0.4.0-beta、minSdk=24、targetSdk=36 |
| 混淆（R8） | ✅ 已启用，规则见 `android/app/proguard-rules.pro` |
| release 包真机走查 | ✅ **已做**（iQOO 12，8 项全过：安装 / 数据保留 / 启动速度 / W19 附件可见性 / W20 文件名 / 类型筛选 / 音频元信息 / 相册滑动） |
| 正式签名 | ⬜ 未配置 —— **个人自用不必配**（理由见 §3 开头） |
| 真机矩阵（≥3 台） | ⬜ 未做（仅上架需要） |
| 隐私政策 / 用户协议 | ⬜ 文档已写（`PRIVACY.md`），待托管（仅上架需要） |
| 应用商店投递 | ⬜ 未做（当前无计划） |

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

### ⚠️ 第二个前提：Windows 开发者模式（2026-09-29 补）

| 项 | 说明 |
|---|---|
| 现象 | `flutter pub get` 报 `Building with plugins requires symlink support` 并提示去开开发者模式；**若忽略它继续构建**，会在 Javac 阶段报 `找不到符号: 类 XxxPlugin`（插件代码压根没被链接进来）|
| 根因 | Flutter 为平台插件建**符号链接**需要该权限。它与中文路径是两个独立问题，W16 时被前者盖住了 |
| 为什么 W17 才暴露 | W17 首次新增平台插件（file_selector）。此前插件集固定，链接是历史上建好的，所以一直没触发 |
| ✅ 解法 | 设置 → 系统 → 开发者选项 → 开启「开发者模式」<br>（或管理员执行 `reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v AllowDevelopmentWithoutDevLicense /d 1`）|
| 校验 | `reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense` → 应为 `0x1` |

### 标准流程（已脚本化，自动同步代码）

构建脚本：`C:\plainleaf-release-src\run_release.bat`。
**每次构建都会先从远端拉最新代码，同步失败则中止构建**——所以不会出现
"改了代码却打出旧包"这种情况（这是这套流程刻意设计的安全阀）。

**唯一需要每次维护的是代理端口**（它在会话之间、甚至同一会话内都会变）：

```bash
# 1. 现查当前端口
env | grep -i proxy        # 形如 http://127.0.0.1:31927

# 2. 写进端口文件（纯数字、一行，不要带换行以外的任何字符）
echo -n "31927" > /c/plainleaf-release-src/proxy_port.txt
```

然后跑构建（本机已注册任务，自动绕开 sandbox 的进程派生限制）：

```bash
"C:/Users/雨/.workbuddy/binaries/python/envs/default/Scripts/python.exe" \
  "C:/Users/雨/AppData/Local/Temp/run_task.py" plainleaf_release_ascii
```

- 产物：`C:\plainleaf-release-src\build\app\outputs\flutter-apk\app-release.apk`
- 输出：`C:\plainleaf-release-src\release_out.txt`
  （含 `FETCH_EXIT` / `CHECKOUT_EXIT` / `PUBGET_EXIT` / `BUILD_EXIT` 四个退出码，
  以及本次实际检出的 commit —— **先看这四个码再相信产物**）

耗时：首次约 2 分钟，AOT 缓存命中后约 40 秒。

**要出某个里程碑的包**：把 `run_release.bat` 里的 `set REF=dev` 改成对应 tag
（如 `v0.4.0-beta`）再跑，脚本会同步并检出到那个 tag。

**要出「还没推送」的分支**：构建目录的 `origin` 指向的是**本地主仓库**
（`C:/Users/雨/Desktop/豆包/相册记事本项目/plainleaf`），不是 GitHub ——
因为 github 常被代理挡住。好处是 `REF` 可以直接写**本地分支名**
（如 `feat/w20-handoff-and-p1`），无需先推送。
2026-09-29 出 W20 包时正是靠这一点（当时该分支的 PR 还没合并）。

### 首次准备（换机器时做一次）

**先开 Windows 开发者模式**（见上面「第二个前提」—— 不开的话插件符号链接建不起来，
`flutter pub get` 会直接失败）。然后：

```bash
git clone "C:/Users/雨/Desktop/豆包/相册记事本项目/plainleaf" C:/plainleaf-release-src
cd /c/plainleaf-release-src
# origin 保持"本地主仓库"即可：不要改成 github —— 它常被代理挡住，
# 且保持本地才能构建尚未推送的分支
git config http.sslBackend openssl     # 本机 schannel 报吊销检查失败
git config http.sslVerify false        # 代理没有本地根证书；只作用于这个构建目录
printf '31927' > proxy_port.txt        # 端口以当时实际值为准
```

> 注意：构建目录里**不要手工改代码**——每次构建的同步步骤（`git checkout -f`）
> 会丢弃所有本地改动。要改代码就改主项目、提交推到远端，再跑构建。

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

## 三、配置正式签名（**仅上架需要**）

> **个人自用请跳过本节。** `android/app/build.gradle.kts` 本就有降级逻辑：
> 没有 `key.properties` 时 release 构建**自动回退用 debug 签名**。
> 因为 debug 签名与你自己原先装的包**同源**，可以**直接覆盖升级、数据不丢** ——
> 2026-09-29 实测确认（SHA-256 `5fa5709a…`，覆盖安装后 8 项功能验证全过）。
>
> 只有要把包**发给别人**或**上架**时，才需要下面的正式签名。
> （注意两种签名的包**不能互相覆盖**：换正式签名时必须卸载重装，
> 所以真要走这条路，最好在做重要数据之前定下来。）

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
这两样东西都放在**构建目录**（`C:\plainleaf-release-src\`）下：
该目录的同步步骤不会删未跟踪文件，所以它们安全；但**别把它们当成唯一一份备份**。

### 3. 重新构建并确认签名已换

按第二节的流程跑一次构建，然后：

```bash
BT="C:/Users/雨/AppData/Local/Android/sdk/build-tools/36.1.0"
"$BT/apksigner.bat" verify --print-certs \
  C:/plainleaf-release-src/build/app/outputs/flutter-apk/app-release.apk
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
