# 01 · 技术栈对照表（iOS → 鸿蒙）

> 最后核对：2026-10-12。iOS 列是**实际在用的**；鸿蒙列是**候选能力**，标「需核实」的请以华为官方文档和目标 API 版本为准，
> 选定后在 `PROGRESS.md` 记下来。**同步的是行为，不是实现。**

---

## 整体架构

| 层 | iOS（实际） | 鸿蒙（候选） |
|---|---|---|
| 语言 / UI | Swift + SwiftUI | ArkTS + ArkUI（Stage 模型） |
| 状态管理 | `@Observable` + `@State` + `@Environment` | `@Provide/@Consume` + `@Observed`/`@ObservedV2`（**全工程选一种，别混用**） |
| 本地数据库 | SwiftData（schema V8，版本化迁移） | RDB `relationalStore` + 版本号 / `onUpgrade` |
| 简单 KV | `@AppStorage`（UserDefaults） | Preferences |
| 敏感信息（token） | Keychain | 资产存储（Asset Store Kit）或通用密钥库，需核实 |
| HTTP | URLSession + 自研 HTTPClient | `@kit.NetworkKit` http + 自己包装 |
| JSON | Codable | 原生 JSON + interface |
| **云同步** | CloudKit 私有库（用户自己的 iCloud） | ⛔ **待定（Q3）**；❌ 不能用开发者侧云数据库存日记 |
| **到达提醒** | **本地定时通知**（不用服务器推送） | 后台代理提醒（reminderAgentManager）或同类能力，需核实数量上限 |
| 短时后台 | `beginBackgroundTask`（投信后切走也寄完） | 短时任务（`backgroundTaskManager.requestSuspendDelay`），需核实 |
| 登录 | 手机号验证码 + Sign in with Apple | 手机号验证码 + 华为账号 Account Kit（⛔ 后端未就绪，Q1） |
| 内购 | StoreKit 2 + 服务端验签 | 华为 IAP Kit（⛔ 服务端验证占位，Q2） |
| 选图 | PhotosPicker | `photoAccessHelper.PhotoViewPicker` |
| 相机 | AVFoundation 自研相机 | Camera Kit |
| 动态照片 | Live Photo（`PHLivePhotoView`） | 动态照片能力（如 `MovingPhotoView`），需核实；互通见 Q13 |
| 存进系统相册 | PhotoKit | 媒体库能力（可能需要安全控件 / 用户确认，需核实） |
| 录音 / 播放 | AVAudioRecorder / AVAudioPlayer（AAC 44.1k 单声道） | Media Kit `AVRecorder` / `AVPlayer` |
| 定位 / 逆地理 | CoreLocation + `CLGeocoder` | Location Kit `geoLocationManager` |
| 附近地点搜索 | MapKit `MKLocalSearch` | Map Kit 地点搜索，需核实 |
| 天气 | WeatherKit | ⛔ 待定（Q8） |
| 语言识别（回信语言） | NaturalLanguage `NLLanguageRecognizer` | 平台文本语种识别能力（需核实）；没有就按 `10_BUILD_MANUAL.md` 5.5 的启发式 |
| 震动 | Core Haptics（跟动画时间轴） | `vibrator` 自定义振动效果，需核实 |
| 音效 | AVAudioPlayer（跟静音键、不打断音乐） | SoundPool / AVPlayer |
| App 内语言 | 自选 `.lproj` bundle + `\.locale` | 应用级首选语言（`i18n.System.setAppPreferredLanguage`），需核实 |
| 深色主题 | 根部 `.preferredColorScheme` | 应用级颜色模式（`setColorMode`），需核实 |
| 换桌面图标 | `setAlternateIconName` | ⛔ 平台能力待确认（Q5） |
| 长按图标快捷方式 | 代码动态登记（标题跟 App 语言） | 快捷方式配置，能否动态登记待确认（Q5） |
| 解压 / 压缩 | ZIPFoundation / `NSFileCoordinator` | `zlib` |
| 备份加密 | CryptoKit（PBKDF2-HMAC-SHA256 21 万轮 + AES-256-GCM） | Crypto Architecture Kit（PBKDF2、AES-GCM） |
| 打开 `.memoir` 文件 | UTI 注册 + `onOpenURL` | `module.json5` skills 声明文件类型 + Want 处理 |
| 导出分享 | ShareLink | 系统分享 / 文件保存选择器 |
| 字体 | Georgia（系统自带） | ⛔ 授权问题（Q6），先集中成主题 token |
| 3D 视差 | ~~CoreMotion~~ | ❌ 两端都不做（已撤销） |

---

## 关键模块对照

### 图文编辑器

| iOS | 鸿蒙 |
|---|---|
| UITextView + TextKit（`Views/Components/RichText/RichTextView.swift`）：照片 / 录音 / 痕迹是叠在文字上的视图，用 `exclusionPaths` 让文字绕开 | ArkUI `RichEditor` 起步。**先做 1 天技术验证**：文字绕排浮动图片、自定义块（录音卡片）、UTF-16 区间样式。做不到的找产品要退化方案（`10_BUILD_MANUAL.md` 2.5） |
| 块结构（`ContentBlock[]`）↔ 富文本的双向转换在 `RichDocument.swift` | 同样做一层转换；**库里存的永远是块结构 JSON** |

### 翻页阅读器

| iOS | 鸿蒙 |
|---|---|
| `UIPageViewController(.pageCurl)` 桥接 | `Swiper` 平滑左右切换即可，不强求仿真翻页 |
| 分页「先算后画」：`Paginator` 与页面共用 `ReaderLayout` 常量，TextKit 测高 | 同样先算后画，用平台的文字测量能力，常量共用一份 |

### 书架拿书

| iOS | 鸿蒙 |
|---|---|
| 封面和书脊当长方体两个面，各自投影、共用转轴和透视（`Views/Home/Shelf/BookBoxProjection.swift`） | `rotate` + 透视参数拼两个面；**转过去时要看得到书的厚度** |

### 数据模型

**以 `05_DATA_MODEL.md` 为准**（含字段表、建议建表 SQL、偏好键）。旧版本文档里那张 `journal_entries` 表已过时，不要用。

---

## 文件组织建议

```
entry/src/main/ets/
├── pages/                 ← 顶层页面
│   ├── MainTabPage.ets     （记录 / 日记本 / 邮筒 / 设置）
│   ├── ConsentPage.ets / OnboardingPage.ets / SplashCover.ets
│   ├── home/               （HomePage、ShowcasePage、EntryDetailPage、EditEntryPage）
│   ├── compose/            （ComposePage、MoodSelector、NotebookSelector、LocationPicker、VoiceRecorder、Camera）
│   ├── books/              （BookshelfPage、BookHomePage、CoverEditorPage、CoverCropPage）
│   ├── reader/             （ReaderPage、Paginator、PageHeader）
│   ├── postbox/            （PostBoxPage、LetterboxPage、LetterDetailPage、Envelope/、Posting/）
│   ├── settings/           （各二级页、ThemeIntroSheet、StatsPage、BackupExport/Import）
│   ├── membership/         （PaywallPage、MembershipStatusPage）
│   └── auth/               （LoginPage、ChangePhonePage、DeleteAccountPage）
├── components/            ← 复用组件（PhotoPaper/、RichText/、WaxSeal、Stamp、MoodBadge、ErrorToast）
├── models/                ← 数据模型 + 纯规则函数（JournalEntry、ContentBlock、Ink、Notebook、Mood、Letter、LetterDelivery、Draft、Api）
├── data/                  ← RDB 打开 / 迁移、Preferences、媒体文件（MediaStore）
├── services/              ← LetterOutbox、LetterNotifications、LetterLanguage、Weather、Backup/、Stats、Greeting
├── environment/           ← AppEnvironment、HttpClient、UserSession、ErrorPresenter
├── theme/                 ← ThemeManager、BambooTheme、LeatherTheme、KentTheme、ThemePaper
└── utils/
```

---

## 命名约定

| 类型 | iOS | 鸿蒙 |
|---|---|---|
| 类型 | PascalCase（`JournalEntry`） | 同名 |
| 函数 / 变量 | camelCase（`requestLetter`） | 同名 |
| 文件 | `JournalEntry.swift` | `JournalEntry.ets` |

**规则函数尽量和 iOS 同名**（`nameKey`、`singleNotebook`、`isInTransit`…），出问题时两边好对照。

---

## 不要做的「直译」

| 不要做 | 原因 | 鸿蒙怎么做 |
|---|---|---|
| ❌ 把 SwiftUI 代码逐行翻成 ArkUI | 概念不完全等价，硬翻反而别扭 | 读懂行为，用 ArkUI 惯用法重写 |
| ❌ 照搬 iOS 的灵动岛相机 | 强依赖 iPhone 硬件 | 按鸿蒙设备重新设计取景，保留「按快门 → 相纸落到手里 → 想写点什么」的意图 |
| ❌ 硬做仿真翻页 | 平台没有原生支持 | Swiper |
| ❌ 用屏幕全局尺寸算布局 | iOS 也在清理 `UIScreen.main` | 响应式布局，尺寸来自父容器 |
| ❌ 用 iOS 的 SF Symbols 名当图标 | 鸿蒙没有 | 线性图标库（Tabler / Lucide）或 HarmonyOS 图标；对照表见 `04` |

## 鸿蒙端可以放飞的部分

- 翻页：Swiper 即可
- 照片拖拽换段落：用原生拖拽能力
- 页面结构、导航方式、弹窗样式：按 HarmonyOS Design
- **不可以放飞的**：数据、规则、文案（`06_RULES.md`）
