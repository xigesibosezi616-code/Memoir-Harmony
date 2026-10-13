import Foundation
import Combine

/// 翻页阅读的数据源：把一组日记展平为连续 `[PageData]` 数组。
///
/// 不直接从 SwiftData 取数 —— 调用方（持有 `@Query` 的 View）传入已过滤好的 `entries`，
/// 这样 PageDataSource 既无 ModelContext 依赖，又能轻松适配"全部日记 / 某个标签"两种入口。
@MainActor
final class PageDataSource: ObservableObject {
    /// 当前日记本内所有页面（展平后的连续翻页数组）
    @Published private(set) var allPages: [PageData] = []

    /// 当前显示的页面索引。只在 `PageCurlReaderView.makeUIViewController` 定初始页时读。
    ///
    /// ⚠️ **刻意不是 `@Published`**：翻页完成后 Coordinator 会回写它，若它会发布变化，
    /// 每翻一页整个阅读器的 SwiftUI 树就重算一次、`updateUIViewController` 被调一次 ——
    /// 而这时用户的下一次翻页手势可能已经开始了。快速来回翻时，SwiftUI 的更新与
    /// `UIPageViewController` 的翻页转场交错进行，正是这类容器最容易出内部状态错乱的时机。
    /// 没有任何视图需要随它刷新，所以不发布。
    var currentIndex: Int = 0

    /// 接受已过滤的日记列表（自动按阅读顺序排好，见 `readingOrder`）+ 跳转目标。
    init(entries: [JournalEntry], initialDiary: JournalEntry) {
        rebuild(from: entries, initialDiary: initialDiary)
    }

    /// 调试用：仅传 entries 时，跳到第一篇的首页
    init(entries: [JournalEntry]) {
        if let first = Self.readingOrder(entries).first {
            rebuild(from: entries, initialDiary: first)
        }
    }

    /// **阅读顺序：从早到晚**（2026-10-08 产品决定）—— 像读一本书，往后翻越来越新，
    /// 日记本主页目录里的第 1 篇就是最早的那篇。
    ///
    /// 按日记的**日期**排（用户写的是哪天），同一天再按创建时间。
    /// 以前是按创建时间从新到旧：补写的旧日子会排错位置，而且和列表的顺序也对不上。
    static func readingOrder(_ entries: [JournalEntry]) -> [JournalEntry] {
        entries.sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    private func rebuild(from entries: [JournalEntry], initialDiary: JournalEntry) {
        let diaries = Self.readingOrder(entries)
        var pages: [PageData] = []
        for diary in diaries {
            pages.append(contentsOf: Paginator.shared.paginate(diary: diary))
        }
        // 整本最后一篇（最新的那篇）末尾追加 ending 页
        if let last = diaries.last {
            pages.append(.ending(diary: last, hasNextDiary: false))
        }
        self.allPages = pages

        // 跳到初始日记的首页（带页眉的第 0 页）
        if let firstPageIndex = pages.firstIndex(where: {
            if case .content(let d, 0, _, _) = $0, d.id == initialDiary.id { return true }
            return false
        }) {
            self.currentIndex = firstPageIndex
        }
    }

    // MARK: - 翻页协议（供 UIPageViewController DataSource 用）

    func nextPage(after page: PageData) -> PageData? {
        guard let i = allPages.firstIndex(of: page), i + 1 < allPages.count else { return nil }
        return allPages[i + 1]
    }

    func previousPage(before page: PageData) -> PageData? {
        guard let i = allPages.firstIndex(of: page), i - 1 >= 0 else { return nil }
        return allPages[i - 1]
    }

    func indexOf(page: PageData) -> Int? {
        allPages.firstIndex(of: page)
    }
}
