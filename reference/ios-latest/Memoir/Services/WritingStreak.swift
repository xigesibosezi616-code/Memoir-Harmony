import Foundation

/// 最长连续写作（2026-10-28 用户定，取代原来的「连续写作」—— 那个是从今天往回数，一断就归零）。
///
/// 规则（鸿蒙照抄，见 HarmonyUpdates U16）：
/// - **连续** = 按日历（设备时区）连着的日子里，每天至少写了一篇
/// - **最长** = 「记下的」和「现在这些日记里最长的那一段」取大的，**只升不降**：
///   连着写了 30 天就是 30，断了还是 30，直到哪天新的一段写到 31 天才变；删了日记也不往下掉
/// - 记在本机（`UserDefaults`），**跟备份包导出**；导入时取「本机」和「包里」大的那个
/// - 什么时候记：打开写作统计、导出、导入时各算一次，比记下的大就更新
enum WritingStreak {
    static let storageKey = "writingStats.bestStreakDays"

    /// 记下的最长连续天数（没记过是 0）
    static var recorded: Int { UserDefaults.standard.integer(forKey: storageKey) }

    /// 只升不降
    static func raise(to days: Int) {
        guard days > recorded else { return }
        UserDefaults.standard.set(days, forKey: storageKey)
        NSLog("ℹ️ [WritingStreak] 最长连续写作 → %ld 天", days)
    }

    /// 这些日子里最长的一段连续天数（同一天写几篇算一天）
    static func longestRun(in dates: [Date], calendar: Calendar = .current) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let p = previous, calendar.date(byAdding: .day, value: 1, to: p) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// 显示用：记下的和算出来的取大的（不写入，界面里随便调）
    static func best(in entries: [JournalEntry]) -> Int {
        max(recorded, longestRun(in: entries.map(\.date)))
    }

    /// 算一次，比记下的大就记下；返回最新的最长天数
    @discardableResult
    static func update(with entries: [JournalEntry]) -> Int {
        let value = best(in: entries)
        raise(to: value)
        return value
    }
}
