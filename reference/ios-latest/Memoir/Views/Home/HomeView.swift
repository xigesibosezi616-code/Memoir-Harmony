import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @State private var showCompose = false
    /// 点「写」的那一刻有没有草稿：有就直接接着写，没有先选写在哪本里（`ComposeFlow`）
    @State private var composeHasDraft = false
    @State private var showFloatingTitle = false
    /// 手记页展示方式：列表（找某一篇）/ 大屏（重看一篇）
    @AppStorage(HomeDisplayMode.storageKey) private var displayModeRaw: String = HomeDisplayMode.list.rawValue
    /// 大屏模式下点卡片要跳详情，用它驱动导航
    @State private var showcaseTarget: JournalEntry?

    /// 大屏模式一屏放几篇（双指捏合换，记住上次的）
    @AppStorage(ShowcaseZoom.storageKey) private var zoomRaw = ShowcaseZoom.one.rawValue
    /// 一屏一篇 / 四篇时翻到了哪：捏小时以它为准，张开回来时停在手指底下那篇。
    /// 放在 `@Observable` 的对象里、这一页的 body 不读它 —— 翻一页只重画翻页那一块，不重画整个首页
    @State private var pages = ShowcasePages()
    /// 总览的版式（引用类型，滚动时在写）：捏合时按它算手指底下是哪篇
    @State private var overviewLayout = OverviewLayout()
    /// 页面宽度：总览格子多大照它算。只在宽度真变了才改（转屏），不跟着滚动重绘
    @State private var showcaseWidth: CGFloat = 0
    /// 滚动区、翻页区在屏幕上的位置（引用类型：滚动时在写，写它不重绘）
    @State private var geometry = ShowcaseGeometry()
    /// 正在捏：手指底下是哪篇、这一次捏合换过级没有
    @State private var pinch: PinchState?
    /// 换级的转场：往外缩（看更多篇）还是往里张，从哪一格缩放进出。先排好转场、下一轮再换级（见 `setZoom`）
    @State private var zoomingOut = true
    @State private var zoomAnchor: UnitPoint = .center
    /// 换级时在**同一帧**里把手指底下那篇滚到原处（排好再滚的话，中间会先跳到别的月份再滑回来）
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayMode: HomeDisplayMode {
        HomeDisplayMode(rawValue: displayModeRaw) ?? .list
    }
    private var isShowcase: Bool { displayMode == .showcase }
    private var zoom: ShowcaseZoom { ShowcaseZoom(rawValue: zoomRaw) ?? .one }

    private struct PinchState {
        let focus: UUID?
        /// 手指在滚动区里的相对位置
        let anchor: UnitPoint
        /// 这一次捏合已经换过一级了：一次只换一级（按次数，不按力度）
        var stepped = false
    }


    /// 本月记录天数。
    ///
    /// `entries` 是新的在前：从头往后数到上个月就停，不把几百篇全扫一遍（每次页面重画都要算它）
    private var monthRecordDays: Int {
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: .now)?.start else { return 0 }
        var days = Set<Date>()
        for entry in entries {
            if entry.date < monthStart { break }
            days.insert(calendar.startOfDay(for: entry.date))
        }
        return days.count
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
                        showcase
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

                    // 给底部按钮/Tab 栏留白；大屏模式按钮在导航栏，留一点即可（总览要滚到底，留出 Tab 栏的高度）
                    Spacer().frame(height: isShowcase ? (zoom == .one ? 24 : 96) : 100)
                }
                .background(theme.background)
                // 一屏 1 / 4 篇只左右翻，整页上下锁死；捏到 16 篇起才能上下滚（2026-10-21 用户定）。
                // 翻页的那两层自己再 `.scrollDisabled(false)` 打开 —— 这个开关是往下传的，不放开它们也翻不动了
                .scrollDisabled(isShowcase && zoom <= .four)
                .scrollPosition($scrollPosition)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    geometry.viewport = frame
                    if abs(frame.width - showcaseWidth) > 0.5 { showcaseWidth = frame.width }
                }
                .simultaneousGesture(magnify, including: isShowcase && !entries.isEmpty ? .all : .subviews)

                // FAB —— 仅列表模式。大屏模式移到导航栏右上角的加号，把版面还给卡片。
                if !isShowcase {
                    Button {
                        startWriting()
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
                            startWriting()
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
                // 从加号里展开，而不是从屏幕底部推上来（与系统「日记」一致）。
                // 2026-10-17 起先选写在哪本里，选好了同一页换成写日记
                ComposeFlow(hasDraft: composeHasDraft)
                    .navigationTransition(.zoom(sourceID: Self.composeSourceID, in: composeTransition))
            }
        }
    }

    // MARK: - 大屏：一屏 1 / 4 篇左右翻，16 / 64 篇上下滚，双指捏合换

    /// 一屏一篇是原来的大卡片、一屏四篇是 2 × 2 一页，都左右翻；捏到 16 / 64 篇是总览宫格（上下滚，按月分组）
    @ViewBuilder
    private var showcase: some View {
        let zoomTo = { (next: ShowcaseZoom?, focus: UUID) in
            if let next { setZoom(next, focus: focus, anchor: .center) }
        }
        switch zoom {
        case .one:
            // 卡片撑到容器高度的八成 —— 头部已压缩、按钮移到了导航栏，这里可以给足张力。
            ShowcaseView(entries: entries, pages: pages, onZoom: zoomTo) { entry in
                showcaseTarget = entry
            }
            .containerRelativeFrame(.vertical) { height, _ in max(460, height * 0.80) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { geometry.pager = $0 }
            .transition(levelTransition(grid: false))
        case .four:
            ShowcaseQuadPager(entries: entries, pages: pages, onZoom: zoomTo) { open($0) }
                .containerRelativeFrame(.vertical) { height, _ in max(460, height * 0.80) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { geometry.pager = $0 }
                .transition(levelTransition(grid: false))
        case .sixteen, .sixtyFour:
            // 16 ↔ 64 是同一个宫格换列数：格子从旧位置平滑挪到新位置
            ShowcaseOverview(entries: entries, zoom: zoom, width: showcaseWidth, layout: overviewLayout, onZoom: zoomTo) { open($0) }
                .transition(levelTransition(grid: true))
        }
    }

    /// 换级的转场：往外缩（看更多篇）时，旧的一层缩小淡出、新的一层从大一号落进来；往里张反过来。
    /// 翻页的那两级从手指那一格缩放进出；宫格很长，从顶上缩放
    private func levelTransition(grid: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        let anchor = grid ? UnitPoint.top : zoomAnchor
        let smaller = AnyTransition.scale(scale: 0.6, anchor: anchor).combined(with: .opacity)
        let larger = AnyTransition.scale(scale: 1.5, anchor: anchor).combined(with: .opacity)
        return zoomingOut ? .asymmetric(insertion: larger, removal: smaller) : .asymmetric(insertion: smaller, removal: larger)
    }

    /// 双指捏合（2026-10-21 用户定：**按次数，不按力度**）：往里捏一次 = 看更多篇一级（1 → 4 → 16 → 64），往外张一次 = 少一级。
    /// 捏过 0.8 倍 / 张过 1.25 倍就换，这一次捏合之后再怎么捏都不再换；页面不跟着手指缩放，没有惯性
    private var magnify: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard isShowcase, !entries.isEmpty, showcaseTarget == nil else { return }
                if pinch == nil {
                    let local = value.startLocation
                    let viewport = geometry.viewport
                    let global = CGPoint(x: viewport.minX + local.x, y: viewport.minY + local.y)
                    let anchor = UnitPoint(x: local.x / max(viewport.width, 1), y: local.y / max(viewport.height, 1))
                    pinch = PinchState(focus: focusEntry(at: global), anchor: anchor)
                }
                guard let current = pinch, !current.stepped else { return }
                let next: ShowcaseZoom?
                if value.magnification < 0.8 {
                    next = zoom.zoomedOut
                } else if value.magnification > 1.25 {
                    next = zoom.zoomedIn
                } else {
                    return
                }
                pinch?.stepped = true
                if let next { setZoom(next, focus: current.focus, anchor: current.anchor) }
            }
            .onEnded { _ in pinch = nil }
    }

    /// 换到 `next` 那一级，换完手指底下（`anchor` 处）还是 `focus` 那篇。
    ///
    /// 两步：先把转场的方向和缩放中心改好（要走的那一层得先按新方向重画一次，它的退场动画才对），下一轮再换级。
    /// 换级和滚动放在同一个事务里：滚到哪是按新的排版算的，不会先跳到别处再滑回来
    private func setZoom(_ next: ShowcaseZoom, focus: UUID?, anchor: UnitPoint) {
        guard next != zoom else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: next > zoom ? 0.55 : 0.7)
        zoomingOut = next > zoom
        zoomAnchor = ShowcaseQuadPager.slotAnchor(of: focus, in: entries)
        let animation: Animation = reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.4)
        DispatchQueue.main.async {
            withAnimation(animation) {
                switch next {
                case .one:
                    pages.single = focus ?? entries.first?.id
                    scrollPosition.scrollTo(edge: .top)
                case .four:
                    pages.quad = ShowcaseQuadPager.pageID(containing: focus, in: entries)
                    scrollPosition.scrollTo(edge: .top)
                case .sixteen, .sixtyFour:
                    if let focus { scrollPosition.scrollTo(id: focus, anchor: anchor) }
                }
                zoomRaw = next.rawValue
            }
        }
    }

    /// 手指底下是哪篇：一屏一篇时就是翻到的那篇；四篇时看手指落在这一页的哪一格；总览里是手指按着的那一格
    private func focusEntry(at point: CGPoint) -> UUID? {
        switch zoom {
        case .one:
            return pages.single ?? entries.first?.id
        case .four:
            return ShowcaseQuadPager.entry(at: point, pagerFrame: geometry.pager, page: pages.quad ?? entries.first?.id, in: entries)
        case .sixteen, .sixtyFour:
            return overviewLayout.entry(at: point)
        }
    }

    /// 总览、四篇一页里点了一格：打开那篇
    private func open(_ id: UUID) {
        showcaseTarget = entries.first { $0.id == id }
    }

    /// 两个「写」的入口（列表模式的胶囊、大屏模式的加号）
    private func startWriting() {
        composeHasDraft = DraftEntry.current(in: modelContext) != nil
        showCompose = true
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

/// 大屏翻页的那两级翻到了哪：一屏一篇时是那篇的 id，一屏四篇时是那一页第一篇的 id
@Observable
final class ShowcasePages {
    var single: UUID?
    var quad: UUID?
}

/// 大屏的滚动区、翻页区此刻在屏幕上的位置（全局坐标）。引用类型、不是 `@Observable`：滚动时在写，写它不能触发重绘
final class ShowcaseGeometry {
    var viewport: CGRect = .zero
    var pager: CGRect = .zero
}

#Preview("Washi") {
    HomeView()
        .environment(ThemeManager())
        .modelContainer(for: [JournalEntry.self, Tag.self], inMemory: true)
}

#Preview("Leather") {
    let manager = ThemeManager()
    manager.currentThemeID = "leather"
    return HomeView()
        .environment(manager)
        .modelContainer(for: [JournalEntry.self, Tag.self], inMemory: true)
}
