import Foundation
import SwiftData

/// 情绪小结写哪一期、发什么（2026-10-27，会员；模型是 `MoodSummary`，服务端是 `Backend/shared/src/moodSummary.ts`）。
///
/// 规则（鸿蒙照抄，见 HarmonyUpdates U14）：
/// - 一期 = **周一开始的一周** / 自然月 / 自然年，按这台设备的时区
/// - 会员**打开写作统计**时，三种各看一眼**刚结束的那一期**：没写过、那一期记了心情的日记够 3 篇，就写一份；
///   只写刚结束的那一期，不往前补
/// - 发的只有统计数字和情绪词（`MoodSummaryRequest`）：🔴 不发日记正文、不发地名（地点按篇数排第几处）
@MainActor
enum MoodSummaryWriter {
    /// 周一开始的一周、自然月、自然年，按这台设备的时区
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = .current
        return c
    }

    /// 正在写的那几期（按 `key`）：页面反复出现时别重复问
    private static var inFlight: Set<String> = []

    private static func component(_ period: MoodSummary.Period) -> Calendar.Component {
        switch period {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    /// 刚结束的那一期
    static func lastCompleted(_ period: MoodSummary.Period, now: Date) -> DateInterval? {
        let cal = calendar
        guard let current = cal.dateInterval(of: component(period), for: now),
              let start = cal.date(byAdding: component(period), value: -1, to: current.start) else { return nil }
        return DateInterval(start: start, end: current.start)
    }

    /// 某一期的上一期（给小结做「和上周比」）
    static func previous(of interval: DateInterval, _ period: MoodSummary.Period) -> DateInterval? {
        guard let start = calendar.date(byAdding: component(period), value: -1, to: interval.start) else { return nil }
        return DateInterval(start: start, end: interval.start)
    }

    /// 这一期写过了吗。起点差几个小时也算同一期（换过时区、夏令时）
    static func hasSummary(_ period: MoodSummary.Period, startingAt start: Date, in summaries: [MoodSummary]) -> Bool {
        summaries.contains { $0.periodKind == period && abs($0.periodStart.timeIntervalSince(start)) < 12 * 3600 }
    }

    private static let weekdayKeys = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// 这一期要发的数字；记了心情的不到 3 篇就是 nil（不写）
    static func request(_ period: MoodSummary.Period, interval: DateInterval, entries: [JournalEntry],
                        language: String) -> MoodSummaryRequest? {
        let items = MoodInsights.moodEntries(entries, in: interval)
        guard items.count >= MoodInsights.minimumSample, let average = MoodInsights.averageValence(items) else { return nil }
        let previous = previous(of: interval, period).flatMap { MoodInsights.averageValence(MoodInsights.moodEntries(entries, in: $0)) }
        let bucket: MoodInsights.TrendBucket = switch period {
        case .week: .day
        case .month: .week
        case .year: .month
        }
        let cal = calendar
        typealias G = MoodSummaryRequest.Group
        return MoodSummaryRequest(
            period: period.rawValue,
            periodStart: interval.start,
            periodEnd: interval.end,
            language: language,
            entryCount: items.count,
            averageValence: average,
            levels: MoodInsights.levelCounts(items),
            labels: MoodInsights.topLabels(items).map { .init(label: $0.label.rawValue, count: $0.count) },
            weather: MoodInsights.byWeather(items).map { G(key: $0.kind.rawValue, valence: $0.group.valence, count: $0.group.count) },
            // 地名不发：按篇数排第几处
            places: MoodInsights.byPlace(items).enumerated().map { G(key: "place\($0.offset + 1)", valence: $0.element.valence, count: $0.element.count) },
            weekdays: MoodInsights.byWeekday(items, calendar: cal).map { G(key: weekdayKeys[$0.weekday - 1], valence: $0.group.valence, count: $0.group.count) },
            dayParts: MoodInsights.byDayPart(items, calendar: cal).map { G(key: $0.part.rawValue, valence: $0.group.valence, count: $0.group.count) },
            trend: MoodInsights.trend(items, bucket: bucket, calendar: cal).map { .init(start: $0.start, valence: $0.valence, count: $0.count) },
            previousAverage: previous
        )
    }

    /// 该写的那几期：刚结束、没写过、够 3 篇
    static func due(entries: [JournalEntry], summaries: [MoodSummary], now: Date = .now)
        -> [(period: MoodSummary.Period, interval: DateInterval, request: MoodSummaryRequest)] {
        let language = LetterLanguage.appLanguage
        return MoodSummary.Period.allCases.compactMap { period in
            guard let interval = lastCompleted(period, now: now),
                  !hasSummary(period, startingAt: interval.start, in: summaries),
                  !inFlight.contains(key(period, interval)),
                  let request = request(period, interval: interval, entries: entries, language: language) else { return nil }
            return (period, interval, request)
        }
    }

    /// 写一期并存进本机（随 iCloud 同步）。失败抛出，由页面显示「这期小结没写成」
    static func write(_ period: MoodSummary.Period, interval: DateInterval, request: MoodSummaryRequest,
                      ai: AIService, context: ModelContext) async throws {
        let k = key(period, interval)
        inFlight.insert(k)
        defer { inFlight.remove(k) }
        let draft = try await ai.generateMoodSummary(request)
        let summary = MoodSummary(period: period, periodStart: interval.start, periodEnd: interval.end,
                                  text: draft.summary, suggestions: draft.suggestions, language: request.language,
                                  entryCount: request.entryCount, heavy: draft.heavy)
        context.insert(summary)
        try context.save()
        NSLog("ℹ️ [MoodSummary] 写好 %@ %@ %ld 篇%@", period.rawValue, interval.start as NSDate,
              request.entryCount, draft.heavy ? "（很沉）" : "")
    }

    private static func key(_ period: MoodSummary.Period, _ interval: DateInterval) -> String {
        "\(period.rawValue)-\(Int(interval.start.timeIntervalSince1970))"
    }
}
