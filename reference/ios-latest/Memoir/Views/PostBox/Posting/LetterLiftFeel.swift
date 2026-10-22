import CoreHaptics
import Foundation

/// 把那叠信往上推进投信口时手里的感觉（2026-10-20 产品定：推的时候要有由下往上的震动，整个过程配音效）。
///
/// 2026-10-20 第三版：**信封跟着手装**（推到哪装到哪，拉回来倒着展开），推到邮筒半腰封舌合上，松手 / 推到投信口就寄。
///
/// | 时刻 | 震动 | 声音 |
/// |---|---|---|
/// | 拿起来 | 轻轻一下 | 纸被拈起来的一点沙沙 |
/// | 往上推的一路 | 一段持续的震动，**越往上越紧、越亮**（锐度跟着高度涨）；推得快重、停住几乎没有 | 纸在空中走的风声，音调跟着高度往上走，响度跟着手速 |
/// | 信纸装到底 | 轻轻一顿 | 「嗒」 |
/// | 封舌合上（松手就寄） | 软软一拍 | 「啪」（`LetterPostingFeel.flapPat`） |
/// | 拉回来、封舌又翻开 | 很轻一下 | — |
/// | 没推到就松手 | 软软一下：信落回桌上 | 纸落下的「噗」 |
///
/// 松手寄出之后是投信的后半截（`LetterPostingFeel.playTail`）。声音由 `Scripts/make_post_sound.py` 生成，
/// 引擎全 App 共用一台（`LetterHaptics`）
@MainActor final class LetterLiftFeel {
    private var player: CHHapticAdvancedPatternPlayer?
    /// 手速平滑一下：DragGesture 报的速度一帧一跳，直接拿来调响度会一顿一顿的
    private var speed = 0.0

    /// 循环那一段多长（秒）。一次推信很少超过两秒，6 秒一轮基本不会接缝
    private static let loopLength: TimeInterval = 6

    func prepare() {
        LetterHaptics.acquire()
    }

    func stop() {
        stopLoop()
        LetterHaptics.release()
    }

    /// 拿起来了
    func begin() {
        stopLoop()
        speed = 0
        let h = LetterHaptics.self
        LetterHaptics.fire(LetterHaptics.Pattern(
            events: [h.transient(0, intensity: 0.35, sharpness: 0.3)],
            sound: "letter_pick_up", volume: 0.8
        ))
        player = LetterHaptics.loop(LetterHaptics.Pattern(
            events: [h.continuous(0, duration: Self.loopLength, intensity: 0.6, sharpness: 0.3)],
            sound: "letter_lift_loop", volume: 0.9
        ), loopEnd: Self.loopLength)
        send(intensity: 0, sharpness: -0.2, volume: 0, pitch: -0.3)
    }

    /// 推到哪了：`progress` 从那叠信原来的位置（0）到投信口跟前（1）；`velocity` 是手指的速度（点/秒）
    func update(progress: Double, velocity: CGSize) {
        let raw = (velocity.width * velocity.width + velocity.height * velocity.height).squareRoot()
        speed += (raw - speed) * 0.25
        let moving = min(1, speed / 900)
        let p = min(max(progress, 0), 1)
        send(
            intensity: Float(moving * (0.45 + 0.55 * p)),
            // 由下往上：越往上越紧、越亮
            sharpness: Float(-0.2 + 0.6 * p),
            volume: Float(0.15 + 0.85 * moving),
            pitch: Float(-0.3 + 0.75 * p)
        )
    }

    /// 信纸装到信封底了
    func tucked() {
        let h = LetterHaptics.self
        LetterHaptics.fire(LetterHaptics.Pattern(
            events: [h.transient(0, intensity: 0.32, sharpness: 0.3)],
            sound: "letter_tuck", volume: 0.8
        ))
    }

    /// 封舌合上了：到这儿松手就寄
    func flapClosed() {
        LetterHaptics.fire(LetterPostingFeel.flapPat)
    }

    /// 拉回来，封舌又翻开了
    func flapReopened() {
        LetterHaptics.fire(LetterHaptics.Pattern(events: [LetterHaptics.transient(0, intensity: 0.2, sharpness: 0.4)]))
    }

    /// 松手。`posted` = 寄出去了（接着放投信那一段）；否则信落回桌上
    func end(posted: Bool) {
        stopLoop()
        guard !posted else { return }
        let h = LetterHaptics.self
        LetterHaptics.fire(LetterHaptics.Pattern(
            events: [
                h.transient(0, intensity: 0.4, sharpness: 0.15),
                h.continuous(0.01, duration: 0.12, intensity: 0.2, sharpness: 0.05),
            ],
            curves: [h.curve(start: 0.01, points: [(0, 1), (0.12, 0)])],
            sound: "letter_settle", volume: 0.8
        ))
    }

    private func send(intensity: Float, sharpness: Float, volume: Float, pitch: Float) {
        guard let player else { return }
        Self.send(player, [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .audioVolumeControl, value: volume, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .audioPitchControl, value: pitch, relativeTime: 0),
        ])
    }

    /// 先把声音和震动压到 0 再停，免得「咔」一下断掉
    private func stopLoop() {
        guard let player else { return }
        self.player = nil
        Self.send(player, [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .audioVolumeControl, value: 0, relativeTime: 0),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            do {
                try player.stop(atTime: CHHapticTimeImmediate)
            } catch {
                let ns = error as NSError
                NSLog("⚠️ [LetterLiftFeel] 停止失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
            }
        }
    }

    private static func send(_ player: CHHapticAdvancedPatternPlayer, _ parameters: [CHHapticDynamicParameter]) {
        do {
            try player.sendParameters(parameters, atTime: CHHapticTimeImmediate)
        } catch {
            let ns = error as NSError
            NSLog("⚠️ [LetterLiftFeel] 调参数失败 domain=%@ code=%ld %@", ns.domain, ns.code, "\(error)")
        }
    }
}
