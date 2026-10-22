import Foundation

/// 翻页阅读的单页数据 —— 整个 UIPageViewController 数据源的最小单位。
///
/// 两种页面：
/// - `.content`：正文页。**每篇日记的第 0 页顶部带页眉**（日期 + 标题 + 心情印章 + 标签），
///   正文紧接在页眉下面；之后的续页顶部只有一行小标题
/// - `.ending`：末页（"已读完所有日记"提示）
///
/// > 2026-09 之前还有第三种 `.cover`（扉页）：日期和标题单独占一整页，正文从下一页才开始。
/// > 读者翻开一篇日记先看到一张只有标题的空页（2026-09-16 实机反馈），已并入正文首页。
enum PageData: Identifiable, Equatable {
    case content(
        diary: JournalEntry,
        pageIndex: Int,        // 这篇日记的第几页（0 起算；第 0 页带页眉）
        totalPages: Int,       // 这篇日记总共几页
        blocks: [ContentBlock] // 这一页要渲染的正文块
    )
    case ending(
        diary: JournalEntry,
        hasNextDiary: Bool
    )

    var id: String {
        switch self {
        case .content(let diary, let pageIndex, _, _):
            return "content-\(diary.id.uuidString)-\(pageIndex)"
        case .ending(let diary, _):
            return "ending-\(diary.id.uuidString)"
        }
    }

    static func == (lhs: PageData, rhs: PageData) -> Bool {
        lhs.id == rhs.id
    }

    /// 调试用：简短文字描述
    var debugDescription: String {
        switch self {
        case .content(let diary, let pageIndex, let totalPages, let blocks):
            let blockSummary = blocks.map { block -> String in
                if block.type == .photo { return "📷" }
                let t = block.text ?? ""
                let preview = t.count > 16 ? String(t.prefix(16)) + "…" : t
                return "“\(preview)”"
            }.joined(separator: " ")
            let header = pageIndex == 0 ? "📖 \(diary.title.isEmpty ? "(无标题)" : diary.title) · " : ""
            return "📄 \(header)\(pageIndex + 1)/\(totalPages) · \(blockSummary)"
        case .ending(let diary, _):
            return "🔚 末页 · \(diary.title.isEmpty ? "(无标题)" : diary.title)"
        }
    }
}
