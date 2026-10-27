import Foundation
import SwiftData

/// 情绪小结（2026-10-27，尺素会员）：每周、每月、每年一份，一段小结 + 两三条建议，放在写作统计「情绪捕捉」最上面。
///
/// - 生成：会员在这一期结束后**第一次打开写作统计**时，用这一期的统计数字和情绪词问一次服务端（`MoodSummaryWriter`）；
///   **不发日记正文、不发地名**。那一期记了心情的日记不到 3 篇就不生成
/// - 存在本机 + 用户自己的 iCloud，跟备份包走；服务端用完即弃
/// - 一期一份：`(period, periodStart)` 相同的只认最新的那份（两台设备同步前各写了一份也不要紧）
///
/// ⚠️ CloudKit 约束：非可选属性必须带默认值（见 `JournalEntry` 顶部说明）
@Model
final class MoodSummary {
    var id: UUID = UUID()
    /// `MoodSummary.Period` 的 rawValue：`week` / `month` / `year`
    var period: String = "week"
    /// 这一期的起点：周一 0 点 / 1 号 0 点 / 1 月 1 日 0 点（写的那台设备的时区）
    var periodStart: Date = Date()
    /// 这一期的终点（不含）
    var periodEnd: Date = Date()
    /// 小结正文
    var text: String = ""
    /// 两三条建议
    var suggestions: [String]?
    /// 写的时候用的 App 语言（换了语言，旧的小结还是旧语言，不重写）
    var language: String = ""
    /// 这一期记了心情的篇数
    var entryCount: Int = 0
    /// 这一期心情很沉（最低两档占得多）：小结下面附求助方式
    var heavy: Bool = false
    var createdAt: Date = Date()

    init(period: Period, periodStart: Date, periodEnd: Date, text: String, suggestions: [String],
         language: String, entryCount: Int, heavy: Bool) {
        self.id = UUID()
        self.period = period.rawValue
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.text = text
        self.suggestions = suggestions
        self.language = language
        self.entryCount = entryCount
        self.heavy = heavy
        self.createdAt = .now
    }

    enum Period: String, CaseIterable, Sendable {
        case week, month, year
    }

    var periodKind: Period { Period(rawValue: period) ?? .week }
    var suggestionList: [String] { suggestions ?? [] }
}
