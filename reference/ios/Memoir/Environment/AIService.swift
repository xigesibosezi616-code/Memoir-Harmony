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
}

/// 来信节奏（`GET /me/rhythm`）。**判定权只在服务端**，客户端只拿它提前告诉用户「这周已经寄过了」，
/// 不在本地算额度（见 `Backend/shared/src/rhythm.ts`）
struct LetterRhythm: Sendable, Equatable {
    let canRequestNow: Bool
    /// `ok` / `weekly_pending` / `daily_cap` / `monthly_cap` / `welcome_pending`
    let reason: String
    /// 下一封最早什么时候能寄；现在就能寄时为 nil
    let nextLetterAt: Date?
    /// 服务端认的档位：`free` / `subscribed`
    let tier: String

    /// 没法问服务端时（Mock、占位）当作随时能寄
    static let open = LetterRhythm(canRequestNow: true, reason: "ok", nextLetterAt: nil, tier: "free")
}

protocol AIService {
    /// 现在还能不能寄信。邮筒页一进来就问，免得用户点了邮筒、信也投了才被拒
    func fetchRhythm() async throws -> LetterRhythm

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
    /// 当前用户给笔友起的名字（来自 `@AppStorage("penPalName")`，默认 "青鸟"）。
    /// 会被快照到 `Letter.fromCharacter`，让历史信件保留写信当时的名字。
    let penPalName: String
}

/// 日记快照 —— 脱离 SwiftData @Model 的不可变值类型。
struct EntrySnapshot: Sendable {
    let id: UUID
    let title: String
    /// 正文文本（已剥离照片块、按段拼接）
    let textContent: String
    let date: Date
    /// 心情键，对应 `MoodTag.name`，可为 nil
    let mood: String?
}

/// AI 生成的来信草稿（尚未落库为 `Letter`）。
struct LetterDraft: Sendable {
    /// 来信正文（含开头/中段/结尾/署名，**署名已包含 penPalName**）
    let body: String
    /// 写信当时的笔友名（直接 = `context.penPalName`，调用方落库时写入 `Letter.fromCharacter`）
    let fromCharacter: String
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
    /// 来信节奏拦截（后端 `rhythm`）。`reason` 见 `Backend/shared/src/rhythm.ts`。
    /// `penPalName` 用于文案 —— 笔友的名字是用户自己起的，不能写死「青鸟」
    case rateLimit(reason: String?, retryAfter: TimeInterval?, penPalName: String)
    /// 内容审核拒绝
    case contentFiltered

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
        case .rateLimit(let reason, let retryAfter, let penPalName):
            switch reason {
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
            mood: mood
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

    func fetchRhythm() async throws -> LetterRhythm { .open }
}
