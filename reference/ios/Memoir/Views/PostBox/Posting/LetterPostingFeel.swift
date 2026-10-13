import CoreHaptics

/// 投信时手里的感觉：震动 + 声音，和投信动画（`LetterPostingFlight`）踩同一条时间轴（`LetterPostingTimeline`）。
///
/// | 时刻 | 画面 | 震动 | 声音 |
/// |---|---|---|---|
/// | 0–0.32 | 那叠日记收拢成一页 | 几下很轻的纸响 | 纸拢在一起的沙沙声 |
/// | 0.32–0.95 | 信纸滑进信封 | 持续的纸擦纸，中段最强；到底轻轻一顿 | 纸擦纸 |
/// | 0.95–1.40 | 封舌合上 | 低低的一段，落下时软软一拍 | 翻过来的风声、「啪」 |
/// | 1.46–1.76 | 会员盖火漆 / 免费用户抹平封口 | 火漆：蜡被压扁的一段 + 实实的一下；抹平：一段很轻的摩擦 | 闷闷的「噗」/ 指腹擦过纸 |
/// | 2.42–2.82 | 推进投信口 | 纸蹭着铁皮，越推越紧 | 纸擦铁皮、翻板被顶开的一声轻响 |
/// | 2.90 | 翻板落回去 | 重重的一下闷响，带一点余震 | 铁皮翻板落下的闷响 |
///
/// 声音文件由 `Scripts/make_post_sound.py` 生成（会员一份、免费一份，整条时间轴从 0 开始），
/// 时间轴要和这里、动画三处一起改。引擎全 App 共用一台（见 `LetterHaptics`）。
@MainActor
final class LetterPostingFeel {
    private typealias T = LetterPostingTimeline

    /// 邮筒页出现时调：引擎热起来、两种编排先登记好
    func prepare() {
        LetterHaptics.acquire()
        for sealed in [true, false] {
            LetterHaptics.preload(Self.key(sealed)) { Self.pattern(sealed: sealed) }
        }
    }

    /// 投信：和投信动画同时开始
    func play(sealed: Bool) {
        LetterHaptics.play(Self.key(sealed)) { Self.pattern(sealed: sealed) }
    }

    /// 邮筒这会儿不收（这周寄过了、一篇都没勾、没有新日记……）：手按在铁皮上，轻轻一顿
    func playRefused() {
        LetterHaptics.tap(intensity: 0.35, sharpness: 0.15)
    }

    /// 「减弱动态效果」下：没有投信过程，只一下投进去的闷响
    func playQuiet() {
        LetterHaptics.tap(intensity: 0.6, sharpness: 0.3)
    }

    func stop() {
        LetterHaptics.release()
    }

    // MARK: - 编排

    private static func key(_ sealed: Bool) -> String { sealed ? "post-sealed" : "post-plain" }

    private static func pattern(sealed: Bool) -> LetterHaptics.Pattern {
        LetterHaptics.Pattern(events: events(sealed: sealed), curves: curves(sealed: sealed),
                              sound: sealed ? "letter_post_sealed" : "letter_post_plain")
    }

    private static func events(sealed: Bool) -> [CHHapticEvent] {
        let h = LetterHaptics.self
        var e: [CHHapticEvent] = []

        // 收拢：几下很轻的纸响
        e += [(0.02, 0.22), (0.09, 0.16), (0.17, 0.12)].map { h.transient($0.0, intensity: Float($0.1), sharpness: 0.5) }

        // 滑进信封：持续的纸擦纸 + 纤维颗粒，到底一顿
        let slide = T.slideIn.upperBound - T.slideIn.lowerBound
        e.append(h.continuous(T.slideIn.lowerBound, duration: slide, intensity: 0.42, sharpness: 0.3))
        var grain = T.slideIn.lowerBound + 0.06
        var seed: UInt64 = 0x504F_5354   // 固定种子：每次投信手感一样
        while grain < T.slideIn.upperBound - 0.08 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let jitter = Double(seed >> 33) / Double(UInt32.max)
            let u = (grain - T.slideIn.lowerBound) / slide
            e.append(h.transient(grain, intensity: Float(0.07 + 0.14 * 4 * u * (1 - u) * (0.6 + 0.4 * jitter)),
                                 sharpness: Float(0.4 + 0.2 * jitter)))
            grain += 0.05 + 0.03 * jitter
        }
        e.append(h.transient(T.slideIn.upperBound - 0.03, intensity: 0.32, sharpness: 0.3))

        // 封舌合上：低低的一段，落下软软一拍
        e.append(h.continuous(T.flapClose.lowerBound, duration: T.flapClose.upperBound - T.flapClose.lowerBound,
                              intensity: 0.22, sharpness: 0.15))
        e.append(h.transient(T.flapClose.upperBound, intensity: 0.5, sharpness: 0.25))

        if sealed {
            // 火漆：蜡被压扁的一段，压实的一下，再一点点回软
            e.append(h.continuous(T.seal.lowerBound + 0.04, duration: 0.22, intensity: 0.32, sharpness: 0.08))
            e.append(h.transient(T.seal.upperBound - 0.06, intensity: 0.85, sharpness: 0.28))
            e.append(h.continuous(T.seal.upperBound - 0.05, duration: 0.1, intensity: 0.25, sharpness: 0.05))
        } else {
            // 抹平封口：指腹顺着封舌擦过去
            e.append(h.transient(T.seal.lowerBound + 0.02, intensity: 0.2, sharpness: 0.4))
            e.append(h.continuous(T.seal.lowerBound + 0.02, duration: 0.26, intensity: 0.2, sharpness: 0.35))
        }

        // 推进投信口：翻板被顶开的一下，纸蹭着铁皮越推越紧
        e.append(h.transient(T.insert.lowerBound + 0.03, intensity: 0.38, sharpness: 0.6))
        e.append(h.continuous(T.insert.lowerBound, duration: T.insert.upperBound - T.insert.lowerBound,
                              intensity: 0.5, sharpness: 0.5))

        // 翻板落回去：重重的一下闷响 + 一点余震
        e.append(h.transient(T.flapFall.upperBound, intensity: 1.0, sharpness: 0.35))
        e.append(h.continuous(T.flapFall.upperBound + 0.01, duration: 0.14, intensity: 0.4, sharpness: 0.08))
        return e
    }

    private static func curves(sealed: Bool) -> [CHHapticParameterCurve] {
        let h = LetterHaptics.self
        let slide = T.slideIn.upperBound - T.slideIn.lowerBound
        let flap = T.flapClose.upperBound - T.flapClose.lowerBound
        let insert = T.insert.upperBound - T.insert.lowerBound
        // 🔴 强度曲线在最后一个控制点之后**一直保持那个值**，会把后面几段持续震动一起压低 ——
        // 所以每条（除了最后一条）收尾都补一个回到 1 的点（`restored`）
        func restored(_ points: [(TimeInterval, Float)], after end: TimeInterval) -> [(TimeInterval, Float)] {
            points + [(end + 0.02, 1)]
        }
        return [
            h.curve(start: T.slideIn.lowerBound, points: h.bell(duration: slide, floor: 0.15, samples: 10)),
            h.curve(start: T.flapClose.lowerBound,
                    points: restored(h.bell(duration: flap, floor: 0.1, samples: 8), after: flap)),
            // 越推越紧：起头轻，后段最重，进去的那一刻松掉
            h.curve(start: T.insert.lowerBound,
                    points: restored([(0, 0.3), (insert * 0.5, 0.7), (insert * 0.85, 1.0), (insert, 0)], after: insert)),
            // 余震很快散掉
            h.curve(start: T.flapFall.upperBound + 0.01, points: [(0, 1.0), (0.14, 0)]),
        ]
    }
}
