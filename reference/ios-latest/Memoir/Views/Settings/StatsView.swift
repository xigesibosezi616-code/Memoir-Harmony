import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(StoreKitManager.self) private var store
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [JournalEntry]
    /// 情绪小结（会员），新的在前
    @Query(sort: \MoodSummary.periodStart, order: .reverse) private var summaries: [MoodSummary]
    @State private var writingSummaries: Set<MoodSummary.Period> = []
    @State private var failedSummaries: Set<MoodSummary.Period> = []
    @State private var showPaywall = false

    /// 情绪捕捉那一段的时间范围（走势、分布、情绪词、天气、地点、星期时段一起跟着变）。
    /// 上方三个数字卡片和写作日历仍是全期 ——「连续写作 / 总篇数 / 总字数」按区间算没有意义。
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
                    // 最长连续写作（2026-10-28）：只升不降，断了也不归零，规则见 `WritingStreak`
                    statCard("最长连续", value: "\(WritingStreak.best(in: entries))", unit: "天", theme: theme)
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

                // 情绪捕捉（2026-10-27）：免费的这几张图全在本机算，规则见 `MoodInsights`
                sectionTitle("情绪捕捉", theme: theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                // 情绪小结（会员）：自己有周 / 月 / 年，不跟下面的时间范围走
                MoodSummaryCard(summaries: summaries, writing: writingSummaries, failed: failedSummaries,
                                isMember: store.isMember, isLoggedIn: env.session.isLoggedIn,
                                onRetry: { period in
                                    failedSummaries.remove(period)
                                    Task { await writeDueSummaries() }
                                },
                                onUnlock: { showPaywall = true })

                RangePicker(selection: $moodRange, theme: theme)

                let items = MoodInsights.moodEntries(entries, range: moodRange)
                insightCard("心情走势", theme: theme) {
                    MoodTrendChart(points: MoodInsights.trend(items, bucket: MoodInsights.bucket(for: moodRange)),
                                   byMonth: MoodInsights.bucket(for: moodRange) == .month, theme: theme)
                }

                insightCard("心情分布", theme: theme) {
                    MoodDonutChart(data: moodData, theme: theme)
                }

                let labels = MoodInsights.topLabels(items)
                if !labels.isEmpty {
                    insightCard("最常出现的情绪", theme: theme) {
                        LabelCountList(items: labels, theme: theme)
                    }
                }

                let weather = MoodInsights.byWeather(items)
                if !weather.isEmpty {
                    insightCard("天气与心情", theme: theme) {
                        VStack(spacing: 12) {
                            ForEach(weather, id: \.kind) { item in
                                MoodScaleRow(title: Text(item.kind.title), group: item.group, theme: theme)
                            }
                        }
                    }
                }

                let places = MoodInsights.byPlace(items)
                if !places.isEmpty {
                    insightCard("地点与心情", theme: theme) {
                        VStack(spacing: 12) {
                            ForEach(places) { group in
                                MoodScaleRow(title: Text(verbatim: group.id), group: group, theme: theme)   // 地名是数据，不翻译
                            }
                        }
                    }
                }

                let weekdays = MoodInsights.byWeekday(items, calendar: localeCalendar)
                let dayParts = MoodInsights.byDayPart(items)
                if !weekdays.isEmpty || !dayParts.isEmpty {
                    insightCard("星期与时段", theme: theme) {
                        VStack(spacing: 12) {
                            ForEach(weekdays, id: \.weekday) { item in
                                MoodScaleRow(title: Text(verbatim: weekdaySymbol(item.weekday)), group: item.group, theme: theme)
                            }
                            if !weekdays.isEmpty && !dayParts.isEmpty {
                                Rectangle().fill(theme.border).frame(height: 0.5).padding(.vertical, 2)
                            }
                            ForEach(dayParts, id: \.part) { item in
                                MoodScaleRow(title: Text(item.part.title), group: item.group, theme: theme)
                            }
                        }
                    }
                }

                // 天气 / 地点 / 星期时段至少有一张没出来：说一句为什么，免得以为坏了
                if weather.isEmpty || places.isEmpty || (weekdays.isEmpty && dayParts.isEmpty) {
                    Text("天气、地点、星期和时段，每一组至少记 3 篇心情才显示。多写几篇，规律会慢慢浮出来。")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
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
        .paywallCover(isPresented: $showPaywall)
        // 最长连续写作：看一眼就记一次（显示本身不写入）
        .onAppear { WritingStreak.update(with: entries) }
        // 会员打开写作统计时，把刚结束、还没写的那几期小结写了（规则见 `MoodSummaryWriter`）
        .task(id: store.isMember) { await writeDueSummaries() }
        // 用 sheet 而不是 push：统计页是「看数据」的地方，点一天只是顺手翻一眼，
        // 看完该回到统计页而不是陷进日记的导航栈里。
        .sheet(item: $pickedDay) { picked in
            DayEntriesSheet(
                date: picked.date,
                entries: entriesByDay[Calendar.current.startOfDay(for: picked.date)] ?? []
            )
        }
    }

    /// 刚结束、没写过、够 3 篇的那几期，一期一期写（不并发，免得一进来连问三次）
    private func writeDueSummaries() async {
        guard store.isMember, env.session.isLoggedIn else { return }
        for item in MoodSummaryWriter.due(entries: entries, summaries: summaries) {
            writingSummaries.insert(item.period)
            do {
                try await MoodSummaryWriter.write(item.period, interval: item.interval, request: item.request,
                                                  ai: env.ai, context: modelContext)
                failedSummaries.remove(item.period)
            } catch {
                // 写不成不弹窗（不是用户刚做的动作）：卡片上写一句「没写成」并给重试，日志打完整 error
                let ns = error as NSError
                NSLog("⚠️ [MoodSummary] 写 %@ 失败 domain=%@ code=%ld %@", item.period.rawValue, ns.domain, ns.code, "\(error)")
                failedSummaries.insert(item.period)
            }
            writingSummaries.remove(item.period)
        }
    }

    /// 星期按 App 语言排（一周从哪天开始、叫什么都跟着语言）
    private var localeCalendar: Calendar {
        var c = Calendar.current
        c.locale = appLocale
        return c
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        localeCalendar.shortStandaloneWeekdaySymbols[(weekday - 1) % 7]
    }

    private func sectionTitle(_ title: LocalizedStringKey, theme: any AppTheme) -> some View {
        Text(title)
            .font(theme.labelFont)
            .foregroundStyle(theme.textSecondary)
            .tracking(theme.letterSpacingWide)
    }

    private func insightCard<Content: View>(_ title: LocalizedStringKey, theme: any AppTheme,
                                            @ViewBuilder content: () -> Content) -> some View {
        let body = content()
        return ThemedCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .tracking(theme.letterSpacingWide)
                body
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 标题必须是 `LocalizedStringKey`：以前是 `String`，`Text(String)` 不查表，外语下这三张卡一直显示中文
    private func statCard(_ title: LocalizedStringKey, value: String, unit: String, theme: any AppTheme) -> some View {
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

// MARK: - 情绪捕捉的几张图

/// 心情走势：每一格的平均愉悦度连成线，点的颜色是那一档的颜色；中间虚线是「不悲不喜」。
/// 没记心情的那一格不画（「没写」不等于「不悲不喜」）
private struct MoodTrendChart: View {
    let points: [MoodInsights.TrendPoint]
    let byMonth: Bool
    let theme: any AppTheme

    var body: some View {
        if points.count < 2 {
            Text("再写几篇，就能看出走势")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
        } else {
            Chart {
                    RuleMark(y: .value("不悲不喜", 0))
                        .lineStyle(StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                        .foregroundStyle(theme.textTertiary.opacity(0.5))
                    ForEach(points) { p in
                        LineMark(x: .value("日期", p.start, unit: byMonth ? .month : .day),
                                 y: .value("心情", p.valence))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 1.2))
                            .foregroundStyle(theme.textTertiary.opacity(0.55))
                        PointMark(x: .value("日期", p.start, unit: byMonth ? .month : .day),
                                  y: .value("心情", p.valence))
                            .symbolSize(48)
                            .foregroundStyle(p.level.tint)
                    }
                }
                .chartYScale(domain: -1...1)
                .chartYAxis(.hidden)
                .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 20))
                // 日期按 App 语言排（中文「10/4」）：FormatStyle 自带 locale，不跟视图环境，得单独给
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: (byMonth ? Date.FormatStyle.dateTime.month(.abbreviated) : .dateTime.month(.defaultDigits).day()).locale(appLocale))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                // 纵轴不画，只在图里左上、左下各写一个字：上面是愉快、下面是低落
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        if let plot = proxy.plotFrame.map({ geo[$0] }) {
                            ZStack(alignment: .topLeading) {
                                Text("愉快").offset(x: plot.minX, y: plot.minY)
                                Text("低落").offset(x: plot.minX, y: plot.maxY - 13)
                            }
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary.opacity(0.8))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
                .frame(height: 150)
        }
    }
}

/// 一行「这一组的平均心情落在哪」：左边是组名，中间一条从低落到愉快的刻度（颜色顺着九档），点在平均值上，
/// 右边是那一档的名字和篇数。天气、地点、星期、时段共用，几张卡片读法一样
private struct MoodScaleRow: View {
    let title: Text
    let group: MoodInsights.Group
    let theme: any AppTheme

    var body: some View {
        HStack(spacing: 10) {
            title
                .font(theme.labelFont)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)

            GeometryReader { geo in
                let width = geo.size.width
                let x = (min(max(group.valence, -1), 1) + 1) / 2 * width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: MoodLevel.allCases.map { $0.tint.opacity(0.3) },
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 4)
                    // 正中是「不悲不喜」
                    Rectangle()
                        .fill(theme.textTertiary.opacity(0.4))
                        .frame(width: 1, height: 10)
                        .offset(x: width / 2 - 0.5)
                    Circle()
                        .fill(group.level.tint)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(theme.cardBackground, lineWidth: 2))
                        .offset(x: x - 6)
                }
                .frame(width: width, height: geo.size.height)
            }
            .frame(height: 14)

            Text(group.level.title)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(width: 76, alignment: .trailing)
            Text("\(group.count)")
                .font(theme.labelFont)
                .foregroundStyle(theme.textTertiary)
                .frame(width: 24, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 最常出现的情绪词：圆点是这个词所在那一档的颜色，条的长短按次数
private struct LabelCountList: View {
    let items: [MoodInsights.LabelCount]
    let theme: any AppTheme

    var body: some View {
        let top = Double(items.map(\.count).max() ?? 1)
        VStack(spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Circle()
                        .fill(item.label.level.tint)
                        .frame(width: 8, height: 8)
                    Text(item.label.title)
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .frame(width: 64, alignment: .leading)
                    GeometryReader { geo in
                        Capsule()
                            .fill(item.label.level.tint.opacity(0.55))
                            .frame(width: max(6, geo.size.width * Double(item.count) / top), height: 6)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 14)
                    Text("\(item.count)")
                        .font(theme.labelFont)
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }
}

extension MoodInsights.WeatherKind {
    var title: LocalizedStringKey {
        switch self {
        case .clear: return "晴"
        case .cloudy: return "多云"
        case .rain: return "雨"
        case .snow: return "雪"
        case .fog: return "雾霾"
        case .wind: return "大风"
        }
    }
}

extension MoodInsights.DayPart {
    var title: LocalizedStringKey {
        switch self {
        case .morning: return "早上"
        case .afternoon: return "下午"
        case .evening: return "晚上"
        case .night: return "深夜"
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
