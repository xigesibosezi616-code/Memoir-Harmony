import SwiftUI

/// 大屏捏到一屏 16 / 64 篇时的总览：上下滚，按月分组，新的在上（和列表模式一样）。点一格打开那篇。
///
/// 一屏 4 篇是左右翻页（`ShowcaseQuadPager`），从 16 篇起才上下滚（2026-10-21 用户定）。级别见 `ShowcaseZoom`，捏合在 `HomeView`。
///
/// 🔴 **为了不卡**（2026-10-21 真机反馈）：
/// - **按行懒加载**：`LazyVStack` 里一行一个 `HStack`，懒加载的单位是行不是格（一屏 64 格只有 8 行），新建的东西少得多
/// - 格子的大小在这里算好传进去（`OverviewCell` 不用 GeometryReader 自己量）
/// - 格子不再各自上报位置：手指底下是哪篇，按版式算（`OverviewLayout.entry(at:)`），月份标题、行高、间距都是定死的
struct ShowcaseOverview: View {
    /// 新的在前
    let entries: [JournalEntry]
    let zoom: ShowcaseZoom
    /// 页面宽度（`HomeView` 量好传进来）：格子多大照它算，不在每一格里量
    let width: CGFloat
    /// 版式和宫格在屏幕上的位置（引用类型，滚动时在写，写它不重绘）：捏合时按它算手指底下是哪篇
    let layout: OverviewLayout
    /// 换一屏放几篇（读屏的动作用；手指捏合在 `HomeView`）：换到哪一级、以哪篇为准
    let onZoom: (ShowcaseZoom?, UUID) -> Void
    let onOpen: (UUID) -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// 月份标题的高度（定死，版式算位置要用）
    static let headerHeight: CGFloat = 34

    var body: some View {
        let theme = themeManager.current
        let months = OverviewLayout.months(of: entries)
        let cell = OverviewLayout.cellSize(width: width, zoom: zoom)
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(months) { month in
                Section {
                    ForEach(month.rows(columns: zoom.columns), id: \.first!.id) { row in
                        HStack(spacing: zoom.spacing) {
                            ForEach(row, id: \.id) { digest in
                                cellView(digest, size: cell)
                            }
                        }
                        .padding(.bottom, zoom.spacing)
                    }
                } header: {
                    Text(verbatim: month.title)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .tracking(theme.letterSpacingWide)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.bottom, 8)
                        .frame(height: Self.headerHeight)
                        .background(theme.background)
                }
            }
        }
        .padding(.horizontal, ShowcaseZoom.margin)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            layout.update(frame: frame, months: months, zoom: zoom, width: width)
        }
    }

    @ViewBuilder
    private func cellView(_ digest: EntryDigest, size: CGSize) -> some View {
        let cell = OverviewCell(digest: digest, zoom: zoom, size: size)
            .contentShape(.rect)
            .onTapGesture { onOpen(digest.id) }
            .accessibilityAction { onOpen(digest.id) }
        // 换级的读屏动作只在旁白开着时挂：每格多三个修饰，几十格一起新建时都是开销
        if voiceOver {
            cell
                .accessibilityAction(named: Text("一屏看更多篇")) { onZoom(zoom.zoomedOut, digest.id) }
                .accessibilityAction(named: Text("一屏看更少篇")) { onZoom(zoom.zoomedIn, digest.id) }
        } else {
            cell
        }
    }
}

/// 总览的版式：格子多大、每个月占多高、手指底下是哪篇。全按定死的数算，不靠格子上报位置。
///
/// 引用类型、不是 `@Observable`：宫格滚动时每帧都在更新它的位置，写它不能触发重绘
final class OverviewLayout {
    struct Month: Identifiable {
        let id: Int
        let title: String
        var digests: [EntryDigest]

        func rows(columns: Int) -> [[EntryDigest]] {
            stride(from: 0, to: digests.count, by: columns).map { Array(digests[$0..<min($0 + columns, digests.count)]) }
        }
    }

    /// 宫格（含两边留白）此刻在屏幕上的位置
    private var frame: CGRect = .zero
    private var width: CGFloat = 0
    private var months: [Month] = []
    private var zoom: ShowcaseZoom = .sixteen

    func update(frame: CGRect, months: [Month], zoom: ShowcaseZoom, width: CGFloat) {
        self.frame = frame
        self.months = months
        self.zoom = zoom
        self.width = width
    }

    /// 按月切段（`entries` 已经是新的在前，不重新排）。文字都是 `EntryDigest` 里算好的，这里只做比较
    @MainActor
    static func months(of entries: [JournalEntry]) -> [Month] {
        var result: [Month] = []
        for entry in entries {
            let digest = EntryDigest.of(entry)
            if result.last?.id == digest.month {
                result[result.count - 1].digests.append(digest)
            } else {
                result.append(Month(id: digest.month, title: digest.monthKey, digests: [digest]))
            }
        }
        return result
    }

    /// 一格多大：一行 `columns` 格，两边留白、格间空隙扣掉，宽高比定死
    static func cellSize(width: CGFloat, zoom: ShowcaseZoom) -> CGSize {
        let columns = CGFloat(zoom.columns)
        let w = max(1, (width - ShowcaseZoom.margin * 2 - zoom.spacing * (columns - 1)) / columns)
        return CGSize(width: w, height: w / ShowcaseZoom.cellAspect)
    }

    /// 手指（全局坐标）底下是哪篇。落在月份标题上算那个月第一篇，落在缝里算最近的一格
    func entry(at point: CGPoint) -> UUID? {
        guard frame.width > 0, width > 0, !months.isEmpty else { return nil }
        let cell = Self.cellSize(width: width, zoom: zoom)
        let rowStride = cell.height + zoom.spacing
        // `frame` 含两边留白：先扣掉左边的留白再算第几列
        let column = min(max(Int((point.x - frame.minX - ShowcaseZoom.margin) / (cell.width + zoom.spacing)), 0), zoom.columns - 1)
        var y = point.y - frame.minY
        for month in months {
            let rows = (month.digests.count + zoom.columns - 1) / zoom.columns
            let height = ShowcaseOverview.headerHeight + CGFloat(rows) * rowStride
            if y < height {
                let inRows = y - ShowcaseOverview.headerHeight
                guard inRows >= 0 else { return month.digests.first?.id }
                let row = min(Int(inRows / rowStride), rows - 1)
                let index = min(row * zoom.columns + column, month.digests.count - 1)
                return month.digests[index].id
            }
            y -= height
        }
        return months.last?.digests.last?.id
    }
}
