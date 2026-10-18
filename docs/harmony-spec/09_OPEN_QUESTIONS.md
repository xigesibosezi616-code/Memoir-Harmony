# 09 · 待决事项与阻塞

> 开工前**先过一遍这张表**。🔴 = 会卡住某个阶段，到那一步之前必须有结论；🟡 = 影响设计，做到那一步时要定；⚪ = 知道就行。
>
> 有结论了：在「结论」栏写上日期和结论，并同步改受影响的文档（05 / 06 / 10）。
> 鸿蒙端发现新的问题，**追加到表尾**，编号接着往下排。

| # | 级别 | 事项 | 卡哪一步 | 谁来定 | 结论 |
|---|---|---|---|---|---|
| Q1 | 🔴 | 后端 **`POST /auth/huawei`、`POST /me/bindings/huawei` 未实现** | 4.4 华为账号登录 | 后端 | |
| Q2 | 🔴 | `POST /subscription/sync-huawei` **只是占位**（只落库、不验证），华为 IAP 产品 ID 也没建 | 7.x 会员 | 后端 + 产品 | |
| Q3 | 🔴 | 鸿蒙**云同步用什么** | 6.6 云同步 | 产品 + 鸿蒙 | |
| Q4 | 🟡 | 回信的**到达时刻、已读状态只在客户端** | 5.x 邮筒 | 产品 + 后端 | |
| Q5 | 🟡 | 鸿蒙能否**动态切换桌面图标**、能否**代码登记长按快捷方式**（标题跟 App 语言） | 6.2 主题与图标 | 鸿蒙调研 | |
| Q6 | 🟡 | **Georgia 字体授权** | 1.1 主题系统 | 产品 | |
| Q7 | 🟡 | 天气图标标识 `weatherCode` 的**跨端词表** | 2.10 此时此地 | 鸿蒙 + iOS | |
| Q8 | 🟡 | 鸿蒙的**天气数据源** | 2.10 此时此地 | 产品 + 法务 | |
| Q9 | ⚪ | 笔友名只存本地 | — | — | 照 iOS |
| Q10 | ⚪ | iOS 设置里的**三个死设置** | 6.1 设置 | 产品 | |
| Q11 | 🟡 | 会员四样专属里**三样 iOS 也还没做** | 7.3 | 产品 | |
| Q12 | 🔴 | **隐私协议 / 用户协议的鸿蒙版** | 1.5 首启 · 8 上架 | 法务 | |
| Q13 | 🟡 | **动态照片**跨端互通 | 2.9 相机 · 6.4 导入 | 鸿蒙调研 | |
| Q14 | ⚪ | 测试开关（来信不设限、假开通会员） | 8 上架 | — | 上架前关 |
| Q15 | ⚪ | 后端域名 | 4.1 | 运维 | |
| Q16 | ⚪ | 「内容审核没过」**后端没有专门的错误码** | 5.3 | 后端 | |
| Q17 | ⚪ | 接华为账号后，**注销时撤销华为授权** | 4.4 | 后端 | |
| Q18 | ⚪ | 鸿蒙**包名 / 应用市场主体** | 0.3 | 产品 | |
| Q19 | 🟡 | 正文小图加载**不放大**（iOS `loadImage` 的 `preparingThumbnail` 会把小图放大到 600） | 2.6 照片相纸 | 鸿蒙 + 产品 | |
| Q20 | 🟡 | **智感握姿实现路径**：`HdsTabs` 不在本 SDK（26），自行用 motion `operatingHandChanged` + `ACTIVITY_MOTION` 实现 | 1.6 主框架 · 真机验收 | 鸿蒙 | 2026-10-15 整体移除：Tabs 系统底栏无横移落点，且 SDK 权限清单证实 `DETECT_GESTURE`（normal + system_grant）后 `holdingHandChanged` 也只是普通权限——智感握姿收益存疑，服务、权限声明、理由文案全部删除（git 历史可寻回），真机验收 `operatingHand` 授权率与灵敏度后若确需再重启 |
| Q21 | ⚪ | 全局 toast 的 kind：文档卡片只写两种，iOS 源码是三种（error/info/success） | — | — | 2026-10-14 照 iOS 三种 |
| Q22 | ⚪ | 2.1 卡片写心情「单选**可取消**」，iOS `MoodSelector` 点已选心情**不取消**（点了始终选中） | 2.1 写日记页 | 产品 | 2026-10-15 按 iOS 源码不可取消实现（CLAUDE.md：iOS 源码优先；用户已确认）。产品若想要「再点一下取消」，iOS 侧要一起改 |
| Q23 | 🔴 | **文字绕排做不到**：RichEditor 无 exclusion 机制，锚点图片无法让文字绕排（iOS `Text` + `imageTextInitializer` 可以）；**荧光笔画法偏差**：`textBackgroundStyle` 只能整块色底，画不出 iOS 「只压文字中下部的圆头条」 | 2.6 照片相纸 · 2.5 荧光笔观感 | 产品 | 2026-10-17 **绕排破局**：graphics.text `headIndents/tailIndents`（API 26）逐行缩进 + 自研 `WrapFlowEngine`（单测全绿）；**详情页阅读态真机验证通过**（绕排/两端对齐/荧光/照片全屏，CustomSpan invalidate 不重测须换新 span、punctuationOverflow SDK 缺席两条实测）。**编辑态方案已定：B1 隐形输入层**（2026-10-17 用户拍板——编辑页实测整行卡换行推下移体验割裂；1px 透明 RichEditor 承接 IME + 自绘光标/选区，任务卡 10 手册 2.5b）；**M1 组件级已完成**（RichDocEditor/diffTextEdit/textBlockRangesOfBlocks/WrapFlowEditor，单测 272 全绿，2026-10-17；**勘误**：`getGlyphPositionAtCoordinate`（since 12）存在，此前「graphics.text 无坐标→偏移 API」结论有误，命中查询无需自算字形）；**M1 收官（2026-10-17）**：页面接入+真机 E2E ✓、光标「落 0」疑案结案（verify_ui 注入例程「全选→清除→输入」×锚点保护交互，非 bug）、空态塌缩补修（max 高度+占位段+空文档光标）、**平台缺陷实证+追修**：`orphanCharOptimization` × `strutStyle` 时恰好 2 行的段落 `paint()` 零输出（1/3/4 行正常，探针矩阵二分实证，查无已知限制）——移除 orphanCharOptimization 规避，真机 2 行态回归 ✓；**M1 追修三（2026-10-18）**：heading `\n` 行段拆分（TextPart/BuiltItems sidecar/caret 区间映射重写）真机 ✓（H 段 21.12vp / B 段 16.32vp 分段正确），顺带双修 EditEntryView 日期行过期（`@State entry`）与标题注入竞态（双信号）；荧光笔圆头条（Run 字形自绘）真机观感后议。**结案（2026-10-18 产品拍板）：三页回退华为备忘录式，绕排下线保留**——平台缺陷连环修不见底（orphanCharOptimization×strut 两行零输出、strut 实测行高 16.32≠20vp 需探针自愈、heading 编辑器合并污染拆段追修三轮），ComposeView/EditEntryView/EntryDetailView 全部换回 2.5/2.6 备忘录形态（RichBodyEditor+工具条+照片链路，真机三页冒烟 ✓）；WrapFlow 全家桶+278 单测下线保留（页面零引用未删）；未建成功能与恢复条件建档 `11_UNBUILT_FEATURES.md`。本问状态改 🔴（回退定型，备忘录式=终态方案） |
| Q24 | ⚪ | 详情页「补记 N 次」行**暂不渲染**：块级 writtenAt 在 2.5 编辑器读不回（RichEditor 样式装不下自定义时间戳），编辑保存一轮后补记信息会丢 | 2.5 详情页 | 产品 + 鸿蒙 | 先按 R-ENTRY-14「没补记过不显示」实现（恒不显示）；2.8 墨迹会干接交互时在保存链路合并回 writtenAt / struckAt |
| Q25 | ⚪ | **老日记录音补进正文**（R-RICH-09）：2026-10-10 之前的日记录音在正文外面（audioURLs 列），打开编辑时要就地转成正文里的录音块 | 2.8 录音 | 鸿蒙 | 纯逻辑已备好（`blocksWithLooseAudio` + 单测）；2.8 接录音块渲染时挂进 EditEntryView 装载链路 |
| Q26 | 🔴 | **bindContentCover 真机「隐形挂载」**：全屏照片查看用 bindContentCover，真机出现 appear 日志齐全但零渲染、吞掉整页触摸（dt=163552ms）的幽灵态；且 EditEntryView 同时 bindSheet+bindContentCover 双绑属 API 违规用法 | 2.6 全屏查看 | 鸿蒙 | 2026-10-17 弃用 bindContentCover：三页改**页面内条件浮层**（根 Stack 末位 if(showPhotoFullscreen)，同层最高）。根因未深挖（疑模态子窗口层丢失）；教训：模态类 API（bindContentCover/bindSheet）同一节点只绑一个，全屏沉浸浮层优先用页面内浮层（可嵌自定义转场、可与其他 UI 联动，如 Tab 栏 barOpacity） |
| Q27 | ⚪ | **真机验证方法论教训（「关全屏白屏」疑云结案）**：曾判定「关闭全屏后整页白屏」并二分删除 transition/barOpacity/hideTitleBar——全部误报 | 验收流程 | 鸿蒙 | 2026-10-17 结案：**像素采样伪象**。`sips` 转 BMP 是负高度 top-down 行序，采样脚本按 bottom-up 公式翻转导致所有采样点垂直镜像（页面照片/Tab 栏位置全采错成背景白区）；dumpLayout 组件树一直完好。教训：①截图判位必须先用已知参照物（状态栏文字、照片区域）校验采样坐标映射；②「白屏」类结论需 dumpLayout（树）+ 像素分布对比（与正常帧 white/dark/colored 占比一致=同页）+ 无诱导语的模型看图三重交叉；③真机注入双击用单次调用链式 down/up（`uinput -T -d x y -u x y -d x y -u x y`，实测间隔 ~45ms；两次独立 uinput ~350ms、uitest doubleClick ~640ms，都超 280ms 双击窗）；④长 E2E 前先 `power-shell timeout -o 600000` 防自动锁屏（锁屏后 dump 有树但截屏全黑） |

---

## 详细说明

### Q1 🔴 华为账号登录接口未实现

后端只有 `/auth/send-code`、`/auth/verify-code`、`/auth/apple`、`/auth/third-party`（微信，v1 不做）。
**鸿蒙 v1 先只做手机号登录**（今天就能用，iOS 也是这套）。华为账号要等后端补：
`POST /auth/huawei { idToken }` → 验证 → 颁发 JWT；`POST /me/bindings/huawei` 契约照搬 Apple 那套。
⚠️ 有了华为登录之后，手机号必绑的警告（R-ACCOUNT-03）一样要做。

### Q2 🔴 华为 IAP

- 服务端 `sync-huawei` 现在**不验证凭据**，直接接华为 IAP 等于可伪造发货。要按 Apple 那套补：服务端验证华为购买凭据、只认会员产品、换 App 账号恢复购买归当前账号、接华为订阅状态通知
- 产品 ID：建议和 iOS 同名（`com.sinaratech.memoir.plus.yearly` / `.monthly`），以华为后台规则为准
- 价格与优惠：年付首年 ¥58 / 之后 ¥88、月付 ¥12、无试用、无家人共享（`MEMBERSHIP.md`）
- 在这之前，鸿蒙可以做一个**本机测试开关**假开通会员（同 iOS `StoreKitManager.testUnlock`），**不要做进服务端**

### Q3 🔴 云同步方案

iOS 用 CloudKit 私有库（数据在用户自己的 iCloud，我们看不到）。隐私协议对用户承诺的是
「日记只存在本地和**用户自己的云**，我们的服务器拿不到」。所以：

- ❌ **不能**用开发者侧的云数据库（例如 AppGallery Connect 云数据库）存日记 —— 那是数据进了我们的项目，违背承诺
- 候选：用户私有的华为云空间类能力（需调研是否存在、是否「我们看不到」）；系统备份 / 设备克隆（应用数据随系统备份走）；或 v1 **纯本地 + 备份包**
- **在有结论之前，鸿蒙按「纯本地 + 备份包」做**，设置 → 数据与备份 里如实写「日记只保存在这台设备上，卸载会丢失，请定期导出备份」（R-DATA-05：不许让用户误以为已上云）

### Q4 🟡 到达时刻 / 已读只在客户端

后端 `letters` 表没有到达时刻列，`GET /letters` 会返回还在路上的信；已读也只记本地（iOS 不调 `POST /letters/:id/read`）。影响：

- 单端使用：没影响（补领规则 R-OUTBOX-09 会按服务端写信时刻重算到达时刻）
- **同一账号 iOS 和鸿蒙都用**：鸿蒙补领到 iOS 寄的信，会按**自己的随机数**算到达时刻，两台设备到达时间不同；已读状态两边各算各的
- 彻底统一需要后端加一列到达时刻并在列表接口过滤。产品决定要不要做；**不做的话鸿蒙照 iOS 现状实现**

### Q5 🟡 桌面图标与快捷方式

iOS：每个主题一张桌面图标，可「跟随主题」或手动固定；桌面长按菜单有「应用图标」直达。
鸿蒙先确认平台有没有对应能力。没有的话：设置里「应用图标」、主题弹窗里的图标那一段、长按快捷方式**整套不做**（R-THEME-09），弹窗按钮只留「更换主题」。

### Q6 🟡 Georgia 字体

iOS 的标题、正文大量用 Georgia（系统自带）。**Georgia 是商业字体，打包进鸿蒙 App 需要授权**。
候选：开源衬线字体（OFL 许可的西文衬线 + 思源宋体 / Noto Serif CJK 这类中文衬线），或 HarmonyOS 自带衬线。
产品定之前，代码里把字体集中成主题 token（`titleFont` / `bodyFont` …），换字体只改一处。

### Q7 🟡 `weatherCode` 跨端词表

iOS 存的是 Apple 天气给的 SF Symbols 名（`sun.max.fill`、`cloud.rain` …）。鸿蒙存自己的标识的话，备份包互导时对方认不出。
**建议**：把 SF Symbols 名当跨端词表 —— 鸿蒙写入时把自己的天气现象映射成最接近的 SF Symbols 名，读取时再映射到自己的图标；认不出的显示通用天气图标。需要 iOS 侧导出一份它实际会写出的名字清单。

### Q8 🟡 天气数据源

iOS 用 WeatherKit，位置只发给 Apple、不经我们服务器。鸿蒙选系统能力或第三方都行，但**用第三方就意味着坐标发给了它**，隐私协议第三方清单要加上（Q12）。

### Q9 ⚪ 笔友名

本地偏好 `penPalName`（默认「青鸟」），寄信时随 `POST /letter` 发给服务端；后端 `users.pen_pal_name` 存在但 iOS 从不写它。鸿蒙照 iOS：**以本地为准**。

### Q10 ⚪ iOS 的三个死设置

| 设置项 | iOS 现状 | 建议 |
|---|---|---|
| 日记 → 封条提醒天数（10/14/21/30） | 存了值，**没有任何地方读** | 鸿蒙不做 |
| 数据与备份 → 同步 Live Photo 视频 | 开关**不生效** | 鸿蒙不做 |
| 日记 → 日记印章（天气 / 心情图标 / 自选表情 / 不显示） | 只影响写日记页「是不是自动取天气」；印章实际显示规则固定（R-ENTRY-16） | 待产品决定，倾向不做 |

### Q11 🟡 会员三样未完成

笔友性格、月度 / 年度回望、精装 PDF —— iOS 付费页已经在宣传，但功能**还没做**（`MEMBERSHIP.md` 进度表 6–8）。
鸿蒙**等 iOS 出 CHANGELOG 条目后再做**；付费页的权益列表与 iOS 保持一致。

### Q12 🔴 鸿蒙版法律文本

iOS 的隐私协议写的是 Apple 登录、iCloud 同步、Apple 天气、Apple 支付。鸿蒙要一份**事实相符**的版本
（华为账号、云同步方案（Q3）、天气数据源（Q8）、华为支付、鸿蒙权限名称），由**法务**出，agent 不改写法律文本。
另：iOS 版里公司注册地址还是「待填」占位，上架前要填。

### Q13 🟡 动态照片

iOS 的 Live Photo = 静态图 + `.mov`，靠图片元数据里的标识配对。鸿蒙有自己的动态照片能力，格式未必互通。
**最低要求**：iOS 导出的包在鸿蒙上至少能显示静态图（R-PHOTO-04）；鸿蒙导出的动态照片在 iOS 上至少显示静态图。
能不能互相播放，鸿蒙调研后定。

### Q14 ⚪ 测试开关

服务端 `LETTER_RHYTHM_OFF=1`（来信不设上限）和 iOS 的假开通会员都在测试期打开，**鸿蒙测试时看到来信不设限是预期**，不是 bug。上架前关（iOS 上架清单 A0c）。

### Q15 ⚪ 后端域名

iOS 当前用阿里云函数计算的系统域名：`https://memoir-api-cn-ecdrwvhwac.cn-hangzhou.fcapp.run`；
备案域名 `https://api.sinaratech.com.cn` 还没切。鸿蒙写成**一个常量**，切换时只改一处。只接大陆后端，不做区域判断。

### Q16 ⚪ 内容审核错误码

iOS 定义了「日记内容未通过审核，这次没能寄出」，但服务端目前**不会**返回专门的错误码（模型拒绝会以 `ai_failed` 502 返回）。
鸿蒙先按 502 处理（重试 3 次后退回）；后端加了专门的 code 后，改成直接退回。

### Q17 ⚪ 注销时撤销华为授权

接了华为账号（Q1）之后，注销账号时服务端要像 Apple 那样撤销授权，需要后端加分支。

### Q18 ⚪ 包名与主体

旧文档建议 `com.sinaratech.memoir.harmony`。以华为 AppGallery Connect 实际创建的为准，主体是玄纳司（西安）科技有限公司。

### Q19 🟡 正文小图加载不放大

iOS `PhotoPaperIO.loadImage` 用 `preparingThumbnail(of: 600×600)` 解码，**小于 600 的图会被放大**；
`loadCoverImage` 则明确判断了「原图比目标小就别放大」。鸿蒙侧（1.4 `PhotoPaperIO.ets`）统一**不放大**：
省内存、小图更清晰，但与 iOS 的正文小图行为不一致（iOS 放大后的图会更糊）。
做 2.6 照片相纸时真机对比两边观感，若要与 iOS 逐像素一致再改 `decodeFit` 的缩放策略。

### Q20 🟡 智感握姿实现路径

HarmonyOS 6 官方「智感握姿」推荐用 `HdsTabs`（HDS 组件库），但本工程 SDK（API 26，hmos-clt 7.26.8）
**没有该组件**（hds 仅有 ActionBar/ColorPicker/SideBar/SideMenu/SnackBar 等）。
2026-10-14 曾自研落地：`@ohos.multimodalAwareness.motion` 的 `on('operatingHandChanged')`
（API 15+，phone）+ `ACTIVITY_MOTION` 权限驱动浮动胶囊底栏横移。

2026-10-15 **整体移除**：
1. 主框架改用 ArkUI Tabs 系统底栏（`.systemMaterial` 对齐 iOS `.thinMaterial`），底栏由系统绘制，无横移落点；
2. SDK 权限清单证实 `DETECT_GESTURE` 为 normal + system_grant（三方声明即授予），`holdingHandChanged`
   并非高门槛——此前暂缓理由不成立，但同时也说明该能力并无稀缺价值；
3. 智感握姿收益（单手够 tab）在四 tab 大图标场景下存疑，而成本是首启多一个权限弹窗。
服务文件、单测、`ACTIVITY_MOTION` 权限声明、七语言理由文案全部删除（git 历史可寻回）。
若真机验收阶段产品确认需要，再重启评估（届时优先核实 `HdsTabs` 在新 SDK 的可用性）。

### Q21 ⚪ 全局 toast 的 kind 数量

10_BUILD_MANUAL.md 1.6 卡片只写了 error / info 两种；iOS `ErrorPresenter.Kind` 实际是
error / info / success 三种（`ErrorToastView` 三色：赭红 / 墨灰蓝 / 橄榄绿）。
以 iOS 源码为准做三种（冲突时 iOS 源码 > 文档），`ErrorToastKind` 枚举三值齐全。

### Q23 🟢→🟡 文字绕排做不到 / 荧光笔画法偏差（绕排真机验证通过，2026-10-17）

2.5 开工前技术验证（2026-10-16，静态 + SDK 源码核实）：

- **文字绕排**：ArkUI `RichEditor` 没有 iOS `NSTextLayoutManager.exclusionPaths`
  等价的绕排机制；`addBuilderSpan` / 图片 span 都是**行内占位**，做不到「文字绕着照片流」。
  影响 2.6 照片相纸：iOS 的「照片嵌在文字流里、左右绕排」退化为
  **照片整行卡片 + 上下独立文字段**（贴近华为备忘录的插入卡片）。
  需要产品确认退化方案，或 2.6 换自绘排版（成本高）。
- **荧光笔画法**：RichEditor 的 `textBackgroundStyle`（色底 + 圆角）作用于整个行框，
  画不出 iOS 「只压文字中下部、随字流断段的圆头条」。2.5 先用整块色底
  （三主题各配 iOS 同款荧光色，圆角随字号推导），真机观感不满意再议
  （候选：2.8 后用自绘渲染层重画荧光条）。

**破局（2026-10-17，R-RICH-02 攻坚）**：RichEditor 确实做不到，但
`@ohos.graphics.text`（API 26，targetSdkVersion 26.0.0、Mate X6 真机 API 26 全支持）有官方绕排原料：
`ParagraphStyle.headIndents / tailIndents`（**逐行首/尾缩进数组**，行号超数组取末位）——
照片左/右侧时对遮挡行给「照片宽+间距」的逐行缩进，文字自然绕开照片流；
配套 `align: TextAlign.JUSTIFY`（CJK 两端对齐）、`orphanCharOptimization`（zh 孤字优化）、
`autoSpace`（中西文自动间距）——排版质量可超 iOS
（TextKit 默认无孤字/悬挂/两端对齐组合）。字形定位（荧光笔圆头条用）：
`Paragraph.getTextLines()` → `TextLine.getGlyphRuns()` → `Run.getPositions()/getAdvances()/getStringRange()`。
自研 `WrapFlowEngine`（纯逻辑，`WrapFlowModel.ets` + `WrapFlowEngine.ets`，单测 14 例全绿）：
照片几何先验已知（宽 46%×比例→高，无循环依赖）→ 一次顺序扫描收敛（iOS 需迭代 4 次）；
锚定语义同 iOS（照片浮锚定段首行+4，比锚定段高时跨段续排，同车道多照片全局串联防重叠）。

**阶段一收口（2026-10-17，详情页阅读态真机验证通过）**：渲染层
`WrapFlowTextAdapter.ets`（vp↔px 适配 + JUSTIFY/孤字/autoSpace + strutStyle 强制行高 +
荧光笔 TextStyle.backgroundRect）+ `WrapFlowView.ets`（CustomSpan 自绘文字、
照片卡组件叠 Stack）落地；Mate X6 E2E：绕排/两端对齐（像素级行尾一致）/heading/
荧光笔/粗体/照片全屏/比例异步重排全过，243 单测全绿。
**真机实测两条硬约束**：① `CustomSpan.invalidate()` 只重绘不触发 Text 重测
（API 26），尺寸变化必须换新 span 走 `setStyledString`（`WrapFlowView.relayout` 已按此实现，
任何复用 CustomSpan 的场景同坑）；② `ParagraphStyle.punctuationOverflow` 文档有、
SDK d.ts 未含，标点悬挂缺席（trailingSpaceOptimized/orphanCharOptimization/autoSpace 可用）。
遗留：编辑态（写/编页）绕排方案阶段二定；荧光笔圆头条（Run 字形定位自绘）真机观感后议。

**阶段二 M1 收官（2026-10-17，编辑态组件+页面接入+真机 E2E）**：`WrapFlowEditor`
（隐形层 diff 模式）接入 ComposeView/EditEntryView（换 RichBodyEditor，bodyLoaded
条件渲染防未装载闪烁）；Mate X6 真机三例验证光标链路全对（点正文/点绕排区/点全宽段 →
命中 → setCaretOffset → 插入位置逐一吻合，hilog 5 点诊断日志；注入通道
`uitest uiInput text/inputText`，`uinput -K` 此设备实测无效弃用）。**「光标落 0」
疑案结案（非 bug）**：verify_ui 的文字注入例程是「全选→清除→输入」，全选删除被锚点
保护 aboutToDelete 正确拦截（否则整篇+照片被删），选区塌缩至 0，后续插入自然落
offset 0——组件链路无缺陷，后续 E2E 断言不可依赖 verify_ui 的注入位置。
**补修真缺陷（空态塌缩）**：`WrapFlowEngine.layout([])` totalHeight=0 → 新建日记
（draftBlocks=[]）/删光正文后 Text/Stack 0 高度不可点；修复：spanMeasure 高度
max(totalHeight, 3×正文行高) + 空文档绘制占位段（复用 s_74bd07ef78「今天，我想说...」）
+ 空文档光标 (0,0) 一行高（WrapFlowTextAdapter 新增 buildPlaceholderParagraph），
真机新建日记全链路（占位→点正文→输入→渲染）验证 ✓；非空内容渲染回归零影响。

**阶段二 M1 追修（2026-10-17，平台缺陷实证：「首段恰好两行整段消失」）**：
真机打字跨入第 2 行时 A 段 paint 零输出，继续输入到 3 行又恢复。像素取证 +
spanDraw 内联探针矩阵（同一样本 × ParagraphStyle 变体逐项二分，避开卡片/文档 A
墨/剪贴板条三大污染源）锁定：**`orphanCharOptimization: true` × `strutStyle` 并存
时恰好排版成 2 行的 `Paragraph.paint()` 零输出**（1/3/4 行正常；strut+orphan ✗ /
strut+trailingSpace ✓ / strut+autoSpace ✓；与文档态、绘制偏移、段落内容无关——
纯段落内禀；`devecocli docs` 查无已知限制记录）。修复：buildParagraph 移除
`orphanCharOptimization`（孤字优化弃用；trailingSpaceOptimized/autoSpace 保留，
对齐 JUSTIFY/strut 行高不动），真机 31 字 2 行态回归 A 段 12335 暗 px（修复前 0）✓，
1/3/4 行态、阅读态（同 adapter 同步生效）、单测 272 全绿不受影响。若未来平台修复
该缺陷可评估回补孤字优化。
**阶段二 M1 追修二（2026-10-18，绕排坐标链断裂：照片漂移+遮字）**：用户反馈
「有时输入推着照片走、照片遮挡文字」。根因＝引擎行带几何按参数行高（正文 20vp）
推演，而实绘行距 16.32vp——**strutStyle.forceHeight 与 TextStyle.heightScale/halfLeading
在该平台（API 26 真机）实测均不生效**（PROBE5 探针段落 h=102/153=51px/行铁证，
参数应为 62.5px/行）。后果：段前文字每行实绘比引擎少 3.68vp → 照片与上文空隙
逐行累积（「被推走」）；照片跨段遮挡时行带按 20vp 切、实绘按 16.32vp 压缩 →
照片底缘附近行实绘落在照片内却未缩进（「遮字」）。修复：引擎行带几何改为消费
**实测行距**——`TextLayoutAdapter` 新增 `measurePitch(isHeading)`（生产适配器单字
探针段落实测+每样式缓存；测不到回退参数行高，平台未来修复 strut 时自动回到 20vp，
自愈），`WrapFlowEngine.layout` 的 y 推进/遮挡行带/照片锚定全部换用实测值。
单测新增 6 例（实测行距推进/遮挡带切分/跨段续排/文末照片贴合/回退；MockAdapter
补 measurePitch，原 14 例数值不变）。真机回归（w1/w4 像素取证）：A 2→3 行照片顶
764.4→815.6px 恰移一行实绘 pitch（修复前漂移 11.4vp/行）、gap 恒 4vp+leading、
B 绕排让位带 0 渗漏、LAYOUT-ACT 实绘段高与引擎游标完全一致。
**M1 追修三（2026-10-18，heading \n 行段拆分）**：编辑态 u1 实测 B 段（106 字）
整段 heading 字号——根因=编辑器 doc 把相邻文本块以 \n 合并成单块渲染，heading
样式段级生效（DB 实况修正：heading 是独立文本块、块内无 \n，\n 合并只发生在
blocksWithEditorDocument 的 doc 拼接）。修复=「\n 行拆分+sidecar 映射」：
`WrapFlowModel.TextPart`/`textPartsOfBlock`（\n 拆段+runs 切片平移全量拷贝+
逐段 isHeading）→ 适配器 `segmentsOf/styleForSegment` heading 分支
（headingFontPx/headingLinePx）→ 编辑器 `BuiltItems` sidecar（items/parts/
blockIdxs 平行数组按 itemIndex 直查，防多段块计数漂移）+ `RenderParagraph.length`
语义（modelStart=块区间起点+行段起点）+ caretSegmentOf/hitTestOffset 区间映射
重写（rp.modelStart..+length）；阅读态（块独立无 \n）零影响。单测 +6（278 全绿）。
真机回归：LAYOUT-ITEMS 拆 5 项（T"夏日的午后"H 独立、body B）、LAYOUT-PARAS
lh 21.12/16.32vp、光标 hit=35 映射 ✓、hidden len=181 ✓；部分行内 heading 一行内
混排几何近似，观感后议。**顺带双修 EditEntryView（回归中发现的既有缺陷）**：
① 日期行过期——`this.entry` 普通字段不进 build 依赖追踪，日期 Text 初帧取
Date.now() 后永不刷新（编辑历史日记恒显当天）；改 `@State entry`（详情页同款）
+ `dateLineText()` 空串守卫。② 标题注入竞态——`injectedTitle` 单边
（onReady/loadEntry）先到即消费，空标题锁死真标题（本机 onReady 恒先到）；
改双信号到齐（`entryLoaded`）才注入。**像素取证方法论教训**：阈值采样（150）
恰漏 textTertiary 浅棕（min 153）+粗行距 →「详情页部分渲染」误判一轮（实际
渲染完全正常）；正解=逐行 min 亮度无阈值全扫 + 多模态交叉验证。
遗留：M2 选区/手柄/双击选词/工具条四灯，M3 照片编辑态联动+保存链路，M4 全量验收
（10 手册 2.5b）。

### Q24 ⚪ 详情页「补记 N 次」暂不渲染

补记判定依赖块级 `writtenAt`（`Ink.isAddendum`），而 2.5 的编辑器读回链路
（`RichBodyController.currentDocument`）从 RichEditor span 还原不出 writtenAt——
RichEditor 的文字样式模型装不下自定义时间戳。经编辑页保存一轮后块上的
writtenAt / struckAt 会丢（正文文字不丢）。

- 2.5 范围内：详情页按 R-ENTRY-14「没补记过不显示」恒不渲染该行（与现状一致）；
- 2.8 墨迹会干接交互时：编辑器侧存活动态格式映射，保存链路把 writtenAt / struckAt
  合并回块，补记行恢复渲染。

### Q25 ⚪ 老日记录音补进正文（R-RICH-09）

2026-10-10 之前的日记（含 iOS 互导的包）录音都在正文外面的 `audioURLs` 列里。
R-RICH-09 要求打开编辑时就地转成正文里的录音块。纯逻辑已就位
（`ContentBlock.blocksWithLooseAudio` + `ContentBlock.test.ets` 单测），
2.8 做录音块渲染时挂进 `EditEntryView` 的装载链路即可。
