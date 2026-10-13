import Foundation
import SwiftUI

/// 统计的时间范围。
///
/// 粒度是按心理健康类数据的常见看法定的：**短期看波动，长期看基线** ——
/// 近 7 天能看出这周的起伏，今年/全部才看得出一个人的情绪底色。
enum StatsRange: String, CaseIterable, Identifiable {
    case week
    case month
    case year
    case all

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .week:  "近 7 天"
        case .month: "近 30 天"
        case .year:  "今年"
        case .all:   "全部"
        }
    }

    /// 这个范围的起点；`nil` 表示不限（全部）。
    ///
    /// `now` 做成参数是为了能在测试里喂假日期跑穿多个区间，
    /// 不用真等一周过去（`SplashVideoPool` 也是这个路子）。
    func startDate(now: Date = .now, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .week:
            // 含今天在内的 7 天，所以是 -6
            return calendar.date(byAdding: .day, value: -6, to: today)
        case .month:
            return calendar.date(byAdding: .day, value: -29, to: today)
        case .year:
            return calendar.date(from: calendar.dateComponents([.year], from: today))
        case .all:
            return nil
        }
    }

    func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let start = startDate(now: now, calendar: calendar) else { return true }
        return date >= start
    }
}

/// 饼图的一瓣。**只有真的有数据的心情才会成为一瓣** —— 0 篇的心情画不出扇区。
struct MoodSlice: Identifiable {
    let id: String          // mood 的存储 key
    let displayName: String // 已按当前语言翻译好
    let colorHex: String
    let count: Int
    let percentage: Double  // 0...100
}

struct MoodChartData {
    var slices: [MoodSlice] = []
    var total: Int = 0
    /// 该区间内一次都没用过的心情（已翻译）。图例底下用灰字列出来 ——
    /// 「哪些情绪我从没记录过」本身也是一种信息。
    var unusedNames: [String] = []

    var isEmpty: Bool { slices.isEmpty }
}

struct WritingStats {
    var totalEntries: Int = 0
    var totalWords: Int = 0
    var streakDays: Int = 0
    var moodDistribution: [String: Int] = [:]
    var datesWithEntries: Set<String> = []
}

struct StatsCalculator {
    static func calculate(from entries: [JournalEntry]) -> WritingStats {
        var stats = WritingStats()
        stats.totalEntries = entries.count
        stats.totalWords = entries.reduce(0) { $0 + $1.wordCount }

        // Mood distribution
        for entry in entries {
            stats.moodDistribution[entry.mood, default: 0] += 1
        }

        // Dates with entries (for heatmap)
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        for entry in entries {
            stats.datesWithEntries.insert(dayFormatter.string(from: entry.date))
        }

        // Streak calculation
        stats.streakDays = calculateStreak(entries: entries)

        return stats
    }

    /// 按时间范围算心情分布，供饼图用。
    ///
    /// - 只统计**真的选了心情**的日记（`mood` 为空的跳过）——
    ///   把「没选心情」混进百分比会让所有比例都失真。
    /// - 分母是**选过心情的篇数**，不是总篇数，否则百分比加起来不到 100%。
    /// - 按篇数降序，图例从多到少读下来。
    static func moodChartData(
        entries: [JournalEntry],
        moodTags: [MoodTag],
        range: StatsRange,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MoodChartData {
        let inRange = entries.filter { range.contains($0.date, now: now, calendar: calendar) }
        var counts: [String: Int] = [:]
        for entry in inRange where !entry.mood.isEmpty {
            counts[entry.mood, default: 0] += 1
        }

        let total = counts.values.reduce(0, +)
        guard total > 0 else {
            return MoodChartData(slices: [], total: 0, unusedNames: [])
        }

        var slices: [MoodSlice] = []
        var unused: [String] = []
        for tag in moodTags {
            let count = counts[tag.name] ?? 0
            if count > 0 {
                slices.append(MoodSlice(
                    id: tag.name,
                    displayName: tag.displayName,
                    colorHex: tag.colorHex,
                    count: count,
                    percentage: Double(count) / Double(total) * 100
                ))
            } else {
                unused.append(tag.displayName)
            }
        }

        // 日记里可能存着已被删掉的心情（老数据/导入的备份包），
        // 它在 moodTags 里找不到 —— 不能就这么丢掉，否则百分比对不上。
        let known = Set(moodTags.map(\.name))
        for (name, count) in counts where !known.contains(name) {
            slices.append(MoodSlice(
                id: name,
                displayName: MoodTag.localizedName(for: name),
                colorHex: "#B8AD9C",
                count: count,
                percentage: Double(count) / Double(total) * 100
            ))
        }

        slices.sort { $0.count > $1.count }
        return MoodChartData(slices: slices, total: total, unusedNames: unused)
    }

    private static func calculateStreak(entries: [JournalEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let entryDays = Set(entries.map { calendar.startOfDay(for: $0.date) })

        var streak = 0
        var checkDate = today

        while entryDays.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return streak
    }
}
