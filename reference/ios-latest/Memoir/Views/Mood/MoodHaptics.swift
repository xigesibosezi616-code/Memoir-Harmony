import CoreHaptics
import Foundation

/// 心情滑杆的手感（2026-10-16 产品定）。
///
/// | 滑到 | 手里 |
/// |---|---|
/// | 不愉快四档 | **慢心跳**「扑通、扑通」，比一般人的静息心率还慢：闷闷不乐约 57 次/分 … 跌入谷底约 48 次/分 |
/// | 不愉快、停住 3 秒 | 慢慢换成**呼吸引导**：4 秒渐强（吸气）、6 秒渐弱（呼气），一分钟 6 次；画面上的心跟着一胀一缩；做完几轮换回平常那档 |
/// | 不悲不喜 | 几乎不震：两秒一下很轻的 |
/// | 愉快四档 | 轻快清脆的两下一组，越愉快越快 |
/// | 每过一档 | 轻轻一「嗒」，摸得出档位 |
///
/// 依据（文案只能说「研究发现……可能让人平静一些」，🔴 **不许写疗效**：非医疗产品，广告法和苹果审核都管）：
/// - 慢心跳：Azevedo et al. 2017, *Scientific Reports* 7:2285 —— 比静息心率慢的「心跳」震动，让准备公开演讲的人焦虑更低
/// - 呼吸引导：Miri et al. 2020, CHI（震动呼吸节拍器降低压力下的焦虑）；Fincham et al. 2023, *Scientific Reports*（呼吸练习对焦虑的荟萃分析）
/// - 40 Hz 之类「特定频率」**没有**站得住的研究，iPhone 的马达也不能指定赫兹，不用
///
/// 画面上的心跟着手里每一下震动跳（`pulse(at:)`，和震动同一个时钟）。引擎和投信、拆信共用一台（`LetterHaptics`）。
@MainActor
final class MoodHaptics {
    private enum Mode: Equatable { case heartbeat, calm, bright, breathing }

    private var mode: Mode?
    private var level: MoodLevel?
    private var player: CHHapticAdvancedPatternPlayer?
    private var active = false
    /// 节奏的时钟：从哪一刻起、那时已经走了几轮、现在一轮多长（随档位调快慢）。画面靠它和震动对拍
    private var clock: (date: Date, loops: Double, period: TimeInterval)?
    /// 现在这种节奏一轮多长（节奏自己的秒，没调快慢之前）
    private var loopEnd: TimeInterval = 1
    /// 现在这档震得多重（0…1）
    private var strength = 1.0

    /// 弹窗出现时调
    func start(valence: Double) {
        guard !active else { return }
        active = true
        LetterHaptics.acquire()
        level = nil
        update(valence: valence)
    }

    /// 弹窗消失时调
    func stop() {
        guard active else { return }
        active = false
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        mode = nil
        clock = nil
        LetterHaptics.release()
    }

    /// 滑杆动了
    func update(valence: Double) {
        guard active else { return }
        let newLevel = MoodLevel(valence: valence)
        if let level, level != newLevel {
            // 过一档：轻轻一「嗒」
            LetterHaptics.tap(intensity: 0.65, sharpness: 0.85)
        }
        level = newLevel
        let newMode: Mode = newLevel.isUnpleasant ? .heartbeat : (newLevel.isPleasant ? .bright : .calm)
        if mode != newMode { play(newMode) }
        tune(newLevel)
    }

    /// 在不愉快那边停住 3 秒了：换成呼吸引导。返回这一轮呼吸从哪一刻算起（画面跟着它一胀一缩）
    func beginBreathing() -> Date? {
        guard active, level?.isUnpleasant == true else { return nil }
        play(.breathing)
        return mode == .breathing ? .now : nil
    }

    /// 跟着呼吸做完了几轮（`MoodCalm`）：换成平常那档的轻轻一下，画面上的心停在平常、跟着它轻轻跳
    func finishBreathing() {
        guard active, mode == .breathing else { return }
        play(.calm)
        tune(.even)
    }

    /// 呼吸引导里（或做完之后）滑杆又动了：回到滑杆那档的节奏
    func endBreathing(valence: Double) {
        guard active else { return }
        mode = nil
        update(valence: valence)
    }

    /// 手指碰了一下画面上的心：手里也轻轻一下
    func touch() {
        guard active else { return }
        LetterHaptics.tap(intensity: 0.6, sharpness: 0.4)
    }

    /// 手里那一下震动在 `date` 这一刻有多满：0 = 两下之间，1 = 正震到最重。画面上的心跟着它跳。
    /// 呼吸引导时是 0（画面跟 `MoodBreath` 一胀一缩）
    func pulse(at date: Date) -> Double {
        guard let clock, let mode, mode != .breathing else { return 0 }
        let loops = clock.loops + date.timeIntervalSince(clock.date) / clock.period
        let inLoop = (loops - loops.rounded(.down)) * loopEnd   // 这一轮的第几秒（节奏自己的秒）
        let speed = loopEnd / clock.period                       // 快慢倍数（= playbackRate）
        var value = 0.0
        for beat in Self.beats(mode) {
            var since = inLoop - beat.at
            if since < 0 { since += loopEnd }
            let real = since / speed
            // 一下：很快涨满（40 毫秒），再慢慢落下去（约 0.16 秒）
            value += Double(beat.intensity) * (real < 0.04 ? real / 0.04 : exp(-(real - 0.04) / 0.16))
        }
        return min(1, value * strength)
    }

    // MARK: - 编排

    private func play(_ newMode: Mode) {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        let (pattern, loopEnd) = Self.pattern(newMode)
        player = LetterHaptics.loop(pattern, loopEnd: loopEnd)
        mode = newMode
        self.loopEnd = loopEnd
        clock = (.now, 0, loopEnd)
    }

    /// 同一种节奏里，按档位调快慢和轻重
    private func tune(_ level: MoodLevel) {
        guard mode != .breathing else { return }
        let rate: Float
        let intensity: Float
        switch level {
        case .rockBottom: rate = 0.8; intensity = 1      // 48 次/分
        case .heartsick: rate = 0.85; intensity = 0.95   // 51 次/分
        case .melancholy: rate = 0.9; intensity = 0.9    // 54 次/分
        case .glum: rate = 0.95; intensity = 0.85        // 57 次/分
        case .even: rate = 1; intensity = 1
        case .content: rate = 0.9; intensity = 0.85
        case .joyful: rate = 1.0; intensity = 0.9
        case .radiant: rate = 1.1; intensity = 0.95
        case .overjoyed: rate = 1.2; intensity = 1
        }
        if let player {
            player.playbackRate = rate
            try? player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0)],
                                       atTime: CHHapticTimeImmediate)
        }
        // 画面的时钟跟着换快慢：先记下到这一刻走了几轮，再按新的快慢往下走（模拟器没有马达，画面照样跳）
        if let clock {
            let now = Date.now
            self.clock = (now, clock.loops + now.timeIntervalSince(clock.date) / clock.period, loopEnd / Double(rate))
        }
        strength = Double(intensity)
    }

    /// 每种节奏里那几下（第几秒、多重）：震动和画面上的心跳都按它
    private static func beats(_ mode: Mode) -> [(at: TimeInterval, intensity: Float)] {
        switch mode {
        // 2026-10-17 用户反馈「不够明显」，整体加大：心跳「扑」打满
        case .heartbeat: return [(0, 1), (0.27, 0.7)]
        case .calm: return [(0, 0.35)]
        case .bright: return [(0, 0.6), (0.11, 0.45)]
        case .breathing: return []
        }
    }

    private static func pattern(_ mode: Mode) -> (LetterHaptics.Pattern, TimeInterval) {
        let h = LetterHaptics.self
        switch mode {
        case .heartbeat:
            // 一拍 1 秒（60 次/分），靠 playbackRate 放慢：「扑」重一点、「通」轻一点，都很钝（锐度低）
            let b = beats(.heartbeat)
            return (LetterHaptics.Pattern(events: [
                h.transient(b[0].at, intensity: b[0].intensity, sharpness: 0.22),
                h.continuous(b[0].at, duration: 0.1, intensity: 0.55, sharpness: 0.1),
                h.transient(b[1].at, intensity: b[1].intensity, sharpness: 0.18),
                h.continuous(b[1].at, duration: 0.08, intensity: 0.35, sharpness: 0.08),
            ]), 1.0)
        case .calm:
            let b = beats(.calm)
            return (LetterHaptics.Pattern(events: [h.transient(b[0].at, intensity: b[0].intensity, sharpness: 0.3)]), 2.0)
        case .bright:
            let b = beats(.bright)
            return (LetterHaptics.Pattern(events: [
                h.transient(b[0].at, intensity: b[0].intensity, sharpness: 0.55),
                h.transient(b[1].at, intensity: b[1].intensity, sharpness: 0.7),
            ]), 0.8)
        case .breathing:
            // 一整轮 10 秒的持续震动，强弱跟着 `MoodBreath.phase` 走（和画面同一条曲线）
            let cycle = MoodBreath.cycle
            let points: [(TimeInterval, Float)] = (0...14).map { i in
                let time = Double(i) / 14 * cycle
                return (time, Float(0.1 + 0.9 * MoodBreath.phase(at: time)))
            }
            return (LetterHaptics.Pattern(
                events: [h.continuous(0, duration: cycle, intensity: 0.95, sharpness: 0.12)],
                curves: [h.curve(start: 0, points: points)]
            ), cycle)
        }
    }
}

/// 呼吸引导的节拍：吸 4 秒、呼 6 秒，一分钟 6 次（慢呼吸的常用节奏）。震动和画面用同一条曲线
enum MoodBreath {
    static let inhale: TimeInterval = 4
    static let exhale: TimeInterval = 6
    static var cycle: TimeInterval { inhale + exhale }

    /// 一轮里的第 `time` 秒：0 = 呼尽，1 = 吸满
    static func phase(at time: TimeInterval) -> Double {
        let e = time.truncatingRemainder(dividingBy: cycle)
        if e < inhale { return smooth(e / inhale) }
        return 1 - smooth((e - inhale) / exhale)
    }

    static func phase(since start: Date, now: Date) -> Double {
        phase(at: max(0, now.timeIntervalSince(start)))
    }

    static func isInhaling(since start: Date, now: Date) -> Bool {
        max(0, now.timeIntervalSince(start)).truncatingRemainder(dividingBy: cycle) < inhale
    }

    private static func smooth(_ x: Double) -> Double {
        let u = min(max(x, 0), 1)
        return u * u * (3 - 2 * u)
    }
}

/// 呼吸引导（2026-10-17 产品定）：跟着震动呼吸几轮，画面从他选的那档褪向「平常」，褪完就收尾 ——
/// 不再引导呼吸，心停在平常，提示换成收尾那句，等他点「完成」。
/// **只是画面** —— 滑杆、档位的字、最后记下来的，都还是他自己选的那档。
///
/// 几轮：跌入谷底 6 轮（一分钟）、黯然神伤 5 轮、郁郁寡欢 4 轮、闷闷不乐 3 轮（一轮 10 秒，见 `MoodBreath`）。
/// 依据只说得到这一步：慢呼吸（每分钟约 6 次）时，心率变异性在练习当下和刚做完就会升高
/// （Laborde et al. 2022, *Neuroscience & Biobehavioral Reviews*，223 项研究的荟萃分析）；
/// 「一分钟够不够」没有研究直接比过，所以「最多一分钟」是**不让人久等**的产品取舍。文案只说「希望……」，🔴 不许写疗效。
enum MoodCalm {
    /// 褪到哪：平常。慢呼吸的研究支持的是「平静一些」，不是「变愉快」，所以不往愉快那边走
    static let target: Double = 0
    /// 呼吸引导被打断后，画面回到滑杆那档要多久
    static let returnDuration: TimeInterval = 0.8

    /// 从 `start` 开始要跟着呼吸几轮：离平常差几档就多几轮，3～6 轮
    static func breaths(from start: Double) -> Int {
        let levels = (target - start) / MoodLevel.width
        return min(6, max(3, Int((2 + levels).rounded())))
    }

    /// 褪完要多久：整数轮，最后一轮呼完正好褪完（这时心是呼尽的样子，停下来不跳）
    static func duration(from start: Double) -> TimeInterval {
        Double(breaths(from: start)) * MoodBreath.cycle
    }

    /// 从 `start` 开始褪，过了 `since` 到 `now` 这么久，褪到了哪。
    /// 先快后慢：第一轮就看得出线在理顺、颜色在变，最后稳稳停在平常
    static func valence(from start: Double, since: Date, now: Date) -> Double {
        guard start < target else { return start }
        let x = min(max(now.timeIntervalSince(since) / duration(from: start), 0), 1)
        return start + (target - start) * (1 - (1 - x) * (1 - x))
    }
}
