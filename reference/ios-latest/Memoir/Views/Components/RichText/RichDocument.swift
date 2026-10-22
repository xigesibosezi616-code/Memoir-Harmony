import UIKit
import SwiftUI

// MARK: - 富文本里的自定义属性

extension NSAttributedString.Key {
    /// 加粗（语义）。字体由 `RichTextStyle` 按语义推出来，存盘只认这几个语义属性
    static let memoirBold = NSAttributedString.Key("memoir.bold")
    /// 斜体（语义）
    static let memoirItalic = NSAttributedString.Key("memoir.italic")
    /// 小标题（语义，整段）
    static let memoirHeading = NSAttributedString.Key("memoir.heading")
    /// 荧光笔（语义）。画法见 `HighlighterLayoutManager`
    static let memoirHighlight = NSAttributedString.Key("memoir.highlight")
    /// 这段字什么时候写的（`NSNumber`，Unix 秒）。没有 = 日记写下时就有（见 `Ink`）
    static let memoirWrittenAt = NSAttributedString.Key("memoir.writtenAt")
    /// 这段字什么时候划掉的（`NSNumber`，Unix 秒）
    static let memoirStruckAt = NSAttributedString.Key("memoir.struckAt")
    /// 整段补记上方要画的小字（「补记 · 10月12日」），挂在段首那个字上。由 `RichTextView` 排完字后算出来
    static let memoirAddendumLabel = NSAttributedString.Key("memoir.addendumLabel")
    /// 上面那行小字的颜色
    static let memoirAddendumLabelColor = NSAttributedString.Key("memoir.addendumLabelColor")
}

/// 一段文字带哪几种格式。富文本里存成上面几个语义属性，存盘时变成 `TextStyleRun`
struct TextFlags: Equatable {
    var bold = false
    var italic = false
    var heading = false
    var highlight = false
    /// 什么时候写的（Unix 秒），nil = 日记写下时就有
    var writtenAt: Double?
    /// 什么时候划掉的（Unix 秒），nil = 没划掉
    var struckAt: Double?

    init(bold: Bool = false, italic: Bool = false, heading: Bool = false, highlight: Bool = false,
         writtenAt: Double? = nil, struckAt: Double? = nil) {
        self.bold = bold
        self.italic = italic
        self.heading = heading
        self.highlight = highlight
        self.writtenAt = writtenAt
        self.struckAt = struckAt
    }

    init(attributes: [NSAttributedString.Key: Any]) {
        bold = attributes[.memoirBold] as? Bool == true
        italic = attributes[.memoirItalic] as? Bool == true
        heading = attributes[.memoirHeading] as? Bool == true
        highlight = attributes[.memoirHighlight] as? Bool == true
        writtenAt = (attributes[.memoirWrittenAt] as? NSNumber)?.doubleValue
        struckAt = (attributes[.memoirStruckAt] as? NSNumber)?.doubleValue
    }

    init(run: TextStyleRun) {
        bold = run.bold == true
        italic = run.italic == true
        heading = run.heading == true
        highlight = run.highlight == true
        writtenAt = run.writtenAt
        struckAt = run.struckAt
    }

    var isPlain: Bool { !bold && !italic && !heading && !highlight && writtenAt == nil && struckAt == nil }
}

/// 照片在正文里的锚点：一个看不见、不占宽度的附件字符。
///
/// 照片本身不在文字流里，而是浮在锚点所在那一行的左边或右边，文字用排除区域绕开它（见 `RichTextView`）。
/// 锚点只记照片块的 id，照片的其他信息在 `RichTextView.photos` 里。
final class PhotoAnchorAttachment: NSTextAttachment {
    let blockID: UUID

    init(blockID: UUID) {
        self.blockID = blockID
        super.init(data: nil, ofType: nil)
        // 不占位、不画东西：照片由浮在上面的视图画
        bounds = .zero
        image = UIImage()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 痕迹（取下的照片 / 删去的录音）在正文里的锚点：自成一行的一行小字，由 `RichTextView` 盖一个标签上去
final class TraceAnchorAttachment: NSTextAttachment {
    let blockID: UUID
    static let lineHeight: CGFloat = 22

    init(blockID: UUID, width: CGFloat) {
        self.blockID = blockID
        super.init(data: nil, ofType: nil)
        image = UIImage()
        setWidth(width)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setWidth(_ width: CGFloat) {
        bounds = CGRect(x: 0, y: 0, width: max(1, width - 1), height: Self.lineHeight)
    }
}

/// 录音在正文里的锚点：自己占一整行（宽 = 正文宽，高 = 录音卡片高），里面不画东西，
/// 录音卡片由浮在上面的视图画（见 `RichTextView`）。
///
/// 和照片不同，录音不让文字绕排 —— 它就是正文里的一行，上下文字照常排
final class AudioAnchorAttachment: NSTextAttachment {
    let blockID: UUID
    /// 录音卡片的高度（`AudioPlayerCard`：内边距 12 × 2 + 播放键 36）
    static let cardHeight: CGFloat = 60

    init(blockID: UUID, width: CGFloat) {
        self.blockID = blockID
        super.init(data: nil, ofType: nil)
        image = UIImage()
        setWidth(width)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 正文宽度变了要跟着改，否则卡片占的地方和画出来的对不上。
    ///
    /// 卡片底边就压在基线上（y = 0）。曾经往下沉 10 想多留点底，结果 TextKit 把那 10 加在了行的上方，
    /// 卡片上面空一大截、下面贴着下一段（2026-10-10 量过：基线离行顶 60，卡片顶却在 +10 处）。
    /// 现在上方是上一段的行距 + 段距，下方是这一行的下伸 + 行距 + 段距，两边差不多
    func setWidth(_ width: CGFloat) {
        bounds = CGRect(x: 0, y: 0, width: max(1, width - 1), height: Self.cardHeight)
    }
}

// MARK: - 正文的字体、颜色、行距

/// 正文排版。编辑页和详情页用同一份 —— 写的时候看到的就是最后的样子
struct RichTextStyle {
    var bodyFont: UIFont = UIFont(name: "Georgia", size: 17) ?? .systemFont(ofSize: 17)
    var headingFont: UIFont = UIFont(name: "Georgia-Bold", size: 21) ?? .boldSystemFont(ofSize: 21)
    var textColor: UIColor = .label
    var lineSpacing: CGFloat = 10
    /// 荧光笔的颜色（按主题，见 `RichTextAppearance`）
    var highlightColor: UIColor = UIColor(red: 0.96, green: 0.84, blue: 0.43, alpha: 0.6)
    /// 日记写下的时刻（见 `Ink`）。nil = 还在写的新日记，没有补记、也不会干
    var baseDate: Date?
    /// 补记的墨色：像隔几天换了一支笔再写
    var laterInkColor: UIColor = UIColor(red: 0.29, green: 0.36, blue: 0.47, alpha: 1)
    /// 「补记 · 某月某日」这类小字的颜色
    var labelColor: UIColor = .secondaryLabel

    /// 按语义算出一段文字的全部属性
    func attributes(_ flags: TextFlags) -> [NSAttributedString.Key: Any] {
        let bold = flags.bold, italic = flags.italic, heading = flags.heading
        var font = heading ? headingFont : bodyFont
        if bold && !heading, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
            font = UIFont(descriptor: descriptor, size: font.pointSize)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = heading ? 4 : lineSpacing
        paragraph.paragraphSpacingBefore = heading ? 8 : 0
        // 段与段之间留半行，读起来不挤
        paragraph.paragraphSpacing = heading ? 4 : 8

        // 补记换一种墨色；划掉的字变淡，加一道线（字还看得清 —— 划掉不是抹掉）
        var ink = Ink.isAddendum(writtenAt: flags.writtenAt, base: baseDate) ? laterInkColor : textColor
        if flags.struckAt != nil { ink = ink.withAlphaComponent(0.42) }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
        ]
        if let writtenAt = flags.writtenAt { attributes[.memoirWrittenAt] = NSNumber(value: writtenAt) }
        if let struckAt = flags.struckAt {
            attributes[.memoirStruckAt] = NSNumber(value: struckAt)
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = ink
        }
        // 中文字体没有斜体字形，用倾斜代替 —— 中英文斜得一样
        if italic { attributes[.obliqueness] = 0.18 }
        if bold { attributes[.memoirBold] = true }
        if italic { attributes[.memoirItalic] = true }
        if heading { attributes[.memoirHeading] = true }
        if flags.highlight {
            attributes[.memoirHighlight] = true
            // 背景色只是让 TextKit 来调 `fillBackgroundRectArray`，真正怎么画由 `HighlighterLayoutManager` 决定
            attributes[.backgroundColor] = highlightColor
        }
        return attributes
    }

    var plainAttributes: [NSAttributedString.Key: Any] {
        attributes(TextFlags())
    }
}

// MARK: - 每套主题的正文外观

/// 正文长什么样（字号、行距、颜色）。**写日记页、编辑页、详情页用同一份** —— 写的时候看到的就是最后的样子。
///
/// - 素笺：和纸排版，17 号字（2026-10-10 图文编辑器原型定）
/// - 皮革、肯特、极夜：跟主题正文字号（14 号），保持这几套主题原来的阅读观感
struct RichTextAppearance: Equatable {
    var fontSize: CGFloat
    var lineSpacing: CGFloat
    var textColor: Color
    /// 荧光笔：素笺、肯特是浅色纸上的黄色记号笔；皮革是深色页面，换成压得住浅色字的琥珀色；极夜是黑底，用深蓝
    var highlightColor: Color
    /// 补记的墨色（见 `Ink`）：浅色纸上是蓝黑墨水，皮革深色页面上是浅灰蓝
    var laterInkColor: Color
    /// 「补记 · 某月某日」这类小字
    var labelColor: Color

    static func forTheme(id: String, theme: any AppTheme) -> RichTextAppearance {
        switch id {
        case "bamboo":
            return RichTextAppearance(fontSize: 17, lineSpacing: 10, textColor: theme.textPrimary,
                                      highlightColor: Color(hex: "#F4D46A").opacity(0.6),
                                      laterInkColor: Color(hex: "#3E5470"), labelColor: theme.textTertiary)
        case "leather":
            return RichTextAppearance(fontSize: 14, lineSpacing: 8, textColor: theme.textPrimary,
                                      highlightColor: Color(hex: "#B8862B").opacity(0.55),
                                      laterInkColor: Color(hex: "#A9B9CC"), labelColor: theme.textTertiary)
        case "polar":
            // 黑底上浅色字：荧光笔换成压得住浅色字的深蓝，补记墨色是浅灰蓝（和皮革一样的道理）
            return RichTextAppearance(fontSize: 14, lineSpacing: 8, textColor: theme.textPrimary,
                                      highlightColor: Color(hex: "#3D5A80").opacity(0.6),
                                      laterInkColor: Color(hex: "#A9B9CC"), labelColor: theme.textTertiary)
        default:
            return RichTextAppearance(fontSize: 14, lineSpacing: 8, textColor: theme.textPrimary,
                                      highlightColor: Color(hex: "#FFE15A").opacity(0.7),
                                      laterInkColor: Color(hex: "#34507A"), labelColor: theme.textTertiary)
        }
    }

    var style: RichTextStyle {
        RichTextStyle(
            bodyFont: UIFont(name: "Georgia", size: fontSize) ?? .systemFont(ofSize: fontSize),
            headingFont: UIFont(name: "Georgia-Bold", size: (fontSize * 1.25).rounded()) ?? .boldSystemFont(ofSize: fontSize * 1.25),
            textColor: UIColor(textColor),
            lineSpacing: lineSpacing,
            highlightColor: UIColor(highlightColor),
            laterInkColor: UIColor(laterInkColor),
            labelColor: UIColor(labelColor)
        )
    }

    /// 占位提示（「今天，我想说...」）要和正文同一个字号，才落在光标的位置
    var bodyFont: Font { .custom("Georgia", size: fontSize) }
}

// MARK: - 内容块 ↔ 富文本

/// 日记正文在两种形态之间转换：
/// - 存盘：`[ContentBlock]`（文本块 + 照片块 + 录音块，文本块带 `styles`）
/// - 编辑 / 排版：一整段富文本，照片和录音是其中的锚点字符
///
/// **规则**：
/// - 相邻的两个文本块是两段（中间补一个换行）
/// - 照片锚点放在它后面那段文字的开头；拆回去时，照片前那个换行是拼接时补的，去掉
/// - 录音锚点**自成一段**：前后各一个换行。拆回去时它前后那两个换行都是补的，去掉
enum RichDocument {
    static let anchorCharacter: unichar = 0xFFFC

    /// `width`：正文宽度，录音锚点按它占满一行（不知道时传 0，排版时会再更新）
    static func attributedString(from blocks: [ContentBlock], style: RichTextStyle, width: CGFloat = 0) -> NSAttributedString {
        let result = NSMutableAttributedString()

        func endsWithNewline() -> Bool {
            result.length > 0 && (result.string as NSString).character(at: result.length - 1) == 0x0A
        }

        for block in blocks {
            switch block.type {
            case .text:
                let text = block.text ?? ""
                // 两个文本块之间是分段；照片后面紧跟的文字和锚点同一段，不补
                if result.length > 0, !endsWithNewline(), !endsWithPhotoAnchor(result), !text.isEmpty {
                    result.append(NSAttributedString(string: "\n", attributes: style.plainAttributes))
                }
                let segment = NSMutableAttributedString(string: text, attributes: style.plainAttributes)
                for run in block.styles ?? [] {
                    let range = NSRange(location: run.location, length: run.length)
                    guard range.location >= 0, NSMaxRange(range) <= segment.length, range.length > 0 else { continue }
                    segment.setAttributes(style.attributes(TextFlags(run: run)), range: range)
                }
                result.append(segment)

            case .photo:
                if result.length > 0, !endsWithNewline() {
                    result.append(NSAttributedString(string: "\n", attributes: style.plainAttributes))
                }
                var attributes = style.plainAttributes
                attributes[.attachment] = PhotoAnchorAttachment(blockID: block.id)
                result.append(NSAttributedString(string: String(utf16CodeUnits: [anchorCharacter], count: 1),
                                                 attributes: attributes))

            case .audio, .trace:
                if result.length > 0, !endsWithNewline() {
                    result.append(NSAttributedString(string: "\n", attributes: style.plainAttributes))
                }
                var attributes = style.plainAttributes
                attributes[.attachment] = block.type == .audio
                    ? AudioAnchorAttachment(blockID: block.id, width: width)
                    : TraceAnchorAttachment(blockID: block.id, width: width)
                result.append(NSAttributedString(string: String(utf16CodeUnits: [anchorCharacter], count: 1),
                                                 attributes: attributes))
                // 录音自成一段：后面总跟一个换行，录音下面永远有一行能接着写
                result.append(NSAttributedString(string: "\n", attributes: style.plainAttributes))
            }
        }
        return result
    }

    /// 富文本拆回内容块。`anchored` 是照片块、录音块的本体（按 id 找）；找不到的锚点丢掉
    static func blocks(from text: NSAttributedString, anchored: [UUID: ContentBlock]) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let string = text.string as NSString
        var segmentStart = 0

        func flushText(upTo end: Int, beforeAnchor: Bool) {
            guard end > segmentStart else { return }
            var range = NSRange(location: segmentStart, length: end - segmentStart)
            // 照片 / 录音前那个换行是拼接时补的
            if beforeAnchor, range.length > 0, string.character(at: NSMaxRange(range) - 1) == 0x0A {
                range.length -= 1
            }
            guard range.length > 0 else { return }
            var block = ContentBlock(text: string.substring(with: range))
            block.styles = styleRuns(in: text, range: range)
            blocks.append(block)
        }

        for index in 0..<string.length where string.character(at: index) == anchorCharacter {
            let attachment = text.attribute(.attachment, at: index, effectiveRange: nil)
            let id = (attachment as? PhotoAnchorAttachment)?.blockID
                ?? (attachment as? AudioAnchorAttachment)?.blockID
                ?? (attachment as? TraceAnchorAttachment)?.blockID
            guard index >= segmentStart, let id, let block = anchored[id] else { continue }
            flushText(upTo: index, beforeAnchor: true)
            blocks.append(block)
            segmentStart = index + 1
            // 录音 / 痕迹后面那个换行也是补的
            if attachment is AudioAnchorAttachment || attachment is TraceAnchorAttachment, segmentStart < string.length,
               string.character(at: segmentStart) == 0x0A {
                segmentStart += 1
            }
        }
        flushText(upTo: string.length, beforeAnchor: false)

        // 空文档也保留一个空文本块（写日记页靠它判断「还没写」）
        if blocks.isEmpty { blocks = [ContentBlock(text: "")] }
        return blocks
    }

    /// 一段文字里的格式区间（相对于这段的开头，UTF-16）
    private static func styleRuns(in text: NSAttributedString, range: NSRange) -> [TextStyleRun]? {
        var runs: [TextStyleRun] = []
        text.enumerateAttributes(in: range) { attributes, subrange, _ in
            let flags = TextFlags(attributes: attributes)
            guard !flags.isPlain else { return }
            let location = subrange.location - range.location
            // 相邻且格式相同的合并成一段
            if var last = runs.last, last.location + last.length == location, TextFlags(run: last) == flags {
                last.length += subrange.length
                runs[runs.count - 1] = last
            } else {
                runs.append(TextStyleRun(location: location, length: subrange.length,
                                         bold: flags.bold ? true : nil, italic: flags.italic ? true : nil,
                                         heading: flags.heading ? true : nil, highlight: flags.highlight ? true : nil,
                                         writtenAt: flags.writtenAt, struckAt: flags.struckAt))
            }
        }
        return runs.isEmpty ? nil : runs
    }

    private static func endsWithPhotoAnchor(_ text: NSAttributedString) -> Bool {
        text.length > 0 && text.attribute(.attachment, at: text.length - 1, effectiveRange: nil) is PhotoAnchorAttachment
    }
}

// MARK: - 荧光笔的画法

/// 让荧光笔像真的记号笔划过：只盖住字的中下部、两头略圆、半透明，而不是一整块填满行高的色块。
///
/// TextKit 1 的背景色默认填满整个行片段（连行距一起），段落一密就连成一大片。
/// 这里拿到每一行要填的横向范围后，按那一行的基线和字号重新算竖向范围。
/// 只接管带 `.memoirHighlight` 的那几段，其他背景色照旧。
///
/// 顺带画补记段落上方的小字（「补记 · 10月12日」，见 `.memoirAddendumLabel`）：
/// 那一段的段前距已经留出了这块地方，字不在正文里，所以不能被选中、删改
final class HighlighterLayoutManager: NSLayoutManager {
    /// 补记小字的字号
    static let labelFontSize: CGFloat = 11
    /// 补记段落多留的段前距（放小字）
    static let labelSpace: CGFloat = 22

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, storage.length > 0 else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.memoirAddendumLabel, in: chars) { value, range, _ in
            guard let label = value as? String else { return }
            let glyph = glyphIndexForCharacter(at: range.location)
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let color = (storage.attribute(.memoirAddendumLabelColor, at: range.location, effectiveRange: nil) as? UIColor)
                ?? .secondaryLabel
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: Self.labelFontSize),
                .foregroundColor: color,
                .kern: 1,
            ]
            (label as NSString).draw(at: CGPoint(x: origin.x + line.minX, y: origin.y + line.minY + 2),
                                     withAttributes: attributes)
        }
    }

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<CGRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: UIColor) {
        guard let storage = textStorage, charRange.location < storage.length,
              storage.attribute(.memoirHighlight, at: charRange.location, effectiveRange: nil) as? Bool == true,
              let container = textContainers.first,
              let context = UIGraphicsGetCurrentContext() else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }
        context.saveGState()
        color.setFill()
        for i in 0..<rectCount {
            let rect = rectArray[i]
            guard rect.width > 0.5 else { continue }
            // 这一行的基线：在这一行中间取一个字，问它的行片段和字形位置
            let probe = CGPoint(x: rect.midX, y: rect.midY)
            let glyph = glyphIndex(for: probe, in: container)
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = line.minY + location(forGlyphAt: glyph).y
            let charIndex = characterIndexForGlyph(at: glyph)
            let font = (storage.attribute(.font, at: min(charIndex, storage.length - 1), effectiveRange: nil) as? UIFont)
                ?? UIFont.systemFont(ofSize: 17)
            let size = font.pointSize
            // 盖住字身的中下部：中文方块字从基线往上约 0.88em，记号笔压在下面六成多
            let marker = CGRect(x: rect.minX - 1, y: baseline - size * 0.62,
                                width: rect.width + 2, height: size * 0.78)
            UIBezierPath(roundedRect: marker, cornerRadius: size * 0.16).fill()
        }
        context.restoreGState()
    }
}
