import Foundation

/// AI 来信服务的抽象边界。背后可切换 Mock（假信）/ Proxy（走中转服务器）。
///
/// 加在 `AppEnvironment.ai`，View 通过 `@Environment(AppEnvironment.self)` 取到。
/// 实现切换在 `MemoirApp` 里构造 `AppEnvironment` 时决定，View 不感知。
/// 服务端已经写好的一封信（`GET /letters` 的元素），用于**补领**本机缺失的信
struct LetterSummary: Sendable, Equatable {
    let body: String
    let fromCharacter: String
    let generatedAt: Date
    /// 寄信时本机给的信件 id（= `Letter.id`）；2026-10-16 之前的信是 nil。**补领时按它对上是哪一封**
    var clientLetterID: UUID? = nil
    /// 世界笔友的 id；自己起名的那位是 nil
    var penPalID: String? = nil
    /// 译文（世界笔友）
    var translation: String? = nil
    var danger: Bool = false
}

/// 邮票夹（`GET /me/stamps`，2026-10-16 起取代来信节奏）。**余额只认服务端**，
/// 客户端拿它提前告诉用户「邮票用完了、下一包几时到」，最终由服务端扣、由服务端拦
struct StampWallet: Sendable, Equatable {
    let balance: Int
    /// 邮票夹最多放几张（2026-10-27 起不清空、一直攒，服务端固定给 999，只是防呆）
    let cap: Int
    /// 下一包什么时候到
    let nextPackAt: Date
    /// 现在就能领一包
    let packReady: Bool
    let isMember: Bool
}

/// 寄给一位世界笔友要带的东西（`POST /penpal-letter`）
struct PenPalLetterContext: Sendable {
    /// = `Letter.id`。**同一个 id 服务端只写一封、只扣一次票**（寄信队列会重试）
    let clientLetterID: UUID
    let penPalID: String
    let entries: [EntrySnapshot]
    let dominantMood: String?
    /// 他给你记的手记（画像 + 大事）：本机存的、只有这一位的（`PenPalNotebook.snapshot`）
    let notebook: [PenPalNoteSnapshot]
}

/// 手记里的一条，寄信时带上（对齐后端 `NotebookItem`）
struct PenPalNoteSnapshot: Sendable {
    let id: UUID
    let kind: PenPalNote.Kind
    let text: String
    /// 记下 / 最后改写这条的时刻
    let date: Date
}

/// 这一封之后手记怎么改：服务端交回，`PenPalNotebook.apply` 照着改本机那一本（对齐后端 `NotebookEdits`）
struct NotebookEdits: Sendable {
    struct Rewrite: Sendable {
        let id: UUID
        let text: String
    }

    /// 整份重写的画像；nil = 画像不动
    var profile: String?
    /// 新记下的大事
    var add: [String] = []
    /// 改写的大事
    var update: [Rewrite] = []
    /// 不再需要的大事
    var remove: [UUID] = []

    var isEmpty: Bool { profile == nil && add.isEmpty && update.isEmpty && remove.isEmpty }
}

/// 世界笔友的回信
struct PenPalLetterDraft: Sendable {
    /// 原文（他的母语）
    let letter: String
    /// 译文（读信人的语言）；同语言时为空串
    let translation: String
    /// 手记怎么改（危险的那封服务端一条都不给）
    let notebook: NotebookEdits
    /// 危险的那封：正面放译文
    let danger: Bool
    let postage: Int
    let generatedAt: Date
    /// 寄完之后邮票夹里还剩几张
    let balance: Int
}

/// 一期情绪小结要发给服务端的东西（`POST /mood-summary`，对齐后端 `MoodSummaryBody`，2026-10-27）。
/// 🔴 **只有统计数字和情绪词** —— 不带日记正文、不带地名（地点按篇数排第几处：`place1`…）
struct MoodSummaryRequest: Sendable, Encodable {
    struct Group: Sendable, Encodable {
        let key: String
        let valence: Double
        let count: Int
    }
    struct LabelCount: Sendable, Encodable {
        let label: String
        let count: Int
    }
    struct TrendPoint: Sendable, Encodable {
        let start: Date
        let valence: Double
        let count: Int
    }

    let period: String
    let periodStart: Date
    let periodEnd: Date
    /// App 的语言（小结用它写）
    let language: String
    let entryCount: Int
    let averageValence: Double
    /// 九档各几篇，从「跌入谷底」到「心花怒放」
    let levels: [Int]
    let labels: [LabelCount]
    let weather: [Group]
    let places: [Group]
    let weekdays: [Group]
    let dayParts: [Group]
    let trend: [TrendPoint]
    /// 上一期的平均愉悦度；上一期没记心情就是 nil
    let previousAverage: Double?
}

/// 服务端写好的一期小结
struct MoodSummaryDraft: Sendable {
    let summary: String
    let suggestions: [String]
    /// 心情很沉：小结下面附求助方式
    let heavy: Bool
}

protocol AIService {
    /// 邮票夹。邮筒页一进来就问，免得用户点了邮筒、信也投了才被拒
    func fetchStamps() async throws -> StampWallet

    /// 领这一包（快递封动画做好之前，邮筒页发现能领就悄悄领）
    func claimStamps() async throws -> StampWallet

    /// 服务端已经备好人设、现在能寄的世界笔友
    func fetchAvailablePenPals() async throws -> Set<String>

    /// 寄给一位世界笔友，拿回他的回信（原文 + 译文 + 记下的事 + 危险标记）
    func generatePenPalLetter(_ context: PenPalLetterContext) async throws -> PenPalLetterDraft

    /// 写一期情绪小结（会员）：只发统计数字和情绪词
    func generateMoodSummary(_ request: MoodSummaryRequest) async throws -> MoodSummaryDraft

    /// 拉取服务端已经写好的信。
    ///
    /// 🔴 **这是补领，不是同步。** 服务端「AI 写完 → 先写库 → 再把正文放响应里返回」，
    /// 而节奏额度是按库里的行数算的。响应一旦没回到客户端（模型慢导致超时、断网、
    /// App 被切走），那封信在服务端存在、在本机却没有 —— 用户这一周再也求不到信，
    /// 手上还什么都没有（2026-09-17 两台真机都是这么卡住的）。
    /// 所以必须能回头把它领回来。
    func fetchLetters(limit: Int) async throws -> [LetterSummary]

    /// 根据近期一组日记生成一封"来信"。
    /// 调用方应在 Task 内 `try await`，失败抛 `AIServiceError`。
    func generateLetter(for context: LetterContext) async throws -> LetterDraft
}

// MARK: - 上下文 / 草稿

/// 生成一封来信所需的上下文。
///
/// **设计要点**：
/// - **多篇**模式（一封信对应近期多篇日记的整体分析；单篇模式 = `entries.count == 1`）
/// - 使用 `EntrySnapshot` 值类型而非 `JournalEntry` @Model —— 跨 actor / 跨进程 / 上传后端都安全
/// - 调用方负责"挑出近期哪些日记"和"算出主导情绪"
struct LetterContext: Sendable {
    let entries: [EntrySnapshot]
    let triggerKind: LetterTriggerKind
    /// 用户最近主导情绪（由调用方预聚合），可为 nil
    let dominantMood: String?
    /// 当前用户给笔友起的名字（来自 `@AppStorage(PenPalName.storageKey)`，用户自己起的，没有默认名）。
    /// 会被快照到 `Letter.fromCharacter`，让历史信件保留写信当时的名字。
    let penPalName: String
    /// = `Letter.id`（2026-10-16 起）。**同一个 id 服务端只写一封、只扣一张邮票**
    var clientLetterID: UUID? = nil
    /// 他给你记的手记（2026-10-27 起，`PenPalNotebook.snapshot(for: PenPalNote.ownID)`）。nil = 不带，服务端也就不改手记
    var notebook: [PenPalNoteSnapshot]? = nil
}

/// 日记快照 —— 脱离 SwiftData @Model 的不可变值类型。
struct EntrySnapshot: Sendable {
    let id: UUID
    let title: String
    /// 正文文本（已剥离照片块、按段拼接）
    let textContent: String
    let date: Date
    /// 这篇的心情：九档的英文名 + 情绪词（如 `melancholy (drained, anxious)`），没记是 nil。
    /// 后端只把它写进提示词（`Backend/shared/src/prompt.ts`），所以用英文、不跟 App 语言走
    let mood: String?
}

/// AI 生成的来信草稿（尚未落库为 `Letter`）。
struct LetterDraft: Sendable {
    /// 来信正文（含开头/中段/结尾/署名，**署名已包含 penPalName**）
    let body: String
    /// 写信当时的笔友名（直接 = `context.penPalName`，调用方落库时写入 `Letter.fromCharacter`）
    let fromCharacter: String
    /// 手记怎么改；请求里没带手记就是 nil
    var notebook: NotebookEdits? = nil
}

// MARK: - 错误

enum AIServiceError: LocalizedError {
    case notImplemented
    /// 未登录 / 登录已过期 —— 来信是云端能力，必须有账号
    case notLoggedIn
    /// 生成失败（Mock 模拟失败 / 后端报错 / Prompt 异常等通用情况）
    case generationFailed(String)
    /// 网络层失败转过来
    case network(HTTPError)
    /// 被服务端拦下（429）。2026-10-16 起来信节奏换成邮票，`reason` 是 `no_stamps`（带下一包几时到）；
    /// 老的 `weekly_pending` 等只在旧服务端出现。
    /// `penPalName` 用于文案 —— 笔友的名字是用户自己起的，不能写死任何名字
    case rateLimit(reason: String?, retryAfter: TimeInterval?, penPalName: String, nextPackAt: Date? = nil)
    /// 内容审核拒绝
    case contentFiltered
    /// 世界笔友只有会员能寄（403 `member_required`）
    case memberRequired
    /// 这位笔友服务端还没备好（404 `unknown_pen_pal`）
    case penPalUnavailable

    var errorDescription: String? {
        switch self {
        // 这些会经 ErrorPresenter 显示给用户 —— `Text(String)` 不查本地化表，
        // 必须显式 NSLocalizedString（`.appLanguage` 而非 `.main`，见 Bundle+AppLanguage）
        case .notImplemented:
            return NSLocalizedString("AI 服务暂未启用", bundle: .appLanguage, comment: "AI 错误")
        case .notLoggedIn:
            return NSLocalizedString("请先登录，笔友才能给你写信", bundle: .appLanguage, comment: "AI 错误")
        // 🔴 下面两条**不写「生成」**：邮筒页的设定是「寄出日记、回信几天后才到」，
        // 失败发生在寄出这一步，用户理解的是「信没寄出去」（2026-09-14）。原因 %@ 照旧透传
        case .generationFailed(let reason):
            return String(format: NSLocalizedString("信没能寄出：%@", bundle: .appLanguage, comment: "寄信失败，%@ 是后端返回的原因"), reason)
        case .network(let underlying):
            return underlying.errorDescription
        // 🔴 **不要用「额度 / 配额 / 剩余 N 封 / 升级解锁」这类计量词**（定价文档 §5.1）：
        // 用户看到的永远是世界观内的解释。中文与后端 `rhythmMessage` 一字对应，
        // 其余六种语言按同样的语气重写（不是直译）。
        //
        // 后端那句只有中文，所以这里按 `reason` 自己渲染，而不是透传后端文案 ——
        // 否则外语用户会看到一句突兀的中文。
        case .rateLimit(let reason, let retryAfter, let penPalName, let nextPackAt):
            switch reason {
            case "no_stamps":
                guard let nextPackAt else {
                    return NSLocalizedString("邮票用完了，新的一包很快就到", bundle: .appLanguage, comment: "寄信被拦：邮票用完了")
                }
                return String(format: NSLocalizedString("邮票用完了，新的一包%@送到", bundle: .appLanguage, comment: "寄信被拦：邮票用完了，%@ 是相对时间如「3 天后」"),
                              nextPackAt.formatted(.relative(presentation: .named).locale(appLocale)))
            case "weekly_pending":
                return String(format: NSLocalizedString("本周的信已经到了。%@习惯每周回一次——你写的它都在读，下周日再来。", bundle: .appLanguage, comment: "来信节奏：本周已回过，%@ 是笔友名"), penPalName)
            case "daily_cap":
                // 这句不出现笔友名，不用套 format
                return NSLocalizedString("今天的信刚寄出，路上还没走远。明天再写，明天再回。", bundle: .appLanguage, comment: "来信节奏：今日已回过")
            case "monthly_cap":
                return String(format: NSLocalizedString("这个月%@已经回过几封了。它写信慢，下个月再续。", bundle: .appLanguage, comment: "来信节奏：本月已到上限，%@ 是笔友名"), penPalName)
            case "welcome_pending":
                return String(format: NSLocalizedString("你的第一封已经寄出了。%@正在读，回信大约在一两日后到。", bundle: .appLanguage, comment: "来信节奏：第一封在路上，%@ 是笔友名"), penPalName)
            default:
                if let s = retryAfter {
                    return String(format: NSLocalizedString("请求过于频繁，请约 %lld 秒后再试", bundle: .appLanguage, comment: "AI 限流，%lld 是秒数"), Int(s))
                }
                return String(format: NSLocalizedString("%@这会儿不在案前，稍后再来。", bundle: .appLanguage, comment: "来信节奏：其他原因，%@ 是笔友名"), penPalName)
            }
        case .contentFiltered:
            return NSLocalizedString("日记内容未通过审核，这次没能寄出", bundle: .appLanguage, comment: "寄信被内容审核拦下")
        case .memberRequired:
            return NSLocalizedString("给各地的笔友写信是尺素会员的，这封信没能寄出", bundle: .appLanguage, comment: "寄给世界笔友被拦：不是会员")
        case .penPalUnavailable:
            return NSLocalizedString("这位笔友还没准备好，这封信没能寄出", bundle: .appLanguage, comment: "寄给世界笔友被拦：服务端还没这位")
        }
    }
}

// MARK: - 便利转换

extension JournalEntry {
    /// 把 SwiftData @Model 转成 Sendable 快照，供 AI 服务跨上下文使用。
    var snapshot: EntrySnapshot {
        EntrySnapshot(
            id: id,
            title: title,
            textContent: content,   // setter 已经把 contentBlocks 内文本拼接同步到了 content
            date: date,
            mood: moodSummary
        )
    }
}

// MARK: - 占位实现

/// **占位实现** —— 唯一作用是让 `AppEnvironment` 可构造、release 编译有 default。
/// ⚠️ 这不是 `MockAIService`（返回假信）。Debug 默认用 MockAIService，见 `MemoirApp`。
struct PlaceholderAIService: AIService {
    func generateLetter(for context: LetterContext) async throws -> LetterDraft {
        throw AIServiceError.notImplemented
    }

    /// 没有服务端可问，补领自然是空的（不抛错：补领是静默的后台动作）
    func fetchLetters(limit: Int) async throws -> [LetterSummary] { [] }

    func fetchStamps() async throws -> StampWallet { throw AIServiceError.notImplemented }
    func claimStamps() async throws -> StampWallet { throw AIServiceError.notImplemented }
    func fetchAvailablePenPals() async throws -> Set<String> { [] }
    func generatePenPalLetter(_ context: PenPalLetterContext) async throws -> PenPalLetterDraft {
        throw AIServiceError.notImplemented
    }
    func generateMoodSummary(_ request: MoodSummaryRequest) async throws -> MoodSummaryDraft {
        throw AIServiceError.notImplemented
    }
}
