import SwiftUI

/// 每周领邮票的小卡片（2026-10-27，用户定：集邮册、快递封推后之前，先用一个小弹窗让用户「领取」这周的邮票）。
///
/// 进邮筒页时，新的一包到了、邮票夹又没满，就浮出这张卡片：三张叠着的齿孔邮票 +「这周的邮票到了」+「领取」。
/// 点领取 →「+20 / 放进邮票夹了」停一下再淡出；点「稍后」先收起，下次进邮筒页再出来。
///
/// 这只是个「收到了」的小仪式：寄信时服务端本来就会把到期的那一包补领上（`claimIfDue`），
/// 用户不点也不会寄不出去。所以卡片上不写「必须领取」之类的话，「稍后」随时能关
struct StampPackCard: View {
    enum Phase: Equatable {
        case ready
        case claiming
        /// 领到了几张
        case claimed(Int)
    }

    let phase: Phase
    let theme: any AppTheme
    /// 邮票的墨色和纸色：跟邮戳、信纸同一套（`Postmark` / `LetterPalette`）
    let ink: Color
    let paper: Color
    let onClaim: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            stampStack
                .padding(.bottom, 18)

            // 两段文字不交叉淡变（叠在一起会糊）：旧的先淡出，新的稍后再淡入
            if case .claimed(let added) = phase {
                VStack(spacing: 4) {
                    // 数字不查翻译表：各语言都是「+20」
                    Text(verbatim: "+\(added)")
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.textPrimary)
                        .monospacedDigit()
                    Text("放进邮票夹了")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
                .transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.25).delay(0.15)),
                                        removal: .opacity.animation(.easeOut(duration: 0.15))))
            } else {
                VStack(spacing: 0) {
                Text("这周的邮票到了")
                    .font(theme.headingFont)
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("寄信时，一封贴一张")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                Button(action: onClaim) {
                    ZStack {
                        Text("领取").opacity(phase == .claiming ? 0 : 1)
                        if phase == .claiming {
                            ProgressView().tint(theme.background)
                        }
                    }
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(theme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(phase == .claiming)
                .padding(.top, 22)

                Button(action: onLater) {
                    Text("稍后")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .disabled(phase == .claiming)
                .padding(.top, 4)
                }
                .transition(.asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.15))))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, phase.isClaimed ? 26 : 12)
        .frame(width: 270)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }

    /// 三张叠着的邮票，像刚从邮局拿回来的一小叠。领到以后收拢成一摞
    private var stampStack: some View {
        let spread: CGFloat = phase.isClaimed ? 0.25 : 1
        return ZStack {
            stamp.rotationEffect(.degrees(-9 * spread)).offset(x: -26 * spread, y: 4 * spread)
            stamp.rotationEffect(.degrees(7 * spread)).offset(x: 26 * spread, y: 3 * spread)
            stamp
        }
        .frame(height: 64)
        .animation(.easeInOut(duration: 0.45), value: phase.isClaimed)
    }

    private var stamp: some View {
        MarkStamp(ink: ink, paper: paper)
    }
}

/// 尺素自己的邮票：齿孔边 + 内框，票面是手写的 m.（桌面图标同一笔）。**不印字**（用户定）。
/// 齿孔和内框的画法同名片上的 `StampPlaceholder`。领邮票的卡片上是 44 宽；笔友地图右上角的邮票数用小号的同一张
struct MarkStamp: View {
    let ink: Color
    let paper: Color
    var width: CGFloat = 44

    var body: some View {
        // 线宽、齿孔间距、内框留白都跟着宽度一起缩，小号的才不会糊成一团
        let k = width / 44
        ZStack {
            Rectangle()
                .fill(paper)
            Rectangle()
                .strokeBorder(ink.opacity(0.55), style: StrokeStyle(lineWidth: 2.2 * k, dash: [0.1, 4.2 * k]))
                .padding(1 * k)
            Rectangle()
                .strokeBorder(ink.opacity(0.4), lineWidth: max(0.5, 0.8 * k))
                .padding(6 * k)
            HandwritingView(ink: ink.opacity(0.85), start: .distantPast, animated: false)
                .frame(width: 24 * k)
        }
        .frame(width: width, height: width * 52 / 44)
        .shadow(color: .black.opacity(0.1), radius: 1 * k, x: 0, y: 0.5 * k)
        .accessibilityHidden(true)
    }
}

private extension StampPackCard.Phase {
    var isClaimed: Bool {
        if case .claimed = self { return true }
        return false
    }
}
