import SwiftUI

/// 正在投的这一封：投信动画要用的全部东西（值快照，点下邮筒那一刻定下）
struct PostingRun: Equatable {
    /// 那叠日记收拢之前的样子
    let items: [OutgoingItem]
    let excluded: Set<UUID>
    /// 会员才盖火漆，印面是自己昵称的首字
    let hasSeal: Bool
    let sealMark: String?
    /// 从点下邮筒算起过了几秒，0 → `LetterPostingTimeline.total`
    var t: Double = 0
}

/// 邮筒页的版式：上面一个邮筒（本身就是按钮），下面一行状态，再下面一块固定高度的地方
/// 放「要寄的日记」/ 邮戳和在路上 / 退回来的信。
///
/// 下面那块**高度固定**：投信动画要从那叠日记飞到投信口，中途邮筒要是因为下面换了内容
/// 变大变小，投信口就对不上了。
struct PostBoxPage<Bottom: View>: View {
    let mailboxImageName: String
    let palette: LetterPalette
    let status: Text
    let posting: PostingRun?
    let onTapMailbox: () -> Void
    @ViewBuilder let bottom: Bottom

    @Environment(ThemeManager.self) private var themeManager

    @State private var mailboxFrame: CGRect = .zero
    @State private var bottomFrame: CGRect = .zero

    private static var space: String { "postbox" }

    /// 投信口的开口在邮筒图上的位置（按图的宽高取比例）。三个主题的邮筒是同一张线稿，位置一样
    static var slotInImage: CGRect { CGRect(x: 0.317, y: 0.19, width: 0.367, height: 0.024) }

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 14) {
            Button(action: onTapMailbox) {
                Image(mailboxImageName)
                    .resizable()
                    .scaledToFit()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { mailboxFrame = $0 }
                    .padding(.horizontal, 40)
            }
            // 🔴 不用系统按钮样式：按下去会整个调淡，邮筒是个铁家伙，按了不该变色
            .buttonStyle(StillButtonStyle())
            .frame(maxHeight: .infinity)
            .accessibilityLabel(Text("寄出日记"))

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
                .padding(.horizontal, 28)
                // 投信时下面这块先藏着（那叠日记正被收进信封），信进了邮筒才把邮戳盖出来
                .modifier(PostingReveal(t: posting?.t))
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
        .coordinateSpace(.named(Self.space))
        .overlay {
            if let posting {
                LetterPostingFlight(
                    palette: palette,
                    sealMark: posting.sealMark,
                    hasSeal: posting.hasSeal,
                    pileFrame: bottomFrame,
                    pile: OutgoingPile(palette: palette, items: posting.items,
                                       excluded: .constant(posting.excluded), interactive: false),
                    slot: slotFrame,
                    t: posting.t
                )
            }
        }
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

/// 什么样子都不变的按钮
private struct StillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
    }
}
