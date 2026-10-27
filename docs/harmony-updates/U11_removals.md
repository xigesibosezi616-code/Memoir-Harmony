# U11 · 要删掉的东西（工作清单，iOS / 后端 / 鸿蒙共用）

> 基于：**v1 + U01（草稿）+ U02**｜ 状态：**草稿**（边删边勾；全部删完、产品确认后交付）
> 2026-10-24 产品定：**不再用的东西，代码、文案、文档一起删干净**，别留「以后也许用得上」的半截代码 —— 留着就会被鸿蒙照着实现，也会被审核、用户看到。
> 这份既是我们自己的删除清单，也是鸿蒙的：每一项写了 iOS 在哪、后端在哪、鸿蒙 v1 施工图里在哪、鸿蒙要做什么。

---

## 怎么读

- **✅ 已删**　**☐ 待删**（已定，还没动手）　**⏸ 推后**（先不删，文档注释都留着）
- 鸿蒙：v1 施工图（`docs/harmony-spec/`）冻结不改，**以本包为准**；本包列到的 v1 条目视为作废或改写

---

## 一、确定要删的

### 1. 「青鸟」这个名字 ✅ iOS / 后端（2026-10-24）

**为什么**：笔友的名字只能是用户自己起的。没起名之前，界面上一律叫「笔友」（七种语言各自的「笔友」），**任何地方都不再出现「青鸟」**（2026-10-24 产品定）。
首启的「给笔友起个名字」**不能跳过**，不起名进不去（2026-10-23 已定，本包一起落实）。

| 端 | 在哪 | 改成 |
|---|---|---|
| iOS 默认值 | `@AppStorage("penPalName")` 默认 `"青鸟"`：`OnboardingView`、`SettingsPenPalView`、`PostBoxView`、`LetterboxView`、`PracticeLetterView` | ✅ 默认空串；显示、寄信一律过 `PenPalName.display`（没起名叫「笔友」，`Services/PenPals/PenPalName.swift`） |
| iOS 引导页 | `OnboardingView`：占位「青鸟」、可跳过、空了回退「青鸟」 | ✅ 占位「写一个名字」、**不能跳过**：没名字「开始书写」是灰的；下面一行「笔友会用这个名字给你写信，之后在设置里也能改」；名字最长 16 个字 |
| iOS 设置页 | `SettingsPenPalView`：占位「青鸟」、清空回退「青鸟」 | ✅ 先编辑、确认再存；清空了恢复原名（离开页面也一样） |
| iOS 数据 | `Letter.fromCharacter` 默认 `"青鸟"`（`Models/Letter.swift`；旧版 `SchemaV5`–`V9` 里的同名默认值是历史快照，不动） | ✅ 默认空串（寄信时总会写入当时的名字；默认值不进数据模型的版本校验，不触发迁移） |
| iOS 测试桩 | `AuthService.swift` 的 Mock 用户 `penPalName: "青鸟"` | ✅ 换成「阿远」 |
| iOS 注释 | `AIService.swift`、`PostBoxView`、`OutgoingPile`、`SealedEnvelope`、`WorldMapPage` 里举例用的「青鸟」 | ✅ 换成「阿远」 |
| iOS 文案 | `Localizable.xcstrings` 里 key「青鸟」一条；「可跳过，之后在设置里也能改」一条 | ✅ 删；新增「写一个名字」「笔友会用这个名字给你写信，之后在设置里也能改」（七种语言） |
| 已有用户 | 名字还是默认「青鸟」或空的（上架前只有内测机） | ✅ 进主界面先弹「给笔友起个名字」（`PenPalNamingSheet`），起好才能关 |
| 后端 | `china/scripts/schema.sql`、`global/scripts/schema.sql`：`pen_pal_name ... DEFAULT '青鸟'`；测试里的「青鸟」 | ✅ 建表脚本默认空串、测试换示例名；☐ 线上库的列默认值还是旧的（App 不读这一列，不影响界面），下次动数据库时一起 `ALTER`（要先问） |
| 文档 | `WORLD_PENPALS.md`、`AUTH_DESIGN.md`、U01 草稿、U02（已交付，冻结 —— 以本包为准） | ✅ 举例换掉；U02 以本包为准 |

**鸿蒙**（v1 里写了青鸟的地方，全部作废）：
`00_PRODUCT_OVERVIEW.md` 53、95 行；`02_BACKEND_API.md` 103、226–266 行的示例；`03_USER_FLOWS.md` 15 行（可跳过 → 改为不能跳过）；
`04_DESIGN_LANGUAGE.md` 125 行；`05_DATA_MODEL.md` 274、368、429 行（默认值改空串）；`06_RULES.md` **R-APP-06**（占位、可跳过 → 不能跳过）；`09_OPEN_QUESTIONS.md` 86 行；`10_BUILD_MANUAL.md` 引导页那一步。

### 2. 集邮册、每周快递封、15 张邮票图 ⏸ 推后

**2026-10-24 改主意：不删，往后推**。邮票还要做，只是集邮册、撕快递封这些精美的动画等用户多了再做；相关的**文档和注释先全部保留**。
这几样从没写成代码。眼下的替代做法见第 4 项（每周一个小弹窗领邮票）。

| 在哪 | 怎么办 |
|---|---|
| `WORLD_PENPALS.md` 决策 9、第 6 步「集邮册」 | 留着 |
| U01 草稿里集邮册、快递封、邮票图的各节 | 留着，交付 U01 时标成「以后做」 |
| 代码注释「快递封动画做好之前悄悄领」（`AIService.swift`、`PostBoxView.swift`） | 留着 |

**鸿蒙**：这几样**先别实现**，等 U01 交付时看标注。

### 3. 「他记得的事」给用户看、让用户删的界面 ✅ 已撤（2026-10-24）

**为什么**：笔友记住的关于用户的事**不给用户看，也不能删**（2026-10-24 产品定）。原计划在世界笔友第 6 步做这个界面，撤销。

| 在哪 | 怎么改 |
|---|---|
| `Models/PenPalNote.swift` 注释「用户能看、能删（界面在第 6 步）」 | 删这句，写明不做 |
| `WORLD_PENPALS.md` 199 行 | 删 |
| U01 草稿里对应的描述 | 删 |

**鸿蒙**：不做任何查看 / 删除「笔友记得的事」的界面。（这些内容只存在用户手机和他自己的云里，跟着备份包导出 —— 不变）

---

## 二、2026-10-24 拍板的

### 4. 邮票额度本身 —— **保留**

现在的邮票**不是摆设，是寄信的额度**：每周悄悄领一包、寄给远的笔友贴的票多（南极 2 张，其余 1 张）、票不够就寄不了，邮筒页显示「邮票 N 张」（2026-10-23 定的是「保留计数、只显示数量」）。

如果连额度也删：
- iOS：`StampWallet`、邮筒页的余额 / 用完提示（「邮票用完了，新的一包……」「贴 %lld 张邮票」三条文案）、`PenPalRoster.postage`、`LetterOutbox` 里的扣票、`Letter.postage`、备份包里的邮资字段
- 后端：`stamps.ts`、`stampStore.ts`、`/me/stamps`、`/me/stamps/claim`、`stamp_wallets` / `stamp_ledger` 两张表、寄信时的扣票
- **必须同时定：寄信的频率用什么来限**（不限的话，大模型的费用没有上限）

**产品定：保留**（2026-10-24）。眼下的做法：**每周弹一个小窗**，点「领取」拿到这周的邮票额度；寄信照常扣票。简陋一点没关系，用户多了再做信封、集邮册这些精美的动画。
✅ **领邮票的小卡片做好了**（2026-10-27，iOS `Views/PostBox/Posting/StampPackCard.swift`，接在 `PostBoxView.refreshStamps`）：

- **什么时候出**：进邮筒页时问一次 `GET /me/stamps`；`packReady` 为真**而且** `balance < cap`（邮票夹没满）才出；没登录不出。原来那句「能领就悄悄领」去掉了
- **样子**：整屏压一层 22% 的黑；中间一张 270pt 宽的卡片（主题卡片色、圆角 20、细边、柔和阴影），从下方 14pt 淡入上浮（easeOut 0.35s，**不回弹**）
  - 上面三张叠着的齿孔邮票（44×52，左右两张各歪 -9° / 7°），**票面只印手写 m.**（和桌面图标同一笔，**不印任何字**，用户定），墨色 = 邮戳色、纸色 = 信纸色
  - 「这周的邮票到了」（标题字）/「寄信时，一封贴一张」（说明字）
  - 「领取」：主题强调色的胶囊按钮，44pt 高；点了换成转圈，调 `POST /me/stamps/claim`
  - 「稍后」：浅色小字，点了收起；**下次进邮筒页还会再出**
- **领到以后**：三张邮票收拢成一摞（0.45s），文字换成「+N」（领到几张，衬线大字）/「放进邮票夹了」，停 1.4 秒淡出
- **领取失败**：顶上提示「邮票没领到，过一会儿再试」，卡片回到能再点的样子
- **不点也不耽误寄信**：寄信时服务端本来就会把到期的那一包补上（`claimIfDue`），所以卡片上不写「必须领取」

| 中文 | 繁中 | English | 日本語 | 한국어 | Français | Español |
|---|---|---|---|---|---|---|
| 这周的邮票到了 | 這週的郵票到了 | This week's stamps are here | 今週の切手が届きました | 이번 주 우표가 도착했어요 | Les timbres de la semaine sont arrivés | Ya llegaron los sellos de esta semana |
| 寄信时，一封贴一张 | 寄信時，一封貼一張 | One stamp for each letter you send | 手紙1通につき1枚貼ります | 편지 한 통에 한 장씩 붙여요 | Un timbre pour chaque lettre envoyée | Un sello por cada carta que envíes |
| 领取 | 領取 | Collect | 受け取る | 받기 | Récupérer | Recoger |
| 稍后 | 稍後 | Later | あとで | 나중에 | Plus tard | Más tarde |
| 放进邮票夹了 | 放進郵票夾了 | Added to your stamps | 切手入れにしまいました | 우표첩에 넣었어요 | Rangés avec vos timbres | Guardados con tus sellos |
| 邮票没领到，过一会儿再试 | 郵票沒領到，過一會兒再試 | Couldn't collect your stamps. Try again in a moment | 切手を受け取れませんでした。少ししてからもう一度どうぞ | 우표를 받지 못했어요. 잠시 후 다시 해 주세요 | Impossible de récupérer les timbres. Réessayez dans un instant | No se pudieron recoger los sellos. Inténtalo de nuevo en un momento |

**鸿蒙**：照上面做；邮票的齿孔、内框画法同名片邮票框，票面的 m. 用 U09 的字形数据。

### 5. 笔友名片上的邮票框 —— **保留**

世界笔友名片右上角有一个「齿孔边框 + 地区码」的邮票占位框（`PenPalCard.swift` 的 `StampPlaceholder`），注释写着「第 3 步换成每位笔友的邮票图」。邮票图不做了，这个框会一直是占位。
**产品定：保留**（邮票还要做，邮票图以后再上）。

### 6. 封存的视频开场 ✅ 已删（2026-10-24）

`Views/Splash/SplashVideoPool.swift`、`SplashVideoPlayerView.swift`：早先的「视频轮播开场」，封存着没删，视频文件已经一个都没有了。开场现在是一笔写出 m.（U09）。
✅ 两个文件和 `SplashView` 里的视频分支、空的 `Resources/SplashVideos/` 都删了；`MEMOIR_DEV_SPEC.md` 那一节改成「已删」；开场现在的设计写在 `Memoir/MEMOIR_SPLASH.md`。
**鸿蒙**：v1 里没有视频开场，不用做。

### 7. 会员专属「笔友性格任选」✅ 已删（2026-10-23 定，10-27 付费页换掉）

原计划会员可以在几种笔友性格（温柔 / 话少 / 爱引诗……）里挑，一直没做。世界笔友上线后，15 位笔友本身就是 15 种性格，这一项删掉。
✅ iOS 付费页第三条「挑一位合你心意的笔友 / 笔友的性格由你选」换成「今雨与雅故 / 十五位住在世界各地的笔友，用母语给你回信，信纸背面附上译文」（「今雨与雅故」是世界笔友在界面上的名字，见 U01），图标换成地球；`MEMBERSHIP.md` 跟着改。
**鸿蒙**：付费页那一条照下表换；不做任何「选笔友性格」的设置项。

| 中文 | 繁中 | English | 日本語 | 한국어 | Français | Español |
|---|---|---|---|---|---|---|
| 今雨与雅故 | 今雨與雅故 | New Friends & Old | 新しき友、古き友 | 새 벗과 오랜 벗 | Amis d’hier et d’aujourd’hui | Amigos nuevos y de siempre |
| 十五位住在世界各地的笔友，用母语给你回信，信纸背面附上译文 | 十五位住在世界各地的筆友，用母語給你回信，信紙背面附上譯文 | Fifteen pen pals across the globe write back in their own language, with a translation on the back | 世界各地に住む15人のペンフレンドが母語で返事をくれます。便箋の裏には翻訳つき | 세계 곳곳에 사는 펜팔 열다섯 명이 모국어로 답장해요. 편지지 뒷면엔 번역이 있어요 | Quinze correspondants à travers le monde vous répondent dans leur langue, avec une traduction au dos | Quince amigos por carta de todo el mundo te responden en su idioma, con la traducción al dorso |

---

## 三、作废的旧规则（不是删功能，是换了做法）

| 旧的 | 新的 | 写在哪 |
|---|---|---|
| 回信长度固定（世界笔友每位人设里写死一句长度；自己起名那位写死「短」） | 按**距离这位笔友上一封多久**定长短：不到 2 天短一点、一周内照常、一个月内多一段、更久写长信；人设的长度只当基准（✅ 2026-10-24 后端已改，`Backend/shared/src/letterLength.ts`） | **鸿蒙不用做**：长短全在服务端定，两端共用同一个后端 |
| 「他记得的事」= 世界笔友每位一串小纸条，只带最近 20 条 | 每位笔友一本「手记」：**画像**（这个人是谁，一份完整的文本）+ **大事**（带日期的事和节点）；**自己起名的那位也有**；每位各记各的（✅ 2026-10-27 iOS、后端已做，后端待部署） | ✅ 已写进 U01「笔友手记」一节（R-NOTEBOOK-01–06） |

---

## 进度

| # | 项 | iOS | 后端 | 文档 | 鸿蒙 |
|---|---|---|---|---|---|
| 1 | 青鸟 | ✅ | ✅（线上库默认值待改） | ✅ | ☐ |
| 2 | 集邮册 / 快递封 / 邮票图 | ⏸ 推后 | — | ⏸ 留着 | 先别做 |
| 3 | 「记得的事」界面 | ✅（注释） | — | ✅ | 不做 |
| 4 | 邮票额度 | 保留；✅ 每周领邮票的小卡片（10-27） | 保留 | ✅ | ☐ 做领取卡片 |
| 5 | 名片邮票框 | 保留 | — | — | 保留 |
| 6 | 视频开场 | ✅ | — | ✅ | 不用做 |
| 7 | 笔友性格（付费页那一条） | ✅ | — | ✅ | ☐ 换付费页文案 |
