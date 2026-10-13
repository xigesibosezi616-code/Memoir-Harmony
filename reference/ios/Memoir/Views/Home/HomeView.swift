import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @State private var showCompose = false
    @State private var showFloatingTitle = false
    /// 手记页展示方式：列表（找某一篇）/ 大屏（重看一篇）
    @AppStorage(HomeDisplayMode.storageKey) private var displayModeRaw: String = HomeDisplayMode.list.rawValue
    /// 大屏模式下点卡片要跳详情，用它驱动导航
    @State private var showcaseTarget: JournalEntry?

    private var displayMode: HomeDisplayMode {
        HomeDisplayMode(rawValue: displayModeRaw) ?? .list
    }
    private var isShowcase: Bool { displayMode == .showcase }

    /// 本月记录天数
    private var monthRecordDays: Int {
        let calendar = Calendar.current
        let now = Date.now
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let daysThisMonth = Set(
            entries
                .filter {
                    calendar.component(.year, from: $0.date) == year &&
                    calendar.component(.month, from: $0.date) == month
                }
                .map { calendar.startOfDay(for: $0.date) }
        )
        return daysThisMonth.count
    }

    private var groupedEntries: [(key: String, entries: [JournalEntry])] {
        let grouped = Dictionary(grouping: entries) { $0.date.yearMonthKey }
        return grouped
            .map { (key: $0.key, entries: $0.value) }
            .sorted { $0.entries.first?.date ?? .distantPast > $1.entries.first?.date ?? .distantPast }
    }

    /// 写日记页从加号里「长」出来的转场（`matchedTransitionSource` + `.zoom`）。
    /// 列表模式的胶囊按钮与大屏模式的加号**共用同一个 id** —— 同一时刻只有一个在视图树里
    @Namespace private var composeTransition

    /// 两个入口共用的转场 id
    private static let composeSourceID = "compose"

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    // 大标题 + 语录区域。大屏模式下整体压缩，把高度让给卡片。
                    VStack(alignment: .leading, spacing: isShowcase ? 2 : 6) {
                        // 大标题（用 GeometryReader 监测可见性）
                        Text("MEMOIR · 尺素")
                            .font(.custom("Georgia", size: isShowcase ? 22 : 30))
                            .foregroundStyle(theme.textPrimary)
                            .tracking(isShowcase ? 1.4 : 2)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onChange(of: geo.frame(in: .global).maxY) { _, maxY in
                                            let shouldShow = maxY < 0
                                            if shouldShow != showFloatingTitle {
                                                withAnimation(.easeIn(duration: 0.2)) {
                                                    showFloatingTitle = shouldShow
                                                }
                                            }
                                        }
                                }
                            )
                            .padding(.bottom, isShowcase ? 1 : 4)

                        // 时段问候
                        Text(GreetingManager.timeBasedGreeting())
                            .font(.custom("Georgia", size: isShowcase ? 14 : 17))
                            .foregroundStyle(theme.textPrimary)

                        // 本月记录
                        if monthRecordDays > 0 {
                            Text("本月记录 \(monthRecordDays) 天")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                        }

                        // 每日语录（大屏模式下省掉，它最占高度且最不影响使用）
                        if !isShowcase {
                            Text(GreetingManager.dailyQuote())
                                .font(.custom("Georgia", size: 13))
                                .foregroundStyle(theme.textSecondary)
                                .italic()
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, isShowcase ? 4 : 12)
                    .padding(.bottom, 16)

                    if entries.isEmpty {
                        emptyState(theme: theme)
                    } else if isShowcase {
                        // 大屏展示：一屏一篇，左右滑动翻篇。
                        // 卡片撑到容器高度的八成 —— 头部已压缩、按钮移到了导航栏，这里可以给足张力。
                        ShowcaseView(entries: entries) { entry in
                            showcaseTarget = entry
                        }
                        .containerRelativeFrame(.vertical) { height, _ in
                            max(460, height * 0.80)
                        }
                    } else {
                        LazyVStack(spacing: 12, pinnedViews: .sectionHeaders) {
                            ForEach(groupedEntries, id: \.key) { group in
                                Section {
                                    ForEach(group.entries) { entry in
                                        NavigationLink(value: entry) {
                                            EntryRowView(entry: entry)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } header: {
                                    HStack {
                                        Text(group.key)
                                            .font(theme.captionFont)
                                            .foregroundStyle(theme.textTertiary)
                                            .tracking(theme.letterSpacingWide)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 6)
                                    .background(theme.background)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // 给底部按钮/Tab 栏留白；大屏模式按钮在导航栏，留一点即可
                    Spacer().frame(height: isShowcase ? 24 : 100)
                }
                .background(theme.background)

                // FAB —— 仅列表模式。大屏模式移到导航栏右上角的加号，把版面还给卡片。
                if !isShowcase {
                    Button {
                        showCompose = true
                    } label: {
                        Text("写下今天的故事")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.cardBackground)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(theme.accent)
                            .clipShape(Capsule())
                            .shadow(color: theme.accent.opacity(0.3), radius: 8, y: 4)
                    }
                    .matchedTransitionSource(id: Self.composeSourceID, in: composeTransition)
                    .padding(.bottom, 90)
                }
            }
            // 整页统一底色：ScrollView 自己那层不覆盖安全区之外的部分，
            // 会在页面上下留出两条别的颜色
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("MEMOIR · 尺素")
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                        .opacity(showFloatingTitle ? 1 : 0)
                }
                // 大屏模式：写日记入口收进右上角，版面全留给卡片
                if isShowcase {
                    ToolbarItem(placement: .topBarTrailing) {
                        CircleIconButton(systemName: "plus", prominence: .prominent, theme: theme) {
                            showCompose = true
                        }
                        .matchedTransitionSource(id: Self.composeSourceID, in: composeTransition)
                    }
                }
            }
            .navigationDestination(for: JournalEntry.self) { entry in
                EntryDetailView(entry: entry)
            }
            .navigationDestination(item: $showcaseTarget) { entry in
                EntryDetailView(entry: entry)
            }
            // 全屏而非 sheet：写日记要的是一张不受打扰的纸。
            // 顺带去掉了下滑关闭手势 —— 退出统一走返回键的「保存草稿 / 不保存」确认。
            .fullScreenCover(isPresented: $showCompose) {
                // 从加号里展开，而不是从屏幕底部推上来（与系统「日记」一致）
                ComposeView()
                    .navigationTransition(.zoom(sourceID: Self.composeSourceID, in: composeTransition))
            }
        }
    }

    private func emptyState(theme: any AppTheme) -> some View {
        VStack(spacing: 16) {
            ThemedCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("暂无日记")
                        .font(theme.headingFont)
                        .foregroundStyle(theme.textPrimary)
                    Text("点击下方按钮，开始书写今天的故事")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
    }

}

#Preview("Washi") {
    HomeView()
        .environment(ThemeManager())
        .modelContainer(for: [JournalEntry.self, Tag.self, MoodTag.self], inMemory: true)
}

#Preview("Leather") {
    let manager = ThemeManager()
    manager.currentThemeID = "leather"
    return HomeView()
        .environment(manager)
        .modelContainer(for: [JournalEntry.self, Tag.self, MoodTag.self], inMemory: true)
}
