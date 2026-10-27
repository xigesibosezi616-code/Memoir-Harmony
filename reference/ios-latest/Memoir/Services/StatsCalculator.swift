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
    /// 不用真等一周过去。
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
/// 环形图的一块：九档里的一档（2026-10-17 从旧心情标签改成九档）
struct MoodSlice: Identifiable {
    let level: MoodLevel
    let count: Int
    let percentage: Double  // 0...100
    var id: Int { level.rawValue }
}

struct MoodChartData {
    var slices: [MoodSlice] = []
    /// 这个区间记了心情的篇数
    var total: Int = 0

    var isEmpty: Bool { slices.isEmpty }
}

struct WritingStats {
    var totalEntries: Int = 0
    var totalWords: Int = 0
    var datesWithEntries: Set<String> = []
}

struct StatsCalculator {
    static func calculate(from entries: [JournalEntry]) -> WritingStats {
        var stats = WritingStats()
        stats.totalEntries = entries.count
        stats.totalWords = entries.reduce(0) { $0 + $1.wordCount }

        // Dates with entries (for heatmap)
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        for entry in entries {
            stats.datesWithEntries.insert(dayFormatter.string(from: entry.date))
        }

        return stats
    }

    /// 按时间范围算心情分布（九档），供环形图用。
    ///
    /// - 只统计**记了心情**的日记（心情页上线之前写的都没有）——
    ///   把「没记」混进百分比会让所有比例都失真；分母是记了心情的篇数
    /// - 从心花怒放排到跌入谷底：环上的颜色顺着九档走，一眼看得出偏哪一边
    static func moodChartData(
        entries: [JournalEntry],
        range: StatsRange,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MoodChartData {
        let levels = entries
            .filter { range.contains($0.date, now: now, calendar: calendar) }
            .compactMap(\.moodLevel)
        guard !levels.isEmpty else { return MoodChartData() }
        let counts = Dictionary(grouping: levels, by: { $0 }).mapValues(\.count)
        let slices = MoodLevel.allCases.reversed().compactMap { level -> MoodSlice? in
            guard let count = counts[level] else { return nil }
            return MoodSlice(level: level, count: count, percentage: Double(count) / Double(levels.count) * 100)
        }
        return MoodChartData(slices: slices, total: levels.count)
    }
}
