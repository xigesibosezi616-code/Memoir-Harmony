import SwiftUI
import UIKit

// MARK: - 一本书里有什么

/// 封面、扉页、版权页要用的这本书的信息
struct BookInfo {
    let title: String
    /// 用户写的副标题；没写是 nil
    let subtitle: String?
    /// 「2026年3月 — 2026年10月」
    let dateRange: String
    /// 作者（昵称）；没登录 / 没昵称是 nil
    let author: String?
    let color: BookColor
    /// 封面照片（已经解好）；nil = 布面
    let coverPhoto: UIImage?
    let coverLayout: CoverLayout
    /// 封面照片的主色（书架上这本书的书脊色）；没有照片是 nil
    let photoTint: Color?
    let entryCount: Int
    let photoCount: Int
    let exportedAt: Date
}

/// 正文里的一张照片：排版只要知道它多大（读文件头就有，不用解图），图到画那一页时才解（`BookExporter`）
struct BookFigure {
    let block: ContentBlock
    /// 照片文件名（Live Photo 是未裁的静态图，和正文里相纸的比例一致）
    let source: String
    /// 宽 / 高（已按拍摄方向转正）
    let aspect: CGFloat
    /// 单独一张时排在版心里多大（含相纸）
    let size: CGSize
}

/// 正文里的一排照片：单独一张（居中），或同一篇里挨着的两张并排（2026-10-22 产品定）。
///
/// 并排的两张相纸一样高：靠**等比**缩放 —— 长的那张（手机截图这种）变窄，照片从不拉伸、不硬塞
struct BookFigureRow {
    let figures: [BookFigure]
    /// 每张（连相纸）排多宽
    let widths: [CGFloat]
    /// 原尺寸时这一排多高
    let height: CGFloat
    /// 页底放不下、整排等比缩小塞进去的比例（1 = 原尺寸）
    var scale: CGFloat = 1

    init(single figure: BookFigure) {
        figures = [figure]
        widths = [figure.size.width]
        height = figure.size.height
    }

    init(pair first: BookFigure, _ second: BookFigure, widths: [CGFloat], height: CGFloat) {
        figures = [first, second]
        self.widths = widths
        self.height = height
    }

    /// 排出来实际占多高
    var scaledHeight: CGFloat { ceil(height * scale) }
    /// 原尺寸时整排多宽（并排时含中间的空）
    var width: CGFloat { widths.reduce(0, +) + BookLayout.pairGap * CGFloat(max(widths.count - 1, 0)) }
}

/// 排版要用的照片尺寸，`BookExporter.figures(for:)` 读文件头量好（排版不解图）
struct BookFigureCatalog {
    /// 单张怎么放，按照片块的 id（同一个文件在两处用了不同的相纸，各是各的）
    var singles: [UUID: BookFigure] = [:]
    /// 挨着的两张并排怎么放；不在表里 = 这两张不并排（等比下来有一张太窄）
    var pairs: [Pair: BookFigureRow] = [:]

    struct Pair: Hashable {
        let first: UUID
        let second: UUID
    }
}

/// 篇首：日期、标题、心情
struct BookEntryHeader {
    let date: String
    let title: String?
    let mood: MoodLevel?
    /// 接着排时和上一篇之间空出来的那一段（另起一页时是 0）
    let topGap: CGFloat
}

/// 正文一页里的一样东西
enum BookItem {
    case header(BookEntryHeader)
    /// 一段字（可能是被分页切开的半段）；`writtenAt` 用来分补记的墨色（同阅读器）
    case text(ContentBlock, writtenAt: Date)
    case figures(BookFigureRow)
    /// 录音：纸上放不了，记一笔
    case audio
    /// 篇末的地点、天气
    case place(String)
}

/// 正文的一页
struct BookBodyPage {
    var items: [BookItem]
    /// 页码（正文第一页是 1）
    var folio: Int
    /// 右页页眉：这一页开头那篇是哪个月
    var month: String
}

/// 目录里的一行
enum BookContentsLine {
    case month(String)
    case entry(day: String, title: String?, folio: Int)
}

/// 书的一页（从封面到封底）
enum BookPage {
    case cover
    case titlePage
    case contents([BookContentsLine], first: Bool)
    case body(BookBodyPage)
    case colophon
    case backCover
}

// MARK: - 排版

/// 把一本日记本排成书：先排正文（知道每篇从第几页开始），再按页码排目录，最后前后加上封面、扉页、版权页。
///
/// 正文的切法和阅读器的 `Paginator` 同一个思路（段落放不下就在能排下的地方切开，余下的接着排），
/// 只是纸是 A5、字是宋体，尺寸全取 `BookLayout`。
///
/// 照片（2026-10-22 产品定）：同一篇里挨着的两张并排成一排；一排放不下这一页剩下的地方时，
/// 剩下的够原尺寸六成就整排等比缩小塞进去，不够才挪到下一页 —— 不再一张图独占大半页、页底空一大块
@MainActor
struct BookPaginator {
    /// 每篇另起一页，还是接着上一篇排（2026-10-21 产品定：导出时让用户选）
    enum Flow: String, CaseIterable {
        case pagePerEntry
        case continuous
    }

    let flow: Flow

    private var width: CGFloat { BookLayout.textWidth }
    private var capacity: CGFloat { BookLayout.textHeight - BookLayout.safetyMargin }

    /// 排一整本：`entries` 已按阅读顺序（从早到晚），照片尺寸在 `catalog` 里
    func paginate(entries: [JournalEntry], catalog: BookFigureCatalog) -> [BookPage] {
        let body = paginateBody(entries: entries, catalog: catalog)
        let contents = contentsPages(entries: entries, body: body)

        // 不要冗余的页（2026-10-23 用户定）：去掉封面后、封底前那两张纯色环衬；
        // 正文直接接在目录后面，不为「从右页开始」再插空白页
        var pages: [BookPage] = [.cover, .titlePage]
        pages += contents.enumerated().map { .contents($0.element, first: $0.offset == 0) }
        pages += body.map { .body($0) }
        pages.append(.colophon)
        pages.append(.backCover)
        return pages
    }

    // MARK: 正文

    /// 正文排成一页页。`folio` 从 1 起
    func paginateBody(entries: [JournalEntry], catalog: BookFigureCatalog) -> [BookBodyPage] {
        var pages: [BookBodyPage] = []
        var current: [BookItem] = []
        /// `current` 里每样东西各占了多高（含和上一样之间的间距）：挪页时要把最后一样撤下来
        var costs: [CGFloat] = []
        var used: CGFloat = 0
        var month = ""

        func flush() {
            guard !current.isEmpty else { return }
            pages.append(BookBodyPage(items: current, folio: pages.count + 1, month: month))
            current = []
            costs = []
            used = 0
        }
        /// 往这一页再放一个高 `h` 的东西，要多占多高（和上一个之间有间距）
        func cost(_ h: CGFloat) -> CGFloat { current.isEmpty ? h : h + BookLayout.blockGap }
        func place(_ item: BookItem, height h: CGFloat) {
            let c = cost(h)
            used += c
            costs.append(c)
            current.append(item)
        }
        /// 把这一页最后放的那样东西撤下来
        func popLast() -> BookItem? {
            guard let item = current.popLast(), let c = costs.popLast() else { return nil }
            used -= c
            return item
        }
        func startPageIfNeeded(for entryMonth: String) {
            if current.isEmpty { month = entryMonth }
        }

        let lineHeight = BookFonts.body(BookLayout.bodySize).lineHeight + BookLayout.bodyLineSpacing

        /// 放一排照片：这一页剩下的地方放不下时，够原尺寸的六成就整排等比缩小塞进去（2026-10-22 用户定），不够才挪到下一页。
        ///
        /// 挪页时别让照片一个人占一页（用户：「一张图放一页不好」）：
        /// - 篇首就在它前面：篇首一起挪，不然标题孤零零留在页底
        /// - 它是这篇最后一样东西、下一页也不会再接这篇的字（每篇另起一页，或这是最后一篇）：
        ///   把前面那段的最后三行一起带过去（那段不长就整段带走）
        func placeRow(_ row: BookFigureRow, month entryMonth: String, endsEntry: Bool, lastEntry: Bool) {
            var row = row
            if used + cost(row.height) > capacity, !current.isEmpty {
                let room = capacity - used - BookLayout.blockGap
                if room >= row.height * BookLayout.figureMinScale {
                    row.scale = floor(room) / row.height
                } else {
                    var carried: [(item: BookItem, height: CGFloat)] = []
                    if current.count > 1, case .header(let header) = current.last {
                        _ = popLast()
                        let moved = BookEntryHeader(date: header.date, title: header.title, mood: header.mood, topGap: 0)
                        carried.append((.header(moved), Self.height(of: moved)))
                    } else if endsEntry, flow == .pagePerEntry || lastEntry, current.count > 1,
                              case .text(let block, let writtenAt) = current.last {
                        _ = popLast()
                        let h = textHeight(block)
                        if h >= lineHeight * 5, let parts = split(block, fittingHeight: h - lineHeight * 3), let tail = parts.tail {
                            place(.text(parts.head, writtenAt: writtenAt), height: textHeight(parts.head))
                            carried.append((.text(tail, writtenAt: writtenAt), textHeight(tail)))
                        } else {
                            carried.append((.text(block, writtenAt: writtenAt), h))
                        }
                    }
                    flush()
                    startPageIfNeeded(for: entryMonth)
                    for (item, height) in carried { place(item, height: height) }
                }
            }
            place(.figures(row), height: row.scaledHeight)
        }

        for (entryIndex, entry) in entries.enumerated() {
            let entryMonth = BookContents.monthTitle(entry.date)
            // 篇首
            if flow == .pagePerEntry {
                flush()
            }
            var gap: CGFloat = 0
            if flow == .continuous, !current.isEmpty {
                gap = BookLayout.entryGap
            }
            var header = makeHeader(entry, topGap: gap)
            var headerHeight = Self.height(of: header)
            // 篇首后面至少要跟得上三行字，不然把篇首挪到下一页
            if !current.isEmpty, used + cost(headerHeight) + lineHeight * 3 > capacity {
                flush()
                header = makeHeader(entry, topGap: 0)
                headerHeight = Self.height(of: header)
            }
            startPageIfNeeded(for: entryMonth)
            place(.header(header), height: headerHeight)

            var isFirstText = true
            let blocks = entry.contentBlocks
            var index = 0
            while index < blocks.count {
                let original = blocks[index]
                index += 1
                // 段首缩进（用户自己空了格的不动），见 `BookIndent`
                var block = original
                if original.type == .text {
                    block = BookIndent.apply(original, isFirstBlockOfEntry: isFirstText)
                    if !(original.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { isFirstText = false }
                }
                switch block.type {
                case .photo:
                    guard let figure = catalog.singles[original.id] else { continue }
                    var row = BookFigureRow(single: figure)
                    // 下一个看得见的块也是照片、两张能并排 → 这两张一排
                    var next = index
                    while next < blocks.count, Self.isInvisible(blocks[next]) { next += 1 }
                    if next < blocks.count, blocks[next].type == .photo,
                       let pair = catalog.pairs[.init(first: original.id, second: blocks[next].id)] {
                        row = pair
                        index = next + 1
                    }
                    // 这一排后面这篇还有没有看得见的东西（字、照片、录音）
                    let endsEntry = !blocks[index...].contains { !Self.isInvisible($0) }
                    placeRow(row, month: entryMonth, endsEntry: endsEntry, lastEntry: entryIndex == entries.count - 1)

                case .audio:
                    let h = Self.audioHeight
                    if used + cost(h) > capacity { flush(); startPageIfNeeded(for: entryMonth) }
                    place(.audio, height: h)

                case .trace:
                    // 取下的照片 / 删去的录音留下的痕迹：书里不印
                    continue

                case .text:
                    guard !(block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    var rest: ContentBlock? = block
                    while let r = rest {
                        let h = textHeight(r)
                        if used + cost(h) <= capacity {
                            place(.text(r, writtenAt: entry.createdAt), height: h)
                            rest = nil
                            continue
                        }
                        let room = capacity - used - (current.isEmpty ? 0 : BookLayout.blockGap)
                        if room >= lineHeight * 2, let parts = split(r, fittingHeight: room) {
                            place(.text(parts.head, writtenAt: entry.createdAt), height: room)
                            flush()
                            startPageIfNeeded(for: entryMonth)
                            rest = parts.tail
                        } else if current.isEmpty {
                            // 一整页都切不出东西（理论上不会发生）：硬放，保证往前走
                            place(.text(r, writtenAt: entry.createdAt), height: h)
                            rest = nil
                        } else {
                            flush()
                            startPageIfNeeded(for: entryMonth)
                        }
                    }
                }
            }

            // 篇末：地点、天气
            if let line = Self.placeLine(entry) {
                let h = Self.placeHeight
                if used + cost(h) > capacity { flush(); startPageIfNeeded(for: entryMonth) }
                place(.place(line), height: h)
            }
        }
        flush()
        return pages
    }

    // MARK: 目录

    /// 目录按月分组，每篇一行：几号、标题、页码。第一页顶上有「目录」两个字
    private func contentsPages(entries: [JournalEntry], body: [BookBodyPage]) -> [[BookContentsLine]] {
        // 每篇从第几页开始：正文里篇首出现在哪一页
        var startFolio: [Int] = []
        for page in body {
            for item in page.items {
                if case .header = item { startFolio.append(page.folio) }
            }
        }
        var lines: [BookContentsLine] = []
        var lastMonth = ""
        for (index, entry) in entries.enumerated() {
            let month = BookContents.monthTitle(entry.date)
            if month != lastMonth {
                lines.append(.month(month))
                lastMonth = month
            }
            let folio = index < startFolio.count ? startFolio[index] : (startFolio.last ?? 1)
            lines.append(.entry(day: BookContents.dayTitle(entry.date), title: BookContents.title(of: entry), folio: folio))
        }

        var pages: [[BookContentsLine]] = []
        var current: [BookContentsLine] = []
        var used: CGFloat = BookContents.headingHeight
        let room = BookLayout.textHeight
        for line in lines {
            let h = BookContents.height(of: line)
            // 月份标题不要落在页底、下面一篇都没跟上
            let needs = { if case .month = line { return h + BookContents.entryLineHeight } else { return h } }()
            if used + needs > room, !current.isEmpty {
                pages.append(current)
                current = []
                used = 0
            }
            current.append(line)
            used += h
        }
        if !current.isEmpty || pages.isEmpty { pages.append(current) }
        return pages
    }

    // MARK: 量

    private func makeHeader(_ entry: JournalEntry, topGap: CGFloat) -> BookEntryHeader {
        BookEntryHeader(
            date: BookContents.headerDate(entry.date),
            title: BookContents.title(of: entry),
            mood: entry.moodLevel,
            topGap: topGap
        )
    }

    /// 篇首多高：和 `BookPageView` 里画的一一对应
    static func height(of header: BookEntryHeader) -> CGFloat {
        var h = header.topGap
        h += BookFonts.body(BookLayout.dateSize).lineHeight
        if let title = header.title {
            h += Self.titleSpacing
            h += TextMeasure.height(of: title, font: BookFonts.body(BookLayout.titleSize, bold: true),
                                    lineSpacing: Self.titleLineSpacing, width: BookLayout.textWidth)
        }
        if header.mood != nil {
            h += Self.moodSpacing + BookFonts.body(BookLayout.moodSize).lineHeight
        }
        h += Self.ruleSpacing + Self.ruleHeight + BookLayout.headerBottomGap
        return ceil(h)
    }

    static let titleSpacing: CGFloat = 6
    static let titleLineSpacing: CGFloat = 4
    static let moodSpacing: CGFloat = 4
    static let ruleSpacing: CGFloat = 10
    static let ruleHeight: CGFloat = 0.6
    static var audioHeight: CGFloat { ceil(BookFonts.body(8.5).lineHeight) }
    static var placeHeight: CGFloat { ceil(BookFonts.body(8).lineHeight) + 4 }

    /// 篇末那一行：地点 · 天气
    static func placeLine(_ entry: JournalEntry) -> String? {
        let parts = [entry.locationInfo, entry.weatherInfo]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 印出来看不见的块：取下照片 / 删去录音留下的痕迹、空段落。判断两张照片「挨着」时跳过它们
    static func isInvisible(_ block: ContentBlock) -> Bool {
        switch block.type {
        case .trace: return true
        case .text: return (block.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return false
        }
    }

    /// 一篇里挨着的两张照片（中间只隔着看不见的块），前后依次两两相邻：并排的候选。
    /// 备料（量并排多大）和排版（实际两两成排）都按这个认「挨着」，两边才对得上
    static func adjacentPhotoPairs(in blocks: [ContentBlock]) -> [(first: ContentBlock, second: ContentBlock)] {
        let visible = blocks.filter { !isInvisible($0) }
        guard visible.count >= 2 else { return [] }
        var pairs: [(first: ContentBlock, second: ContentBlock)] = []
        for i in 0..<(visible.count - 1) where visible[i].type == .photo && visible[i + 1].type == .photo {
            pairs.append((visible[i], visible[i + 1]))
        }
        return pairs
    }

    /// 一段字排出来多高（宋体、正文字号、小标题字号都对上）
    private func textHeight(_ block: ContentBlock) -> CGFloat {
        TextMeasure.height(of: measuring(block), width: width)
    }

    private func measuring(_ block: ContentBlock) -> NSAttributedString {
        StyledText.measuring(block, body: BookFonts.body(BookLayout.bodySize),
                             heading: BookFonts.body(BookLayout.headingSize, bold: true),
                             lineSpacing: BookLayout.bodyLineSpacing)
    }

    /// 在 `height` 高度内能排下的部分切出来（同 `Paginator.split`：格式跟着拆，断在换行处时下半段去掉开头的换行）
    private func split(_ block: ContentBlock, fittingHeight height: CGFloat) -> (head: ContentBlock, tail: ContentBlock?)? {
        let ns = (block.text ?? "") as NSString
        let n = TextMeasure.fittingLength(of: measuring(block), width: width, height: height)
        guard n > 0, n < ns.length else { return nil }
        let tailStart = ns.character(at: n) == 0x0A ? n + 1 : n
        let tailText = ns.substring(from: tailStart)
        var head = ContentBlock(text: ns.substring(to: n))
        head.styles = StyledText.styles(block.styles, before: n)
        guard !tailText.isEmpty else { return (head, nil) }
        var tail = ContentBlock(text: tailText)
        tail.styles = StyledText.styles(block.styles, from: tailStart)
        return (head, tail)
    }
}

// MARK: - 文字

/// 书里的几种写法（跟着 App 语言）
enum BookContents {
    /// 「2026年10月」/「October 2026」
    static func monthTitle(_ date: Date) -> String {
        date.yearMonthKey(locale: appLocale)
    }

    /// 目录里的「19日」/「19」
    static func dayTitle(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: appLocale).day())
    }

    /// 篇首的日期：「2026年10月19日 星期一」/「Monday, October 19, 2026」
    static func headerDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: appLocale).year().month(.wide).day().weekday(.wide))
    }

    /// 标题；没写标题用正文第一行；都空是 nil
    static func title(of entry: JournalEntry) -> String? {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let first = entry.textPreview.split(whereSeparator: \.isNewline).first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return first.isEmpty ? nil : String(first.prefix(30))
    }

    // 目录的尺寸（`BookPageView` 照这个画）
    static let headingHeight: CGFloat = 58
    static let monthLineHeight: CGFloat = 30
    static let entryLineHeight: CGFloat = 19

    static func height(of line: BookContentsLine) -> CGFloat {
        switch line {
        case .month: return monthLineHeight
        case .entry: return entryLineHeight
        }
    }
}
