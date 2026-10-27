import SwiftUI

/// 正在投的这一封：投信动画要用的全部东西（值快照，寄出那一刻定下）
struct PostingRun: Equatable {
    /// 那叠日记收拢之前的样子
    let items: [OutgoingItem]
    let excluded: Set<UUID>
    /// 信纸抬头写着寄给谁
    let recipients: String
    /// 会员才盖火漆，印面是自己昵称的首字
    let hasSeal: Bool
    let sealMark: String?
    /// 投信时间轴走到哪（秒），→ `LetterPostingTimeline.total`。推着寄的从推到的那一刻接着放，读屏寄的从 0 放
    var t: Double = 0
}

/// 邮筒页的版式：上面一个邮筒，下面一行状态，再下面一块固定高度的地方
/// 放「要寄的日记」/ 邮戳和在路上 / 退回来的信。
///
/// ## 怎么寄（2026-10-20 产品定）
///
/// **点邮筒不再投信**（拿邮筒玩的时候容易误触）：点一下只是「戳」，翻板「哐」一声。
/// 寄信要把下面那叠信**往上推**，而且**信封跟着手装**（第三版，用户提的）：
/// 推到哪装到哪 —— 那叠日记收成一页、信纸滑进信封、推到邮筒半腰封舌合上「啪」；拉回来就倒着走，封舌又翻开、信纸抽出来。
/// 封舌合上之后**松手、或者继续推到投信口**就寄：接着封口（会员压火漆）、升到投信口、塞进去、落信。
/// 没推到就松手：信封展开、那叠日记摊回原位。
/// 推的一路有由下往上的震动和风声，装到底、合上各有一下（`LetterLiftFeel`）。一拿起信，邮筒就弹回正面。读屏时点邮筒照旧是寄（从头放）。
///
/// 推的时候原来那叠信藏起来，画面整个交给投信动画（`LetterPostingFlight`）：时间轴不按时钟走，按推到哪走（`scrubTime`），
/// 那叠信的位置跟着手指（`visualFrame`）；寄出后从推到的那一刻接着按时钟放。
///
/// 下面那块**高度固定**：投信动画要从那叠日记飞到投信口，中途邮筒要是因为下面换了内容
/// 变大变小，投信口就对不上了。
struct PostBoxPage<Bottom: View>: View {
    let mailboxImageName: String
    let palette: LetterPalette
    let status: Text
    let posting: PostingRun?
    /// 托起来时信封里装的是什么（那叠日记的样子、收件人、火漆）：推的途中就开始装信封，要先知道
    let liftPreview: PostingRun
    /// 这会儿能寄（有勾上的日记、邮票够、没在投）：能寄时下面那叠信才拿得起来
    let canPost: Bool
    /// 那叠信里的日记多到要在纸里滚动：这时往上划先是翻纸，手指划出纸的上沿才算把信拿起来
    let pileScrolls: Bool
    /// 点了一下邮筒：戳
    let onPoke: () -> Void
    /// 寄：投信动画从时间轴的哪一刻接着放（推着寄的是推到的那一刻；读屏点邮筒是 0）
    let onPost: (Double) -> Void
    /// 投信口在屏幕上的位置（全局坐标）：新手指引「往上推进邮筒」的箭头要一路指到这里
    var onSlotFrame: (CGRect) -> Void = { _ in }
    @ViewBuilder let bottom: Bottom

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mailboxFrame: CGRect = .zero
    @State private var bottomFrame: CGRect = .zero
    /// 手里托着的那叠信（往投信口推的途中）
    @State private var lift: PileLift?
    /// 这一封的投信动画从哪接着放：寄出时信在的地方（读屏寄的没有，就是原位）
    @State private var flightStart: CGRect?
    /// 这一封的封舌合上时绕哪一头转（见 `flapSide`）
    @State private var flightPivot: HorizontalEdge = .leading
    /// 每加一次，邮筒弹回正面
    @State private var frontRequest = 0
    @State private var liftFeel = LetterLiftFeel()

    private typealias T = LetterPostingTimeline

    static var space: String { "postbox" }

    /// 投信口的开口在邮筒图上的位置（按图的宽高取比例）。四个主题的邮筒是同一张线稿，位置一样
    static var slotInImage: CGRect { CGRect(x: 0.317, y: 0.19, width: 0.367, height: 0.024) }

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 14) {
            MailboxStage(
                imageName: mailboxImageName,
                isLocked: posting != nil || lift?.lifted == true,
                frontRequest: frontRequest,
                space: Self.space,
                onFrame: { mailboxFrame = $0 },
                onPoke: onPoke
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(canPost ? Text("寄出日记") : Text("邮筒"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard canPost else { return onPoke() }
                flightPivot = flapSide(of: bottomFrame.midX)
                onPost(0)
            }

            status
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 40)
                .padding(.horizontal, 32)
                .animation(.easeInOut(duration: 0.25), value: posting == nil)

            // 🔴 外面必须垫一层 `Color.clear`：下面空着的时候 `bottom` 是 EmptyView，
            // 加在 EmptyView 上的 frame 会被整个丢掉，邮筒就变大了 —— 一寄出又缩回去
            ZStack { Color.clear; bottom }
                .frame(maxWidth: .infinity)
                .frame(height: OutgoingPile.height)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { bottomFrame = $0 }
                .scrollDisabled(lift?.lifted == true)
                // 托起来以后，这叠信交给上面的投信动画画（跟着手、装信封）；这里先藏着
                .opacity(lift?.lifted == true ? 0 : 1)
                .simultaneousGesture(pileGesture, including: canPost ? .all : .subviews)
                .padding(.horizontal, 28)
                // 投信时下面这块先藏着（那叠日记正被收进信封），信进了邮筒才把邮戳盖出来
                .modifier(PostingReveal(t: posting?.t))
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
        .coordinateSpace(.named(Self.space))
        .overlay {
            if let posting {
                flight(posting, t: posting.t, from: flightStart ?? bottomFrame, pivot: flightPivot)
            } else if let lift, lift.lifted {
                let frame = visualFrame(of: lift)
                flight(liftPreview, t: Self.scrubTime(lift.progress), from: frame,
                       pivot: lift.flapPivot ?? flapSide(of: frame.midX))
            }
        }
        .overlay {
            // 先量再摆：量在 `.position` 后面的话，量到的是整块区域而不是投信口
            Color.clear
                .frame(width: max(slotFrame.width, 1), height: max(slotFrame.height, 1))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onSlotFrame($0) }
                .position(x: slotFrame.midX, y: slotFrame.midY)
                .allowsHitTesting(false)
        }
        .onChange(of: posting == nil) { _, done in if done { flightStart = nil } }
        .onAppear { liftFeel.prepare() }
        .onDisappear {
            liftFeel.stop()
            lift = nil
        }
    }

    private func flight(_ run: PostingRun, t: Double, from frame: CGRect, pivot: HorizontalEdge) -> some View {
        LetterPostingFlight(
            palette: palette,
            sealMark: run.sealMark,
            hasSeal: run.hasSeal,
            pileFrame: frame,
            pileSize: bottomFrame.size,
            // 抬头的「⊕」也画上（传个空动作，不可点）：和原来那一叠一模一样，接手那一下不跳
            pile: OutgoingPile(palette: palette, items: run.items,
                               excluded: .constant(run.excluded), recipients: run.recipients,
                               interactive: false, onTapRecipients: {}),
            slot: slotFrame,
            flapPivot: pivot,
            t: t
        )
    }

    /// 封舌合上时绕上沿哪一头转（2026-10-21 产品定）：以邮筒中轴为界，信封在左边就绕左头转 —— 右边先落下；在右边反过来
    private func flapSide(of envelopeMidX: CGFloat) -> HorizontalEdge {
        envelopeMidX <= mailboxFrame.midX ? .leading : .trailing
    }

    private var slotFrame: CGRect {
        let s = Self.slotInImage
        return CGRect(
            x: mailboxFrame.minX + s.minX * mailboxFrame.width,
            y: mailboxFrame.minY + s.minY * mailboxFrame.height,
            width: s.width * mailboxFrame.width,
            height: s.height * mailboxFrame.height
        )
    }

    // MARK: - 推着装信封、推进投信口

    /// 推到这条线（邮筒半腰）封舌正好合上；再往上、或者在这儿松手，就寄
    private var zoneLine: CGFloat { mailboxFrame.minY + mailboxFrame.height * 0.5 }

    /// 推到哪 → 投信时间轴走到哪：0 = 那叠日记还摊着，1（推到邮筒半腰）= 封舌合上
    private static func scrubTime(_ progress: CGFloat) -> Double {
        T.flapClose.upperBound * Double(min(max(progress, 0), 1))
    }

    /// 托着的那叠信此刻在屏幕上哪儿：跟着手指（捏住的那一点一直在手指下面），越往上越小，像拿着往远处的投信口送。
    /// 信封要在投信口下面成形（投信口以上的部分算进去了、看不见）：推得太高就停在投信口下面
    private func visualFrame(of lift: PileLift) -> CGRect {
        let scale = 1 - 0.5 * lift.progress
        let r = lift.rest
        let grip = CGPoint(x: r.minX + lift.grip.x * r.width, y: r.minY + lift.grip.y * r.height)
        var frame = CGRect(
            x: grip.x + (r.minX - grip.x) * scale + lift.translation.width,
            y: grip.y + (r.minY - grip.y) * scale + lift.translation.height,
            width: r.width * scale,
            height: r.height * scale
        )
        let envelopeHeight = min(frame.width * 0.6, 220) / SealedEnvelope.aspect
        let lowest = slotFrame.maxY + envelopeHeight + 12
        if frame.maxY < lowest { frame.origin.y += lowest - frame.maxY }
        return frame
    }

    private var pileGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard canPost, posting == nil, lift?.returning != true else { return }
                if lift == nil {
                    lift = PileLift(start: value.startLocation, rest: bottomFrame, grip: Self.grip(value.startLocation, in: bottomFrame))
                }
                guard var current = lift else { return }
                if !current.lifted {
                    let up = -value.translation.height
                    // 纸里滚得动：手指先在翻纸，划出纸的上沿才算拿起来 —— 这时改捏信纸的上沿，信从这儿接上手指，不跳
                    let leftSheet = value.location.y < current.rest.minY - 4
                    guard up > 10, up > abs(value.translation.width), !pileScrolls || leftSheet else { return }
                    if pileScrolls {
                        current = PileLift(start: value.location, rest: current.rest,
                                           grip: UnitPoint(x: Self.grip(value.location, in: current.rest).x, y: 0))
                    }
                    current.lifted = true
                    frontRequest += 1
                    liftFeel.begin()
                }
                let before = Self.scrubTime(current.progress)
                current.progress = min(max((current.start.y - value.location.y) / max(current.start.y - zoneLine, 1), 0), 1)
                current.translation = CGSize(width: value.location.x - current.start.x, height: value.location.y - current.start.y)
                let now = Self.scrubTime(current.progress)
                // 封舌开始合的那一刻定下绕哪头转，合的途中手指过了中轴也不换（换了封舌会跳）；推回去封舌全开了再重新定
                if now > T.flapClose.lowerBound {
                    if current.flapPivot == nil { current.flapPivot = flapSide(of: visualFrame(of: current).midX) }
                } else {
                    current.flapPivot = nil
                }
                milestones(&current, from: before, to: now)
                lift = current
                liftFeel.update(progress: current.progress, velocity: value.velocity)
                // 信封合上了还往上推，推到投信口：直接寄，不用等松手
                if current.progress >= 1, value.location.y <= slotFrame.maxY + 24 {
                    post(from: current)
                }
            }
            .onEnded { value in
                guard let current = lift, !current.returning else { return }
                guard current.lifted else {
                    lift = nil
                    return
                }
                // 往投信口一甩：还没合上，但照这个速度推得到
                let predicted = (current.start.y - value.predictedEndLocation.y) / max(current.start.y - zoneLine, 1)
                let flicked = value.velocity.height < -900 && current.progress > 0.3 && predicted >= 1
                if current.progress >= 1 || flicked {
                    post(from: current)
                } else {
                    // 没推到：信封展开、信纸抽出来、那叠日记摊回去，落回原位
                    liftFeel.end(posted: false)
                    var back = current
                    back.returning = true
                    back.progress = 0
                    back.translation = .zero
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.4)) {
                        lift = back
                    } completion: {
                        lift = nil
                    }
                }
            }
    }

    /// 推的途中：信纸装到底、封舌合上 / 又翻开，各有一下手感（来回晃不连响）
    private func milestones(_ lift: inout PileLift, from before: Double, to after: Double) {
        let tucked = T.slideIn.upperBound - 0.03
        if !lift.tucked, after >= tucked {
            lift.tucked = true
            liftFeel.tucked()
        } else if lift.tucked, after < tucked - 0.05 {
            lift.tucked = false
        }
        let closed = T.flapClose.upperBound
        if !lift.closed, after >= closed {
            lift.closed = true
            liftFeel.flapClosed()
        } else if lift.closed, after < closed - 0.06 {
            lift.closed = false
            liftFeel.flapReopened()
        }
    }

    /// 寄：投信动画从信此刻装到的那一刻、此刻在的地方接着放
    private func post(from current: PileLift) {
        let frame = visualFrame(of: current)
        flightStart = frame
        flightPivot = current.flapPivot ?? flapSide(of: frame.midX)
        liftFeel.end(posted: true)
        // 托着的信直接交给投信动画接着放，不要缩回原位的动画
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { lift = nil }
        onPost(Self.scrubTime(current.progress))
    }

    /// 一点在那叠信上的相对位置（0…1）
    private static func grip(_ point: CGPoint, in frame: CGRect) -> UnitPoint {
        UnitPoint(x: (point.x - frame.minX) / max(frame.width, 1), y: (point.y - frame.minY) / max(frame.height, 1))
    }
}

/// 手里托着的那叠信
private struct PileLift {
    /// 手指按下的位置（`PostBoxPage.space` 坐标）；纸里滚动时是划出纸面的那一点
    let start: CGPoint
    /// 那叠信原来的位置
    let rest: CGRect
    /// 手指捏在信的哪儿（0…1，按信的宽高）
    let grip: UnitPoint
    /// 拿起来了没有：往上推了一点 / 手指划出了纸面
    var lifted = false
    /// 手指从 `start` 到现在挪了多少（信跟着挪这么多）
    var translation: CGSize = .zero
    /// 0 = 原位，1 = 推到邮筒半腰（封舌合上）
    var progress: CGFloat = 0
    /// 信纸装到底了 / 封舌合上了（推的途中各响一下用）
    var tucked = false
    var closed = false
    /// 封舌开始合时定下的绕哪头转；封舌还全开着时是 nil
    var flapPivot: HorizontalEdge?
    /// 没推到松手，正在落回原位
    var returning = false
}

/// 投信时下面那块：信进了邮筒才淡出来，邮戳像刚盖上去一样略大一点落定（不回弹）
private struct PostingReveal: ViewModifier, Animatable {
    var t: Double?

    var animatableData: Double {
        get { t ?? LetterPostingTimeline.total }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let reveal = t.map { LetterPostingTimeline.smooth($0, LetterPostingTimeline.flapFall.lowerBound...LetterPostingTimeline.total) } ?? 1
        content
            .opacity(reveal)
            .scaleEffect(1 + 0.05 * (1 - reveal))
    }
}
