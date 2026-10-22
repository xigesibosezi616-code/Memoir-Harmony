import CoreHaptics

/// 拆火漆信时手里的感觉：持续的震动 + 纸的声音，和拆信动画（`SealedEnvelope`）踩同一条时间轴。
///
/// 拆信是**三下**（2026-10-11 产品定）：第一下打碎火漆、第二下打开信封、第三下抽出信纸（抽完自己摊开）。
/// 每一步一段震动、一段声音，时间都从这一下点下去算起；急着连点时，三步首尾相接，等于一口气拆完。
///
/// | 步 | 画面 | 震动 | 声音 |
/// |---|---|---|---|
/// | 1 | 火漆裂开（0.36s） | 一下清脆的重击，紧跟三下越来越轻、越来越快的碎裂，中间夹着细砂似的颗粒 | 蜡块闷闷的「嗒」，跟几声细裂 |
/// | 2 | 封舌翻起（1.07s） | 先一点撕开封口的阻力，然后一段持续的低沉震动随翻起的速度涨落；翻过头顶时软软一顿 | 撕开、沙沙声、翻过去的「噗」 |
/// | 3 | 信纸抽出（1.17s）+ 摊开（0.55s） | 持续的纸张摩擦，中段最强，一路带着纤维的颗粒；离开信封轻轻一松；摊开时落在桌上一顿 | 纸擦纸、轻「嘶」、展开的脆响、轻轻落下 |
///
/// 声音文件由 `Scripts/make_letter_sound.py` 生成，时间轴要和这里、动画三处一起改。
///
/// - 声音走 `.ambient`：跟着静音键（静音时只有震动），也不打断用户在放的音乐
/// - 设备不支持 Core Haptics（iPad 等）时只放声音
/// - 「减弱动态效果」打开时不播拆信动画，只轻轻一顿，不放声音
@MainActor
final class LetterOpeningFeel {
    /// 拆信一口气走完的时长（三步加起来），各步按 progress 的份额分
    static let animationDuration: TimeInterval = 2.6
    /// 每一步结束时 `SealedEnvelope.progress` 到哪：火漆裂开、封舌翻起、信纸抽出
    static let stageTargets: [Double] = [0.14, 0.55, 1.0]
    /// 抽出后摊成信纸的淡入时长
    static let unfoldDuration: TimeInterval = 0.55

    /// 第 `stage` 步（0、1、2）的动画时长：按它在整条拆信里占的 progress 份额算，连起来就是一口气拆完的速度
    static func duration(ofStage stage: Int) -> TimeInterval {
        let from = stage == 0 ? 0 : stageTargets[stage - 1]
        return (stageTargets[stage] - from) * animationDuration
    }

    // MARK: - 播放（引擎全 App 共用一台，见 `LetterHaptics` —— 投信也用它）

    private static func key(_ stage: Int) -> String { "open-\(stage)" }

    private static func pattern(stage: Int) -> LetterHaptics.Pattern {
        LetterHaptics.Pattern(events: events(stage: stage), curves: curves(stage: stage),
                              sound: "letter_open_\(stage + 1)")
    }

    /// 打开信封页时先把引擎热起来、三步的编排登记好：等到点下去再做，第一下震动会慢半拍
    func prepare() {
        LetterHaptics.acquire()
        for stage in 0..<Self.stageTargets.count {
            LetterHaptics.preload(Self.key(stage)) { Self.pattern(stage: stage) }
        }
    }

    /// 第 `stage` 步（0 火漆、1 封舌、2 信纸）：和这一步的动画同时开始
    func play(stage: Int) {
        guard Self.stageTargets.indices.contains(stage) else { return }
        LetterHaptics.play(Self.key(stage)) { Self.pattern(stage: stage) }
    }

    /// 「减弱动态效果」下：没有拆信过程，只在信纸出现时轻轻一顿
    func playQuiet() {
        LetterHaptics.tap(intensity: 0.45, sharpness: 0.2)
    }

    /// 离开信封页。不打断正在放的（信纸摊开时最后那一下落桌声还在放）
    func stop() {
        LetterHaptics.release()
    }

    // MARK: - 编排（时间都从这一步点下去算起）

    private static func events(stage: Int) -> [CHHapticEvent] {
        switch stage {
        case 0:
            // 火漆裂开：一下清脆的重击 + 三下越来越轻的碎裂，中间夹着细砂似的颗粒
            return [
                Self.transient(0.03, intensity: 1.0, sharpness: 0.85),
                Self.transient(0.078, intensity: 0.55, sharpness: 0.75),
                Self.transient(0.122, intensity: 0.38, sharpness: 0.7),
                Self.transient(0.186, intensity: 0.24, sharpness: 0.6),
                Self.continuous(0.02, duration: 0.24, intensity: 0.22, sharpness: 0.9),
            ]
        case 1:
            // 封舌：撕开封口的一点阻力（几下细碎），然后随翻起的速度涨落；翻过头顶时软软一顿
            var events = [(0.005, 0.22), (0.035, 0.18), (0.08, 0.15), (0.13, 0.12)].map {
                Self.transient($0.0, intensity: Float($0.1), sharpness: 0.5)
            }
            events.append(Self.continuous(0, duration: Self.duration(ofStage: 1), intensity: 0.42, sharpness: 0.18))
            events.append(Self.transient(0.51, intensity: 0.42, sharpness: 0.22))
            return events
        default:
            // 信纸抽出：持续的纸张摩擦，中段最强；一路带着纤维的颗粒（细密的轻敲）；离开信封轻轻一松；
            // 摊开成信纸时落在桌上一顿
            let slide = Self.duration(ofStage: 2)
            var events = [Self.continuous(0.02, duration: slide - 0.04, intensity: 0.5, sharpness: 0.32)]
            var grain = 0.07
            var seed: UInt64 = 0x4D45_4D4F_4952   // 固定种子：每次拆信手感一样
            while grain < slide - 0.1 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let jitter = Double(seed >> 33) / Double(UInt32.max)       // 0…1
                let speed = 4 * (grain / slide) * (1 - grain / slide)
                events.append(Self.transient(grain, intensity: Float(0.08 + 0.16 * speed * (0.6 + 0.4 * jitter)),
                                             sharpness: Float(0.4 + 0.2 * jitter)))
                grain += 0.045 + 0.03 * jitter
            }
            events.append(Self.transient(slide - 0.05, intensity: 0.32, sharpness: 0.4))
            events.append(Self.continuous(1.55, duration: 0.12, intensity: 0.18, sharpness: 0.1))
            events.append(Self.transient(1.62, intensity: 0.5, sharpness: 0.15))
            return events
        }
    }

    private static func curves(stage: Int) -> [CHHapticParameterCurve] {
        switch stage {
        case 0:
            return [Self.curve(start: 0.02, points: [(0, 1.0), (0.12, 0.6), (0.24, 0)])]
        case 1:
            return [Self.curve(start: 0, points: Self.bell(duration: Self.duration(ofStage: 1), floor: 0.12, samples: 10))]
        default:
            return [Self.curve(start: 0.02, points: Self.bell(duration: Self.duration(ofStage: 2) - 0.04, floor: 0.15, samples: 12))]
        }
    }

    private static func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        LetterHaptics.transient(time, intensity: intensity, sharpness: sharpness)
    }

    private static func continuous(_ time: TimeInterval, duration: TimeInterval,
                                   intensity: Float, sharpness: Float) -> CHHapticEvent {
        LetterHaptics.continuous(time, duration: duration, intensity: intensity, sharpness: sharpness)
    }

    private static func curve(start: TimeInterval, points: [(TimeInterval, Float)]) -> CHHapticParameterCurve {
        LetterHaptics.curve(start: start, points: points)
    }

    private static func bell(duration: TimeInterval, floor: Float, samples: Int) -> [(TimeInterval, Float)] {
        LetterHaptics.bell(duration: duration, floor: floor, samples: samples)
    }
}
