# 05 · 本地数据模型（权威）

> **这份是鸿蒙端本地库的施工依据。** 字段名、取值、默认值、语义必须与 iOS 一致 ——
> 两端之间唯一的数据通路是备份包（`EXPORT_FORMAT.md`），字段对不上 = 互导丢数据。
>
> - iOS 对照：`Memoir/Models/*.swift`（SwiftData `@Model`，当前 schema **V8**）
> - 备份包字段：`Memoir/Services/Backup/BackupFormat.swift` + `Memoir/Docs/EXPORT_FORMAT.md`
> - 核对日期：**2026-10-12**（对着 V8 源码逐字段过了一遍）
>
> 存储方案鸿蒙自己定（建议 RDB + Preferences），**但本文的「逻辑字段」不许改名、不许改语义**。
> 下面给的建表 SQL 是建议，不是契约；契约是字段语义和备份包。

---

## 0. 通用约定（先读）

| 项 | 约定 | 为什么 |
|---|---|---|
| **id** | UUID 字符串。iOS 写出的是**大写带横线**（`8B1F2C3D-...`）。鸿蒙生成的也写大写；**比较时忽略大小写** | 备份包按 id 去重，大小写不一致会把同一篇当成两篇 |
| **本地时间字段** | 建议存毫秒时间戳（INTEGER） | — |
| **墨迹类时间**（`writtenAt` / `struckAt` / `addedAt` / `removedAt`） | **Unix 秒，浮点数**（`Double`） | 存在内容块 JSON 里，两端、备份包都是这个单位 |
| 🔴 **备份包里的日期** | ISO8601，**不带毫秒**：`2026-08-05T12:00:00Z` | iOS 解析备份包用的是不认小数秒的解析器 —— **鸿蒙导出的包如果写 `toISOString()`（带 `.123`），iOS 导入会失败**。导出时去掉毫秒；读取时两种都认 |
| 后端接口里的日期 | `toISOString()`，**一定带毫秒** | 见 `02_BACKEND_API.md`。解析时两种都认 |
| 字符串区间 | **UTF-16** 偏移与长度 | 与 NSString、ArkTS 字符串下标一致 |
| 字数 | iOS 按 Swift `Character`（字形簇）计 | ArkTS `length` 是 UTF-16 单元，emoji 会多算。中文、英文字母两端一致即可，emoji 差异可接受 |
| 列表类字段 | 本地存 JSON 字符串 | `tags`、`audioURLs` 等 |
| 非可选字段 | **一律有默认值** | 云同步记录可能缺字段（iOS CloudKit 的硬约束，鸿蒙若做云同步同理） |

---

## 1. 实体总览

| 实体 | iOS 类型 | 作用 | 鸿蒙建议表名 |
|---|---|---|---|
| 日记 | `JournalEntry` | 一篇正式日记 | `journal_entry` |
| 内容块 | `ContentBlock`（值类型） | 正文的结构化内容，**JSON 存在日记的一列里**，不单独建表 | — |
| 日记本 | `Tag` | 书架上的一本（**名字就是身份**） | `notebook` |
| 心情 | `MoodTag` | 12 个预设心情 | `mood` |
| 来信 | `Letter` | 笔友回信（含在路上 / 写信中 / 退回） | `letter` |
| 信 ↔ 日记 | `Letter.relatedEntries` | 多对多 | `letter_entry` |
| 草稿 | `DraftEntry` | 没写完的那一篇，**全局只留一份** | `draft` |
| 媒体云副本 | `MediaAsset` | iOS 专为 CloudKit 同步照片文件而设，**鸿蒙按自己的同步方案决定要不要** | （可选） |
| 偏好 | `@AppStorage` | 见 §9 | Preferences |

---

## 2. 日记 `JournalEntry`

| 字段 | 类型 | 默认 | 语义 / 约束 |
|---|---|---|---|
| `id` | UUID | 新生成 | 备份包去重键 |
| `title` | string | `""` | **≤ 40 字，不含换行**（输入时去掉 `\n` 并截断）。可空 |
| `content` | string | `""` | **派生字段**：所有文本块的 `visibleText`（去掉划掉的字）用 `"\n\n"` 连接。字数、搜索、摘要、寄给笔友都读它。**只能由内容块写入时同步生成**，不许单独写 |
| `date` | 时间 | 创建时刻 | 日记属于哪一天。**目前 UI 不能改**（没有日期选择器）。排序键 |
| `mood` | string | `""` | 心情 **key**（`calm` …，见 §5），空 = 没选 |
| `moodColorHex` | string? | null | 选心情时一并存下的颜色快照 |
| `tags` | string[] | `[]` | 所在日记本的**名字**。🔴 **最多一个元素**（一篇日记最多属于一本）。空 = 只在「全部日记」 |
| `isFavorite` | bool | false | **iOS 没有任何 UI 用它**，只是随备份包来回带。鸿蒙存着、原样导出即可，不要做收藏功能 |
| `wordCount` | int | 0 | = `content` 的字数 |
| `createdAt` | 时间 | 创建时刻 | **真正写下的时刻**。「墨迹干没干」「邮筒要寄哪些」都按它判断，不按 `date` |
| `updatedAt` | 时间 | 创建时刻 | 内容块每次写入都刷新 |
| `audioURLs` | string[] | `[]` | **录音文件总清单**，相对路径 `"audio/<名>.m4a"`。同步、备份、删日记清文件**只认它**。存盘时由正文里的录音块按顺序生成 |
| `weatherCode` | string? | null | 天气图标标识。iOS 存的是 SF Symbols 名（如 `sun.max.fill`）。跨端词表见 `09_OPEN_QUESTIONS.md` Q7 |
| `weatherInfo` | string? | null | 温度文本，如 `"26°"` |
| `locationInfo` | string? | null | 地点文本，如 `"广州市"`、`"广州市 天河区"`、`"广州塔"` |
| `stampEmoji` | string? | null | 旧字段，**iOS 已不读不写**，也不在备份包里。鸿蒙不建 |
| `contentBlocksData` | JSON? | null | `ContentBlock[]` 的 JSON。为空时按 `content` 退化成一个文本块（老数据兼容） |

**删日记**：先删它引用的全部媒体文件（照片 / Live 原图 / Live 视频 / 录音），再删记录；若有云端副本，副本一起删。
来信不随日记删除（信里的关联置空即可）。整篇日记**随时可以删**（「墨迹会干」不限制删整篇）。

**派生（不存库）**：
- `photoFilenames`：正文里照片文件名，按出现顺序
- `coverPhotoFilename`：`isCover == true` 的那张；没有就第一张；没照片为空（大屏模式用）
- `textPreview`：文本块 `visibleText` 用 `\n` 连接后去首尾空白
- `addendumDays`：补记过的日子（见 §3.4）

---

## 3. 内容块 `ContentBlock`（正文的 JSON 结构）

正文 = `ContentBlock[]`，按数组顺序排版。**解析必须逐块容错**：认不出的 `type` 跳过该块，不能让整篇失败。

### 3.1 通用字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 块 id |
| `type` | `"text"` \| `"photo"` \| `"audio"` \| `"trace"` | 块类型 |

### 3.2 各类型字段

**`text` 文本块**

| 字段 | 说明 |
|---|---|
| `text` | 纯文字（**含划掉的字**，它们还留在纸上） |
| `styles` | `TextStyleRun[]`，可空。见 3.3 |

**`photo` 照片块**

| 字段 | 说明 |
|---|---|
| `photoFilename` | 显示用图片文件名（裸名，如 `photo_a1b2c3d4.jpg`） |
| `livePhotoVideoFilename` | Live Photo 视频（`.mov`），只有动态照片有 |
| `livePhotoStillFilename` | **未裁原图**，只有尺素相机拍的动态照片有（配对用）。为空时用 `photoFilename` 配对 |
| `position` | `"left"` \| `"right"`（没有居中） |
| `paperStyle` | 相纸，见 §3.5 |
| `rotationAngle` | 倾斜角度，`-3.0 ~ +3.0`，**创建时定死**，之后不变（不能每次渲染随机，会抖） |
| `isCover` | 大屏模式封面，一篇最多一张为 true |
| `addedAt` | 什么时候放进来的（Unix 秒），null = 日记写下时就有 |

**`audio` 录音块**

| 字段 | 说明 |
|---|---|
| `audioFilename` | 与 `audioURLs` 里同一个相对路径，如 `"audio/rec_xxx.m4a"` |
| `addedAt` | 同上 |

**`trace` 痕迹块**（墨迹干了之后取下的照片 / 删去的录音留下的一行字）

| 字段 | 说明 |
|---|---|
| `traceOf` | `"photo"` \| `"audio"` |
| `removedAt` | 取下的时刻（Unix 秒） |

### 3.3 文字格式 `TextStyleRun`

```json
{ "location": 13, "length": 4, "bold": true, "italic": null, "heading": null,
  "highlight": null, "writtenAt": 1760000000.0, "struckAt": null }
```

| 字段 | 说明 |
|---|---|
| `location` / `length` | **UTF-16** 区间，相对所在文本块的 `text` |
| `bold` / `italic` | 加粗 / 斜体 |
| `heading` | 小标题（整段格式，区间覆盖整段） |
| `highlight` | 荧光笔 |
| `writtenAt` | 这段字什么时候写的（Unix 秒）。null = 日记写下时就有 |
| `struckAt` | 什么时候划掉的（Unix 秒）。null = 没划掉 |

所有布尔字段可选，缺省 = false。`text` 永远是纯文字，不认识 `styles` 的版本照样能显示正文。

### 3.4 墨迹会干（数据层规则；交互见 `06_RULES.md` R-INK）

- **干的判定**：`now - (writtenAt ?? entry.createdAt) >= 24h`。还没存成日记的新稿一律不干
- **补记**：`writtenAt` 与 `entry.createdAt` **不是同一天**（按本地日历）
- **`visibleText`** = `text` 去掉所有 `struckAt != null` 的区间（从后往前删，越界的区间跳过）
- `content` / 字数 / 搜索 / 寄给笔友，一律用 `visibleText`

### 3.5 相纸 `PaperStyle`

| rawValue | 名称 | 会员 | 样子（详见 iOS `Views/Components/PhotoPaper/*Paper.swift`） |
|---|---|---|---|
| `original` | 原图 | 免费 | 无相框，仅圆角微裁 |
| `polaroid` | 宝丽来 | 免费 | 白色厚边框，底部留白 |
| `washiSticker` | 和风贴纸 | 会员 | 米白底、棕边、四角装饰 |
| `minimalCard` | 极简卡片 | 会员 | 淡色 0.5px 细边 |
| `filmFrame` | 胶片帧 | 会员 | 两侧胶卷齿孔 |
| `letterAttached` | 信纸附照 | 会员 | 像贴在信纸上，有阴影 |

默认相纸存在偏好 `defaultPaperStyle`（默认 `polaroid`）。存的是会员款而当前不是会员 → **实际按宝丽来**，存的值不改写。

### 3.6 正文规模上限（写日记 / 编辑页）

| 项 | 上限 |
|---|---|
| 照片 | 每篇 **5 张** |
| 录音 | 每篇 **3 段**，每段最长 **3 分钟** |
| 标题 | 40 字 |

---

## 4. 日记本 `Tag`

> 🔴 **名字就是身份**：日记靠 `tags` 里的名字字符串挂在日记本上，不是外键。改名必须连带改所有日记的 `tags`。

| 字段 | 类型 | 默认 | 语义 |
|---|---|---|---|
| `id` | UUID | 新生成 | 路由用 id（名字会被改） |
| `name` | string | `""` | 只去首尾空白存库，大小写 / 全半角**原样保留** |
| `color` | string? | null | 旧字段（早期 hex），**只供迁移读取**。鸿蒙不建 |
| `colorID` | string | `"WineRed"` | 封面颜色，见 §4.1 |
| `textureID` | string | iOS 声明默认 `"Leather"`，**新写一律 `"Linen"`** | 渲染不读；读取时一律按亚麻 |
| `lastOpenedAt` | 时间 | 创建时刻 | 保留备用，不渲染 |
| `createdAt` | 时间 | 创建时刻 | 排序的第二键 |
| `sortOrder` | int | 0 | 书架位置，小的在前；相同按 `createdAt`。**新建 = 现有最大值 + 1** |
| `coverPhotoFilename` | string? | null | 照片封面文件（`cover_<UUID>.jpg`，和日记照片同目录）。null = 纯色亚麻 |
| `coverLayoutID` | string? | null | 版式：`FullBleed` / `Framed` / `TipIn`，null 或不认识 = 满版 |
| `subtitle` | string? | null | 书名下的小字，≤ 24 字，去首尾空白，空 = 没有 |

### 4.1 封面颜色 `BookColor`（8 色，只有亚麻）

| rawValue | 名称 | 色点 hex | 浅色底？ |
|---|---|---|---|
| `WineRed` | 酒红 | `#592A2C` | |
| `PineGreen` | 墨绿 | `#34473B` | |
| `PrussianBlue` | 普鲁士蓝 | `#233C58` | |
| `Eggplant` | 茄紫 | `#3E2F43` | |
| `AmberBrown` | 琥珀棕 | `#7A5429` | |
| `Charcoal` | 炭黑 | `#201E1C` | |
| `Slate` | 石灰 | `#625F5C` | |
| `Ivory` | 象牙白 | `#EBE2D2` | ✅（字用深棕，其余用米白） |

**下架色映射**（读到这些一律换成右边，迁移、导入、渲染三处都要接）：

| 下架 | → 保留 |
|---|---|
| `RustRed` | `WineRed` |
| `OliveBrown` | `PineGreen` |
| `BronzeBrown` | `AmberBrown` |
| `Camel` | `AmberBrown` |

完全不认识的 colorID：**原样保存**（可能是更新版本加的色），渲染兜底酒红。
封面图素材：iOS `Assets.xcassets/Cover_<colorID>_Linen.imageset`（亚麻布面贴图，每色一张）。

- 新建日记本默认色：**墨绿**
- 「全部日记」的门面：**象牙白亚麻**（它不是数据库里的一条记录，是固定的第一格）
- 写日记页顺手新建的日记本：取书架上**用得最少**的颜色（象牙白除外；并列按上表顺序取第一个）

### 4.2 名字规则

- **判重键** = 去首尾空白 + 忽略大小写 + 忽略全角半角（`Travel` / `travel` / `Ｔｒａｖｅｌ` 是同一个）
- 起不撞名的名字：`旅行` → `旅行 2` → `旅行 3`（名字 + **半角空格** + 数字，不随语言变）
- 默认日记本：库里**一本都没有**时建 `生活 / 读书笔记 / 旅行 / 工作`，`sortOrder` 0–3，颜色墨绿
  （⚠️ 这四个名字是**用户数据**，按中文写入，不随界面语言翻译 —— 与 iOS 一致）

---

## 5. 心情 `MoodTag`（纯预设，用户不可增删改）

| 字段 | 类型 | 默认 | 语义 |
|---|---|---|---|
| `id` | UUID | | |
| `name` | string | | 🔴 **英文 key**，显示时按语言查表（`mood.<key>`） |
| `colorHex` | string | `#B8AD9C` | |
| `isDefault` | bool | false | 预设 = true |
| `sortOrder` | int | 0 | |
| `createdAt` | 时间 | | |
| `iconName` | string? | null | iOS SF Symbol 名，鸿蒙映射到自己的线性图标 |

**12 个预设**（顺序即 `sortOrder`）：

| # | key | 简中 | 繁中 | 颜色 | iOS 图标 |
|---|---|---|---|---|---|
| 0 | `calm` | 平静 | 平靜 | `#A8C5B8` | leaf |
| 1 | `productive` | 充实 | 充實 | `#C5B8A8` | flame |
| 2 | `reflective` | 沉思 | 沉思 | `#B8C5D4` | drop |
| 3 | `joyful` | 喜悦 | 喜悅 | `#D4C8A8` | sun.max |
| 4 | `low` | 低落 | 低落 | `#C5B8C5` | moon |
| 5 | `anxious` | 焦虑 | 焦慮 | `#D4B8B8` | bolt |
| 6 | `grateful` | 感恩 | 感恩 | `#B8D4C8` | heart |
| 7 | `excited` | 期待 | 期待 | `#D4C4B8` | star |
| 8 | `tired` | 疲惫 | 疲憊 | `#B8B8D4` | cloud |
| 9 | `peaceful` | 安宁 | 安寧 | `#D4D4B8` | wind |
| 10 | `nostalgic` | 怀念 | 懷念 | `#C5D4B8` | sparkles |
| 11 | `hopeful` | 希望 | 希望 | `#D4B8C5` | snowflake |

其余五种语言的译名在 `Localizable.xcstrings` 的 `mood.<key>` 条目。
首启插入全部 12 个；之后每次启动补齐缺的预设（按 key 判断）。
**导入时备份包里带的自定义心情（老版本）照样接收**，按名字去重，显示时直接显示原名。

---

## 6. 来信 `Letter`

| 字段 | 类型 | 默认 | 语义 |
|---|---|---|---|
| `id` | UUID | | |
| `relatedEntries` | → 日记（多对多） | `[]` | 这封信寄出的日记。日记删了**不删信**，读取时滤掉悬空引用 |
| `status` | string | `pending` | 见 6.1。**原样存字符串，不要过枚举**（导入时可能有不认识的值） |
| `body` | string | `""` | 回信正文。空 = 还没写好 |
| `fromCharacter` | string | `"青鸟"` | **寄出那一刻的笔友名快照**，之后改名不影响 |
| `toName` | string? | null | **寄出那一刻的用户昵称快照**。null = 抬头只写「致」 |
| `stationery` | string? | null | 信纸：null = 普通；`"sealed"` = 火漆信（会员）。**寄出那一刻定死**，不实时读会员状态 |
| `triggerKind` | string | `weekly` | 后端取值：`welcome` / `weekly` / `perEntry` / `daily` / `monthly`。iOS 现在寄信一律发 `weekly`。原样存字符串 |
| `errorMessage` | string? | null | 退回原因（仅 failed） |
| `generatedAt` | 时间 | 创建时刻 | 🔴 **寄出时刻**（点下邮筒那一刻） |
| `deliveredAt` | 时间? | null | 🔴 **到达时刻** = 寄出 + [6h, 72h] 均匀随机，寄出时就算好（是未来时间）。null 的老数据按 `generatedAt` 算 |
| `readAt` | 时间? | null | 读信时刻 |
| `updatedAt` | 时间 | 创建时刻 | |

### 6.1 状态与阶段（🔴 两端判定必须逐字一致）

`LetterStatus`：`pending` / `generating` / `delivered` / `read` / `failed`

| 阶段 | 判定 |
|---|---|
| 真正的信 | `body` 非空 且 `status ∈ {pending, delivered, read}` |
| **已到达** | 真正的信 且 `(deliveredAt ?? generatedAt) <= now` |
| **在路上** | 真正的信 且 `(deliveredAt ?? generatedAt) > now` |
| **未读** | 已到达 且 `status != read` |
| **写信中** | `status == generating` 且 `body` 为空（投进邮筒、回信还没写好；对用户也算「在路上」） |
| **退回** | `status == failed` 且 `body` 为空 且 **归本机负责**（见 6.2） |
| 不显示 | 其余（老版本残留的空正文记录、「不寄了」的信） —— 不删，也不显示 |

### 6.2 「归本机负责」不进同步数据

哪些信由本机负责寄，记在**本机偏好**里（iOS：UserDefaults `letterOutbox.v1`，`{ letterId: { attempts, failures, nextAttemptAt } }`），
**不进数据库、不进云同步、不进备份包**。写信中的信同步到别的设备，那边只看到一封写信中的信，不会再寄一次。

### 6.3 信 ↔ 日记关联表（建议）

```sql
CREATE TABLE letter_entry (
  letter_id TEXT NOT NULL,
  entry_id  TEXT NOT NULL,
  PRIMARY KEY (letter_id, entry_id)
);
```

---

## 7. 草稿 `DraftEntry`（全局只留一份）

> **为什么单独一张表、不在日记表加 `isDraft`**：加标志位的话首页、日记本、统计、大屏、备份……每处查询都得记得过滤，漏一处草稿就混进正式日记。

| 字段 | 类型 | 默认 | 语义 |
|---|---|---|---|
| `id` | UUID | | |
| `title` | string | `""` | |
| `contentBlocksData` | JSON? | null | 与日记同一套内容块 JSON，转正时直接搬 |
| `mood` / `moodColorHex` | | | 同日记 |
| `tags` | string[] | `[]` | 选过的日记本（≤1） |
| `audioURLs` | string[] | `[]` | |
| `weatherCode` / `weatherInfo` / `locationInfo` | | | 存草稿那一刻的「此时此地」，**恢复时原样还原、不重新定位** |
| `placeMode` | string | `auto` | `auto` / `none` / `manual` |
| `manualPlaceName` | string? | null | `placeMode == manual` 时用户挑的地点 |
| `createdAt` / `updatedAt` | 时间 | | |

- 取当前草稿：按 `updatedAt` 倒序取第一条；多出来的（多设备同步造成）连同媒体一起删
- 草稿**不进**统计、列表、备份包
- 草稿引用的媒体**算「在用」**，孤儿清理不能删
- 转正：建日记 → 删草稿记录，**不删草稿引用的媒体**（新日记接着用）
- 「不保存」：草稿记录 + 它引用的媒体一起删

---

## 8. 媒体文件

| 类型 | 目录（应用沙箱 Documents 下） | 文件名 | 格式 |
|---|---|---|---|
| 日记照片 | `journal_photos/` | `photo_<UUID 前 8 位>.jpg` | JPEG，质量 0.85 |
| 相机拍的未裁原图 | `journal_photos/` | `photo_<同上>_full.jpg` | **原样字节，不许重编码**（动态照片配对靠它） |
| 动态照片视频 | `journal_photos/` | `photo_<同上>.mov`（iOS） | 原样 |
| 日记本封面 | `journal_photos/` | `cover_<UUID>.jpg` | 居中裁成宽高比 **0.73**，宽 **1200px**，JPEG 0.85 |
| 录音 | `audio/` | 文件名任意，`audioURLs` 记相对路径 `audio/<名>.m4a` | AAC 单声道 44.1kHz（iOS） |

**引用表**（判断孤儿、决定上云的唯一依据）= 所有日记的照片三件套 + `audioURLs` + **草稿**引用的 + **日记本封面**。
漏掉任何一类，「清理残留文件」就会误删用户的东西（iOS 两次差点踩：草稿、封面）。

**同名冲突**（导入时）：目标已有同名文件 → 大小相同视作同一份复用；大小不同**必须另起名并改写块内引用**。

---

## 9. 偏好（Preferences）键

> 键名照抄 iOS，方便对照排查。**不需要两端同步**（偏好不进备份包）。

| key | 类型 | 默认 | 用途 |
|---|---|---|---|
| `acceptedLegalVersion` | string | `""` | 已同意的隐私协议**版本号**（当前 iOS 是 `2026-10-09`）。不等于当前版本 → 弹同意页 |
| `hasCompletedOnboarding` | bool | false | 引导走完 |
| `appLanguage` | string | 首启解析 | 七种之一：`zh-Hans` `zh-Hant` `en` `ja` `ko` `fr` `es` |
| `selectedTheme` | string | `bamboo` | `bamboo` / `leather` / `kent`（旧值 `washi`→`bamboo`、`nordic`→`kent`） |
| `appIconSelection` | string | `""` | 空 = 跟随主题；否则固定为某主题的图标 |
| `penPalName` | string | `青鸟` | 笔友名（本地；**不与后端 `penPalName` 同步**，见 `09_OPEN_QUESTIONS.md` Q9） |
| `homeDisplayMode` | string | `list` | `list` / `showcase` |
| `showSplashAnimation` | bool | true | 启动封面 |
| `defaultPaperStyle` | string | `polaroid` | 插照片预选的相纸 |
| `bookContentsLayout` | string | `list` | 日记本目录 列表 / 宫格 |
| `locationRecordingEnabled` | bool | true | 记录位置 |
| `locationPrecision` | string | `city` | `city` / `district` / `street` |
| `stampMode` | string | `weather` | 见 `09_OPEN_QUESTIONS.md` Q10（iOS 几乎没用上） |
| `dormantDaysThreshold` | int | 14 | 🔴 **死设置**：iOS 设置页有、但没有任何读取方。鸿蒙**不做** |
| `syncLivePhotoVideos` | bool | true | 🔴 **死设置**：同上，开关不生效。鸿蒙**不做** |
| `letterOutbox.v1` | JSON | `{}` | 本机负责寄的信（§6.2） |
| `debugFastLetterDelivery` | bool | false | 测试包专用：回信加速（1 分钟 ≈ 1 天）。**正式包不可见、不生效** |
| 迁移标记 `didMigrateCoverLinenOnly` / `didMigrateSingleNotebook` | bool | false | 一次性迁移跑过的标记。🔴 迁移加了新步骤**必须换 key** |

---

## 10. 建议的 RDB 建表（非契约）

```sql
CREATE TABLE IF NOT EXISTS journal_entry (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',          -- 派生，只由内容块写入时生成
  date INTEGER NOT NULL,                      -- 毫秒
  mood TEXT NOT NULL DEFAULT '',
  mood_color_hex TEXT,
  tags TEXT NOT NULL DEFAULT '[]',            -- JSON，≤1 个元素
  is_favorite INTEGER NOT NULL DEFAULT 0,
  word_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  audio_urls TEXT NOT NULL DEFAULT '[]',
  weather_code TEXT, weather_info TEXT, location_info TEXT,
  content_blocks TEXT                         -- ContentBlock[] JSON
);

CREATE TABLE IF NOT EXISTS notebook (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  color_id TEXT NOT NULL DEFAULT 'WineRed',
  texture_id TEXT NOT NULL DEFAULT 'Linen',
  last_opened_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  cover_photo_filename TEXT, cover_layout_id TEXT, subtitle TEXT
);

CREATE TABLE IF NOT EXISTS mood (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  color_hex TEXT NOT NULL DEFAULT '#B8AD9C',
  is_default INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  icon_name TEXT
);

CREATE TABLE IF NOT EXISTS letter (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'pending',
  body TEXT NOT NULL DEFAULT '',
  from_character TEXT NOT NULL DEFAULT '青鸟',
  to_name TEXT,
  stationery TEXT,
  trigger_kind TEXT NOT NULL DEFAULT 'weekly',
  error_message TEXT,
  generated_at INTEGER NOT NULL,
  delivered_at INTEGER,
  read_at INTEGER,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS letter_entry (
  letter_id TEXT NOT NULL, entry_id TEXT NOT NULL,
  PRIMARY KEY (letter_id, entry_id)
);

CREATE TABLE IF NOT EXISTS draft (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  content_blocks TEXT,
  mood TEXT NOT NULL DEFAULT '', mood_color_hex TEXT,
  tags TEXT NOT NULL DEFAULT '[]',
  audio_urls TEXT NOT NULL DEFAULT '[]',
  weather_code TEXT, weather_info TEXT, location_info TEXT,
  place_mode TEXT NOT NULL DEFAULT 'auto', manual_place_name TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
);
```

**schema 演进**：RDB 版本号 + `onUpgrade`。每次加版本都要**拿上一版的真实库跑一次升级**再算完成 ——
「新装能建表」不等于「老库能升级」（iOS 两次栽在这）。

---

## 11. 备份包字段对照（与本地字段的映射）

| 备份包 | 本地 |
|---|---|
| `entries[].audio` | `audioURLs` 的**文件名部分**（包内 `media/` 平铺） |
| `entries[].blocks[].file` | `photoFilename`（照片）/ 录音文件名（`type: "audio"`） |
| `blocks[].liveVideo` / `liveStill` | `livePhotoVideoFilename` / `livePhotoStillFilename` |
| `blocks[].paperStyle` / `position` / `rotationAngle` / `isCover` / `styles` / `addedAt` / `traceOf` / `removedAt` | 同名字段 |
| `letters[].relatedEntryIDs` | 关联表 |
| `taxonomy.tags[].coverFile` / `coverLayout` / `subtitle` | `coverPhotoFilename` / `coverLayoutID` / `subtitle` |
| `taxonomy.tags` 数组顺序 | 书架顺序（**不写 `sortOrder` 字段**） |
| `taxonomy.moods` | 心情（按名字去重） |

完整格式、加密头、合并规则：`Memoir/Docs/EXPORT_FORMAT.md` + `modules/08_backup_package.md`。
