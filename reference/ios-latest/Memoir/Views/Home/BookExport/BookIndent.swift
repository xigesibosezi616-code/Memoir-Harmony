import Foundation

/// 书里的段首缩进（2026-10-21 产品定）：**用户自己在段首空了格的，原样不动；没空的，按这段字的语言补上**。
///
/// | 这段字 | 缩进 |
/// |---|---|
/// | 中文 | 两个全角空格（中文书的规矩） |
/// | 日文（有假名的段，或 App 选日文时的纯汉字段） | 一个全角空格（日本書籍の字下げ） |
/// | 韩文 | 一个全角空格 |
/// | 英文 | 一个 em 空格；**一篇的第一段不缩**（英文书的规矩：标题下第一段顶格） |
/// | 法文、西文（App 选法文 / 西文时的拉丁字母段） | 一个 em 空格，第一段也缩 |
///
/// 按**这一段写的是什么字**定，不按下载地区：在马来西亚下载、写中文的人，书里该是中文的样子。
/// SwiftUI 的 `Text` 没有首行缩进，所以直接在段首插空格字符 —— 量高度和画出来用的是同一串字，对得上；
/// 插了字，后面的格式（加粗、荧光笔……）位置跟着往后挪。小标题段不缩
enum BookIndent {
    private enum Script {
        case chinese, japanese, korean, latin, other
    }

    /// 给一个文字块的每一段补上缩进。`isFirstBlockOfEntry`：这是一篇的第一个文字块（英文的第一段不缩）
    static func apply(_ block: ContentBlock, isFirstBlockOfEntry: Bool) -> ContentBlock {
        guard let text = block.text, !text.isEmpty else { return block }
        let ns = text as NSString
        let styles = block.styles ?? []

        // 每一段的开头位置（UTF-16）
        var starts: [Int] = [0]
        for i in 0..<ns.length where ns.character(at: i) == 0x0A && i + 1 < ns.length {
            starts.append(i + 1)
        }

        var insertions: [(at: Int, indent: String)] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] - 1 : ns.length
            guard end > start else { continue }   // 空段
            let paragraph = ns.substring(with: NSRange(location: start, length: end - start))
            guard let first = paragraph.unicodeScalars.first, !Self.isSpace(first) else { continue }   // 用户自己空了格
            if styles.contains(where: { $0.heading == true && $0.location <= start && start < $0.location + $0.length }) {
                continue   // 小标题
            }
            guard let indent = indent(for: paragraph, firstOfEntry: isFirstBlockOfEntry && index == 0) else { continue }
            insertions.append((start, indent))
        }
        guard !insertions.isEmpty else { return block }

        // 从后往前插，前面的位置不受影响；格式按插入的长度往后挪
        let result = NSMutableString(string: text)
        var runs = styles
        for insertion in insertions.reversed() {
            let length = (insertion.indent as NSString).length
            result.insert(insertion.indent, at: insertion.at)
            for i in runs.indices {
                if runs[i].location >= insertion.at {
                    runs[i].location += length
                } else if runs[i].location + runs[i].length > insertion.at {
                    runs[i].length += length
                }
            }
        }
        var indented = ContentBlock(text: result as String)
        indented.styles = runs.isEmpty ? nil : runs
        return indented
    }

    private static func indent(for paragraph: String, firstOfEntry: Bool) -> String? {
        switch script(of: paragraph) {
        case .chinese: return "\u{3000}\u{3000}"
        case .japanese, .korean: return "\u{3000}"
        case .latin:
            let language = appLocale.language.languageCode?.identifier ?? "en"
            let indentsFirst = language == "fr" || language == "es"
            if firstOfEntry && !indentsFirst { return nil }
            return "\u{2003}"
        case .other: return nil
        }
    }

    /// 这一段是什么字：有假名就是日文，有谚文就是韩文，有汉字就是中文（App 选日文时算日文），否则看有没有拉丁字母
    private static func script(of paragraph: String) -> Script {
        var hasHan = false
        var hasLatin = false
        for scalar in paragraph.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: return .japanese
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: return .korean
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x20000...0x2FA1F: hasHan = true
            default:
                if scalar.properties.isAlphabetic, scalar.isASCII || (0x00C0...0x024F).contains(scalar.value) {
                    hasLatin = true
                }
            }
        }
        if hasHan {
            return appLocale.language.languageCode?.identifier == "ja" ? .japanese : .chinese
        }
        return hasLatin ? .latin : .other
    }

    /// 段首是不是已经空了格（半角、全角、制表、各种宽度的空格）
    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || scalar.value == 0x3000
    }
}
