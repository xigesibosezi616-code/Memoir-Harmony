import SwiftUI
import UIKit

/// 书架的格子：摆书、长按拿起、拖到别处放下、拖到边缘自动滚动。
///
/// 只管「摆」和「挪」，不碰数据库 —— 打开、新建、保存新顺序都回调给 `BookshelfView`。
///
/// ## 交互（2026-10 日记本重铸 P1，按产品负责人的描述）
/// 像从真的书架上拿一本书、换个位置放回去，**丝滑、温柔**：
/// 1. 长按一本 → 这一本绕自己的竖轴**同轴转过去**一个角度，露出书脊，轻轻浮起
/// 2. 拖着它走 → **其余的书一动不动**（不晃、不让位、不出角标 —— 真的书架不会这样）
/// 3. 松手 → 先落进手下的那个位置，这时其余的书才轻轻挪开让出位子
/// 4. 落定之后 → 再同轴转回正面
///
/// 全程用不过冲的平滑曲线（`.smooth`），不弹、不晃。
/// 「全部日记」固定第一格，不能拖。换封面 / 重命名 / 删除在日记本页右上角的「…」里。
///
/// > 第一版做过「像桌面图标那样」：长按进入整理模式、其余的书抖动、拖动时实时让位、随手速侧倾回弹。
/// > 产品负责人看过后否掉了（2026-10-07）—— 真正的书架和日记本不会抖。
///
/// ## 为什么格子位置是算出来的，不是量出来的
/// 换位之后各格子上报的新位置要晚一帧才到，按上报的位置算落点会算错。
/// 所以只量两样东西 —— 整个格子的起点和单格尺寸 —— 每一格的位置都按行列推算。
struct ShelfGridView: View {
    /// 已按书架顺序排好（`sortOrder`, `createdAt`）
    let tags: [Tag]
    let counts: [String: Int]
    let allEntriesCount: Int

    var onOpenAll: () -> Void
    var onOpen: (Tag) -> Void
    var onCreate: () -> Void
    /// 松手后顺序真的变了才调，参数是全部日记本的新顺序
    var onReorder: ([UUID]) -> Void

    @Environment(ThemeManager.self) private var themeManager
    /// 读一下让语言切换时重算「全部日记」那本的书名（它不是 `Text(LocalizedStringKey)`）
    @Environment(\.locale) private var locale

    // MARK: 布局与手感常量

    private static let space = "shelf"
    private static let columnCount = 3
    private static let columnSpacing: CGFloat = 18
    /// 行距要容下书架板（板子画在书底下）
    private static let rowSpacing: CGFloat = 38
    /// 第一排书离导航栏的距离。和左右边距差不多，书架看起来是个整齐的框
    private static let topInset: CGFloat = 20

    /// 拿起时转过去的角度。32° 露出书脊又不至于转得太夸张
    private static let liftDegrees: CGFloat = 32
    /// 长按多久拿起。比系统默认的长按略长一点，免得滑动浏览时误触
    private static let pressDuration: Double = 0.35
    /// 拿起（转过去 + 浮起）
    private static let liftAnimation: Animation = .smooth(duration: 0.45)
    /// 跟手：很短的平滑，拖起来不生硬，又不至于明显拖在手指后面
    private static let followAnimation: Animation = .interactiveSpring(response: 0.2, dampingFraction: 0.88)
    /// 落位（书移进去、其余的书让开）
    private static let settleAnimation: Animation = .smooth(duration: 0.42)
    /// 转回正面
    private static let turnBackAnimation: Animation = .smooth(duration: 0.5)

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.columnSpacing), count: Self.columnCount)
    }

    // MARK: 状态

    /// 本地顺序。拖动过程中不变，松手那一刻才改（其余的书这时才动）
    @State private var order: [UUID] = []
    @State private var gridFrame: CGRect = .zero
    @State private var cellSize: CGSize = .zero

    @State private var drag: Drag?
    /// 拿在手里那本书的中心（shelf 坐标）
    @State private var dragCenter: CGPoint = .zero
    /// 手指位置（shelf 坐标）。自动滚动时手指不动、内容在动，要自己跟着挪
    @State private var finger: CGPoint = .zero
    /// 拿在手里那本的转角（弧度）
    @State private var bookAngle: CGFloat = 0
    /// 浮起（略放大 + 影子变深）
    @State private var isLifted = false
    @State private var orderAtLift: [UUID] = []
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var autoScrollSpeed: CGFloat = 0

    @State private var scrollPosition = ScrollPosition()
    @State private var metrics = ScrollMetrics()
    @State private var hasAppeared = false

    private struct Drag: Equatable {
        let id: UUID
        /// 拿起那一刻手指相对书中心的偏移，拖动时保持不变 —— 手指捏在书的哪儿，就一直捏在哪儿
        var grab: CGSize
        /// 已松手、正在落位 / 转回正面
        var isSettling = false
    }

    /// `ScrollGeometry` 里用得到的几样。
    ///
    /// ⚠️ 实测（2026-10-07 隔离 harness）：`contentOffset.y` 静止在顶部时是 **−导航栏高度**（−116），
    /// 而 `ScrollPosition.scrollTo(y:)` 的 y 是**扣掉导航栏之后**的坐标（y = 0 就是顶部）。
    /// 两者差一个 `contentInsets.top`，混用的话第一下就会跳出一个导航栏的高度。
    private struct ScrollMetrics: Equatable {
        var offsetY: CGFloat = 0
        var insetTop: CGFloat = 0
        var container: CGFloat = 0
        var content: CGFloat = 0

        /// `scrollTo(y:)` 口径的当前位置
        var scrollY: CGFloat { offsetY + insetTop }
        var maxScrollY: CGFloat { max(0, content - container) }
    }

    // MARK: - Body

    var body: some View {
        let theme = themeManager.current
        ScrollView {
            // 📌 2026-10 去掉了顶上的「珍藏的日记本」：导航栏已经写着「日记本」，书架直接从顶上开始
            LazyVGrid(columns: columns, spacing: Self.rowSpacing) {
                allEntriesSlot
                ForEach(Array(orderedTags.enumerated()), id: \.element.id) { index, tag in
                    bookSlot(tag, index: index)
                }
                newBookSlot(theme: theme, index: orderedTags.count + 1)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                gridFrame = $0
            }
            .padding(.horizontal, 22)
            .padding(.top, Self.topInset)
            .padding(.bottom, 60)
            .coordinateSpace(.named(Self.space))
            .background {
                ShelfPlanks(rowBottoms: rowBottoms, theme: theme)
            }
            .overlay(alignment: .topLeading) {
                bookInHand
            }
        }
        .scrollPosition($scrollPosition)
        .scrollDisabled(drag != nil)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
            ScrollMetrics(
                offsetY: geo.contentOffset.y,
                insetTop: geo.contentInsets.top,
                container: geo.containerSize.height,
                content: geo.contentSize.height
            )
        } action: { _, new in
            metrics = new
        }
        .onChange(of: tags.map(\.id), initial: true) { _, ids in
            // 手里拿着书的时候不跟着数据库改（CloudKit 可能这时同步进来一本），放下之后自然对齐
            if drag == nil { order = ids }
        }
        .onAppear { hasAppeared = true }
        .onDisappear { resetImmediately() }
    }

    // MARK: - 各格

    private var allEntriesSlot: some View {
        ShelfBookView(
            name: NSLocalizedString("全部日记", bundle: .appLanguage, comment: "书架上的第一本：全部日记"),
            entryCount: allEntriesCount,
            color: .ivory
        )
        // 单格尺寸从这一格量：它固定在第一格、永远不会被拿走
        .onGeometryChange(for: CGSize.self) { $0.size } action: { cellSize = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            if drag == nil { onOpenAll() }
        }
        .appearing(hasAppeared, index: 0)
    }

    private func bookSlot(_ tag: Tag, index: Int) -> some View {
        ShelfBookView(name: tag.name, entryCount: counts[tag.name, default: 0], color: tag.bookColor, photo: tag.coverPhoto, layout: tag.coverLayout)
            // 拿在手里的那本：原位空着（像真的从架子上抽走了一本），书本身画在 `bookInHand`
            .opacity(drag?.id == tag.id ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if drag == nil { onOpen(tag) }
            }
            .gesture(BookPressGesture(
                minimumDuration: Self.pressDuration,
                space: .named(Self.space),
                onBegan: { lift(tag, at: $0) },
                onChanged: { move(to: $0) },
                onEnded: { drop() }
            ))
            .appearing(hasAppeared, index: index + 1)
    }

    private func newBookSlot(theme: any AppTheme, index: Int) -> some View {
        Button(action: onCreate) {
            NewBookButton(theme: theme)
                .padding(.trailing, ShelfBookView.pageEdge)   // 与书同宽同高，书架上才对得齐
        }
        .buttonStyle(.plain)
        .appearing(hasAppeared, index: index)
    }

    /// 拿在手里的那本：有厚度，能同轴转（见 `ShelfBook3D`）
    @ViewBuilder
    private var bookInHand: some View {
        if let current = drag, let tag = orderedTags.first(where: { $0.id == current.id }) {
            ShelfBook3D(
                name: tag.name,
                entryCount: counts[tag.name, default: 0],
                color: tag.bookColor,
                photo: tag.coverPhoto,
                layout: tag.coverLayout,
                size: cellSize,
                angle: bookAngle
            )
            .scaleEffect(isLifted ? 1.04 : 1)
            .shadow(
                color: .black.opacity(isLifted ? 0.22 : 0),
                radius: isLifted ? 16 : 0,
                x: 0, y: isLifted ? 12 : 0
            )
            .position(dragCenter)
            .allowsHitTesting(false)
        }
    }

    // MARK: - 顺序与格子几何

    /// 按本地顺序排好的日记本。数据库里多出来的（拿着书时同步进来的）接在最后
    private var orderedTags: [Tag] {
        let byID = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = order.compactMap { byID[$0] }
        let placed = Set(result.map(\.id))
        result += tags.filter { !placed.contains($0.id) }
        return result
    }

    /// 总格数：全部日记 + 各本 + 新建
    private var slotCount: Int { orderedTags.count + 2 }

    private var columnWidth: CGFloat {
        (gridFrame.width - Self.columnSpacing * CGFloat(Self.columnCount - 1)) / CGFloat(Self.columnCount)
    }

    /// 第 `index` 格（0 = 全部日记）在 shelf 坐标里的位置
    private func slotRect(_ index: Int) -> CGRect {
        let col = index % Self.columnCount
        let row = index / Self.columnCount
        let x = gridFrame.minX + CGFloat(col) * (columnWidth + Self.columnSpacing)
            + (columnWidth - cellSize.width) / 2
        let y = gridFrame.minY + CGFloat(row) * (cellSize.height + Self.rowSpacing)
        return CGRect(x: x, y: y, width: cellSize.width, height: cellSize.height)
    }

    /// 离 `p` 最近的那本书的位置（0 起算，不含「全部日记」和「新建」）。
    /// 按最近而不是按「落在哪一格里」：松手在格子之间的缝里、或拖到了最后一本后面，也有个确定的去处
    private func nearestBookIndex(to p: CGPoint) -> Int? {
        guard !order.isEmpty else { return nil }
        return order.indices.min { a, b in
            distance(slotRect(a + 1), p) < distance(slotRect(b + 1), p)
        }
    }

    private func distance(_ rect: CGRect, _ p: CGPoint) -> CGFloat {
        hypot(rect.midX - p.x, rect.midY - p.y)
    }

    /// 每一层书底的 y，给书架板用
    private var rowBottoms: [CGFloat] {
        guard cellSize.height > 0 else { return [] }
        let rows = (slotCount + Self.columnCount - 1) / Self.columnCount
        return (0..<rows).map { slotRect($0 * Self.columnCount).maxY }
    }

    // MARK: - 拿起 / 拖动 / 放下

    /// `point`：长按成立那一刻手指的位置（shelf 坐标）
    private func lift(_ tag: Tag, at point: CGPoint) {
        guard drag == nil, cellSize.height > 0,
              let index = orderedTags.firstIndex(where: { $0.id == tag.id }) else { return }
        order = orderedTags.map(\.id)
        orderAtLift = order
        let rect = slotRect(index + 1)
        dragCenter = CGPoint(x: rect.midX, y: rect.midY)
        finger = point
        bookAngle = 0
        isLifted = false
        drag = Drag(id: tag.id, grab: CGSize(width: point.x - dragCenter.x, height: point.y - dragCenter.y))
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        // 下一拍再转：先让手里这本以正面、原尺寸出现（和格子里那本一模一样），再开始转，
        // 否则「出现」和「转」落在同一帧，看不到转过去的过程
        Task { @MainActor in
            withAnimation(Self.liftAnimation) {
                bookAngle = BookBox.liftAngle(degrees: Self.liftDegrees)
                isLifted = true
            }
        }
    }

    private func move(to point: CGPoint) {
        guard drag?.isSettling == false else { return }
        finger = point
        withAnimation(Self.followAnimation) { followFinger() }
        updateAutoScroll()
    }

    private func followFinger() {
        guard let grab = drag?.grab else { return }
        dragCenter = CGPoint(x: finger.x - grab.width, y: finger.y - grab.height)
    }

    /// 松手：先落位（其余的书这时才让开），落定后再同轴转回正面
    private func drop() {
        guard var current = drag, !current.isSettling else { return }
        stopAutoScroll()
        current.isSettling = true
        drag = current

        if let from = order.firstIndex(of: current.id), let to = nearestBookIndex(to: dragCenter) {
            let target = slotRect(to + 1)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
            withAnimation(Self.settleAnimation) {
                if to != from {
                    order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
                dragCenter = CGPoint(x: target.midX, y: target.midY)
                isLifted = false
            } completion: {
                withAnimation(Self.turnBackAnimation) {
                    bookAngle = 0
                } completion: {
                    drag = nil
                }
            }
        } else {
            drag = nil
        }
        if order != orderAtLift { onReorder(order) }
    }

    /// 离开书架页时立刻收摊，不做动画
    private func resetImmediately() {
        stopAutoScroll()
        drag = nil
        bookAngle = 0
        isLifted = false
    }

    // MARK: - 拖到边缘自动滚动

    /// 手指进入可视区上下 70pt 的边缘带就开始滚，越靠边越快
    private func updateAutoScroll() {
        let top = metrics.scrollY
        let bottom = top + metrics.container
        let zone: CGFloat = 70
        var speed: CGFloat = 0
        if finger.y < top + zone {
            speed = -max(2, min(12, (top + zone - finger.y) / 6))
        } else if finger.y > bottom - zone {
            speed = max(2, min(12, (finger.y - (bottom - zone)) / 6))
        }
        autoScrollSpeed = speed
        guard speed != 0 else { stopAutoScroll(); return }
        guard autoScrollTask == nil else { return }

        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled, drag?.isSettling == false, autoScrollSpeed != 0 {
                let current = metrics.scrollY
                let next = min(max(current + autoScrollSpeed, 0), metrics.maxScrollY)
                let delta = next - current
                if abs(delta) >= 0.5 {
                    scrollPosition.scrollTo(y: next)
                    // 先记上，别等滚动回调（16ms 内不一定回来），否则下一拍会重复滚同一段
                    metrics.offsetY += delta
                    // 手指没动、内容动了 —— 手指在内容里的位置跟着挪，书才会留在手指下
                    finger.y += delta
                    followFinger()
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
            autoScrollTask = nil
        }
    }

    private func stopAutoScroll() {
        autoScrollSpeed = 0
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }
}

// MARK: - 入场动画

private extension View {
    /// 书架第一次出现时一本本依次落下来
    func appearing(_ hasAppeared: Bool, index: Int) -> some View {
        self
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 20)
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.06), value: hasAppeared)
    }
}

// MARK: - 长按拿起的手势

/// 长按拿起一本书、接着拖动 —— 用 UIKit 原生的 `UILongPressGestureRecognizer`。
///
/// ## 为什么不用 SwiftUI 的 `LongPressGesture.sequenced(before: DragGesture)`
/// 2026-10-08 真机日志 + 模拟器注入滑动实测：挂上那套手势后，**手指落在书上（连同书周围十来 pt
/// 的命中余量）起手的滑动，书架完全滚不动** —— 按压在 20ms 左右就结束了，可滚动也没有接手。
/// 书铺满了整页，体感就是「整页时不时滑不动」。
///
/// UIKit 的长按和滚动视图的配合是系统级的老规矩（相册、桌面都是这么做的）：
/// 0.35s 内手指挪动超过 10pt，长按就失败、滚动接手；按够时长才拿起，拿起之后的移动都归长按。
struct BookPressGesture: UIGestureRecognizerRepresentable {
    let minimumDuration: TimeInterval
    /// 报告手指位置用的坐标空间（书架内容的坐标，随内容一起滚）
    let space: NamedCoordinateSpace
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    /// 松手、被系统打断（来电、切后台）、或者没按够时长就挪开了，都走这里
    var onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            onBegan(context.converter.location(in: space))
        case .changed:
            onChanged(context.converter.location(in: space))
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }
}
