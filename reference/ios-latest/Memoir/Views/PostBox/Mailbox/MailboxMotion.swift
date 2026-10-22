import Foundation

/// 邮筒怎么动（2026-10-20 产品定）：左右甩出去的滑行、投信时弹回正面、上下晃完摆回直立。
///
/// 和选本子的转盘（`CarouselMotion`）一个思路：开始那一刻把参数定好，之后每一帧按时间算位置，
/// 不靠一帧帧累加 —— 掉帧也不会跑偏。角度的单位是弧度，不取模，一直往一个方向转会越来越大。
nonisolated enum MailboxMotion {

    /// 甩出去之后的滑行：铁家伙沉，带着惯性越转越慢，**转到哪停在哪**（不对齐任何位置，产品定）。
    ///
    /// 2026-10-20 真机上调了两回：第一版（τ 1.1 / 摩擦 1.6 / 封顶 14）一甩将近两圈，「重物不该滑一下转这么多圈」；
    /// 第二版（0.4 / 3.5 / 10）一甩才半圈，又嫌太沉，「最起码滑一下能转一圈转回来」。
    /// 现在：用力一甩约一圈多一点（≈410°，1.6 秒停住），中等力度半圈多（≈200°）。
    ///
    /// 摩擦和转盘一样是两份：跟速度成正比的一份（快的时候减得快）+ 恒定的一份（慢下来以后在有限的时间里停住）。
    /// v' = −v/τ − a 的解：x(t) = τ(v₀ + aτ)(1 − e^(−t/τ)) − aτ·t，停在 T = τ·ln(1 + v₀/(aτ))
    struct Spin {
        /// 粘滞那一份的时间常数（秒）。越大转得越久
        static let tau = 0.7
        /// 恒定那一份（弧度/秒²）。越大最后停得越干脆
        static let friction = 2.4
        /// 低于这个（弧度/秒）不算甩：松手就停
        static let minimumSpeed = 0.6
        /// 再快也就这么快（弧度/秒）。手指一甩通常都超过它，所以它基本决定了「用力一甩转多少」：14 → 一圈多一点
        static let maximumSpeed = 14.0

        let from: Double
        let speed: Double
        let direction: Double
        let duration: TimeInterval

        init?(from: Double, velocity: Double) {
            let speed = min(abs(velocity), Self.maximumSpeed)
            guard speed > Self.minimumSpeed else { return nil }
            self.from = from
            self.speed = speed
            direction = velocity > 0 ? 1 : -1
            duration = Self.tau * log(1 + speed / (Self.friction * Self.tau))
        }

        /// 停下来的角度
        var target: Double { position(duration) }

        func position(_ t: TimeInterval) -> Double {
            let t = min(max(t, 0), duration)
            let c = Self.friction * Self.tau
            return from + direction * (Self.tau * (speed + c) * (1 - exp(-t / Self.tau)) - c * t)
        }

        func velocity(_ t: TimeInterval) -> Double {
            guard t < duration else { return 0 }
            let c = Self.friction * Self.tau
            return direction * max(0, (speed + c) * exp(-max(t, 0) / Self.tau) - c)
        }
    }

    /// 弹簧：从 `from` 带着初速度回到 `to`。
    ///
    /// - 投信时转回正面：**Q 弹一点**（产品定，2026-10-20），冲过头一点点再回来（阻尼比 0.8，过冲不到 2%；
    ///   第一版 0.6 过冲近 10%，真机上嫌太容易弹）
    /// - 上下晃完松手：轻轻回一下就直立（阻尼比 0.65，过冲约 7%；第一版 0.4 摆两下，同样嫌弹）
    /// - 「减弱动态效果」时阻尼给到 1：不冲过头、不摆
    ///
    /// 欠阻尼：x(t) = to + e^(−ζω₀t)·(a·cos ω_d t + b·sin ω_d t)；临界阻尼：x(t) = to + (a + (v₀ + ω₀a)·t)·e^(−ω₀t)
    struct Spring {
        let to: Double
        private let a: Double
        private let b: Double
        private let omega: Double
        private let zeta: Double
        private let omegaD: Double
        private let response: Double

        /// - Parameters:
        ///   - response: 大约多久回到位（秒），越小越快
        ///   - damping: 阻尼比。1 = 不冲过头；越小摆得越多
        init(from: Double, to: Double, velocity: Double, response: Double, damping: Double) {
            self.to = to
            self.response = response
            omega = 2 * .pi / response
            zeta = min(max(damping, 0.05), 1)
            a = from - to
            if zeta < 1 {
                omegaD = omega * (1 - zeta * zeta).squareRoot()
                b = (velocity + zeta * omega * a) / omegaD
            } else {
                omegaD = 0
                b = velocity + omega * a
            }
        }

        func position(_ t: TimeInterval) -> Double {
            let t = max(t, 0)
            if zeta < 1 {
                return to + exp(-zeta * omega * t) * (a * cos(omegaD * t) + b * sin(omegaD * t))
            }
            return to + (a + b * t) * exp(-omega * t)
        }

        func velocity(_ t: TimeInterval) -> Double {
            let t = max(t, 0)
            if zeta < 1 {
                let decay = exp(-zeta * omega * t)
                let c = cos(omegaD * t), s = sin(omegaD * t)
                return decay * ((-zeta * omega * a + omegaD * b) * c + (-zeta * omega * b - omegaD * a) * s)
            }
            return (b - omega * (a + b * t)) * exp(-omega * t)
        }

        func isFinished(_ t: TimeInterval) -> Bool {
            t > response * 4 || (abs(position(t) - to) < 0.0005 && abs(velocity(t)) < 0.005)
        }
    }
}
