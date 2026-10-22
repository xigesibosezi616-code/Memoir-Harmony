import SwiftUI
import QuartzCore

/// 选本子的转盘：一排日记本立在书架上，正中那本正对着你，两边的斜着排开 —— 像挑唱片（Cover Flow）。
///
/// - 几本书**共用一个视点**（`BookBox.Offset`）：左边那几本朝正中转过来，露出书脊；右边那几本露出书口
/// - 视点放在书架板的高度：远一点的书只是小一点、书底都落在同一块板上
/// - 左右甩一下带着惯性一本本转过去，越转越慢，正好停在一本上（`CarouselMotion.Glide`）；每到一本「笃」一声（`NotebookPickerFeel`）
/// - 转着的时候按下去当场停住，松手就近落到一本上；停着的时候点旁边那本转过去，点正中那本 = 就选它
/// - 三本以上首尾相接，两个方向都能一直转；一两本的时候不接（接起来同一本会在两边同时出现）
struct NotebookCarousel: View {
    let books: [PickerBook]
    /// 正中那本（`books` 的下标），转的时候跟着变
    @Binding var centered: Int
    /// 外面要转到哪本（按 id，比如刚新建的那本）；转过去之后清空
    @Binding var focus: String?
    /// 停着的时候点正中那本
    var onConfirm: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    /// 正中是第几本（不取模，见 `CarouselMotion`）
    @State private var position: Double = 0
    @State private var motion: CarouselMotion?
    @State private var drag: DragStart?
    @State private var feel = NotebookPickerFeel()
    /// 照片封面的缩略图读好了（书脊颜色要用照片的主色，读好之后重画一次）
    @State private var thumbnailsReady = false

    private struct DragStart {
        let position: Double
        /// 按下去那一刻正在转（这一下是「停住」，不是点选）
        let stoppedMotion: Bool
    }

    /// 甩得再快也就这么快（本/秒）
    private static let maxSpeed = 16.0

    private var count: Int { books.count }
    /// 三本以上首尾相接
    private var loops: Bool { count >= 3 }

    var body: some View {
        let theme = themeManager.current
        GeometryReader { geo in
            let geometry = CarouselGeometry(size: geo.size)
            TimelineView(.animation(paused: motion == nil)) { context in
                let p = motion?.position(at: context.date) ?? position
                stage(p, geometry: geometry, theme: theme)
                    .onChange(of: context.date) { _, now in advance(to: now) }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(geometry))
        }
        .onAppear {
            feel.start()
            feel.reset(Int(position.rounded()))
        }
        .onDisappear { feel.stop() }
        .task { await loadThumbnails() }
        .onChange(of: books.map(\.id)) { old, new in realign(from: old, to: new) }
        .onChange(of: focus) { _, id in turn(toID: id) }
        .accessibilityElement()
        .accessibilityLabel(Text("日记本"))
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let here = Int(position.rounded())
            switch direction {
            case .increment: turn(to: here + 1)
            case .decrement: turn(to: here - 1)
            @unknown default: break
            }
        }
        .accessibilityAction { onConfirm() }
    }

    // MARK: - 画

    private func stage(_ p: Double, geometry g: CarouselGeometry, theme: any AppTheme) -> some View {
        ZStack(alignment: .topLeading) {
            ShelfPlanks(rowBottoms: [g.shelfY], theme: theme)
                .frame(width: g.size.width, height: g.size.height)
                .zIndex(-100)
            ForEach(slots(around: p), id: \.self) { j in
                let d = Double(j) - p
                CarouselBook(book: books[Self.wrap(j, count)], d: d, geometry: g)
                    .opacity(fade(d))
                    .zIndex(-abs(d))
            }
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        // 读一下，缩略图读好后重画（书脊用照片的主色）
        .id(thumbnailsReady)
    }

    /// 这一刻要画的几本（不取模的位置）。离正中四本以外的早就出了屏幕
    private func slots(around p: Double) -> [Int] {
        guard count > 0 else { return [] }
        guard loops else { return Array(0..<count) }
        let base = Int(p.rounded(.down))
        return (base - 4...base + 5).filter { fade(Double($0) - p) > 0.001 }
    }

    /// 远处淡出。本数少的时候，同一本在左右两头各有一份 —— 离正中半圈的地方淡掉，不让它同时出现
    private func fade(_ d: Double) -> Double {
        let a = abs(d)
        var alpha = min(1, max(0, 4 - a))
        if loops {
            let half = Double(count) / 2
            alpha = min(alpha, max(0, (half - a) / 0.5))
        }
        return alpha
    }

    private var accessibilityValue: Text {
        guard let book = books[safe: centered] else { return Text(verbatim: "") }
        if book.isAll { return Text("全部日记") }
        return Text(verbatim: book.title)
    }

    // MARK: - 动

    private func dragGesture(_ g: CarouselGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    // 按下：正在转的话当场停住（产品定：转着的时候随时点一下就停）
                    var stopped = false
                    if let motion {
                        position = motion.position(at: .now)
                        self.motion = nil
                        stopped = true
                    }
                    drag = DragStart(position: position, stoppedMotion: stopped)
                }
                guard let drag else { return }
                position = bounded(drag.position - value.translation.width / g.dragSpacing)
                reach(position, speed: value.velocity.width / g.dragSpacing)
            }
            .onEnded { value in
                guard let start = drag else { return }
                drag = nil
                let moved = abs(value.translation.width) > 8 || abs(value.translation.height) > 8
                if moved {
                    let v = -value.velocity.width / g.dragSpacing
                    fling(min(Self.maxSpeed, max(-Self.maxSpeed, v)))
                } else if start.stoppedMotion {
                    settle(velocity: 0)
                } else if let j = g.slot(at: value.location, position: position, candidates: slots(around: position).filter { fade(Double($0) - position) > 0.5 }) {
                    if j == Int(position.rounded()) { onConfirm() } else { turn(to: j) }
                } else {
                    settle(velocity: 0)
                }
            }
    }

    /// 每一帧：转到哪了、有没有新的一本到正中、停没停
    private func advance(to now: Date) {
        guard let motion else { return }
        reach(motion.position(at: now), speed: motion.velocity(at: now))
        if motion.isFinished(at: now) {
            position = motion.target
            self.motion = nil
            reach(position, speed: 0)
        }
    }

    /// 位置变了：到了新的一本就「笃」，正中那本换了就告诉外面
    private func reach(_ p: Double, speed: Double) {
        feel.track(p, speed: speed)
        let index = Self.wrap(Int(p.rounded()), count)
        if index != centered, count > 0 { centered = index }
    }

    private func fling(_ velocity: Double) {
        if let glide = CarouselMotion.Glide(from: position, velocity: velocity, range: range) {
            motion = CarouselMotion(kind: .glide(glide), start: .now)
        } else {
            settle(velocity: velocity)
        }
    }

    /// 就近落到一本上
    private func settle(velocity: Double) {
        var target = position.rounded()
        if let range { target = min(max(target, range.lowerBound), range.upperBound) }
        // 不首尾相接的时候，往头上冲的那点速度不要了（不回弹）
        var v = velocity
        if let range, (position <= range.lowerBound && v < 0) || (position >= range.upperBound && v > 0) { v = 0 }
        motion = CarouselMotion(kind: .settle(.init(from: position, to: target, velocity: v)), start: .now)
    }

    /// 转到第 `j` 本（不取模的位置）
    private func turn(to j: Int) {
        var target = Double(j)
        if let range { target = min(max(target, range.lowerBound), range.upperBound) }
        if let motion { position = motion.position(at: .now) }
        motion = CarouselMotion(kind: .tween(.init(from: position, to: target)), start: .now)
    }

    /// 转到某一本（按 id）：首尾相接时走近的那个方向
    private func turn(toID id: String?) {
        guard let id else { return }
        focus = nil
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        let here = Int(position.rounded())
        guard loops else { return turn(to: index) }
        var delta = index - Self.wrap(here, count)
        if delta > count / 2 { delta -= count }
        if delta < -(count - 1) / 2 { delta += count }
        turn(to: here + delta)
    }

    /// 日记本列表变了（刚新建了一本、别的设备同步来增删了）：正中那本还是那本，不跳到别的书上
    private func realign(from old: [String], to new: [String]) {
        guard old != new, !new.isEmpty else { return }
        let current = old.isEmpty ? nil : old[Self.wrap(Int(position.rounded()), old.count)]
        let index = current.flatMap { new.firstIndex(of: $0) } ?? 0
        motion = nil
        drag = nil
        position = Double(index)
        feel.reset(index)
        centered = index
    }

    /// 只有一两本的时候能停的范围；首尾相接时 nil
    private var range: ClosedRange<Double>? {
        loops ? nil : 0...Double(max(0, count - 1))
    }

    /// 不首尾相接的时候拖过头：越拖越沉，最多再出去小半本
    private func bounded(_ p: Double) -> Double {
        guard let range else { return p }
        if p < range.lowerBound { return range.lowerBound - 0.4 * tanh((range.lowerBound - p) * 0.8) }
        if p > range.upperBound { return range.upperBound + 0.4 * tanh((p - range.upperBound) * 0.8) }
        return p
    }

    private func loadThumbnails() async {
        for book in books {
            if case .file(let name)? = book.photo, NotebookCoverStore.cachedThumbnail(name) == nil {
                _ = await NotebookCoverStore.thumbnail(name)
            }
        }
        thumbnailsReady = true
    }

    static func wrap(_ j: Int, _ n: Int) -> Int {
        guard n > 0 else { return 0 }
        return ((j % n) + n) % n
    }
}

// MARK: - 几何

/// 转盘的几何：正中那本多大、两边怎么排、视点多远。都按正中那本封面的宽度成比例
struct CarouselGeometry {
    let size: CGSize
    /// 正中那本的封面
    let cover: CGSize
    /// 书的厚度
    let depth: CGFloat
    /// 视点到正中那本封面的距离
    let eye: CGFloat
    /// 书底（书架板）的 y，也是视点的高度
    let shelfY: CGFloat

    /// 正中那本到旁边那本的距离；再往外每本之间的距离
    private let near: CGFloat
    private let far: CGFloat
    /// 两边的书往后退多少
    private let back: CGFloat

    /// 两边的书转过去的角度：朝露出书脊的方向转（左边那几本），右边的反过来。
    /// 72° 侧得够多，两边能叠出一摞（左边一排书脊、右边一排书口），正中那本才显得大
    private static let sideAngle = BookBox.liftAngle(degrees: 72)

    /// 拖多远算一本
    var dragSpacing: CGFloat { cover.width * 0.8 }

    init(size: CGSize) {
        self.size = size
        // 正中那本占屏宽一半（产品定：弹出来一本大的「全部日记」）；书架板（前沿 9 + 板面 7）和书的影子要留出地方
        let width = max(80, min(size.width * 0.5, (size.height - 40) * 0.73))
        cover = CGSize(width: width, height: width / 0.73)
        depth = (width * 0.12).rounded()
        eye = width * 4.6
        shelfY = (size.height - 24 + cover.height) / 2
        // 两边的书退到后面（变小），旁边那本的里侧正好挨着正中那本的边
        near = width * 0.84
        far = width * 0.16
        back = width * 1.1
    }

    /// 视点（透视的消失点）在转盘里的位置
    var vanishingPoint: CGPoint { CGPoint(x: size.width / 2, y: shelfY) }

    /// 离正中差 `d` 本的那本书：转角、在场景里的位置。
    /// 一本以内平滑过渡（正中那本正对着、到旁边那格转满、退到后面），再往外只是一本本排过去
    func place(_ d: Double) -> (angle: CGFloat, offset: BookBox.Offset) {
        let a = abs(d)
        let sign: Double = d < 0 ? -1 : 1
        let x = a <= 1
            ? far * d + (near - far) * sin(d * .pi / 2)
            : sign * (far * a + near - far)
        let turn = a <= 1 ? sin(d * .pi / 2) : sign
        let z = -back * (1 - cos(min(a, 1) * .pi)) / 2 - max(0, a - 1) * cover.width * 0.04
        return (-Self.sideAngle * turn, BookBox.Offset(x: x, y: -cover.height / 2, z: z))
    }

    /// 点在哪本书上（`candidates` 是不取模的位置）：从前往后找，先碰到的那本
    func slot(at point: CGPoint, position p: Double, candidates: [Int]) -> Int? {
        for j in candidates.sorted(by: { abs(Double($0) - p) < abs(Double($1) - p) }) {
            let (angle, offset) = place(Double(j) - p)
            let span = horizontalSpan(angle: angle, offset: offset)
            // 书的高度按封面最靠前那条边算，宽松一点
            let scale = eye / (eye - offset.z)
            let top = shelfY - cover.height * scale
            if span.contains(point.x), point.y >= top - 8, point.y <= shelfY + 12 {
                return j
            }
        }
        return nil
    }

    /// 整本书（四条竖边）投影到屏幕上的左右范围
    private func horizontalSpan(angle: CGFloat, offset: BookBox.Offset) -> ClosedRange<CGFloat> {
        let turn = CATransform3DMakeRotation(angle, 0, 1, 0)
        let xs = [(-1.0, -1.0), (-1.0, 1.0), (1.0, -1.0), (1.0, 1.0)].map { sx, sz -> CGFloat in
            let lx = sx * cover.width / 2
            let lz = sz * depth / 2
            let x = lx * turn.m11 + lz * turn.m31 + offset.x
            let z = lx * turn.m13 + lz * turn.m33 - depth / 2 + offset.z
            return vanishingPoint.x + x * eye / (eye - z)
        }
        return xs.min()!...xs.max()!
    }
}

// MARK: - 一本书

/// 转盘上的一本：封面、书脊、书口三个面各自投影（`BookBox`），背着视点的面不画。
/// 整个视图和转盘一样大，几个面都摆在左上角 —— 投影直接落在转盘的坐标里
private struct CarouselBook: View {
    let book: PickerBook
    let d: Double
    let geometry: CarouselGeometry

    /// 封面按 150 宽画（和编辑封面页的大预览一样，书名、篇数的比例对），再放大到正中那本的大小
    private static let baseWidth: CGFloat = 150

    var body: some View {
        let g = geometry
        let (angle, offset) = g.place(d)
        let spine = ShelfBook3D.spineColor(color: book.color, photo: book.photo, layout: book.layout)
        // 转得越侧，封面越暗（光从正前方来）
        let shade = 0.26 * min(1, abs(d)) + 0.05 * max(0, min(2, abs(d) - 1))

        ZStack(alignment: .topLeading) {
            if visible(.spine, angle, offset) {
                BookSpine(color: spine)
                    .frame(width: g.depth, height: g.cover.height)
                    .colorMultiply(Color(white: 0.92))
                    .projectionEffect(projection(.spine, angle, offset, face: CGSize(width: g.depth, height: g.cover.height)))
            }
            if visible(.foreEdge, angle, offset) {
                BookForeEdge(boardColor: spine)
                    .frame(width: g.depth, height: g.cover.height)
                    .projectionEffect(projection(.foreEdge, angle, offset, face: CGSize(width: g.depth, height: g.cover.height)))
            }
            if visible(.cover, angle, offset) {
                BookCoverView(name: book.title, entryCount: book.count, color: book.color, photo: book.photo, layout: book.layout)
                    .frame(width: Self.baseWidth, height: Self.baseWidth / 0.73)
                    .scaleEffect(g.cover.width / Self.baseWidth, anchor: .topLeading)
                    .frame(width: g.cover.width, height: g.cover.height, alignment: .topLeading)
                    .colorMultiply(Color(white: 1 - shade))
                    .projectionEffect(projection(.cover, angle, offset, face: g.cover))
            }
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func visible(_ face: BookBox.Face, _ angle: CGFloat, _ offset: BookBox.Offset) -> Bool {
        BookBox.isVisible(face: face, angle: angle, coverSize: geometry.cover, depth: geometry.depth, eye: geometry.eye, offset: offset)
    }

    private func projection(_ face: BookBox.Face, _ angle: CGFloat, _ offset: BookBox.Offset, face size: CGSize) -> ProjectionTransform {
        ProjectionTransform(BookBox.transform(
            face: face, angle: angle, coverSize: geometry.cover, depth: geometry.depth,
            faceCenter: CGPoint(x: size.width / 2, y: size.height / 2),
            boxCenter: geometry.vanishingPoint, eye: geometry.eye, offset: offset
        ))
    }
}

/// 书口：一页页纸的边（细竖纹），前后两块书板的边压在两侧，书板比纸页上下各长出一点
private struct BookForeEdge: View {
    let boardColor: Color

    var body: some View {
        Canvas { ctx, size in
            let board = max(1.5, size.width * 0.08)
            let overhang: CGFloat = 2.5
            ctx.fill(Path(CGRect(x: 0, y: 0, width: board, height: size.height)), with: .color(boardColor))
            ctx.fill(Path(CGRect(x: size.width - board, y: 0, width: board, height: size.height)), with: .color(boardColor))
            let pages = CGRect(x: board, y: overhang, width: size.width - 2 * board, height: size.height - 2 * overhang)
            ctx.fill(Path(pages), with: .color(Color(hex: "#ECE4D3")))
            // 一页页纸的边
            var x = pages.minX + 0.8
            var i = 0
            while x < pages.maxX - 0.4 {
                var line = Path()
                line.move(to: CGPoint(x: x, y: pages.minY))
                line.addLine(to: CGPoint(x: x, y: pages.maxY))
                ctx.stroke(line, with: .color(.black.opacity(i % 3 == 0 ? 0.09 : 0.045)), lineWidth: 0.4)
                x += 1.1
                i += 1
            }
            // 侧面不朝着光，整体暗一点
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.12)))
        }
    }
}
