import Foundation

/// 选本子的转盘怎么动：甩出去的滑行、松手后的归位、点旁边那本时转过去。
///
/// 都是「位置 = 时间的函数」：开始那一刻把参数定好，之后每一帧按时间算位置（`NotebookCarousel` 的 TimelineView），
/// 不靠一帧帧累加 —— 掉帧也不会跑偏，停在哪一本开始那一刻就定了。
///
/// 位置的单位是「本」：0 = 第一本（全部日记）在正中，1 = 下一本在正中……不取模，一直往一个方向转会越来越大。
nonisolated struct CarouselMotion {
    enum Kind {
        /// 甩出去：带着惯性转，越转越慢，正好停在一本上
        case glide(Glide)
        /// 松手时没什么速度（或者转着的时候点了一下）：就近落到一本上
        case settle(Settle)
        /// 点了旁边那本、新建好了转过去：平平稳稳转过去
        case tween(Tween)
    }

    let kind: Kind
    let start: Date

    /// 停下来的位置（一定是整数）
    var target: Double {
        switch kind {
        case .glide(let g): return g.target
        case .settle(let s): return s.to
        case .tween(let t): return t.to
        }
    }

    func position(at date: Date) -> Double {
        let t = max(0, date.timeIntervalSince(start))
        switch kind {
        case .glide(let g): return g.position(t)
        case .settle(let s): return s.position(t)
        case .tween(let w): return w.position(t)
        }
    }

    /// 速度（本/秒，带方向）—— 「笃」的轻重跟着它
    func velocity(at date: Date) -> Double {
        let t = max(0, date.timeIntervalSince(start))
        switch kind {
        case .glide(let g): return g.velocity(t)
        case .settle(let s): return s.velocity(t)
        case .tween(let w): return w.velocity(t)
        }
    }

    func isFinished(at date: Date) -> Bool {
        let t = max(0, date.timeIntervalSince(start))
        switch kind {
        case .glide(let g): return t >= g.duration
        case .settle(let s): return s.isFinished(t)
        case .tween(let w): return t >= w.duration
        }
    }
}

// MARK: - 甩出去

extension CarouselMotion {
    /// 甩出去之后的滑行。
    ///
    /// 摩擦 = 跟速度成正比的一份（粘滞：快的时候减得快）+ 恒定的一份（像书在木板上蹭：慢下来以后也会在有限的时间里停住）。
    /// 只有前一份的话（指数衰减，`UIScrollView` 那种）最后一本要蹭好几秒才到位，最后那声「笃」拖得老长；
    /// 只有后一份的话轻轻一甩转不动几本。
    ///
    /// 要正好停在一本上：先算自然会停在哪，取最近的那本，再把整条轨迹在时间上压缩 / 拉长（`k`）——
    /// 起步的速度不变（接得住手指离开时的速度），走的距离正好到那本。
    /// 推一下：v' = −v/τ − a 的解是 x(t) = τ(v₀ + aτ)(1 − e^(−t/τ)) − aτ·t，停在 T = τ·ln(1 + v₀/(aτ))；
    /// 把 τ 换成 τ/k、a 换成 a·k，aτ 不变，起步速度不变，距离和时间都变成原来的 1/k。
    nonisolated struct Glide {
        /// 粘滞那一份的时间常数（秒）。越大转得越久
        static let tau = 1.3
        /// 恒定那一份（本/秒²）。越大最后停得越干脆
        static let friction = 1.8
        /// 速度低于这个（本/秒）不算甩，就近落下
        static let minimumSpeed = 0.5

        let from: Double
        let target: Double
        let speed: Double
        let direction: Double
        let k: Double
        let duration: TimeInterval

        /// - Parameters:
        ///   - velocity: 手指离开时的速度（本/秒，带方向）
        ///   - range: 不首尾相接时（只有一两本）能停的范围；首尾相接传 nil
        init?(from: Double, velocity: Double, range: ClosedRange<Double>?) {
            let speed = abs(velocity)
            guard speed > Self.minimumSpeed else { return nil }
            let direction: Double = velocity > 0 ? 1 : -1
            let c = Self.friction * Self.tau
            let naturalDuration = Self.tau * log(1 + speed / c)
            let naturalDistance = Self.tau * speed - c * naturalDuration
            var target = (from + direction * naturalDistance).rounded()
            if let range { target = min(max(target, range.lowerBound), range.upperBound) }
            let distance = (target - from) * direction
            // 自然停的地方离起点不到半本、往回取整了：不是甩，就近落下
            guard distance > 0.05 else { return nil }
            let k = naturalDistance / distance
            // 差太多（比如快到头了被截住）：压缩得太狠会像撞墙，拉得太长会像卡住 —— 交给「转过去」
            guard (0.3...4).contains(k) else { return nil }
            self.from = from
            self.target = target
            self.speed = speed
            self.direction = direction
            self.k = k
            self.duration = naturalDuration / k
        }

        func position(_ t: TimeInterval) -> Double {
            guard t < duration else { return target }
            let c = Self.friction * Self.tau
            let s = t * k
            let travelled = Self.tau * (speed + c) * (1 - exp(-s / Self.tau)) - c * s
            return from + direction * travelled / k
        }

        func velocity(_ t: TimeInterval) -> Double {
            guard t < duration else { return 0 }
            let c = Self.friction * Self.tau
            return direction * max(0, (speed + c) * exp(-t * k / Self.tau) - c)
        }
    }
}

// MARK: - 就近落下

extension CarouselMotion {
    /// 就近落到一本上：临界阻尼（不过冲、不回弹），带着松手时那一点速度接上
    nonisolated struct Settle {
        /// 越小落得越快。0.09 秒大约 0.5 秒落稳
        static let tau = 0.09

        let to: Double
        private let a: Double
        private let b: Double

        init(from: Double, to: Double, velocity: Double) {
            self.to = to
            a = from - to
            // x(t) = to + (a + b·t)·e^(−t/τ)。a、b 异号时会冲过头再回来 —— 不要回弹，冲过头的那点速度不要了
            let b = velocity + a / Self.tau
            self.b = a * b < 0 ? 0 : b
        }

        func position(_ t: TimeInterval) -> Double {
            to + (a + b * t) * exp(-t / Self.tau)
        }

        func velocity(_ t: TimeInterval) -> Double {
            (b - (a + b * t) / Self.tau) * exp(-t / Self.tau)
        }

        func isFinished(_ t: TimeInterval) -> Bool {
            t > 1.2 || (abs(position(t) - to) < 0.002 && abs(velocity(t)) < 0.05)
        }
    }
}

// MARK: - 转过去

extension CarouselMotion {
    /// 平平稳稳转到某一本：缓起缓停，隔得越远转得越久（有上限）
    nonisolated struct Tween {
        let from: Double
        let to: Double
        let duration: TimeInterval

        init(from: Double, to: Double) {
            self.from = from
            self.to = to
            duration = min(1.2, 0.42 + 0.14 * abs(to - from))
        }

        func position(_ t: TimeInterval) -> Double {
            from + (to - from) * Self.ease(min(1, t / duration))
        }

        func velocity(_ t: TimeInterval) -> Double {
            guard t < duration else { return 0 }
            let u = t / duration
            let slope = u < 0.5 ? 12 * u * u : 3 * pow(2 - 2 * u, 2)
            return (to - from) * slope / duration
        }

        /// 三次缓入缓出
        private static func ease(_ u: Double) -> Double {
            u < 0.5 ? 4 * u * u * u : 1 - pow(2 - 2 * u, 3) / 2
        }
    }
}

// MARK: - 「笃」

/// 记着上一声「笃」是哪一本到了正中，判断这一刻有没有**另一本**到了正中。
///
/// 「到了」= 越过了那本的正中，或者离它不到 0.02 本（就近落下是无限逼近，等不到真越过去）。
/// 在同一本附近来回晃不会一直响；一帧里越过好几本（甩得很快）也只响一声 —— 再密就成了嗡嗡声
nonisolated struct CarouselTicker {
    private(set) var last = 0
    private static let reach = 0.02

    mutating func reset(_ index: Int) {
        last = index
    }

    mutating func reached(_ position: Double) -> Bool {
        if position >= Double(last + 1) - Self.reach {
            last = Int((position + Self.reach).rounded(.down))
            return true
        }
        if position <= Double(last - 1) + Self.reach {
            last = Int((position - Self.reach).rounded(.up))
            return true
        }
        return false
    }
}
