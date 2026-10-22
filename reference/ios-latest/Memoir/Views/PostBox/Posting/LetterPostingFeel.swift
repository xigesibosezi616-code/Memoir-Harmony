import CoreHaptics

/// 投信时手里的感觉：震动 + 声音，和投信动画（`LetterPostingFlight`）踩同一条时间轴（`LetterPostingTimeline`）。
///
/// | 时刻 | 画面 | 震动 | 声音 |
/// |---|---|---|---|
/// | 0–0.24 | 那叠日记收拢成一页 | 几下很轻的纸响 | 纸拢在一起的沙沙声 |
/// | 0.24–0.56 | 信纸滑进信封 | 持续的纸擦纸，中段最强；到底轻轻一顿 | 纸擦纸 |
/// | 0.48–0.86 | 封舌合上（和上一段叠着） | 低低的一段，落下时软软一拍 | 翻过来的风声、「啪」 |
/// | 0.90–1.20 | 会员盖火漆 / 免费用户抹平封口 | 火漆：蜡被压扁的一段 + 实实的一下；抹平：一段很轻的摩擦 | 闷闷的「噗」/ 指腹擦过纸 |
/// | 1.75–2.15 | 推进投信口 | 纸顺着投信口滑进去，越推越深 | 纸擦着投信口的唇边，进了筒里声音闷下去 |
/// | 2.21 | 信落进邮筒 | 软软的一下，空筒里一点余韵 | 「噗」+ 低低一声「咚」+ 纸摞上的细响 |
///
/// 🔴 2026-10-20 产品定：**铁皮声只留给戳邮筒**（`playPoke`），寄信最后那一下换成「落信」—— 原来也是翻板落回的「哐」。
/// 投信也不再是点邮筒：从下面那叠信往上推进投信口，推的那一路另有手感（`LetterLiftFeel`），松手寄出时接这一段。
///
/// 声音文件由 `Scripts/make_post_sound.py` 生成（会员一份、免费一份，整条时间轴从 0 开始），
/// 时间轴要和这里、动画三处一起改。引擎全 App 共用一台（见 `LetterHaptics`）。
@MainActor
final class LetterPostingFeel {
    private typealias T = LetterPostingTimeline

    /// 邮筒页出现时调：引擎热起来、几种编排先登记好
    func prepare() {
        LetterHaptics.acquire()
        for sealed in [true, false] {
            LetterHaptics.preload(Self.key(sealed)) { Self.pattern(sealed: sealed) }
            LetterHaptics.preload(Self.tailKey(sealed)) { Self.tailPattern(sealed: sealed) }
        }
    }

    /// 投信（从头放一整段）：和投信动画同时开始。读屏点邮筒寄信时走这里
    func play(sealed: Bool) {
        LetterHaptics.play(Self.key(sealed)) { Self.pattern(sealed: sealed) }
    }

    /// 推着寄的（2026-10-20 起）：信封在推的途中已经装到 `start`（时间轴上的一刻），松手后动画从这里接着放 ——
    /// 声音和震动也只放封舌落定之后那一截（封口、推进投信口、落信）。
    /// 松手时封舌还没合上的，动画接着把它合上，落定那一下「啪」在这里补（推的途中合上了的话 `LetterLiftFeel` 已经响过）
    func playTail(sealed: Bool, from start: Double) {
        if start < T.flapClose.upperBound {
            LetterHaptics.fire(Self.flapPat, after: T.flapClose.upperBound - start)
        }
        LetterHaptics.play(Self.tailKey(sealed), after: max(0, Self.tailStart - start)) { Self.tailPattern(sealed: sealed) }
    }

    /// 封舌落定那一下：软软一拍 + 「啪」。推的途中合上（`LetterLiftFeel.flapClosed`）、松手后才合上（`playTail`）共用
    static var flapPat: LetterHaptics.Pattern {
        let h = LetterHaptics.self
        return LetterHaptics.Pattern(
            events: [
                h.transient(0, intensity: 0.5, sharpness: 0.25),
                h.continuous(0.005, duration: 0.06, intensity: 0.22, sharpness: 0.1),
            ],
            curves: [h.curve(start: 0.005, points: [(0, 1), (0.06, 0)])],
            sound: "letter_flap", volume: 0.85
        )
    }

    /// 戳邮筒（点一下邮筒；2026-10-20 起点邮筒只是戳，不再投信）：
    /// 手指把投信口的翻板顶进去一点，翻板落回来「哐」一下 —— **铁皮声只在这里有**，寄信用的是「落信」。
    /// 2026-10-16 产品定：挺解压的，每戳一下都要有；连着戳就一下叠一下（`LetterHaptics.fire`）
    func playPoke() {
        let h = LetterHaptics.self
        LetterHaptics.fire(LetterHaptics.Pattern(
            events: [
                // 手指顶开翻板
                h.transient(0, intensity: 0.32, sharpness: 0.6),
                // 翻板落回来：重重的一下，铁筒里一点余震
                h.transient(Self.pokeClack, intensity: 1.0, sharpness: 0.35),
                h.continuous(Self.pokeClack + 0.01, duration: 0.14, intensity: 0.4, sharpness: 0.08),
            ],
            curves: [h.curve(start: Self.pokeClack + 0.01, points: [(0, 1.0), (0.14, 0)])],
            sound: "mailbox_poke"
        ))
    }

    /// 戳邮筒时翻板落回来的时刻，和 `Scripts/make_post_sound.py` 的 POKE_CLACK 一致
    private static let pokeClack: TimeInterval = 0.07

    /// 「减弱动态效果」下：没有投信过程，只一下投进去的闷响
    func playQuiet() {
        LetterHaptics.tap(intensity: 0.6, sharpness: 0.3)
    }

    func stop() {
        LetterHaptics.release()
    }

    // MARK: - 编排

    private static func key(_ sealed: Bool) -> String { sealed ? "post-sealed" : "post-plain" }
    private static func tailKey(_ sealed: Bool) -> String { sealed ? "post-tail-sealed" : "post-tail-plain" }

    private static func pattern(sealed: Bool) -> LetterHaptics.Pattern {
        LetterHaptics.Pattern(events: events(sealed: sealed), curves: curves(sealed: sealed),
                              sound: sealed ? "letter_post_sealed" : "letter_post_plain")
    }

    /// 后半截从哪一刻起：封舌落定之后一点（落定那一下单独放，见 `flapPat`）。和 `make_post_sound.py` 的 TAIL 一致
    static let tailStart: Double = 0.88

    /// 后半截：整段编排里 `tailStart` 之后的那些，时间往前挪；声音是整段从 `tailStart` 切开的后半截
    private static func tailPattern(sealed: Bool) -> LetterHaptics.Pattern {
        let events = events(sealed: sealed).filter { $0.relativeTime >= tailStart }
        events.forEach { $0.relativeTime -= tailStart }
        let curves = curves(sealed: sealed).filter { $0.relativeTime >= tailStart }
        curves.forEach { $0.relativeTime -= tailStart }
        return LetterHaptics.Pattern(events: events, curves: curves,
                                     sound: sealed ? "letter_post_tail_sealed" : "letter_post_tail_plain")
    }

    private static func events(sealed: Bool) -> [CHHapticEvent] {
        let h = LetterHaptics.self
        var e: [CHHapticEvent] = []

        // 收拢：几下很轻的纸响
        e += [(0.015, 0.22), (0.07, 0.16), (0.13, 0.12)].map { h.transient($0.0, intensity: Float($0.1), sharpness: 0.5) }

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
            e.append(h.transient(T.sealPress, intensity: 0.85, sharpness: 0.28))
            e.append(h.continuous(T.seal.upperBound - 0.05, duration: 0.1, intensity: 0.25, sharpness: 0.05))
        } else {
            // 抹平封口：指腹顺着封舌擦过去
            e.append(h.transient(T.seal.lowerBound + 0.02, intensity: 0.2, sharpness: 0.4))
            e.append(h.continuous(T.seal.lowerBound + 0.02, duration: 0.26, intensity: 0.2, sharpness: 0.35))
        }

        // 推进投信口：纸顺着投信口滑进去，越推越深（不再有铁皮被顶开的那一下）
        e.append(h.transient(T.insert.lowerBound + 0.03, intensity: 0.22, sharpness: 0.35))
        e.append(h.continuous(T.insert.lowerBound, duration: T.insert.upperBound - T.insert.lowerBound,
                              intensity: 0.45, sharpness: 0.32))

        // 信落进邮筒：落在信摞上软软的一下，空铁筒里低低的余韵
        e.append(h.transient(T.land, intensity: 0.85, sharpness: 0.12))
        e.append(h.continuous(T.land + 0.01, duration: 0.24, intensity: 0.45, sharpness: 0.03))
        return e
    }

    private static func curves(sealed: Bool) -> [CHHapticParameterCurve] {
        let h = LetterHaptics.self
        let slide = T.slideIn.upperBound - T.slideIn.lowerBound
        // 封舌和装信叠着走：同一时刻只能有一条强度曲线说了算，封舌这条等装信那条走完再接上
        let flap = T.flapClose.upperBound - T.slideIn.upperBound
        let insert = T.insert.upperBound - T.insert.lowerBound
        // 🔴 强度曲线在最后一个控制点之后**一直保持那个值**，会把后面几段持续震动一起压低 ——
        // 所以每条（除了最后一条）收尾都补一个回到 1 的点（`restored`）
        func restored(_ points: [(TimeInterval, Float)], after end: TimeInterval) -> [(TimeInterval, Float)] {
            points + [(end + 0.02, 1)]
        }
        return [
            h.curve(start: T.slideIn.lowerBound, points: h.bell(duration: slide, floor: 0.15, samples: 10)),
            h.curve(start: T.slideIn.upperBound,
                    points: restored(h.bell(duration: flap, floor: 0.1, samples: 8), after: flap)),
            // 越推越紧：起头轻，后段最重，进去的那一刻松掉
            h.curve(start: T.insert.lowerBound,
                    points: restored([(0, 0.3), (insert * 0.5, 0.7), (insert * 0.85, 1.0), (insert, 0)], after: insert)),
            // 余韵慢慢散掉
            h.curve(start: T.land + 0.01, points: [(0, 1.0), (0.08, 0.5), (0.24, 0)]),
        ]
    }
}
