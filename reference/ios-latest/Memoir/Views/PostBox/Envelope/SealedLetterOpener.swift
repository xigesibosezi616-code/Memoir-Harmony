import SwiftUI

/// 一枚封着的火漆信，一下一下拆开（2026-10-11 产品定，2026-10-21 加了滑和掀）：
/// 第一步打碎火漆 → 第二步打开信封 → 第三步抽出信纸，抽完自己摊成信纸（`onFinished`）。
///
/// - 第一步、第三步：**轻点或上滑**都行
/// - 第二步：**手指捏住封舌往任意方向拉**，封舌像书页一样跟着手指卷开（`SealedEnvelope.dragGrab`）；
///   拉过四成（或者往上一甩）松手，自己卷开到底；没过就落回去。也可以轻点 / 上滑，封舌从尖上往上卷开
/// - 每一步播完停在那等下一下 —— 中间不刻意停顿，也不催
/// - **急着连点**：这一步还没播完又点了，就不再等，后面几步首尾相接一口气拆完，和以前的一气呵成一样
/// - 「减弱动态效果」打开时：点一下直接换成信纸，只轻轻一顿
/// - 旁白（VoiceOver）的「激活」动作一口气拆完
///
/// 震动和纸声见 `LetterOpeningFeel`（掀封舌那一路借投信推信的 `LetterLiftFeel`），动画见 `SealedEnvelope`
struct SealedLetterOpener: View {
    let palette: LetterPalette
    /// 火漆上压的字（笔友名字的首字）
    let sealMark: String?
    /// 信封背面那行「来自 某某」，也是旁白读出来的
    let sender: Text
    /// 第一下打碎火漆的那一刻（信算拆开了）
    var onBroken: () -> Void = {}
    /// 信纸抽出来了，该摊开成信纸了
    var onFinished: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var feel = LetterOpeningFeel()
    /// 掀封舌那一路的手感（持续的纸声和震动跟着手速）
    @State private var peelFeel = LetterLiftFeel()
    @State private var progress: Double = 0
    /// 已经开始的步数：0 = 还封着，1 = 火漆碎了，2 = 信封开了，3 = 信纸在抽 / 抽完了
    @State private var stage = 0
    /// 有一步正在播
    @State private var playing = false
    /// 急着连点：后面的步不等了，一口气拆完
    @State private var hurried = false
    @State private var finished = false

    /// 信封在这一页上的位置（换算手指捏在封舌哪儿）
    @State private var envelopeFrame: CGRect = .zero
    /// 手指正捏着封舌拉：捏住的那一点（封舌合着时的位置，按信封宽高的比例）
    @State private var grab: CGPoint?
    /// 手指现在把那一点拉到了哪（按信封宽高的比例）
    @State private var finger: CGPoint = .zero
    /// 这一下手势已经算过数了（上滑触发了一步）：松手时不再当成点
    @State private var gestureUsed = false

    private static let space = "opener"

    var body: some View {
        let theme = themeManager.current
        GeometryReader { geo in
            VStack(spacing: 28) {
                SealedEnvelope(palette: palette, sealMark: sealMark, sender: sender, progress: progress,
                               curls: true, curl: .straight, dragGrab: grab, dragFinger: finger)
                    .frame(width: min(geo.size.width - 64, 340))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { envelopeFrame = $0 }

                // 下一下该做什么。正在播、或者急着拆完的时候不显示
                ZStack {
                    hint(Text("轻点或上滑，拆开火漆"), visible: stage == 0)
                    hint(Text("捏住封舌掀开，或者轻点一下"), visible: stage == 1 && !playing && !hurried && grab == nil)
                    hint(Text("上滑或轻点，抽出信纸"), visible: stage == 2 && !playing && !hurried)
                }
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
            }
            // 抽出来的信纸会冒出信封上沿，整体放在中间偏下，给它留出地方
            .padding(.top, 80)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(gesture)
        }
        .coordinateSpace(.named(Self.space))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sender)
        .accessibilityHint(Text("拆开这封信"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            hurried = true
            if !playing { tap() }
        }
        // 先把震动引擎热起来，点下去那一刻才不会慢半拍
        .onAppear {
            feel.prepare()
            peelFeel.prepare()
        }
        .onDisappear {
            feel.stop()
            peelFeel.stop()
        }
    }

    private func hint(_ text: Text, visible: Bool) -> some View {
        text
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: visible)
    }

    // MARK: - 手势：点、上滑、掀

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !finished, !gestureUsed else { return }
                let moved = hypot(value.translation.width, value.translation.height)
                // 第二步：捏住封舌拉
                if stage == 1, !playing, !hurried, !reduceMotion, envelopeFrame.width > 1 {
                    if grab == nil, moved > 8 { startPeel(at: value.startLocation) }
                    if grab != nil { peel(to: value.location, velocity: value.velocity) }
                    return
                }
                // 第一步、第三步：上滑
                let up = -value.translation.height
                if up > 28, up > abs(value.translation.width) * 1.2 {
                    gestureUsed = true
                    tap()
                }
            }
            .onEnded { value in
                defer { gestureUsed = false }
                if grab != nil {
                    finishPeel(velocity: value.velocity)
                    return
                }
                guard !gestureUsed else { return }
                // 几乎没挪：是点
                if hypot(value.translation.width, value.translation.height) < 10 { tap() }
            }
    }

    // MARK: - 掀封舌

    /// 开始掀：按在封舌上就捏住按的那一点（太靠上沿的往下挪一点，不然轻轻一拉就翻到底）；按在别处就当捏住封舌尖
    private func startPeel(at location: CGPoint) {
        let e = envelopeFrame
        let p = CGPoint(x: (location.x - e.minX) / e.width, y: (location.y - e.minY) / e.height)
        let onFlap = p.y >= 0 && p.y <= 0.58 * (1 - abs(2 * p.x - 1))
        let g = onFlap ? CGPoint(x: p.x, y: max(p.y, 0.3)) : CGPoint(x: 0.5, y: 0.56)
        grab = g
        finger = g
        peelFeel.begin()
    }

    /// 手指挪到 `location`：捏住的那一点跟过去。上沿那道折痕粘着，拉不脱 —— 手指只能在不把折痕扯开的范围里
    private func peel(to location: CGPoint, velocity: CGSize) {
        guard let g = grab else { return }
        let w = envelopeFrame.width, h = envelopeFrame.height
        let gp = CGPoint(x: g.x * w, y: g.y * h)
        let dx = location.x - (envelopeFrame.minX + gp.x)
        let dy = location.y - (envelopeFrame.minY + gp.y)
        var f = CGPoint(x: gp.x + dx, y: gp.y + dy)
        // 折痕两头离手指不能比离捏住的点远（否则卷轴会切过折痕，封舌就从信封上撕下来了）
        let ends = [CGPoint.zero, CGPoint(x: w, y: 0)]
        for _ in 0..<3 {
            for end in ends {
                let limit = hypot(gp.x - end.x, gp.y - end.y)
                let vx = f.x - end.x, vy = f.y - end.y
                let d = hypot(vx, vy)
                if d > limit, d > 0 { f = CGPoint(x: end.x + vx * limit / d, y: end.y + vy * limit / d) }
            }
        }
        // 卷开的封舌画在信封上方一块地方，别拉出画布
        f.x = min(max(f.x, -0.25 * w), 1.25 * w)
        f.y = max(f.y, -0.7 * h)
        finger = CGPoint(x: f.x / w, y: f.y / h)
        peelFeel.update(progress: openFraction, velocity: velocity)
    }

    /// 掀开了多少：捏住的那一点从原地到它沿折痕的倒影（翻开到底）走了几成
    private var openFraction: Double {
        guard let g = grab, envelopeFrame.height > 0 else { return 0 }
        let w = envelopeFrame.width, h = envelopeFrame.height
        let full = 2 * g.y * h
        let moved = hypot((finger.x - g.x) * w, (finger.y - g.y) * h)
        return full > 0 ? min(1, moved / full) : 0
    }

    /// 松手：过了四成（或者往上一甩）就自己卷开到底，算打开了信封；否则落回去
    private func finishPeel(velocity: CGSize) {
        guard let g = grab else { return }
        let open = openFraction
        let flung = velocity.height < -600 && open > 0.2
        if open >= 0.4 || flung {
            peelFeel.end(posted: true)
            stage = 2
            playing = true
            withAnimation(.smooth(duration: 0.32)) {
                finger = CGPoint(x: g.x, y: -g.y)
            } completion: {
                // 卷到底了：换成静止的「信封开着」（和卷到底一模一样，接得上）
                LetterHaptics.fire(LetterPostingFeel.flapPat)
                progress = LetterOpeningFeel.stageTargets[1]
                grab = nil
                playing = false
                if hurried { advance() }
            }
        } else {
            peelFeel.end(posted: false)
            withAnimation(.smooth(duration: 0.28)) {
                finger = g
            } completion: {
                grab = nil
            }
        }
    }

    // MARK: - 一下一下拆

    private func tap() {
        guard !finished, grab == nil else { return }
        if reduceMotion {
            guard stage == 0 else { return }
            stage = 3
            finished = true
            onBroken()
            feel.playQuiet()
            onFinished()
            return
        }
        // 这一步还在播又点了：急了，后面的不等了
        if playing {
            hurried = true
            return
        }
        advance()
    }

    /// 播下一步。播完：抽出来了就摊开；急着拆的话接着播下一步；否则停在这等下一下
    private func advance() {
        guard stage < LetterOpeningFeel.stageTargets.count else { return }
        let step = stage
        stage += 1
        playing = true
        if step == 0 { onBroken() }
        // 震动和纸声与这一步的动画同时起步
        feel.play(stage: step)
        withAnimation(.linear(duration: LetterOpeningFeel.duration(ofStage: step))) {
            progress = LetterOpeningFeel.stageTargets[step]
        } completion: {
            playing = false
            if stage == LetterOpeningFeel.stageTargets.count {
                finished = true
                onFinished()
            } else if hurried {
                advance()
            }
        }
    }
}
