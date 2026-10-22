import UIKit

/// 阅读器的版式尺寸 —— **分页（`Paginator`）和页面视图（`ContentPageView`）共用这一份**。
///
/// 分页是「先算后画」：Paginator 按这里的尺寸估算每页装多少，页面再按同样的尺寸去画。
/// 两边各写一份数字的话，改了一边忘了另一边，一页就会装不下 ——
/// SwiftUI 的 `Text` 放不下时会**静默截断**，读者看到的是一句话说到一半没了下文。
enum ReaderLayout {
    /// 页面左右留白
    static let hInset: CGFloat = 20
    /// 内容顶部距安全区的距离。左上角悬浮的返回按钮占安全区下 8–44pt（见 `DiaryReaderView`），要让开它
    static let topInset: CGFloat = 56
    /// 内容底部距安全区的距离
    static let bottomInset: CGFloat = 30

    /// 正文字号与行距
    static let bodyFontSize: CGFloat = 16
    static let bodyLineSpacing: CGFloat = 8
    /// 相邻内容块之间的间距（与 `ContentBlockRenderer` 的 VStack spacing 一致）
    static let blockSpacing: CGFloat = 12
    /// 正文区顶部的额外留白
    static let bodyTopGap: CGFloat = 6

    /// 续页顶部的小标题（提示当前在读哪一篇）
    static let runningTitleFontSize: CGFloat = 11
    static let runningTitleBottomGap: CGFloat = 10
    /// 首页页眉与正文之间的间距
    static let headerBottomGap: CGFloat = 14

    /// 页脚页码
    static let pageNumberFontSize: CGFloat = 11
    static let pageNumberTopGap: CGFloat = 8

    /// 照片块在页面中的标称高度（相纸样式；与 `ContentBlockRenderer` 的同名常量一致）
    static let photoBlockHeight: CGFloat = 280

    /// 测量与渲染的细微差异（字体回退、舍入）留的余量。宁可页底多一点空白，不能挤掉正文
    static let safetyMargin: CGFloat = 8

    static var bodyFont: UIFont {
        UIFont(name: "Georgia", size: bodyFontSize) ?? .systemFont(ofSize: bodyFontSize)
    }

    /// 小标题（格式见 `StyledText`）：正文大一号的粗体
    static let headingFontSize: CGFloat = 20
    static var headingFont: UIFont {
        UIFont(name: "Georgia-Bold", size: headingFontSize) ?? .boldSystemFont(ofSize: headingFontSize)
    }

    /// 录音卡片的高度（与正文编辑器里的一致）
    static let audioBlockHeight: CGFloat = AudioAnchorAttachment.cardHeight
    /// 痕迹行（取下的照片 / 删去的录音）的高度
    static let traceBlockHeight: CGFloat = TraceAnchorAttachment.lineHeight
}

/// 用 TextKit 按真实字体 + 行距排版来测量文字。
///
/// 折行规则与 SwiftUI `Text` 同源，比「字数 ÷ 每行字数」可靠得多：
/// 中英混排、标点避头尾、手动换行都算得准。
enum TextMeasure {
    private static func attributed(_ text: String, font: UIFont, lineSpacing: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
    }

    /// 带格式的一段字在 `width` 宽度下排完的高度（加粗、小标题的字号不一样，得按真实字体量）
    static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0 else { return 0 }
        let rect = text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(rect.height)
    }

    /// 带格式的一段字在 `width × height` 的框里从头能排下多少字符（UTF-16，退到完整字符边界）
    static func fittingLength(of text: NSAttributedString, width: CGFloat, height: CGFloat) -> Int {
        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: height))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let glyphs = layoutManager.glyphRange(for: container)
        let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var length = NSMaxRange(chars)
        let ns = text.string as NSString
        if length > 0, length < ns.length {
            let composed = ns.rangeOfComposedCharacterSequence(at: length)
            if composed.location < length { length = composed.location }
        }
        return length
    }

    /// `text` 在 `width` 宽度下排完的高度
    static func height(of text: String, font: UIFont, lineSpacing: CGFloat, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let rect = attributed(text, font: font, lineSpacing: lineSpacing).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(rect.height)
    }

    /// 在 `width × height` 的框里从头能排下多少字符（UTF-16 长度，已退到完整字符边界，
    /// 不会把 emoji 之类的组合字符从中间劈开）
    static func fittingLength(of text: String, font: UIFont, lineSpacing: CGFloat,
                              width: CGFloat, height: CGFloat) -> Int {
        let storage = NSTextStorage(attributedString: attributed(text, font: font, lineSpacing: lineSpacing))
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: height))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        let glyphs = layoutManager.glyphRange(for: container)
        let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var length = NSMaxRange(chars)
        let ns = text as NSString
        if length > 0, length < ns.length {
            let composed = ns.rangeOfComposedCharacterSequence(at: length)
            if composed.location < length { length = composed.location }
        }
        return length
    }
}

/// 把一篇日记的内容块按页面可用高度分页。
///
/// **分页规则**：
/// - 第 0 页顶部是页眉（日期 + 标题 + 标签，见 `DiaryPageHeader`），正文紧接在下面，可用高度扣掉页眉
/// - 续页顶部是一行小标题
/// - 文本块：按真实排版测高；放不下就在本页能排下的位置断开，余下的接到下一页
/// - 照片块：不可分割，放不下就连同它前面的文本块（环绕锚点）一起挪到下一页
/// - 正文为空也至少产出一页（只有页眉）
///
/// 拆开的文本块**不复用原 id**（`ContentBlock.id` 是 `let`），每段新生成 UUID。
/// 分页结果是渲染态、不持久化，所以无副作用。
///
/// > 2026-09 之前第一页是单独的「扉页」，只有日期和标题，正文要再翻一页才开始 ——
/// > 读者看到标题孤零零占一页（2026-09-16 实机反馈）。现在页眉并进了正文首页。
final class Paginator {
    static let shared = Paginator()

    private init() {}

    // MARK: - 页面度量

    /// 整页尺寸与安全区，取自当前窗口 —— 阅读器全屏展示，页面就是整个窗口
    private var windowGeometry: (size: CGSize, safeArea: UIEdgeInsets) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else {
            return (CGSize(width: 390, height: 844), UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0))
        }
        return (window.bounds.size, window.safeAreaInsets)
    }

    /// 正文可用宽度。`ContentPageView` 也按它排版（照片宽度按它的比例算），两边必须一致
    var contentWidth: CGFloat {
        max(0, windowGeometry.size.width - ReaderLayout.hInset * 2)
    }

    /// 一页里留给「页眉/小标题 + 正文」的高度：安全区内，扣掉上下留白、页码和正文顶部留白
    private var contentAreaHeight: CGFloat {
        let g = windowGeometry
        let pageNumberFont = UIFont(name: "Georgia", size: ReaderLayout.pageNumberFontSize)
            ?? .systemFont(ofSize: ReaderLayout.pageNumberFontSize)
        return g.size.height - g.safeArea.top - g.safeArea.bottom
            - ReaderLayout.topInset - ReaderLayout.bottomInset
            - ReaderLayout.pageNumberTopGap - pageNumberFont.lineHeight
            - ReaderLayout.bodyTopGap - ReaderLayout.safetyMargin
    }

    // MARK: - 分页主入口

    /// 把一篇日记拆成若干 `.content` 页（至少一页）
    func paginate(diary: JournalEntry) -> [PageData] {
        let width = contentWidth
        let area = contentAreaHeight
        let firstCapacity = max(0, area
            - DiaryPageHeader.estimatedHeight(for: diary, width: width)
            - ReaderLayout.headerBottomGap)
        let fullCapacity = area
            - UIFont.systemFont(ofSize: ReaderLayout.runningTitleFontSize).lineHeight
            - ReaderLayout.runningTitleBottomGap
        let twoLines = (ReaderLayout.bodyFont.lineHeight + ReaderLayout.bodyLineSpacing) * 2

        var pages: [[ContentBlock]] = []
        var current: [ContentBlock] = []
        var used: CGFloat = 0

        /// 当前页的正文容量：第 0 页扣掉页眉，其余是整页
        func capacity() -> CGFloat { pages.isEmpty ? firstCapacity : fullCapacity }
        /// 往当前页再放一个高 `h` 的块，已用高度要加多少（块与块之间有间距）
        func cost(_ h: CGFloat) -> CGFloat { current.isEmpty ? h : h + ReaderLayout.blockSpacing }
        /// 当前页是一张空的续页 —— 再往后挪也不会有更大的地方了
        func onBlankContinuationPage() -> Bool { current.isEmpty && !pages.isEmpty }

        func flush() {
            // 续页不产出空页；第 0 页即使一个块都没放下也要出（它有页眉）
            guard !current.isEmpty || pages.isEmpty else { return }
            pages.append(current)
            current = []
            used = 0
        }

        func place(_ block: ContentBlock) {
            used += cost(height(of: block, width: width))
            current.append(block)
        }

        for block in diary.contentBlocks {
            // 录音、痕迹：一行，不可拆。放不下就挪到下一页
            if block.type == .audio || block.type == .trace {
                if used + cost(height(of: block, width: width)) > capacity() && !onBlankContinuationPage() {
                    flush()
                }
                place(block)
                continue
            }
            if block.type == .photo {
                if used + cost(ReaderLayout.photoBlockHeight) <= capacity() || onBlankContinuationPage() {
                    place(block)
                    continue
                }
                // 放不下：照片要带上紧挨着它的前一个文本块 —— `ContentBlockRenderer` 让照片
                // 环绕在前一段文字旁边，只搬照片的话，到了新页它就成了一张没有文字的孤图。
                // 那段文字本身太长（带上它新页也装不下）就不带了。
                var companion: ContentBlock?
                if let last = current.last, last.type == .text,
                   height(of: last, width: width) + ReaderLayout.blockSpacing
                    + ReaderLayout.photoBlockHeight <= fullCapacity {
                    companion = current.removeLast()
                }
                flush()
                if let companion { place(companion) }
                place(block)
                continue
            }

            // 文本块：放得下就整段放；放不下就在本页能排下的位置断开，余下的接着排
            var rest: ContentBlock? = block
            while let r = rest {
                let h = height(of: r, width: width)
                if used + cost(h) <= capacity() {
                    place(r)
                    rest = nil
                    continue
                }
                let room = capacity() - used - (current.isEmpty ? 0 : ReaderLayout.blockSpacing)
                if room >= twoLines, let parts = split(r, fittingHeight: room, width: width) {
                    place(parts.head)
                    flush()
                    rest = parts.tail
                } else if onBlankContinuationPage() {
                    // 一整页都切不出东西（理论上不会发生）：硬放，保证循环一定前进
                    place(r)
                    rest = nil
                } else {
                    // 本页剩余不足两行：整段挪到下一页
                    flush()
                }
            }
        }
        flush()

        let total = pages.count
        return pages.enumerated().map { index, blocks in
            PageData.content(diary: diary, pageIndex: index, totalPages: total, blocks: blocks)
        }
    }

    // MARK: - 辅助

    /// 一个块的渲染高度（不含块间距）
    private func height(of block: ContentBlock, width: CGFloat) -> CGFloat {
        switch block.type {
        case .photo:
            return ReaderLayout.photoBlockHeight
        case .audio:
            return ReaderLayout.audioBlockHeight
        case .trace:
            return ReaderLayout.traceBlockHeight
        case .text:
            // 空文本块在 SwiftUI 里也占一行
            if (block.text ?? "").isEmpty {
                return TextMeasure.height(of: " ", font: ReaderLayout.bodyFont,
                                          lineSpacing: ReaderLayout.bodyLineSpacing, width: width)
            }
            return TextMeasure.height(of: measuring(block), width: width)
        }
    }

    /// 把文本块在 `height` 高度内能排下的部分切出来。
    /// 切不出（一个字都放不下，或者整段都放得下）返回 nil；余下部分为空时 `tail` 为 nil。
    private func split(_ block: ContentBlock, fittingHeight height: CGFloat,
                       width: CGFloat) -> (head: ContentBlock, tail: ContentBlock?)? {
        let text = block.text ?? ""
        let ns = text as NSString
        let n = TextMeasure.fittingLength(of: measuring(block), width: width, height: height)
        guard n > 0, n < ns.length else { return nil }
        // 正好断在换行处时，续页开头会多出一个空行
        let tailStart = ns.character(at: n) == 0x0A ? n + 1 : n
        let tailText = ns.substring(from: tailStart)
        // 格式跟着拆：前半段裁到断点，后半段整体前移
        var head = ContentBlock(text: ns.substring(to: n))
        head.styles = StyledText.styles(block.styles, before: n)
        guard !tailText.isEmpty else { return (head, nil) }
        var tail = ContentBlock(text: tailText)
        tail.styles = StyledText.styles(block.styles, from: tailStart)
        return (head, tail)
    }

    /// 文本块按阅读器的字体量高度用的富文本（正文 / 粗体 / 斜体 / 小标题字号都对上）
    private func measuring(_ block: ContentBlock) -> NSAttributedString {
        StyledText.measuring(block, body: ReaderLayout.bodyFont, heading: ReaderLayout.headingFont,
                             lineSpacing: ReaderLayout.bodyLineSpacing)
    }
}
