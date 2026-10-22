import SwiftUI
import UIKit

/// 把文本块的格式（`ContentBlock.styles`）交给 SwiftUI `Text` / 测量用的 `NSAttributedString`。
///
/// 给**翻页阅读器**和**大屏卡片**用 —— 它们还是 SwiftUI `Text` 排版（阅读器保持原样，2026-10 产品定），
/// 写日记页、编辑页、详情页用的是 `RichTextView`。
///
/// - 加粗、斜体走 `inlinePresentationIntent`：`Text` 会按它自己的字体加粗 / 变斜，字号跟着调用处走
/// - 小标题在 `Text` 里没法单独设行距，只换成大一号的粗体（`heading(_:)` 由调用方给）
enum StyledText {

    /// 一个文本块 → 带格式的 `AttributedString`。小标题先用 `presentationIntent` 标着，渲染时再换字体；
    /// 荧光笔用 `highlight` 色做底
    static func attributed(_ block: ContentBlock, highlight: Color, laterInk: Color? = nil, base: Date? = nil,
                           textColor: Color = .primary) -> AttributedString {
        attributed(text: block.text ?? "", styles: block.styles, highlight: highlight, laterInk: laterInk, base: base,
                   textColor: textColor)
    }

    /// `laterInk` / `base`：补记换墨色、划掉的字加删除线（见 `Ink`）。不传就不分
    static func attributed(text: String, styles: [TextStyleRun]?, highlight: Color,
                           laterInk: Color? = nil, base: Date? = nil, textColor: Color = .primary) -> AttributedString {
        let ns = NSMutableAttributedString(string: text)
        for run in styles ?? [] {
            let range = NSRange(location: run.location, length: run.length)
            guard range.location >= 0, range.length > 0, NSMaxRange(range) <= ns.length else { continue }
            if run.bold == true { ns.addAttribute(.memoirBold, value: true, range: range) }
            if run.italic == true { ns.addAttribute(.memoirItalic, value: true, range: range) }
            if run.heading == true { ns.addAttribute(.memoirHeading, value: true, range: range) }
            if run.highlight == true { ns.addAttribute(.memoirHighlight, value: true, range: range) }
            if let written = run.writtenAt { ns.addAttribute(.memoirWrittenAt, value: NSNumber(value: written), range: range) }
            if let struck = run.struckAt { ns.addAttribute(.memoirStruckAt, value: NSNumber(value: struck), range: range) }
        }
        var result = AttributedString(ns.string)
        ns.enumerateAttributes(in: NSRange(location: 0, length: ns.length)) { attributes, range, _ in
            guard let swiftRange = Range(range, in: ns.string),
                  let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
                  let upper = AttributedString.Index(swiftRange.upperBound, within: result) else { return }
            var intent: InlinePresentationIntent = []
            if attributes[.memoirBold] as? Bool == true { intent.insert(.stronglyEmphasized) }
            if attributes[.memoirItalic] as? Bool == true { intent.insert(.emphasized) }
            if !intent.isEmpty { result[lower..<upper].inlinePresentationIntent = intent }
            if attributes[.memoirHeading] as? Bool == true {
                result[lower..<upper].presentationIntent = PresentationIntent(.header(level: 1), identity: 1)
            }
            if attributes[.memoirHighlight] as? Bool == true {
                result[lower..<upper].backgroundColor = highlight
            }
            let written = (attributes[.memoirWrittenAt] as? NSNumber)?.doubleValue
            if let laterInk, Ink.isAddendum(writtenAt: written, base: base) {
                result[lower..<upper].foregroundColor = laterInk
            }
            if attributes[.memoirStruckAt] != nil {
                result[lower..<upper].strikethroughStyle = .single
                // 划掉的字变淡（字还看得清 —— 划掉不是抹掉）
                let ink = Ink.isAddendum(writtenAt: written, base: base) ? laterInk : nil
                result[lower..<upper].foregroundColor = (ink ?? textColor).opacity(0.42)
            }
        }
        return result
    }

    /// 渲染前把小标题那几段换成 `heading` 字体
    static func applyingHeading(_ text: AttributedString, font heading: Font) -> AttributedString {
        var text = text
        for run in text.runs where run.presentationIntent != nil {
            text[run.range].font = heading
        }
        return text
    }

    /// 测量用：和 `Text` 渲染时同一套字体（正文 / 粗体 / 斜体 / 小标题），行距统一
    static func measuring(_ block: ContentBlock, body: UIFont, heading: UIFont, lineSpacing: CGFloat) -> NSAttributedString {
        let text = block.text ?? ""
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let result = NSMutableAttributedString(string: text, attributes: [.font: body, .paragraphStyle: paragraph])
        for run in block.styles ?? [] {
            let range = NSRange(location: run.location, length: run.length)
            guard range.location >= 0, range.length > 0, NSMaxRange(range) <= result.length else { continue }
            var font = run.heading == true ? heading : body
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.bold == true || run.heading == true { traits.insert(.traitBold) }
            if run.italic == true { traits.insert(.traitItalic) }
            if !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: font.pointSize)
            }
            result.addAttribute(.font, value: font, range: range)
        }
        return result
    }

    // MARK: - 拆块时格式跟着走

    /// 文本块在 `cut`（UTF-16）处断开，前半段的格式
    static func styles(_ styles: [TextStyleRun]?, before cut: Int) -> [TextStyleRun]? {
        let clipped: [TextStyleRun] = (styles ?? []).compactMap { run in
            let end = min(run.location + run.length, cut)
            guard run.location < cut, end > run.location else { return nil }
            var r = run
            r.length = end - run.location
            return r
        }
        return clipped.isEmpty ? nil : clipped
    }

    /// 后半段（从 `start` 开始）的格式，位置改成相对后半段开头
    static func styles(_ styles: [TextStyleRun]?, from start: Int) -> [TextStyleRun]? {
        let shifted: [TextStyleRun] = (styles ?? []).compactMap { run in
            let begin = max(run.location, start)
            let end = run.location + run.length
            guard end > begin else { return nil }
            var r = run
            r.location = begin - start
            r.length = end - begin
            return r
        }
        return shifted.isEmpty ? nil : shifted
    }
}
