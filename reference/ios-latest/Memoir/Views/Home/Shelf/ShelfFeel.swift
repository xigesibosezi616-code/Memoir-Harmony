import CoreHaptics

/// 书架上拖着换位置的手感：书落进新位置的那一刻，木头书架上闷闷的「咚」一声 + 一下闷震（2026-10-17 产品定）。
///
/// 声音是 `shelf_drop`（`Scripts/make_book_sound.py`）—— 写日记前选本子的转盘**第一版**那一声：
/// 在转盘上一本接一本地响嫌闷，书落回书架上就这一下，正合适。
/// 只在顺序**真的变了**才响；放回原处不响（松手那一下轻震照旧，见 `ShelfGridView.drop()`）。
/// 引擎和信件共用一台（`LetterHaptics`），声音跟着静音键走。
@MainActor final class ShelfFeel {
    /// 书架页出现时把引擎热起来，落定那一下才不慢半拍；出现 / 消失可能不成对地来，自己记着
    private var active = false

    func start() {
        guard !active else { return }
        active = true
        LetterHaptics.acquire()
    }

    func stop() {
        guard active else { return }
        active = false
        LetterHaptics.release()
    }

    /// 书落进新位置：重而钝的一下，跟一小段余震（书板压在木板上）
    func land() {
        let h = LetterHaptics.self
        LetterHaptics.fire(LetterHaptics.Pattern(
            events: [
                h.transient(0, intensity: 0.9, sharpness: 0.15),
                h.continuous(0.005, duration: 0.06, intensity: 0.4, sharpness: 0.05),
            ],
            sound: "shelf_drop"
        ))
    }
}
