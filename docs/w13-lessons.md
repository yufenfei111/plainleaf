# W13 开工前自查 · 问题清单与规避策略

> 用途：把 W1–W12（含 W13 交接包）里**真实踩过**的坑、错误决策与返工点收敛成一张表，
> 本轮开发中逐条对照。**写下来的目的不是复盘，是阻止重犯**——下面每一条都对应一次真实代价。
> 本轮未触发任何一条，才允许合入 dev。

---

## 一、环境与验证通道（最容易把"环境故障"误判成"代码 bug"）

| # | 历史问题 | 代价 | 本轮规避策略 |
|---|---|---|---|
| E1 | **跑测试被本地代理劫持**：`HTTP_PROXY` 会把 `flutter test` 进程与 `flutter_tester` 之间的本地 WebSocket 拦掉，报 `Invalid WebSocket upgrade request`，现象极像代码问题 | 反复怀疑代码 | `run_all.bat` 里已 `set HTTP_PROXY=` 清空；**不要手工带代理跑 flutter test** |
| E2 | **`flutter analyze` 在中文路径下必崩**（握手 JSON 百分号编码触发 `FormatException`） | 一度以为工程坏了 | 统一用 `dart analyze`，不用 `flutter analyze` |
| E3 | **验证口径比 CI 宽松**：本地只跑 `dart analyze --fatal-infos lib test`，**漏了 `tool/`**，而 CI 跑全项目 → 出现「本地全绿、CI 红」 | W12 一次真实 CI 失败 | 提交前必须跑 `dart analyze --fatal-infos lib test tool`（**`tool/` 不能省**） |
| E4 | **命令执行环境禁止派生子进程**（`CreateFile failed 231`）：`flutter`/`flutter test` 从工具里直接调必崩 | 曾误判为"环境退化/资源枯竭"，浪费大量时间 | 只走计划任务 COM 通道：`python run_task.py plainleaf_all`，轮询 `test_all.txt` 的 `TESTEXIT=` / `EXIT=` 行。**不要再从 bash 直接调 `flutter`** |
| E5 | **排查网络时拿"去代理"的结果下结论**，得出"外网不可达"的错误结论 | 错误结论写进了长期记忆，误导后续 | 外网必须**走**代理（端口每会话不同，`env \| grep -i proxy` 现查）；github 常抖（本次 `000`），**别把网络动作和本地动作串在同一条命令里** |
| E6 | **静默成功的操作凭返回码判定**（`TeamDelete`、计划任务启动） | 以为删了/启动了，实际没有 | 启动验证任务后**必须回读 `test_all.txt`** 确认真的在跑、真的跑完 |

---

## 二、架构与数据红线

| # | 历史问题 | 代价 | 本轮规避策略 |
|---|---|---|---|
| A1 | **页面直接 `ref.read(dbProvider).xxxDao`** 绕过分层（editor/search/settings/gallery 已违规待补） | 分层腐化、难测 | W13 一律 `Provider → 服务 → UI`；设置页只 `ref.watch/read` Provider，不碰 `BackupService`/文件系统 |
| A2 | **恢复前没有自动备份**（数据红线） | 覆盖即丢数据 | 云端恢复**必须**复用 `BackupService.restore()`（内部已含 verify → 自动备份 → 关库 → 替换），**严禁自行写库覆盖** |
| A3 | 表结构变更不写 Migration + 迁移测试 | 升级丢数据 | W13 **不改任何表结构**：凭据不进 `settings_kv`（见 S1），因此无需迁移 |
| A4 | 手改 `*.g.dart` / 全量重跑 build_runner | 生成物冲突风险 | W13 不新增表 → **不跑 build_runner、不碰任何 `.g.dart`** |

---

## 三、UI 与测试

| # | 历史问题 | 代价 | 本轮规避策略 |
|---|---|---|---|
| U1 | **循环动画 / 常驻 ticker** 让 `pumpAndSettle` 永远等不到静止 | 整套 Widget 测试挂死 | 云备份卡片**只用一次性 ≤250ms 过渡**；进度态用 `CircularProgressIndicator`（其动画在测试里由框架接管，不额外起 ticker）。判定标准：新增 UI 后 `w9_settings_test` 仍要能通过 |
| U2 | **对话框用页面级 `context.pop()` 收尾** | 把整页弹掉 | 配置对话框/确认框一律用 **dialog 自己的 context** 收尾 |
| U3 | 列表用 `AsyncValue.when`，重载时把已加载列表推翻回骨架 | 用户滚动位置丢失 | 云备份的"列远端备份"是一次性动作（按钮触发），**不进列表流**；结果态用独立状态 Provider |
| U4 | 颜色/字号写死 | 深色模式不可读 | 卡片所有颜色/文本样式取 `Theme.of(context).colorScheme / textTheme`；触控 ≥44dp |
| U5 | 测试依赖真机/真实外网 | CI 跑不了 | 用**本地假 `HttpServer`**（`InternetAddress.loopbackIPv4` + 端口 0），CI 不依赖外网；测试放 `test/`，**不放 `integration_test/`** |
| U6 | 局部变量下划线前缀触发 `no_leading_underscores_for_local_identifiers`（info 级也算失败） | CI 红 | 局部函数/变量不用 `_` 开头 |
| U7 | 中文 commit message 直接 `-m` 传参 | 编码错乱 | 走文件 + `git commit -F` |

---

## 四、W13 本轮**新增**的风险点（历史没有，先预判再写）

| # | 风险 | 规避策略 |
|---|---|---|
| S1 | **凭据进 `settings_kv` → 随 `.plbk` 上传云端 = 把云盘口令写进上传包** | 凭据存**支持目录根部的独立文件 `webdav.json`**；`BackupService` 只打包 `media/` `thumb/`，天然不会带出去。**测试里加断言**：导出的包内不含凭据文件 |
| S2 | **上传前的包是坏的**（打包静默失败） | 上传前先 `BackupService.verify()`，失败不上传 |
| S3 | 引入新依赖（`http` / `dio` / `flutter_secure_storage`）后 `flutter pub get` 在本机通道跑不通 → 全树编译失败 | **本轮零新增依赖**：用 `dart:io` 的 `HttpClient` 实现 PUT/GET/PROPFIND；凭据文件明文**已知取舍**，待 W14（AES-GCM）升级 |
| S4 | WebDAV 的 PROPFIND 返回 XML，没有 XML 依赖 | 用**受限正则**只提取 `href / getlastmodified / getcontentlength / collection` 四个字段，写成**纯静态函数**并单测两例（含目录被跳过） |
| S5 | 网络请求不设超时 → 慢网下 flutter test 挂死 | 客户端显式 `Duration` 超时（默认 30s，测试里注入 300ms）；`SocketException`/`TlsException`/`HandshakeException` 统一映射为 `offline` |
| S6 | 测试环境的 `HTTP_PROXY` 会把假服务器请求也代理走 | `WebDavClient` 支持注入 `HttpClient`，测试注入 `findProxy = (_) => 'DIRECT'` |
| S7 | 双向同步的诱惑 | 路线图已明确：W13 只做**单向备份上传/恢复**，双向 LWW 移出 v1.0。**不写任何冲突合并逻辑** |

---

## 五、合入前的硬性自查（逐条打勾）

- [ ] `flutter test` 全绿，用例数 **≥132**（基线 132，不许为绿而删断言）
- [ ] `dart analyze --fatal-infos lib test tool` → **No issues found**
- [ ] `git status --short` 里**没有** `.g.dart`、`pubspec.yaml`、`pubspec.lock` 的改动（= 没有偷偷加依赖/动生成代码）
- [ ] 仓库里**没有**任何真实凭据
- [ ] 设置页旧入口（导出/恢复/Markdown）行为未变（`w9_settings_test` 通过）
