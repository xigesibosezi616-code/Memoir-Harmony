import SwiftUI
import SwiftData

/// 日记本主页（2026-10 P3，参考图 ① 首页 + ④ 目录 + ⑤ 宫格合成一页）。
///
/// 从上往下：
/// 1. **封面大图**（`BookHeroView`）：照片铺满，或这本的布面铺满；书名、副标题
/// 2. **目录**（`BookContentsView`）：按阅读顺序（从早到晚）编号，按月分组；可切换成宫格小样
/// 3. 底部常驻：「开始阅读」（从第一篇翻起）+ 写一篇
///
/// 点目录里任一篇 → 翻页阅读器从那一篇开始；阅读器本身不动（`DiaryReaderView`）。
/// 右上角「…」：换封面 / 重命名 / 删除（「全部日记」没有）。
struct BookDetailView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allEntries: [JournalEntry]
    @State private var showCompose = false
    @State private var readerDiary: JournalEntry?
    // 右上角「…」：换封面 / 重命名 / 删除（2026-10 从书架的长按菜单挪过来）
    @State private var showCoverSheet = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteAlert = false
    /// 目录用列表还是宫格。记住用户上次选的（所有日记本共用一个偏好）
    @AppStorage("bookContentsLayout") private var layoutRaw = BookContentsView.Layout.list.rawValue
    /// 滚动区的可视高度（含状态栏、导航栏下面那段），大图取它的 62%
    @State private var containerHeight: CGFloat = 0
    @State private var scrolledPastHero = false

    /// 大图高度：可视高度的 62%（参考图 ④ 的比例）。还没量到时先给个合理值
    private var heroHeight: CGFloat {
        containerHeight > 0 ? max(360, containerHeight * 0.62) : 470
    }

    let tag: Tag?

    /// 这本里的日记，按阅读顺序（从早到晚）
    private var readingEntries: [JournalEntry] {
        let entries = tag.map { tag in allEntries.filter { $0.tags.contains(tag.name) } } ?? allEntries
        return PageDataSource.readingOrder(entries)
    }

    /// 日记本名是用户数据，原样显示；「全部日记」要走翻译
    private var navigationTitle: String {
        tag?.name ?? NSLocalizedString("全部日记", bundle: .appLanguage, comment: "全部日记页标题")
    }

    private var layout: BookContentsView.Layout {
        BookContentsView.Layout(rawValue: layoutRaw) ?? .list
    }

    /// 大图上那行小字：用户写了副标题就用它，没写就是这本日记跨越的年月（「2026年3月 — 2026年9月」）
    private func heroSubtitle(_ entries: [JournalEntry]) -> String? {
        if let custom = tag?.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        guard let first = entries.first?.date, let last = entries.last?.date else { return nil }
        let start = BookContentsView.monthTitle(first)
        let end = BookContentsView.monthTitle(last)
        return start == end ? start : "\(start) — \(end)"
    }

    /// 大图是深色的：状态栏和导航栏按钮用浅色。
    /// 满版照片按深色处理（顶上压了一层暗）；白框是浅色纸面；贴照片和纯色看布面颜色
    private var heroIsDark: Bool {
        guard let tag else { return false }   // 全部日记：象牙白
        if tag.coverPhoto != nil {
            switch tag.coverLayout {
            case .fullBleed: return true
            case .framed:    return false
            case .tipIn:     break
            }
        }
        return !tag.bookColor.isLight
    }

    var body: some View {
        let theme = themeManager.current
        let entries = readingEntries
        ScrollView {
            VStack(spacing: 0) {
                BookHeroView(
                    title: navigationTitle,
                    subtitle: heroSubtitle(entries),
                    color: tag?.bookColor ?? .ivory,
                    photo: tag?.coverPhoto,
                    layout: tag?.coverLayout ?? .fullBleed
                )
                // 给定高度，不用 containerRelativeFrame —— 它在滚动区里不约束子视图，铺满的照片会把自己撑高
                .frame(height: heroHeight)

                contentsHeader(count: entries.count, theme: theme)

                if entries.isEmpty {
                    emptyState(theme: theme)
                } else {
                    BookContentsView(
                        entries: entries,
                        layout: layout,
                        onOpen: { readerDiary = $0 },
                        onCompose: { showCompose = true }
                    )
                }
            }
            .padding(.bottom, 24)
        }
        // 大图顶到屏幕最上沿，压在状态栏和导航栏下面（参考图 ①）
        .ignoresSafeArea(edges: .top)
        .background(theme.background)
        .safeAreaInset(edge: .bottom) {
            bottomBar(firstEntry: entries.first, theme: theme)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.containerSize.height + geo.contentInsets.top + geo.contentInsets.bottom
        } action: { _, height in
            containerHeight = height
        }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > heroHeight - 110
        } action: { _, past in
            withAnimation(.smooth(duration: 0.25)) { scrolledPastHero = past }
        }
        .navigationBarTitleDisplayMode(.inline)
        // 停在大图上时导航栏透明；滚过大图才出底色和标题
        .toolbarBackground(scrolledPastHero ? .automatic : .hidden, for: .navigationBar)
        .toolbarColorScheme(heroIsDark && !scrolledPastHero ? .dark : nil, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: navigationTitle)
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textSecondary)
                    .opacity(scrolledPastHero ? 1 : 0)
            }
            // 「全部日记」不是一本真的日记本，没有可改的
            if tag != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCoverSheet = true
                        } label: {
                            Label("编辑封面", systemImage: "paintbrush")
                        }
                        Button {
                            renameText = tag?.name ?? ""
                            showRename = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .navigationDestination(for: JournalEntry.self) { entry in
            EntryDetailView(entry: entry)
        }
        .sheet(isPresented: $showCoverSheet) {
            if let tag {
                CoverChangeSheet(
                    tag: tag,
                    onSave: { edit in
                        do {
                            try edit.apply(to: tag, in: modelContext)
                        } catch {
                            let ns = error as NSError
                            NSLog("❌ [BookDetail] 封面照片保存失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
                            env.errors.present(error, fallback: NSLocalizedString("保存失败", bundle: .appLanguage, comment: "通用保存失败"))
                        }
                        save()
                        // 新照片当场登记上云，不等下次启动对账
                        if case .replaced = edit.photo { MediaStorage.syncToCloud(in: modelContext) }
                        showCoverSheet = false
                    },
                    onCancel: { showCoverSheet = false }
                )
                .presentationDetents([.large])
            }
        }
        .alert("重命名日记本", isPresented: $showRename) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { commitRename() }
        }
        .alert("删除日记本", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteNotebook() }
        } message: {
            Text("删除日记本不会删除其中的日记，只会移除标签关联。")
        }
        // 全屏而非 sheet：写日记要的是一张不受打扰的纸。
        // 顺带去掉了下滑关闭手势 —— 退出统一走返回键的「保存草稿 / 不保存」确认。
        .fullScreenCover(isPresented: $showCompose) {
            if let tag {
                ComposeView(initialTags: [tag.name])
            } else {
                ComposeView()
            }
        }
        // 翻页阅读器（三个主题都进）
        .fullScreenCover(item: $readerDiary) { diary in
            DiaryReaderView(initialDiary: diary, entries: entries)
        }
        // 自动封条：每次进入此 Tag 的日记列表 → 刷新 lastOpenedAt（"全部日记"无 Tag，跳过）
        .onAppear {
            if let tag {
                withAnimation {
                    tag.lastOpenedAt = Date()
                }
                try? modelContext.save()
            }
        }
    }

    // MARK: - 目录抬头

    /// 「目录」……「N 篇」+ 列表 / 宫格切换（参考图 ④ 的 CONTENTS ……… Nº2 · 5 PAGES）
    private func contentsHeader(count: Int, theme: any AppTheme) -> some View {
        HStack(spacing: 14) {
            Text("目录")
                .font(theme.labelFont)
                .tracking(theme.letterSpacingWide * 1.5)
                .foregroundStyle(theme.textSecondary)
            Spacer()
            if count > 0 {
                Text("\(count) 篇")
                    .font(theme.labelFont)
                    .tracking(theme.letterSpacingWide)
                    .foregroundStyle(theme.textTertiary)
                layoutToggle(theme: theme)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func layoutToggle(theme: any AppTheme) -> some View {
        HStack(spacing: 2) {
            ForEach([BookContentsView.Layout.list, .grid], id: \.self) { option in
                Button {
                    withAnimation(.smooth(duration: 0.3)) { layoutRaw = option.rawValue }
                } label: {
                    Image(systemName: option == .list ? "list.bullet" : "square.grid.3x3")
                        .font(.system(size: 12))
                        .foregroundStyle(layout == option ? theme.textPrimary : theme.textTertiary)
                        .frame(width: 30, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option == .list ? Text("列表") : Text("宫格"))
            }
        }
    }

    // MARK: - 底部

    /// 「开始阅读」+ 写一篇（参考图 ④ 的 READ THE ISSUE + 分享键；分享换成写一篇 —— 私密日记不分享）
    private func bottomBar(firstEntry: JournalEntry?, theme: any AppTheme) -> some View {
        HStack(spacing: 12) {
            Button {
                readerDiary = firstEntry
            } label: {
                Text("开始阅读")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(firstEntry == nil ? theme.textTertiary : theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(firstEntry == nil ? theme.border : theme.textPrimary.opacity(0.75), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(firstEntry == nil)

            Button {
                showCompose = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.textPrimary.opacity(0.75), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("写一篇"))
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            theme.background
                .overlay(alignment: .top) { Rectangle().fill(theme.border).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - 空本子

    private func emptyState(theme: any AppTheme) -> some View {
        VStack(spacing: 14) {
            Text("这本还是空的")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textTertiary)
            Button {
                showCompose = true
            } label: {
                Text("写下第一篇")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: - 「…」里的动作

    private func commitRename() {
        guard let tag else { return }
        do {
            switch try tag.rename(to: renameText, in: modelContext) {
            case .renamed:
                save()
            case .unchanged:
                break
            case .nameTaken:
                // 撞名要说出来 —— 以前是静默不保存，用户只看到「改了没反应」
                env.errors.present(
                    NSLocalizedString("已有同名的日记本", bundle: .appLanguage, comment: "日记本重名"),
                    kind: .info
                )
            }
        } catch {
            let ns = error as NSError
            NSLog("❌ [BookDetail] 重命名读取失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            env.errors.present(error, fallback: NSLocalizedString("保存失败", bundle: .appLanguage, comment: "通用保存失败"))
        }
    }

    /// 先退回书架，再删。
    ///
    /// 反过来的话，这一页在退场动画里还会读 `tag.name`，读一个已经删掉的 SwiftData 对象会直接崩。
    private func deleteNotebook() {
        guard let tag else { return }
        let context = modelContext
        let errors = env.errors
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            // 照片封面和它的云端副本一起删，不然成了没人认领的文件，还白占用户的 iCloud
            NotebookCoverStore.remove(tag.coverPhotoFilename, in: context)
            context.delete(tag)
            do {
                try context.save()
            } catch {
                let ns = error as NSError
                NSLog("❌ [BookDetail] 删除日记本保存失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
                errors.present(error, fallback: NSLocalizedString("保存失败", bundle: .appLanguage, comment: "通用保存失败"))
            }
        }
    }

    /// 写库失败要让用户知道（`AppEnvironment.errors`），不能 `try?` 吞掉
    private func save() {
        do {
            try modelContext.save()
        } catch {
            let ns = error as NSError
            NSLog("❌ [BookDetail] 保存日记本失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            env.errors.present(error, fallback: NSLocalizedString("保存失败", bundle: .appLanguage, comment: "通用保存失败"))
        }
    }
}
