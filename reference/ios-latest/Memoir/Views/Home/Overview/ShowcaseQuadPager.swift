import SwiftUI

/// 大屏捏小一级：一屏 4 篇，一页 2 × 2，**还是左右翻页**（2026-10-21 用户定：4 篇时左右翻，16 篇起才上下滚）。
///
/// 和一屏一篇的大卡片同一种翻法（横向分页、懒加载，只建眼前这一两页）；每格是缩小了的大卡片（`OverviewCell`）。
/// 翻到哪页记在 `HomeView` 给的 `pages.quad` 里（这一页第一篇的 id），捏合时它按手指落在哪一格算是哪篇
struct ShowcaseQuadPager: View {
    /// 新的在前
    let entries: [JournalEntry]
    /// 翻到的那一页（`pages.quad`，这一页第一篇的 id）。`@Observable`：翻页只重画这一块，不重画首页
    @Bindable var pages: ShowcasePages
    /// 换一屏放几篇（读屏的动作用）：换到哪一级、以哪篇为准
    let onZoom: (ShowcaseZoom?, UUID) -> Void
    let onOpen: (UUID) -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// 两格之间的空隙
    static let gap: CGFloat = 12

    private struct Page: Identifiable {
        let id: UUID
        let digests: [EntryDigest]
    }

    /// 每 4 篇一页（文字都是 `EntryDigest` 里算好的）
    private var quadPages: [Page] {
        stride(from: 0, to: entries.count, by: 4).map { start in
            let digests = entries[start..<min(start + 4, entries.count)].map { EntryDigest.of($0) }
            return Page(id: digests[0].id, digests: digests)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let cell = CGSize(
                width: max(0, (geo.size.width - ShowcaseZoom.margin * 2 - Self.gap) / 2),
                height: max(0, (geo.size.height - 16 - Self.gap) / 2)
            )
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(quadPages) { page in
                        VStack(spacing: Self.gap) {
                            HStack(spacing: Self.gap) {
                                slot(page.digests, 0, cell)
                                slot(page.digests, 1, cell)
                            }
                            HStack(spacing: Self.gap) {
                                slot(page.digests, 2, cell)
                                slot(page.digests, 3, cell)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pages.quad)
            // 外面整页的上下滚动锁着（`HomeView`），锁是往下传的：这里自己放开，左右照样翻
            .scrollDisabled(false)
            .scrollIndicators(.hidden)
        }
        .onChange(of: pages.quad, initial: true) { _, id in prefetch(around: id) }
    }

    @ViewBuilder
    private func slot(_ digests: [EntryDigest], _ index: Int, _ size: CGSize) -> some View {
        if index < digests.count {
            let digest = digests[index]
            let cell = OverviewCell(digest: digest, zoom: .four, size: size)
                .contentShape(.rect)
                .onTapGesture { onOpen(digest.id) }
                .accessibilityAction { onOpen(digest.id) }
            // 换级的读屏动作只在旁白开着时挂（同 `ShowcaseOverview`）
            if voiceOver {
                cell
                    .accessibilityAction(named: Text("一屏看更多篇")) { onZoom(ShowcaseZoom.four.zoomedOut, digest.id) }
                    .accessibilityAction(named: Text("一屏看更少篇")) { onZoom(ShowcaseZoom.four.zoomedIn, digest.id) }
            } else {
                cell
            }
        } else {
            // 最后一页不满四篇：空着，别让剩下的格子挪位置
            Color.clear.frame(width: size.width, height: size.height)
        }
    }

    /// 左右各一页的照片先在后台解出来，翻过去就有
    private func prefetch(around id: UUID?) {
        guard !entries.isEmpty else { return }
        let index = id.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        let range = max(0, index - 4)...min(entries.count - 1, index + 7)
        let names = range.compactMap { EntryDigest.of(entries[$0]).cover }
        EntryPhotoStore.prefetch(names, pixels: OverviewCell.pixels(.four))
    }

    /// `entry` 在第几页：那一页第一篇的 id
    static func pageID(containing entry: UUID?, in entries: [JournalEntry]) -> UUID? {
        guard let entry, let index = entries.firstIndex(where: { $0.id == entry }) else { return entries.first?.id }
        return entries[index / 4 * 4].id
    }

    /// 手指落在这一页的哪一格（0 左上、1 右上、2 左下、3 右下）是哪篇
    static func entry(at point: CGPoint, pagerFrame: CGRect, page: UUID?, in entries: [JournalEntry]) -> UUID? {
        guard let start = page.flatMap({ id in entries.firstIndex { $0.id == id } }) ?? (entries.isEmpty ? nil : 0) else { return nil }
        let slot = (point.x > pagerFrame.midX ? 1 : 0) + (point.y > pagerFrame.midY ? 2 : 0)
        return entries[min(start + slot, entries.count - 1)].id
    }

    /// `entry` 在它那一页的哪一格的中心（按页面的比例）：从这一格缩放进出
    static func slotAnchor(of entry: UUID?, in entries: [JournalEntry]) -> UnitPoint {
        guard let entry, let index = entries.firstIndex(where: { $0.id == entry }) else { return .center }
        let slot = index % 4
        return UnitPoint(x: slot % 2 == 0 ? 0.27 : 0.73, y: slot < 2 ? 0.27 : 0.73)
    }
}
