import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Query private var entries: [JournalEntry]

    /// 心情分布的时间范围。**只影响饼图**，上方三个数字卡片仍是全期统计 ——
    /// 「连续写作 / 总篇数 / 总字数」按区间算没有意义。
    @State private var moodRange: StatsRange = .month

    private var stats: WritingStats {
        StatsCalculator.calculate(from: entries)
    }

    private var moodData: MoodChartData {
        StatsCalculator.moodChartData(entries: entries, range: moodRange)
    }

    /// 被点开的那一天。包成 Identifiable 才能喂给 `.sheet(item:)`
    struct PickedDay: Identifiable {
        let date: Date
        var id: TimeInterval { date.timeIntervalSince1970 }
    }
    @State private var pickedDay: PickedDay?

    /// 按「天」分组，日历格子和当天列表共用同一份 —— 两处各算一遍迟早会不一致
    private var entriesByDay: [Date: [JournalEntry]] {
        Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
    }

    var body: some View {
        let theme = themeManager.current
        ScrollView {
            VStack(spacing: 16) {
                // Stats cards
                HStack(spacing: 12) {
                    statCard("连续写作", value: "\(stats.streakDays)", unit: "天", theme: theme)
                    statCard("总篇数", value: "\(stats.totalEntries)", unit: "篇", theme: theme)
                    statCard("总字数", value: "\(stats.totalWords)", unit: "字", theme: theme)
                }

                // 写作日历
                ThemedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("写作日历")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                            .tracking(theme.letterSpacingWide)
                        WritingCalendar(entriesByDay: entriesByDay, theme: theme) { date in
                            pickedDay = PickedDay(date: date)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Mood distribution
                ThemedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("心情分布")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                            .tracking(theme.letterSpacingWide)

                        RangePicker(selection: $moodRange, theme: theme)

                        MoodDonutChart(data: moodData, theme: theme)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("写作统计")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        // 用 sheet 而不是 push：统计页是「看数据」的地方，点一天只是顺手翻一眼，
        // 看完该回到统计页而不是陷进日记的导航栈里。
        .sheet(item: $pickedDay) { picked in
            DayEntriesSheet(
                date: picked.date,
                entries: entriesByDay[Calendar.current.startOfDay(for: picked.date)] ?? []
            )
        }
    }

    private func statCard(_ title: String, value: String, unit: String, theme: any AppTheme) -> some View {
        ThemedCard {
            VStack(spacing: 4) {
                Text(value)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                Text(title)
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 写作日历

/// 一格日期。`date` 为 nil 表示当月之外的占位格（用来把 1 号顶到正确的星期列上）。
private struct CalendarCell: Identifiable {
    let id: Int
    let date: Date?
}

/// 写作日历 —— **真实月历排布**，不是 1→31 的平铺网格。
///
/// 与旧的 `MonthHeatmap` 的区别：
/// - **按星期对齐**：1 号落在它真正的星期列上，前面补空格。旧版把 1 号硬顶在第一格，
///   于是整个月的星期全是错位的，"周末写得多吗"这类问题根本看不出来
/// - **可翻月**：不再只能看当月
/// - **可点**：有日记的那天点进去看当天写了什么
/// - **星期表头与首日跟随语言**：`firstWeekday` 在中文/英文下是周日、法语下是周一，
///   交给 `Calendar` 按 `appLocale` 决定，不写死
private struct WritingCalendar: View {
    let entriesByDay: [Date: [JournalEntry]]
    let theme: any AppTheme
    let onPick: (Date) -> Void

    @State private var monthAnchor: Date = .now

    private var calendar: Calendar {
        var c = Calendar.current
        c.locale = appLocale
        return c
    }

    /// 当月的格子：前置占位 + 实际日期。
    private var cells: [CalendarCell] {
        let cal = calendar
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor)),
              let dayRange = cal.range(of: .day, in: .month, for: monthStart) else { return [] }

        // 1 号是星期几 → 前面要空几格。firstWeekday 随 locale 变（周日起 or 周一起）
        let leading = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7

        var result: [CalendarCell] = (0..<leading).map { CalendarCell(id: -($0 + 1), date: nil) }
        for day in dayRange {
            let date = cal.date(byAdding: .day, value: day - 1, to: monthStart)
            result.append(CalendarCell(id: day, date: date))
        }
        return result
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = appLocale
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f.string(from: monthAnchor)
    }

    /// 星期表头，按 locale 的首日轮转（中/英是周日起，法语是周一起）
    private var weekdaySymbols: [String] {
        let cal = calendar
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// 能不能再往后翻 —— 不给看未来的月份，那里不可能有日记
    private var canGoForward: Bool {
        let cal = calendar
        let thisMonth = cal.dateComponents([.year, .month], from: .now)
        let shown = cal.dateComponents([.year, .month], from: monthAnchor)
        return !(shown.year == thisMonth.year && shown.month == thisMonth.month)
    }

    var body: some View {
        VStack(spacing: 10) {
            // 月份导航
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.plain)

                Spacer()
                Text(monthTitle)   // 已按 appLocale 格式化，是数据不是文案
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                Spacer()

                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(canGoForward ? theme.textSecondary : theme.textTertiary.opacity(0.35))
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
            }

            // 星期表头
            HStack(spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells) { cell in
                    if let date = cell.date {
                        dayCell(date: date)
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(date: Date) -> some View {
        let cal = calendar
        let count = entriesByDay[cal.startOfDay(for: date)]?.count ?? 0
        let isToday = cal.isDateInToday(date)

        Button {
            if count > 0 { onPick(date) }
        } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(count > 0 ? theme.accent : theme.surfaceBackground)
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Text("\(cal.component(.day, from: date))")
                        .font(.system(size: 11, weight: count > 0 ? .medium : .regular))
                        .foregroundStyle(count > 0 ? theme.background : theme.textTertiary)
                )
                .overlay(
                    // 今天描一圈，即使没写日记也能定位「今天在哪」
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isToday ? theme.textPrimary : Color.clear, lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: monthAnchor) else { return }
        if delta > 0 && !canGoForward { return }
        withAnimation(.easeInOut(duration: 0.2)) { monthAnchor = next }
    }
}

// MARK: - Mood Bar Chart

/// 时间范围切换。用胶囊分段而不是系统 `Picker(.segmented)` ——
/// 后者的配色由 tint 决定，接不上三套主题。
private struct RangePicker: View {
    @Binding var selection: StatsRange
    let theme: any AppTheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(StatsRange.allCases) { range in
                let isOn = selection == range
                Button {
                    withAnimation(.spring(duration: 0.25)) { selection = range }
                } label: {
                    Text(range.displayName)
                        .font(theme.labelFont)
                        .foregroundStyle(isOn ? theme.background : theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isOn ? theme.accent : Color.clear)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(isOn ? Color.clear : theme.border, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

/// 心情分布环形图 + 图例（九档，颜色取自线团爱心那一档，见 `MoodLevel.tint`）。
///
/// 用环形（`innerRadius`）而不是实心饼：中间那个洞不是装饰，
/// 用来放**这个区间记了心情的总篇数** —— 看比例的同时得知道样本量，
/// 「3 篇里 2 篇不悲不喜」和「300 篇里 200 篇不悲不喜」不是一回事。
private struct MoodDonutChart: View {
    let data: MoodChartData
    let theme: any AppTheme

    var body: some View {
        if data.isEmpty {
            Text("这段时间还没有记录心情")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
        } else {
            VStack(spacing: 16) {
                Chart(data.slices) { slice in
                    SectorMark(
                        angle: .value("count", slice.count),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(slice.level.tint)
                }
                .chartLegend(.hidden)   // 系统图例给不出百分比和篇数，自己画
                .frame(height: 180)
                .overlay {
                    VStack(spacing: 2) {
                        Text("\(data.total)")
                            .font(.system(size: 28, weight: .light, design: .serif))
                            .foregroundStyle(theme.textPrimary)
                        Text("篇")
                            .font(theme.labelFont)
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(data.slices) { slice in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(slice.level.tint)
                                .frame(width: 8, height: 8)
                            Text(slice.level.title)
                                .font(theme.labelFont)
                                .foregroundStyle(theme.textSecondary)
                            Spacer()
                            Text(String(format: "%.0f%%", slice.percentage))
                                .font(theme.labelFont)
                                .foregroundStyle(theme.textPrimary)
                            Text("\(slice.count)")
                                .font(theme.labelFont)
                                .foregroundStyle(theme.textTertiary)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 某天的日记

/// 点日历某一天弹出来的列表。
///
/// **自带 `NavigationStack`** —— 它活在 sheet 里，外层统计页的导航栈到不了这儿；
/// 不自带的话点进日记详情会没有返回路径。
private struct DayEntriesSheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let entries: [JournalEntry]

    private var title: String {
        let f = DateFormatter()
        f.locale = appLocale
        f.setLocalizedDateFormatFromTemplate("yMMMMd")
        return f.string(from: date)
    }

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(entries.sorted { $0.date > $1.date }) { entry in
                        NavigationLink(value: entry) {
                            EntryRowView(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .background(theme.background)
            .navigationDestination(for: JournalEntry.self) { entry in
                EntryDetailView(entry: entry)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)   // 已按 appLocale 格式化，是数据不是文案
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("完成")
                            .font(theme.labelFont)
                            .foregroundStyle(theme.accent)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
