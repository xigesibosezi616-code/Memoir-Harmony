import SwiftUI

/// 线团爱心的样子：一百多根彩色细线一圈圈绕成一颗心。纯几何，不存状态 ——
/// 动起来的部分（时间、呼吸、跟着震动跳、呼吸时慢慢褪色）在 `ScribbleHeart`。
///
/// 线一直在流：每根线沿着心形一圈圈往前走（快慢各不相同），所以停着不动时整颗心也是活的。
/// 心情越好线越整齐：大家顺着同一个方向流、顺着同一道波起伏，还有一道波绕着心走；
/// 心情越差越乱：各起各的伏、一阵阵打结（结跟着线走）、中心错开，线和线缠在一起。
/// 手里每震一下，一道搏动从心的中间往外一圈圈传出去（里圈先跳、外圈后跳）。
///
/// 可以碰（2026-10-17 产品定）：手指碰到哪一圈，那几圈线往前一涌（流得快一阵，涌过去的不退回来）；
/// 碰到的地方荡开一圈涟漪，整颗心轻轻一跳。按住划过去，留下一路涟漪。
///
/// 滑动时不是一起变：每根线有自己的「反应快慢」，有的立刻跟上、有的慢半拍（`Pose.target` 和 `Pose.valence` 之间），
/// 整团心像被拂过一样换样子。
///
/// 坐标：心形宽 2（x -1…1），上缘约 -0.73，心尖在 1.06，y 朝下；画的时候按画布大小放大。
enum ScribbleHeartDrawing {
    /// 这一帧的样子由什么决定
    struct Pose {
        /// 慢慢跟上来的愉悦度（-1 很不愉快 … 1 很愉快）
        var valence: Double
        /// 滑杆此刻的愉悦度：反应快的线直接用它
        var target: Double
        /// 秒：线慢慢浮动
        var time: Double
        /// 呼吸 0 呼尽 … 1 吸满：吸气时心稍稍胀开
        var breath: Double
        /// 手里的震动：第 i 个 = `pulseStep × i` 秒以前那一刻有多满（0…1），心跟着跳，外圈晚一点
        var pulses: [Double]
        /// 出场后第几秒：线一根根画出来（给个大数 = 早画完了）
        var appear: Double
        /// 最近手指碰过的地方
        var touches: [Touch] = []
        /// 早先碰过、已经涌完的那几下：每根线累计往前多走了多少（弧度，按 `strands` 的顺序）
        var surges: [Double] = []
    }

    /// 手指碰了一下：碰在心形坐标里的哪儿、碰过多久了（秒）
    struct Touch {
        var x: Double
        var y: Double
        var age: Double
    }

    /// 一下碰完，碰到的那一圈最多往前涌多少（弧度）
    private static let surgeReach = 0.9
    /// 涌的快慢：大约这么多秒涌完
    private static let surgeTime = 0.6

    /// `Pose.pulses` 相邻两格隔多久
    static let pulseStep: TimeInterval = 0.025
    static let pulseCount = 8

    /// 一根线：沿着心形绕的一段
    struct Strand {
        /// 每个点在线上的位置（心形参数，开头那一刻）：此刻在心形上的位置 = 它 + 流过的
        var ts: [Double] = []
        /// 沿着心形往前流多快（弧度/秒）
        var flow = 0.15
        /// 绕在哪一圈：1 = 贴着轮廓，越小越靠里
        var scale = 1.0
        /// 这一圈的中心偏向哪（乱的时候才偏出去）
        var cx = 0.0
        var cy = 0.0
        /// 自己那道起伏：频率（一圈几个起伏）、相位、浮动快慢
        var f1 = 3.0, f2 = 6.0, f3 = 11.0
        var p1 = 0.0, p2 = 0.0, p3 = 0.0
        var w1 = 0.2, w2 = 0.3, w3 = 0.4
        /// 打结：沿线绕的小圈，一阵一阵的
        var curlFreq = 16.0, curlPhase = 0.0
        var burstFreq = 3.0, burstPhase = 0.0
        /// 乱的时候往外或往里偏多少
        var stray = 0.0
        /// 自己慢慢胀缩的相位（停着时也在浮动）
        var float = 0.0
        /// 滑动时跟得多快：1 = 立刻，0 = 最慢
        var response = 0.5
        /// 用调色板里的第几色
        var slot = 0
        var width = 1.0
        /// 出场时第几秒开始画
        var delay = 0.0
    }

    // MARK: - 线

    /// 心形曲线（经典的 16 sin³t 那条），缩到宽 2、y 朝下
    static func heart(_ t: Double) -> (x: Double, y: Double) {
        let s = sin(t)
        let x = 16 * s * s * s
        let y = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))
        return (x / 16, y / 16)
    }

    /// 一圈一圈往里缩时围着的点
    private static let middle = (x: 0.0, y: 0.12)

    /// 从 `middle` 往各个方向（0 = 正上，顺时针）到心形边缘有多远：用来算手指碰在第几圈
    private static let outline: [Double] = {
        var table = [Double](repeating: 0, count: 720)
        for i in 0..<8192 {
            let p = heart(2 * .pi * Double(i) / 8192)
            let dx = p.x - middle.x
            let dy = p.y - middle.y
            let index = Int((atan2(dx, -dy) + .pi) / (2 * .pi) * 720) % 720
            table[index] = max(table[index], (dx * dx + dy * dy).squareRoot())
        }
        for i in 0..<720 where table[i] == 0 {
            table[i] = max(table[(i + 719) % 720], table[(i + 1) % 720])
        }
        return table
    }()

    /// 心形坐标里的一点在第几圈（0 = 正中，1 = 轮廓上）
    private static func ring(_ x: Double, _ y: Double) -> Double {
        let dx = x - middle.x
        let dy = y - middle.y
        let index = Int((atan2(dx, -dy) + .pi) / (2 * .pi) * 720) % 720
        return (dx * dx + dy * dy).squareRoot() / max(outline[index], 0.05)
    }

    /// 画布上心的大小和位置
    static func layout(in size: CGSize) -> (unit: Double, originX: Double, originY: Double) {
        let unit = min(size.width * 0.40, size.height * 0.36)
        return (unit, size.width / 2, size.height * 0.5 - 0.165 * unit)
    }

    /// 画布上的一点 → 心形坐标
    static func heartCoordinates(of location: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        let l = layout(in: size)
        guard l.unit > 0 else { return (0, 0) }
        return ((location.x - l.originX) / l.unit, (location.y - l.originY) / l.unit)
    }

    /// 碰在 (x, y)，这一下涌完以后每根线往前多走了多少（弧度）：碰在哪一圈，那一圈附近的线涌得最多
    static func surge(at x: Double, _ y: Double) -> [Double] {
        let r = ring(x, y)
        return strands.map { surge(of: $0, ring: r) }
    }

    private static func surge(of strand: Strand, ring r: Double) -> Double {
        guard r < 1.35 else { return 0 }   // 碰在心外面
        let d = (strand.scale - r) / 0.1
        return surgeReach * exp(-d * d)
    }

    /// 心形曲线查表（4096 格，线性插值）：线在流，每帧每个点都要重新取位置，直接算三角函数太贵
    private static let heartTable: [(x: Double, y: Double)] = (0..<4096).map { heart(2 * .pi * Double($0) / 4096) }

    private static func heartPoint(_ t: Double) -> (x: Double, y: Double) {
        var u = t / (2 * .pi) * 4096
        u -= (u / 4096).rounded(.down) * 4096
        let i = min(Int(u), 4095)
        let f = u - Double(i)
        let a = heartTable[i]
        let b = heartTable[(i + 1) & 4095]
        return (a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f)
    }

    /// 固定种子：每次打开都是同一颗心
    static let strands: [Strand] = {
        var rng = SplitMix(seed: 20261017)
        return (0..<190).map { _ in
            var s = Strand()
            // 四成贴着轮廓绕（心的形状靠它们撑起来），其余从外到心正中均匀填满 ——
            // 圈的大小均匀分布，线的疏密才处处一样（是实心，不是中间空个心形）
            s.scale = rng.unit() < 0.4 ? 0.86 + 0.16 * rng.unit() : 0.04 + 0.82 * rng.unit()
            let span = 2 * Double.pi * (0.55 + 0.9 * rng.unit())
            let start = 2 * Double.pi * rng.unit()
            // 小圈短，点也少些
            let count = max(24, Int(span / (2 * .pi) * 170 * max(s.scale, 0.3)))
            s.ts = (0..<count).map { start + span * Double($0) / Double(count - 1) }
            // 一圈要 26～63 秒：慢，但一直在走
            s.flow = 0.10 + 0.14 * rng.unit()
            s.cx = 0.05 * (rng.unit() - 0.5)
            s.cy = 0.05 * (rng.unit() - 0.5)
            s.f1 = 2 + 2 * rng.unit()
            s.f2 = 5 + 3 * rng.unit()
            s.f3 = 9 + 4 * rng.unit()
            s.p1 = 2 * .pi * rng.unit()
            s.p2 = 2 * .pi * rng.unit()
            s.p3 = 2 * .pi * rng.unit()
            s.w1 = 0.15 + 0.3 * rng.unit()
            s.w2 = 0.15 + 0.3 * rng.unit()
            s.w3 = 0.15 + 0.3 * rng.unit()
            s.curlFreq = 12 + 8 * rng.unit()
            s.curlPhase = 2 * .pi * rng.unit()
            s.burstFreq = 2 + 3 * rng.unit()
            s.burstPhase = 2 * .pi * rng.unit()
            s.stray = 2 * rng.unit() - 1
            s.float = 2 * .pi * rng.unit()
            s.response = rng.unit()
            s.slot = Int(rng.unit() * 6) % 6
            s.width = 0.8 + 0.6 * rng.unit()
            s.delay = 0.9 * rng.unit()
            return s
        }
    }()

    // MARK: - 颜色

    /// 九档各六色（顺序同 `MoodLevel`）：愉快那头暖而鲜，不悲不喜是一整套彩虹，不愉快那头冷、发灰
    private static let palettes: [[SIMD3<Double>]] = [
        [SIMD3(0.42, 0.45, 0.58), SIMD3(0.50, 0.48, 0.58), SIMD3(0.38, 0.46, 0.55),
         SIMD3(0.55, 0.55, 0.60), SIMD3(0.45, 0.42, 0.52), SIMD3(0.60, 0.58, 0.62)],
        [SIMD3(0.44, 0.47, 0.66), SIMD3(0.52, 0.49, 0.65), SIMD3(0.39, 0.52, 0.62),
         SIMD3(0.57, 0.57, 0.63), SIMD3(0.47, 0.43, 0.57), SIMD3(0.59, 0.60, 0.66)],
        [SIMD3(0.45, 0.50, 0.75), SIMD3(0.55, 0.50, 0.72), SIMD3(0.40, 0.58, 0.70),
         SIMD3(0.60, 0.60, 0.66), SIMD3(0.50, 0.45, 0.62), SIMD3(0.58, 0.62, 0.70)],
        [SIMD3(0.62, 0.60, 0.86), SIMD3(0.45, 0.68, 0.85), SIMD3(0.42, 0.75, 0.75),
         SIMD3(0.70, 0.55, 0.80), SIMD3(0.55, 0.65, 0.80), SIMD3(0.75, 0.72, 0.70)],
        [SIMD3(0.93, 0.50, 0.66), SIMD3(0.95, 0.80, 0.40), SIMD3(0.55, 0.80, 0.50),
         SIMD3(0.38, 0.75, 0.82), SIMD3(0.50, 0.62, 0.92), SIMD3(0.68, 0.56, 0.90)],
        [SIMD3(0.96, 0.45, 0.64), SIMD3(0.97, 0.82, 0.34), SIMD3(0.52, 0.84, 0.44),
         SIMD3(0.32, 0.80, 0.86), SIMD3(0.48, 0.64, 0.98), SIMD3(0.72, 0.52, 0.96)],
        [SIMD3(0.96, 0.42, 0.62), SIMD3(0.99, 0.56, 0.45), SIMD3(0.96, 0.80, 0.30),
         SIMD3(0.50, 0.82, 0.40), SIMD3(0.30, 0.78, 0.85), SIMD3(0.66, 0.50, 0.95)],
        [SIMD3(0.97, 0.39, 0.60), SIMD3(1.00, 0.53, 0.42), SIMD3(0.98, 0.73, 0.29),
         SIMD3(0.98, 0.81, 0.28), SIMD3(0.80, 0.48, 0.82), SIMD3(0.52, 0.82, 0.38)],
        [SIMD3(0.98, 0.36, 0.58), SIMD3(1.00, 0.50, 0.40), SIMD3(1.00, 0.66, 0.28),
         SIMD3(0.98, 0.82, 0.26), SIMD3(0.95, 0.45, 0.70), SIMD3(0.55, 0.82, 0.35)],
    ]

    /// 档位正中（0、±2/9、±4/9、±6/9、±8/9）正好是那一档的颜色，之间平滑过渡
    private static func color(slot: Int, valence: Double) -> SIMD3<Double> {
        let last = Double(palettes.count - 1)
        let k = min(max((valence + 1) / 2 * Double(palettes.count) - 0.5, 0), last)
        let i = min(Int(k), palettes.count - 2)
        let w = smooth(k - Double(i))
        return palettes[i][slot] + (palettes[i + 1][slot] - palettes[i][slot]) * w
    }

    // MARK: - 画

    static func draw(in context: inout GraphicsContext, size: CGSize, pose: Pose) {
        let time = pose.time
        let (unit, originX, originY) = layout(in: size)
        // 每一下碰：在第几圈、涌到哪一步了、涟漪还剩多少
        let touches = pose.touches.map { touch in
            (touch: touch, ring: ring(touch.x, touch.y), surged: 1 - exp(-touch.age / surgeTime), ripple: exp(-touch.age / 0.7))
        }

        for (index, strand) in strands.enumerated() {
            let shown = min(max((pose.appear - strand.delay) / 0.6, 0), 1)
            guard shown > 0 else { continue }
            let n = max(2, Int(Double(strand.ts.count) * (1 - (1 - shown) * (1 - shown))))

            // 这根线眼下按哪个心情画：反应快的跟着滑杆，慢的跟着慢慢追上来的那个
            let v = min(max(pose.valence + (pose.target - pose.valence) * strand.response, -1), 1)
            let neg = max(0, -v)
            let pos = max(0, v)
            // 乱的程度：很愉快 0.05 · 平常 0.25 · 很不愉快 1
            let mess = 0.25 - 0.2 * pos + 0.75 * neg
            let wobble = 0.015 + 0.13 * mess
            let curl = 0.07 * mess * mess.squareRoot()
            let together = 1 - 0.85 * mess
            let spread = 1 + 2.5 * mess
            let radius = strand.scale * (1 + 0.12 * mess * mess * strand.stray)

            // 跳：里圈先跳、外圈晚一点（像一道搏动往外传）；吸气时整颗心胀一点；停着也自己慢慢浮
            let lag = min(max((strand.scale - 0.04) / 0.98, 0), 1) * Double(pose.pulses.count - 1)
            let i0 = min(Int(lag), max(0, pose.pulses.count - 2))
            let beat = pose.pulses.isEmpty ? 0 : (pose.pulses.count == 1 ? pose.pulses[0]
                : pose.pulses[i0] + (pose.pulses[i0 + 1] - pose.pulses[i0]) * (lag - Double(i0)))
            // 碰一下，心也轻轻一跳（同样里圈先、外圈后）；碰到的那几圈往前一涌
            var poke = 0.0
            var advance = index < pose.surges.count ? pose.surges[index] : 0
            for k in touches {
                let age = k.touch.age - 0.12 * strand.scale
                if age > 0 && age < 1 { poke += exp(-age / 0.14) * min(1, age / 0.03) }
                advance += surge(of: strand, ring: k.ring) * k.surged
            }
            let swell = 1 + beat * (0.025 + 0.06 * pos + 0.025 * neg)
                + 0.045 * pose.breath
                + (0.008 + 0.01 * pos) * sin(0.6 * time + strand.float)
                + 0.03 * min(poke, 1.5)

            let drift = strand.flow * time + advance
            var path = Path()
            for j in 0..<n {
                let a = strand.ts[j]     // 线自己身上的位置：结跟着线走
                let t = a + drift        // 此刻流到了心形上的哪儿
                let h = heartPoint(t)
                // 起伏：一起的那道波（整齐）+ 自己的（乱）+ 愉快时一道绕着心走的波
                let shared = 0.6 * sin(3 * t + 0.5 * time) + 0.4 * sin(5 * t - 0.35 * time + 1.3)
                let own = 0.55 * sin(strand.f1 * t + strand.p1 + strand.w1 * time)
                    + 0.30 * sin(strand.f2 * t + strand.p2 - strand.w2 * time)
                    + 0.15 * sin(strand.f3 * t + strand.p3 + strand.w3 * time)
                let travel = sin(4 * t - 1.6 * time + 0.6)
                let r = radius * (1 + wobble * (together * shared + (1 - together) * own) + 0.035 * pos * travel) * swell
                var x = strand.cx * spread + h.x * r
                var y = middle.y + strand.cy * spread + (h.y - middle.y) * r
                // 打结：沿线一阵一阵地绕小圈
                if curl > 0.0005 {
                    let burst = max(0, sin(strand.burstFreq * a + strand.burstPhase + 0.3 * time))
                    let c = curl * (0.25 + 0.75 * burst * burst)
                    x += c * cos(strand.curlFreq * a + strand.curlPhase + 0.8 * time)
                    y += c * sin(strand.curlFreq * a + strand.curlPhase + 0.8 * time)
                }
                // 碰到的地方荡开一圈圈涟漪：从手指那儿往外推
                for k in touches where k.ripple > 0.02 {
                    let dx = x - k.touch.x
                    let dy = y - k.touch.y
                    let d2 = dx * dx + dy * dy
                    guard d2 < 0.2 else { continue }
                    let d = d2.squareRoot() + 0.0001
                    let wave = 0.05 * exp(-d2 / 0.04) * k.ripple * sin(18 * d - 11 * k.touch.age)
                    x += dx / d * wave
                    y += dy / d * wave
                }
                let point = CGPoint(x: originX + x * unit, y: originY + y * unit)
                if j == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            let rgb = color(slot: strand.slot, valence: v)
            context.stroke(path,
                           with: .color(Color(red: rgb.x, green: rgb.y, blue: rgb.z, opacity: 0.88 - 0.12 * neg)),
                           style: StrokeStyle(lineWidth: strand.width, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: - 小工具

    private static func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// 固定种子的随机数（SplitMix64）
    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func unit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }
    }
}
