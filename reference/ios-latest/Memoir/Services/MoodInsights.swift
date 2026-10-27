import Foundation

/// 情绪捕捉（2026-10-27 产品定，取代原计划的「回望」）：写作统计里免费的那几张图，**全在本机算，不联网**。
///
/// 规则（鸿蒙照抄，见 HarmonyUpdates U14）：
/// - 只算**记了心情**的日记（心情页上线前写的、跳过的都不进分母）
/// - 时间范围跟着页面上的「近 7 天 / 近 30 天 / 今年 / 全部」走（`StatsRange`）
/// - 天气、地点、星期、时段：**一组不到 `minimumSample` 篇不显示** —— 两三篇看不出规律，硬画出来会误导
/// - 「心情」一律用愉悦度（-1…1）的平均值，再落回九档取颜色和名字（`MoodLevel(valence:)`）
enum MoodInsights {
    /// 一组至少几篇才显示
    static let minimumSample = 3
    /// 地点最多列几处（按篇数从多到少）
    static let placeLimit = 5
    /// 情绪词最多列几个
    static let labelLimit = 5

    /// 一组日记的平均心情
    struct Group: Identifiable, Equatable {
        let id: String
        let valence: Double
        let count: Int
        var level: MoodLevel { MoodLevel(valence: valence) }
    }

    struct TrendPoint: Identifiable, Equatable {
        /// 这一格的起点（某一天 0 点，或某个月 1 号 0 点）
        let start: Date
        let valence: Double
        let count: Int
        var id: Date { start }
        var level: MoodLevel { MoodLevel(valence: valence) }
    }

    struct LabelCount: Identifiable, Equatable {
        let label: MoodLabel
        let count: Int
        var id: String { label.rawValue }
    }

    /// 记了心情的一篇：日记和它的愉悦度
    typealias Item = (entry: JournalEntry, valence: Double)

    /// 页面上选的范围里记了心情的日记
    static func moodEntries(_ entries: [JournalEntry], range: StatsRange, now: Date = .now,
                            calendar: Calendar = .current) -> [Item] {
        entries.compactMap { e in
            guard let v = e.moodValence, range.contains(e.date, now: now, calendar: calendar) else { return nil }
            return (e, v)
        }
    }

    /// 某一期（情绪小结用，`MoodSummaryWriter`）里记了心情的日记
    static func moodEntries(_ entries: [JournalEntry], in interval: DateInterval) -> [Item] {
        entries.compactMap { e in
            guard let v = e.moodValence, e.date >= interval.start, e.date < interval.end else { return nil }
            return (e, v)
        }
    }

    static func averageValence(_ items: [Item]) -> Double? {
        items.isEmpty ? nil : average(items.map(\.valence))
    }

    // MARK: - 心情走势

    /// 走势一格多长
    enum TrendBucket { case day, week, month }

    /// 页面上：近 7 天、近 30 天按天；今年、全部按月
    static func bucket(for range: StatsRange) -> TrendBucket {
        range == .year || range == .all ? .month : .day
    }

    /// 每一格的平均心情。没记心情的那一格不画（不补 0 —— 「没写」不等于「不悲不喜」）
    static func trend(_ items: [Item], bucket: TrendBucket, calendar: Calendar = .current) -> [TrendPoint] {
        let groups = Dictionary(grouping: items) { item -> Date in
            let d = item.entry.date
            switch bucket {
            case .day: return calendar.startOfDay(for: d)
            case .week: return calendar.dateInterval(of: .weekOfYear, for: d)?.start ?? calendar.startOfDay(for: d)
            case .month: return calendar.date(from: calendar.dateComponents([.year, .month], from: d)) ?? d
            }
        }
        return groups.map { start, items in
            TrendPoint(start: start, valence: average(items.map(\.valence)), count: items.count)
        }
        .sorted { $0.start < $1.start }
    }

    /// 九档各几篇，从「跌入谷底」到「心花怒放」
    static func levelCounts(_ items: [Item]) -> [Int] {
        var counts = Array(repeating: 0, count: MoodLevel.count)
        for item in items { counts[MoodLevel(valence: item.valence).rawValue] += 1 }
        return counts
    }

    // MARK: - 常出现的情绪

    /// 选过的情绪词，按次数从多到少；次数一样按九档从低到高排（先看到需要照顾的那些）
    static func topLabels(_ items: [Item]) -> [LabelCount] {
        let labels = items.flatMap { $0.entry.moodLabelList }
        let counts = Dictionary(grouping: labels, by: { $0 }).mapValues(\.count)
        let order = MoodLabel.allCases
        return counts
            .map { LabelCount(label: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count
                : (order.firstIndex(of: $0.label) ?? 0) < (order.firstIndex(of: $1.label) ?? 0) }
            .prefix(labelLimit)
            .map { $0 }
    }

    // MARK: - 天气

    /// 天气归成六类。日记里存的是 WeatherKit 给的 SF Symbol 名（如 `cloud.sun.rain`），老日记是自定义代码（如 `heavyRain`）
    enum WeatherKind: String, CaseIterable {
        case clear, cloudy, rain, snow, fog, wind

        /// 认不出的（如「酷寒」`thermometer.snowflake`）不归类、不进统计
        init?(code: String) {
            let c = code.lowercased()
            func has(_ words: String...) -> Bool { words.contains { c.contains($0) } }
            if has("snow", "sleet", "hail", "flurries", "blizzard") { self = .snow }
            else if has("rain", "drizzle", "bolt", "thunder") { self = .rain }
            else if has("fog", "haze", "smoke", "dust") { self = .fog }
            else if has("wind", "tornado", "hurricane", "tropicalstorm") { self = .wind }
            else if has("cloud") { self = .cloudy }
            else if has("sun", "moon", "clear", "hot") { self = .clear }
            else { return nil }
        }
    }

    static func byWeather(_ items: [Item]) -> [(kind: WeatherKind, group: Group)] {
        let groups = Dictionary(grouping: items) { item in item.entry.weatherCode.flatMap { WeatherKind(code: $0) } }
        return WeatherKind.allCases.compactMap { kind in
            guard let g = groups[kind], g.count >= minimumSample else { return nil }
            return (kind, Group(id: kind.rawValue, valence: average(g.map(\.valence)), count: g.count))
        }
    }

    // MARK: - 地点

    /// 常写日记的几处地方（地名按日记上存的原样，精度跟着当时的「位置精度」设置），按篇数从多到少
    static func byPlace(_ items: [Item]) -> [Group] {
        let groups = Dictionary(grouping: items) { item -> String in
            (item.entry.locationInfo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return groups
            .filter { !$0.key.isEmpty && $0.value.count >= minimumSample }
            .map { Group(id: $0.key, valence: average($0.value.map(\.valence)), count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
            .prefix(placeLimit)
            .map { $0 }
    }

    // MARK: - 星期、时段

    /// 按星期几（1 = 周日 … 7 = 周六，同 `Calendar`），顺序跟着这种语言的一周从哪天开始
    static func byWeekday(_ items: [Item], calendar: Calendar = .current) -> [(weekday: Int, group: Group)] {
        let groups = Dictionary(grouping: items) { calendar.component(.weekday, from: $0.entry.date) }
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return order.compactMap { day in
            guard let g = groups[day], g.count >= minimumSample else { return nil }
            return (day, Group(id: "\(day)", valence: average(g.map(\.valence)), count: g.count))
        }
    }

    /// 一天里的四段：早上 5–11 点、下午 11–17 点、晚上 17–23 点、深夜 23–5 点（按写日记那一刻）
    enum DayPart: String, CaseIterable {
        case morning, afternoon, evening, night

        init(hour: Int) {
            switch hour {
            case 5..<11: self = .morning
            case 11..<17: self = .afternoon
            case 17..<23: self = .evening
            default: self = .night
            }
        }
    }

    static func byDayPart(_ items: [Item], calendar: Calendar = .current) -> [(part: DayPart, group: Group)] {
        let groups = Dictionary(grouping: items) { DayPart(hour: calendar.component(.hour, from: $0.entry.date)) }
        return DayPart.allCases.compactMap { part in
            guard let g = groups[part], g.count >= minimumSample else { return nil }
            return (part, Group(id: part.rawValue, valence: average(g.map(\.valence)), count: g.count))
        }
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

extension MoodLabel {
    /// 这个情绪词属于九档里的哪一档（心情页就是按档给词的，见 `choices(for:)`）
    var level: MoodLevel { MoodLevel.allCases.first { MoodLabel.choices(for: $0).contains(self) } ?? .even }
}
