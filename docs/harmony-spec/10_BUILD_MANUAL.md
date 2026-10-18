# 10 · 鸿蒙复刻分步手册

> **给谁**：鸿蒙事业部的负责人（排期、验收）和执行的 coding agent（一步一会话）。
> **目标**：用 ArkTS / ArkUI 复刻一个**行为、数据与 iOS 尺素一致**的鸿蒙版；界面可以按 HarmonyOS Design 重画。
> **基线**：iOS 2026-10-12（schema V8、提交 `2a16f6c`，当时在开发分支上，`main` 尚未合入）。之后 iOS 的变化看 `CHANGELOG.md` 顶部。

---

## 怎么用这份手册

### 文档分工

| 文档 | 回答什么 | 什么时候读 |
|---|---|---|
| `00_PRODUCT_OVERVIEW.md` | 这是什么产品、什么调性 | 开工前，人和 agent 都读一次 |
| `01_TECH_STACK_MAPPING.md` | iOS 用 X → 鸿蒙用什么 | 每步开工时查 |
| `02_BACKEND_API.md` | 后端接口契约 | 做到联网的步骤 |
| `03_USER_FLOWS.md` | 端到端流程 | 做到对应流程 |
| `04_DESIGN_LANGUAGE.md` | 色值、字体、语调 | 做任何界面 |
| **`05_DATA_MODEL.md`** | 本地数据**权威**定义 | 1.3 及之后凡碰数据 |
| **`06_RULES.md`** | 现行规则，**带编号**（验收引用） | 每步的「验收」都指向它 |
| `09_OPEN_QUESTIONS.md` | 阻塞与待决 | 开工前 + 每个阶段开始前 |
| `modules/08_backup_package.md` | 备份包的决策与坑 | 6.4 / 6.5 |
| `CHANGELOG.md` | iOS 之后又改了什么 | **基线之后**每周看顶部 |

**冲突时以谁为准**：iOS 源码 > `06_RULES.md` > `00`–`05` > CHANGELOG 旧条目。发现冲突写进 `09_OPEN_QUESTIONS.md`，别自己挑一个。

### 一步 = 一个 agent 会话

每一步是一张卡，结构固定：

- **目标**：做完是什么样
- **先读**：要喂给 agent 的文档 / iOS 文件（iOS 文件路径相对 iOS 仓库的 `Memoir/`）
- **要做**：拆好的小项
- **不要**：明确的禁区
- **验收**：怎么算完成（引用 `06_RULES.md` 编号）

agent 的通用开场提示词见 **附录 A**；鸿蒙仓库的 `CLAUDE.md` 模板在 `templates/HARMONY_CLAUDE.md`；进度表模板见 **附录 B**。

### 顺序与并行

```
阶段 0 准备（人）
  └─ 阶段 1 地基 ──┬─ 阶段 2 写与读 ──┬─ 阶段 3 日记本与阅读
                    │                    └─ 阶段 6 设置与数据（6.4/6.5 备份可提前）
                    └─ 阶段 4 账号与后端 ── 阶段 5 邮筒 ── 阶段 7 会员
                                                             └─ 阶段 8 上架前
```

- 阶段 1 必须先做完；之后「写与读」和「账号与后端」两条线可以并行
- **6.4 备份包导入建议尽早做**（阶段 2.1 之后就能做）：用 iOS 导出的真实包导进来，是检验数据层对不对的最快办法
- 每个阶段结束，负责人按「阶段验收」过一遍再进下一阶段

### 每步完成的通用标准（所有卡都适用）

1. 编译通过、无新增告警
2. 纯逻辑（判定、计算、解析）有单元测试，跑通
3. 新增的用户可见文字七种语言齐全（取自 iOS 译文，见 0.4）
4. 失败对用户可见（统一错误提示），不静默吞掉；日志打完整错误码
5. 在进度表勾掉这一步，写下与 iOS 的偏差和原因

---

## 阶段 0 · 开工准备（人做）

### 0.1 收齐移交物料

| 物料 | 从哪来 | 用途 |
|---|---|---|
| 本目录 `Memoir/Docs/Harmony/` 全部文件 | iOS 仓库 | 施工图 |
| `Memoir/Docs/EXPORT_FORMAT.md`、`Memoir/Docs/MEMBERSHIP.md` | iOS 仓库 | 备份包契约、会员边界 |
| `Backend/shared/src/types.ts`、`rhythm.ts`、`handlers/` | iOS 仓库 | 接口权威 |
| **iOS 源码只读副本**（整个 `Memoir/` 目录） | iOS 仓库 | 参考实现。**强烈建议给**：每张卡都会指到具体文件 |
| `Memoir/Localizable.xcstrings`、`Memoir/InfoPlist.xcstrings` | iOS 仓库 | 七种语言全部译文的**唯一来源** |
| `Memoir/Resources/Legal/*.md` | iOS 仓库 | 协议骨架（鸿蒙版要法务改，Q12） |
| `Memoir/Resources/Sounds/*.wav` | iOS 仓库 | 投信 / 拆信声音（`Scripts/make_*_sound.py` 生成，可直接用） |
| `Memoir/Resources/SplashCovers/splash_{bamboo,leather,kent}.png` | iOS 仓库 | 启动封面（1290×2796） |
| `Assets.xcassets`：`Mailbox_{Bamboo,Leather,Kent}`、`Cover_*_Linen`、`AppIconPreview_*`、三套 App 图标、`BrandLogo`、`ConsentBackground` | iOS 仓库 | 邮筒插画、日记本布面、图标 |
| **iOS 导出的示例备份包** 2 个：明文 1 个 + 加密 1 个（附密码） | iOS 团队用**测试账号的测试数据**导出，**不要用真实日记** | 6.4 导入的验收样本 |
| **iOS 截图**（清单见附录 C） | iOS 团队在真机上截 | 视觉参照 |

### 0.2 过一遍阻塞表

逐条看 `09_OPEN_QUESTIONS.md`。**Q3（云同步）、Q12（法律文本）、Q6（字体）开工第一周就要有人认领**；Q1、Q2 不挡前四个阶段。

### 0.3 建工程

- DevEco Studio 新建 Stage 模型工程，`entry` 单模块起步；包名见 Q18
- 目录建议见 `01_TECH_STACK_MAPPING.md`「文件组织建议」
- 把 `templates/HARMONY_CLAUDE.md` 拷到鸿蒙仓库根目录改名 `CLAUDE.md`，按实际情况填空
- 把附录 B 的进度表存成鸿蒙仓库的 `PROGRESS.md`
- 把本目录整个拷进鸿蒙仓库 `docs/harmony-spec/`（agent 要能读到）；iOS 源码副本放 `reference/ios/`（只读，不参与编译）

### 0.4 物料转换（可交给 agent 做，作为第一个任务）

1. **字符串**：写一个脚本把 `Localizable.xcstrings` 转成鸿蒙资源
   - 七个限定词目录：`zh_Hans`、`zh_Hant`、`en`、`ja`、`ko`、`fr`、`es`（目录名以 DevEco 实际支持的写法为准）
   - xcstrings 的 key 就是简体中文原文（如「写下今天的故事」），不能直接当资源名 → 生成稳定的资源名（例：`s_` + 原文 SHA1 前 10 位），同时输出一份 `strings_index.json`：`资源名 → 简中原文 / iOS 注释`，agent 写界面时按中文原文查资源名
   - 带 `%@` / `%lld` / `%1$@` 的占位符转成鸿蒙格式化写法；**带参数的整句要保持整句**（语序各语言不同，R-LANG-07）
   - `InfoPlist.xcstrings` 里的 App 名、权限说明同样转（R-LANG-05、R-LANG-06）
   - 写一个**漏翻检查脚本**：代码里出现的中文字面量不在资源里、或资源七种不齐 → 报错，退出码非 0（iOS 的 `Scripts/check_localization.py` 是参照）
2. **图片**：上面那批图拷进 `resources/base/media`，命名改小写下划线
3. **声音**：wav 原样放 `resources/rawfile/sounds/`

**验收**：脚本可重复运行、结果稳定（同一份 xcstrings 两次生成的资源名不变）；七个目录都有 `string.json`；检查脚本对空工程返回 0。

---

## 阶段 1 · 地基

### 1.1 主题系统

- **目标**：三套主题 token 可切换，即时生效，深色主题让整个 App 走深色
- **先读**：`04_DESIGN_LANGUAGE.md`；iOS `Theme/AppTheme.swift`、`BambooTheme.swift`、`LeatherTheme.swift`、`KentTheme.swift`、`ThemeManager.swift`
- **要做**
  1. 定义主题 token 接口：背景 4 个、文字 3 个、边框 2 个、accent 2 个、心情 3 个、destructive、**要求的系统明暗（可空）**、**邮筒图资源名**、字体 6 个、正文行距、宽字距。明暗与邮筒图做成**必填**（漏配编译报错）
  2. 三套实现，色值逐个抄 iOS（`04` 有全表）
  3. ThemeManager：当前主题 id 存偏好 `selectedTheme`；读取时 `washi→bamboo`、`nordic→kent` 归一并写回；通过 `@Provide/@Consume`（或 AppStorage）下发
  4. 深色主题：在应用级设置颜色模式为深色；浅色主题恢复「跟随系统」（R-THEME-03）
  5. 字体集中成 token（Q6 没定之前先用系统衬线占位）
- **不要**：在页面里写死任何色值；按主题 id 到处 `if`
- **验收**：一个调试页列出全部 token，三套切换即时变化；切到皮革后状态栏、弹窗、底栏都是深色，切回素笺恢复（R-THEME-01/03）

### 1.2 多语言基础设施

- **目标**：App 内选语言，七种，切换当场生效
- **先读**：`06_RULES.md` R-LANG；iOS `Services/LanguageManager.swift`、`Extensions/Bundle+AppLanguage.swift`、`Extensions/Date+Formatting.swift`
- **要做**
  1. LanguageManager：偏好 `appLanguage`；首启按 R-LANG-02 解析并**立刻落盘**
  2. 设置 App 级首选语言，使资源按所选语言加载（候选：`i18n.System.setAppPreferredLanguage`，需核实）
  3. 日期格式化工具全部接受 App 语言（「2026年9月」「September 2026」「9月27日」「Sep 27」）
  4. 界面文字一律用资源引用（`$r('app.string.xxx')`），**不要**在启动时取一次字符串缓存起来
- **不要**：提供「跟随系统」；切换语言时重建整个页面栈
- **验收**：七种语言轮流切，记录页 / 设置页 / 日期当场变，导航不跳回首页（R-LANG-01/02/03/08）；系统语言设成德语首启 → 英语

### 1.3 本地数据层

- **目标**：`05_DATA_MODEL.md` 的全部实体可读写，有版本化迁移
- **先读**：`05_DATA_MODEL.md` 全文；iOS `Models/` 全部
- **要做**
  1. 建表（05 §10 为参考）+ 版本号 + `onUpgrade` 框架
  2. 模型类型：日记、内容块（含 `TextStyleRun`）、日记本、心情、来信、草稿；内容块 JSON 的编解码**逐块容错**（认不出的 `type` 跳过，单块坏了不影响其他块）
  3. 日记的**唯一写入口**：写内容块时同步生成 `content`（`visibleText` 用 `\n\n` 连接）、`wordCount`、`updatedAt`、`audioURLs`（R-RICH-10）
  4. 纯函数并配单测：`visibleText`、`isDry`、`isAddendum`、`nameKey`、`uniqueName`、`singleNotebook`、`nextSortOrder`、`BookColor` 下架映射、`LetterDelivery` 的五个阶段判定（05 §6.1）
  5. UUID 生成大写、比较忽略大小写
- **不要**：给日记表加 `isDraft`；把 `tags` 改成外键（名字就是身份）
- **验收**：单测覆盖上面所有纯函数（含边界：区间越界、跨日、同名不同大小写、全角）；造一个旧版本库跑一次升级不丢数据

### 1.4 媒体文件存储

- **目标**：照片 / 录音 / 封面落盘、读取、删除、孤儿清理
- **先读**：`05_DATA_MODEL.md` §8；iOS `Views/Components/PhotoPaper/PhotoPaperHelpers.swift`（`PhotoPaperIO`）、`Services/MediaStorage.swift`
- **要做**：目录 `journal_photos/`、`audio/`；命名规则照 05 §8；图片内存缓存；「引用表」函数（日记 + 草稿 + 封面）；占用统计；孤儿清理（只删不在引用表里的）
- **不要**：重新编码动态照片的静态图（R-PHOTO-03）
- **验收**：单测：草稿里引用的照片、日记本封面都不会被当孤儿（R-DATA-08）；删日记后它的文件都没了

### 1.5 首启：协议同意 → 引导 → 默认数据 → 开场

- **目标**：新装 App 的第一分钟和 iOS 一致
- **先读**：`06_RULES.md` R-APP；iOS `ContentView.swift`、`Views/Legal/*`、`Views/Onboarding/OnboardingView.swift`、`Views/Splash/SplashView.swift`、`SplashCoverPool.swift`
- **要做**
  1. 协议同意页：最上层、不可关；版本号比对；「同意」写版本号；不同意不退出（R-APP-01~03）。协议正文内置 md 渲染（Q12 定稿前先用 iOS 文本占位，**标注占位**）
  2. 引导页：品牌标题「Memoir · 尺素」+「写给自己的日记」；「选择你的纸张」三张小卡（素笺 / 皮革 / 肯特，中间一个「文」字）；「给笔友起个名字」输入框（占位「青鸟」）+「可跳过，之后在设置里也能改」；「开始书写」→ 去空白，空则「青鸟」，存主题，标记完成
  3. 默认数据：12 个心情（缺的补）、日记本表为空时建 4 本（R-APP-07）
  4. 开场封面：当前主题有图才放；时长按 R-APP-08；设置开关 `showSplashAnimation`
  5. 一次性迁移的框架（标记 key 可换）
- **不要**：示例日记；在同意前申请任何权限或联网
- **验收**：卸载重装走一遍：同意页 → 引导 → 记录页空状态；断网抓包确认同意前零请求；把协议版本号改大 → 再启动重新弹同意

### 1.6 主框架与全局提示

- **目标**：四个 tab + 全局提示条
- **先读**：iOS `ContentView.swift`、`Environment/ErrorPresenter.swift`、`ErrorToastView.swift`、`Environment/AppEnvironment.swift`
- **要做**
  1. 底部四 tab：记录 / 日记本 / 邮筒 / 设置（图标见 `04` 图标对照）
  2. AppEnvironment（依赖容器）：`errors`、`http`、`session`、`ai`(寄信服务) 等，用 `@Provide` 注入
  3. ErrorPresenter：顶部滑入、自动消失（0.35s 弹簧），种类 error / success；`present(error, fallback)` 统一把错误转成用户文案
  4. 回到前台的钩子（后面多个步骤挂在这：重排通知、处理寄信队列、同名日记本合并）
- **验收**：四 tab 可切；在调试入口触发一个错误 → 顶部出现提示并消失；主题切换后 tab 着色跟随

**阶段 1 验收**：新装 → 同意 → 引导 → 四个空 tab；七种语言、三套主题任意组合下没有一处中文漏翻、没有一处颜色不对。

---

## 阶段 2 · 写与读（纯本地闭环）

### 2.1 写日记页 v1（纯文本）

- **目标**：能写、能存、能存草稿
- **先读**：R-ENTRY-01~10；iOS `Views/Compose/ComposeView.swift`、`DraftExitDialog.swift`、`MoodSelector.swift`、`TagSelector.swift`、`Models/DraftEntry.swift`
- **要做**
  1. 全屏页：顶部日期 + 星期、字数；标题（≤40、去换行、最多三行）；正文（先用多行输入）；「心情」横滑选择（12 个，文字 + 色点 / 线性图标，单选可取消）；「收进日记本」单选 + 当场新建
  2. 右上 ✓：正文空时不可点；点了建日记（`createdAt`=`date`=此刻）→ 删草稿记录（不删媒体）→ 关闭
  3. 左上返回：R-ENTRY-02/03 的确认框；「保存草稿」后关闭并提示「草稿已保存」
  4. 进页面恢复草稿（R-ENTRY-04/05）
- **不要**：自动保存成正式日记；做草稿箱 / 多份草稿
- **验收**：R-ENTRY-01~10 逐条过；杀进程后草稿还在；「不保存」后草稿和它的媒体都没了

### 2.2 记录页（列表模式）

- **先读**：R-HOME-01/03/04/05；iOS `Views/Home/HomeView.swift`、`EntryRowView.swift`、`Services/GreetingManager.swift`
- **要做**：大标题 + 问候（五个时段各一组，按小时取模）+「本月记录 N 天」+ 每日语录（按一年第几天取模）；按年月分组倒序列表（组头吸顶）；底部浮钮；空状态；点行进详情
- **验收**：R-HOME-01/03/04/05；问候语和语录七种语言都对（这批是产品的嗓子，**必须用 iOS 译文**）

### 2.3 日记详情页

- **先读**：R-ENTRY-13~16；iOS `Views/Detail/EntryDetailView.swift`、`Views/Components/StampView.swift`、`WeatherLocationBadge.swift`
- **要做**：素笺「和纸版式」（大日期数字前小后大基线对齐 + 心情印章 + 星期 + 短线 + 标题 + 标签）；其余主题普通版式；正文只读；此时此地；「补记 N 次 · 最近 X」；右上编辑、删除（确认弹窗「删除日记」/「确定要删除这篇日记吗？此操作不可撤销。」）
- **验收**：删除后媒体文件清掉（R-DATA-07）；三套主题各看一遍

### 2.4 编辑页

- **先读**：R-ENTRY-11；iOS `Views/Edit/EditEntryView.swift`
- **要做**：全屏，复用写日记页的编辑组件；✕ 放弃改动、✓ 保存；老日记录音补进正文（R-RICH-09）
- **验收**：改标题、改心情、换日记本、改正文都能存下；✕ 后数据不变

### 2.5 图文编辑器：格式（技术验证先行）

- **目标**：一整篇连续编辑 + 粗体 / 斜体 / 小标题 / 荧光笔
- **先读**：R-RICH 全部；iOS `Views/Components/RichText/`（`RichDocument.swift` 是块 ↔ 富文本的转换核心）
- **⚠️ 先做 1 天技术验证（spike）**：ArkUI `RichEditor` 能否做到 ① 文字绕开浮动图片排 ② 自定义块（录音卡片、痕迹行）③ 区间样式与 UTF-16 偏移对得上。**做不到的项写进 `09_OPEN_QUESTIONS.md` 找产品要退化方案**（例：照片独占一行左 / 右对齐），不要自己定
- **要做**：块 ↔ 编辑器内容的双向转换（`text` + `styles` ↔ 富文本）；格式工具条；选中菜单「荧光笔 / 擦掉荧光笔」；荧光笔按主题配色与画法（R-RICH-08）
- **验收**：iOS 备份包里带格式的日记导入后格式正确；鸿蒙写的格式导出后 iOS 能正确显示（用 0.1 的样本包 + 6.5 导出互验）

### 2.6 照片：相册选图 + 相纸

- **先读**：R-PHOTO、R-RICH-02/03/05/06；05 §3.5；iOS `Views/Components/PhotoPaper/*`、`Views/Components/RichText/PhotoInsertFlow.swift`
- **要做**
  1. 系统照片选择器选图 → 选相纸（默认取偏好 `defaultPaperStyle`）→ 插到光标处（R-RICH-03）
  2. 六种相纸组件；倾斜角在创建时定（-3°~+3°）；照片格子尺寸只由宽 × 比例决定（R-PHOTO-09）
  3. 全屏查看页：点 / 长按都进；右上「⋯」：靠左 / 靠右、设为封面、换相纸、删除
  4. 每篇 ≤5 张（R-ENTRY-08）；会员锁先留钩子（7.2 接上）
- **验收**：大图、竖图、全景图都不会撑破版面；退格先选中再删

### 2.5b 编辑态绕排：隐形输入层（B1，2026-10-17 产品拍板）

> ⚠️ **本章已回退作废（2026-10-18 产品拍板）**：绕排平台缺陷连环修不见底
> （orphanCharOptimization×strut 两行零输出 / strut 行高实测不生效需探针自愈 /
> heading 编辑器合并污染拆段追修三轮），三页全部回退华为备忘录式
> （`RichBodyEditor` + `RichFormatToolbar` + 照片链路，真机三页冒烟 ✓）。
> WrapFlow 全家桶 + 278 单测**下线保留**（页面零引用未删）；未建成功能与恢复
> 条件见 **`11_UNBUILT_FEATURES.md`**。M2/M3/M4 任务随之作废，本章仅作
> 攻坚史料保留——里面沉淀的平台实测结论（strut/orphan/pitch/invalidate）
> 重启绕排时仍是第一手资料。
>
> 背景：2.6 追记的绕排攻坚阶段一（详情页阅读态 `WrapFlowView`）已真机验收；编辑态
> （写/编页）实测整行卡换行推下移、体验割裂，用户拍板做 **B1 隐形输入层方案**。

- **目标**：写/编页正文编辑态与阅读态**同构绕排**——照片浮动、打字实时绕排、光标/
  选区/拼音组合正确，替代 `RichBodyEditor`。
- **先读**：R-RICH-02/03/05/06/08；Q23（09，含真机实测两条硬约束）；2.5/2.6 的
  PROGRESS 追记；`WrapFlowModel/Engine/TextAdapter/View` 四文件 + `WrapFlow.test.ets`；
  `RichDocument.ets`（2.5 块↔文档转换，**拼接/拆回逻辑复用它**）；iOS
  `Views/Components/RichText/RichTextView.swift`（编辑/阅读一体参照）。
- **架构（定案，不再议）**
  1. **渲染**：复用 `WrapFlowView`（graphics.text 自绘 + 照片卡组件叠放）
  2. **输入**：1px 透明 `RichEditor` 隐形层承接输入法——内容与自绘文档同构
     （`RichDocument` 拼接、照片锚点 U+FFFC 占位保持偏移一致）；`aboutToIMEInput`
     （含 `previewText` 拼音组合）/ `aboutToDelete` 拦截（返回 false 阻止系统落字），
     事件流入自研编辑模型 → relayout → 自绘重渲
  3. **光标/选区**：graphics.text 无坐标→偏移 API，命中查询自算
     （`getLineMetrics` 行定位 + `Run.getAdvances/getPositions` 行内最近字形）；
     光标竖线/选区高亮/手柄全部自绘；`getRectsForRange` 画选区框、`getWordBoundary`
     双击选词
- **要做**
  1. **M1 骨架** ✅（2026-10-17 全毕，含页面接入+真机 E2E）：编辑算子
     `models/RichDocEditor.ets`（insert 继承左一字符/deleteRange 锚点保护/
     insertAnchor/applyFlags(offset,length) 整段替换/flagsAt）+ diff 算子
     `diffTextEdit`（隐形层单点 diff，拼音逐键即单点）+ 区间表
     `textBlockRangesOfBlocks`（文本块↔全文档偏移映射，与 fromBlocks 同步推演）；
     编辑组件 `richtext/WrapFlowEditor.ets`（渲染同构 WrapFlowView + 1px 透明隐形
     RichEditor **diff 模式**：onDidChange→getSpans→diff→模型→拆回→relayout；
     锚点保护两道闸 aboutToDelete 预判 + diff 兜底恢复；光标自绘闪烁
     getRectsForRange(TIGHT,STRUT)；命中 getGlyphPositionAtCoordinate——**勘误：
     该 API 存在（since 12），无需自算字形**；点击落光标/焦点 requestFocus）。
      单测 272 全绿（258→272）。**页面接入+真机 E2E ✓（2026-10-17）**：
      ComposeView/EditEntryView 换装 WrapFlowEditor（bodyLoaded 条件渲染防未装载
      闪烁；新建日记 draftBlocks=[]）；光标落点三例日志全对（点正文 hit=6→插入@6、
      点绕排区 hit=16→@16、uitest inputText(700,900) hit=22→@22；注入通道
      `uitest uiInput text/inputText`，`uinput -K` 按键注入此设备实测无效弃用）；
      **光标「落 0」疑案结案（非 bug）**：verify_ui 注入例程「全选→清除→输入」×
      锚点保护交互——全选删除被 aboutToDelete 正确拦截（否则整篇+照片被删）→
      选区塌缩 0→插入落 0，人工链路 4 次验证全对，后续 E2E 断言不可依赖 verify_ui
      的注入位置；**补修空态塌缩真缺陷**：`layout([])` totalHeight=0 → 新建日记/
      删光正文后正文 0 高度不可点——spanMeasure 高度 max(totalHeight, 3×正文行高)
      + 空文档占位段（复用 s_74bd07ef78）+ 空文档光标 (0,0) 一行高
      （WrapFlowTextAdapter 新增 buildPlaceholderParagraph），真机新建全链路
      （占位→点→输入→渲染）✓、非空回归零影响；5 点诊断日志保留（M2 调试用）；
      **真机缺陷「首段恰好两行整段消失」根因锁定+修复（2026-10-17）**：
      平台缺陷——`ParagraphStyle.orphanCharOptimization: true` × `strutStyle`
      同时存在时，**恰好排版成 2 行**的 `Paragraph.paint()` 零输出（1/3/4 行正常，
      去掉任一开关即恢复；逐项二分实证：strut+orphan ✗ / strut+trailingSpace ✓ /
      strut+autoSpace ✓；且为段落内禀，与文档态/偏移无关——固定样本探针矩阵
      g1/h1 实证）。修复：buildParagraph 移除 `orphanCharOptimization`
      （trailingSpaceOptimized/autoSpace 保留），真机 31 字 2 行态回归
      A 段 12335 暗px（修复前 0）✓、1/3/4 行态不受影响。排查方法沉淀：
      spanDraw 内联变体矩阵（mkVariant 闭包画同一样本不同 ParagraphStyle 于
      不同 y 偏移）+ 区域暗px统计二分定位；剪贴板建议条（屏幕 1462-1599）/卡片
      区/文档 A 自身 ink 是三大墨污染源，实验槽位须避开；
      **绕排坐标链追修（2026-10-18，照片漂移+遮字）**：引擎行带几何按参数行高
      （20vp）推演而实绘 16.32vp——**strutStyle.forceHeight 与
      TextStyle.heightScale/halfLeading 平台实测均不生效**（探针段落 51px/行
      铁证）→ 照片与上文空隙逐行累积（被「推走」）、跨段遮挡行带与实绘错位
      （底缘遮字）。修复：`TextLayoutAdapter.measurePitch(isHeading)` 实测行距
       （单字探针+缓存，测不到回退参数）+ 引擎 y 推进/遮挡带/照片锚定全消费实测
       （平台修复 strut 后自动回 20vp 自愈）；单测 +6 例，真机 w1/w4 像素回归
       （照片随打字恰移一行实绘 pitch、gap 恒 4vp、让位带 0 渗漏）。
       **heading 行段拆分追修（2026-10-18，编辑态 B 段整段 heading 污染）**：
       编辑器 doc 相邻文本块 \n 合并成单块渲染，块内 heading 样式整段生效
       （真机 u1：106 字 B 段全 heading pitch；DB 实况——heading 是独立文本块、
       块内无 \n，\n 合并只发生在 blocksWithEditorDocument 拼接）。修复=「\n 行
       拆分+sidecar 映射」：`WrapFlowModel.TextPart`/`textPartsOfBlock`（\n 拆段
       +runs 切片平移全量拷贝+逐段 isHeading）→ 适配器 `segmentsOf/
       styleForSegment` heading 分支（headingFontPx/headingLinePx）→ 编辑器
       `BuiltItems` sidecar（items/parts/blockIdxs 平行数组按 itemIndex 直查，
       防多段块计数漂移）+ `RenderParagraph.length` 语义（modelStart=块区间起点
       +行段起点）+ caret/hitTest 区间映射重写（rp.modelStart..+length）；
       `WrapFlowView.buildItems` 同步拆段（阅读态块独立无 \n 零影响）。单测 +6
       （278 全绿）。真机回归：LAYOUT-ITEMS 拆 5 项（T"夏日的午后"H 独立、
       body B）、LAYOUT-PARAS lh 21.12/16.32vp、光标 hit=35 映射 ✓、hidden
       len=181 ✓；部分行内 heading 一行内混排几何近似，观感后议。**顺带双修
       EditEntryView（回归中发现的既有缺陷）**：① 日期行过期——`this.entry`
       普通字段不进 build 依赖追踪，日期 Text 初帧取 Date.now() 后永不刷新
       （编辑历史日记恒显当天）；改 `@State entry`（详情页同款）+
       `dateLineText()` 空串守卫（加载前不闪「今天」）。② 标题注入竞态——
       `injectedTitle` 单边（onReady/loadEntry）先到即消费、空标题锁死真标题
       （本机 onReady 恒先到）；改双信号到齐（`entryLoaded`）才注入；测试条目
       8B704EE9 的 DB title 列本为空（「验证绕排测试」是正文首块），编辑页标题
       占位符是正确行为勿误判。
       **编辑器测试注意**：点击照片卡会触发 onPhotoOpen 全屏预览（不夺焦点，
       uitest text 仍进编辑器，截图却是预览页——dump 里找 Button [37,193][137,293]
       点 (87,243) 关闭）；暗像素分析前先确认页面内容（全页轮廓扫描）；
       **像素取证三坑（2026-10-18）**：阈值采样恰漏浅色文字（textTertiary
       min153 vs 常用阈值 150）+ 粗行距采样漏窄文字带 →「部分渲染」误判
       （实际正常，多模态识别证实）——正解=逐行 min 亮度无阈值全扫 +
       `recognize_ui_components` 多模态交叉验证；装机后旧进程可能存活（HAP 被换
       进程不死）→ `aa force-stop` + `aa start` 必做；`snapshot_tool` 会消失，
       备选 `snapshot_display` / `uitest screenCap`（实测一致）
  2. **M2 选区**：高亮 + 手柄拖拽；双击选词；格式工具条四灯接线
     （bold/italic/heading/highlight 的灯态与 apply 走编辑模型）
  3. **M3 联动**：长按自定义菜单（复制/粘贴/全选，系统菜单对不上自绘层不用）；
     照片插入/删除/换边/双击换边在编辑态实时重排；保存链路（编辑模型 →
     `ContentBlock[]`，writtenAt 语义同 2.5 的 Q24 处理）
  4. **M4 验收**：真机 E2E——打字实时绕排（光标在照片旁、文字不跳）；拼音组合/
     删除/换行/光标移动；照片全操作；保存后阅读态一致；中文/英文混排
- **不要**：不要动阅读态（WrapFlowView 详情页路径已验收）；不要用系统 editMenu /
  系统光标（排版不一致必然错位）；**不要**让隐形层真实渲染可见内容（透明、1px）
- **验收**：编辑态打字时照片不被推下移、文字实时绕排；光标点击/移动/选区/组合输入
  全对；保存 → 详情页阅读态排版一致；单测覆盖命中查询与编辑模型纯逻辑

### 2.7 录音

- **先读**：R-RICH-04/05/09；iOS `Views/Compose/VoiceRecordingSheet.swift`、`AudioPlayerCard.swift`、`Services/AudioRecorderManager.swift`
- **要做**：录音面板（≤3 分钟自动停）；AAC 单声道；存 `audio/`；插入规则；正文里的录音卡片可播放、有进度；每篇 ≤3 段
- **验收**：录 3 段后按钮置灰；删录音块后 `audioURLs` 同步变化

### 2.8 墨迹会干

- **先读**：R-INK 全部；05 §3.4；iOS `Models/ContentBlock.swift`（`Ink`）、`Views/Components/RichText/RichTextView.swift`（删除转划掉的交互）
- **要做**：编辑时按 R-INK-01~06 的规则拦截删除、转成划掉；补记墨色与「补记 · 某月某日」段标；取下照片 / 录音留 `trace` 块；详情页补记次数
- **验收**：单测 + 手测：把设备时间拨后 25 小时，删字变划线、新写的字换墨色；字数不算划掉的（R-INK-08）

### 2.9 相机与动态照片

- **先读**：R-PHOTO-02~07；Q13；iOS `Views/Camera/*`、`Views/Components/PhotoPaper/LivePhotoView.swift`、`Services/PhotoLibrarySaver.swift`、`Services/LivePhotoMovieTransferable.swift`
- **要做**：取景 → 拍 → 方形裁切显示图 + 原图原样 + 动态视频（若平台支持）→ 存一份进系统相册 →「写下这一刻」插入正文；闪光灯三态；拒绝权限给「去设置」
- **不要**：照搬灵动岛取景框；给动态照片加角标
- **验收**：拍一张动态照片，全屏按住能播；配对失败时显示静态图（R-PHOTO-04）；系统相册里多了一张

### 2.10 此时此地

- **先读**：R-PLACE；Q7、Q8；iOS `Services/WeatherManager.swift`、`Views/Compose/LocationPickerView.swift`、`Views/Settings/SettingsLocationView.swift`
- **要做**：进写日记页（且开了记录位置）自动定位 → 逆地理（按精度三档）→ 天气；地点选择器（不显示位置 / 当前位置 / 附近地点可搜）；失败重试 + 错误码上屏；权限被拒引导去设置；设置页「记录位置」开关 + 精度
- **验收**：R-PLACE-01~05；草稿恢复时地点不变（R-ENTRY-05）

**阶段 2 验收**：一台设备上从零写 10 篇（带格式、照片、录音、地点），全部能看、能改、能删；草稿、墨迹规则都对；拿 0.1 的样本包导入（需先做 6.4）显示与 iOS 截图一致。

---

## 阶段 3 · 日记本与阅读

### 3.1 书架

- **先读**：R-BOOK-01~05/08；05 §4；iOS `Views/Home/BookshelfView.swift`、`Shelf/ShelfGridView.swift`、`ShelfBookView.swift`、`ShelfDecor.swift`、`BookCoverView.swift`、`Models/Tag.swift`、`BookColor.swift`
- **要做**：三列书架板；第一格「全部日记」（象牙白）；每本显示封面（纯色亚麻 / 照片）、书名（每行 4 字折行）、篇数；末尾「新建」；新建弹窗（名称 + 撞名提示）
- **验收**：R-BOOK-01~05；新建撞名（含大小写、全角）被拦

### 3.2 长按拿书、拖动换位

- **先读**：R-BOOK-06/07；iOS `Shelf/ShelfGridView.swift`（动画参数在文件头）、`Shelf/BookBoxProjection.swift`（书的立体投影）
- **要做**：按 R-BOOK-06 的五个阶段做；书脊颜色按 R-BOOK-07；松手只写变了的 `sortOrder`
- **不要**：抖动、让位动画、角标
- **验收**：录屏给产品看（这一条是手感，**必须产品当面确认**，见反馈「视觉改动先给看实物」）

### 3.3 日记本主页

- **先读**：R-BOOK-09~11；iOS `Views/Home/BookDetailView.swift`、`BookHome/BookHeroView.swift`、`BookHome/BookContentsView.swift`
- **要做**：封面大图（照片满版渐隐 / 纯色布面干净收边）、副标题或年月跨度、目录（列表 / 宫格，记偏好 `bookContentsLayout`）、底部「开始阅读」+ 写一篇（带入这本）、右上「…」（编辑封面 / 重命名 / 删除）
- **验收**：R-BOOK-09~11；改名后日记跟着走、打开着的页面不丢

### 3.4 封面编辑器

- **先读**：R-BOOK-12~16；R-MEMBER-06；iOS `Views/Home/BookCustomizerView.swift`、`Shelf/CoverCropView.swift`、`Shelf/NotebookCoverStore.swift`、`Models/CoverLayout.swift`
- **要做**：预览 → 照片（选图直接进构图）→ 版式三种 → 颜色（条件出现）→ 副标题；保存时裁切烤进文件；换 / 移除 / 删本时旧文件连云端副本删
- **验收**：R-BOOK-12~16；会员锁钩子留好（7.2 接）

### 3.5 翻页阅读器

- **先读**：R-READ 全部；iOS `Reader/Paginator.swift`（版式常量在 `ReaderLayout`）、`DiaryPageHeader.swift`、`ContentPageView.swift`、`PageDataSource.swift`、`EndingPageView.swift`
- **要做**：阅读顺序（从早到晚）；分页器（按真实字体测量，首页扣页眉，照片块标称高 280）；首页页眉；续页小标题；页码；结尾页「已读完所有日记」；Swiper 翻页；从目录某篇 / 从头进入
- **不要**：独立扉页
- **验收**：长短日记各种组合，**任何一页都不截断正文**（R-READ-05）；三主题配色正确

### 3.6 大屏模式

- **先读**：R-HOME-02/06；iOS `Views/Home/ShowcaseView.swift`、`Models/JournalEntry+Showcase.swift`、`Views/Components/DominantColor.swift`
- **要做**：一屏一篇左右滑；封面照片轮播；文字区染色 + 深浅字判定；设置 → 外观「手记页」切换
- **验收**：深色夜景照片上文字清晰；没照片的日记也好看

**阶段 3 验收**：书架 → 日记本主页 → 阅读器全链路；拖书手感、封面三版式经产品确认。

---

## 阶段 4 · 账号与后端

### 4.1 网络层

- **先读**：`02_BACKEND_API.md`；Q15；iOS `Environment/HTTPClient.swift`、`URLSessionHTTPClient.swift`、`ProxyAIService.swift`（错误映射）
- **要做**：基础地址常量；JSON 请求 / 响应；鉴权头；统一错误 `{ error: { code, message }, ...extras }` 解析（429 的 `reason` / `nextLetterAt` 在**顶层**）；超时分级（寄信 90s、补领 30s、节奏 15s、其他 30s）；**日期解析认带毫秒和不带毫秒两种**；区分「断网 / 超时 / 取消」与「服务端错误」
- **验收**：单测覆盖错误映射：401 → 清登录态；429 → 节奏原因；5xx → 服务端错误；断网 → 网络错误

### 4.2 手机号登录与会话

- **先读**：R-ACCOUNT-01/02；iOS `Views/Auth/LoginView.swift`、`Environment/AuthService.swift`、`UserSession.swift`、`KeychainStore.swift`
- **要做**：登录页（11 位手机号 → 获取验证码 → 6 位码 → 登录；「未注册的手机号验证后自动创建账号」；重发倒计时）；token + 用户快照存安全存储；`GET /me` 刷新
- **验收**：登录 → 杀进程 → 仍登录；手动让 token 失效 → 任一请求 401 后回到未登录

### 4.3 账户页

- **先读**：R-ACCOUNT-03~08；iOS `Views/Settings/SettingsAccountView.swift`、`SettingsView.swift`（账户卡）、`Views/Auth/ChangePhoneView.swift`、`DeleteAccountView.swift`
- **要做**：设置一级页账户卡（未登录「登录 / 注册」；未绑手机号红色警告）；账户二级页：昵称（`PATCH /me`）、手机号（绑定 / 换绑）、退出登录、注销账号（三步流程）；绑定返回 `switchedAccount` 的处理
- **验收**：R-ACCOUNT-03~08 逐条；注销后本地日记一篇不少

### 4.4 华为账号登录（阻塞：Q1、Q17）

后端补完接口后再做：登录页主选项华为账号；已登录账号绑定华为账号；注销时撤销授权。

**阶段 4 验收**：测试手机号走完 登录 → 改昵称 → 换绑 → 退出 → 再登录 → 注销。

---

## 阶段 5 · 邮筒（产品的核心情感，慢慢做）

### 5.1 信件阶段判定 + 信箱 + 读信（普通信）

- **先读**：05 §6；R-BOX-01~04/07~10；iOS `Models/LetterDelivery.swift`、`Views/PostBox/LetterboxView.swift`、`LetterDetailView.swift`
- **要做**：五个阶段判定函数（1.3 已有单测）；信箱列表（只显示已到达，定时推进「此刻」）；读信页（「致{昵称}」抬头、正文、打开即已读）；信末会员小字（入口先留）
- **验收**：用调试入口插几封不同 `deliveredAt` 的信，到点自动出现在信箱、红点亮起

### 5.2 邮筒页：候选日记 + 状态行 + 节奏

- **先读**：R-POST-01~06、R-POST-12；iOS `Views/PostBox/PostBoxView.swift`、`Posting/PostBoxPage.swift`、`Posting/OutgoingPile.swift`、`Environment/AIService.swift`
- **要做**：邮筒插画（页面底色取插画左上像素）；「这次寄出的日记」一叠（默认全勾、可取消、超出行数在纸内滚动）；状态行按 R-POST-06 的顺序；进页面问 `GET /me/rhythm`；固定高度的下半区
- **验收**：R-POST-02~06 逐条（候选按 `createdAt` 不按 `date`；14 篇上限；退回的日记不在候选里）

### 5.3 投信 + 寄信队列

- **先读**：R-POST-07/11、R-OUTBOX 全部；iOS `Services/LetterOutbox.swift`（整份读，注释里是全部踩过的坑）
- **要做**
  1. 点邮筒 → 按 R-POST-07 落一封「写信中」→ 记入本机负责表 → 立即处理队列
  2. 队列：R-OUTBOX-02~11 全部，含**重发前先补领**、429 先补领、3 次退回、断网不算失败
  3. 回到前台 + 前台每 30 秒处理一次
  4. 退回卡片：重新寄出 / 不寄了（R-POST-11）
  5. 寄信请求的 `language` 用 5.5 的识别结果
- **不要**：等 AI 写完才算寄出；把「本机负责」写进数据库
- **验收**：单测覆盖补领匹配（±5 分钟容差、按正文去重）、重试计时、退回条件；手测：飞行模式投信 → 恢复网络后自动寄出；寄出瞬间杀进程 → 重开后不会寄两封

### 5.4 到达通知

- **先读**：R-NOTIFY 全部；iOS `Services/LetterNotifications.swift`、`Environment/AppDelegate.swift`
- **要做**：投信动画后申请通知权限；寄成功预约定时提醒（候选：后台代理提醒，注意平台对数量的限制，需核实）；回前台重排（同标识覆盖）；点通知 → 邮筒 tab → 信箱（冷 / 热启动）
- **验收**：开测试加速（见 5.8），寄一封，锁屏等到通知，点开直达信箱

### 5.5 回信语言识别

- **先读**：R-LETTERLANG 全部；iOS `Environment/LetterLanguage.swift`
- **要做**：按规则数票；简繁、en/fr/es 的细分用平台能力，**没有的话**用启发式：简体专用字 / 繁体专用字表、三种语言的高频虚词 + 重音字符；置信不足退回 App 语言
- **验收**：单测样例至少包括：「今天 meeting 好多，deadline 又提前了，真的 so tired」→ 中文；纯日文、日文含汉字、繁体、简繁同形短句（→ App 语言）、法语、西语、韩文、少于 12 字

### 5.6 投信动画、邮戳、声音、震动

- **先读**：R-POST-08~10；iOS `Posting/LetterPostingFlight.swift`（`LetterPostingTimeline` 时间轴）、`LetterPostingFeel.swift`（震动声音表）、`Postmark.swift`、`PostBoxNotes.swift`、`Views/Components/WaxSeal.swift`
- **要做**：按时间轴重做动画（平滑、无回弹）；会员火漆印面 = 昵称首字；声音 `letter_post_sealed.wav` / `letter_post_plain.wav`；震动跟着时间轴；邮戳（日期 + 地点、油墨按主题）；减弱动态效果时的替代
- **验收**：录屏给产品确认（手感项）

### 5.7 火漆信

- **先读**：R-BOX-03~06；iOS `Views/PostBox/Envelope/*`（`LetterOpeningFeel.swift` 是拆信时间轴）
- **要做**：寄出时写 `stationery`；信箱里火漆信显示为小信封、不露预览；读信页三下拆信；打碎火漆算已读；专属信纸（字一行一格落在格线上）；拆信声 `letter_open_1/2/3.wav`
- **验收**：会员到期后旧火漆信仍是火漆（R-MEMBER-07）；只看信封退出 → 仍未读

### 5.8 测试加速（仅测试包）

- **要做**：设置 → 关于 里一个「回信加速」开关（1 分钟 ≈ 1 天：6 小时 ≈ 15 秒、3 天 ≈ 3 分钟），**只在调试 / 内测包可见，正式包不存在**
- **验收**：正式构建里搜不到这个开关

**阶段 5 验收**：两周测试期内真实使用：每周寄信、等回信、拆火漆信；中途断网、杀进程、换语言，没有一封信丢失或重复。

---

## 阶段 6 · 设置与数据

### 6.1 设置结构

- **先读**：R-SETTINGS 全部；Q10；iOS `Views/Settings/SettingsView.swift`、`SettingsRow.swift`、各二级页
- **要做**：一级页按 R-SETTINGS-01 排；二级页：外观（主题选择 / 应用图标 / 启动动画 / 手记页 列表·大屏）、日记（照片相纸样式默认值）、笔友（笔友名）、位置与天气、数据与备份、关于（隐私政策 / 用户协议 / 版本 / ICP / 主办单位）；离开 tab 重置到首页；评分入口
- **不要**：封条提醒天数、同步 Live Photo 视频（死设置，Q10）
- **验收**：R-SETTINGS-01~05；R-APP-05

### 6.2 主题选择 + 主题介绍 + 应用图标

- **先读**：R-THEME-04~09；Q5；iOS `Views/Settings/ThemePickerView.swift`、`ThemeIntroSheet.swift`、`Theme/ThemePaper.swift`、`AppIconPickerView.swift`、`Environment/QuickActions.swift`
- **要做**：列表（名称 + 一句纸史副标题）；介绍弹窗（用目标主题配色渲染；纸史正文与出处取 iOS 译文，**不改写**）；图标选择（视 Q5）；长按快捷方式（视 Q5）
- **验收**：R-THEME-04~08 逐条

### 6.3 写作统计

- **先读**：R-SETTINGS-06；iOS `Views/Settings/StatsView.swift`、`Services/StatsCalculator.swift`
- **要做**：连续写作 / 总篇数 / 总字数 / 写作日历 / 心情分布（四个范围、饼图只画有数据的心情）
- **验收**：单测：连续天数（今天没写 = 0）、范围起点（近 7 天含今天）

### 6.4 备份包导入（建议提前到阶段 2 之后）

- **先读**：`modules/08_backup_package.md` 全文、`EXPORT_FORMAT.md`、R-DATA-01~03；iOS `Services/Backup/BackupImporter.swift`、`BackupCrypto.swift`、`BackupFormat.swift`、`Views/Settings/BackupImportView.swift`
- **要做**：按 08 文档「八、鸿蒙端实现顺序」六步走：明文包 → 三个 json 容错解析 → 合并（id / 名字 / 判重键 / 同名询问）→ 媒体落盘（同名不同大小改名）→ 加密包（PBKDF2-SHA256 21 万轮 + AES-256-GCM）→ 预览与结果页；从别的应用「用尺素打开」`.memoir`
- **验收**：0.1 的两个样本包都能导入，结果数字与 iOS 一致；同一个包导两次第二次全部跳过；故意删掉包里一张图 → 其余照常、汇总里报 1 张缺失；`formatVersion: 2` 的包被拒并提示更新

### 6.5 备份包导出

- **先读**：R-DATA-04；05 §0（**日期不带毫秒**）；iOS `Services/Backup/BackupExporter.swift`、`Views/Settings/BackupExportView.swift`
- **要做**：内容与体积预估 → 加密选择（默认加密，密码两次）→ 免责声明勾选 → 打包（平铺或带一层目录都行）→ 系统分享 / 存文件；「仅文字」选项；`manifest.platform = "harmony"`
- **验收**：🔴 **鸿蒙导出的包在 iOS 上导入成功**（这是双端互通的最终验收，必须真机互导一次）

### 6.6 云同步（阻塞：Q3）

结论出来之前：数据与备份页如实展示「日记只在这台设备上」+ 引导导出（R-DATA-05）。结论出来后按 R-DATA-05~07 做，**同步状态只认真实的同步成功事件**。

### 6.7 关于页与合规展示

- **要做**：隐私政策、用户协议（内置）、版本号、ICP 备案号 + 主办单位（常量文件）、测试包的回信加速开关（5.8）
- **验收**：R-APP-04/05

**阶段 6 验收**：iOS ⇄ 鸿蒙双向互导各一次，抽 10 篇逐字段比对（含格式、照片、录音、墨迹、日记本封面与版式、信件火漆）。

---

## 阶段 7 · 尺素会员（华为 IAP）

### 7.1 后端：华为凭据验证（阻塞：Q2）

后端任务：`sync-huawei` 改成真实验证 + 订阅状态通知 + 换账号恢复归当前账号，契约对齐 Apple 那套（`02_BACKEND_API.md`）。

### 7.2 付费页、状态页、入口与锁

- **先读**：`MEMBERSHIP.md`；R-MEMBER 全部；iOS `Views/Membership/*`、`Models/MembershipRules.swift`、`Services/StoreKitManager.swift`
- **要做**：付费页（R-MEMBER-04 四样必备 + 权益列表，顶部火漆 = 昵称首字）；会员状态页（方案、有效期至、管理订阅、恢复购买）；四个入口（R-MEMBER-05）；相纸与封面版式锁（R-MEMBER-06/07）；本机权益判定 + 交给服务端同步；测试期本机假开通开关
- **验收**：免费 / 会员 / 到期三种状态下，相纸、封面、信纸的表现逐条对 R-MEMBER-05~07

### 7.3 等 iOS 定稿的三样（Q11）

笔友性格、月度 / 年度回望、精装 PDF。**iOS 出 CHANGELOG 条目之前不做**。

---

## 阶段 8 · 上架前

| # | 检查 | 依据 |
|---|---|---|
| 1 | 首启同意页、同意前零请求零权限 | R-APP-01~03 |
| 2 | 鸿蒙版隐私协议 / 用户协议已由法务定稿并内置；改了正文就改版本号 | Q12、R-APP-02 |
| 3 | ICP 备案号与主办单位逐字一致 | R-APP-05 |
| 4 | App 内注销账号可用 | R-ACCOUNT-07 |
| 5 | 七种语言零漏翻（检查脚本退出码 0），权限说明七种齐 | R-LANG-04/05 |
| 6 | 协议里写的事实与实现一致：日记不上传、照片录音从不发送、只在寄信时发选中日记的文字 | `CHANGELOG` 2026-09-12 |
| 7 | 测试开关全关：服务端来信不设限、本机假开通、回信加速只在测试包 | Q14、5.8 |
| 8 | 不能对用户说「已同步」除非真的同步成功 | R-DATA-05 |
| 9 | 华为应用市场自身的审核要求（隐私声明、权限用途说明、订阅说明） | 鸿蒙团队自查 |

---

## 附录 A · 每步的开场提示词（复制给 agent）

> **agent 输入框不能粘贴时**：鸿蒙仓库根目录有一份 `TASK.md`，内容就是下面这段提示词（路径已对好）。
> 只需手敲一句：**读取 TASK.md，执行第 X.Y 步**。

```text
你在做「尺素」鸿蒙版的第 <X.Y> 步：<步骤名>。

1. 先读：docs/harmony-spec/10_BUILD_MANUAL.md 里这一步的卡片，以及卡片「先读」列出的文档和
   reference/ios/ 下的 iOS 文件（iOS 代码只读、只参考，不要逐行翻译）。
2. 只做卡片「要做」里的事；卡片「不要」里的事一律不碰。发现必须扩大范围才能完成，先停下来说明。
3. 规则以 docs/harmony-spec/06_RULES.md 为准；文档和 iOS 源码不一致时以 iOS 源码为准，
   并把不一致追加到 docs/harmony-spec/09_OPEN_QUESTIONS.md。
4. 用户可见文字一律走字符串资源，七种语言取自 iOS 译文，不要机翻。
5. 每完成一处有意义的改动就编译一次；纯逻辑写单元测试。
6. 做完：对照卡片「验收」逐条自查并汇报结果（哪些过了、哪些需要真机 / 产品确认），
   然后在 PROGRESS.md 勾掉这一步、写下与 iOS 的偏差。
```

## 附录 B · 进度表模板（`PROGRESS.md`）

```markdown
| 步骤 | 状态 | 负责人 | 完成日期 | 与 iOS 的偏差 / 备注 |
|---|---|---|---|---|
| 0.4 物料转换 | ⬜ | | | |
| 1.1 主题系统 | ⬜ | | | |
| 1.2 多语言 | ⬜ | | | |
| 1.3 数据层 | ⬜ | | | |
| 1.4 媒体存储 | ⬜ | | | |
| 1.5 首启 | ⬜ | | | |
| 1.6 主框架 | ⬜ | | | |
| 2.1 写日记 v1 | ⬜ | | | |
| 2.2 记录页 | ⬜ | | | |
| 2.3 详情页 | ⬜ | | | |
| 2.4 编辑页 | ⬜ | | | |
| 2.5 图文格式 | ⬜ | | | |
| 2.6 照片 | ⬜ | | | |
| 2.7 录音 | ⬜ | | | |
| 2.8 墨迹会干 | ⬜ | | | |
| 2.9 相机 | ⬜ | | | |
| 2.10 此时此地 | ⬜ | | | |
| 3.1 书架 | ⬜ | | | |
| 3.2 拖书 | ⬜ | | | |
| 3.3 日记本主页 | ⬜ | | | |
| 3.4 封面编辑 | ⬜ | | | |
| 3.5 阅读器 | ⬜ | | | |
| 3.6 大屏 | ⬜ | | | |
| 4.1 网络层 | ⬜ | | | |
| 4.2 登录 | ⬜ | | | |
| 4.3 账户页 | ⬜ | | | |
| 4.4 华为账号 | ⛔ Q1 | | | |
| 5.1 信箱读信 | ⬜ | | | |
| 5.2 邮筒页 | ⬜ | | | |
| 5.3 寄信队列 | ⬜ | | | |
| 5.4 到达通知 | ⬜ | | | |
| 5.5 语言识别 | ⬜ | | | |
| 5.6 投信动画 | ⬜ | | | |
| 5.7 火漆信 | ⬜ | | | |
| 5.8 测试加速 | ⬜ | | | |
| 6.1 设置结构 | ⬜ | | | |
| 6.2 主题与图标 | ⬜ | | | |
| 6.3 统计 | ⬜ | | | |
| 6.4 导入 | ⬜ | | | |
| 6.5 导出 | ⬜ | | | |
| 6.6 云同步 | ⛔ Q3 | | | |
| 6.7 关于 | ⬜ | | | |
| 7.1 华为验证（后端） | ⛔ Q2 | | | |
| 7.2 会员 | ⬜ | | | |
| 7.3 三样新权益 | ⛔ Q11 | | | |
| 8 上架前 | ⬜ | | | |
```

## 附录 C · iOS 截图清单（iOS 团队提供）

每张**三套主题各一张**（素笺 / 皮革 / 肯特），真机、中文界面；标 ★ 的再补一张英文界面。

| # | 画面 |
|---|---|
| 1 | 协议同意页 ★ |
| 2 | 引导页 |
| 3 | 记录页 · 列表模式（有日记）★ / 空状态 |
| 4 | 记录页 · 大屏模式（有照片 / 没照片各一张） |
| 5 | 写日记页（含照片、录音、格式、此时此地）/ 返回确认框 / 草稿恢复提示 |
| 6 | 日记详情（素笺和纸版式、其余普通版式）/ 有补记、有划掉的字 |
| 7 | 照片全屏页 + 「⋯」菜单；相纸选择器（六种） |
| 8 | 书架 / 拿起一本时（录屏） |
| 9 | 日记本主页：满版 / 白框 / 贴照片 / 纯色 / 空本子；目录列表与宫格 |
| 10 | 封面编辑器、构图页 |
| 11 | 阅读器：首页页眉、续页、结尾页 |
| 12 | 邮筒页：可寄（日记一叠）/ 在路上（邮戳）/ 节奏拦截 / 退回卡片 / 未登录；投信过程（录屏）|
| 13 | 信箱（有未读、有火漆信）/ 普通信 / 火漆信拆信过程（录屏）|
| 14 | 设置一级页（登录且未绑手机号的红色警告态）及全部二级页 |
| 15 | 主题介绍弹窗（三种）★ |
| 16 | 付费页 ★ / 会员状态页 |
| 17 | 登录页、账户页、注销三步 |
| 18 | 备份导出、导入预览、导入结果、同名日记本询问 |
| 19 | 写作统计 |
