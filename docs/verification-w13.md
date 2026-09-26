# W13 验收报告 · 云备份（WebDAV 单向）

> 分支 `feat/w13-webdav-backup`（从 W12 尖端切出）。
> 开工前的问题清单与规避策略见 `docs/w13-lessons.md`（本轮逐条对照，未触发任何一条）。

---

## 一、验收结果（逐项）

| 项 | 标准 | 结果 |
|---|---|---|
| `flutter test` | 全部通过，用例数 ≥132 | ✅ **146/146**（基线 132 + 新增 14） |
| `dart analyze --fatal-infos lib test tool` | 0 issue | ✅ **No issues found** |
| 既有行为回归 | 备份/恢复、时间轴、相册、编辑器自动保存不变 | ✅ 132 条旧用例全绿 |
| 网络红线 | 无真实凭据入库；断网/401/404/超时都有对应用例；CI 不依赖外网 | ✅ 见第三节 |
| 依赖红线 | 不新增依赖 | ✅ `pubspec.yaml` / `pubspec.lock` **零改动** |
| 生成代码红线 | 不手改 `*.g.dart`、不跑 build_runner | ✅ 无 `.g.dart` 变更 |

---

## 二、本轮交付

### 新增文件

| 文件 | 职责 |
|---|---|
| `lib/core/sync/webdav_client.dart` | WebDAV 客户端：MKCOL / PUT / GET / PROPFIND；PROPFIND 解析为纯静态函数 |
| `lib/core/sync/webdav_config.dart` | 配置模型 + 凭据存储（支持目录 `webdav.json`） |
| `lib/core/sync/cloud_backup_service.dart` | 上传（打包→校验→PUT）与恢复（GET→校验→`BackupService.restore`）编排 |
| `lib/features/settings/presentation/providers/webdav_providers.dart` | Provider + 写入门面 `CloudBackupActions` + 状态 `CloudBackupStatus` |
| `test/w13_webdav_test.dart` | 14 例（本地假 `HttpServer`，不依赖外网） |

### 修改文件

| 文件 | 改动 |
|---|---|
| `lib/core/errors/app_exception.dart` | **纯新增** `NetworkException` + `NetworkErrorKind`（未触碰既有类型） |
| `lib/features/settings/presentation/settings_page.dart` | disabled 的 WebDAV 占位条目 → 可用的「云备份」卡片 + 配置对话框 + 恢复流程 |

---

## 三、测试覆盖（14 例）

| # | 用例 | 覆盖点 |
|---|---|---|
| ① ② | PROPFIND 解析（含容错） | 跳过目录自身、识别 `.plbk`、无命名空间前缀、绝对 URL、坏日期降级为 null |
| ③ | 401 → `unauthorized` | 提示指向"改密码" |
| ④ | 404 → `notFound` | 下载不存在的文件 |
| ⑤ | 服务器不响应 → `timeout` | 客户端超时 300ms / 服务端延迟 3s |
| ⑥ | 端口无人监听 → `offline` | `SocketException` 映射 |
| ⑦ | 上传全流程 | PUT 路径正确、带 Basic 认证、内容是 zip、上传前已本地校验 |
| ⑧ | 列目录 | base 无尾斜杠也拼对、按时间倒序、非 `.plbk` 被过滤 |
| ⑨ | 恢复全流程 | 下载 → 校验 → **自动备份** → 覆盖 → 重开库数据一致（数据红线） |
| ⑩ | 下载到坏文件 | 中止恢复，**当前数据未被触碰**（库仍可用） |
| ⑪ | **凭据不随备份包外传** | 解包断言：包内无 `webdav` 条目、无任何含服务器地址的内容（安全红线） |
| ⑫ | 配置校验 | 缺协议头 / 空账号不通过 |
| ⑬ | 设置页渲染 | 卡片与四个入口可见；未配置时除「配置」外按钮不可点 |
| ⑭ | 写入门面 | 保存 → 状态成功 → 能读回；非法配置不写盘且不覆盖旧配置 |

---

## 四、关键设计取舍（别走回头路）

1. **零新增依赖**：WebDAV 用 `dart:io` 的 `HttpClient` 自己实现四个动词。
   `http`/`dio` 能省的代码量，抵不上"为一个小功能牵动 pubspec + 本机 pub get 通道不稳定"的风险。
2. **凭据绝不进 `settings_kv`**：settings_kv 会随 `.plbk` **上传云端**，
   把云盘口令写进上传包等于给远端递钥匙。改为支持目录根部的独立文件，
   `BackupService` 只打包 `media/` `thumb/`，天然不会被带出去（用例 ⑪ 守着这条）。
3. **PROPFIND 用受限正则而非 XML 解析器**：只取 4 个字段，服务器响应格式稳定；
   为它引一个 XML 依赖不划算。代价（畸形响应漏项）用 `modifiedAt`/`sizeBytes` 可为 null 兜住。
4. **`_resolve` 自己拼路径而不用 `Uri.resolve`**：base 无尾斜杠时 `Uri.resolve`
   会把最后一段目录名吃掉（`/dav/backup` + `a.plbk` → `/dav/a.plbk`）。
5. **上传前、恢复前都先 `verify`**：坏包不上传；下载到的坏包不落地。
   顺序反了的话，一次网络损坏就会造成"看起来成功的假备份"或直接覆盖掉用户数据。
6. **恢复一律复用 `BackupService.restore()`**：它内部已含"恢复前自动备份 + 关库 + 替换 + 还原媒体"，
   另写一套就是绕过数据红线与既有迁移路径。
7. **`userMessage` 只按 `kind` 给文案**：具体技术原因记在 `message`（日志用）。
   UI 绝不显示 `cause`（可能含 URL）。因此测试要断言原因时应断言 `message`。
8. **一次性动作不用 `AsyncValue.when`**：云备份是"点一下做一件事"，
   用独立的状态 Provider 才能保留上一次操作结果（`when` 会在重载时被冲掉）。

---

## 五、本机测试的两个坑（下次直接复用）

1. **flutter_test 会把 `HttpClient` 换成一律返回 400 的桩**（`TestWidgetsFlutterBinding`
   为了防止测试误打真实外网）。要测真实 socket 行为，必须把用例跑在
   `HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides())` 里
   （空子类继承来的 `createHttpClient` 会造出真客户端）。不这么做，
   所有网络用例都会拿到 HTTP 400，现象极像业务代码写错。
2. **ListView 只构建视口内的 children**：设置页底部的卡片在默认 800×600 视口下
   根本不会被 build，`find.text(...)` 连 `skipOffstage:false` 也找不到。
   解法是放大测试视口（`tester.view.physicalSize`），比 `scrollUntilVisible` 稳定。
3. 测试环境的 `HTTP_PROXY` 会代理走 127.0.0.1 的请求 → 注入 `HttpClient` 时
   显式 `findProxy = (_) => 'DIRECT'`。

---

## 六、坚果云实测走查清单（**未做**，需用户自己的账号）

> 本轮只用本地假服务器验证，未连任何真实 WebDAV 服务。以下为手动走查步骤，
> 建议 W14 之前完成；发现问题记回本文件。

1. 坚果云 → 账户信息 → 安全选项 → **添加应用密码**（不要用登录密码）。
2. App：我的 → 云备份 → 配置，地址填 `https://dav.jianguoyun.com/dav/<你的目录>/`，
   账号填坚果云账号邮箱，密码填**应用密码**。
3. 点「测试连接」→ 应提示"连接成功"。
4. 点「立即上传」→ 网页端应能看到 `plainleaf-backup-YYYY-MM-DD.plbk`。
5. **换机/卸载重装恢复**：在新设备上填同一配置 → 从云端恢复 → 选刚才那个包
   → 确认 → 重启 App → 检查记录、图片、笔记本是否一致。
6. 异常路径抽查：
   - 填错密码 → 应提示"账号或密码不正确"；
   - 飞行模式 → 应提示"连不上服务器"；
   - 目录填一个不存在的路径 → 上传应自动创建该目录并成功。
7. 检查**上传的包里没有凭据**：下载该 `.plbk` 用任意 zip 工具打开，
   确认里面只有 `manifest.json`、`plainleaf.sqlite`、`media/**`、`thumb/**`。

---

## 七、遗留（明确推迟，不含糊）

| # | 遗留 | 原因 / 下一步 |
|---|---|---|
| 1 | 坚果云真实账号实测未做 | 需要用户自己的账号与另一台设备，见第六节清单 |
| 2 | `webdav.json` 明文存储 | 待 W14 AES-GCM 落地后升级为加密存储 |
| 3 | 未做上传进度回调 | 大包（含大量图片）上传时只有转圈没有百分比；`HttpClient` 可在写入时分片上报，留待有真机反馈再做 |
| 4 | 未做定时自动备份 | 路线图未排；若要做需后台任务，与"不起常驻定时器"的基调冲突，得单独评估 |
| 5 | 云端备份包无自动清理 | 每次上传按日期命名，同一天覆盖；长期会累积，需要时再加"保留最近 N 份" |
