import SwiftUI

/// 邮筒页上那个邮筒：左右拨着转、上下拨着晃，点一下是「戳」（2026-10-20 产品定）。
///
/// - 左右：手指按住筒面跟着走（正面那一点跟手），松手带惯性越转越慢、转到哪停在哪（`MailboxMotion.Spin`）；
///   帽檐的铆钉每转过正面一颗「嗒」一下（`MailboxSpinFeel`）
/// - 上下：小幅前后晃（最多 9°，越往外拨越拨不动），松手轻轻摆一下回到直立 —— 跟着手，灵动一点
/// - 点一下（没在转的时候）：戳邮筒，翻板「哐」。**点邮筒不再投信**（容易误触，产品定）—— 投信是把下面那叠信推进投信口
/// - 转着的时候按一下：当场停住，不算戳
/// - 投信、手里托着信往上推的时候：上锁，并且立刻弹回正面（Q 弹一点）—— 信要对准投信口
/// - 离开邮筒页再回来：总是正面，不记停下的角度
struct MailboxStage: View {
    let imageName: String
    let isLocked: Bool
    /// 每变一次就弹回正面
    let frontRequest: Int
    /// 量邮筒图位置用的坐标空间（投信口按它算）
    let space: String
    let onFrame: (CGRect) -> Void
    let onPoke: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var yaw = 0.0
    @State private var spin: YawMotion?
    @State private var pitch = 0.0
    @State private var sway: PitchMotion?
    @State private var drag: DragStart?
    /// 筒身半径（点）：手指拨多远转多少
    @State private var radius: CGFloat = 50
    @State private var feel = MailboxSpinFeel()

    /// 前后最多倾多少（弧度）
    private static let maxPitch = 9.0 * .pi / 180
    /// 手指上下拨多远倾到七成多（tanh：越往外越拨不动）
    private static let pitchReach: CGFloat = 150

    var body: some View {
        TimelineView(.animation(paused: spin == nil && sway == nil)) { context in
            RotatingMailbox(
                imageName: imageName,
                yaw: spin?.position(at: context.date) ?? yaw,
                pitch: sway?.position(at: context.date) ?? pitch
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frame in
                onFrame(frame)
                radius = max(20, frame.width * MailboxGeometry.bodyRadius)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: context.date) { _, now in advance(to: now) }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onChange(of: frontRequest) { turnToFront() }
        .onChange(of: isLocked) { _, locked in if locked { drag = nil } }
        .onAppear {
            feel.start()
            resetToFront()
        }
        .onDisappear {
            feel.stop()
            resetToFront()
        }
    }

    // MARK: - 手势

    private struct DragStart {
        let yaw: Double
        let pitch: Double
        /// 按下去时邮筒正转着：这一下是「停住」，不算戳
        let caught: Bool
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isLocked else { return }
                if drag == nil { grab() }
                guard let drag else { return }
                yaw = drag.yaw + value.translation.width / radius
                // 往下拨 = 顶朝你倾过来
                let lean = Self.maxPitch * tanh(value.translation.height / Self.pitchReach)
                pitch = min(Self.maxPitch, max(-Self.maxPitch, drag.pitch - lean))
                feel.track(yaw, speed: value.velocity.width / radius)
            }
            .onEnded { value in
                guard let start = drag else { return }
                drag = nil
                guard !isLocked else { return }
                let moved = abs(value.translation.width) > 6 || abs(value.translation.height) > 6
                if moved {
                    if !reduceMotion, let glide = MailboxMotion.Spin(from: yaw, velocity: value.velocity.width / radius) {
                        spin = YawMotion(kind: .spin(glide), start: .now)
                    }
                    // 手指上下的速度换成倾角的速度（tanh 的导数），带着它摆回去
                    let u = tanh(value.translation.height / Self.pitchReach)
                    let speed = -Self.maxPitch * (1 - u * u) * value.velocity.height / Self.pitchReach
                    swayBack(velocity: min(3, max(-3, speed)))
                } else {
                    if !start.caught { onPoke() }
                    swayBack(velocity: 0)
                }
            }
    }

    /// 按下：正在转、正在摆的话当场停住，从停住的地方接着拨
    private func grab() {
        let now = Date.now
        var caught = false
        if let spin {
            yaw = spin.position(at: now)
            caught = abs(spin.velocity(at: now)) > 1
            self.spin = nil
        }
        if let sway {
            pitch = sway.position(at: now)
            self.sway = nil
        }
        drag = DragStart(yaw: yaw, pitch: pitch, caught: caught)
    }

    // MARK: - 动

    /// 每一帧：铆钉到没到、停没停
    private func advance(to now: Date) {
        if let spin {
            feel.track(spin.position(at: now), speed: spin.velocity(at: now))
            if spin.isFinished(at: now) {
                self.spin = nil
                // 折回一圈以内：转了很多圈以后数也不会越来越大（样子不变）
                yaw = spin.target.remainder(dividingBy: 2 * .pi)
                feel.reset(yaw)
            }
        }
        if let sway, sway.isFinished(at: now) {
            self.sway = nil
            pitch = 0
        }
    }

    /// 松手后摆回直立：轻轻摆一下（「减弱动态效果」时不摆）
    private func swayBack(velocity: Double) {
        guard abs(pitch) > 0.0005 || abs(velocity) > 0.01 else {
            pitch = 0
            return
        }
        sway = PitchMotion(
            spring: .init(from: pitch, to: 0, velocity: velocity, response: 0.5, damping: reduceMotion ? 1 : 0.65),
            start: .now
        )
    }

    /// 投信：立刻转回正面，Q 弹一点（转到最近的那个正面，不倒着转好几圈）
    private func turnToFront() {
        let now = Date.now
        drag = nil
        let current = spin?.position(at: now) ?? yaw
        let velocity = spin?.velocity(at: now) ?? 0
        let front = (current / (2 * .pi)).rounded() * 2 * .pi
        yaw = current
        if abs(current - front) < 0.001 && abs(velocity) < 0.01 {
            spin = nil
            yaw = front
        } else {
            spin = YawMotion(
                kind: .spring(.init(from: current, to: front, velocity: velocity, response: 0.45,
                                    damping: reduceMotion ? 1 : 0.8)),
                start: now
            )
        }
        let lean = sway?.position(at: now) ?? pitch
        pitch = lean
        if abs(lean) > 0.0005 {
            sway = PitchMotion(spring: .init(from: lean, to: 0, velocity: 0, response: 0.4, damping: reduceMotion ? 1 : 0.8),
                               start: now)
        }
    }

    /// 离开邮筒页（换 tab、进信箱、去地图）：回到正面，下次进来看到的是正面
    private func resetToFront() {
        spin = nil
        sway = nil
        drag = nil
        yaw = 0
        pitch = 0
        feel.reset(0)
    }
}

/// 左右转的运动：甩出去的滑行，或者弹回正面
private struct YawMotion {
    enum Kind {
        case spin(MailboxMotion.Spin)
        case spring(MailboxMotion.Spring)
    }

    let kind: Kind
    let start: Date

    func position(at date: Date) -> Double {
        let t = date.timeIntervalSince(start)
        switch kind {
        case .spin(let s): return s.position(t)
        case .spring(let s): return s.position(t)
        }
    }

    func velocity(at date: Date) -> Double {
        let t = date.timeIntervalSince(start)
        switch kind {
        case .spin(let s): return s.velocity(t)
        case .spring(let s): return s.velocity(t)
        }
    }

    func isFinished(at date: Date) -> Bool {
        let t = date.timeIntervalSince(start)
        switch kind {
        case .spin(let s): return t >= s.duration
        case .spring(let s): return s.isFinished(t)
        }
    }

    /// 停下来的角度
    var target: Double {
        switch kind {
        case .spin(let s): return s.target
        case .spring(let s): return s.to
        }
    }
}

/// 前后晃的运动：摆回直立
private struct PitchMotion {
    let spring: MailboxMotion.Spring
    let start: Date

    func position(at date: Date) -> Double { spring.position(date.timeIntervalSince(start)) }
    func isFinished(at date: Date) -> Bool { spring.isFinished(date.timeIntervalSince(start)) }
}
