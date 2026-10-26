# 09 · 待决事项与阻塞

> 开工前**先过一遍这张表**。🔴 = 会卡住某个阶段，到那一步之前必须有结论；🟡 = 影响设计，做到那一步时要定；⚪ = 知道就行。
>
> 有结论了：在「结论」栏写上日期和结论，并同步改受影响的文档（05 / 06 / 10）。
> 鸿蒙端发现新的问题，**追加到表尾**，编号接着往下排。

| # | 级别 | 事项 | 卡哪一步 | 谁来定 | 结论 |
|---|---|---|---|---|---|
| Q1 | ✅ | 后端 **`POST /auth/huawei`、`POST /me/bindings/huawei` 未实现** | 4.4 华为账号登录 | 后端 | **2026-10-25 真机全通，结案**：AGC 密钥已配齐，`POST /auth/huawei` 实测返回 AuthResponse（Mate X6 静默再授权登录闭环 U02-1 ✓，后端解析 idToken 出昵称「你好」）。剩余尾巴在 Q17（/me/delete 华为分支 500）、Q38（/me/bindings/phone 500）与绑定行 E2E（需「已登录未绑华为」账号——当前账号建号即绑恒已绑，需第二手机号 SMS 建新号，U02-2 客户端 authorize 已修见 4.4 卡） |
| Q2 | 🔴 | `POST /subscription/sync-huawei` **只是占位**（只落库、不验证），华为 IAP 产品 ID 也没建 | 7.x 会员 | 后端 + 产品 | |
| Q3 | 🔴 | 鸿蒙**云同步用什么** | 6.6 云同步 | 产品 + 鸿蒙 | |
| Q4 | 🟡 | 回信的**到达时刻、已读状态只在客户端** | 5.x 邮筒 | 产品 + 后端 | |
| Q5 | 🟡 | 鸿蒙能否**动态切换桌面图标**、能否**代码登记长按快捷方式**（标题跟 App 语言） | 6.2 主题与图标 | 鸿蒙调研 | |
| Q6 | 🟡 | **Georgia 字体授权** | 1.1 主题系统 | 产品 | |
| Q7 | 🟡 | 天气图标标识 `weatherCode` 的**跨端词表** | 2.10 此时此地 | 鸿蒙 + iOS | |
| Q8 | ✅ | 鸿蒙的**天气数据源**（拍板彩云 v2.6） | 2.10 此时此地 | 产品 + 法务 | 2026-10-20 |
| Q9 | ⚪ | 笔友名只存本地 | — | — | 照 iOS |
| Q10 | ⚪ | iOS 设置里的**三个死设置** | 6.1 设置 | 产品 | |
| Q11 | 🟡 | 会员四样专属里**三样 iOS 也还没做** | 7.3 | 产品 | |
| Q12 | 🔴 | **隐私协议 / 用户协议的鸿蒙版** | 1.5 首启 · 8 上架 | 法务 | |
| Q13 | 🟡 | **动态照片**跨端互通 | 2.9 相机 · 6.4 导入 | 鸿蒙 | 鸿蒙侧 2.9 真机验收全过 ✅（2026-10-19：拍/选/原样配对落盘/全屏按住播放，链路假设见 Q28 结案）；跨端互通（iOS 包导入/鸿蒙包导出）仍待 6.4 验证 |
| Q14 | ⚪ | 测试开关（来信不设限、假开通会员） | 8 上架 | — | 上架前关 |
| Q15 | ⚪ | 后端域名 | 4.1 | 运维 | |
| Q16 | ⚪ | 「内容审核没过」**后端没有专门的错误码** | 5.3 | 后端 | |
| Q17 | 🔴 | 接华为账号后，**注销时撤销华为授权** | 4.4 | 后端 | 2026-10-24 后端已实现：`POST /me/delete` 带 `{huaweiIdToken, huaweiAuthorizationCode}` → `{ok, huaweiRevoked?}`，撤销失败不阻断注销（客户端不区别对待）；鸿蒙端已接（DeleteAccountView 华为验证分支）。**2026-10-25 真机实测（Mate X6）：500 复现 2/2**——`POST /me/delete` 返 `500 {"error":{"code":"internal","message":"服务器内部错误"}}`（服务端兜底 envelope，非撤销失败分支——撤销失败应 ok 照判），账号未删、客户端会话完好；客户端载荷按契约（{huaweiIdToken, huaweiAuthorizationCode} + bearer），华为验证步静默通过。**需后端（尺素）查 FC 日志定位 internal 异常**；客户端已加诊断日志（DeleteAccountView.deleteAccountWithHuawei catch 打 kind/status/body）。**2026-10-27 结案 ✅（Higgs 修复已部署）**：真机 E2E 全通——说明→华为静默验证（双凭证）→AlertDialog 确认→`POST /me/delete` 华为分支成功→账号删除、回未登录设置页，本地数据无恙。U02-3 注销 E2E 收尾完成 |
| Q18 | ⚪ | 鸿蒙**包名 / 应用市场主体** | 0.3 | 产品 | |
| Q19 | 🟡 | 正文小图加载**不放大**（iOS `loadImage` 的 `preparingThumbnail` 会把小图放大到 600） | 2.6 照片相纸 | 鸿蒙 + 产品 | |
| Q20 | 🟡 | **智感握姿实现路径**：`HdsTabs` 不在本 SDK（26），自行用 motion `operatingHandChanged` + `ACTIVITY_MOTION` 实现 | 1.6 主框架 · 真机验收 | 鸿蒙 | 2026-10-15 整体移除：Tabs 系统底栏无横移落点，且 SDK 权限清单证实 `DETECT_GESTURE`（normal + system_grant）后 `holdingHandChanged` 也只是普通权限——智感握姿收益存疑，服务、权限声明、理由文案全部删除（git 历史可寻回），真机验收 `operatingHand` 授权率与灵敏度后若确需再重启 |
| Q21 | ⚪ | 全局 toast 的 kind：文档卡片只写两种，iOS 源码是三种（error/info/success） | — | — | 2026-10-14 照 iOS 三种 |
| Q22 | ⚪ | 2.1 卡片写心情「单选**可取消**」，iOS `MoodSelector` 点已选心情**不取消**（点了始终选中） | 2.1 写日记页 | 产品 | 2026-10-15 按 iOS 源码不可取消实现（CLAUDE.md：iOS 源码优先；用户已确认）。产品若想要「再点一下取消」，iOS 侧要一起改 |
| Q23 | 🔴 | **文字绕排做不到**：RichEditor 无 exclusion 机制，锚点图片无法让文字绕排（iOS `Text` + `imageTextInitializer` 可以）；**荧光笔画法偏差**：`textBackgroundStyle` 只能整块色底，画不出 iOS 「只压文字中下部的圆头条」 | 2.6 照片相纸 · 2.5 荧光笔观感 | 产品 | 2026-10-17 **绕排破局**：graphics.text `headIndents/tailIndents`（API 26）逐行缩进 + 自研 `WrapFlowEngine`（单测全绿）；**详情页阅读态真机验证通过**（绕排/两端对齐/荧光/照片全屏，CustomSpan invalidate 不重测须换新 span、punctuationOverflow SDK 缺席两条实测）。**编辑态方案已定：B1 隐形输入层**（2026-10-17 用户拍板——编辑页实测整行卡换行推下移体验割裂；1px 透明 RichEditor 承接 IME + 自绘光标/选区，任务卡 10 手册 2.5b）；**M1 组件级已完成**（RichDocEditor/diffTextEdit/textBlockRangesOfBlocks/WrapFlowEditor，单测 272 全绿，2026-10-17；**勘误**：`getGlyphPositionAtCoordinate`（since 12）存在，此前「graphics.text 无坐标→偏移 API」结论有误，命中查询无需自算字形）；**M1 收官（2026-10-17）**：页面接入+真机 E2E ✓、光标「落 0」疑案结案（verify_ui 注入例程「全选→清除→输入」×锚点保护交互，非 bug）、空态塌缩补修（max 高度+占位段+空文档光标）、**平台缺陷实证+追修**：`orphanCharOptimization` × `strutStyle` 时恰好 2 行的段落 `paint()` 零输出（1/3/4 行正常，探针矩阵二分实证，查无已知限制）——移除 orphanCharOptimization 规避，真机 2 行态回归 ✓；**M1 追修三（2026-10-18）**：heading `\n` 行段拆分（TextPart/BuiltItems sidecar/caret 区间映射重写）真机 ✓（H 段 21.12vp / B 段 16.32vp 分段正确），顺带双修 EditEntryView 日期行过期（`@State entry`）与标题注入竞态（双信号）；荧光笔圆头条（Run 字形自绘）真机观感后议。**结案（2026-10-18 产品拍板）：三页回退华为备忘录式，绕排下线保留**——平台缺陷连环修不见底（orphanCharOptimization×strut 两行零输出、strut 实测行高 16.32≠20vp 需探针自愈、heading 编辑器合并污染拆段追修三轮），ComposeView/EditEntryView/EntryDetailView 全部换回 2.5/2.6 备忘录形态（RichBodyEditor+工具条+照片链路，真机三页冒烟 ✓）；WrapFlow 全家桶+278 单测下线保留（页面零引用未删）；未建成功能与恢复条件建档 `11_UNBUILT_FEATURES.md`。本问状态改 🔴（回退定型，备忘录式=终态方案） |
| Q24 | 🟢 | ~~详情页「补记 N 次」行暂不渲染~~ 影子台账（InkLedger）解决：writtenAt/struckAt 全链路保留，补记行 2.8 已接通 | 2.8 墨迹 | 鸿蒙 | 2026-10-18 落地（见下 Q24 详述） |
| Q25 | ⚪ | **老日记录音补进正文**（R-RICH-09）：2026-10-10 之前的日记录音在正文外面（audioURLs 列），打开编辑时要就地转成正文里的录音块 | 2.8 录音 | 鸿蒙 | 纯逻辑已备好（`blocksWithLooseAudio` + 单测）；2.8 接录音块渲染时挂进 EditEntryView 装载链路 |
| Q26 | 🟡 | 2.8 墨迹三处小偏差：补记段标不做（RichEditor 无段前距）；scissors/strikethrough 符号不存在（痕迹行纯文字、菜单项无图标）；sys.symbol 离线不可枚举 | 2.8 墨迹 | 产品拍板 + 鸿蒙 | 见下 Q26 详述 |
| Q26 | 🔴 | **bindContentCover 真机「隐形挂载」**：全屏照片查看用 bindContentCover，真机出现 appear 日志齐全但零渲染、吞掉整页触摸（dt=163552ms）的幽灵态；且 EditEntryView 同时 bindSheet+bindContentCover 双绑属 API 违规用法 | 2.6 全屏查看 | 鸿蒙 | 2026-10-17 弃用 bindContentCover：三页改**页面内条件浮层**（根 Stack 末位 if(showPhotoFullscreen)，同层最高）。根因未深挖（疑模态子窗口层丢失）；教训：模态类 API（bindContentCover/bindSheet）同一节点只绑一个，全屏沉浸浮层优先用页面内浮层（可嵌自定义转场、可与其他 UI 联动，如 Tab 栏 barOpacity） |
| Q27 | ⚪ | **真机验证方法论教训（「关全屏白屏」疑云结案）**：曾判定「关闭全屏后整页白屏」并二分删除 transition/barOpacity/hideTitleBar——全部误报 | 验收流程 | 鸿蒙 | 2026-10-17 结案：**像素采样伪象**。`sips` 转 BMP 是负高度 top-down 行序，采样脚本按 bottom-up 公式翻转导致所有采样点垂直镜像（页面照片/Tab 栏位置全采错成背景白区）；dumpLayout 组件树一直完好。教训：①截图判位必须先用已知参照物（状态栏文字、照片区域）校验采样坐标映射；②「白屏」类结论需 dumpLayout（树）+ 像素分布对比（与正常帧 white/dark/colored 占比一致=同页）+ 无诱导语的模型看图三重交叉；③真机注入双击用单次调用链式 down/up（`uinput -T -d x y -u x y -d x y -u x y`，实测间隔 ~45ms；两次独立 uinput ~350ms、uitest doubleClick ~640ms，都超 280ms 双击窗）；④长 E2E 前先 `power-shell timeout -o 600000` 防自动锁屏（锁屏后 dump 有树但截屏全黑） |
| Q28 | ✅ | **2.9 相机/动态照片的三条官方链路假设**：① `requestMovingPhoto`/`requestImageData`/`saveCameraPhoto` d.ts 权限标注与官方文档用法相悖；② `PhotoViewPicker` IMAGE_TYPE（'image/*'）是否包含动态照片资产可选；③ `loadMovingPhoto`+`MovingPhotoView` 沙箱文件播放可用性 | 2.9 相机 | 鸿蒙 | **2026-10-19 真机实证三条全过，结案**（详述见下 Q28） |
| Q29 | ✅ | **首启默认日记本颜色冲突**：05_DATA_MODEL §4.2 写「墨绿」，iOS 源码 `ContentView.ensureDefaultTagsExist` 用 `Tag()` 默认构造（**酒红**） | 3.1 书架 | 文档 | 2026-10-20 拍板：**以 iOS 为准（酒红）**，实现已一致；05 §4.2 待勘误（详述见下 Q29） |
| Q30 | ✅ | 书架 Scroll「短内容居中 + 内容槽原点 0」双坑（真机像素级实证） | 3.1 书架 | 鸿蒙 | 2026-10-20 结案（详述见下 Q30） |
| Q31 | ✅ | 3.2 拖书五坑（编译+单测实证） | 3.2 拖书 | 鸿蒙 | 2026-10-20 结案（详述见下 Q31）；真机录屏验收未过 → 转 Q32 |
| Q32 | 🔴 | **3.2 拖书手感未达产品要求（四项）**：① 32° 转身露书脊**透视不对**；② 侧转一瞬**有一条红线**；③ **动画生硬卡顿**；④ **落格、其余书让位与 iOS 差距很大** | 3.2 拖书 | 鸿蒙 + 产品（录屏验收） | 待专项修复（详述见下 Q32） |
| Q33 | 🟡 | 3.3 删除日记本语义：规则措辞与 iOS 源码不一致（按 iOS 源码执行：只删本子行，不删日记） | 3.3 日记本主页 | 鸿蒙 | 2026-10-21（详述见下 Q33） |
| Q34 | 🟡 | 3.3 大图照片加载复用 600px 缓存（iOS 独立 300px） | 3.3 日记本主页 | 鸿蒙 | 2026-10-21（详述见下 Q34） |
| Q35 | 🟡 | 3.3 大图高度/布面标题/顶栏磨砂等真机验收四轮定稿 | 3.3 日记本主页 | 产品 + 鸿蒙 | 2026-10-21 定稿（详述见下 Q35） |
| Q36 | 🟡 | **3.5 阅读器三条声明偏差 + 仿真翻页技术坑**：① 仿真翻页（官方最佳实践配方）替代 iOS `UIPageViewController(.pageCurl)`，华为 Reader Kit 排除；② 大屏单列页宽封顶 420vp；③ trace 25 / audio 60 / photoHeight 剪裁等尺寸常量待真机核对 | 3.5 阅读器 | 鸿蒙 + 产品（录屏验收） | 2026-10-22 代码完成待真机验收（详述见下 Q36） |
| Q37 | ⚪ | **一键登录（LoginType.QUICK_LOGIN）要不要做** | v1.1 候选 | 产品 + 后端（尺素） | 2026-10-25 SDK 调研结论（详述见下 Q37） |
| Q38 | ✅ | **线上 `POST /me/bindings/phone` 500**（消费验证码后绑定步崩溃） | 4.3 补绑手机号 | 后端（尺素） | 2026-10-25 真机实测复现（详述见下 Q38）。**2026-10-27 结案 ✅（Higgs 修复已部署）**：真机 E2E 全通——发码（真实阿里云短信）→221716→`POST /me/bindings/phone` 成功，返回 switchedAccount 合并到既有手机号账户，账户页手机号行翻已绑、警告消失 |

---

## 详细说明

### Q1 🔴 华为账号登录接口未实现

**2026-10-24 更新：后端三端点已部署**（`POST /auth/huawei {idToken}`→AuthResponse、`POST /me/bindings/huawei {idToken}`→`{ok:true}`、`POST /me/delete` 华为分支→`{ok,huaweiRevoked?}`），但服务端 AGC 密钥未配 → 实测恒返 **503 `huawei_disabled`**（U02 卡设计如此：客户端先写好按 503 分支自测）。
鸿蒙客户端已全部接好：LoginView 华为官方按钮（LoginWithHuaweiIDButton，503 专判「华为账号登录暂未开放，请先用手机号登录」）、SettingsAccountView 绑定行（请求式 API）、DeleteAccountView 华为验证注销。**打通只差后端配 AGC 密钥**：Client ID=6917619854007528919（=APP ID）+ OAuth 客户端 Secret（client_credentials 拿应用级 token；ID Token 验签走华为 JWKS 公钥；aud 校验值=6917619854007528919）。**公钥指纹调试阶段免配**（2026-10-24 核官方《配置签名和指纹》：compatibleSdkVersion≥20 豁免，本项目 26 满足；AGC 里 0A:4E:B0:D8… 为旧自动签名证书残留）；客户端 module.json5 client_id 已修正为 6917619854007528919（原 2067731667488866304 是 agconnect 旧值）。
手机号必绑警告（R-ACCOUNT-03）照做：华为登录若返回未绑手机号的 user，设置页红色警告行同样生效。

历史（已过时）：后端只有 `/auth/send-code`、`/auth/verify-code`、`/auth/apple`、`/auth/third-party`（微信，v1 不做）时期，鸿蒙 v1 先只做手机号登录。

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

**✅ 结论（2026-10-24 调研 + 用户拍板）**：云同步采用华为**端云数据同步**（ArkData 端云协同）——数据同步进**用户自己的华为云空间**（设置-云空间），开发者不可见，满足「数据在用户自己的云、我们拿不到」的承诺。落位 = 设置 → 数据与备份 → 二级页的云同步位（对齐 iOS 的 iCloud 同步位），即 6.6 卡。技术要点与门槛：

- RDB 表级同步：AGC 云侧建容器（名称 = 本地 RDB 库名）+ 数据类型逐字段配置（字段名/类型与本地表一致；本地表字段不可 NOT NULL；主键在云侧勾「端侧去重主键」）；`app.json5` 开 `cloudStructuredDataSyncEnabled`
- 设备 ≥ HarmonyOS 6.1.0 且云空间 ≥ 6.3.0，仅中国大陆；用户需在「设置-云空间」开同步开关
- 生产环境配置部署后**只增不改不删**——schema 纪律同 iOS CloudKit
- 媒体走 Asset/ASSETS 字段；同步状态按 R-DATA-05 只认真实同步事件（官方同步状态码：0 已同步 / 1 暂停 / 2 网络错误 / 3 未开启 / 5 超上限 / 6 云空间不足 / 7 未连 WLAN）
- AGC 云数据库（开发者侧）确认排除（数据进我们项目，违背隐私承诺）
- 可选保底：BackupExtensionAbility（换机克隆 / 系统云备份带走应用数据，半小时级小卡，与云同步互补）
- 6.6 落地前，数据与备份页仍按 R-DATA-05 如实展示「日记只在这台设备上」

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

### Q8 ✅ 天气数据源（2026-10-20 拍板：彩云天气）

iOS 用 WeatherKit，位置只发给 Apple、不经我们服务器。鸿蒙选系统能力或第三方都行，但**用第三方就意味着坐标发给了它**，隐私协议第三方清单要加上（Q12）。

**拍板（2026-10-20，2.10）**：华为官方 WeatherServiceKit **仅面向系统应用开放**（本地文档实锤「仅面向系统应用开放」+ 用户 AGC 开放能力管理实测无天气服务开关）→ 接入**彩云天气 v2.6 实况接口**（`https://api.caiyunapp.com/v2.6/{token}/{lng},{lat}/realtime`，token 内嵌客户端 URL，个人版设计如此；AppKey/AppSecret 不入代码）。坐标会发给彩云，**Q12 隐私协议第三方清单须加彩云天气**。skycon → SF Symbol 名（Q7 词表）→ sys.symbol 图标双跳映射；华为若日后向三方开放天气服务可切回（conditionTypeToSFSymbol 保留）。

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

**鸿蒙侧现状（2026-10-18，2.9；2026-10-19 真机验收全过）**：相机拍 / 相册选的动态照片按「原样字节配对」落盘——
显示图 `photo_<uuid8>.jpg`（相机=方形裁切重编码；相册=原图原样字节）+ 相机专属未裁原图
`photo_<uuid8>_full.jpg` + 视频 `photo_<uuid8>.mp4`（均 saveData 原样，R-PHOTO-03）；
全屏 `loadMovingPhoto` + `MovingPhotoView` 长按播放，失败退静态图（R-PHOTO-04）。
链路假设真机实证结案（Q28，2026-10-19）；跨端互通（iOS 包导入 / 鸿蒙包导出）留 6.4 验证。

### Q14 ⚪ 测试开关

服务端 `LETTER_RHYTHM_OFF=1`（来信不设上限）和 iOS 的假开通会员都在测试期打开，**鸿蒙测试时看到来信不设限是预期**，不是 bug。上架前关（iOS 上架清单 A0c）。

### Q15 ⚪ 后端域名

iOS 当前用阿里云函数计算的系统域名：`https://memoir-api-cn-ecdrwvhwac.cn-hangzhou.fcapp.run`；
备案域名 `https://api.sinaratech.com.cn` 还没切。鸿蒙写成**一个常量**，切换时只改一处。只接大陆后端，不做区域判断。

### Q16 ⚪ 内容审核错误码

iOS 定义了「日记内容未通过审核，这次没能寄出」，但服务端目前**不会**返回专门的错误码（模型拒绝会以 `ai_failed` 502 返回）。
鸿蒙先按 502 处理（重试 3 次后退回）；后端加了专门的 code 后，改成直接退回。

### Q17 ⚪ 注销时撤销华为授权

**2026-10-24 已闭环（待真机验收）**：后端 `POST /me/delete` 带 `{huaweiIdToken, huaweiAuthorizationCode}` → `{ok, huaweiRevoked?}`，撤销失败不阻断注销；鸿蒙端 DeleteAccountView 华为验证分支已接（授权码不缓存、AlertDialog 取消即丢、finally 恒清）。

历史：接了华为账号（Q1）之后，注销账号时服务端要像 Apple 那样撤销授权，需要后端加分支。

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

### Q24 🟢→⚪ 块级 writtenAt 编辑后丢（影子台账解决，2.8 落地）

补记判定依赖块级 `writtenAt`（`Ink.isAddendum`），而 2.5 的编辑器读回链路
（`RichBodyController.currentDocument`）从 RichEditor span 还原不出 writtenAt——
RichEditor 的文字样式模型装不下自定义时间戳。经编辑页保存一轮后块上的
writtenAt / struckAt 会丢（正文文字不丢）。

**2026-10-18 已解决**：`models/InkLedger.ets` 的影子台账——`writtenAt[]` / `struckAt[]`
与活文本（锚点占 1 字符）逐字符对齐，`onDidChange` 单点 diff 同步
（插入记编辑会话时刻，`diffTextEdit`），`currentDocument` 读回时
`overlayInkOntoSpans` 把台账叠回纯视觉 spans，保存链路从此带上
writtenAt / struckAt；详情页「补记 N 次」行（R-INK-04）同日接通渲染。
单测 `InkLedger.test.ets`（台账 diff / 删除计划 / overlay）+ `RichDocument.test.ets`
（blocks→doc→blocks 墨迹与痕迹往返）覆盖。

### Q25 ⚪ 老日记录音补进正文（R-RICH-09）

2026-10-10 之前的日记（含 iOS 互导的包）录音都在正文外面的 `audioURLs` 列里。
R-RICH-09 要求打开编辑时就地转成正文里的录音块。纯逻辑已就位
（`ContentBlock.blocksWithLooseAudio` + `ContentBlock.test.ets` 单测），
2.8 做录音块渲染时挂进 `EditEntryView` 的装载链路即可。

### Q26 🟡 2.8 墨迹三处小偏差（2026-10-18）

- **「补记 · 某月某日」段标不做**：iOS 补记段前有 `addendumNote` 小字段标
  （段前距 + 12fp 标签）。ArkUI RichEditor 段落模型拿不到段前距（API 26），
  且无法在正文中可靠定位「补记段起点」（非模型级锚点，需污染存盘格式才能画）。
  决定：段标省略，补记的墨色变化（laterInkColor）已足够传达；详情页顶部
  「补记 N 次」行不受影响。产品拍板（2026-10-18）。
- **痕迹行 / 菜单图标缺失**：`sys.symbol.scissors`、`sys.symbol.strikethrough`
  均不在系统符号集（编译期资源校验报错）。痕迹行退化为纯文字
  （12fp 三级色）；「取消划掉」菜单项无图标（只文字）。
- **`sys.symbol` 离线不可枚举**：hm_symbol_config.json 只有分组名，
  预判只能靠编译期报错兜底（本次 scissors 即此路径发现）。

### Q27 🟢 RichEditor 引擎退格判定光标铁律（2026-10-18 真机实证，已绕开）

- **现象**：`aboutToDelete` 拦截（返回 false）后，引擎对下一次退格（DEL）
  的判定光标固定停在**被取消范围的起点**。`setCaretOffset` 同步调用、
  `setTimeout(0)` 延迟、两次 toggle 三轮实测**均改不了它**（AceRichText
  `RecordOperation` 内部状态，`caret:26->27` 日志铁证）。可视光标引擎会
  自动移对位置，与 DEL 判定光标是两套。
- **影响**：两段式取下（ARM 后第二下退格）在直接命中路径上，第二下范围
  变 [锚点-1, 锚点) 而非锚点本身，被引擎单锚点分支吞掉。尾随换行路径
  因被取消范围恰从锚点起而侥幸命中——先验证录音成功是路径运气非逻辑完备。
- **绕开**：`handleAboutToDelete` 开头加武装分支——`armedAnchorId` 在位
  且 BACKWARD len=1 且 end=锚点 offset → 直走取下/删除，不动锚点前字符。
  2.8 已落地并真机验证（照片/录音取下均过）。
- **沉淀**：今后任何「拦截删除后引导下一次退格」的交互都要按此铁律设计，
  不能依赖 setCaretOffset 改变引擎 DEL 判定位置。

### Q28 ✅ 2.9 相机/动态照片的三条官方链路假设（2026-10-19 真机实证结案）

- **① d.ts 权限标注与官方文档用法相悖**：`MediaAssetManager.requestMovingPhoto`/
  `requestImageData`（d.ts 标 `ohos.permission.READ_IMAGEVIDEO`）、
  `MediaAssetChangeRequest.saveCameraPhoto`（标 `WRITE_IMAGEVIDEO`）——READ/WRITE_IMAGEVIDEO
  三方应用 2024 起已不可申请。但官方《访问和管理动态照片资源》《动态照片拍摄(ArkTS)》
  文档把这三条作为 **Picker 选中后 / 相机 photoAssetAvailable 回调上下文里的标准方式**
  展示，全程无权限申请步骤。假设：临时授权或相机回调上下文免权限。真机不通过时的
  兜底：相机侧 `requestImageData` 静态图（R-PHOTO-04）；相册侧 Picker URI 直接读文件
  解码（现实现里动态链路失败本来就走这条路）。
- **② `PhotoViewPicker` IMAGE_TYPE 是否含动态照片**：官方示例选动态照片用
  `MOVING_PHOTO_IMAGE_TYPE`（'image/movingPhoto'，只列动态照片）。现实现用
  IMAGE_TYPE（'image/\*'）+ 选中后 `getAssets` 查 `PHOTO_SUBTYPE === MOVING_PHOTO(3)`
  分流——假设 'image/\*' 会列出动态照片资产。若真机相册里动态照片不可选，
  改用 `MOVING_PHOTO_IMAGE_TYPE` 单独入口或调 MIME 组合。
- **③ `loadMovingPhoto` + `MovingPhotoView` 沙箱播放**：全屏查看用
  `MediaAssetManager.loadMovingPhoto(context, stillUri, videoUri)`（since 14）+
  `MovingPhotoView`（长按播放、API 26 免手动导 MovingPhotoViewAttribute）。
  组件标注「不支持动态属性设置」→ 已避开（不参与捏合缩放）；`onError` 退静态图。
  沙箱 fileUri 配对播放真机可用性待验证。
- **验证时机**：2.9 真机验收（相机拍动态照片 → 按住播放 → 相册选动态照片 →
  全屏播放 → 存相册多一张 → 配对失败退化普通照片）时逐条过。任何一条不过走
  上述兜底，均不阻塞 2.9 静态照片链路。
- **结案（2026-10-19，Mate X6 真机）三条全过**：
  - **① 过**：相机 `photoAssetAvailable` 回调上下文里 `requestMovingPhoto`/
    `saveCameraPhoto` 免权限可用（编译期有 READ/WRITE_IMAGEVIDEO 告警但不拦执行）。
    实测发现的真坑不是权限而是**资产两阶段写入竞态**：`requestMovingPhoto` 在资产
    未就绪时秒回 14000011 或 resolve undefined——BALANCE 模式失败快适合密集探针
    轮询（waits [300..5000] 八档）+still 跨尝试保留+HIGH_QUALITY 背水一战+
    still-only 兜底；夜拍 50MP 从「22s 全败」修到 1.0-3.6s 交付（解法详见
    PROGRESS 2.9 追记）。
  - **② 过**：`IMAGE_TYPE`（'image/*'）相册能列出并选中动态照片，`getAssets` 查
    `PHOTO_SUBTYPE === MOVING_PHOTO(3)` 分流正常（相册选动态→插入→全屏播放真机过）。
  - **③ 过**：`loadMovingPhoto`+`MovingPhotoView` 沙箱 fileUri 配对长按播放可用；
    实测约束记录：MovingPhotoView 不支持动态属性、不支持 expandSafeArea、
    AVPlayer 并发 ≤3；`onError` 退化静态图路径保持。

### Q29 ✅ 首启默认日记本颜色冲突（2026-10-20 拍板：以 iOS 为准，酒红）

- **冲突**：`05_DATA_MODEL.md` §4.2 写首启默认 4 本颜色为「墨绿」，但 iOS 源码
  `ContentView.ensureDefaultTagsExist`（L255-266）用 `Tag()` 默认构造建 4 本，
  `Tag.init` 默认 `color = .wineRed`（**酒红**）——iOS 真机首启 4 本都是酒红。
- **拍板**：按 CLAUDE.md「冲突以 iOS 源码为准」，**默认 4 本 = 酒红**。鸿蒙实现
  `Notebook` 构造函数默认 `colorId` 本就是 WineRed，与 iOS 一致，**实现无需改**；
  05 §4.2 属文档笔误待勘误（本条即记录）。
- **注意区分三个「默认颜色」**（易混）：
  ① 首启 4 本 → 酒红（`Tag()` 默认，本条）；
  ② 书架「+ 新建日记本」弹窗 → 墨绿（iOS `CreateTagSheet` `CoverEdit(color:.pineGreen)`，3.1 已照做）；
  ③ 写日记页顺手新建（没机会挑颜色）→ `quietestColor`（书架上用得最少的颜色，象牙白除外，书架为空/并列时按 `BookColor` 声明序取第一个；iOS `TagSelector.quietestColor`，05 §4.1，3.1 已接）。

### Q30 ✅ 书架 Scroll「短内容居中 + 内容槽原点 0」双坑（2026-10-20 真机像素级实证结案）

- **现象**（Mate X6 折叠外屏 1080×2440，密度 3.125，沉浸全屏窗口）：
  ① 短内容（4 本/1288px < 视口 2318px）时书架内容 Column 悬在屏幕中部
  （[0,576]，576=(2440-1288)/2 精确居中于**全窗**帧），冷启 100% 复现；
  ② 高内容态下 Scroll 内容**首个子组件的 top inset（margin/padding）渲染约半密度**
  （12vp→15px 而非 37.5px）；
  ③ dump 里 Scroll/Column 的 bounds 是**钳制后可见域**（Scroll 显示 (0,122) 但内容槽
  实际从窗口顶 y=0 起——`.align(Alignment.Top)` 试验时标题渲染在 y≈40-70 **状态栏底下**，
  截图像素实锤）。uitest dumpLayout 的 y 坐标在沉浸布局下**不可当布局原点用**，以像素为准。
- **根因**：沉浸窗口 + HdsTabs barOverlap 下，Scroll 内容槽 = 全窗 [0,2440]（含状态栏区），
  布局系统**不做**顶部避让；子内容 < 槽高时走「窗口帧居中」分支（官方 faqs-arkui-725
  实锤「子组件小于 Scroll 尺寸默认居中排布」），≥ 时从槽顶 y=0 排（穿进状态栏）。
  旧代码的 safeAreaTopVp 补偿其实一直在做顶部避让的正事（先前误诊「双重避让」删掉了）。
- **试错**：`.align(Alignment.Top)`（faqs-arkui-725 官方方案一）在本机 API 下会**吃掉
  Scroll 第一个子组件**（标题 Row 从组件树消失，A/B 隔离实验实锤），弃用；
  HomeView 免疫此坑是因为它用 **List**（官方方案二：List 高度受限时短内容默认顶对齐）。
- **终稿**（BookshelfView，双保险）：
  ① 内容 Column `.constraintSize({ minHeight: viewportHeightVp })`（Scroll.onAreaChange
  量视口高）→ 内容恒 ≥ 视口，居中分支永不触发，两种数据量下标题都精确落
  [479,158][601,195]（状态栏下 12vp）；
  ② 标题 `.margin({ top: safeAreaTopVp + 12 })` 恢复顶部避让（内容槽原点 0，避让必须
  自做；12vp 小间隙与 HomeView 头部 padding 同款）；
  ③ `edgeEffect(Spring, { alwaysEnabled: true })`（内容不满一屏也果冻回弹，HomeView
  同款注释）；④ 内容树整体 `if (contentWidthVp > 0)` 量到才画，防首帧居中闪屏。
- **验证**：4 本/8 本两数据量冷启 dump + 像素双验，标题一字不差 158、板全宽
  [0,·][1079,·]、书顶对齐 257；367 测试全绿。
- **大屏预警**：折叠展开态视口更高、内容更矮，居中错位会被放大——本修复已从根上
  消灭，大屏适配时无需再处理此坑，但**避让/几何全部走 safeAreaTopVp + onAreaChange
  实测值**，勿信 dump 坐标。

### Q31 ✅ 3.2 拖书五坑（2026-10-20 编译+单测实证结案，真机录屏验收待做）

- **① `LongPressGesture` 接口没有 `.sequenced()`**（编译实锤 `Property 'sequenced' does
  not exist on type 'LongPressGestureInterface'`）。长按→拖动的顺序组合必须用
  `GestureGroup(GestureMode.Sequence, LongPressGesture(...), PanGesture(...))`：
  按够 350ms 才解锁 Pan，按不够就挪开→整组失败→外层 Scroll 的滚动手势接手
  （体感与相册/桌面一致）。各子手势自己的 onAction/onActionEnd/onActionCancel
  照常回调，drop 各入口幂等（settling 早退）。
- **② `GestureEvent` 没有 `globalY`**（编译实锤）。手指的窗口坐标在
  `event.fingerList[i].globalY`（FingerInfo，相对应用窗口左上角，vp，API 8+）。
  边缘自动滚需要**视口内**坐标：Scroll `.onAreaChange` 记 `newArea.globalPosition.y`
  （Scroll 滚动不改自身区域，该值恒定），`fingerList[0].globalY − viewportGlobalYVp`
  即视口内 y。
- **③ springMotion 是渲染服务（RS）侧物理弹簧，且不回调完成**。跟手/自动滚
  全程用**同一个文件级 `curves.springMotion(0.2, 0.88)` 实例**逐帧 retarget——
  中途换实例或换曲线改写同一属性会孤儿化 RS 侧动画（跟手丢弹簧感）。
  **松手落位是例外**（2026-10-21 对齐 iOS）：跟随已结束，孤儿化旧弹簧安全；
  落位滑动改定长 `animateTo` 420ms EaseInOut（iOS `settleAnimation .smooth(0.42)`
  单个 withAnimation 块：order 挪位 + 浮书滑落点 + lifted 同拍），带跟手弹簧
  会有过冲且节奏与 iOS 不符。完成链靠定时兜底（450ms 落位 + 500ms 转回 + 50ms
  余量）。另外 `.animation()` 隐式动画会劫持同组件所有可动画属性，落位让位
  必须包在 `animateTo` 事务里（只有 position 变，ForEach 键 = slot key 组件
  不重建）。
- **④ 投影矩阵不能进动画系统**。`.transform3D` 属性线性插值两颗旋转矩阵的中间态
  不是旋转（书会先缩小再放大）。转角动画 = 16ms `setInterval` 改 `bookAngleRad`
  状态、每帧重算两颗投影矩阵（iOS `Animatable.angle` 同款思路）。
- **⑤ 自拼 3D 矩阵的两处正确性要点**（`BookBoxProjection.ets`，单测数值实证）：
  a) 矩阵的 **z′ 行清零后再交给 ArkUI**：透视 + 平移的组合会在 z′ 行留下正比
  x/y 的 bogus 深度（静止封面角点 z′≈−27），命中测试/深度排序可能被带偏；
  清零后静止时对平面输入（面视图 z 恒 0）严格等于恒等——拿起那一下不跳。
  b) `matRotateY` 的**实现方向与直觉相反**（x′=x·cos−z·sin）：书脊视图的
  **右缘**（x=depth）才是与封面左缘共用的缝，左缘是背面。方向别靠记：
  `spineFaceAngle`/`bookBoxLiftAngle` 直接读矩阵元素挑（书脊落左侧、拿起
  方向自动朝可见侧），缝的对齐由单测钉死（任意转角下封面左缘角与书脊右缘
  角投影差 < 0.01vp）。
- **⑥ 浮书手感三件套**（真机实证，先前会话）：LTPO 深闲置触摸不唤醒低功耗链路
  （第一帧冻住）→ 触地 poke（透明度里一个看不见的 0.1 小数抖动，强制出一帧
  真实渲染）；浮书**常驻挂载**（idle 透明度 0.01 仍参与栅格化，首次挂载渲染
  管线要现编译实测 ~367ms，页面加载时就挂出来第一次拿起才不卡）；
  `HitTestMode.None` 实测吞触摸，浮书层用 `Transparent`。
- **⑦ 顺序组合手势里只有最后一个手势能响应 onActionEnd**（官方 GestureGroup 文档
  明示 + 真机实证，2026-10-20 用户报「拖书卡住」定位）。只长按拿起（350ms
  onAction 已回调、书已浮起）、没拖就松手：PanGesture 从未识别 → 它的
  onActionEnd/onActionCancel 都不来，而 LongPressGesture 的 onActionEnd 在
  Sequence 组里**不回调** → dropBook 没人叫 → 书永远浮在原格上方，且
  dragId 卡住后全架书点击/拖动全被守卫拦死（真机 `devecocli ui longclick`
  稳定复现）。修法：格子上挂 `.onTouch` 兜底网，`TouchType.Up/Cancel` 且
  `dragId === slot.key && !settling` → dropBook（真拖动时 pan 的 end 也会来，
  dropBook 幂等先到先放下）；LongPress 的 onActionEnd 留作跨机型保险丝。
- **⑧ 拖动中的格子用 opacity 0 隐藏，不用 `Visibility.Hidden`**：Hidden 会把
  组件整个移出命中测试，拿起那一刻正在进行的触摸流有被掐断的风险（pan /
  onTouch 收不到后续事件）；opacity 0 视觉等效（格子本来无背景，只剩书），
  触摸流全程不断。（Hidden 掐流未单独实证——修 ⑦ 时顺手换掉防患未然；
  onTouch 兜底网在 opacity 0 下命中链路完整是确定的。）
- **验证**：398 测试全绿（新增 ShelfDrag 21 + BookBoxProjection 10）、
  `devecocli build` 零 ERROR、check_localization 过绿。
  真机录屏验收待做（R-BOOK-06 验收 = 用户看录屏确认）。
  ⑦ 修复后真机复测：`ui longclick` 三本书（生活×2、旅行×1）拿起→松手全部
  正常落回原格，书架无残影（布局签名 + 截图识别双确认）。

### Q32 🔴 3.2 拖书手感未达产品要求（2026-10-21 用户真机验收反馈，待专项修复）

- **产品结论**：功能逻辑（拿起/拖动/松手/只写变了 sortOrder）与 398 单测全绿，
  但**手感多轮调教仍未过产品关**。用户拍板（2026-10-21）：先记入清单，
  **后续专项修复**，不阻塞其它卡片推进；修复并录屏过验收前 3.2 不结案。
- **四项问题（用户原话）**：
  1. **长按后 32° 转身露书脊透视不对**；
  2. **长按 32° 日记本侧转一瞬有一条红线**；
  3. **动画生硬卡顿**；
  4. **落格、其余书让位与 iOS 版本差距很大**。
- **修复时先读**：R-BOOK-06/07；iOS `Shelf/ShelfGridView.swift`（动画参数在
  文件头：lift `.smooth(0.45)` / follow `interactiveSpring(0.2, 0.88)` /
  settle `.smooth(0.42)` / turnBack `.smooth(0.5)`）、
  `Shelf/BookBoxProjection.swift`（eyeDistance 520、矩阵链）。
- **初步假设（修复时逐条验证，勿直接当结论）**：
  - ①透视：`eyeDistance 520` 是 iOS pt 口径直搬 vp；且 Q31 ⑤ 行/列主序转置
    实验只验证了「静止恒等 + 缝对齐」，**透视强度的真实观感未与 iOS 对照过**
    （TransformLab 实验页当时为查 transform3D 语义而建，透视项 w 的读法
    行/列两种候选，实验未做完即 cleanup，备份在会话临时目录）。
  - ②红线：疑似封面/书脊**双面各自 transform3D 栅格化在拼缝处露底**
    （两颗矩阵浮点路径不同 → 同帧 1px 缝露出下层内容），或书脊渐变/烫线
    （#D9C08A）在极窄投影带上的采样伪影；需逐帧截图定位出现在哪个转角区间。
  - ③卡顿：现实现转角动画 = 16ms `setInterval` 改状态 → 每帧走 ArkUI 状态
    更新管线重算两颗矩阵（iOS 是 Animatable 在渲染层插值）；考虑降每帧
    状态传播面 / 与 vsync 对齐 / 减少同帧重布局范围。
  - ④落格让位：现 `animateTo` 420ms **EaseInOutCubic** 单拍；iOS 是
    `.smooth(0.42)`（SwiftUI smooth 样条，曲线形状不同）+ completion 链
    （落位完 → 转回 0.5s）。曲线形状、让位起始时机都可能与 iOS 有观感差。
- **约束（卡片原文）**：不要抖动、让位动画（拖动中实时让位）、角标；
  验收 = **录屏给产品当面确认**。

### Q33 🟡 3.3 删除日记本语义：规则措辞与 iOS 源码不一致（2026-10-21，按 iOS 源码执行）

- **冲突**：`06_RULES.md` R-BOOK-08 措辞是「删除日记本**只移除归属**（不删日记）」，
  暗示要顺手清掉日记上的归属标记；但 iOS 源码（> 规则文档，CLAUDE.md 冲突裁决序）
  `BookDetailView.deleteNotebook` 只做 `NotebookCoverStore.remove` + `context.delete(tag)`
  ——删的是 Tag 记录，**完全不动 `JournalEntry.tags`**（tags 是独立存的字符串数组，
  与 Tag 记录无外键关联），留下悬空的名字字符串；同名重建一本时那些日记按
  「名字就是身份」重新归入。
- **鸿蒙对齐做法**（3.3 已实现）：`NotebookRepository.deleteNotebook` 只
  `DELETE FROM notebook WHERE id = ?`，封面文件走 `MediaStorageService.deleteCoverFile`；
  `journal_entry.tags` 原样保留。
- **若产品后续要求「删本时清归属」**：需在 deleteNotebook 里加一步
  journal_entry tags 数组去除该名的批改（renameNotebook 的同款套路），并同步改 iOS。

### Q34 🟡 3.3 大图照片加载复用 600px 缓存（iOS 独立 300px）（2026-10-21，观感差异微小）

- **iOS**：`BookHeroView` 用独立 `SizedCache(maxSize: 300px)` 解码封面照片。
- **鸿蒙**（3.3 已实现）：直接复用 `PhotoPaperIO.forFilesDir(...).loadImage`
  （600px 全局缓存，与封面/详情页共用）。清晰度更高、内存占用略大；
  大图按视口约 2×600px 显示，实际观感差异微小。若真机验收发现内存压力
  或锯齿问题，再给 BookHeroView 建独立 300px 入口。

### Q35 🟡 3.3 大图高度 62%→48%、布面标题居中、顶栏回归 iOS 滚动磨砂（2026-10-21 用户真机验收四轮定稿）

- **用户三条**（原文口径）：①「全部日记」标题放大图中间；②目录上移、
  差不多露出三篇日记的完整题目；③顶部做一条磨砂安全边界。
- **与 iOS 的偏差**：hero 高 iOS 0.62（底部浮条 + 胶囊清让共吃 ~190vp，
  0.62 时目录只露一行标题）→ 鸿蒙 0.48；布面烫标 iOS 顶部锚定
  （top 60）→ 垂直居中（纯色本 +「全部日记」共用版式，一并生效）。
- **磨砂边界四轮演进**（每轮真机截图像素实测驱动，最终回归 iOS 原版行为）：
  1. Thin 毛玻璃 + 主题色 40%（记录主页同款）→ 在暖米布面上隐形
     （带身只比底子亮 ~14/255）；
  2. COMPONENT_ULTRA_THICK + 冷灰 65% 罩面 → 读得出层但切层感重；
  3. backgroundEffect 白 30% 透明磨砂挪到状态栏下沿 → 用户否
     （「弄的像iOS一样，现在这个不行」）；
  4. **定稿 = iOS 原版**：常驻边界全部删除——静止时状态栏区域完全
     透明沉浸；滚过大图后顶栏出磨砂（Thin + 主题色 40%，记录主页同
     配方）+ 细线 + 居中标题，250ms 渐显。
- **滚动后才暴露的布局 bug（已修）**：顶栏居中标题在 Stack 里不定位会
  居中在「状态栏 + 44 行」整块上、压进状态栏（真机滚动后像素实测
  y≈114-141）——显式 Row 钉到状态栏下面那行（y≈188 处居中）。
- **顶栏返回 /「…」换官方圆钮（用户提出，2026-10-21）**：裸 SymbolGlyph
  → `CircleIconButton`（官方 Button 圆钮，详情页 / 书写页同款全 app
  统一）。给组件加可选 `iconColor` 参数承载 hero 亮暗自适应色
  （`topBarIconColor()`，iOS `toolbarColorScheme` 同款逻辑）。官方沉浸
  光感材质在内容区不生效（官方《沉浸光感》生效范围：仅系统标题栏 /
  底部 TabBar；本页系统标题栏为全面屏 hero 隐藏）——正好落在「官方
  组件不带沉浸感」形态：透明底 + stateEffect 按压反馈。系统返回钮
  （真正的官方返回组件）只存在于系统标题栏，启用即占位、全面屏 hero
  没了——与带不带沉浸光感无关，故不用。
- **返回键无反应回归（用户报，2026-10-21，已修）**：根因 = 上一轮修
  「标题压状态栏」时把居中标题包进了**全宽 44vp Row**，Stack 里后声明
  = z 更高，正好盖在图标行上吞掉全部触摸（旧版标题是不定宽 Text、
  两侧空隙能透传才没暴露）。修 = 标题 Row 加
  `hitTestBehavior(HitTestMode.None)` 穿透。🔴 教训两条：① Stack 兄弟
  全宽节点永远考虑触摸遮挡；② 上轮「点击返回 ✓」是**假阳性验证**——
  用「y200-400 深色像素多」判回书架，磨砂态列表文字同样命中；本轮
  改用整屏差异比例（37.3%）+ 书架大标题双重标记。
- **底条与 Tab 胶囊的 36vp 不透明死带（用户报「和 iOS 不一致」，2026-10-21，
  已修）**：iOS 底条是 `safeAreaInset(edge: .bottom)` 直接坐在系统
  tab bar 上沿（无间隙）；鸿蒙旧值清让 90vp 让底条浮在胶囊上方
  36vp，中间夹一条什么都不放的奶油色死带。修 = `BOTTOM_BAR_
  CAPSULE_CLEARANCE_VP` 90→54，底条底边与胶囊可见顶边平齐（真机
  实测胶囊顶 = 屏底上方 87vp@3x；底条底 2184px 与胶囊顶 2178px 重叠
  6px，胶囊 barOverlap 在上层盖住，视觉无缝）。滚动内容底部清让公式
  不变，末端距底条顶仍 24vp（iOS padding(.bottom, 24) 同款）。
- **滚动内容透视过半透明 Tab 胶囊（用户报，2026-10-21，已修）**：根
  Stack 底对齐、Scroll 铺满整页，滚过的目录行会从底条底下和胶囊磨砂
  里透出来（iOS 视口天然裁在 safeAreaInset 条上沿）。修 = Scroll 视口
  显式裁到底条上沿：`.height(scrollViewportHeight())`（容器高 −
  底条顶到屏底距离）+ `.position({x:0,y:0})` 钉回顶部 + 尾部 Spacer
  简化为 24。真机像素复验：滚到底后 1978px 以下零内容像素，胶囊区
  干净。
- **🔴 设备 OTA 改了安全区避让模型 → 其他颜色日记本顶部白色色块
  （用户报，2026-10-21，已修，根因级）**：系统 OTA（伴随 density
  3.0→3.125、状态栏 126→121px）后 ArkUI 默认把整棵组件树**渲染**避让
  到状态栏下面（布局仍全屏：dump `origBounds=[0,0]` vs `bounds=[0,122]`），
  `getWindowAvoidArea(TYPE_SYSTEM)` 随之报 **0**（内容不再与状态栏
  重叠就没有可避让区）——应用的手动让位链路（safeAreaTopVp 全 app
  padding）整体失效，状态栏底下露出窗口底色：素笺主题米色不显眼，
  WineRed/皮革页就是一条刺眼白块。**getWindowAvoidArea 上报的语义
  实测 = 当前内容与避让区的实际重叠量**（底部边缘到边 → indicator
  87px 真值照常上报）。修 = Index 根 Stack
  `.expandSafeArea([SafeAreaType.SYSTEM], [TOP, BOTTOM])`：绘制区域
  扩回边缘到边，TYPE_SYSTEM 恢复上报 121px（hilog 实测
  `sysTop=121 indicatorBottom=87`），safeAreaTopVp=38.72 让位链路
  整体复活。顶栏图标 y168-212 修前后同位（避让平移 + margin=0 与
  零平移 + margin=38.72 两组数值屏幕坐标巧合相等，各页无回归）。
- **Scroll 受限高度 + 内容不满一屏 = 内容居中（faqs-arkui-725，已修）**：
  视口裁剪后空本子内容 522vp < 视口 633vp，Scroll 默认把短内容垂直
  居中 → hero 顶上顶出 ~55vp 死区。修 = 内容 Column
  `.constraintSize({ minHeight: scrollViewportHeightVp() })` 顶齐。
- **技术坑（复用必读）**：① 系统磨砂材质（Thin/ULTRA_THICK 等）自带
  近乎不透明白底，`backgroundColor` 叠色会被材质埋掉；要自定义透明
  磨砂只能用 `backgroundEffect`。② 页面内容短于视口时 Scroll 拖动只有
  弹簧回弹、截图零变化——验证滚动行为前先确认内容足够长（本次往库里
  直插 8 条测试日记才滚得动）。③ **截图像素分析**：`sips` 转 BMP 后
  JPEG 源是 24bpp（步长 w×3）、PNG 源是 32bpp（步长 w×4），必须先读
  `readUInt16LE(28)` 位深再定步长——步长用错坐标错位且越界读空
  （本轮白色块排查时曾因此误判旧截图）。④ `uitest dumpLayout` 的
  `bounds` 是安全区避让后的渲染框、`origBounds` 是布局框；expandSafeArea
  生效后 bounds 元数据不变但绘制已扩展（以截图像素为准）。
- **恢复 iOS 版式时改**：`BookDetailView.ets` 的 `HERO_HEIGHT_RATIO`、
  顶栏磨砂底 Column、`BookHeroView.clothHero` 的 justifyContent 三处。

### Q36 🟡 3.5 阅读器三条声明偏差 + 仿真翻页技术坑（2026-10-22 代码完成；2026-10-22 深夜真机材质对齐华为完成，见「追记」）

- **偏差① 仿真翻页替代 iOS 页卷转场（用户拍板，R-READ-07 允许）**：
  iOS 阅读器用系统 `UIPageViewController(.pageCurl)`；鸿蒙无系统页卷
  转场，华为 Reader Kit 排除（不可用）。终稿 = 官方《翻页动效》最佳
  实践配方移植（`views/reader/PageCurlNode.ets`）：三页 Stack（上一页/
  当前页/下一页）+ `componentSnapshot.getSync` 截图 + `NodeContainer`/
  `RenderNode` + `drawPixelMapMesh` 沿折线 E-H 的 3×3 反射矩阵画折起
  背面 + pathA/pathC/pathB 阴影全套。**backward（右滑回上一页）=
  forward 水平镜像**（canvas translate+scale(-1,1) 后几何与截图逻辑
  完全复用）。松手进度 >35% 或甩速 >600vp/s 补完、否则回弹（16ms
  setInterval，官方节奏）；翻页动画期间 animating 锁新手势（iOS 实机
  教训：转场交错崩）。
- **偏差② 大屏单列页宽封顶 420vp**：iOS 阅读器单列、无此约束；鸿蒙
  大屏（≥600vp 断点）若行宽吃满 716.8vp 每行字数过长不可读，页宽
  封顶 `ReaderLayout.maxPageWidth` 420 居中。
- **偏差③ 尺寸常量待真机核对**：trace 25 / audio 60 / photoHeight
  剪裁策略等从 iOS pt 1:1 换算，真机验收时一并核对。
- **技术坑（复用必读）**：① `GestureEvent` 本 SDK **无 localX/localY/
  velocityX 字段**——位置在 `fingerList[0].localX`（FingerInfo），速度
  需手动采样（隔 ~8ms 记两帧位移/时间自算，dt>160ms 回 0）；②
  `lineSpacing(number)` 不收裸 number，要 `LengthMetrics.vp()`
  （2.3/3.3 后第三犯）；③ `NodeController` 只有抽象 `makeNode`，无
  addNode/clearNodes——自包根 FrameNode，每帧 new CurlRenderNode +
  setNode（remove+append）触发重绘（官方样例同款）；④ 翻页后页面
  内容刷新用 **ForEach 单元素数组 + 带页号 keyGenerator** 强制子树
  重建（V1 plain 成员变化不触发子组件重渲染的坑）；⑤ NodeContainer
  加 `hitTestBehavior(HitTestMode.None)` 才不拦底层手势；⑥
  `hvigorw assembleHap` 需要 `JAVA_HOME`（export DevEco 自带 JBR）。
- **验收口径**：真机翻书手感（卷页跟手/松手补完/回弹/甩页）、R-READ-05
  长文不截断、R-READ-06 三主题、页眉页码/续页小标题/结尾页；若每帧
  setNode 换节点真机掉帧，备选方案 = 单节点+状态更新重绘。
- **追记（2026-10-22 深夜，角卷材质对华为 hc4 逐像素标定完成，真机全验证）**：
  - **对标方法**：华为阅读（com.huawei.hmsapp.books）抓拍 hold 帧
    （hc1-hc8，关键 hc4 = 触点 (600,700)），PIL 逐行剖面 + 白像素中位
    （>150 滤文字干扰）+ 多模态裁剪放大交叉验证。**先决条件：对比双方
    渲染几何必须一致**（首次采样错用未约束基准 A，全部剖面错位返工）。
  - **华为角卷材质实测基准**（W=1080，纸底 249 归一）：背面带 = 渐变
    88%（弦侧）→ ~98-100%（折缘受光），clip 五边形 = **直线边缘**
    （pathC 画在 pathA 之上，B 左侧楔形 = 镜像背面内容，文字方向
    镜像）；弦影带 = 沿弦 0x1E(88%) 起 ~0.22W 衰减，画在透出页上；
    折缘平页侧 B-A 软影 [0x14→0x05] ~0.12W、D-B 侧 [0x1E→0x06]
    ~0.03W、**A-K 侧无**；楔形区（B 左侧）hw 压暗 88%。
  - **跟手约束放宽**：华为真机渲染 A=(600,700) **不被约束**（多扫描线
    证明；官方样例 0.6 会浅 74px 破坏跟手）→ `TOUCH_CIRCLE_RATIO`
    0.6→0.7（(600,700) 恰过圆 maxY=703.8，极深拖拽仍夹回防退化）。
  - **绘制序终稿（drawCornerCurl 五步）**：① 弦影带（端点外延 0.06W
    盖 I/D 角隙）→ ② pathA 平面页 → ③ pathC 背面带（反射矩阵 +
    drawPixelMapMesh，**画在 pathA 后** = 直线边缘 + 楔形镜像内容）→
    ④ 背面暗化渐变 [chordMid→A, 0x1E→0x04] fill pathC → ⑤ 折缘带
    D-B + B-A（awayFrom 用弦中点；早期 awayFrom=geo.I 因 I 位于
    A-K 延长线下方致带翻转进背面带，B-A 带平页侧全丢——几何敏感
    bug 教训）。
  - **右缘返回手势冲突（真机 Mate X6 实测）**：系统返回手势区
    x≥~1008（72px）会消费触点，角抓取永远到不了 app——华为同款
    Navigation 机制，系统限制接受。终稿 = NavDestination
    `.onBackPressed((): boolean => true)` 拦截系统返回（依据
    faqs-arkui-1117：拦截侧滑+标题栏返回+返回键，不拦
    navPathStack.pop()，悬浮返回键照常退出）。**测试注入注意**：
    uinput 从 x=1050 起手不触发 app 手势（系统区），从 x=1000 内
    起手正常。
  - **边折模式触发**（易误测）：方向判定需水平位移过 6vp 阈值——
    纯竖直注入不触发任何翻页；边折 = 水平拖拽且起手不在角落区
    （如 (950,700)→(500,700)），竖直折缝渲染 + commit 验证 ✓。
  - **回归结论（真机）**：四角（TR/BR/TL/BL）背面带 90-92% +
    commit 全过；边折 crease x≈780-900 竖直暗带 + commit 过；
    取消路径（x=980 小拖松手）无 commit 页恢复；`compare_images`
    hc4 vs 终稿 = **零差异**；hilog 无 Drawing_napi mesh 报错。
  - **像素取证方法论**：① 对比前必须确认双方渲染几何一致（约束/
    触点差异毁所有剖面）；② 正文区扫描线单值不可靠——文字抗锯齿
    边缘 ≈ 88-96% 与阴影带同域，须白像素中位 + 多点剖面；③
    recognize_ui_components 是组件识别工具不做材质对比，材质对比
    用 compare_images；④ 本模型不支持直接读图（read 图片文件报错），
    视觉判断走 compare_images / 多模态工具。
  - **追记（2026-10-23 用户反馈「字体排版 + 纸感都不行」后的重构）**：
    - **字体排版**：`ReaderTextAdapter` 不再用 `ceil(fs×1.5)+sp` 估算，
      改为 graphics.text 实测「国Ag」自然行高 + `lineSpacing`；渲染用
      `heightOnly:true + heightScale`（此前只设 heightScale、没开
      heightOnly，参数被忽略，实绘仅 ~19.7vp/行，分页却按 32vp 算，
      导致页底留白与断页都不对）。字体族显式映射 `Noto Serif`（西文，
      对齐 Georgia）+ `HarmonyOS Sans SC`（中文回退，对齐 iOS
      Georgia→PingFang）；`serif` generic 在 graphics.text 里不是有效
      family，会整段退默认无衬线。真机验证：正文行距 ~30vp、页数
      1/5→1/7，页眉日期/标题/页码字号保持 iOS 同值。
    - **纸感翻书**：去掉「上下角 A-K 锥形角卷」触发（用户反馈上下角
      翻页质感不行），所有水平拖拽统一整页卷曲；被卷起的一半用当前页
      `cloneSync + flipSync(true,false)` 的水平镜像副本，按 24 条竖条铺到
      折缝另一侧（轻微圆柱弯曲），整层 92% 不透明、留 8% 让下一页隐约
      透出（薄纸 show-through），再叠折缝高光 / 折缘投影 / 透出页暗化。
      代码：`PageCurlNode.drawEdgeCurl` + `DiaryReaderView.beginFlip`；
      `CurlMath` 的角卷纯函数与单测保留，但手势不再触发。
    - **验证**：488 单测全绿、`assembleHap` BUILD SUCCESSFUL、
      `check_localization` 过绿；字体真机截图已验；纸感重构后 USB 断开，
      真机录屏 / 像素对比待设备重连（模拟器冒烟另记）。

### Q37 ⚪ 一键登录（LoginType.QUICK_LOGIN）调研结论（2026-10-25）

**是什么**：`LoginWithHuaweiIDButton` 的第三种登录形态（`LoginType.QUICK_LOGIN = 3`，API 5.0.0(12)+）。
用户点一下按钮 → Account Kit 返回华为账号的**匿名手机号**（脱敏）+ openID/unionID/authorizationCode/idToken →
**服务端**拿 authorizationCode 调华为 REST `/oauth2/v6/quickLogin/getPhoneNumber`（需应用级 token，
即 Client ID + Client Secret 的 client_credentials，Q1 已配）换**真实手机号** → 以该手机号直接建/登账号。
等价于「运营商一键登录」的华为账号版：**免验证码、登录即绑手机号**。

**关键约束**（d.ts 官方注释）：
- 匿名号拿不到时须降级其他登录形态（华为账号未绑手机号的用户走不了）
- 不支持 icon / 图文按钮形态，**只能纯文本按钮**
- 手机 / PC 二合一 / 平板 / TV(仅 5.1.1) 可用，其余设备 1001500003
- 响应字段与 ID 型相同（openID/unionID/authorizationCode/idToken），多一个匿名手机号

**对尺素的价值**：R-ACCOUNT-03「手机号必绑」红警告的根治——现在华为登录建号不带手机号，
用户要手动补绑（SMS 验证码 + 输入）；QUICK_LOGIN 登录即有手机号，红警告场景大幅消失。

**建议**：**v1 不做，v1.1 候选**。理由：① 服务端要加 `/auth/huawei` 的 quickLogin 分支
（authorizationCode → 应用级 token → 华为 REST 换手机号 → 手机号建号逻辑），而服务端当前
连 `/me/delete` 华为分支还有 500 待修（Q17），带宽有限；② 手机号补绑流程（4.3）已覆盖痛点；
③ 客户端侧改动小（登录页加一个文本按钮 + LoginType 切换），随时可加。
产品拍板要做时：客户端 LoginView 加 QUICK_LOGIN 文本按钮（「华为账号一键登录」），
服务端加分支，验收口径 = 登录后 user.phone 非空、账户页无红警告。

### Q38 🔴 线上 POST /me/bindings/phone 500（2026-10-25 实测）

**现象**（Mate X6 真机，4.4 收尾顺带复测 4.3 补绑手机号 E2E）：
- 发码正常（`/auth/send-code` 200，倒计时 59s，次日额度已重置）；
- 输入**新鲜验证码**（965973，发送后 ~1 分钟内提交）→ 6 位自动提交 →
  服务端返 `500 {"error":{"code":"internal","message":"服务器内部错误"}}`；
- **验证码已通过校验**（错误桶从「请先获取验证码」变为「服务器内部错误」），
  且**码已被消费**（重输同码报「请先获取验证码」）——即崩在校验通过后的绑定写库步。
- 首次提交（590321，用户误读昨日遗留短信）被拒「请先获取验证码」属预期，
  非 bug；真 500 观测 1 次（重试需新短信，未烧额度复测第二次）。

**客户端已核对无误**：请求体 `{target, code}` 与契约一致（sendCode `{target}`、
login `{target, code}` 同构）；bearer 带上；envelope.message 正确透出。
已加诊断日志（LoginView.bindPhone catch，status≥500 打 kind/status/body）。

**待后端（尺素）排查**：switchedAccount 转移路径（17375778851 疑似挂着 4.2/4.3
时期测试账号，转移逻辑可能崩）或绑定写库约束。与 Q17（/me/delete 华为分支 500）
同日出现，疑似同一部署引入的写路径回归。修复前补绑手机号 E2E 收不了尾。
