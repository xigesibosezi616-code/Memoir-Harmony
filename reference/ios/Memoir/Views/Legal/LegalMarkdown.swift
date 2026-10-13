import SwiftUI

/// 法律文档用的极简 Markdown 解析。
///
/// **为什么自己写而不是用 `AttributedString(markdown:)`**：
/// 那个 API 只能把整段文字变成一个 `AttributedString`，标题和正文最终是同一个
/// `Text`，没法按主题给标题单独的字号与间距；`inlineOnlyPreservingWhitespace`
/// 之外的块级选项在 SwiftUI 里也渲染不出层次。
///
/// 只支持这几种写法 —— 两份法律文档全部照此书写，**翻译时不要引入其他语法**：
/// `# 标题` / `## 小节` / `### 子节` / 普通段落 / `- 列表项` / 行内 `**加粗**`。
///
/// ⚠️ **顺序要紧**：判断前缀时 `###` 必须排在 `##` 前面，否则三级标题会被
/// 当成二级标题匹配掉，剩下一个 `# ` 留在正文里。
enum LegalMarkdown {

    enum Block: Identifiable {
        case title(String)
        case heading(String)
        case subheading(String)
        case paragraph(AttributedString)
        case bullet(AttributedString)

        var id: String {
            switch self {
            case .title(let s):     return "t\(s)"
            case .heading(let s):   return "h\(s)"
            case .subheading(let s): return "s\(s)"
            case .paragraph(let s): return "p\(s.description)"
            case .bullet(let s):    return "b\(s.description)"
            }
        }
    }

    static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        // 段落可能跨行（md 里用换行排版但语义上是一段），遇到空行才收束
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ")
            blocks.append(.paragraph(inline(joined)))
            paragraphBuffer.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.subheading(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bullet(inline(String(line.dropFirst(2)))))
            } else {
                paragraphBuffer.append(line)
            }
        }
        flushParagraph()
        return blocks
    }

    /// 行内样式：只处理 `**加粗**`。
    ///
    /// 交给系统的 markdown 解析器做，失败就退回纯文本 ——
    /// 法律文本宁可少个加粗，也不能因为一个语法问题整段消失。
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
