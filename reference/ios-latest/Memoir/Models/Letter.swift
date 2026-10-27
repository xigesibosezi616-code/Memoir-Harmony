import Foundation
import SwiftData

/// 来信的状态机
enum LetterStatus: String, Codable {
    case pending      // 等待触发（已排期未开始）
    case generating   // AI 正在生成
    case delivered    // 已生成、已"送达"（推送已发，用户未读）
    case read         // 用户已阅
    case failed       // 生成失败（带 errorMessage）
}

/// 触发频率类型 —— 决定一封 Letter 是由哪种规则触发生成的
enum LetterTriggerKind: String, Codable {
    case daily        // 每日总结
    case weekly       // 每周总结
    case monthly      // 每月总结
    case perEntry     // 单篇回信（付费高级特性）
}

/// 笔友给用户的来信。
///
/// **关系设计**：
/// - 一封 Letter 关联多篇 JournalEntry（"基于近期日记整体状态分析"）。
/// - **单向**强关系：JournalEntry 不反向持有 letters 数组。
///   原因：加反向关系需要改 JournalEntry schema，会破坏 V1 → V2 的 lightweight migration。
/// - 删日记不删信（`.nullify`）；但因为是单向，SwiftData 在 iOS 18 不会自动从
///   `relatedEntries` 数组中移除被删 entry 的悬空引用 —— 读取时需在 fetch 后过滤。
///   未来要"翻一篇日记看引发过哪些信"时再加反向关系（届时单独走 V3 migration）。
/// ⚠️ **CloudKit 约束**：非可选属性必须带默认值，关系必须可选且有反向。见 `JournalEntry` 顶部说明。
@Model
final class Letter {
    var id: UUID = UUID()

    /// 关联的源日记（多对多：一封信基于多篇日记）。
    /// 可选 + 反向关系（`JournalEntry.letters`）是 CloudKit 的硬性要求。
    @Relationship(deleteRule: .nullify)
    var relatedEntries: [JournalEntry]? = []

    /// `LetterStatus.rawValue`
    var status: String = LetterStatus.pending.rawValue

    /// 来信正文（AI 生成）
    var body: String = ""

    /// **写信当时的笔友名快照**。SwiftData @Model 持久化字段天然就是 snapshot ——
    /// 用户后续在设置里改 `@AppStorage("penPalName")` 不会反向修改老 letter 的此字段，
    /// 保证历史信件的署名与头像永远是"写下那一刻的笔友"。
    var fromCharacter: String = ""

    /// **写信当时的收信人昵称快照**（信件抬头「致 XXX」）。
    ///
    /// 与 `fromCharacter` 完全对称：那个是笔友名快照，这个是用户昵称快照。
    /// 用户改昵称只影响**之后**收到的信 —— 去年那封信的抬头仍然是当时的称呼，
    /// 显示时实时读当前昵称的话，改一次名字连历史信件都会跟着变。
    ///
    /// 昵称来自账号资料（`UserSession.user.displayName`，后端 `PATCH /me`）。
    /// **没登录 / 没设昵称时留 nil**，抬头就只写「致」—— 所以是可选的。
    var toName: String?

    /// **这封信用的什么信纸**（2026-10 尺素会员，V8 新增，见 `SchemaV8`）。
    /// 取值见 `LetterStationeryKind`；`nil` = 普通信纸。
    ///
    /// 在**寄出那一刻**按当时的会员身份写定，之后不再改 —— 会员到期后，
    /// 已经收到的火漆信保持原样（`Docs/MEMBERSHIP.md`「会员到期之后」）。
    /// 所以显示时**不能**实时读会员状态来决定信纸。
    var stationery: String?

    // MARK: 世界笔友（2026-10-16，V9 新增，见 `SchemaV9`）。老信件都是 nil

    /// 世界笔友的 id（`penpals.json`）；**nil = 自己起名的那位**
    var penPalID: String?
    /// 译文（读信人的语言）。世界笔友用自己的母语写 `body`，信纸翻过来是这一面；同语言时为 nil
    var translatedBody: String?
    /// 日记里有危机信号：**正面直接放读信人的语言**（`translatedBody`），原文在背面
    var danger: Bool?
    /// 这封贴了几张邮票（南极两张）
    var postage: Int?

    /// `LetterTriggerKind.rawValue`
    var triggerKind: String = LetterTriggerKind.weekly.rawValue

    /// 失败原因（仅 status == failed 时有值）
    var errorMessage: String?

    var generatedAt: Date = Date()
    var deliveredAt: Date?
    var readAt: Date?
    var updatedAt: Date = Date()

    init(
        relatedEntries: [JournalEntry] = [],
        status: LetterStatus = .pending,
        body: String = "",
        fromCharacter: String = "",
        toName: String? = nil,
        triggerKind: LetterTriggerKind = .weekly,
        errorMessage: String? = nil
    ) {
        self.id = UUID()
        self.relatedEntries = relatedEntries
        self.status = status.rawValue
        self.body = body
        self.fromCharacter = fromCharacter
        self.toName = toName
        self.triggerKind = triggerKind.rawValue
        self.errorMessage = errorMessage
        self.generatedAt = .now
        self.deliveredAt = nil
        self.readAt = nil
        self.updatedAt = .now
    }
}

/// `Letter.stationery` 的取值。
enum LetterStationeryKind: String {
    /// 火漆封口的信封 + 专属信纸（尺素会员）
    case sealed
}

extension Letter {
    /// 火漆信：信箱里是一枚封着的信封，第一次打开要拆
    var isSealed: Bool { stationery == LetterStationeryKind.sealed.rawValue }

    /// 寄出时按会员身份定信纸
    static func stationery(isMember: Bool) -> String? {
        isMember ? LetterStationeryKind.sealed.rawValue : nil
    }
}
