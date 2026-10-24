import SwiftUI

/// 手写的「m.」—— 桌面图标上那一笔，开场时一笔写出来，再落下句点（2026-10-24 产品定）。
///
/// 字形和 `Scripts/make_app_icon.py` 的 `STROKE` 是**同一份数据**（364 的格子，照用户手写的原图拟合）：
/// 四段三次贝塞尔当中线，沿中线盖圆，圆的半径按弧长插值 —— 一支圆头笔写出来的样子。
/// 🔴 改一处要改另一处，图标和开场才对得上
enum HandwrittenMark {
    /// 笔画整体加粗（用户在原粗细和 1.35 倍之间选了加粗）
    static let weight: CGFloat = 1.35

    /// 起笔 → 第一个尖 → 底下的折角 → 第二个尖 → 收笔的小勾。每段 [起点, 控制点, 控制点, 终点]
    static let segments: [[CGPoint]] = [
        [CGPoint(x: 66.25, y: 241.5), CGPoint(x: 89.25, y: 211.38), CGPoint(x: 136.0, y: 154.5), CGPoint(x: 174.62, y: 143.12)],
        [CGPoint(x: 174.62, y: 143.12), CGPoint(x: 175.31, y: 166.25), CGPoint(x: 161.25, y: 205.62), CGPoint(x: 163.56, y: 221.62)],
        [CGPoint(x: 163.56, y: 221.62), CGPoint(x: 194.69, y: 195.25), CGPoint(x: 219.94, y: 161.25), CGPoint(x: 248.38, y: 151.75)],
        [CGPoint(x: 248.38, y: 151.75), CGPoint(x: 249.44, y: 202.19), CGPoint(x: 249.0, y: 219.5), CGPoint(x: 257.19, y: 221.31)],
    ]
    /// 每段（起点、中点、终点）的半径，段内按弧长线性插值
    static let radii: [(start: CGFloat, mid: CGFloat, end: CGFloat)] = [
        (6.975, 8.2, 8.934), (8.934, 10.091, 10.55), (10.55, 8.553, 10.066), (10.066, 10.288, 10.297),
    ]
    static let dotCenter = CGPoint(x: 305.375, y: 228.75)
    static let dotRadius: CGFloat = 12.2 * weight

    /// 整个字（含句点、含笔画粗细）在格子里占的框，画的时候按它缩放、居中
    static let bounds = CGRect(x: 52.0, y: 128.9, width: 321.9 - 52.0, height: 255.7 - 128.9)

    struct Sample {
        let point: CGPoint
        let radius: CGFloat
        /// 从这一段起点走了多远（格子单位）
        let distance: CGFloat
    }

    /// 每段沿弧长每隔 1 格一个圆（屏幕上不到 1pt，看不出圆和圆的接缝）
    static let samples: [[Sample]] = segments.indices.map(sampleSegment)

    /// 每段的长度
    static let lengths: [CGFloat] = samples.map { $0.last?.distance ?? 0 }

    private static func sampleSegment(_ index: Int) -> [Sample] {
        let p = segments[index]
        // 先密密地取参数点、量出弧长，再按等弧长重取
        let dense = 600
        var points: [CGPoint] = []
        var cumulative: [CGFloat] = [0]
        for i in 0...dense {
            let t = CGFloat(i) / CGFloat(dense), u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            let point = CGPoint(x: a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x,
                                y: a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y)
            if let last = points.last { cumulative.append(cumulative.last! + hypot(point.x - last.x, point.y - last.y)) }
            points.append(point)
        }
        let total = cumulative.last!
        let r = radii[index]
        var result: [Sample] = []
        var j = 0
        var s: CGFloat = 0
        while true {
            let target = min(s, total)
            while j < cumulative.count - 2 && cumulative[j + 1] < target { j += 1 }
            let span = cumulative[j + 1] - cumulative[j]
            let f = span > 0 ? (target - cumulative[j]) / span : 0
            let point = CGPoint(x: points[j].x + (points[j + 1].x - points[j].x) * f,
                                y: points[j].y + (points[j + 1].y - points[j].y) * f)
            let u = target / total
            let radius = u < 0.5 ? r.start + (r.mid - r.start) * u / 0.5 : r.mid + (r.end - r.mid) * (u - 0.5) / 0.5
            result.append(Sample(point: point, radius: radius * weight, distance: target))
            if target >= total { break }
            s += 1
        }
        return result
    }

    // MARK: - 怎么写（时间表）

    /// 开场写字的时间表。🔴 **`Scripts/make_splash_sound.py` 按同一张表合成笔声**，改了这里要改那边重出声音
    enum Script {
        /// 四段各写多久（秒）。按段长的 0.8 次方分（长的那段写得快一些），合计约 0.42 秒
        /// （第一版 0.56 秒，用户真机看了嫌慢，整体压到 3/4）
        static let segmentDurations: [TimeInterval] = [0.142, 0.086, 0.113, 0.080]
        /// 段内的快慢：一段里笔先快后慢，到拐角几乎停住（真写字时笔在尖角处会顿一下）。
        /// 0 = 匀速，越接近 1 拐角停得越干脆
        static let ease: Double = 0.85
        /// 写完 m 抬笔、挪到句点的空当
        static let penLift: TimeInterval = 0.07
        /// 句点：笔尖点下去，墨在这么短的时间里洇开
        static let dotDuration: TimeInterval = 0.05
        /// 写完停一下再淡出：让人看清写好的字再进 App（0.15 秒时用户觉得「点完立刻就进去了」，多留 0.2 秒）
        static let hold: TimeInterval = 0.35

        static var writingDuration: TimeInterval { segmentDurations.reduce(0, +) }
        static var dotStart: TimeInterval { writingDuration + penLift }
        static var total: TimeInterval { dotStart + dotDuration + hold }

        /// 第几段写到了多远（格子单位）
        static func drawnLength(segment: Int, at time: TimeInterval) -> CGFloat {
            let start = segmentDurations[..<segment].reduce(0, +)
            let tau = min(max((time - start) / segmentDurations[segment], 0), 1)
            // 速度 ∝ 1 − ease·cos(2πτ)：两头慢、中间快，积分后正好从 0 走到 1
            let progress = tau - ease * sin(2 * .pi * tau) / (2 * .pi)
            return HandwrittenMark.lengths[segment] * CGFloat(progress)
        }

        /// 句点洇开到多大（0…1）
        static func dotScale(at time: TimeInterval) -> CGFloat {
            guard time >= dotStart else { return 0 }
            let x = min((time - dotStart) / dotDuration, 1)
            // 笔尖一点下去就有一小团墨，随后很快洇满，不回弹
            return CGFloat(0.4 + 0.6 * (1 - pow(1 - x, 3)))
        }
    }

    // MARK: - 画

    /// 把写到 `time` 秒时的样子画进 `size` 大小的画布（字按 `bounds` 等比铺满画布）
    static func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, ink: Color) {
        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let origin = CGPoint(x: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
                             y: (size.height - bounds.height * scale) / 2 - bounds.minY * scale)
        func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
            CGRect(x: origin.x + (center.x - radius) * scale, y: origin.y + (center.y - radius) * scale,
                   width: radius * 2 * scale, height: radius * 2 * scale)
        }

        var path = Path()
        for segment in samples.indices {
            let drawn = Script.drawnLength(segment: segment, at: time)
            guard drawn > 0 else { break }
            let line = samples[segment]
            var last: Sample?
            for sample in line {
                if sample.distance > drawn { break }
                path.addEllipse(in: circle(sample.point, sample.radius))
                last = sample
            }
            // 笔尖：落在两个取样点之间时补一个圆，写的过程才是连续的
            if let last, let next = line.first(where: { $0.distance > drawn }) {
                let f = (drawn - last.distance) / (next.distance - last.distance)
                let point = CGPoint(x: last.point.x + (next.point.x - last.point.x) * f,
                                    y: last.point.y + (next.point.y - last.point.y) * f)
                path.addEllipse(in: circle(point, last.radius + (next.radius - last.radius) * f))
            }
        }
        let dot = Script.dotScale(at: time)
        if dot > 0 {
            path.addEllipse(in: circle(dotCenter, dotRadius * dot))
        }
        context.fill(path, with: .color(ink))
    }
}

/// 开场写字的那块画布。`start` 为 nil 时什么都不画；`animated == false`（系统开了「减弱动态效果」）直接画完整的字
struct HandwritingView: View {
    let ink: Color
    let start: Date?
    var animated = true

    var body: some View {
        TimelineView(.animation(paused: start == nil || !animated)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let time = animated ? timeline.date.timeIntervalSince(start) : .infinity
                HandwrittenMark.draw(in: &context, size: size, time: time, ink: ink)
            }
        }
        .aspectRatio(HandwrittenMark.bounds.width / HandwrittenMark.bounds.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
