import SwiftUI

/// 投信一口气的时间轴（秒，从把信推进投信口、松手那一刻算起）。
///
/// 动画（`LetterPostingFlight`）、震动（`LetterPostingFeel`）、声音（`Scripts/make_post_sound.py`）
/// 三处踩同一条时间轴，**改一处要三处一起改**。
///
/// 2026-10-20 真机试过嫌「装进信封慢、封舌合上那一下生硬」：收拢和装信加快，封舌在信纸还剩一截时就开始合（两段叠着走，
/// 不再一段停稳了才起下一段），后面跟着提前，整段 2.95 → 2.28 秒
enum LetterPostingTimeline {
    /// 那叠日记收拢成一页信纸，悬在打开的信封上方
    static let gather: ClosedRange<Double> = 0.0...0.24
    /// 信纸滑进信封
    static let slideIn: ClosedRange<Double> = 0.24...0.56
    /// 封舌合上，0.86 落下。和上一段叠着：信纸还剩一截在外面就开始合
    static let flapClose: ClosedRange<Double> = 0.48...0.86
    /// 会员：火漆落下、压平（`sealPress` 压实）；免费：手指顺着封口抹一下
    static let seal: ClosedRange<Double> = 0.90...1.20
    /// 信封举到投信口
    static let rise: ClosedRange<Double> = 1.20...1.75
    /// 推进投信口
    static let insert: ClosedRange<Double> = 1.75...2.15
    /// 投信口里的翻板落回去
    static let flapFall: ClosedRange<Double> = 2.15...2.23
    /// 信落进邮筒那一声
    static let land: Double = 2.21
    /// 整个动作的长度
    static let total: Double = 2.28

    /// 火漆压实的那一刻
    static var sealPress: Double { seal.upperBound - 0.06 }

    /// t 在区间里走到哪（0…1，线性）
    static func linear(_ t: Double, _ r: ClosedRange<Double>) -> Double {
        min(max((t - r.lowerBound) / (r.upperBound - r.lowerBound), 0), 1)
    }

    /// 同上，两头缓（smoothstep，不过冲）
    static func smooth(_ t: Double, _ r: ClosedRange<Double>) -> Double {
        let u = linear(t, r)
        return u * u * (3 - 2 * u)
    }
}

/// 投信的整个过程，盖在邮筒页上面画（2026-10-11 产品定，替换原来的果冻回弹）：
///
/// 1. 那叠日记收拢成一页信纸 → 滑进信封 → 封舌合上
/// 2. 会员盖上自己的火漆（印面是昵称首字，和笔友回信的火漆对上）；免费用户是普通封口
/// 3. 信封举到投信口，上沿往里一倒，推进去 —— 过了投信口下沿的部分就看不见了
/// 4. 推进去时翻板被顶开（口子里露出黑），信一进去翻板落回去
///
/// 全程是不过冲的平滑曲线，没有回弹（见记忆「交互贴着实物」）。装信和合封舌叠着走；
/// 封舌落定、火漆压实时信封被轻轻按一下（压下去一点再回来），合上那一下才有接触的实感。
/// 所有位置都在本视图的坐标里，由邮筒页量好传进来
struct LetterPostingFlight<Pile: View>: View, Animatable {
    let palette: LetterPalette
    /// 火漆上压的字（会员自己的昵称首字）
    let sealMark: String?
    /// 会员才盖火漆
    let hasSeal: Bool
    /// 那叠日记在哪：推着的时候跟着手（缩小过的），寄出后停在松手的地方；读屏寄信时是原位
    var pileFrame: CGRect
    /// 那叠日记原本的大小（按这个排版，再缩到 `pileFrame`）—— 缩小过的信不能按小尺寸重新排，字会挤
    let pileSize: CGSize
    let pile: Pile
    /// 投信口的开口
    let slot: CGRect
    /// 封舌合上时绕上沿哪一头转（2026-10-21）：信在邮筒中轴左边就绕左头转、右边先落下；在右边反过来
    var flapPivot: HorizontalEdge = .leading
    /// 时间轴走到哪（秒）。推着的时候跟着手走（0 → 封舌合上），寄出后接着往下放
    var t: Double

    /// 时间和位置一起插值：没推到松手时，信封展开、那叠日记摊回去、落回原位是同一个动画
    var animatableData: AnimatablePair<Double, CGRect.AnimatableData> {
        get { AnimatablePair(t, pileFrame.animatableData) }
        set {
            t = newValue.first
            pileFrame.animatableData = newValue.second
        }
    }

    private typealias T = LetterPostingTimeline

    var body: some View {
        // 信封在原地的大小：底边和那叠日记的底边对齐，抽出来的信纸往上冒
        let homeW = min(pileFrame.width * 0.6, 220)
        let homeH = homeW / SealedEnvelope.aspect
        let home = CGPoint(x: pileFrame.midX, y: pileFrame.maxY - homeH / 2)
        // 到投信口时的大小：比开口窄一圈（往里倒时下沿离人近、看着会变宽）
        let endW = slot.width * 0.7
        let endH = endW / SealedEnvelope.aspect
        let approach = CGPoint(x: slot.midX, y: slot.maxY + endH / 2)

        let rise = T.smooth(t, T.rise)
        let insert = T.smooth(t, T.insert)
        let w = homeW + (endW - homeW) * rise
        let center = CGPoint(
            x: home.x + (approach.x - home.x) * rise,
            y: home.y + (approach.y - home.y) * rise - insert * endH * 1.25
        )
        // 举到跟前时上沿开始往里倒，推进去时倒得更多
        let tilt = 25 * T.smooth(t, (T.rise.lowerBound + 0.25)...T.rise.upperBound) + 30 * insert
        let press = Self.press(t, at: T.flapClose.upperBound) + (hasSeal ? Self.press(t, at: T.sealPress) : 0)

        ZStack(alignment: .topLeading) {
            slotGap

            // 信封。过了投信口下沿的部分看不见（进去了）
            ZStack(alignment: .topLeading) {
                SealedEnvelope(
                    palette: palette,
                    sealMark: sealMark,
                    hasSeal: hasSeal,
                    sealPress: hasSeal ? T.linear(t, T.seal) : 0,
                    pose: EnvelopePose(flap: 1 - T.smooth(t, T.flapClose), letter: 1 - T.smooth(t, T.slideIn)),
                    curls: true,
                    curl: .sweep(pivot: flapPivot)
                )
                .frame(width: w)
                // 封舌落定、火漆压实那一下：信封被轻轻按一下，往下压一点再回来（不弹）
                .scaleEffect(x: 1 + 0.006 * press, y: 1 - 0.022 * press, anchor: .bottom)
                .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
                .position(center)
                // 信封从下面托上来，接住收拢好的信纸
                .offset(y: (1 - T.smooth(t, 0.06...T.gather.upperBound)) * homeH * 0.5)
                .opacity(T.smooth(t, 0.06...0.20))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .mask(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(0, slot.maxY))
                    Color.black
                }
            }

            if t < T.gather.upperBound {
                gatheringSheet(homeW: homeW, homeH: homeH, home: home)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 按一下：从 `start` 起 0.16 秒里压下去再回来（sin² 鼓包，两头都缓，不过冲）
    private static func press(_ t: Double, at start: Double) -> Double {
        let u = (t - start) / 0.16
        guard u > 0, u < 1 else { return 0 }
        let s = sin(.pi * u)
        return s * s
    }

    /// 那叠日记收拢成信封上方那页信纸：字先淡掉，纸缩到信纸的位置和大小，和信封里那页严丝合缝
    private func gatheringSheet(homeW: CGFloat, homeH: CGFloat, home: CGPoint) -> some View {
        let g = T.smooth(t, T.gather)
        // 拆信 progress = 1 时信纸的位置（见 `SealedEnvelope`：宽高 0.9，上移 0.8 个信封高）
        let target = CGRect(
            x: home.x - homeW / 2 + homeW * 0.05,
            y: home.y - homeH / 2 + homeH * 0.05 - homeH * 0.8,
            width: homeW * 0.9,
            height: homeH * 0.9
        )
        let rect = CGRect(
            x: pileFrame.minX + (target.minX - pileFrame.minX) * g,
            y: pileFrame.minY + (target.minY - pileFrame.minY) * g,
            width: pileFrame.width + (target.width - pileFrame.width) * g,
            height: pileFrame.height + (target.height - pileFrame.height) * g
        )
        return ZStack {
            FoldedLetter(palette: palette)
                .frame(width: rect.width, height: rect.height)
                .opacity(T.smooth(t, 0.02...0.14))
            pile
                .frame(width: pileSize.width, height: pileSize.height)
                .scaleEffect(x: rect.width / max(pileSize.width, 1), y: rect.height / max(pileSize.height, 1))
                .opacity(1 - T.smooth(t, 0...0.14))
        }
        .position(x: rect.midX, y: rect.midY)
    }

    /// 投信口里的翻板：信顶进来时被推开，露出里面的黑；信进去了就落回去（重力，越落越快）
    private var slotGap: some View {
        let open = T.smooth(t, T.insert.lowerBound...(T.insert.lowerBound + 0.14))
        let fall = T.linear(t, T.flapFall)
        let amount = open * (1 - fall * fall)
        let h = slot.height * amount
        return Capsule()
            .fill(Color.black.opacity(0.62))
            .frame(width: slot.width, height: h)
            .position(x: slot.midX, y: slot.maxY - h / 2)
            .opacity(amount > 0.001 ? 1 : 0)
    }
}
