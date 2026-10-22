import CoreHaptics
import QuartzCore

/// 选本子时的手感：每过一本响一声木头声 + 震一下（2026-10-17 产品定：每过一本就响一声；声音听过三种试听后定了小木块轻叩的「笃」）。
///
/// 声音是 `Scripts/make_book_sound.py` 合成的三份 `book_knock_1…3`，轮着放，连着转过去是一串木头声，不是同一下复读。
/// 引擎和信件共用一台（`LetterHaptics`），声音跟着静音键走。
@MainActor final class NotebookPickerFeel {
    private var ticker = CarouselTicker()
    private var nextSound = 0
    private var lastKnock: CFTimeInterval = 0

    /// 两声之间至少隔多久（秒）。甩得很快时一秒能过十几本，再密就成了嗡嗡声
    private static let minimumGap: CFTimeInterval = 0.045

    func start() {
        LetterHaptics.acquire()
    }

    func stop() {
        LetterHaptics.release()
    }

    /// 正中换了一本但不是转过去的（日记本列表变了，重新对齐）：不响，从这本重新数
    func reset(_ index: Int) {
        ticker.reset(index)
    }

    /// 位置变了：有另一本到了正中就「笃」。`speed` 是此刻的速度（本/秒）
    func track(_ position: Double, speed: Double) {
        guard ticker.reached(position) else { return }
        knock(speed: abs(speed))
    }

    /// 转得快时轻一点（一串连着响，太重会吵），慢下来的最后几本重一点 —— 落定的那一下要实
    private func knock(speed: Double) {
        let now = CACurrentMediaTime()
        guard now - lastKnock >= Self.minimumGap else { return }
        lastKnock = now
        nextSound = (nextSound + 1) % 3

        let fast = Float(min(1, speed / 12))
        let h = LetterHaptics.self
        LetterHaptics.fire(LetterHaptics.Pattern(
            events: [
                // 闷闷的一下：锐度低
                h.transient(0, intensity: 0.8 - 0.3 * fast, sharpness: 0.18),
                h.continuous(0.005, duration: 0.04, intensity: 0.35 - 0.15 * fast, sharpness: 0.05),
            ],
            sound: "book_knock_\(nextSound + 1)",
            volume: 0.8 - 0.25 * fast
        ))
    }
}
