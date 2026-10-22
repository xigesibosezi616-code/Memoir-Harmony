import SwiftUI

/// 日记本「…」→「精装 PDF」：先看自己这本排成书的样子，再导出（2026-10-21 产品定，会员专属）。
///
/// 免费用户能完整地翻预览（封面、扉页、目录、正文开头几页，用的是自己的日记和照片），点导出才弹付费页 ——
/// 「先让用户用自己的照片看到效果，再问要不要」（`Docs/MEMBERSHIP.md` 原则 4）。
///
/// 1. 备料：宋体还没有就先下载（带进度；下不到退回苹方，照样能导出），读照片尺寸，排版
/// 2. 预览 + 选排法（每篇另起一页 / 接着上一篇排，记住上次选的）+ 一共多少页、大概多大
/// 3. 导出：一页页画进 PDF（进度条，能取消）→ 分享、存储或打印
struct BookExportView: View {
    let tag: Tag
    /// 已按阅读顺序（从早到晚）
    let entries: [JournalEntry]

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppEnvironment.self) private var env
    @Environment(StoreKitManager.self) private var store

    @AppStorage("bookExportFlow") private var flowRaw = BookPaginator.Flow.pagePerEntry.rawValue
    @State private var stage: Stage = .preparing(fontProgress: nil)
    @State private var info: BookInfo?
    @State private var catalog = BookFigureCatalog()
    @State private var pages: [BookPage] = []
    @State private var previews: [Preview] = []
    /// 宋体没下成，这次用苹方排的
    @State private var usingFallbackFont = false
    @State private var showPaywall = false
    @State private var exportTask: Task<Void, Never>?
    /// 「怎么打印这本日记」小弹窗；第一次导出完成时自动弹一次，之后点主按钮下面的链接看
    @State private var showPrintTips = false
    @AppStorage("bookPrintTipsSeen") private var printTipsSeen = false

    private enum Stage: Equatable {
        /// 备料中；`fontProgress` 非 nil 表示在下宋体
        case preparing(fontProgress: Double?)
        case ready
        case exporting(Double)
        case done(URL, bytes: Int)
    }

    private struct Preview: Identifiable {
        let id: Int
        let image: UIImage
    }

    private var flow: BookPaginator.Flow {
        BookPaginator.Flow(rawValue: flowRaw) ?? .pagePerEntry
    }

    var body: some View {
        let theme = themeManager.current
        NavigationStack {
            VStack(spacing: 0) {
                previewStrip(theme: theme)
                    .frame(maxHeight: .infinity)
                controls(theme: theme)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("精装 PDF")
                        .font(theme.labelFont)
                        .tracking(theme.letterSpacingWide)
                        .foregroundStyle(theme.textSecondary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    CircleIconButton(systemName: "xmark", prominence: .glass, theme: theme, size: 13) {
                        exportTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task { await prepare() }
        .onChange(of: flowRaw) { _, _ in
            Task { await layout() }
        }
        .onDisappear { exportTask?.cancel() }
        .paywallCover(isPresented: $showPaywall)
        .sheet(isPresented: $showPrintTips) {
            BookPrintTipsView(theme: themeManager.current)
        }
    }

    // MARK: - 预览

    @ViewBuilder
    private func previewStrip(theme: any AppTheme) -> some View {
        if previews.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                if case .preparing(let fontProgress?) = stage {
                    Text("正在下载宋体 \(Int(fontProgress * 100))%")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                } else {
                    Text("正在排版…")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geo in
                // 一页 A5 竖着放：最宽占屏幕的 78%，让右边露出下一页的一条边（看得出能往左翻）；矮的屏幕按高度收
                let ratio = BookLayout.pageSize.width / BookLayout.pageSize.height
                let width = min(geo.size.width * 0.78, max(140, geo.size.height - 48) * ratio)
                let height = width / ratio
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 18) {
                        ForEach(previews) { preview in
                            Image(uiImage: preview.image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: width, height: height)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
                                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, (geo.size.width - width) / 2)
                    .padding(.vertical, 24)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - 下面的选项和按钮

    @ViewBuilder
    private func controls(theme: any AppTheme) -> some View {
        VStack(spacing: 14) {
            // 先把要选的事说清楚，下面两段就是回答（2026-10-22 用户提）
            Text("有的日记写不满一页。下一篇是另起一页，还是接着往下排？")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Picker("排法", selection: $flowRaw) {
                Text("每篇另起一页").tag(BookPaginator.Flow.pagePerEntry.rawValue)
                Text("接着上一篇排").tag(BookPaginator.Flow.continuous.rawValue)
            }
            .pickerStyle(.segmented)
            .disabled(!isIdle)

            if !pages.isEmpty {
                Text("共 \(pages.count) 页 · 约 \(Self.format(bytes: BookExporter.estimatedBytes(figureCount: catalog.singles.count, pageCount: pages.count)))")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            }
            if usingFallbackFont {
                Text("宋体没能下载，这次先用苹方排版。联网后再导出就是宋体。")
                    .font(theme.labelFont)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
            }

            switch stage {
            case .preparing:
                primaryButton(Text("导出 PDF"), theme: theme) {}
                    .disabled(true)
            case .ready:
                if store.isMember {
                    primaryButton(Text("导出 PDF"), theme: theme) { startExport() }
                } else {
                    primaryButton(Text("开通尺素会员，导出这本日记"), theme: theme) { showPaywall = true }
                }
            case .exporting(let progress):
                VStack(spacing: 10) {
                    ProgressView(value: progress)
                        .tint(theme.accent)
                    HStack {
                        Text("正在导出 \(Int(progress * 100))%")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Button("取消") { exportTask?.cancel() }
                            .font(theme.captionFont)
                            .foregroundStyle(theme.accent)
                    }
                }
                .frame(height: 50)
            case .done(let url, let bytes):
                ShareLink(item: url) {
                    Label("分享、存储或打印（\(Self.format(bytes: bytes))）", systemImage: "square.and.arrow.up")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.cardBackground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(theme.accent, in: Capsule())
                }
            }

            // 这本书是什么规格、该怎么印：随时能点开看（导出过程中不显示）
            if !isExporting {
                Button { showPrintTips = true } label: {
                    Label("怎么打印这本日记", systemImage: "printer")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var isExporting: Bool {
        if case .exporting = stage { return true }
        return false
    }

    private var isIdle: Bool {
        switch stage {
        case .ready, .done: return true
        case .preparing, .exporting: return false
        }
    }

    private func primaryButton(_ label: Text, theme: any AppTheme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(theme.bodyFont)
                .foregroundStyle(theme.cardBackground)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 备料、排版、导出

    private func prepare() async {
        if BookFonts.needsDownload {
            stage = .preparing(fontProgress: 0)
            let ready = await BookFonts.prepare { value in
                Task { @MainActor in
                    if case .preparing = stage { stage = .preparing(fontProgress: value) }
                }
            }
            usingFallbackFont = !ready
        }
        stage = .preparing(fontProgress: nil)
        info = await BookExporter.info(tag: tag, entries: entries, author: env.session.user?.displayName)
        catalog = await BookExporter.figures(for: entries)
        await layout()
    }

    /// 按选的排法排一遍，预览前几页：封面、扉页、目录第一页、正文开头两页
    private func layout() async {
        guard let info else { return }
        pages = BookPaginator(flow: flow).paginate(entries: entries, catalog: catalog)
        var wanted: [Int] = []
        if let title = pages.firstIndex(where: { if case .titlePage = $0 { return true } else { return false } }) {
            wanted.append(0)
            wanted.append(title)
        }
        if let contents = pages.firstIndex(where: { if case .contents = $0 { return true } else { return false } }) {
            wanted.append(contents)
        }
        if let body = pages.firstIndex(where: { if case .body = $0 { return true } else { return false } }) {
            wanted.append(contentsOf: [body, body + 1].filter { $0 < pages.count })
        }
        var images: [Preview] = []
        for index in wanted {
            if let image = await BookExporter.image(of: pages[index], index: index, info: info, scale: 2) {
                images.append(Preview(id: index, image: image))
            }
        }
        previews = images
        if case .preparing = stage { stage = .ready }
    }

    private func startExport() {
        guard let info, !pages.isEmpty else { return }
        let url = Self.exportURL(title: info.title)
        let pages = pages
        stage = .exporting(0)
        exportTask = Task {
            do {
                try? FileManager.default.removeItem(at: url)
                try await BookExporter.renderPDF(pages: pages, info: info, to: url) { progress in
                    stage = .exporting(progress)
                }
                let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                stage = .done(url, bytes: bytes)
                // 第一次导出完：先告诉一声这本书怎么印（之后不再自动弹）
                if !printTipsSeen {
                    printTipsSeen = true
                    showPrintTips = true
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: url)
                stage = .ready
            } catch {
                try? FileManager.default.removeItem(at: url)
                let ns = error as NSError
                NSLog("❌ [BookExport] 导出失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
                env.errors.present(error, fallback: NSLocalizedString("导出失败", bundle: .appLanguage, comment: "精装 PDF 导出失败"))
                stage = .ready
            }
        }
    }

    /// 导出到临时目录，文件名就是书名（分享出去别人看到的名字）
    private static func exportURL(title: String) -> URL {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BookExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent((safe.isEmpty ? "Memoir" : safe) + ".pdf")
    }

    private static func format(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
