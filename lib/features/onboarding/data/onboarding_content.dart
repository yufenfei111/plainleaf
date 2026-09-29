import 'package:flutter/material.dart';

/// 新手引导与操作手册的**内容**（W22）
///
/// ## 为什么内容写成 Dart 常量而不是 `assets/manual.md` + markdown 渲染
/// 渲染 Markdown 需要新增 `flutter_markdown` 之类的依赖，而本项目的依赖面
/// 已经因为 AGP 9 变得敏感（`file_picker` 就是栽在这一步，见 pubspec 注释）。
/// 权衡下来：手册是**结构化内容**（章节 → 条目 → 段落），用 Dart 数据结构直接
/// 描述、用 Widget 渲染，能做得比 Markdown 更贴合 App 的视觉，且**零依赖风险**。
/// 代价是改文案要重新编译 —— 对一份内置手册来说完全可以接受。
///
/// 内容取材自 `docs/DEVELOPMENT.md`、`CHANGELOG.md` 与各周验收文档，
/// 只写**当前真实存在**的功能，不写"计划中"的东西。

// ───────────────────────────── 引导页 ─────────────────────────────

class OnboardingSlide {
  const OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.highlights,
  });

  final IconData icon;
  final String title;

  /// 一句话说清这一页在讲什么
  final String body;

  /// 2～3 条要点，宁可少而准，不要多而空
  final List<String> highlights;
}

const List<OnboardingSlide> kOnboardingSlides = [
  OnboardingSlide(
    icon: Icons.eco_outlined,
    title: '欢迎使用素页',
    body: '一个「本地优先」的私人记录工具。写下来的东西只存在你自己的设备上，'
        '不上传、不联网、不需要账号。',
    highlights: [
      '全部数据存在本机数据库里',
      '音乐、图片、文档都能挂到记录上',
      '支持加密备份，换设备也能带走',
    ],
  ),
  OnboardingSlide(
    icon: Icons.edit_note_outlined,
    title: '像记事本一样记东西',
    body: '点底部中间的按钮就能写。标题、正文、待办、心情、分类都在一个页面里，'
        '边写边自动保存，不用担心丢字。',
    highlights: [
      '正文支持加粗、列表、待办等富文本',
      '写完可以留着当草稿，想清楚再发布',
      '底部曲别针按钮可以挂图片、PDF、压缩包等任意文件',
    ],
  ),
  OnboardingSlide(
    icon: Icons.photo_library_outlined,
    title: '相册里翻看与浏览',
    body: '挂进来的图片会自动汇进相册。点开任意一张进入全屏，'
        '手势都做成了你习惯的样子。',
    highlights: [
      '左右滑动切换上一张 / 下一张',
      '双击放大看细节，下滑退出全屏',
      '看完可以直接保存到系统相册',
    ],
  ),
  OnboardingSlide(
    icon: Icons.lock_outline,
    title: '该上锁的地方上好锁',
    body: '如果记的东西比较私密，可以打开应用锁；备份包还能用密码加密，'
        '即使文件被别人拿到也打不开。',
    highlights: [
      '应用锁：打开 App 需要指纹 / 密码',
      '加密备份：AES-GCM + 密码派生，无密码不可解',
      '恢复前会自动备份当前数据，不必担心手滑',
    ],
  ),
];

// ───────────────────────────── 操作手册 ─────────────────────────────

/// 手册里的一条：小标题 + 正文（正文可含换行，按段落渲染）
class ManualEntry {
  const ManualEntry(this.title, this.body, {this.art});

  final String title;
  final String body;

  /// 可选的示意图（W22）。**不是每一条都配图** —— 只在"光靠文字说不清空间关系
  /// 或操作路径"的地方配（手势方向、界面结构、流程顺序），否则图会变成噪音。
  final ManualArt? art;
}

/// 手册示意图的种类。
///
/// ## 为什么是代码画的矢量图，而不是截图
/// 1. **不占包体**：截图动辄几百 KB，十几张就是几 MB；矢量图是几行 Widget。
/// 2. **不会过期**：UI 改一版，截图就全废了；示意图画的是*概念*（"底部有四个 Tab"），
///    不跟着换皮失效。
/// 3. **跟随主题**：深色模式下截图会很刺眼，矢量图直接用主题色。
/// 4. **零依赖**：不需要图片资源管线，也不用新依赖。
/// 代价是画不出"真实界面长什么样"—— 真要那个，应该配真机截图，那是另一件事。
enum ManualArt {
  /// 主界面结构：底部四个 Tab + 记录入口的位置
  mainTabs,

  /// 附件条的三个入口（相机 / 相册 / 曲别针）及其副作用差异
  attachEntry,

  /// 一条记录上能挂的维度
  recordParts,

  /// 全屏看图的三个手势
  viewerGestures,

  /// 筛选的四个维度
  filterDimensions,

  /// 备份 → 传输 → 恢复 的三步流程
  backupFlow,
}

/// 手册的一章
class ManualSection {
  const ManualSection({
    required this.icon,
    required this.title,
    required this.summary,
    required this.entries,
  });

  final IconData icon;
  final String title;

  /// 章首一句话，让人知道这一章解决什么问题
  final String summary;

  final List<ManualEntry> entries;
}

const List<ManualSection> kManualSections = [
  ManualSection(
    icon: Icons.rocket_launch_outlined,
    title: '1 · 快速开始',
    summary: '三条路都能进编辑器，随手就能记下一条。',
    entries: [
      ManualEntry(
        '记下第一条记录',
        '在「时间轴」页点右下角的 + 按钮，或者点底部中间那个按钮。\n'
            '新建时会先以「草稿」保存下来，所以标题还没想好也不要紧 —— 先写内容，'
            '想清楚了再点右上角「完成」发布。',
        art: ManualArt.mainTabs,
      ),
      ManualEntry(
        '草稿与发布',
        '草稿只出现在「我的 → 草稿箱」里，不会混进时间轴。\n'
            '如果一条都没写就退出，它会自动进回收站，不会留下空记录。',
      ),
      ManualEntry(
        '自动保存',
        '输入停止约半秒后自动保存，右上角会显示保存状态。\n'
            '切到别的页面再回来，内容都还在。',
      ),
    ],
  ),
  ManualSection(
    icon: Icons.edit_note_outlined,
    title: '2 · 记录与编辑',
    summary: '一条记录上能挂的维度，以及它们分别用在什么场合。',
    entries: [
      ManualEntry(
        '正文富文本',
        '正文支持加粗、斜体、下划线、标题、列表、待办、引用、代码块等。\n'
            '工具栏在正文上方，可以撤销 / 重做。',
      ),
      ManualEntry(
        '时间与心情',
        '每条记录可以单独设置日期（默认今天）与心情。心情会以颜色点显示在卡片上，'
            '方便一眼扫过去时看出当天状态。',
      ),
      ManualEntry(
        '分类与标签',
        '「分类」是记录的归属（比如某本笔记本），一条记录属于一个笔记本；\n'
            '「标签」可以贴多个，而且支持多级（父子标签），适合跨笔记本串联主题。',
        art: ManualArt.recordParts,
      ),
      ManualEntry(
        '置顶',
        '重要的记录可以置顶，置顶项会单独成组排在最前面，不受日期分组影响。',
      ),
    ],
  ),
  ManualSection(
    icon: Icons.attach_file,
    title: '3 · 附件',
    summary: '除了图片，还能挂 PDF、Word、压缩包等任意类型的文件。',
    entries: [
      ManualEntry(
        '怎么挂附件',
        '编辑器上方的附件条有三个入口：\n'
            '· 相机 —— 直接拍照\n'
            '· 相册 —— 从系统相册选图\n'
            '· 曲别针 —— 选择任意类型的本机文件\n'
            '前两个会压缩（省空间），曲别针是**原样导入**（不压缩、不改格式）。',
        art: ManualArt.attachEntry,
      ),
      ManualEntry(
        '支持哪些格式',
        '实际上任意文件都能挂进来。App 会按文件内容 + 扩展名识别类型：\n'
            '· 图片 / 视频 / 音频 / PDF —— 会生成缩略图（音频还会读出时长与封面）\n'
            '· 文档（Word、Excel、PPT、txt、md）/ 压缩包 —— 显示类型图标\n'
            '· 认不出来的格式 —— 归为「其他」，一样能存、能备份、能打开',
      ),
      ManualEntry(
        '附件条上看到什么',
        '图片显示缩略图；其他类型显示**类型图标 + 扩展名**（如 PDF、DOCX）。\n'
            '点一下就打开：图片用 App 内全屏浏览，其他类型交给系统里对应的应用。',
      ),
      ManualEntry(
        '文件名会保留吗',
        '会。虽然文件在磁盘上是用随机名存的（避免重名和非法字符），'
            '但你看到、以及交给系统应用时用的都是**原始文件名**。',
      ),
    ],
  ),
  ManualSection(
    icon: Icons.photo_library_outlined,
    title: '4 · 相册与浏览',
    summary: '所有图片汇总浏览，手势与系统相册保持一致。',
    entries: [
      ManualEntry(
        '全屏浏览手势',
        '在相册里点任意一张进入全屏：\n'
            '· 左右滑动 —— 切换上一张 / 下一张\n'
            '· 双击 —— 放大（再双击还原），放大后可拖动看细节\n'
            '· 下滑 —— 退出全屏回到相册',
        art: ManualArt.viewerGestures,
      ),
      ManualEntry(
        '保存到设备',
        '全屏右上角的下载按钮可以保存当前这张。\n'
            '手机上是存进**系统相册**；桌面端会落到「下载」目录并告诉你路径。\n'
            '保存用的是原图，不是缩略图。',
      ),
      ManualEntry(
        '为什么翻页很顺',
        'App 会提前把相邻的图片准备好，所以翻页时基本不用等。'
            '同时只保留你附近几张的解码数据，长时间翻也不会卡。',
      ),
    ],
  ),
  ManualSection(
    icon: Icons.search,
    title: '5 · 查找与回顾',
    summary: '四种找法，覆盖「记得大概内容」和「只记得时间」两种情形。',
    entries: [
      ManualEntry(
        '搜索',
        '时间轴右上角的放大镜。支持中文全文检索（按词匹配），'
            '标题和正文都能搜到。',
      ),
      ManualEntry(
        '按条件筛选',
        '时间轴工具栏的筛选按钮，可以按记录类型、笔记本、标签、'
            '以及**附件类型**（比如"只看带 PDF 的"）组合筛选。',
        art: ManualArt.filterDimensions,
      ),
      ManualEntry(
        '日历回顾',
        '时间轴工具栏的日历图标，按天回看写过的内容，适合做月度回顾。',
      ),
      ManualEntry(
        '那年今日',
        '时间轴顶部会提示去年的今天写了什么，点一下就能翻回去看。',
      ),
    ],
  ),
  ManualSection(
    icon: Icons.checklist_outlined,
    title: '6 · 待办与学习',
    summary: '「学习」Tab 里的两件事：待办清单与学习记录。',
    entries: [
      ManualEntry(
        '待办',
        '可以在正文里直接插待办项（斜杠菜单或工具栏），也可以在学习页单独管理。'
            '勾掉之后会记录完成时间。',
      ),
      ManualEntry(
        '学习记录',
        '学习页可以记录学习内容与时长，按月汇总，用来看自己这段时间投入了多少。',
      ),
    ],
  ),
  ManualSection(
    icon: Icons.lock_outline,
    title: '7 · 安全与隐私',
    summary: '数据不出设备；要上锁的地方提供了应用锁与加密备份。',
    entries: [
      ManualEntry(
        '数据在哪',
        '所有记录都存在本机的私有目录里，App 不会把它们上传到任何服务器。\n'
            '需要联网的地方只有一处：你主动配置 WebDAV 云备份时。',
      ),
      ManualEntry(
        '应用锁',
        '在「我的 → 安全」里开启，可以用指纹 / 面容解锁。\n'
            '开启后每次启动 App 都需要验证。',
      ),
      ManualEntry(
        '加密备份',
        '导出备份包时可以设置密码。设置后备份包用 AES-GCM 加密、'
            '密钥由密码派生（PBKDF2），**没有密码无法解开**，'
            '即使文件被别人拿到也不用担心。',
      ),
    ],
  ),
  ManualSection(
    icon: Icons.backup_outlined,
    title: '8 · 备份与恢复',
    summary: '备份包（.plbk）是「换手机 / 重装」时唯一可靠的手段，建议定期做。',
    entries: [
      ManualEntry(
        '导出备份包',
        '「我的 → 导出备份包（.plbk）」。它包含**数据库快照 + 全部附件文件**，'
            '是一个完整的归档，不是只导文字。',
      ),
      ManualEntry(
        '从备份包恢复',
        '「我的 → 从备份包恢复（.plbk）」。\n'
            '**恢复前 App 会自动先备份一次当前数据**，所以万一恢复错了还能退回去。\n'
            '注意：恢复是覆盖式的，会替换掉当前的记录。',
      ),
      ManualEntry(
        '云备份（WebDAV）',
        '如果配置了 WebDAV（坚果云、Nextcloud 等），可以手动把备份包传到云端，'
            '也可以设置定期上传。备份包本身可以加密。',
      ),
      ManualEntry(
        '推荐做法',
        '重要的记录养成习惯：每隔一段时间导出一个加密的 .plbk，'
            '放到电脑或网盘上。它是你数据的最后一道保险。',
        art: ManualArt.backupFlow,
      ),
    ],
  ),
  ManualSection(
    icon: Icons.import_export,
    title: '9 · 导入与导出',
    summary: '和其它工具之间搬东西。',
    entries: [
      ManualEntry(
        '导出 Markdown',
        '把已发布的记录导成单个 .md 文本，含标题、日期、类型、心情、正文，'
            '以及附件清单。适合迁移到别处的笔记工具。',
      ),
      ManualEntry(
        '导出 PDF',
        '按记录逐篇排版成 PDF。注意：需要系统里有中文字体，'
            '否则中文可能不显示。',
      ),
      ManualEntry(
        '导入 Markdown',
        '「我的 → 导入 Markdown」，把外部 .md 文本转成素页的记录。',
      ),
    ],
  ),
  ManualSection(
    icon: Icons.help_outline,
    title: '10 · 常见问题',
    summary: '几个容易踩到的地方。',
    entries: [
      ManualEntry(
        '删掉的东西去哪了',
        '删除都是**软删除**：记录进「回收站」，附件也会保留。\n'
            '回收站里的内容会在 30 天后自动清理，在此之前都可以恢复。',
      ),
      ManualEntry(
        '附件打不开怎么办',
        '如果点开附件提示「没有能打开该类型的应用」，说明系统里没有装对应的软件，'
            '装一个即可。文件本身没有损坏。',
      ),
      ManualEntry(
        '换手机怎么搬数据',
        '在旧手机上导出 `.plbk` 备份包 → 传到新手机 → 在新手机上「从备份包恢复」。'
            '建议备份时设置密码（传输过程更安全）。',
      ),
      ManualEntry(
        '觉得卡怎么办',
        '「我的 → 补齐历史缩略图」可以为早期记录补生成缩略图，'
            '列表滚动会明显更顺。',
      ),
    ],
  ),
];
