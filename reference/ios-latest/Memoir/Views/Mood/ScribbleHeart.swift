import SwiftUI

/// 心情弹窗中间那颗线团爱心（2026-10-17 产品定，换掉星云）。直接画在纸上，不用框：彩色细线的质感本身就和尺素搭。
///
/// 样子见 `ScribbleHeartDrawing`：心情越好线越整齐，越差越乱；线一直沿着心形在流，
/// 手里每震一下，心跟着跳一下（`MoodHaptics.pulse(at:)`，和震动同一个时钟）。
/// 呼吸引导时吸气胀、呼气缩，乱线慢慢理顺、颜色褪向平常（`MoodCalm`）；做完了停在平常 ——
/// 只是画面，记下的仍是他选的那档。
///
/// 可以碰：手指碰到哪一圈，那几圈线往前一涌，碰到的地方荡开涟漪，心轻轻一跳，手里也轻轻一下。
///
/// 每秒 60 帧。「减弱动态效果」下线不流、心不跳、碰了没有涟漪、不逐根画出来，但呼吸引导照样一胀一缩、照样慢慢褪。
struct ScribbleHeart: View, Animatable {
    /// 慢慢跟上滑杆的愉悦度（父视图给它加弹簧动画）
    var valence: Double
    /// 滑杆此刻的愉悦度：反应快的线直接跟它
    var target: Double
    /// 呼吸引导从哪一刻开始；nil = 不在呼吸引导里
    var breathingSince: Date?
    /// 呼吸引导做完了：心停在平常，不再一胀一缩
    var calmed: Bool
    /// 手里那台震动：心跟着它跳，碰心时也靠它轻轻一下
    var haptics: MoodHaptics?

    var animatableData: Double {
        get { valence }
        set { valence = newValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    /// 呼吸引导开始那一刻滑杆停在哪：画面从这里慢慢褪
    @State private var calmFrom: Double?
    /// 呼吸引导被打断（他又动了滑杆）那一刻画面褪到了哪：从这里回到滑杆那档，不跳
    @State private var interrupted: (valence: Double, at: Date)?
    /// 最近碰过的地方（心形坐标）
    @State private var touches: [(x: Double, y: Double, at: Date)] = []
    /// 早先碰过、已经涌完的：每根线累计往前多走了多少
    @State private var surges = [Double](repeating: 0, count: ScribbleHeartDrawing.strands.count)
    /// 这一次按住划动时，上一下记在哪
    @State private var lastTouch: CGPoint?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion && breathingSince == nil)) { timeline in
            let date = timeline.date
            let pose = ScribbleHeartDrawing.Pose(
                valence: shown(valence, at: date),
                target: shown(target, at: date),
                time: reduceMotion ? 0 : date.timeIntervalSince(start),
                breath: calmed ? 0 : (breathingSince.map { MoodBreath.phase(since: $0, now: date) } ?? 0),
                pulses: reduceMotion ? [] : (0..<ScribbleHeartDrawing.pulseCount).map { i in
                    haptics?.pulse(at: date.addingTimeInterval(-Double(i) * ScribbleHeartDrawing.pulseStep)) ?? 0
                },
                appear: reduceMotion ? .infinity : date.timeIntervalSince(start),
                touches: reduceMotion ? [] : touches.map { .init(x: $0.x, y: $0.y, age: date.timeIntervalSince($0.at)) },
                surges: surges
            )
            Canvas { context, size in
                ScribbleHeartDrawing.draw(in: &context, size: size, pose: pose)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { touch($0.location) }
                .onEnded { _ in lastTouch = nil }
        )
        .accessibilityHidden(true)
        .onChange(of: breathingSince) { old, new in
            if new != nil {
                calmFrom = target
                interrupted = nil
            } else if let old {
                interrupted = (MoodCalm.valence(from: calmFrom ?? target, since: old, now: .now), .now)
                calmFrom = nil
            }
        }
    }

    /// 画哪个愉悦度：平时就是 `value`；呼吸引导时从他选的那档慢慢褪向平常、做完了停在平常；
    /// 被打断后从褪到的地方回来，不跳
    private func shown(_ value: Double, at date: Date) -> Double {
        if let breathingSince {
            return calmed ? MoodCalm.target : MoodCalm.valence(from: calmFrom ?? value, since: breathingSince, now: date)
        }
        if let interrupted, !reduceMotion {
            let x = min(max(date.timeIntervalSince(interrupted.at) / MoodCalm.returnDuration, 0), 1)
            return interrupted.valence + (value - interrupted.valence) * x * x * (3 - 2 * x)
        }
        return value
    }

    /// 手指碰到心。按住划动时每划过一小段（24pt）记一下，划过去留下一路涟漪
    private func touch(_ location: CGPoint) {
        if let lastTouch, hypot(location.x - lastTouch.x, location.y - lastTouch.y) < 24 { return }
        lastTouch = location
        let now = Date.now
        // 涌完的（3 秒以上）记进每根线的累计里，不再逐帧算；最多同时算 20 下
        while let oldest = touches.first, now.timeIntervalSince(oldest.at) > 3 || touches.count >= 20 {
            let weights = ScribbleHeartDrawing.surge(at: oldest.x, oldest.y)
            for i in surges.indices where i < weights.count { surges[i] += weights[i] }
            touches.removeFirst()
        }
        let p = ScribbleHeartDrawing.heartCoordinates(of: location, in: canvasSize)
        touches.append((p.x, p.y, now))
        haptics?.touch()
    }
}
