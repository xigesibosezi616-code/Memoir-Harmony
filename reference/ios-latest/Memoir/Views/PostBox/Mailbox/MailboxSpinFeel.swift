import CoreHaptics
import QuartzCore

/// 拨邮筒时手里的感觉：帽檐那圈铆钉每转过正面一颗，轻轻「嗒」一下（2026-10-20 产品定，选的「每转过一颗铆钉轻轻一下」）。
///
/// 只震不响 —— 声音留给戳邮筒的「哐」和投信。一圈 20 颗（和 `MailboxSurface.metal` 的 kRivetCount 一致），
/// 转得快时一下比一下轻、两下之间至少隔一点（再密就成了嗡嗡声）。
/// 数「到没到下一颗」用选本子转盘那个 `CarouselTicker`：在同一颗附近来回晃不会一直震
@MainActor final class MailboxSpinFeel {
    /// 一圈几颗铆钉
    static let rivets = 20.0
    private static var step: Double { 2 * .pi / rivets }
    /// 两下之间至少隔多久（秒）
    private static let minimumGap: CFTimeInterval = 0.04

    private var ticker = CarouselTicker()
    private var lastTick: CFTimeInterval = 0

    func start() {
        LetterHaptics.acquire()
    }

    func stop() {
        LetterHaptics.release()
    }

    /// 角度被直接改了（回正面、折回一圈以内）：不震，从这里重新数
    func reset(_ yaw: Double) {
        ticker.reset(Int((yaw / Self.step).rounded()))
    }

    /// 转到了 `yaw`：有一颗新的铆钉到了正面就「嗒」。`speed` 是此刻的角速度（弧度/秒）
    func track(_ yaw: Double, speed: Double) {
        guard ticker.reached(yaw / Self.step) else { return }
        let now = CACurrentMediaTime()
        guard now - lastTick >= Self.minimumGap else { return }
        lastTick = now
        // 慢慢拨时一颗一颗实一点；甩起来一串连着，轻一点
        let fast = Float(min(1, abs(speed) / 10))
        LetterHaptics.fire(LetterHaptics.Pattern(events: [
            LetterHaptics.transient(0, intensity: 0.5 - 0.25 * fast, sharpness: 0.62),
        ]))
    }
}
